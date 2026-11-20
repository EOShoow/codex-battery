#!/usr/bin/env python3
"""Exercise local Fable and reset inventory updates through the menu with synthetic Desktop cache entries."""

from datetime import datetime, timezone
from hashlib import sha1, sha256
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import time
import zlib

repo = Path(__file__).resolve().parents[1]
org = "00000000-0000-0000-0000-000000000001"
other = "00000000-0000-0000-0000-000000000002"
base = int(time.time()) - 5
prefixes = [Path(p) for p in [os.getenv("ZSTD_PREFIX"), "/opt/homebrew/opt/zstd", "/usr/local/opt/zstd"] if p]
zstd = next((p for p in prefixes if (p / "include/zstd.h").is_file() and (p / "lib/libzstd.a").is_file()
             and (p / "bin/zstd").is_file()), None)


def iso(offset):
    return datetime.fromtimestamp(base + offset, timezone.utc).isoformat(timespec="microseconds")


def payload(ago, used, reset=2 * 86400):
    row = {"kind": "weekly_scoped", "scope": {"model": {"display_name": "Fable"}}, "percent": used, "resets_at": iso(reset)}
    return {"seven_day": {"utilization": 27}, "seven_day_breakdown": {"as_of": iso(ago)}, "cedar_ember": None,
            "limits": [] if used is None else [row]}


def cache_key(organization, suffix):
    return f"1/0/https://claude.ai/api/organizations/{organization}/usage{suffix}".encode()


def entry(folder, obj, suffix="?skip_spend=1", organization=org, *, stored_key=None, compress=False,
          version=5, crc=True, digest=True, crc_error=False, digest_error=False, trim=0):
    key = cache_key(organization, suffix)
    name = sha1(key).digest()[:8][::-1].hex() + "_0"
    stored_key = stored_key or key
    body = json.dumps(obj).encode()
    if compress:
        body = subprocess.run([str(zstd / "bin/zstd"), "-qc"], input=body, capture_output=True, check=True).stdout
    magic = 0xf4fa6f45970d41d8
    header = struct.pack("<QIIII", 0xfcfb6d1ba7725c30, version, len(stored_key), 0, 0)
    eof1 = struct.pack("<QIIII", magic, int(crc), zlib.crc32(body) ^ int(crc_error), 0, 0)
    # A different valid-looking response in the metadata must never be parsed as the body.
    metadata = json.dumps(payload(0, 99)).encode()
    key_hash = (bytes(32) if digest_error else sha256(stored_key).digest()) if digest else b""
    eof0 = struct.pack("<QIIII", magic, 1 | (2 if digest else 0), zlib.crc32(metadata), len(metadata), 0)
    data = header + stored_key + body + eof1 + metadata + key_hash + eof0
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / name
    path.write_bytes(data[:len(data) - trim])
    return path


