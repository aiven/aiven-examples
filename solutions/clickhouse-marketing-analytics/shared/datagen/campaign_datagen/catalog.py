"""Campaign catalog: ~200 campaigns across 5 channels, keywords, landing pages,
budget weights (power-law) and email send schedules."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date

import numpy as np

CHANNELS = ["paid_search", "social", "email", "organic", "direct"]
# source/medium per channel; social source is sampled per event from SOCIAL_SOURCES.
SOURCE_MEDIUM = {
    "paid_search": ("google", "cpc"),
    "social": (None, "paid_social"),
    "email": ("newsletter", "email"),
    "organic": ("google", "organic"),
    "direct": (None, None),
}
SOCIAL_SOURCES = ["facebook", "instagram", "tiktok"]

_ADJ = ["mega", "smart", "instant", "payday", "holiday", "summer", "weekend",
        "flash", "cashback", "loyal", "fresh", "super", "extra", "promo"]
_NOUN = ["bundle", "trial", "sale", "bills", "rewards", "merchant", "deals",
         "points", "referral", "onboard", "reactivate", "upgrade", "festive", "clearance"]

_KEYWORD_POOL = [
    "online deals", "best rewards app", "discount codes", "flash sale today",
    "free shipping", "loyalty points app", "cashback offers", "coupon app",
    "best price finder", "member discounts", "cheap bundles", "compare prices online",
    "gift card deals", "seasonal sale", "promo codes app", "daily deals",
    "shopping rewards", "digital coupons", "exclusive offers", "price drop alerts",
]


@dataclass
class Catalog:
    n: int
    campaign_ids: list[str]
    channel_idx: np.ndarray          # (n,) uint8 into CHANNELS
    budget: np.ndarray               # (n,) float, normalized per channel
    active_from: np.ndarray          # (n,) int day-ordinal
    active_to: np.ndarray            # (n,) int day-ordinal (inclusive)
    ad_groups: list[list[str]]       # per campaign
    keywords: list[str]              # global paid-search pool
    landing_pages: list[str]
    # email sends: one row per scheduled send
    send_campaign: np.ndarray = field(default=None)   # (s,) int campaign index
    send_day: np.ndarray = field(default=None)        # (s,) int day-ordinal
    send_hour: np.ndarray = field(default=None)       # (s,) int hour (local clock)
    send_audience: np.ndarray = field(default=None)   # (s,) int
    send_unsub_rate: np.ndarray = field(default=None)
    send_bounce_rate: np.ndarray = field(default=None)
    segment_of_campaign: np.ndarray = field(default=None)  # (n,) int, -1 if not email

    def campaigns_for(self, channel: int, day_ord: int) -> tuple[np.ndarray, np.ndarray]:
        """Indices + normalized budget weights of campaigns live on `day_ord`."""
        mask = (self.channel_idx == channel) & (self.active_from <= day_ord) & (self.active_to >= day_ord)
        idx = np.flatnonzero(mask)
        w = self.budget[idx]
        if len(idx) == 0:  # fall back to any campaign of the channel
            idx = np.flatnonzero(self.channel_idx == channel)
            w = self.budget[idx]
        return idx, w / w.sum()


def build_catalog(cfg, rng: np.random.Generator, start: date, end: date) -> Catalog:
    n = cfg.catalog.campaigns
    ch_names = list(vars(cfg.catalog.channels).keys())
    ch_weights = np.array([getattr(cfg.catalog.channels, c) for c in ch_names])
    # map config channel order onto canonical CHANNELS indices
    ch_lookup = np.array([CHANNELS.index(c) for c in ch_names], dtype=np.uint8)
    channel_idx = ch_lookup[rng.choice(len(ch_names), size=n, p=ch_weights / ch_weights.sum())]

    campaign_ids = []
    for i in range(n):
        slug = f"{_ADJ[rng.integers(len(_ADJ))]}-{_NOUN[rng.integers(len(_NOUN))]}"
        campaign_ids.append(f"cmp-{i:03d}-{CHANNELS[channel_idx[i]][:4]}-{slug}")

    budget = rng.pareto(1.4, size=n) + 0.15  # power law: few big spenders, long tail

    start_ord, end_ord = start.toordinal(), end.toordinal()
    horizon = end_ord - start_ord + 1
    # ~40% always-on, the rest run bounded flights of 2-8 weeks
    always_on = rng.random(n) < 0.4
    a_from = np.where(always_on, start_ord, start_ord + rng.integers(0, max(1, horizon - 14), size=n))
    length = rng.integers(14, 57, size=n)
    a_to = np.where(always_on, end_ord + 366, np.minimum(a_from + length, end_ord + 366))

    lo, hi = cfg.catalog.ad_groups_per_campaign
    ad_groups = [[f"ag-{i:03d}-{g}" for g in range(rng.integers(lo, hi + 1))] for i in range(n)]

    kw_n = cfg.catalog.keywords
    keywords = [_KEYWORD_POOL[i % len(_KEYWORD_POOL)] + (f" {i // len(_KEYWORD_POOL) + 1}" if i >= len(_KEYWORD_POOL) else "")
                for i in range(kw_n)]
    landing_pages = [f"/lp/{_NOUN[i % len(_NOUN)]}-{i:02d}" for i in range(cfg.catalog.landing_pages)]

    cat = Catalog(n, campaign_ids, channel_idx, budget, a_from, a_to, ad_groups, keywords, landing_pages)
    _schedule_email_sends(cfg, rng, cat, start_ord, end_ord)
    return cat


def _schedule_email_sends(cfg, rng, cat: Catalog, start_ord: int, end_ord: int) -> None:
    email_ch = CHANNELS.index("email")
    email_camps = np.flatnonzero(cat.channel_idx == email_ch)
    seg = np.full(cat.n, -1, dtype=np.int64)
    seg[email_camps] = np.arange(len(email_camps))
    bad = set(rng.choice(len(email_camps), size=min(cfg.catalog.bad_email_segments, len(email_camps)),
                         replace=False).tolist())

    s_lo, s_hi = cfg.catalog.email_sends_per_week
    aud_lo, aud_hi = cfg.email.audience_per_send
    rows = []
    for ci in email_camps:
        is_bad = seg[ci] in bad
        u_lo, u_hi = (cfg.email.bad_segment_unsubscribe_rate if is_bad else cfg.email.unsubscribe_rate)
        b_lo, b_hi = (cfg.email.bad_segment_bounce_rate if is_bad else cfg.email.bounce_rate)
        day = max(cat.active_from[ci], start_ord)
        last = min(cat.active_to[ci], end_ord)
        while day <= last:
            n_sends = rng.integers(s_lo, s_hi + 1)
            offsets = rng.choice(7, size=min(n_sends, 7), replace=False)
            for off in offsets:
                d = day + int(off)
                if d > last:
                    continue
                rows.append((ci, d, int(rng.choice([9, 10, 11, 14, 16, 19])),
                             int(rng.integers(aud_lo, aud_hi + 1)),
                             rng.uniform(u_lo, u_hi), rng.uniform(b_lo, b_hi)))
            day += 7
    rows.sort(key=lambda r: r[1])
    arr = np.array(rows, dtype=np.float64).reshape(-1, 6)
    cat.send_campaign = arr[:, 0].astype(np.int64)
    cat.send_day = arr[:, 1].astype(np.int64)
    cat.send_hour = arr[:, 2].astype(np.int64)
    cat.send_audience = arr[:, 3].astype(np.int64)
    cat.send_unsub_rate = arr[:, 4]
    cat.send_bounce_rate = arr[:, 5]
    cat.segment_of_campaign = seg
