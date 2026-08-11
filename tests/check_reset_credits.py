#!/usr/bin/env python3
"""Regression checks for reset-credit expiry parsing, timeline mapping, and UI wiring."""

from pathlib import Path
import subprocess


source = Path(__file__).parents[1] / "Sources" / "main.swift"
text = source.read_text(encoding="utf-8")

python_start = text.index("def normalize_reset_credit_count(")
python_end = text.index("\ndef prefer_monotonic_quota_values", python_start)
namespace = {}
exec(text[python_start:python_end], namespace)
normalize = namespace["normalize_reset_credit_expirations"]
normalize_count = namespace["normalize_reset_credit_count"]

payload = {
    "availableCount": 4,
    "credits": [
        {"status": "available", "expiresAt": 400},
        {"status": "used", "expiresAt": 100},
        {"status": "available", "expires_at": "200"},
        {"status": "available", "expiresAt": None},
        {"status": "expired", "expiresAt": 300},
    ],
}
assert normalize(payload) == [200, 400]
assert normalize(None) == []
assert normalize("unexpected") == []
assert normalize({"credits": "unexpected"}) == []
assert normalize({"credits": [None, "unexpected", {"status": "available", "expiresAt": 500}]}) == [500]
assert normalize_count(payload) == 4
assert normalize_count({"availableCount": "3", "credits": []}) == 3
assert normalize_count({"credits": [{"status": "available"}, {"status": "used"}]}) == 1
assert normalize_count({"availableCount": "bad", "credits": [{"status": "available"}]}) == 1
assert normalize_count({"availableCount": True, "credits": []}) == 0
assert normalize_count("unexpected") is None

snapshot_start = text.index("private struct ResetCreditSnapshot")
snapshot_end = text.index("private struct ResetCreditMarkerTiming", snapshot_start)
snapshot_logic = text[snapshot_start:snapshot_end]

swift_start = text.index("private struct ResetCreditMarkerTiming")
swift_end = text.index("private struct ResetCreditExpiryMarker", swift_start)
timeline = text[swift_start:swift_end]
swift_test = f"""
import Foundation

{snapshot_logic}

{timeline}

private let preserved = ResetCreditSnapshot.resolve(
    liveCount: nil,
    liveExpirations: nil,
    cachedCount: 1,
    cachedExpirations: [400]
)
precondition(preserved.count == 1)
precondition(preserved.expirations == [400])
precondition(preserved.isStale == true)

private let explicitZero = ResetCreditSnapshot.resolve(
    liveCount: 0,
    liveExpirations: [400],
    cachedCount: 1,
    cachedExpirations: [400]
)
precondition(explicitZero.count == 0)
precondition(explicitZero.expirations == [])
precondition(explicitZero.isStale == false)

private let unavailable = ResetCreditSnapshot.resolve(
    liveCount: nil,
    liveExpirations: nil,
    cachedCount: nil,
    cachedExpirations: nil
)
precondition(unavailable.count == nil)
precondition(unavailable.expirations == nil)
precondition(unavailable.isStale == false)

let now = Date(timeIntervalSince1970: 100)
let future = ResetCreditTimeline.futureExpirations([300, 50, 200, 200], now: now)
precondition(future.map {{ Int($0.timeIntervalSince1970) }} == [200, 200, 300])
let start = Date(timeIntervalSince1970: 0)
let reset = Date(timeIntervalSince1970: 400)
precondition(abs((ResetCreditTimeline.progress(for: future[0], from: start, to: reset) ?? -1) - 0.5) < 0.001)
precondition(ResetCreditTimeline.progress(for: Date(timeIntervalSince1970: 401), from: start, to: reset) == nil)

var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(secondsFromGMT: 0)!
private let marker = ResetCreditTimeline.nearestMarker(
    expirations: [50, 200, 220, 500],
    now: now,
    start: start,
    reset: reset,
    calendar: utc
)
precondition(Int(marker?.expiration.timeIntervalSince1970 ?? -1) == 200)
precondition(abs((marker?.progress ?? -1) - 0.5) < 0.001)
precondition(marker?.countOnDay == 2)
precondition(marker?.isUrgent == true)
precondition(ResetCreditTimeline.nearestMarker(
    expirations: [500], now: now, start: start, reset: reset, calendar: utc
) == nil)

let day = 24.0 * 3600
let longReset = Date(timeIntervalSince1970: 7 * day)
precondition(ResetCreditTimeline.nearestMarker(
    expirations: [Int(24 * day)],
    now: Date(timeIntervalSince1970: 23 * day),
    start: Date(timeIntervalSince1970: 21 * day),
    reset: Date(timeIntervalSince1970: 28 * day),
    calendar: utc
)?.isUrgent == true)
precondition(ResetCreditTimeline.nearestMarker(
    expirations: [Int(2 * day + 1)],
    now: Date(timeIntervalSince1970: 0),
    start: Date(timeIntervalSince1970: 0),
    reset: longReset,
    calendar: utc
)?.isUrgent == false)
precondition(ResetCreditTimeline.missingExpiryCount(availableCount: 4, knownExpirations: 2) == 2)
precondition(ResetCreditTimeline.missingExpiryCount(availableCount: nil, knownExpirations: 2) == 0)
print("reset credit timeline: ok")
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

for required in (
    "let resetCreditExpirations: [Int]?",
    "let resetCreditsStale: Bool?",
    '"availableResetCredits": normalize_reset_credit_count(reset_credits)',
    '"resetCreditExpirations": normalize_reset_credit_expirations(reset_credits)',
    'send({"method": "account/rateLimits/read", "id": 3, "params": None})',
    "cachedQuota: self.lastGoodInfo",
    "cachedQuota: cached",
    't("  旧数据", "  cached")',
    "menu.addItem(resetCreditsItem)",
    "private func setResetCreditsItem",
    "private func makeResetCreditMarker",
    "view.resetCreditMarker = presentation.resetCreditMarker",
    "最近到期",
    "未返回到期日期",
):
    assert required in text, f"missing reset-credit expiry component: {required}"

print(result.stdout.strip())
print("reset credit parsing and UI: ok")