harness = r'''
import AppKit
import Foundation

let app = NSApplication.shared
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let now = Date(timeIntervalSince1970: Double(CommandLine.arguments[2])!)
let org = "00000000-0000-0000-0000-000000000001"
let other = "00000000-0000-0000-0000-000000000002"
func group(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }
func load(_ name: String, _ organization: String = org) -> ClaudeUsageCache.FableSample? {
    ClaudeUsageCache.latest(in: group(name), organization: organization, at: now).fable
}
precondition(load("initial")?.value?.used == 47 && load("initial")?.time == now.addingTimeInterval(-60))
precondition(load("initial", other)?.value?.used == 96 && load("initial", "invalid") == nil)
precondition(load("reset")?.value?.used == 0 && load("overrun")?.value?.used == 100)
for broken in ["wrongkey", "badcrc", "badhash", "truncated", "version", "future", "notime", "boolean", "oversize", "duplicate"] {
    precondition(load(broken) == nil, broken)
}
for absent in ["noFable", "conflict", "otherKind", "notStarted"] {
    precondition(load(absent) != nil && load(absent)?.value == nil, absent)
}
let dir = group("Desktop")
let live = dir.appendingPathComponent("Cache/Cache_Data")
let plan = dir.appendingPathComponent("plan-usage-history.json")
let diag = root.appendingPathComponent("diagnostic.json")
try! FileManager.default.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
func replace(_ name: String) {
    if FileManager.default.fileExists(atPath: live.path) { try! FileManager.default.removeItem(at: live) }
    try! FileManager.default.copyItem(at: group(name), to: live)
}
func tray(_ organization: String) {
    let record: [String: Any] = ["t": now.timeIntervalSince1970 * 1000, "org": organization, "u": ["fh": 8, "sd": 27]]
    try! JSONSerialization.data(withJSONObject: ["version": 2, "samples": [record]]).write(to: plan, options: .atomic)
}
replace("initial")
tray(org)
let suite = "local.codex.battery.test." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
for key in [QuotaBalanceMenuController.localOnlyKey, QuotaBalanceMenuController.enabledKey, "claudeDesktopSyncEnabled"] {
    defaults.set(true, forKey: key)
}
let menu = QuotaBalanceMenuController(defaults: defaults, chinese: true, diagnosticURL: diag, planHistoryURL: plan,
    desktopAccess: { fatalError("Unexpected AX access") }, credentialLoader: { fatalError("Unexpected credential access") })
func weeklyCell() -> String? {
    menu.item.view?.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.first { $0.contains("Fable") }
}
menu.menuWillOpen()
precondition(weeklyCell() == "73% · Fable 53%" && menu.localForecast?.fableSource == .desktopUsageCache)
let initialStock = menu.claudeResetStock(at: now)!
precondition(initialStock.count == 4 && initialStock.nearestExpiry(at: now) == now.addingTimeInterval(3600))
let resetStamp = now.addingTimeInterval(-7200)
precondition(menu.localResetSample?.time == resetStamp && menu.localResetSample!.isStale(at: now))
let resetCell = menu.item.view!.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("4 次") }!
precondition(resetCell.stringValue.hasSuffix("到期 · 旧") && resetCell.toolTip!.contains("重置明细采样于"))
precondition(menu.settingsItem.submenu!.items.contains { $0.title.hasPrefix("最近已知到期时间") })
let encoded = String(data: defaults.data(forKey: "claudeLocalResetInventory")!, encoding: .utf8)!
precondition(!encoded.contains("SYNTHETIC-GRANT-ID") && !encoded.contains("SYNTHETIC-LABEL"))
let old = menu.localForecast!.fable!
let rows = menu.localForecast!.rows(at: now, chinese: true, activity: nil)
precondition(rows.last?.used == 47 && rows.last?.projectedUsed != nil && rows.last!.tooltip.contains("本机用量缓存"))
replace("badcrc")
menu.refreshIfDue(now: now.addingTimeInterval(3600))
let atExpiry = now.addingTimeInterval(3600)
let nextExpiry = now.addingTimeInterval(3 * 86400)
precondition(menu.localResetSample?.time == resetStamp && menu.claudeResetStock(at: atExpiry)?.count == 2)
precondition(menu.claudeResetStock(at: atExpiry)?.nearestExpiry(at: atExpiry) == nextExpiry)
precondition(menu.item.view!.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.contains { $0.hasPrefix("2 次 · ") })
precondition(menu.claudeResetStock(at: now.addingTimeInterval(7200))?.count == 5, "a scheduled grant begins at its own start")
let reopened = QuotaBalanceMenuController(defaults: defaults, planHistoryURL: plan,
    desktopAccess: { fatalError("AX") }, credentialLoader: { fatalError("credential") })
precondition(reopened.localResetSample?.time == resetStamp && reopened.claudeResetStock(at: now)?.count == 4)
precondition(menu.localForecast?.fable == old && weeklyCell()?.hasSuffix("Fable 53% · 旧") == true)
precondition(menu.localForecast!.rows(at: now.addingTimeInterval(86400), chinese: true, activity: nil).last?.projectedUsed == nil)
replace("reset")
menu.refreshIfDue(now: now)
precondition(menu.localForecast?.fable?.used == 0 && menu.localForecast!.fable!.reset > old.reset)
precondition(weeklyCell() == "73% · Fable 100%")
// An explicit correction wins until the next server sample, even if the new percentage goes down.
precondition(menu.saveCalibration(organization: org, fableUsed: 23, reset: old.reset, now: now))
precondition(menu.localForecast?.fableSource == .manual)
replace("afterManual")
menu.refreshIfDue(now: now.addingTimeInterval(2))
precondition(menu.localForecast?.fable?.used == 12 && menu.localForecast?.fableSource == .desktopUsageCache)
replace("absentAfterManual")
menu.refreshIfDue(now: now.addingTimeInterval(10))
precondition(menu.localForecast?.fable == nil && weeklyCell() == nil)
precondition(menu.localForecast!.rows(at: now, chinese: true, activity: nil).last?.endText == "待自动更新")
tray(other)
replace("badcrc")
menu.refreshIfDue(now: now)
precondition(menu.localForecast?.fable == nil, "another organization must not inherit a cached or manual meter")
precondition(menu.localResetSample == nil && menu.claudeResetStock(at: now) == nil)
tray(org)
replace("expired")
defaults.removeObject(forKey: "claudeLocalForecastCalibration")
menu.refreshIfDue(now: now)
precondition(menu.localForecast?.fable == nil && menu.currentQuotas.claude == nil && !menu.desktopSyncEnabled)
precondition(menu.claudeResetStock(at: now)?.count == 4, "the original organization can recover its own snapshot")
replace("newInventory")
menu.refreshIfDue(now: now)
let currentReset = menu.localResetSample!
precondition(currentReset.time == now.addingTimeInterval(-30) && !currentReset.isStale(at: now))
precondition(menu.claudeResetStock(at: now)?.count == 1 && menu.claudeResetStock(at: now)?.nearestExpiry(at: now) == nextExpiry)
for malformed in ["missingInventory", "badGrant", "wrongDate", "wrongPause", "futureInventory", "genericOnly"] {
    replace(malformed)
    menu.refreshIfDue(now: now)
    precondition(menu.localResetSample == currentReset, malformed)
}
for name in ["emptyInventory", "noGrant"] {
    replace(name)
    menu.refreshIfDue(now: now)
    precondition(menu.claudeResetStock(at: now)?.count == 0 && menu.claudeResetStock(at: now)?.nearestExpiry(at: now) == nil, name)
    precondition(menu.item.view!.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.contains("0 次"))
}
for name in ["conflictingInventory", "outsideProgram"] {
    replace(name)
    menu.refreshIfDue(now: now)
    precondition(menu.localResetSample != nil && menu.claudeResetStock(at: now) == nil, name)
}
let info = try! JSONSerialization.jsonObject(with: Data(contentsOf: diag)) as! [String: Any]
precondition(info["claude_requests_started_this_process"] as? Int == 0 && info["claude_desktop_accessibility"] as? Bool == false)
print("Local Fable and reset inventory, independent timestamps, native panels, expiry, persistence and account isolation: ok")
'''

