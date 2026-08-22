"""Day-90 live streamer — feeds the Post 1 pipeline at a target rate.

The batch generator writes days 1..89; this replays day 90 ("now" =
horizon.anchor) and, with --days > 1, the plan_extra_days after it, straight
into Valkey Streams with pipelined XADD — the same stream the Post 1 in-app
flusher consumes (XREADGROUP -> native bulk INSERT -> the MVs fire per batch).

Determinism: the same (seed, anchor) population/catalog/plan as the batch
run, so day 90 is a seamless statistical continuation of the history. The
day is generated vectorized, pre-serialized to JSON lines once, then paced
out at --rate events/s. event_time is OMITTED from the payload on purpose:
the ingest service stamps arrival time, so live rows land in the current
partition and every rollup's GROUP BY — that is the live-demo semantic.

Entry format matches ValkeyEventSink: one stream entry per event, single
field "json" = the event exactly as POST /events would carry it (snake_case
EventDto fields).

Backpressure: XLEN is checked periodically; past --max-stream-len the sender
pauses instead of growing Valkey without bound (mirrors the app's 429 rule).
"""

from __future__ import annotations

import json
import time
from datetime import timedelta
from pathlib import Path

import numpy as np

from .catalog import build_catalog
from .engine import build_lookups, generate_day
from .plan import build_plan
from .population import build_population

WARM_UP_DAYS = 3
XLEN_CHECK_EVERY = 20  # pipeline batches between XLEN checks


def _rss_gb() -> float:
    """Peak RSS in GB (ru_maxrss: bytes on macOS, KB on Linux)."""
    import resource
    import sys
    r = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return r / 1e9 if sys.platform == "darwin" else r / 1e6


def _chunks(it, n: int):
    buf = []
    for x in it:
        buf.append(x)
        if len(buf) == n:
            yield buf
            buf = []
    if buf:
        yield buf


def _emit(client, source, rate: int, stream: str,
          pipeline_size: int, max_stream_len: int, forever: bool = False,
          rate_file: str | None = None) -> None:
    """Pace payloads out at `rate`/s via pipelined XADD; loop when forever.

    source: callable returning a fresh iterable of payload bytes per pass —
    a list for the one-shot day path, a spill-file line reader in loop mode
    (holding a full day in RAM OOM-killed 8 GB containers).

    rate_file: path polled every report interval for a new target rate (one
    integer). Lets a sweep harness change the rate at runtime without
    restarting the generator (and re-paying the plan build)."""
    sent = 0
    batch_n = 0
    wall0 = time.perf_counter()
    last_report = wall0
    report_sent = 0
    # Pacing is windowed (reset on rate change) so an old surplus/deficit
    # doesn't distort the new rate.
    win0, win_sent = wall0, 0
    while True:
        for chunk in _chunks(source(), pipeline_size):
            if client is not None:
                pipe = client.pipeline(transaction=False)
                for line in chunk:
                    pipe.xadd(stream, {"json": line})
                pipe.execute()
                batch_n += 1
                if max_stream_len and batch_n % XLEN_CHECK_EVERY == 0:
                    while client.xlen(stream) > max_stream_len:
                        time.sleep(1)
            sent += len(chunk)
            win_sent += len(chunk)
            ahead = win_sent / rate - (time.perf_counter() - win0)
            if ahead > 0:
                time.sleep(ahead)
            now = time.perf_counter()
            if now - last_report >= 5:
                print(f"    {sent:,} sent, {(sent - report_sent) / (now - last_report):,.0f}/s "
                      f"(target {rate:,}/s)", flush=True)
                last_report, report_sent = now, sent
                if rate_file:
                    try:
                        new = int(open(rate_file).read().strip())
                        if new > 0 and new != rate:
                            print(f"    rate change: {rate:,} -> {new:,}/s", flush=True)
                            rate = new
                            win0, win_sent = time.perf_counter(), 0
                    except (OSError, ValueError):
                        pass
        if not forever:
            break


def _day_payloads(df) -> list[bytes]:
    """Serialize one generated day to JSON-line payloads, event_time dropped,
    ordered by event_time so the replay preserves the day's natural order.

    Chunked: one write_ndjson() of a full day is ~GBs, and with the encoded
    copy alive at the same time the peak is 2x the day — enough to OOM-kill
    an 8 GB Aiven Apps container. Slices bound the transient to one chunk."""
    df = df.sort("event_time").drop("event_time")
    out: list[bytes] = []
    for chunk in df.iter_slices(200_000):
        out.extend(line.encode() for line in chunk.write_ndjson().splitlines() if line)
    return out


