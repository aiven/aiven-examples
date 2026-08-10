"""Shared event-type codes, diurnal clock, and column helpers."""

from __future__ import annotations

import numpy as np

EVENT_TYPES = [
    "page_view", "click", "lead", "trial_start", "purchase",
    "email_send", "email_open", "email_click", "unsubscribe", "bounce",
]
PAGE_VIEW, CLICK, LEAD, TRIAL, PURCHASE, E_SEND, E_OPEN, E_CLICK, E_UNSUB, E_BOUNCE = range(10)

# Hourly activity weights (consumer app: commute peaks, lunch, evening).
_DIURNAL = np.array([
    0.3, 0.2, 0.15, 0.1, 0.15, 0.5, 1.2, 2.0, 2.6, 2.4, 2.2, 2.8,
    3.0, 2.4, 2.2, 2.3, 2.6, 3.0, 3.4, 3.6, 3.2, 2.4, 1.4, 0.7,
])
_DIURNAL_P = _DIURNAL / _DIURNAL.sum()


def diurnal_frac(rng: np.random.Generator, size: int) -> np.ndarray:
    """Fraction-of-day (WIB) samples following the diurnal curve."""
    hour = rng.choice(24, size=size, p=_DIURNAL_P)
    return (hour + rng.random(size)) / 24.0


def day_frac_to_ts_ms(day_ord: np.ndarray | int, frac: np.ndarray, tz_offset_hours: int) -> np.ndarray:
    """(day ordinal, WIB fraction-of-day) -> UTC epoch millis (int64)."""
    epoch_day = np.asarray(day_ord, dtype=np.int64) - 719163  # ordinal of 1970-01-01
    ms = (epoch_day * 86_400_000
          + (frac * 86_400_000).astype(np.int64)
          - tz_offset_hours * 3_600_000)
    return ms