with tempfile.TemporaryDirectory(prefix="codex-battery-fable-") as tmp:
    test = Path(tmp)
    initial = entry(test / "initial", payload(-60, 47), compress=zstd is not None)
    os.utime(initial, (base - 10000, base - 10000))
    entry(test / "initial", payload(-300, 45), "", crc=False, digest=False)
    entry(test / "initial", payload(-10, 96), organization=other)
    grant_query = "?cedar_ember=1&skip_spend=1"
    def inventory(name, offset, block, suffix=grant_query):
        # A reset reading remains valid even in a response without model meters.
        entry(test / name, {"seven_day_breakdown": {"as_of": iso(offset)}, "cedar_ember": block}, suffix)

    early = {"resets_left": 1, "ends_at": iso(3600), "id": "SYNTHETIC-GRANT-ID", "label": "SYNTHETIC-LABEL"}
    later = {"resets_left": 2, "ends_at": iso(3 * 86400)}
    inventory("initial", -7200, {"eligible": True, "grants": [early, {**early, "id": "second"}, later,
              {**later, "paused": True}, {**later, "ends_at": iso(-60)}, {**later, "resets_left": 0},
              {**later, "resets_left": 3, "starts_at": iso(7200)}]})
    remaining = {"eligible": True, "grants": [{**later, "resets_left": 1}]}
    inventory("newInventory", -30, remaining)
    inventory("missingInventory", -25, {"eligible": True})
    inventory("badGrant", -25, {"eligible": True, "grants": [early, {"resets_left": True}]})
    inventory("wrongDate", -25, {"eligible": True, "grants": [{**early, "ends_at": "invalid"}]})
    inventory("wrongPause", -25, {"eligible": True, "grants": [{**early, "paused": "false"}]})
    inventory("futureInventory", 300, {"eligible": True, "grants": []})
    entry(test / "genericOnly", payload(-5, 50))
    inventory("emptyInventory", -20, {"eligible": True, "grants": []})
    inventory("noGrant", -15, {"eligible": False, "ineligible_reason": "no_grant"})
    inventory("conflictingInventory", -12, remaining)
    inventory("conflictingInventory", -12, {"eligible": True, "grants": []}, "")
    inventory("outsideProgram", -10, {"eligible": False, "ineligible_reason": "tier"})
    entry(test / "reset", payload(-10, 0, 6 * 86400), "?cedar_ember=1&skip_spend=1")
    entry(test / "overrun", payload(-10, 102))
    entry(test / "afterManual", payload(1, 12))
    entry(test / "noFable", payload(0, None))
    entry(test / "noFable", payload(-98, 47), "")
    # Later than the manual correction for the controller's second read.
    entry(test / "absentAfterManual", payload(5, None))
    entry(test / "expired", payload(-4000, 7, -60))
    entry(test / "conflict", payload(-60, 24))
    entry(test / "conflict", payload(-60, 77), "")
    for name, overrides in [("wrongkey", {"stored_key": cache_key(other, "?skip_spend=1")}),
                            ("badcrc", {"crc_error": True}), ("badhash", {"digest_error": True}),
                            ("truncated", {"trim": 8}), ("version", {"version": 9})]:
        entry(test / name, payload(-60, 47), **overrides)
    entry(test / "future", payload(300, 98))
    entry(test / "boolean", payload(-60, True))
    entry(test / "oversize", {**payload(-60, 31), "pad": " " * 270000}, compress=zstd is not None)
    entry(test / "notime", {**payload(-60, 47), "seven_day_breakdown": {}})
    for name, change in [("otherKind", {"kind": "weekly_scoped_shares"}), ("notStarted", {"percent": 0, "resets_at": None})]:
        obj = payload(-60, 47)
        obj["limits"][0].update(change)
        entry(test / name, obj)
    obj = payload(-60, 47)
    obj["limits"] *= 2
    entry(test / "duplicate", obj)
    main = test / "main.swift"
    main.write_text(harness)
    files = ["ClaudeQuota", "ClaudeDesktopResets", "ClaudeForecast", "ClaudeLocalForecast", "ClaudeUsageCache",
             "QuotaBalanceMenu", "PaceBars", "WeeklyActivitySchedule"]
    flags = ["-D", "CODEX_BATTERY_ZSTD", "-import-objc-header", str(zstd / "include/zstd.h"),
             str(zstd / "lib/libzstd.a")] if zstd else []
    binary = test / "check"
    subprocess.run(["swiftc", str(main), *(str(repo / "Sources" / (f + ".swift")) for f in files), *flags,
                    "-framework", "AppKit", "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(test), str(base)], check=True)