def stream_live(cfg, anchor_override: str | None, *, rate: int, valkey_url: str,
                stream: str, pipeline_size: int, days: int, max_stream_len: int,
                dry_run: bool, loop: bool = False, rate_file: str | None = None) -> None:
    from .cli import horizon_dates  # local import to avoid a cycle

    start, _batch_end, anchor, plan_end = horizon_dates(cfg, anchor_override)
    last = min(anchor + timedelta(days=days - 1), plan_end)

    client = None
    if not dry_run:
        import redis  # deferred: only needed when actually streaming
        client = redis.Redis.from_url(valkey_url)
        client.ping()

    t0 = time.time()
    rng0 = np.random.default_rng([cfg.seed, 0])
    pop = build_population(cfg, rng0, start, plan_end)
    cat = build_catalog(cfg, rng0, start, plan_end)
    window_days = cfg.horizon.days
    plan_days = (plan_end - start).days + 1
    target = int(cfg.targets.total_rows * plan_days / window_days)
    plan = build_plan(cfg, pop, cat, rng0, start, plan_end, target)
    lookups = build_lookups(cfg, cat, pop, rng0)
    print(f"plan built in {time.time() - t0:.0f}s; streaming {anchor}..{last} "
          f"at {rate:,}/s -> {'(dry run)' if dry_run else stream} "
          f"[peak rss {_rss_gb():.1f}G]", flush=True)

    # Warm up so cross-day email carryover into day 90 is reproduced exactly.
    carryover: dict = {}
    d = anchor - timedelta(days=WARM_UP_DAYS)
    while d < anchor:
        generate_day(cfg, pop, cat, plan, lookups, d.toordinal(), carryover, cfg.seed)
        print(f"  warmup {d} done [peak rss {_rss_gb():.1f}G]", flush=True)
        d += timedelta(days=1)

    if loop:
        # Load-generation mode: build day 90's payloads ONCE, replay them
        # forever at the target rate — no plan-rebuild gaps between passes.
        # Replayed events land as new rows (arrival timestamps), which is the
        # point: sustained insert pressure for the under-load benchmarks.
        # The day is spilled to disk and replayed from there: the serialized
        # day is ~5 GB, and holding it for the whole run OOM-killed 8 GB
        # containers. The page cache keeps the hot rungs fast anyway.
        import tempfile
        df = generate_day(cfg, pop, cat, plan, lookups, anchor.toordinal(), carryover, cfg.seed)
        print(f"  day-90 generated: {len(df):,} rows [peak rss {_rss_gb():.1f}G]", flush=True)
        df = df.sort("event_time").drop("event_time")
        spill = Path(tempfile.gettempdir()) / "livegen-day90.ndjson"
        n = len(df)
        with open(spill, "wb") as f:
            for chunk in df.iter_slices(200_000):
                f.write(chunk.write_ndjson().encode())
        df = None  # replay reads the spill file; free the frame before the long hold
        print(f"  loop mode: replaying {n:,} day-90 events at {rate:,}/s from "
              f"{spill} ({spill.stat().st_size / 1e9:.1f}G) [peak rss {_rss_gb():.1f}G]",
              flush=True)

        def source():
            with open(spill, "rb") as f:
                for line in f:
                    line = line.rstrip(b"\n")
                    if line:
                        yield line

        _emit(client, source, rate, stream, pipeline_size, max_stream_len,
              forever=True, rate_file=rate_file)
        return

    sent_total = 0
    wall0 = time.perf_counter()
    d = anchor
    while d <= last:
        gen0 = time.time()
        df = generate_day(cfg, pop, cat, plan, lookups, d.toordinal(), carryover, cfg.seed)
        if df is None:
            d += timedelta(days=1)
            continue
        payloads = _day_payloads(df)
        print(f"  {d}: {len(payloads):,} events generated+serialized "
              f"in {time.time() - gen0:.1f}s, streaming...")

        batch_n = 0
        last_report = time.perf_counter()
        report_sent = sent_total
        for i in range(0, len(payloads), pipeline_size):
            chunk = payloads[i:i + pipeline_size]
            if client is not None:
                pipe = client.pipeline(transaction=False)
                for line in chunk:
                    pipe.xadd(stream, {"json": line})
                pipe.execute()
                batch_n += 1
                if max_stream_len and batch_n % XLEN_CHECK_EVERY == 0:
                    while client.xlen(stream) > max_stream_len:
                        print("    backpressure: stream over "
                              f"{max_stream_len:,}, pausing 1s")
                        time.sleep(1)
            sent_total += len(chunk)

            # Token-bucket pacing against the global clock.
            ahead = sent_total / rate - (time.perf_counter() - wall0)
            if ahead > 0:
                time.sleep(ahead)

            now = time.perf_counter()
            if now - last_report >= 5:
                inst = (sent_total - report_sent) / (now - last_report)
                print(f"    {sent_total:,} sent, {inst:,.0f}/s over last "
                      f"{now - last_report:.0f}s")
                last_report, report_sent = now, sent_total
        d += timedelta(days=1)

    elapsed = time.perf_counter() - wall0
    print(f"\ndone: {sent_total:,} events in {elapsed:.0f}s "
          f"({sent_total / max(elapsed, 1e-9):,.0f}/s sustained)")
