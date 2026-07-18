#!/usr/bin/env python3
"""Regression checks for the weekly trend model and graphical forecast row."""

from pathlib import Path
from collections import Counter
from datetime import datetime, timedelta, timezone


source = Path(__file__).parents[1] / "Sources" / "main.swift"
text = source.read_text(encoding="utf-8")

start = text.index("def habit_hour_index(")
end = text.index("\ndef read_app_server_quota", start)
namespace = {
    "Counter": Counter,
    "datetime": datetime,
    "timedelta": timedelta,
    "tz": timezone(timedelta(hours=8)),
}
exec(text[start:end], namespace)
build_weekly_trend = namespace["build_weekly_trend"]
build_habit_profile = namespace["build_habit_profile"]
build_historical_pace_profile = namespace["build_historical_pace_profile"]

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
assert trend["model"] == "building"
assert trend["rate"] is None
assert trend["projectedUsed"] is None
assert trend["exhaustAt"] is None

now = 12 * hour
short_burst = [point(0, 0, reset), point(4 * hour, 2, reset), point(8 * hour, 4, reset), point(12 * hour, 6, reset)]
trend = build_weekly_trend(short_burst, reset, now, 6)
assert trend["confidence"] == "low"

# A personal work-hours profile moves exhaustion across idle nights instead of
# extending an afternoon burst through every remaining wall-clock hour.
habit_weights = [0.02] * 168
for weekday in range(5):
    for local_hour in range(8, 18):
        habit_weights[weekday * 24 + local_hour] = 1.0
now = 13 * hour
workday_burst = [
    point(hour, 0, reset),
    point(4 * hour, 5, reset),
    point(8 * hour, 15, reset),
    point(now, 20, reset),
]
trend = build_weekly_trend(
    workday_burst,
    reset,
    now,
    20,
    habit_weights=habit_weights,
    habit_offset_seconds=8 * hour,
    habit_sample_days=21,
    habit_sample_buckets=80,
)
assert trend["model"] == "habit"
assert trend["confidence"] == "low"
assert trend["projectedUsed"] > 100
assert trend["exhaustAt"] > now + 72 * hour

# The local profile builder learns daytime concentration without retaining any
# thread title or prompt content.
window_start = 35 * 24 * hour
active_buckets = []
for day_index in range(7, 35):
    for local_hour in (9, 10, 14, 15):
        active_buckets.append(day_index * 24 * hour + (local_hour - 8) * hour)
profile = build_habit_profile(active_buckets, window_start)
assert profile["sampleDays"] == 28
assert profile["sampleBuckets"] == 112
daytime = sum(profile["weights"][weekday * 24 + 10] for weekday in range(7)) / 7
night = sum(profile["weights"][weekday * 24 + 3] for weekday in range(7)) / 7
assert daytime > night * 5

# Historical pace uses complete normal cycles and drops a short reset-credit
# sprint, so one deliberately heavy 24-hour cycle cannot redefine normal burn.
historical_weights = [1.0] * 168
first_reset = week
second_reset = 2 * week
short_cycle_end = 2 * week + 24 * hour
target_reset = short_cycle_end + week
historical_points = [
    point(first_reset - hour, 42, first_reset),       # 0.25% per habit hour
    point(week + 23 * hour, 96, second_reset),       # reset after only 24h
    point(short_cycle_end - hour, 50.4, short_cycle_end),  # 0.30% / habit hour
]
historical = build_historical_pace_profile(
    historical_points,
    target_reset,
    target_reset - 48 * hour,
    historical_weights,
)
assert historical["sampleCycles"] == 2
assert historical["excludedShortCycles"] == 1
assert abs(historical["rate"] - 0.275) < 0.001
assert abs(historical["lowRate"] - 0.25) < 0.001
assert abs(historical["highRate"] - 0.30) < 0.001

# Short reset-credit cycles never become the normal baseline by themselves.
all_short_resets = [week, week + 24 * hour, week + 48 * hour]
all_short_points = [
    point(23 * hour, 40, all_short_resets[0]),
    point(47 * hour, 50, all_short_resets[1]),
    point(71 * hour, 60, all_short_resets[2]),
]
all_short = build_historical_pace_profile(
    all_short_points,
    week + 72 * hour,
    73 * hour,
    historical_weights,
)
assert all_short["sampleCycles"] == 0
assert all_short["rate"] is None

