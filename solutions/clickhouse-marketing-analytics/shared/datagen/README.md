# datagen — synthetic backfill generator

Generates the ≥100M-row `campaign_events` backfill (journey-based, not uniform
noise) as monthly Parquet file-sets, publishes them to a public-read GCS
bucket, and validates the data against its built-in validation gates.

Python + numpy/polars. Deterministic: everything derives from `seed` in
`config.yaml`; each day is generated with `rng([seed, day_ordinal])`, so any
day/month is reproducible in isolation (demo-morning catch-up is idempotent).

## Setup

```sh
python3 -m venv .venv
.venv/bin/pip install -e .
```

## Usage

```sh
# Full 3-month backfill (2026-05..2026-07, ~100M rows, ~10 min)
.venv/bin/campaign-datagen generate

# Regenerate one month only (3 warm-up days are simulated, not written,
# so cross-day email open/click carryover is reproduced exactly)
.venv/bin/campaign-datagen generate --only 2026-06

# Demo-morning month-to-date catch-up (replayed via the Java ingest service)
.venv/bin/campaign-datagen generate --through 2026-08-06

# Check the validation gates: event mix, funnel drop-offs, attribution
# divergence >= 15%, null ratios, email list-health alerts
.venv/bin/campaign-datagen validate

# Publish to GCS (public-read, NYC-taxi style; prints the s3(... NOSIGN) INSERT)
.venv/bin/campaign-datagen upload --bucket <bucket>
```

Output layout: `out/campaign_events/month=YYYY-MM/part-NNN.parquet`
(~5M rows/part, zstd) plus a sha256 `_manifest.json` per month and at the root.

## Smoke test (1/60 scale, runs in seconds)

Scale population, months, row target, and email audience together — email
audiences are absolute numbers, so leaving them unscaled drowns the mix:

```python
import yaml
cfg = yaml.safe_load(open("config.yaml"))
S = 60
cfg["population"]["users"] //= S
cfg["horizon"]["months"] = 1
cfg["horizon"]["plan_extra_months"] = 1
cfg["targets"]["total_rows"] = cfg["targets"]["total_rows"] // S // 3
cfg["email"]["audience_per_send"] = [max(1, v // S) for v in cfg["email"]["audience_per_send"]]
cfg["output"]["dir"] = "out-smoke"
cfg["output"]["rows_per_file"] = 2_000_000
yaml.safe_dump(cfg, open("config-smoke.yaml", "w"), sort_keys=False)
```

Then `campaign-datagen -c config-smoke.yaml generate && campaign-datagen -c config-smoke.yaml validate`.
At smoke scale, one extra email campaign may cross the list-health alert
thresholds from sampling noise (audiences of ~50–250); at full scale only the
3 deliberately-bad segments alert.

## Design notes

- `plan.py` pre-plans all funnel conversions over the whole horizon (journey
  touches land 1–14 days *before* their purchase); the daily loop merges
  `plan.for_day(day)`. `horizon.plan_extra_months` extends the plan past the
  published months so `--through` catch-up never perturbs published data.
- `session_id` encodes provenance: `s0-` organic, `s1-` planned funnel/journey,
  `s2-` email; `validate.py` uses this for the attribution check.
- `targets.event_mix` is authoritative for funnel sizing (`plan.py` reads
  lead/trial_start/purchase); the mix is tuned to be internally consistent
  (opens = 35% of sends, user funnel ~100 → 12 → 6 → 4) rather than copying
  the blog's rough mix, whose 3% leads would flatten the funnel chart.
- Timestamps are UTC with a WIB (+7) diurnal shape, so each `month=` file
  spills ~400 boundary rows into the previous UTC month partition — harmless,
  but don't expect `DROP PARTITION` to align 1:1 with one file-set month.
- Local sanity load into Docker ClickHouse (repo-root `docker-compose.yml`):
  `docker exec -i <container> clickhouse-client --password local -q "INSERT INTO campaign_events FORMAT Parquet" < out/campaign_events/month=2026-05/part-000.parquet`
