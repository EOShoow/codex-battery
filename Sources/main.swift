import AppKit
import Foundation

final class QuotaIconView: NSView {
    var fiveHour = 0
    var week = 0
    var tooltipText = "Codex quota" {
        didSet { toolTip = tooltipText }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = tooltipText
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        toolTip = tooltipText
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.shouldAntialias = true
        let size = min(bounds.width, bounds.height)
        let origin = NSPoint(
            x: bounds.midX - size / 2,
            y: bounds.midY - size / 2
        )
        let square = NSRect(origin: origin, size: NSSize(width: size, height: size)).insetBy(dx: 2.5, dy: 2.5)
        drawRing(in: square, remaining: week, width: 2.7)
        drawRing(in: square.insetBy(dx: 3.5, dy: 3.5), remaining: fiveHour, width: 2.7)
    }

    private func drawRing(in rect: NSRect, remaining: Int, width: CGFloat) {
        let base = NSBezierPath(ovalIn: rect)
        base.lineWidth = width
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        base.stroke()

        let clamped = max(0, min(100, remaining))
        guard clamped > 0 else { return }

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: 90,
            endAngle: 90 - CGFloat(clamped) / 100 * 360,
            clockwise: true
        )
        arc.lineWidth = width
        arc.lineCapStyle = .round
        NSColor.labelColor.withAlphaComponent(0.86).setStroke()
        arc.stroke()
    }
}

