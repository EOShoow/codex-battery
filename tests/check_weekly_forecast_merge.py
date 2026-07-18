#!/usr/bin/env python3
"""Execute the real Swift live-quota/trend merge logic against reset changes."""

from pathlib import Path
import subprocess


source = Path(__file__).parents[1] / "Sources" / "main.swift"
text = source.read_text(encoding="utf-8")
for required in (
    "let mergedTrend = WeeklyTrendCalculator.merge(",
    "sourceReset: secondaryReset",
    "targetReset: quota.secondaryReset",
    "currentUsed: quota.secondaryUsed",
):
    assert required in text, f"live quota merge is not wired through the trend calculator: {required}"
start = text.index("struct WeeklyTrendPoint: Decodable")
end = text.index("private struct ResetCreditExpiryMarker", start)
calculator = text[start:end]

swift_test = f"""
import Foundation

{calculator}

func iso(_ timestamp: Double) -> String {{
    ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
}}

let week = 7.0 * 24 * 3600
let reset = week
let now = 72.0 * 3600
let points = [
    WeeklyTrendPoint(timestamp: 0, used: 0),
    WeeklyTrendPoint(timestamp: 24 * 3600, used: 5),
    WeeklyTrendPoint(timestamp: 48 * 3600, used: 10),
    WeeklyTrendPoint(timestamp: 60 * 3600, used: 20),
    WeeklyTrendPoint(timestamp: now, used: 30),
]

private let sameWeek = WeeklyTrendCalculator.merge(
    points: points,
    sourceReset: Int(reset),
    targetReset: Int(reset + 1),
    timestamp: iso(now),
    currentUsed: 40
)
precondition(sameWeek.rate != nil && sameWeek.rate! > 0.55)
precondition(sameWeek.points.last?.used == 40)
let projectedAtReset = 40 + sameWeek.rate! * ((reset + 1 - now) / 3600)
precondition(projectedAtReset > 100)

var habitWeights = [Double](repeating: 0.02, count: 168)
for weekday in 0..<5 {{
    for hour in 8..<18 {{
        habitWeights[weekday * 24 + hour] = 1
    }}
}}
let habitNow = 13.0 * 3600
let habitPoints = [
    WeeklyTrendPoint(timestamp: 1 * 3600, used: 0),
    WeeklyTrendPoint(timestamp: 4 * 3600, used: 5),
    WeeklyTrendPoint(timestamp: 8 * 3600, used: 15),
    WeeklyTrendPoint(timestamp: habitNow, used: 20),
]
private let habitWeek = WeeklyTrendCalculator.merge(
    points: habitPoints,
    sourceReset: Int(reset),
    targetReset: Int(reset),
    timestamp: iso(habitNow),
    currentUsed: 20,
    habitWeights: habitWeights,
    habitTimeZoneOffsetSeconds: 8 * 3600,
    habitSampleDays: 21,
    habitSampleBuckets: 80
)
precondition(habitWeek.model == "habit")
precondition(habitWeek.confidence == "low")
precondition((habitWeek.projectedUsed ?? 0) > 100)
precondition((habitWeek.exhaustAt ?? 0) > habitNow + 72 * 3600)

let historicalWeights = [Double](repeating: 1, count: 168)
let earlyBurstNow = 6.0 * 3600
let earlyBurstPoints = [
    WeeklyTrendPoint(timestamp: 0, used: 0),
    WeeklyTrendPoint(timestamp: 2 * 3600, used: 5),
    WeeklyTrendPoint(timestamp: 4 * 3600, used: 15),
    WeeklyTrendPoint(timestamp: earlyBurstNow, used: 20),
]
private let historicalWeek = WeeklyTrendCalculator.merge(
    points: earlyBurstPoints,
    sourceReset: Int(reset),
    targetReset: Int(reset),
    timestamp: iso(earlyBurstNow),
    currentUsed: 20,
    habitWeights: historicalWeights,
    historicalRatePctPerHabitHour: 0.30,
    historicalLowRatePctPerHabitHour: 0.20,
    historicalHighRatePctPerHabitHour: 0.50,
    historicalSampleCycles: 4
)
precondition(historicalWeek.model == "habit-history")
precondition(historicalWeek.rate != nil)
precondition((historicalWeek.projectedUsed ?? 0) > 60)
precondition((historicalWeek.projectedUsed ?? 100) < 80)
precondition((historicalWeek.projectedLowUsed ?? 100) < (historicalWeek.projectedUsed ?? 0))
precondition((historicalWeek.projectedUsed ?? 100) < (historicalWeek.projectedHighUsed ?? 0))
precondition((historicalWeek.projectedLowUsed ?? 100) < 100)
precondition((historicalWeek.projectedHighUsed ?? 0) >= 100)
precondition(historicalWeek.exhaustAt == nil)

let midnightNow = 49.0 * 3600
private let cachedMidnightBaseline = WeeklyTrendCalculator.merge(
    points: [
        WeeklyTrendPoint(timestamp: 48 * 3600 + 120, used: 11),
        WeeklyTrendPoint(timestamp: midnightNow, used: 12),
    ],
    sourceReset: Int(reset),
    targetReset: Int(reset),
    timestamp: iso(midnightNow),
    currentUsed: 12,
    todayBaselineUsed: 10,
    todayBaselineDayStart: 48 * 3600
)
precondition(abs((cachedMidnightBaseline.todayUsed ?? 0) - 2) < 0.001)
precondition(cachedMidnightBaseline.todayBaselineUsed == 10)
precondition(cachedMidnightBaseline.todayBaselineDayStart == 48 * 3600)

private let staleMidnightBaseline = WeeklyTrendCalculator.merge(
    points: [],
    sourceReset: Int(reset),
    targetReset: Int(reset),
    timestamp: iso(73 * 3600),
    currentUsed: 13,
    todayBaselineUsed: 10,
    todayBaselineDayStart: 48 * 3600
)
precondition(staleMidnightBaseline.todayUsed == nil)

private let acceptedBoundary = WeeklyTrendCalculator.merge(
    points: points,
    sourceReset: Int(reset),
    targetReset: Int(reset + 300),
    timestamp: iso(now),
    currentUsed: 40
)
precondition(acceptedBoundary.points.count > 2)

private let rejectedBoundary = WeeklyTrendCalculator.merge(
    points: points,
    sourceReset: Int(reset),
    targetReset: Int(reset + 301),
    timestamp: iso(now),
    currentUsed: 40
)
precondition(rejectedBoundary.confidence == "low")
precondition(rejectedBoundary.points.count == 2)

precondition(WeeklyForecastClock.isExpired(
    resetSeconds: 100,
    wallClockNow: Date(timeIntervalSince1970: 101)
))
let referenceNow = WeeklyForecastClock.referenceNow(
    snapshot: Date(timeIntervalSince1970: 50),
    wallClockNow: Date(timeIntervalSince1970: 101)
)
precondition(referenceNow.timeIntervalSince1970 == 101)

let newReset = reset + week
let newNow = reset + 12 * 3600
private let newWeek = WeeklyTrendCalculator.merge(
    points: points,
    sourceReset: Int(reset),
    targetReset: Int(newReset),
    timestamp: iso(newNow),
    currentUsed: 1
)
precondition(newWeek.confidence == "low")
precondition(newWeek.points.count == 2)
precondition(newWeek.rate == nil)
precondition(newWeek.projectedUsed == nil)
precondition(newWeek.exhaustAt == nil)
precondition(newWeek.model == "building")

print("weekly live merge: ok")
"""

result = subprocess.run(
    ["swift", "-"],
    input=swift_test,
    text=True,
    capture_output=True,
    check=False,
)
if result.returncode != 0:
    raise AssertionError(result.stdout + result.stderr)
print(result.stdout.strip())
