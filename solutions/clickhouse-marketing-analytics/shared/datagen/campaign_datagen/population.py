"""User population: acquisition dates (growth + weekly seasonality), power-law
engagement, channel affinity, device/country, cohort retention curve."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date

import numpy as np

from .catalog import CHANNELS


@dataclass
class Population:
    n: int
    acquired_ord: np.ndarray      # (n,) int day-ordinal
    engagement: np.ndarray        # (n,) float, mean ~1, power-law
    primary_channel: np.ndarray   # (n,) uint8
    secondary_channel: np.ndarray # (n,) uint8
    device_mobile: np.ndarray     # (n,) bool
    country_idx: np.ndarray       # (n,) uint8
    countries: list[str]
    retention_by_week: np.ndarray # (w,) float


def build_population(cfg, rng: np.random.Generator, start: date, end: date) -> Population:
    n = cfg.population.users
    start_ord, end_ord = start.toordinal(), end.toordinal()
    horizon = end_ord - start_ord + 1

    # Acquisition: growth trend x weekly seasonality. A chunk of users predate
    # the window (acquired before day 0) so day-1 traffic isn't all brand-new.
    day_idx = np.arange(horizon)
    weekday = (np.array([date.fromordinal(start_ord + int(d)).weekday() for d in day_idx]))
    season = np.where(weekday >= 5, 0.8, 1.0)
    growth = (1.0 + cfg.population.growth_per_day) ** day_idx
    w = season * growth
    pre_existing = rng.random(n) < 0.35
    acq_in_window = start_ord + rng.choice(horizon, size=n, p=w / w.sum())
    acq_before = start_ord - rng.integers(1, 365, size=n)
    acquired = np.where(pre_existing, acq_before, acq_in_window)

    engagement = rng.pareto(2.5, size=n) + 0.25  # mean ~0.9, heavy tail of power users

    ch_w = np.array([0.22, 0.24, 0.16, 0.22, 0.16])  # affinity across CHANNELS
    primary = rng.choice(len(CHANNELS), size=n, p=ch_w).astype(np.uint8)
    shift = rng.integers(1, len(CHANNELS), size=n).astype(np.uint8)
    secondary = ((primary + shift) % len(CHANNELS)).astype(np.uint8)

    device_mobile = rng.random(n) < cfg.population.mobile_share

    countries = list(vars(cfg.population.countries).keys())
    c_w = np.array([getattr(cfg.population.countries, c) for c in countries])
    country_idx = rng.choice(len(countries), size=n, p=c_w / c_w.sum()).astype(np.uint8)

    return Population(
        n=n, acquired_ord=acquired.astype(np.int64), engagement=engagement,
        primary_channel=primary, secondary_channel=secondary,
        device_mobile=device_mobile, country_idx=country_idx, countries=countries,
        retention_by_week=np.array(cfg.population.retention_by_week, dtype=np.float64),
    )


def activity_probability(pop: Population, cfg, day_ord: int) -> np.ndarray:
    """P(user active on day) = base x engagement x cohort retention x weekday."""
    weeks_since = np.clip((day_ord - pop.acquired_ord) // 7, 0, len(pop.retention_by_week) - 1)
    retention = pop.retention_by_week[weeks_since]
    retention = np.where(day_ord < pop.acquired_ord, 0.0, retention)  # not born yet
    weekday_mult = cfg.activity.weekday_multipliers[date.fromordinal(day_ord).weekday()]
    p = cfg.activity.daily_active_base * pop.engagement * retention * weekday_mult
    return np.clip(p, 0.0, 0.95)
