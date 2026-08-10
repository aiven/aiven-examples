"""Monthly Parquet part writer + manifest (NYC-taxi-style layout).

out/campaign_events/month=YYYY-MM/part-NNN.parquet (zstd) + _manifest.json
with per-file row counts, min/max event_time, bytes and sha256 — so every
import can be verified with a count() against the manifest.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import polars as pl

SCHEMA = {
    "event_time": pl.Datetime("ms"),
    "event_type": pl.Utf8,
    "user_id": pl.Utf8,
    "session_id": pl.Utf8,
    "campaign_id": pl.Utf8,
    "channel": pl.Utf8,
    "source": pl.Utf8,
    "medium": pl.Utf8,
    "ad_group": pl.Utf8,
    "keyword": pl.Utf8,
    "landing_page": pl.Utf8,
    "conversion_value": pl.Float64,
    "currency": pl.Utf8,
    "country": pl.Utf8,
    "device_type": pl.Utf8,
    "properties": pl.Utf8,
}


class MonthWriter:
    def __init__(self, root: Path, month: str, rows_per_file: int, compression: str):
        self.dir = root / f"month={month}"
        self.dir.mkdir(parents=True, exist_ok=True)
        self.month = month
        self.rows_per_file = rows_per_file
        self.compression = compression
        self.buffer: list[pl.DataFrame] = []
        self.buffered = 0
        self.part = 0
        self.files: list[dict] = []

    def add(self, df: pl.DataFrame) -> None:
        self.buffer.append(df)
        self.buffered += len(df)
        if self.buffered >= self.rows_per_file:
            self._flush()

    def _flush(self) -> None:
        if not self.buffered:
            return
        df = pl.concat(self.buffer).cast(SCHEMA)
        path = self.dir / f"part-{self.part:03d}.parquet"
        df.write_parquet(path, compression=self.compression, statistics=True)
        digest = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                digest.update(chunk)
        self.files.append({
            "file": path.name,
            "rows": len(df),
            "min_event_time": str(df["event_time"].min()),
            "max_event_time": str(df["event_time"].max()),
            "bytes": path.stat().st_size,
            "sha256": digest.hexdigest(),
        })
        print(f"  wrote {path} ({len(df):,} rows, {path.stat().st_size / 1e6:.1f} MB)")
        self.buffer, self.buffered = [], 0
        self.part += 1

    def close(self) -> dict:
        self._flush()
        manifest = {
            "month": self.month,
            "rows": sum(f["rows"] for f in self.files),
            "bytes": sum(f["bytes"] for f in self.files),
            "files": self.files,
        }
        with open(self.dir / "_manifest.json", "w") as f:
            json.dump(manifest, f, indent=2)
        return manifest


def write_root_manifest(root: Path, months: list[dict]) -> None:
    """Merge per-month manifests into one top-level _manifest.json."""
    existing: dict[str, dict] = {}
    root_manifest = root / "_manifest.json"
    if root_manifest.exists():
        with open(root_manifest) as f:
            existing = {m["month"]: m for m in json.load(f)["months"]}
    for m in months:
        existing[m["month"]] = m
    merged = sorted(existing.values(), key=lambda m: m["month"])
    with open(root_manifest, "w") as f:
        json.dump({
            "table": "campaign_events",
            "rows": sum(m["rows"] for m in merged),
            "months": merged,
        }, f, indent=2)
