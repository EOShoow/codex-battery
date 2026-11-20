#!/usr/bin/env python3
"""Claude weekly history, activity-weighted projections and the shared pace-bar view. Offline only."""

import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / "Sources" / "main.swift"
text = source.read_text(encoding="utf-8")
app_entrypoint = """let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
"""
assert app_entrypoint in text, "cannot locate the app entrypoint"

harness = r'''
import AppKit
import Foundation

extension AppDelegate {
    func verifyDesktopPaceRows() {
        renderForecast()
        guard let view = forecastItem.view as? PaceBarsView else { fatalError("Desktop fallback needs pace bars") }
        precondition(view.rows.map(\.name) == ["Codex", "Claude", "Fable"])
        let desktopRows = Array(view.rows.dropFirst())
        precondition(desktopRows.map(\.used) == [26, 45])
        precondition(desktopRows[0].endText.contains("74%") && desktopRows[1].endText.contains("55%"))
        precondition(desktopRows.allSatisfy { $0.projectedUsed == nil && $0.pace == nil && $0.tooltip.contains("Claude Desktop") })
        if CommandLine.arguments.count > 2 {
            let output = URL(fileURLWithPath: CommandLine.arguments[2]).deletingPathExtension()
                .appendingPathExtension("desktop.png")
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: output)
        }
    }

    func verifyLocalMenu() {
        quotaBalanceMenu.onChange = { [weak self] in self?.renderForecast() }
        applyClaudeSettings()
        precondition(claudeDesktopResetMonitor == nil && taskLauncher == nil)
        precondition(menu.items.first === quotaBalanceMenu.item)
        let view = forecastItem.view as! PaceBarsView
        precondition(view.rows.map(\.name) == ["Codex", "Claude", "Fable · 旧"] ||
                     view.rows.map(\.name) == ["Codex", "Claude", "Fable · old"])
        precondition(view.rows[1].projectedUsed != nil && view.rows[2].projectedUsed != nil)
    }

    func verifyMenuIsolation(defaults: UserDefaults) {
        let codexRows = [fiveHourItem, weekItem, resetCreditsItem, todayItem, quotaBurnItem,
                         forecastItem, topItem, activityItem, updatedItem]
        func assertCodexOnlyMenu() {
            precondition(Array(menu.items.prefix(codexRows.count)) == codexRows, "Codex menu order stays intact")
            precondition(!menu.items.contains(quotaBalanceMenu.item), "the comparison requires an opt-in")
            precondition(forecastItem.view is WeeklyForecastView, "the Codex-only forecast remains a trend chart")
            precondition(iconStyleItem.submenu?.items.count == 2, "Codex-only users keep the two original icon choices")
            precondition(claudeDesktopResetMonitor == nil, "default off must not start an Accessibility observer")
        }

        lastCodexForecast = WeeklyForecastPresentation(
            summary: "60% left at reset", confidence: "High", actualPoints: [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.2)],
            currentPoint: CGPoint(x: 0.5, y: 0.2), forecastPoint: CGPoint(x: 1, y: 0.4),
            resetCreditMarker: nil, tone: .systemGreen, tooltip: "Codex usage forecast"
        )
        quotaBalanceMenu.onChange = { [weak self] in self?.renderForecast() }
        applyClaudeSettings()
        assertCodexOnlyMenu()
        precondition(taskLauncher == nil, "default off must not create the experimental task launcher")

        // Flip the stored preference without calling the account client in this UI harness.
        defaults.set(true, forKey: QuotaBalanceMenuController.enabledKey)
        applyClaudeSettings()
        precondition(menu.items.first === quotaBalanceMenu.item && forecastItem.view is PaceBarsView)
        precondition(taskLauncher.map { menu.items.contains($0.item) } == true)
        precondition(iconStyleItem.submenu?.items.count == 3)
        precondition(claudeDesktopResetMonitor == nil, "account-only use must not start Desktop sync")

        defaults.set(false, forKey: QuotaBalanceMenuController.enabledKey)
        applyClaudeSettings()
        assertCodexOnlyMenu()
        precondition(taskLauncher.map { !menu.items.contains($0.item) } == true)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let menuSuite = "local.codex.battery.menu.isolation." + UUID().uuidString
let menuDefaults = UserDefaults(suiteName: menuSuite)!
defer { menuDefaults.removePersistentDomain(forName: menuSuite) }
let menuController = QuotaBalanceMenuController(defaults: menuDefaults,
    desktopAccess: { fatalError("menu layout must not probe Accessibility") },
    credentialLoader: { fatalError("menu layout must not read Claude credentials") })
AppDelegate(quotaBalanceMenu: menuController).verifyMenuIsolation(defaults: menuDefaults)

let desktopSuite = menuSuite + ".desktop"
let desktopDefaults = UserDefaults(suiteName: desktopSuite)!
defer { desktopDefaults.removePersistentDomain(forName: desktopSuite) }
desktopDefaults.set(true, forKey: QuotaBalanceMenuController.enabledKey)
desktopDefaults.set(true, forKey: "claudeDesktopSyncEnabled")
desktopDefaults.set("credential_expired", forKey: "claudeQuotaLastOutcome")
let desktopController = QuotaBalanceMenuController(defaults: desktopDefaults, chinese: true, desktopAccess: { true },
    credentialLoader: { fatalError("desktop bars should not read Claude credentials") })
desktopController.updateDesktopQuota(ClaudeDesktopQuotaSnapshot(fiveHourUsed: 3, weekUsed: 26, fableUsed: 45, updatedAt: Date()))
AppDelegate(quotaBalanceMenu: desktopController).verifyDesktopPaceRows()

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let historyURL = folder.appendingPathComponent("support/claude-usage-history.json")
let now = Date()
let day: TimeInterval = 86400
let reset = now.addingTimeInterval(5.8 * day)        // 1.2 days into the week
let fableReset = now.addingTimeInterval(3 * day)     // 4 days into its own week

func snapshot(at time: Date, week: Double, fable: Double?, opus: ProviderQuotaWindow? = nil) -> ProviderQuotaSnapshot {
    var models: [String: ProviderQuotaWindow] = [:]
    if let fable { models["seven_day_fable"] = ProviderQuotaWindow(used: fable, resetsAt: fableReset) }
    if let opus { models["seven_day_opus"] = opus }
    return ProviderQuotaSnapshot(checkedAt: time, fiveHour: ProviderQuotaWindow(used: 6, resetsAt: now.addingTimeInterval(3600)),
                                 week: ProviderQuotaWindow(used: week, resetsAt: reset), modelWindows: models)
}

let history = ClaudeUsageHistory(url: historyURL)
let unused = ProviderQuotaWindow(used: 0, resetsAt: nil)
history.record(snapshot(at: now.addingTimeInterval(-3600), week: 11, fable: 70, opus: unused))
history.record(snapshot(at: now.addingTimeInterval(-3500), week: 11.5, fable: 71)) // within 4 min: replaces
history.record(snapshot(at: now, week: 13, fable: 80))
precondition(history.windows["seven_day"]?.samples.count == 2, "samples closer than 4 minutes are merged")
precondition(history.windows["seven_day_opus"] == nil, "a window without a reset time is not charted")
let attributes = try FileManager.default.attributesOfItem(atPath: historyURL.path)
precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "history is private to the user")
let raw = try String(contentsOf: historyURL, encoding: .utf8)
precondition(!raw.contains("five_hour") && !raw.lowercased().contains("token"), "only weekly percentages are stored")

let reloaded = ClaudeUsageHistory(url: historyURL)
precondition(reloaded.windows == history.windows, "history survives relaunch")
let rows = ClaudeForecast.rows(history: reloaded, now: now, chinese: false)
precondition(rows.map(\.name) == ["Claude", "Fable"], "account row first, then model windows")
// Claude: 13% after 28.8h → 0.451%/h; 139.2h left → ~75.8% used → 24% left.
precondition(rows[0].endText == "24% left at reset", rows[0].endText)
precondition(abs((rows[0].projectedUsed ?? 0) - 75.83) < 0.1 && rows[0].used == 13)
precondition(abs((rows[0].pace ?? 0) - 1.2 / 7) < 0.001, "pace tick sits at the elapsed share of the week")
// Fable: 80% after 96h → 0.833%/h; runs out after 24h more, 2 days before its reset.
precondition(rows[1].endText == "Out 2.0 days early", rows[1].endText)
precondition(rows[1].runsOut && rows[1].tone == .systemRed)
precondition(rows[0].color != rows[1].color)
precondition(rows[0].tooltip.contains("While activity history builds"))

// A Saturday snapshot in UTC+8, with work from 09:00 to 17:00 on weekdays.
let iso = ISO8601DateFormatter()
let saturday = iso.date(from: "2026-01-10T04:00:00Z")!
let mondayMorning = iso.date(from: "2026-01-12T01:00:00Z")!
let tuesdayEvening = iso.date(from: "2026-01-13T09:00:00Z")!
var weights = [Double](repeating: 0, count: 168)
for weekday in 0..<5 {
    for hour in 9..<17 { weights[weekday * 24 + hour] = 1 }
}
let schedule = WeeklyActivitySchedule(weights: weights, timeZoneOffsetSeconds: 8 * 3600)!
let weightedHistory = ClaudeUsageHistory(url: nil)
weightedHistory.record(ProviderQuotaSnapshot(checkedAt: saturday, fiveHour: nil,
    week: ProviderQuotaWindow(used: 40, resetsAt: mondayMorning),
    modelWindows: ["seven_day_fable": ProviderQuotaWindow(used: 75, resetsAt: tuesdayEvening)]))
let weighted = ClaudeForecast.rows(history: weightedHistory, now: saturday, chinese: false, activitySchedule: schedule)
// Claude's window ends before any more active hours. Fable has used 75% in 24 active hours,
// and can spend 8 more active hours before hitting its limit at 17:00 Monday.
precondition(weighted.map(\.endText) == ["60% left at reset", "Out 1.0 days early"])
precondition(weighted[0].projectedUsed == 40 && weighted[1].projectedUsed == 125)
precondition(weighted.map(\.used) == [40, 75] && weighted.allSatisfy { $0.tooltip.contains("same local activity hours") })
precondition(!weighted[0].runsOut && weighted[1].runsOut)
let uniform = ClaudeForecast.rows(history: weightedHistory, now: saturday, chinese: false)
precondition(weighted.map(\.pace) == uniform.map(\.pace), "the reference tick still measures elapsed wall time")
precondition(weighted.map(\.projectedUsed) != uniform.map(\.projectedUsed))
precondition(WeeklyActivitySchedule(weights: []) == nil)
precondition(ClaudeForecast.rows(history: reloaded, now: now.addingTimeInterval(20 * 60), chinese: true)[0].endText.hasSuffix("· 旧"))
let cachedRows = ClaudeForecast.rows(history: reloaded, now: now, chinese: false, reliable: false, windowKeys: ["seven_day"])
precondition(cachedRows.count == 1 && cachedRows[0].endText == "Last left 87% · stale")
precondition(cachedRows[0].projectedUsed == nil && cachedRows[0].pace == nil, "an old reading cannot drive a projection")
let partial = ClaudeUsageHistory(url: nil)
partial.record(snapshot(at: now.addingTimeInterval(-60), week: 12, fable: 80))
partial.record(snapshot(at: now, week: 13, fable: nil))
precondition(partial.lastWeeklySnapshot(at: now)?.modelWindows.isEmpty == true,
             "the last total must not be paired with a model value from another check")

// The tray cache keeps each organization's samples separate. This suite never touches a real account.
let planURL = folder.appendingPathComponent("plan-usage-history.json")
let a = now.addingTimeInterval(-8 * 3600)
let b = now.addingTimeInterval(-3 * 3600)
let c = now.addingTimeInterval(-40 * 60)
func tray(_ at: Date, _ used: Any, _ org: String = "one", _ five: Any = 10) -> [String: Any] {
    ["org": org, "t": floor(at.timeIntervalSince1970 * 1000), "u": ["fh": five, "sd": used]]
}
func savePlan(_ samples: [[String: Any]], version: Int = 2) {
    try! JSONSerialization.data(withJSONObject: ["version": version, "samples": samples]).write(to: planURL, options: .atomic)
}
let savedHistory = ClaudeUsageHistory(url: folder.appendingPathComponent("account.json"))
savedHistory.record(snapshot(at: a, week: 10, fable: 20))
savedHistory.record(snapshot(at: b, week: 20, fable: 35))
let entries = [tray(a, 10), tray(b, 20), tray(c, 25), tray(now, 27)]
savePlan(entries.reversed())
let plan = ClaudePlanHistory.read(planURL, at: now)!
precondition(plan.samples.map(\.week) == [10, 20, 25, 27])
let page = ClaudeDesktopQuotaSnapshot(fiveHourUsed: 10, weekUsed: 25, fableUsed: 45, updatedAt: c)
let local = ClaudeLocalForecast(plan: plan, history: savedHistory, page: page, calibration: nil, now: now)
let localRows = local.rows(at: now, chinese: false, activity: nil)
precondition(abs(local.weekReset!.timeIntervalSince(reset)) < 0.001 && abs(local.fable!.reset.timeIntervalSince(fableReset)) < 0.001 && local.fable?.time == c, "use each meter’s own reset and independent reading time")
precondition(localRows.map(\.name) == ["Claude", "Fable · old"] && localRows.map(\.used) == [27, 45])
precondition(localRows.allSatisfy { $0.projectedUsed != nil } && localRows[1].tooltip.contains("Claude Desktop"))
precondition(local.snapshot.modelWindows.isEmpty, "an old Fable measurement must never carry the total's fresh timestamp")
let afterDay = local.rows(at: now.addingTimeInterval(day), chinese: false, activity: nil)
precondition(afterDay.allSatisfy { $0.projectedUsed == nil })
let modelReset = ClaudeDesktopQuotaSnapshot(fiveHourUsed: 10, weekUsed: 25, fableUsed: 2, updatedAt: c)
precondition(ClaudeLocalForecast(plan: plan, history: savedHistory, page: modelReset, calibration: nil, now: now).fable == nil)
let clean = ClaudeLocalForecast(plan: plan, history: nil, page: page, calibration: nil, now: now)
let cleanRows = clean.rows(at: now, chinese: false, activity: nil)
precondition(clean.weekReset == nil && cleanRows[0].endText == "~22% left in 24h" && cleanRows[0].pace == nil)
precondition(cleanRows[1].used == nil && cleanRows[1].projectedUsed == nil, "total usage cannot supply a model reading")
let conflicting = ClaudeUsageHistory(url: nil)
conflicting.record(snapshot(at: a, week: 10, fable: 20))
conflicting.record(snapshot(at: b, week: 20, fable: 35))
conflicting.record(snapshot(at: c, week: 22, fable: 40))
precondition(plan.matchingAccount(conflicting) == nil, "later conflicting overlap invalidates an apparent match")

let disabledAccount = menuSuite + ".local"
let localDefaults = UserDefaults(suiteName: disabledAccount)!
defer { localDefaults.removePersistentDomain(forName: disabledAccount) }
for key in [QuotaBalanceMenuController.localOnlyKey, QuotaBalanceMenuController.enabledKey, "claudeDesktopSyncEnabled"] {
    localDefaults.set(true, forKey: key)
}
localDefaults.set("credential_expired", forKey: "claudeQuotaLastOutcome")
localDefaults.set(try! JSONEncoder().encode(page), forKey: "claudeDesktopQuota")
let diagnostic = folder.appendingPathComponent("local-diagnostic.json")
let reader = QuotaBalanceMenuController(defaults: localDefaults, chinese: true, diagnosticURL: diagnostic,
    historyURL: folder.appendingPathComponent("account.json"), planHistoryURL: planURL,
    desktopAccess: { precondition(!localDefaults.bool(forKey: QuotaBalanceMenuController.localOnlyKey)); return false },
    credentialLoader: { fatalError("local mode must never load credentials") })
reader.menuWillOpen()
let reload = reader.settingsItem.submenu!.items.first { $0.title == "重读本机记录" }!
precondition(NSApp.sendAction(reload.action!, to: reload.target, from: reload))
precondition(reader.active && !reader.enabled && !reader.desktopSyncEnabled && reader.currentQuotas.claude == nil)
precondition(reader.displayedClaude(at: now).snapshot?.week?.remaining == 73)
let localDelegate = AppDelegate(quotaBalanceMenu: reader)
localDelegate.verifyLocalMenu()
let diag = try! JSONSerialization.jsonObject(with: Data(contentsOf: diagnostic)) as! [String: Any]
precondition(diag["claude_requests_started_this_process"] as? Int == 0 && diag["claude_desktop_accessibility"] as? Bool == false)

precondition(reader.saveCalibration(organization: "one", fableUsed: 60, reset: fableReset, now: now))
precondition(reader.saveCalibration(organization: "one", fableUsed: nil, reset: reset.addingTimeInterval(3600), now: now))
precondition(reader.localForecast?.fable?.used == 60 && reader.localForecast?.resetSource == .manual)
precondition(!reader.saveCalibration(organization: "one", fableUsed: 101, reset: fableReset, now: now))
precondition(!reader.saveCalibration(organization: "one", fableUsed: 30, reset: now, now: now))
let reloadedLocal = QuotaBalanceMenuController(defaults: localDefaults, planHistoryURL: planURL)
precondition(reloadedLocal.localForecast?.fable?.used == 60 && reloadedLocal.localForecast?.resetSource == .manual)
let switched = entries + [tray(now.addingTimeInterval(1), 11, "two")]
savePlan(switched)
reader.refreshIfDue(now: now.addingTimeInterval(2))
precondition(reader.localForecast?.fable == nil && reader.localForecast?.weekReset == nil)
precondition(!reader.saveCalibration(organization: "one", fableUsed: 50, reset: fableReset, now: now.addingTimeInterval(2)))
savePlan(entries + [tray(now.addingTimeInterval(1), 1)])
reader.refreshIfDue(now: now.addingTimeInterval(2))
precondition(reader.localForecast?.weekReset == nil, "a total drop invalidates a total reset calibration")
savePlan(entries, version: 3)
reader.menuWillOpen()
precondition(reader.displayedClaude(at: now).snapshot == nil && reader.localForecast == nil)
reader.setLocalOnly(false)
precondition(reader.enabled && reader.desktopSyncEnabled, "leaving local mode restores prior choices")

savePlan([tray(now, true)])
precondition(ClaudePlanHistory.read(planURL, at: now) == nil)
savePlan([tray(now, 103)])
precondition(ClaudePlanHistory.read(planURL, at: now) == nil)
savePlan([tray(now, 3, "one"), tray(now, 3, "two")])
precondition(ClaudePlanHistory.read(planURL, at: now) == nil)
savePlan([tray(a, 12), tray(now, 15, "one", true), tray(now.addingTimeInterval(60), 55)])
precondition(ClaudePlanHistory.read(planURL, at: now)?.latest.fiveHour == nil)
precondition(ClaudePlanHistory.read(planURL, at: now)?.latest.week == 15)
try Data(repeating: 32, count: 256 * 1024 + 1).write(to: planURL)
precondition(ClaudePlanHistory.read(planURL, at: now) == nil)
try FileManager.default.removeItem(at: planURL)
precondition(ClaudePlanHistory.read(planURL, at: now) == nil)

// Two closely bracketed, seven-day-separated drops predict a boundary. One isolated redemption does not.
let lastDrop = now.addingTimeInterval(-2 * day)
let firstDrop = lastDrop.addingTimeInterval(-7 * day)
let recurring = [tray(firstDrop.addingTimeInterval(-1800), 31), tray(firstDrop, 1),
                 tray(lastDrop.addingTimeInterval(-1800), 44), tray(lastDrop, 0), tray(now, 14)]
savePlan(recurring)
let repeated = ClaudePlanHistory.read(planURL, at: now)!
precondition(abs(repeated.estimatedReset(at: now)!.timeIntervalSince(lastDrop.addingTimeInterval(7 * day - 900))) < 0.002)
precondition(repeated.estimatedReset(at: now.addingTimeInterval(6 * day)) == nil)
savePlan(Array(recurring.dropFirst(2)))
precondition(ClaudePlanHistory.read(planURL, at: now)!.estimatedReset(at: now) == nil)

// A new week replaces the old samples instead of mixing windows.
let rollover = ClaudeUsageHistory(url: nil)
rollover.record(snapshot(at: now, week: 40, fable: nil))
let nextWeek = ProviderQuotaSnapshot(checkedAt: reset.addingTimeInterval(3600), fiveHour: nil,
                                     week: ProviderQuotaWindow(used: 1, resetsAt: reset.addingTimeInterval(7 * day)))
rollover.record(nextWeek)
precondition(rollover.windows["seven_day"]?.samples.count == 1)
precondition(ClaudeForecast.rows(history: rollover, now: reset.addingTimeInterval(3600), chinese: false)[0].endText == "building")

// An unused model window (0%, no reset time) is not a model-limit concern.
precondition(unused.notStarted && !unused.needsAttention(at: now))
precondition(ProviderQuotaWindow(used: 3, resetsAt: nil).needsAttention(at: now))

let codexRow = PaceRow(name: "Codex", color: .systemGray, used: 13, projectedUsed: 97, pace: 0.124,
                       endText: "重置时剩 3%", tone: .systemOrange, tooltip: "Codex")
let zhRows = [codexRow] + ClaudeForecast.rows(history: weightedHistory, now: saturday, chinese: true, activitySchedule: schedule)
let view = PaceBarsView(frame: NSRect(x: 0, y: 0, width: 460, height: PaceBarsView.height(rows: zhRows.count)))
view.title = "周预测"
view.legend = ("已用", "预计", "均匀配速")
view.rows = zhRows
view.installTooltips()
precondition(PaceBarsView.endX + PaceBarsView.endWidth <= 448, "end text stays inside the menu width")
let canvas = NSView(frame: view.frame)
canvas.wantsLayer = true
canvas.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
canvas.addSubview(view)
let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
canvas.cacheDisplay(in: canvas.bounds, to: rep)
if CommandLine.arguments.count > 2 {
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
// Count pixels close to each series' own color, so the check follows the system palette.
func near(_ c: NSColor, _ target: NSColor) -> Bool {
    guard let t = target.usingColorSpace(.sRGB) else { return false }
    return abs(c.redComponent - t.redComponent) < 0.12 && abs(c.greenComponent - t.greenComponent) < 0.12
        && abs(c.blueComponent - t.blueComponent) < 0.12 && c.alphaComponent > 0.5
}
let lineColors = [NSColor.systemPurple]
var counts = Array(repeating: 0, count: lineColors.count)
for x in stride(from: 0, to: rep.pixelsWide, by: 1) {
    for y in stride(from: 0, to: rep.pixelsHigh, by: 1) {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        for (i, color) in lineColors.enumerated() where near(c, color) { counts[i] += 1 }
    }
}
precondition(counts[0] > 40, "the Claude used bar must be drawn \(counts)")
print("Codex-only menu, account and local Claude forecasts, calibration, rollover, isolation and pace bars: ok")
'''

with tempfile.TemporaryDirectory() as folder:
    folder = Path(folder)
    render = folder / "main.swift"
    render.write_text(text.replace(app_entrypoint, harness), encoding="utf-8")
    binary = folder / "check-claude-forecast"
    subprocess.run(["swiftc", str(render),
                    *[str(p) for p in sorted(source.parent.glob("*.swift")) if p != source],
                    "-framework", "AppKit", "-o", str(binary)], check=True)
    command = [str(binary), str(folder)]
    if preview := os.environ.get("CODEX_BATTERY_FORECAST_PREVIEW"):
        target = Path(preview).resolve()
        target.parent.mkdir(parents=True, exist_ok=True)
        command.append(str(target))
    subprocess.run(command, check=True)