struct QuotaInfo: Decodable {
    let ok: Bool
    let error: String?
    let timestamp: String?
    let planType: String?
    let limitId: String?
    let limitName: String?
    let primaryUsed: Double?
    let secondaryUsed: Double?
    let primaryReset: Int?
    let secondaryReset: Int?
    let title: String?
    let model: String?
    let effort: String?
    let totalTokens: Int?
    let todayTokens: Int?
    let todayVs3DayAvg: Double?
    let weeklyBurnPctPerHour: Double?
    let weeklyEtaHours: Double?
    let weeklyBudgetRatio: Double?
    let weeklyDaysEarly: Double?
    let risk: String?
    let topThread: String?
    let topThreadTokens: Int?
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let iconView = QuotaIconView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
    private let menu = NSMenu()
    private let fiveHourItem = NSMenuItem(title: "5h -", action: nil, keyEquivalent: "")
    private let weekItem = NSMenuItem(title: "1w -", action: nil, keyEquivalent: "")
    private let todayItem = NSMenuItem(title: "Today -", action: nil, keyEquivalent: "")
    private let forecastItem = NSMenuItem(title: "Forecast -", action: nil, keyEquivalent: "")
    private let topItem = NSMenuItem(title: "Top -", action: nil, keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
    private let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
    private let useChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
    private var refreshTimer: Timer?
    private var isRefreshing = false

    private func t(_ zh: String, _ en: String) -> String {
        useChinese ? zh : en
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.length = 24
        if let button = statusItem.button {
            iconView.frame = button.bounds
            iconView.autoresizingMask = [.width, .height]
            button.addSubview(iconView)
            button.toolTip = "Codex Battery"
        }

        refreshItem.target = self
        quitItem.target = self
        menu.delegate = self
        menu.addItem(fiveHourItem)
        menu.addItem(weekItem)
        menu.addItem(todayItem)
        menu.addItem(forecastItem)
        menu.addItem(topItem)
        menu.addItem(.separator())
        menu.addItem(refreshItem)
        menu.addItem(quitItem)
        statusItem.menu = menu

        refreshNow()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 300,
            target: self,
            selector: #selector(refreshNow),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        fiveHourItem.title = t("刷新中...", "Refreshing...")
        weekItem.title = t("1周 -", "1w -")
        todayItem.title = t("今日 -", "Today -")
        forecastItem.title = t("预测 -", "Forecast -")
        topItem.title = "Top -"
        DispatchQueue.global(qos: .utility).async {
            let info = Self.readQuota()
            DispatchQueue.main.async {
                self.render(info)
                self.isRefreshing = false
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshNow()
    }

    private func render(_ info: QuotaInfo) {
        guard info.ok else {
            let message = info.error ?? "No quota data"
            iconView.fiveHour = 0
            iconView.week = 0
            iconView.needsDisplay = true
            fiveHourItem.title = message
            weekItem.title = t("1周 -", "1w -")
            todayItem.title = t("今日 -", "Today -")
            forecastItem.title = t("预测 -", "Forecast -")
            topItem.title = "Top -"
            iconView.tooltipText = message
            return
        }

        let fiveHour = max(0, 100 - Int(round(info.primaryUsed ?? 0)))
        let week = max(0, 100 - Int(round(info.secondaryUsed ?? 0)))
        iconView.fiveHour = fiveHour
        iconView.week = week
        iconView.needsDisplay = true

        let primaryReset = formatReset(info.primaryReset)
        let secondaryReset = formatReset(info.secondaryReset)
        let today = info.todayTokens.map { Self.formatCompact($0) } ?? "-"
        let ratio = info.todayVs3DayAvg.map { String(format: "%.1fx", $0) } ?? "-"
        let weeklyPrediction = formatWeeklyPrediction(
            budgetRatio: info.weeklyBudgetRatio,
            daysEarly: info.weeklyDaysEarly
        )
        let todayFlag = formatTodayFlag(info.todayVs3DayAvg)
        let topThread = info.topThread ?? "-"
        let topThreadTokens = info.topThreadTokens.map { Self.formatCompact($0) } ?? "-"
        let detail = useChinese ? """
        5小时剩余: \(fiveHour)%  \(primaryReset)
        1周剩余: \(week)%  \(secondaryReset)
        今日: \(today)  \(ratio)\(todayFlag)
        周预测: \(weeklyPrediction)
        Top: \(topThread)  \(topThreadTokens)
        """ : """
        5h left: \(fiveHour)%  \(primaryReset)
        1w left: \(week)%  \(secondaryReset)
        Today: \(today)  \(ratio)\(todayFlag)
        Weekly forecast: \(weeklyPrediction)
        Top: \(topThread)  \(topThreadTokens)
        """
        fiveHourItem.title = t("5小时剩余  \(fiveHour)%    \(primaryReset)", "5h left     \(fiveHour)%    \(primaryReset)")
        weekItem.title = t("1周剩余    \(week)%    \(secondaryReset)", "1w left     \(week)%    \(secondaryReset)")
        todayItem.title = t("今日消耗    \(today)    \(ratio)\(todayFlag)", "Today burn  \(today)    \(ratio)\(todayFlag)")
        forecastItem.title = t("周预测      \(weeklyPrediction)", "Forecast    \(weeklyPrediction)")
        topItem.title = "Top         \(topThread)    \(topThreadTokens)"
        iconView.tooltipText = detail
    }

    private static func readQuota() -> QuotaInfo {
        let script = pythonScript
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return try JSONDecoder().decode(QuotaInfo.self, from: data)
        } catch {
            return QuotaInfo(
                ok: false,
                error: error.localizedDescription,
                timestamp: nil,
                planType: nil,
                limitId: nil,
                limitName: nil,
                primaryUsed: nil,
                secondaryUsed: nil,
                primaryReset: nil,
                secondaryReset: nil,
                title: nil,
                model: nil,
                effort: nil,
                totalTokens: nil,
                todayTokens: nil,
                todayVs3DayAvg: nil,
                weeklyBurnPctPerHour: nil,
                weeklyEtaHours: nil,
                weeklyBudgetRatio: nil,
                weeklyDaysEarly: nil,
                risk: nil,
                topThread: nil,
                topThreadTokens: nil
            )
        }
    }

    private func formatReset(_ seconds: Int?) -> String {
        guard let seconds else { return "-" }
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: useChinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : (useChinese ? "M月d日 HH:mm" : "MMM d HH:mm")
        return formatter.string(from: date)
    }

    private static func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func formatCompact(_ value: Int) -> String {
        let double = Double(value)
        if value >= 1_000_000 {
            return String(format: "%.1fM", double / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0fK", double / 1_000)
        }
        return "\(value)"
    }

    private static func formatEta(_ hours: Double) -> String {
        if !hours.isFinite || hours <= 0 {
            return "-"
        }
        if hours < 24 {
            return String(format: "%.0fh", hours)
        }
        return String(format: "%.1fd", hours / 24)
    }

    private func formatWeeklyPrediction(budgetRatio: Double?, daysEarly: Double?) -> String {
        guard let budgetRatio, budgetRatio.isFinite else {
            return "-"
        }
        let ratio = useChinese ? String(format: "%.1fx预算", budgetRatio) : String(format: "%.1fx budget", budgetRatio)
        if let daysEarly, daysEarly.isFinite, daysEarly > 0 {
            if daysEarly < 1 {
                return useChinese
                    ? "提前\(String(format: "%.0f", daysEarly * 24))小时耗尽  \(ratio)"
                    : "runs out \(String(format: "%.0f", daysEarly * 24))h early  \(ratio)"
            }
            return useChinese
                ? "提前\(String(format: "%.1f", daysEarly))天耗尽  \(ratio)"
                : "runs out \(String(format: "%.1f", daysEarly))d early  \(ratio)"
        }
        if budgetRatio <= 1.05 {
            return useChinese ? "可撑到重置  \(ratio)" : "lasts to reset  \(ratio)"
        }
        return useChinese ? "偏快但可撑  \(ratio)" : "fast but okay  \(ratio)"
    }

    private func formatTodayFlag(_ ratio: Double?) -> String {
        guard let ratio, ratio.isFinite else {
            return ""
        }
        if ratio >= 5 {
            return useChinese ? "    今日冲高" : "    spike today"
        }
        if ratio >= 2 {
            return useChinese ? "    偏快" : "    fast"
        }
        return ""
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private let pythonScript = #"""
import json
import os
import pathlib
import sqlite3
import time
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

home = pathlib.Path.home()
db_path = home / ".codex" / "state_5.sqlite"
tz = timezone(timedelta(hours=8))
now = datetime.now(tz)
today = now.date()

def fail(message):
    print(json.dumps({"ok": False, "error": message}))
    raise SystemExit(0)

if not db_path.exists():
    fail("No Codex state database found")

def reversed_lines(path, block_size=65536):
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        position = f.tell()
        buffer = b""
        while position > 0:
            read_size = min(block_size, position)
            position -= read_size
            f.seek(position)
            chunk = f.read(read_size)
            lines = (chunk + buffer).split(b"\n")
            buffer = lines[0]
            for line in reversed(lines[1:]):
                if line:
                    yield line.decode("utf-8", "ignore")
        if buffer:
            yield buffer.decode("utf-8", "ignore")

def parse_ts(value):
    if not value:
        return None
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(value).astimezone(tz)
    except Exception:
        return None

def compact_title(value):
    return (value or "Unknown").replace("\n", " ")[:28]

try:
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    rows = con.execute(
        """
        SELECT id, rollout_path, title, model, reasoning_effort
        FROM threads
        WHERE rollout_path IS NOT NULL
        ORDER BY updated_at DESC
        LIMIT 50
        """
    ).fetchall()
except Exception as exc:
    fail(f"Cannot read Codex state: {exc}")

latest = None
daily = defaultdict(Counter)
top_by_thread = defaultdict(Counter)
weekly_points = []
rate_snapshots = []

for thread_id, rollout_path, title, model, effort in rows:
    if not rollout_path:
        continue
    path = pathlib.Path(rollout_path)
    if not path.exists():
        continue
    events = []
    try:
        for line in path.read_text(errors="ignore").splitlines():
            try:
                obj = json.loads(line)
            except Exception:
                continue
            payload = obj.get("payload") or {}
            if payload.get("type") != "token_count":
                continue
            ts = parse_ts(obj.get("timestamp"))
            if not ts:
                continue
            rate_limits = payload.get("rate_limits")
            info = payload.get("info") or {}
            total = info.get("total_token_usage") or {}
            if "total_tokens" not in total:
                continue
            events.append((ts, obj, rate_limits, total))
        events.sort(key=lambda item: item[0])
        prev = None
        seen = set()
        for ts, obj, rate_limits, total in events:
            state = tuple(int(total.get(k, 0) or 0) for k in ("input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"))
            if state in seen:
                continue
            seen.add(state)
            if rate_limits:
                primary = rate_limits.get("primary") or {}
                secondary = rate_limits.get("secondary") or {}
                rate_snapshots.append({
                    "ts": ts,
                    "timestamp": obj.get("timestamp"),
                    "planType": rate_limits.get("plan_type"),
                    "limitId": rate_limits.get("limit_id"),
                    "limitName": rate_limits.get("limit_name"),
                    "primaryUsed": primary.get("used_percent"),
                    "secondaryUsed": secondary.get("used_percent"),
                    "primaryReset": primary.get("resets_at"),
                    "secondaryReset": secondary.get("resets_at"),
                    "title": title,
                    "model": model,
                    "effort": effort,
                    "totalTokens": total.get("total_tokens")
                })
                used = secondary.get("used_percent")
                if used is not None:
                    weekly_points.append((ts, float(used)))
                if latest is None or ts > latest["ts"]:
                    latest = {
                        "ts": ts,
                        "timestamp": obj.get("timestamp"),
                        "planType": rate_limits.get("plan_type"),
                        "limitId": rate_limits.get("limit_id"),
                        "limitName": rate_limits.get("limit_name"),
                        "primaryUsed": primary.get("used_percent"),
                        "secondaryUsed": secondary.get("used_percent"),
                        "primaryReset": primary.get("resets_at"),
                        "secondaryReset": secondary.get("resets_at"),
                        "title": title,
                        "model": model,
                        "effort": effort,
                        "totalTokens": total.get("total_tokens")
                    }
            if prev is None:
                diff = int(total.get("total_tokens", 0) or 0)
            else:
                diff = max(0, int(total.get("total_tokens", 0) or 0) - int(prev.get("total_tokens", 0) or 0))
            prev = total
            if diff <= 0:
                continue
            day = ts.date()
            if day >= today - timedelta(days=10):
                daily[day]["total_tokens"] += diff
                daily[day]["turns"] += 1
                label = compact_title(title)
                top_by_thread[(day, label)]["total_tokens"] += diff
                top_by_thread[(day, label)]["turns"] += 1
    except Exception:
        continue

if not latest:
    fail("No recent Codex rate-limit data found")

# Multiple active Codex threads can write rate-limit snapshots with the same
# reset window but stale used_percent values. Within one reset window usage
# should be monotonic, so prefer the highest recent value over a lower snapshot
# that merely has a newer timestamp.
fresh_cutoff = now - timedelta(minutes=15)
now_epoch = now.timestamp()
same_limit = [
    snap for snap in rate_snapshots
    if snap["ts"] >= fresh_cutoff
    and snap.get("planType") == latest.get("planType")
    and snap.get("limitId") == latest.get("limitId")
]
primary_candidates = [
    snap for snap in same_limit
    if snap.get("primaryReset") is not None
    and float(snap.get("primaryReset") or 0) > now_epoch
    and snap.get("primaryUsed") is not None
]
secondary_candidates = [
    snap for snap in same_limit
    if snap.get("secondaryReset") is not None
    and float(snap.get("secondaryReset") or 0) > now_epoch
    and snap.get("secondaryUsed") is not None
]
if not primary_candidates:
    primary_candidates = [
        snap for snap in same_limit
        if snap.get("primaryReset") == latest.get("primaryReset")
        and snap.get("primaryUsed") is not None
    ]
if not secondary_candidates:
    secondary_candidates = [
        snap for snap in same_limit
        if snap.get("secondaryReset") == latest.get("secondaryReset")
        and snap.get("secondaryUsed") is not None
    ]
if primary_candidates:
    best_primary = max(primary_candidates, key=lambda snap: (float(snap.get("primaryReset") or 0), float(snap.get("primaryUsed") or 0), snap["ts"]))
    latest["primaryUsed"] = best_primary.get("primaryUsed")
    latest["primaryReset"] = best_primary.get("primaryReset")
if secondary_candidates:
    best_secondary = max(secondary_candidates, key=lambda snap: (float(snap.get("secondaryReset") or 0), float(snap.get("secondaryUsed") or 0), snap["ts"]))
    latest["secondaryUsed"] = best_secondary.get("secondaryUsed")
    latest["secondaryReset"] = best_secondary.get("secondaryReset")

today_tokens = int(daily[today]["total_tokens"])
previous_active = [
    (day, int(counter["total_tokens"]))
    for day, counter in sorted(daily.items())
    if day < today and counter["total_tokens"] > 0
]
prev3 = previous_active[-3:]
prev3_avg = sum(total for _, total in prev3) / len(prev3) if prev3 else 0
today_vs_3 = (today_tokens / prev3_avg) if prev3_avg else None

today_threads = [
    (label, int(counter["total_tokens"]))
    for (day, label), counter in top_by_thread.items()
    if day == today
]
today_threads.sort(key=lambda item: item[1], reverse=True)
top_thread, top_thread_tokens = today_threads[0] if today_threads else (None, None)

weekly_points.sort(key=lambda item: item[0])
cutoff = now - timedelta(hours=3)
recent_weekly = [(ts, used) for ts, used in weekly_points if ts >= cutoff]
weekly_burn = None
weekly_eta = None
weekly_budget_ratio = None
weekly_days_early = None
if len(recent_weekly) >= 2:
    first_ts, first_used = recent_weekly[0]
    last_ts, last_used = recent_weekly[-1]
    hours = max((last_ts - first_ts).total_seconds() / 3600, 1 / 60)
    delta = max(0.0, last_used - first_used)
    weekly_burn = delta / hours
    latest_remaining = max(0.0, 100.0 - float(latest.get("secondaryUsed") or 0))
    if weekly_burn > 0:
        weekly_eta = latest_remaining / weekly_burn

reset_at = latest.get("secondaryReset")
used_week = latest.get("secondaryUsed")
if reset_at and used_week is not None:
    try:
        used_week = float(used_week)
        reset_at = float(reset_at)
        week_seconds = 7 * 24 * 3600
        start_at = reset_at - week_seconds
        now_at = now.timestamp()
        elapsed = max(0.0, min(week_seconds, now_at - start_at))
        expected_used = elapsed / week_seconds * 100.0 if elapsed > 0 else 0.0
        if expected_used >= 0.5:
            weekly_budget_ratio = used_week / expected_used
        if used_week > 0 and elapsed > 0:
            exhaust_at = start_at + 100.0 * elapsed / used_week
            if exhaust_at < reset_at:
                weekly_days_early = (reset_at - exhaust_at) / 86400
    except Exception:
        pass

remaining_week = max(0.0, 100.0 - float(latest.get("secondaryUsed") or 0))
risk = "OK"
if remaining_week < 15 or (weekly_days_early is not None and weekly_days_early >= 1):
    risk = "CRITICAL"
elif (weekly_days_early is not None and weekly_days_early > 0) or (today_vs_3 is not None and today_vs_3 >= 5):
    risk = "HOT"
elif (weekly_budget_ratio is not None and weekly_budget_ratio >= 1.2) or (today_vs_3 is not None and today_vs_3 >= 2):
    risk = "FAST"

out = dict(latest)
out.pop("ts", None)
out.update({
    "ok": True,
    "todayTokens": today_tokens,
    "todayVs3DayAvg": today_vs_3,
    "weeklyBurnPctPerHour": weekly_burn,
    "weeklyEtaHours": weekly_eta,
    "weeklyBudgetRatio": weekly_budget_ratio,
    "weeklyDaysEarly": weekly_days_early,
    "risk": risk,
    "topThread": top_thread,
    "topThreadTokens": top_thread_tokens
})
print(json.dumps(out, ensure_ascii=False))
raise SystemExit(0)

for thread_id, rollout_path, title, model, effort in []:
    if not rollout_path:
        continue
    path = pathlib.Path(rollout_path)
    if not path.exists():
        continue
    try:
        for line in reversed_lines(path):
            try:
                obj = json.loads(line)
            except Exception:
                continue
            payload = obj.get("payload") or {}
            if payload.get("type") != "token_count":
                continue
            rate_limits = payload.get("rate_limits")
            info = payload.get("info") or {}
            if not rate_limits:
                continue
            primary = rate_limits.get("primary") or {}
            secondary = rate_limits.get("secondary") or {}
            total = info.get("total_token_usage") or {}
            print(json.dumps({
                "ok": True,
                "timestamp": obj.get("timestamp"),
                "planType": rate_limits.get("plan_type"),
                "limitId": rate_limits.get("limit_id"),
                "limitName": rate_limits.get("limit_name"),
                "primaryUsed": primary.get("used_percent"),
                "secondaryUsed": secondary.get("used_percent"),
                "primaryReset": primary.get("resets_at"),
                "secondaryReset": secondary.get("resets_at"),
                "title": title,
                "model": model,
                "effort": effort,
                "totalTokens": total.get("total_tokens")
            }, ensure_ascii=False))
            raise SystemExit(0)
    except SystemExit:
        raise
    except Exception:
        continue

fail("No recent Codex rate-limit data found")
"""#

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
