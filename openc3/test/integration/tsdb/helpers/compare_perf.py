# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

"""
Summarize perf_results.jsonl written by python/test_perf_ingest.py.

Prints one table per scenario with a column per run label (median across
repeated runs of that label) and the change relative to the first label.

Usage:
    uv run python ../test/integration/tsdb/helpers/compare_perf.py [results.jsonl] [--labels a,b,c]
"""

import argparse
import json
import os
import statistics
from collections import OrderedDict, defaultdict


DEFAULT_RESULTS = os.path.join(os.path.dirname(__file__), "..", "perf_results.jsonl")

# Metrics to show per scenario, and whether bigger is better
METRICS = {
    "bulk_wide": [("ingest_rows_per_s", True), ("visible_after_s", False), ("end_to_end_rows_per_s", True)],
    "interleaved": [("ingest_rows_per_s", True), ("visible_after_s", False), ("end_to_end_rows_per_s", True)],
    "queries": [
        ("select_star_ms", False),
        ("select_items_ms", False),
        ("sample_by_1s_ms", False),
        ("latest_ms", False),
        ("count_ms", False),
    ],
}
FLUSH_METRICS = [
    ("flush_p50_ms", False),
    ("flush_p95_ms", False),
    ("flush_p99_ms", False),
    ("flush_rows_per_s", True),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results", nargs="?", default=DEFAULT_RESULTS)
    parser.add_argument("--labels", help="Comma separated labels to compare, in order (default: all, in file order)")
    args = parser.parse_args()

    # data[scenario][label][metric] -> [values]
    data = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    labels = OrderedDict()
    with open(args.results) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            result = json.loads(line)
            labels[result["label"]] = True
            for key, value in result.items():
                if isinstance(value, (int, float)):
                    data[result["scenario"]][result["label"]][key].append(value)

    order = args.labels.split(",") if args.labels else list(labels)
    baseline = order[0]
    width = max(14, *(len(label) + 2 for label in order))

    for scenario in sorted(data):
        if scenario.startswith("back_orbit"):
            metrics = METRICS["bulk_wide"]
        else:
            metrics = METRICS.get(scenario, FLUSH_METRICS if scenario.startswith("flush_latency") else [])
        if not metrics:
            continue
        runs = {label: len(next(iter(data[scenario][label].values()), [])) for label in order}
        print(f"\n## {scenario}  (runs: " + ", ".join(f"{label}={runs[label]}" for label in order) + ")")
        print(f"{'metric':<24}" + "".join(f"{label:>{width}}" for label in order))
        for metric, bigger_better in metrics:
            base_values = data[scenario][baseline].get(metric)
            base = statistics.median(base_values) if base_values else None
            row = f"{metric:<24}"
            for label in order:
                values = data[scenario][label].get(metric)
                if not values:
                    row += f"{'-':>{width}}"
                    continue
                value = statistics.median(values)
                cell = f"{value:,.1f}" if value < 1000 else f"{value:,.0f}"
                if label != baseline and base:
                    change = (value - base) / base * 100.0
                    if change == 0:
                        marker = ""
                    else:
                        marker = "+" if (change > 0) == bigger_better else "-"
                    cell += f" ({change:+.0f}%{marker})"
                row += f"{cell:>{width}}"
            print(row)
    print(f"\nChanges are relative to {baseline}; a trailing + means better, - means worse.")


if __name__ == "__main__":
    main()
