"""Synthetic campaign_events generator.

One simulation engine, two output modes (batch Parquet backfill now; live mode
reuses the same per-day engine). Deterministic per (seed, day): any day can be
regenerated bit-identically, which is what makes the current-month catch-up
idempotent.
"""

__version__ = "0.1.0"
