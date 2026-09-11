#!/usr/bin/env python3
"""Baseline regression gate (US7 / T043).

Compares a fresh Google Benchmark JSON run against a recorded baseline.
Fails (exit 1) when a benchmark's median metric regresses by more than 10%.

Usage: compare_baseline.py <baseline.json> <new_run.json>
Metrics: uses items_per_second when present, else real_time (lower is worse).
"""

import json
import statistics
import sys

THRESHOLD = 0.10  # >10% regression blocks (research.md #1)


def load(path):
    with open(path) as f:
        data = json.load(f)
    out = {}
    for b in data.get("benchmarks", []):
        name = b.get("name", "")
        if "aggregate" in name or "error" in b:
            continue
        if "items_per_second" in b:
            out.setdefault(name, {"ips": []})["ips"].append(
                b["items_per_second"])
        elif "real_time" in b:
            out.setdefault(name, {"rt": []})["rt"].append(b["real_time"])
    med = {}
    for name, d in out.items():
        if "ips" in d:
            med[name] = ("items_per_second", statistics.median(d["ips"]))
        else:
            med[name] = ("real_time", statistics.median(d["rt"]))
    return med


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    base, new = load(sys.argv[1]), load(sys.argv[2])
    if not base:
        print("baseline has no comparable benchmarks")
        return 2
    regressions = []
    for name, (metric, base_v) in sorted(base.items()):
        if name not in new:
            continue
        metric2, new_v = new[name]
        if metric2 != metric:
            continue
        if metric == "items_per_second":
            drop = (base_v - new_v) / base_v
            if drop > THRESHOLD:
                regressions.append(
                    "%s: %.1f -> %.1f items/s (-%.1f%%)" %
                    (name, base_v, new_v, drop * 100))
        else:  # real_time: higher is worse
            rise = (new_v - base_v) / base_v
            if rise > THRESHOLD:
                regressions.append(
                    "%s: %.1f -> %.1f ns (+%.1f%%)" %
                    (name, base_v, new_v, rise * 100))
    if regressions:
        print("REGRESSION > %d%%:" % int(THRESHOLD * 100))
        for r in regressions:
            print("  " + r)
        return 1
    print("baseline check: OK (%d benchmarks compared)" % len(base))
    return 0


if __name__ == "__main__":
    sys.exit(main())
