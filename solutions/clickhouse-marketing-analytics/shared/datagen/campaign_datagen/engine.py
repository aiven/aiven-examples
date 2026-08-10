"""Day-by-day event generation.

Each day is generated from rng(seed, day_ordinal) + the pre-built plan, so any
day regenerates bit-identically (idempotent current-month catch-up). Email
opens/clicks that land on a later calendar day are carried over in a small
buffer, which is why regeneration warms up a few days before the first
published day.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import date, timedelta

import numpy as np
import polars as pl

from .catalog import CHANNELS, SOCIAL_SOURCES, SOURCE_MEDIUM, Catalog
from .events import (CLICK, E_BOUNCE, E_CLICK, E_OPEN, E_SEND, E_UNSUB,
                     EVENT_TYPES, PAGE_VIEW, day_frac_to_ts_ms, diurnal_frac)
from .plan import Plan
from .population import Population, activity_probability

_STEP_MS = 45_000  # ordering gap between events within a session
_SITE_EVENTS = frozenset({0, 1, 2, 3, 4})
_PAID = CHANNELS.index("paid_search")
_ORGANIC = CHANNELS.index("organic")
_DIRECT = CHANNELS.index("direct")
_EMAIL = CHANNELS.index("email")


@dataclass
class _Lookups:
    """Precomputed numpy lookup tables for string materialization."""
    campaign_ids: np.ndarray      # object, [n_campaigns + 1], last = "" for -1
    channel_names: np.ndarray
    source_by_ch: np.ndarray      # object, None-able
    medium_by_ch: np.ndarray
    ag_flat: np.ndarray           # object, flattened ad_groups
    ag_offset: np.ndarray
    ag_count: np.ndarray
    keywords: np.ndarray          # object
    kw_p: np.ndarray              # zipf-ish winners/losers
    landing_pages: np.ndarray
    lp_p: np.ndarray
    props_mobile: np.ndarray      # object, pre-rendered JSON strings
    props_desktop: np.ndarray
    countries: np.ndarray


def build_lookups(cfg, cat: Catalog, pop: Population, rng: np.random.Generator) -> _Lookups:
    camp = np.array(cat.campaign_ids + [""], dtype=object)
    ag_offset = np.zeros(cat.n, dtype=np.int64)
    ag_flat = []
    for i, groups in enumerate(cat.ad_groups):
        ag_offset[i] = len(ag_flat)
        ag_flat.extend(groups)
    ag_count = np.array([len(g) for g in cat.ad_groups], dtype=np.int64)

    def zipf(k: int, a: float) -> np.ndarray:
        w = 1.0 / np.arange(1, k + 1) ** a
        w = rng.permutation(w)
        return w / w.sum()

    def props(mobile: bool) -> np.ndarray:
        pool = []
        for _ in range(300 if mobile else 100):
            os_v = (f"Android {rng.choice([12, 13, 14, 15])}" if mobile and rng.random() < 0.8
                    else f"iOS {rng.choice([16, 17, 18])}" if mobile
                    else f"{rng.choice(['macOS 15', 'Windows 11', 'Windows 10'])}")
            pool.append(json.dumps({
                "app_version": str(rng.choice(cfg.properties.app_versions)),
                "os_version": os_v,
                "screen": str(rng.choice(["home", "shop", "deals", "rewards", "promo", "history"])),
                "ab_variant": str(rng.choice(cfg.properties.ab_variants)),
            }, separators=(",", ":")))
        return np.array(pool, dtype=object)

    return _Lookups(
        campaign_ids=camp,
        channel_names=np.array(CHANNELS, dtype=object),
        source_by_ch=np.array([SOURCE_MEDIUM[c][0] for c in CHANNELS], dtype=object),
        medium_by_ch=np.array([SOURCE_MEDIUM[c][1] for c in CHANNELS], dtype=object),
        ag_flat=np.array(ag_flat, dtype=object), ag_offset=ag_offset, ag_count=ag_count,
        keywords=np.array(cat.keywords, dtype=object), kw_p=zipf(len(cat.keywords), 1.1),
        landing_pages=np.array(cat.landing_pages, dtype=object), lp_p=zipf(len(cat.landing_pages), 0.9),
        props_mobile=props(True), props_desktop=props(False),
        countries=np.array(pop.countries, dtype=object),
    )


class _Cols:
    """Column accumulator for one day (compact numpy representation)."""

    def __init__(self):
        self.parts: list[dict[str, np.ndarray]] = []

    def add(self, ts_ms, etype, user, camp, chan, skind, snum, value=None):
        m = len(ts_ms)
        self.parts.append({
            "ts_ms": ts_ms.astype(np.int64),
            "etype": np.broadcast_to(etype, (m,)).astype(np.uint8) if np.isscalar(etype) else etype.astype(np.uint8),
            "user": user.astype(np.uint32),
            "camp": np.broadcast_to(camp, (m,)).astype(np.int16) if np.isscalar(camp) else camp.astype(np.int16),
            "chan": np.broadcast_to(chan, (m,)).astype(np.uint8) if np.isscalar(chan) else chan.astype(np.uint8),
            "skind": np.broadcast_to(skind, (m,)).astype(np.uint8),
            "snum": snum.astype(np.uint32),
            "value": (np.full(m, np.nan, dtype=np.float32) if value is None else value.astype(np.float32)),
        })

    def concat(self) -> dict[str, np.ndarray] | None:
        if not self.parts:
            return None
        return {k: np.concatenate([p[k] for p in self.parts]) for k in self.parts[0]}


def _organic_day(cfg, pop: Population, cat: Catalog, rng, day_ord: int, cols: _Cols) -> None:
    p = activity_probability(pop, cfg, day_ord)
    active = np.flatnonzero(rng.random(pop.n) < p)
    if len(active) == 0:
        return
    s_lo, s_hi = cfg.activity.sessions_per_active_day
    n_sess_per_user = rng.integers(s_lo, s_hi + 1, size=len(active))
    sess_user = np.repeat(active, n_sess_per_user).astype(np.uint32)
    n_sess = len(sess_user)

    use_secondary = rng.random(n_sess) < 0.3
    sess_chan = np.where(use_secondary, pop.secondary_channel[sess_user],
                         pop.primary_channel[sess_user]).astype(np.uint8)

    # organic/direct sessions carry no campaign; paid/social/email pick a live one
    sess_camp = np.full(n_sess, -1, dtype=np.int16)
    for ch in (_PAID, CHANNELS.index("social"), _EMAIL):
        m = np.flatnonzero(sess_chan == ch)
        if len(m):
            idx, w = cat.campaigns_for(ch, day_ord)
            sess_camp[m] = idx[rng.choice(len(idx), size=len(m), p=w)].astype(np.int16)

    pv_lo, pv_hi = cfg.activity.page_views_per_session
    n_pv = rng.integers(pv_lo, pv_hi + 1, size=n_sess)
    n_click = rng.binomial(n_pv, cfg.activity.funnel.click_per_page_view)
    base_frac = diurnal_frac(rng, n_sess).astype(np.float32)
    base_ms = day_frac_to_ts_ms(day_ord, base_frac, cfg.output.timezone_offset_hours)
    snum = np.arange(n_sess, dtype=np.uint32)

    for counts, etype, off0 in ((n_pv, PAGE_VIEW, 0), (n_click, CLICK, 1)):
        total = int(counts.sum())
        if total == 0:
            continue
        rep = np.repeat(np.arange(n_sess), counts)
        step = np.arange(total) - np.repeat(np.cumsum(counts) - counts, counts)  # 0..k-1 per session
        ts = base_ms[rep] + (step * 2 + off0) * _STEP_MS
        cols.add(ts, etype, sess_user[rep], sess_camp[rep], sess_chan[rep], 0, snum[rep])


def _plan_day(cfg, plan: Plan, cat: Catalog, day_ord: int, cols: _Cols) -> None:
    sl = plan.for_day(day_ord)
    if sl.start == sl.stop:
        return
    camp = plan.campaign[sl]
    ts = day_frac_to_ts_ms(day_ord, plan.frac[sl], cfg.output.timezone_offset_hours)
    cols.add(ts, plan.etype[sl], plan.user[sl], camp, cat.channel_idx[camp], 1,
             plan.sess[sl], plan.value[sl])


def _email_day(cfg, pop: Population, cat: Catalog, rng, day_ord: int,
               cols: _Cols, carryover: dict[int, _Cols]) -> None:
    lo = np.searchsorted(cat.send_day, day_ord, "left")
    hi = np.searchsorted(cat.send_day, day_ord, "right")
    tz = cfg.output.timezone_offset_hours
    for s in range(lo, hi):
        ci = int(cat.send_campaign[s])
        n = int(cat.send_audience[s])
        aud = rng.choice(pop.n, size=n, replace=False).astype(np.uint32)
        send_frac = (cat.send_hour[s] + rng.random(n) * 0.5) / 24.0
        send_ms = day_frac_to_ts_ms(day_ord, send_frac.astype(np.float32), tz)
        snum = np.full(n, s % (2**31), dtype=np.uint32)
        cols.add(send_ms, E_SEND, aud, ci, _EMAIL, 2, snum)

        bounce = rng.random(n) < cat.send_bounce_rate[s]
        b = np.flatnonzero(bounce)
        if len(b):
            cols.add(send_ms[b] + rng.integers(2_000, 30_000, size=len(b)), E_BOUNCE,
                     aud[b], ci, _EMAIL, 2, snum[b])

        can_open = np.flatnonzero(~bounce)
        n_open = int(len(can_open) * cfg.email.open_rate)
        opened = rng.choice(can_open, size=n_open, replace=False)
        delay_h = np.minimum(rng.exponential(12.0, size=n_open), cfg.email.open_decay_hours)
        open_ms = send_ms[opened] + (delay_h * 3_600_000).astype(np.int64)
        _emit_or_carry(cols, carryover, day_ord, open_ms, E_OPEN, aud[opened], ci, snum[opened])

        n_click = int(n * cfg.email.click_per_send)
        if n_click and n_open:
            ci_rows = rng.choice(n_open, size=min(n_click, n_open), replace=False)
            click_ms = open_ms[ci_rows] + rng.integers(20_000, 600_000, size=len(ci_rows))
            _emit_or_carry(cols, carryover, day_ord, click_ms, E_CLICK, aud[opened][ci_rows], ci, snum[opened][ci_rows])
            # downstream site session from the email click
            n_dpv = rng.integers(1, 5, size=len(ci_rows))
            rep = np.repeat(np.arange(len(ci_rows)), n_dpv)
            step = np.arange(int(n_dpv.sum())) - np.repeat(np.cumsum(n_dpv) - n_dpv, n_dpv)
            dpv_ms = click_ms[rep] + (step + 1) * _STEP_MS
            _emit_or_carry(cols, carryover, day_ord, dpv_ms, PAGE_VIEW,
                           aud[opened][ci_rows][rep], ci, snum[opened][ci_rows][rep], site=True)

        unsub = rng.random(n) < cat.send_unsub_rate[s]
        u = np.flatnonzero(unsub & ~bounce)
        if len(u):
            u_ms = send_ms[u] + rng.integers(600_000, 36_000_000, size=len(u))
            _emit_or_carry(cols, carryover, day_ord, u_ms, E_UNSUB, aud[u], ci, snum[u])


def _emit_or_carry(cols, carryover, day_ord, ts_ms, etype, user, camp, snum, site=False):
    day_of = (ts_ms + 7 * 3_600_000) // 86_400_000 + 719_163  # WIB day-ordinal
    skind = 2
    for d in np.unique(day_of):
        m = day_of == d
        target = cols if d <= day_ord else carryover.setdefault(int(d), _Cols())
        target.add(ts_ms[m], etype, user[m], camp, _EMAIL, skind, snum[m])


def generate_day(cfg, pop, cat, plan, lookups, day_ord: int,
                 carryover: dict[int, _Cols], seed: int) -> pl.DataFrame | None:
    rng = np.random.default_rng([seed, day_ord])
    cols = carryover.pop(day_ord, _Cols())
    _organic_day(cfg, pop, cat, rng, day_ord, cols)
    _plan_day(cfg, plan, cat, day_ord, cols)
    _email_day(cfg, pop, cat, rng, day_ord, cols, carryover)
    data = cols.concat()
    if data is None:
        return None
    return _materialize(cfg, pop, lookups, data, day_ord, rng)


def _materialize(cfg, pop: Population, lk: _Lookups, d: dict[str, np.ndarray],
                 day_ord: int, rng) -> pl.DataFrame:
    m = len(d["ts_ms"])
    order = np.argsort(d["ts_ms"], kind="stable")
    for k in d:
        d[k] = d[k][order]

    etype, chan, camp, user = d["etype"], d["chan"], d["camp"], d["user"]
    site = etype <= 4

    source = lk.source_by_ch[chan]
    is_social = chan == CHANNELS.index("social")
    if is_social.any():
        source = source.copy()
        source[is_social] = np.array(SOCIAL_SOURCES, dtype=object)[
            rng.integers(0, len(SOCIAL_SOURCES), size=int(is_social.sum()))]

    ad_group = np.full(m, None, dtype=object)
    keyword = np.full(m, None, dtype=object)
    paid_rows = np.flatnonzero(site & (chan == _PAID) & (camp >= 0))
    if len(paid_rows):
        c = camp[paid_rows]
        ad_group[paid_rows] = lk.ag_flat[lk.ag_offset[c] + rng.integers(0, 1 << 30, size=len(c)) % lk.ag_count[c]]
        keyword[paid_rows] = lk.keywords[rng.choice(len(lk.keywords), size=len(paid_rows), p=lk.kw_p)]

    landing = np.full(m, None, dtype=object)
    site_rows = np.flatnonzero(site)
    landing[site_rows] = lk.landing_pages[rng.choice(len(lk.landing_pages), size=len(site_rows), p=lk.lp_p)]

    mobile = pop.device_mobile[user]
    props = np.where(mobile,
                     lk.props_mobile[rng.integers(0, len(lk.props_mobile), size=m)],
                     lk.props_desktop[rng.integers(0, len(lk.props_desktop), size=m)])

    value = d["value"].astype(np.float64)
    has_value = ~np.isnan(value)
    currency = np.where(has_value, cfg.purchases.currency, None).astype(object)

    df = pl.DataFrame({
        "event_time": d["ts_ms"],
        "event_type": np.array(EVENT_TYPES, dtype=object)[etype],
        "user": user,
        "skind": d["skind"],
        "snum": d["snum"],
        "campaign_id": lk.campaign_ids[camp],  # -1 wraps to the trailing ""
        "channel": lk.channel_names[chan],
        # None-able columns go through list-Series: an ALL-None numpy object
        # array would otherwise be inferred as polars Object, which can't cast.
        "source": pl.Series("source", source.tolist(), dtype=pl.Utf8),
        "medium": pl.Series("medium", lk.medium_by_ch[chan].tolist(), dtype=pl.Utf8),
        "ad_group": pl.Series("ad_group", ad_group.tolist(), dtype=pl.Utf8),
        "keyword": pl.Series("keyword", keyword.tolist(), dtype=pl.Utf8),
        "landing_page": pl.Series("landing_page", landing.tolist(), dtype=pl.Utf8),
        "conversion_value": value,
        "currency": pl.Series("currency", currency.tolist(), dtype=pl.Utf8),
        "country": lk.countries[pop.country_idx[user]],
        "device_type": np.where(mobile, "mobile", "desktop"),
        "properties": props,
    })
    return df.with_columns(
        pl.col("event_time").cast(pl.Datetime("ms")),
        pl.format("u{}", pl.col("user")).alias("user_id"),
        pl.format("s{}-{}-{}", pl.col("skind"), pl.lit(day_ord), pl.col("snum")).alias("session_id"),
        pl.col("conversion_value").fill_nan(None),
    ).select(
        "event_time", "event_type", "user_id", "session_id", "campaign_id",
        "channel", "source", "medium", "ad_group", "keyword", "landing_page",
        "conversion_value", "currency", "country", "device_type", "properties",
    )


def iter_days(start: date, end: date):
    d = start
    while d <= end:
        yield d.toordinal()
        d += timedelta(days=1)
