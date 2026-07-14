#!/usr/bin/env python3
"""Regression checks for semantic quota-window normalization and ring visibility."""

from pathlib import Path


source = Path(__file__).parents[1] / "Sources" / "main.swift"
text = source.read_text(encoding="utf-8")

start = text.index("def normalize_quota_windows(")
end = text.index("\ndef read_app_server_quota", start + 1)
namespace = {}
exec(text[start:end], namespace)
normalize = namespace["normalize_quota_windows"]
prefer_monotonic = namespace["prefer_monotonic_quota_values"]


def camel(used, reset, minutes):
    return {
        "usedPercent": used,
        "resetsAt": reset,
        "windowDurationMins": minutes,
    }


def snake(used, reset, minutes):
    return {
        "used_percent": used,
        "resets_at": reset,
        "window_minutes": minutes,
    }


five_hour, week = normalize(camel(12, 111, 300), camel(34, 222, 10080))
assert five_hour["used"] == 12 and week["used"] == 34

five_hour, week = normalize(camel(19, 333, 10080), None)
assert five_hour is None, "a lone weekly primary window must not be shown as 5h"
assert week["used"] == 19 and week["reset"] == 333

five_hour, week = normalize(snake(7, 444, 300), None)
assert five_hour["used"] == 7 and week is None

five_hour, week = normalize(camel(41, 555, 10080), camel(9, 666, 300))
assert five_hour["used"] == 9 and week["used"] == 41

# Missing duration metadata keeps the legacy primary=5h / secondary=1w contract.
five_hour, week = normalize({"usedPercent": 3}, {"usedPercent": 27})
assert five_hour["used"] == 3 and week["used"] == 27

# Explicit unknown windows stay unclassified instead of receiving a wrong label.
five_hour, week = normalize(camel(10, 777, 2880), None)
assert five_hour is None and week is None
five_hour, week = normalize(camel(10, 888, 30 * 24 * 60), None)
assert five_hour is None and week is None
five_hour, week = normalize(camel(10, 999, "unknown"), None)
assert five_hour is None and week is None

# A weekly-only latest snapshot must not inherit an old 5h window from fallback history.
latest = {
    "primaryUsed": None,
    "primaryReset": None,
    "secondaryUsed": 17,
    "secondaryReset": 222,
}
snapshots = [
    {"ts": 1, "primaryUsed": 8, "primaryReset": 111, "secondaryUsed": 16, "secondaryReset": 222},
    {"ts": 2, "primaryUsed": None, "primaryReset": None, "secondaryUsed": 17, "secondaryReset": 222},
]
prefer_monotonic(latest, snapshots)
assert latest["primaryUsed"] is None
assert latest["secondaryUsed"] == 17

# Existing windows still keep the highest recent reading within the same reset window.
latest = {"primaryUsed": 3, "primaryReset": 111, "secondaryUsed": 17, "secondaryReset": 222}
snapshots = [
    {"ts": 1, "primaryUsed": 8, "primaryReset": 111, "secondaryUsed": 18, "secondaryReset": 222},
    {"ts": 2, "primaryUsed": 99, "primaryReset": 999, "secondaryUsed": 99, "secondaryReset": 999},
]
prefer_monotonic(latest, snapshots)
assert latest["primaryUsed"] == 8 and latest["secondaryUsed"] == 18

for required in (
    "var fiveHour: Int?",
    "var week: Int?",
    "if week == nil && fiveHour == nil",
    "fiveHourItem.isHidden = fiveHour == nil",
    "weekItem.isHidden = week == nil",
):
    assert required in text, f"missing adaptive single-ring UI component: {required}"

print("quota window normalization: ok")
