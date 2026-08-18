#!/usr/bin/env python3
"""Equality gate: every naive/optimized pair must return identical answers.

Compares result sets row-by-row after canonical sorting. Numeric cells use a
relative tolerance of 1e-6 — partial-sum merging legitimately reorders
floating-point addition, nothing more. Any structural difference (row count,
columns, keys) or numeric drift beyond tolerance fails the gate.

  python3 verify_equality.py            # all pairs
  python3 verify_equality.py q3 q5      # subset
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

from bench_lib import ClickHouse

HERE = Path(__file__).parent
QUERIES = HERE.parent / "queries"
REL_TOL = 1e-6

# Per-query bounded approximations, documented in the query file headers.
# q6: sessions/unique_users are uniqCombined(14) estimates (≤0.5% by design;
# 2% gate ceiling) and rows near the HAVING sessions >= 100 boundary may
# appear on only one side — allowed within the same tolerance of the cut.
OVERRIDES = {
    # q6 compares two DIFFERENT uniq estimators against each other: the naive
    # query's uniq() (~2% at the 10^5-10^6 cardinalities of these cells) vs
    # the rollup's uniqCombined(14) (~0.5%). Their estimates can differ by
    # the sum of both errors — observed ≤3% at 679M rows, matching the
    # customer report's ≤3.5% note; 4% ceiling. abs_tol 0.011 additionally
    # covers one rounding step of the round(x, 2) percentage columns.
    "q6": {"rel_tol": 0.04, "abs_tol": 0.011, "having": ("sessions", 100)},
}


def canon(rows: list[dict]) -> list[tuple]:
    out = []
    for r in rows:
        out.append(tuple((k, r[k]) for k in sorted(r)))
    return sorted(out, key=lambda t: str(t))


def cell_equal(a, b, rel_tol=REL_TOL, abs_tol=1e-9) -> bool:
    if a is None or b is None:
        return a == b
    try:
        fa, fb = float(a), float(b)
        if math.isnan(fa) and math.isnan(fb):
            return True
        return math.isclose(fa, fb, rel_tol=rel_tol, abs_tol=abs_tol)
    except (TypeError, ValueError):
        return a == b


def compare(name: str, naive: list[dict], opt: list[dict]) -> list[str]:
    ov = OVERRIDES.get(name.split("_")[0], {})
    rel_tol = ov.get("rel_tol", REL_TOL)
    abs_tol = ov.get("abs_tol", 1e-9)
    if "having" in ov:
        # Approximate uniqs: pair rows by their DIMENSION key (numeric drift
        # would misalign a value-sorted pairing), tolerate rows that appear
        # on only one side when they sit at the approximate HAVING cut, and
        # fail on any other one-sided row.
        col, cut = ov["having"]
        key = lambda r: tuple(str(v) for k, v in sorted(r.items())
                              if not isinstance(v, (int, float)))
        nk = {key(r): r for r in naive}
        ok = {key(r): r for r in opt}
        for k in nk.keys() ^ ok.keys():
            row = nk.get(k) or ok[k]
            if abs(float(row[col]) - cut) / cut > rel_tol:
                return [f"one-sided row not at the HAVING boundary: {row}"]
        problems = []
        for k in sorted(nk.keys() & ok.keys()):
            for c in nk[k]:
                if not cell_equal(nk[k][c], ok[k].get(c), rel_tol, abs_tol):
                    problems.append(f"key {k} col {c}: {nk[k][c]!r} vs {ok[k].get(c)!r}")
                    if len(problems) >= 5:
                        return problems
        return problems
    problems = []
    if len(naive) != len(opt):
        problems.append(f"row count {len(naive)} vs {len(opt)}")
        return problems
    for i, (rn, ro) in enumerate(zip(canon(naive), canon(opt))):
        kn = [k for k, _ in rn]
        ko = [k for k, _ in ro]
        if kn != ko:
            problems.append(f"row {i}: columns differ {kn} vs {ko}")
            return problems
        for (k, va), (_, vb) in zip(rn, ro):
            if not cell_equal(va, vb, rel_tol, abs_tol):
                problems.append(f"row {i} col {k}: {va!r} vs {vb!r}")
                if len(problems) >= 5:
                    return problems
    return problems


def main() -> None:
    only = set(sys.argv[1:])
    ch = ClickHouse()
    failures = 0
    for f in sorted((QUERIES / "naive").glob("q*.sql")):
        name = f.stem
        if only and not any(name.startswith(o) for o in only):
            continue
        opt_file = QUERIES / "optimized" / f.name
        if not opt_file.exists():
            print(f"{name}: SKIP (no optimized twin)")
            continue
        print(f"{name}: ", end="", flush=True)
        # Compare COMPLETE answer sets: a trailing LIMIT under an ORDER BY
        # with ties (e.g. Q2's revenue_per_session rounded to 2dp) selects a
        # nondeterministic subset — for the naive query itself too — so the
        # gate strips it and compares everything the query would rank.
        strip = lambda sql: re.sub(r"\bLIMIT\s+\d+\s*;?\s*$", ";", sql.strip(), flags=re.I)
        naive = ch.json(strip(f.read_text()))["data"]
        opt = ch.json(strip(opt_file.read_text()))["data"]
        problems = compare(name, naive, opt)
        if problems:
            failures += 1
            print("FAIL")
            for p in problems:
                print(f"    {p}")
        else:
            print(f"OK ({len(naive)} rows)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
