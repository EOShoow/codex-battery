#!/usr/bin/env python3
"""Regression checks for the weekly trend model and graphical forecast row."""

from pathlib import Path


source = Path(__file__).parents[1] / "Sources" / "main.swift"
text = source.read_text(encoding="utf-8")

start = text.index("def build_weekly_trend(")
end = text.index("\ndef ", start + 1)
namespace = {}
exec(text[start:end], namespace)
build_weekly_trend = namespace["build_weekly_trend"]

hour = 3600
week = 7 * 24 * hour


def point(timestamp, used, reset):
    return (timestamp, used, reset)


# A steady week should project close to 100% used at reset.
reset = week
now = week / 2
steady = [point(t, t / week * 100, reset) for t in range(0, int(now) + 1, 12 * hour)]
trend = build_weekly_trend(steady, reset, now, 50)
projected = 50 + trend["rate"] * ((reset - now) / hour)
assert 98 <= projected <= 102
assert trend["confidence"] == "high"

# A recent acceleration should influence the estimate without fully replacing
# the more stable since-reset rate.
now = 3 * 24 * hour
accelerating = [
    point(0, 0, reset),
    point(24 * hour, 5, reset),
    point(48 * hour, 10, reset),
    point(60 * hour, 20, reset),
    point(72 * hour, 30, reset),
]
trend = build_weekly_trend(accelerating, reset, now, 30)
base_rate = 30 / 72
recent_rate = 20 / 24
assert base_rate < trend["rate"] < recent_rate

# A nearby reset timestamp is the same week, while an unrelated window must
# not contaminate the trend.
mixed = accelerating + [point(70 * hour, 99, reset + 10_000), point(71 * hour, 31, reset + 1)]
trend = build_weekly_trend(mixed, reset, now, 31)
assert max(item["used"] for item in trend["points"]) <= 31
assert any(item["used"] == 31 for item in trend["points"])

reset_edges = [
    point(10 * hour, 5, reset + 300),
    point(20 * hour, 80, reset + 301),
]
trend = build_weekly_trend(reset_edges, reset, 24 * hour, 100)
values = [item["used"] for item in trend["points"]]
assert 5 in values and 80 not in values

# Duplicate threads in one 5-minute bucket keep the highest monotonic value.
duplicates = [point(3600, 8, reset), point(3700, 6, reset), point(7200, 7, reset)]
trend = build_weekly_trend(duplicates, reset, 3 * hour, 8)
values = [item["used"] for item in trend["points"]]
assert 8 in values and 6 not in values and 7 not in values

# Sparse early-week evidence is shown with low confidence.
now = 4 * hour
sparse = [point(0, 0, reset), point(4 * hour, 2, reset)]
trend = build_weekly_trend(sparse, reset, now, 2)
assert trend["confidence"] == "low"

now = 12 * hour
short_burst = [point(0, 0, reset), point(4 * hour, 2, reset), point(8 * hour, 4, reset), point(12 * hour, 6, reset)]
trend = build_weekly_trend(short_burst, reset, now, 6)
assert trend["confidence"] == "low"

# A sharp recent burst is bounded so it influences but does not replace the
# stable since-reset rate.
now = 72 * hour
burst = [point(0, 0, reset), point(48 * hour, 0, reset), point(72 * hour, 10, reset)]
trend = build_weekly_trend(burst, reset, now, 10)
base_rate = 10 / 72
assert base_rate < trend["rate"] <= base_rate * 1.7

for required in (
    "final class WeeklyForecastView: NSView",
    "weeklyTrendRatePctPerHour",
    "weeklyTrendConfidence",
    "weeklyTrendPoints",
    "private func setWeeklyForecastItem",
    "等待新周数据",
    "WeeklyForecastClock.isExpired",
):
    assert required in text, f"missing graphical forecast component: {required}"

print("weekly forecast model and view: ok")
