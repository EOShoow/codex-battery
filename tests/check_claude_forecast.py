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
print("Codex-only menu isolation, Claude weekly history, rollover, privacy and pace bars: ok")
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
