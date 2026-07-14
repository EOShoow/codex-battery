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
    WeeklyTrendPoint(timestamp: 48 * 3600, used: 10),
    WeeklyTrendPoint(timestamp: now, used: 20),
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
precondition(abs((newWeek.rate ?? 0) - (1.0 / 12.0)) < 0.001)

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
