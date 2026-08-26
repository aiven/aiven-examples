#!/usr/bin/env python3
"""q5 equality gate with spill-to-disk on the naive side.

Naive q5 (the self-join cohort query) cannot execute at default settings on
business-16: its join hash table blows the ~10 GiB server memory cap
(MEMORY_LIMIT_EXCEEDED) — that DNF is itself an article finding. For the
correctness gate we still need the comparison, so the naive side runs with
grace_hash + external group-by/sort (identical results, ~3x slower).
Reuses verify_equality's strip/compare verbatim.
"""

import re
import sys
import time
from pathlib import Path

from bench_lib import ClickHouse
from verify_equality import compare

HERE = Path(__file__).parent
SPILL = {"join_algorithm": "grace_hash",
         "grace_hash_join_initial_buckets": 8,
         "max_bytes_before_external_group_by": 2_000_000_000,
         "max_bytes_before_external_sort": 2_000_000_000}
strip = lambda sql: re.sub(r"\bLIMIT\s+\d+\s*;?\s*$", ";", sql.strip(), flags=re.I)

ch = ClickHouse()
naive_sql = strip(next((HERE.parent / "queries" / "naive").glob("q5_*.sql")).read_text())
opt_sql = strip(next((HERE.parent / "queries" / "optimized").glob("q5_*.sql")).read_text())

t0 = time.perf_counter()
naive = ch.json(naive_sql, settings=SPILL, timeout=3600)["data"]
t_naive = time.perf_counter() - t0
opt = ch.json(opt_sql, timeout=3600)["data"]

problems = compare("q5_cohort_retention", naive, opt)
if problems:
    print("q5_cohort_retention: FAIL")
    for p in problems:
        print(f"    {p}")
    sys.exit(1)
print(f"q5_cohort_retention: OK ({len(naive)} rows; naive with external spill "
      f"took {t_naive:.1f}s)")
