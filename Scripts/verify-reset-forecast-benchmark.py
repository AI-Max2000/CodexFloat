#!/usr/bin/env python3
"""Independently replay ResetBench's 48h common cases, without executing its code.

Usage: python3 Scripts/verify-reset-forecast-benchmark.py /path/to/benchmark
Input: a checkout of https://github.com/AghDoo/codex-reset-benchmark
Output: a JSON audit to stdout. No network access or source mutation.
"""

import bisect
import json
import math
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys


def instant(value):
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    assert parsed.tzinfo is not None, "Timezone is required"
    return parsed.astimezone(timezone.utc)


def audit(root):
    published = json.loads((root / "docs/generated/leaderboard.json").read_text())
    truth = json.loads((root / "data/events/resets.json").read_text())
    sources = json.loads((root / "data/sources.json").read_text())["sources"]
    reviewed = instant(truth["reviewed_at"])
    cutoff = min(reviewed, instant(published["generated_at"])) - timedelta(hours=48)
    events = [instant(e["occurred_at"]) for e in truth["events"] if e["status"] == "confirmed"]
    snapshots = []
    for path in sorted((root / "data/forecasts").rglob("*.ndjson")):
        snapshots.extend(json.loads(line) for line in path.read_text().splitlines() if line.strip())
    assert len({s["snapshot_id"] for s in snapshots}) == len(snapshots), "Duplicate snapshots"

    cases = {}
    metadata = {}
    for source in sources:
        if not source.get("enabled", True):
            continue
        rows = sorted(
            (s for s in snapshots if s["source_id"] == source["id"] and "48h" in s["forecasts"]),
            key=lambda s: instant(s["observed_at"]),
        )
        if not rows:
            continue
        times = [instant(s["observed_at"]) for s in rows]
        for row in rows:
            p = row["forecasts"]["48h"]
            assert isinstance(p, (float, int)) and math.isfinite(p) and 0 <= p <= 1
        checkpoint = times[0].replace(hour=0, minute=0, second=0, microsecond=0)
        selected = {}
        while checkpoint <= cutoff:
            index = bisect.bisect_right(times, checkpoint) - 1
            if index >= 0 and checkpoint - times[index] <= timedelta(hours=6):
                row = rows[index]
                outcome = int(any(checkpoint < e <= checkpoint + timedelta(hours=48) for e in events))
                selected[checkpoint] = (row["forecasts"]["48h"], outcome)
            checkpoint += timedelta(hours=6)
        if len(selected) >= 10:
            cases[source["id"]] = selected
            metadata[source["id"]] = source

    common = sorted(set.intersection(*(set(c) for c in cases.values())))
    assert len(common) >= 10, "Insufficient common cases"
    result = []
    for source_id, source_cases in cases.items():
        values = [source_cases[c] for c in common]
        row = {
            "source_id": source_id,
            "name": metadata[source_id]["name"],
            "samples": len(values),
            "brier": round(sum((p - y) ** 2 for p, y in values) / len(values), 6),
            "hit_rate": round(sum((p >= 0.5) == bool(y) for p, y in values) / len(values), 6),
        }
        reference = next(r for r in published["rankings"]["48h"] if r["source_id"] == source_id)
        for key in ("samples", "brier", "hit_rate"):
            assert row[key] == reference[key], f"Mismatch for {source_id}: {key}"
        result.append(row)
    result.sort(key=lambda row: row["brier"])
    assert set(cases) == set(published["ranking_cohorts"]["48h"])
    old = next(r for r in result if r["source_id"] == "codex-reset-com")
    return {
        "methodology": published["methodology_version"],
        "ground_truth_reviewed_at": truth["reviewed_at"],
        "first_checkpoint": common[0].isoformat(),
        "last_checkpoint": common[-1].isoformat(),
        "archive_rows": len(snapshots),
        "positive_checkpoints": sum(cases[result[0]["source_id"]][c][1] for c in common),
        "rankings": result,
        "brier_reduction_vs_current_percent": round((old["brier"] - result[0]["brier"]) / old["brier"] * 100, 2),
        "limitations": [
            "48h windows overlap; checkpoints are not independent reset events.",
            "Freshness reproduces the benchmark's observed_at rule, not source_updated_at.",
            "Results only compare this archived period and these model versions.",
            "Personal weekly/5h recovery and banked reset grants are excluded.",
        ],
    }


if __name__ == "__main__":
    print(json.dumps(audit(Path(sys.argv[1])), ensure_ascii=False, indent=2))
