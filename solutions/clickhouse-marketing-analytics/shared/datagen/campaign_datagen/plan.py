"""Pre-planned funnel conversions and multi-touch journeys.

Planned ahead of the daily loop because journey touches land 1-14 days BEFORE
their conversion; forward day-by-day generation can then just merge in each
day's slice. Compact dtypes: the whole 90-day plan for a 100M-row dataset is
~20M rows of ints, a few hundred MB.

Attribution divergence is engineered here: journey (early) touches are sampled
from upper-funnel channels (social, paid_search), while the converting
campaign is biased to lower-funnel channels (direct, email, organic) — so
first-touch vs last-touch attribution differ well beyond the 15% gate.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date

import numpy as np

from .catalog import CHANNELS, Catalog
from .events import CLICK, LEAD, PAGE_VIEW, PURCHASE, TRIAL, diurnal_frac
from .population import Population

_UPPER_FUNNEL_W = np.array([0.34, 0.40, 0.06, 0.14, 0.06])  # journey touches
_SEC_PER_STEP = 45 / 86_400  # ordering gap between events in one session


@dataclass
class Plan:
    """Row-per-event, sorted by day. Slice per day with `for_day`."""
    day: np.ndarray        # (m,) int32 day-ordinal
    user: np.ndarray       # (m,) uint32
    campaign: np.ndarray   # (m,) int16
    etype: np.ndarray      # (m,) uint8
    frac: np.ndarray       # (m,) float32 fraction-of-day (WIB)
    value: np.ndarray      # (m,) float32, NaN except purchases
    sess: np.ndarray       # (m,) uint32 distinct-session tag

    def for_day(self, day_ord: int):
        lo = np.searchsorted(self.day, day_ord, "left")
        hi = np.searchsorted(self.day, day_ord, "right")
        return slice(lo, hi)


def _pick_campaigns(cat: Catalog, rng, channel: np.ndarray, day: np.ndarray) -> np.ndarray:
    """Vectorized-ish campaign choice grouped by (channel, day)."""
    out = np.zeros(len(channel), dtype=np.int16)
    order = np.lexsort((day, channel))
    ch_s, day_s = channel[order], day[order]
    boundaries = np.flatnonzero(np.diff(ch_s) | np.diff(day_s)) + 1
    for grp in np.split(np.arange(len(order)), boundaries):
        idx, w = cat.campaigns_for(int(ch_s[grp[0]]), int(day_s[grp[0]]))
        out[order[grp]] = idx[rng.choice(len(idx), size=len(grp), p=w)].astype(np.int16)
    return out


def build_plan(cfg, pop: Population, cat: Catalog, rng: np.random.Generator,
               start: date, end: date, total_rows_target: int) -> Plan:
    start_ord, end_ord = start.toordinal(), end.toordinal()
    horizon = end_ord - start_ord + 1

    mix = cfg.targets.event_mix
    n_leads = int(total_rows_target * mix.lead)
    n_trials = int(total_rows_target * mix.trial_start)
    n_purch = int(total_rows_target * mix.purchase)

    # --- leads ---------------------------------------------------------------
    # Users weighted by engagement; lead day uniform-ish with weekday shape,
    # never before the user's acquisition.
    p_user = pop.engagement / pop.engagement.sum()
    lead_user = rng.choice(pop.n, size=n_leads, p=p_user).astype(np.uint32)
    wd_mult = np.array(cfg.activity.weekday_multipliers)
    day_w = np.array([wd_mult[date.fromordinal(start_ord + d).weekday()] for d in range(horizon)])
    lead_day = (start_ord + rng.choice(horizon, size=n_leads, p=day_w / day_w.sum())).astype(np.int32)
    lead_day = np.maximum(lead_day, np.minimum(pop.acquired_ord[lead_user], end_ord).astype(np.int32))

    # Channel propensity from the per-channel lead rates (organic/direct/email
    # convert better than social — Q6's organic-vs-paid gap comes from here).
    lead_rates = np.array([getattr(cfg.activity.funnel.lead_per_click, c) for c in CHANNELS])
    lead_ch = rng.choice(len(CHANNELS), size=n_leads, p=lead_rates / lead_rates.sum()).astype(np.uint8)
    lead_camp = _pick_campaigns(cat, rng, lead_ch, lead_day)

    # --- trials / purchases are prefixes of the (shuffled) lead set -----------
    order = rng.permutation(n_leads)
    trial_rows = order[:n_trials]
    purch_rows = order[:n_purch]
    trial_day = np.full(n_leads, -1, dtype=np.int32)
    trial_day[trial_rows] = np.minimum(lead_day[trial_rows] + rng.integers(0, 3, size=n_trials), end_ord)
    purch_day = np.full(n_leads, -1, dtype=np.int32)
    purch_day[purch_rows] = np.minimum(trial_day[purch_rows] + rng.integers(0, 4, size=n_purch), end_ord)

    ln_mu = np.log(cfg.purchases.value_median)
    # Cents precision (USD); the old IDR config rounded to the nearest 100.
    purch_value = np.round(np.exp(rng.normal(ln_mu, cfg.purchases.value_sigma, size=n_purch)), 2)

    # --- assemble funnel events: pv + click + lead (+ trial) (+ purchase) -----
    days, users, camps, etypes, fracs, values, sess = [], [], [], [], [], [], []
    sess_counter = 0

    base = diurnal_frac(rng, n_leads).astype(np.float32)
    lead_sess = (np.arange(n_leads) + sess_counter).astype(np.uint32)
    sess_counter += n_leads
    for step, et in enumerate((PAGE_VIEW, CLICK, LEAD)):
        days.append(lead_day); users.append(lead_user); camps.append(lead_camp)
        etypes.append(np.full(n_leads, et, dtype=np.uint8))
        fracs.append(base + np.float32(step * _SEC_PER_STEP))
        values.append(np.full(n_leads, np.nan, dtype=np.float32)); sess.append(lead_sess)

    t_base = diurnal_frac(rng, n_trials).astype(np.float32)
    days.append(trial_day[trial_rows]); users.append(lead_user[trial_rows]); camps.append(lead_camp[trial_rows])
    etypes.append(np.full(n_trials, TRIAL, dtype=np.uint8)); fracs.append(t_base)
    values.append(np.full(n_trials, np.nan, dtype=np.float32))
    sess.append((np.arange(n_trials) + sess_counter).astype(np.uint32)); sess_counter += n_trials

    # Purchase: attributed to a lower-funnel campaign — the LAST touch.
    p_base = diurnal_frac(rng, n_purch).astype(np.float32)
    days.append(purch_day[purch_rows]); users.append(lead_user[purch_rows]); camps.append(lead_camp[purch_rows])
    etypes.append(np.full(n_purch, PURCHASE, dtype=np.uint8)); fracs.append(p_base)
    values.append(purch_value.astype(np.float32))
    sess.append((np.arange(n_purch) + sess_counter).astype(np.uint32)); sess_counter += n_purch

    # --- multi-touch journeys for purchasers ----------------------------------
    j_lo, j_hi = cfg.activity.journey_touches
    w_lo, w_hi = cfg.activity.journey_window_days
    n_touch = rng.integers(j_lo, j_hi + 1, size=n_purch)
    total_t = int(n_touch.sum())
    t_user = np.repeat(lead_user[purch_rows], n_touch)
    t_anchor = np.repeat(purch_day[purch_rows], n_touch)
    t_day = np.maximum(t_anchor - rng.integers(w_lo, w_hi + 1, size=total_t), start_ord).astype(np.int32)
    t_ch = rng.choice(len(CHANNELS), size=total_t, p=_UPPER_FUNNEL_W).astype(np.uint8)
    t_camp = _pick_campaigns(cat, rng, t_ch, t_day)
    t_base = diurnal_frac(rng, total_t).astype(np.float32)
    t_sess = (np.arange(total_t) + sess_counter).astype(np.uint32)
    sess_counter += total_t

    days.append(t_day); users.append(t_user); camps.append(t_camp)
    etypes.append(np.full(total_t, PAGE_VIEW, dtype=np.uint8)); fracs.append(t_base)
    values.append(np.full(total_t, np.nan, dtype=np.float32)); sess.append(t_sess)
    with_click = rng.random(total_t) < 0.55
    days.append(t_day[with_click]); users.append(t_user[with_click]); camps.append(t_camp[with_click])
    etypes.append(np.full(int(with_click.sum()), CLICK, dtype=np.uint8))
    fracs.append(t_base[with_click] + np.float32(_SEC_PER_STEP))
    values.append(np.full(int(with_click.sum()), np.nan, dtype=np.float32)); sess.append(t_sess[with_click])

    day_a = np.concatenate(days); order = np.argsort(day_a, kind="stable")
    return Plan(
        day=day_a[order],
        user=np.concatenate(users)[order],
        campaign=np.concatenate(camps)[order],
        etype=np.concatenate(etypes)[order],
        frac=np.concatenate(fracs)[order],
        value=np.concatenate(values)[order],
        sess=np.concatenate(sess)[order],
    )