# One complete cycle is still insufficient when the other samples are short
# sprints; the model waits for a second normal cycle instead of mixing them.
mixed_resets = [week, 2 * week, 2 * week + 24 * hour]
mixed_duration_points = [
    point(week - hour, 42, mixed_resets[0]),
    point(week + 23 * hour, 80, mixed_resets[1]),
    point(week + 47 * hour, 90, mixed_resets[2]),
]
one_long = build_historical_pace_profile(
    mixed_duration_points,
    2 * week + 48 * hour,
    week + 49 * hour,
    historical_weights,
)
assert one_long["sampleCycles"] == 0
assert one_long["rate"] is None

# An early-cycle burst starts from the historical baseline. Its typical path
# still lasts to reset, while the high side crossing 100% remains a risk range
# instead of becoming a certain exhaustion date.
now = 6 * hour
early_burst = [
    point(0, 0, reset),
    point(2 * hour, 5, reset),
    point(4 * hour, 15, reset),
    point(now, 20, reset),
]
trend = build_weekly_trend(
    early_burst,
    reset,
    now,
    20,
    habit_weights=historical_weights,
    historical_rate=0.30,
    historical_low_rate=0.20,
    historical_high_rate=0.50,
    historical_sample_cycles=4,
)
assert trend["model"] == "habit-history"
assert 60 < trend["projectedUsed"] < 80
assert trend["projectedLowUsed"] < trend["projectedUsed"] < trend["projectedHighUsed"]
assert trend["projectedLowUsed"] < 100 <= trend["projectedHighUsed"]
assert trend["exhaustAt"] is None

# Quota "fuel economy" keeps today's increment separate from the full-cycle
# daily average.
now = 58 * hour
burn_points = [
    point(0, 0, reset),
    point(24 * hour, 10, reset),
    point(48 * hour, 25, reset),
    point(now, 32, reset),
]
trend = build_weekly_trend(burn_points, reset, now, 32)
assert abs(trend["todayUsed"] - 7) < 0.001
assert abs(trend["cycleAveragePctPerDay"] - (32 / (58 / 24))) < 0.001

# Midnight uses the last snapshot at or before 00:00. A first post-midnight
# point cannot erase early-today burn, and an overly old baseline stays unknown.
midnight_points = [
    point(48 * hour - 60, 10, reset),
    point(48 * hour + 120, 11, reset),
    point(49 * hour, 12, reset),
]
trend = build_weekly_trend(midnight_points, reset, 49 * hour, 12)
assert abs(trend["todayUsed"] - 2) < 0.001
assert trend["todayBaselineUsed"] == 10
assert trend["todayBaselineDayStart"] == 48 * hour

old_baseline = [point(40 * hour, 10, reset), point(49 * hour, 12, reset)]
trend = build_weekly_trend(old_baseline, reset, 49 * hour, 12)
assert trend["todayUsed"] is None
assert trend["todayBaselineUsed"] is None
assert trend["todayBaselineDayStart"] is None

midnight_reset = week + 48 * hour
trend = build_weekly_trend(
    [point(48 * hour, 0, midnight_reset), point(49 * hour, 3, midnight_reset)],
    midnight_reset,
    49 * hour,
    3,
)
assert abs(trend["todayUsed"] - 3) < 0.001
assert trend["todayBaselineUsed"] == 0
assert trend["todayBaselineDayStart"] == 48 * hour

# A sharp recent burst is bounded so it influences but does not replace the
# stable since-reset rate.
now = 72 * hour
burst = [
    point(0, 0, reset),
    point(24 * hour, 1, reset),
    point(48 * hour, 2, reset),
    point(60 * hour, 3, reset),
    point(72 * hour, 10, reset),
]
trend = build_weekly_trend(burst, reset, now, 10)
base_rate = 10 / 72
assert base_rate < trend["rate"] <= base_rate * 1.7

for required in (
    "final class WeeklyForecastView: NSView",
    "weeklyTrendRatePctPerHour",
    "weeklyTrendConfidence",
    "weeklyTrendPoints",
    "weeklyTrendProjectedUsed",
    "weeklyTrendProjectedLowUsed",
    "weeklyTrendProjectedHighUsed",
    "weeklyTodayUsed",
    "weeklyCycleAveragePctPerDay",
    "build_historical_pace_profile",
    "weeklyHabitWeights",
    "短期重置冲量会被降权",
    "额度油耗",
    "private func setWeeklyForecastItem",
    "等待新周数据",
    "WeeklyForecastClock.isExpired",
):
    assert required in text, f"missing graphical forecast component: {required}"

print("weekly forecast model and view: ok")
