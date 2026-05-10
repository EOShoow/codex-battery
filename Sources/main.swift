import AppKit
import Foundation

final class QuotaIconView: NSView {
    var fiveHour = 0
    var week = 0
    var serviceTier = "standard"
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
        drawCenterMark(in: square.insetBy(dx: 7.0, dy: 7.0), serviceTier: serviceTier)
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

    private func drawCenterMark(in rect: NSRect, serviceTier: String) {
        if Self.isStandardServiceTier(serviceTier) {
            return
        }
        drawBolt(in: rect)
    }

    private static func isStandardServiceTier(_ serviceTier: String) -> Bool {
        let normalized = serviceTier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "standard" || normalized == "default" || normalized == "none" || normalized == "null"
    }

    private func drawBolt(in rect: NSRect) {
        let x = rect.midX
        let y = rect.midY
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: x + 0.9, y: y + 4.0))
        bolt.line(to: NSPoint(x: x - 3.0, y: y - 0.2))
        bolt.line(to: NSPoint(x: x - 0.5, y: y - 0.2))
        bolt.line(to: NSPoint(x: x - 1.0, y: y - 4.0))
        bolt.line(to: NSPoint(x: x + 3.0, y: y + 0.6))
        bolt.line(to: NSPoint(x: x + 0.5, y: y + 0.6))
        bolt.close()
        NSColor.labelColor.withAlphaComponent(0.9).setFill()
        bolt.fill()
    }
}

struct QuotaInfo: Decodable {
    let ok: Bool
    let error: String?
    let timestamp: String?
    let planType: String?
    let limitId: String?
    let limitName: String?
    let serviceTier: String?
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
    let weeklyActiveBudgetRatio: Double?
    let risk: String?
    let topThread: String?
    let topThreadTokens: Int?
    let activeThreads: Int?
    let activeWindowSeconds: Int?
}

struct ActivityProbeInfo: Decodable {
    let ok: Bool
    let error: String?
    let timestamp: String?
    let sourceUpdatedAt: String?
    let activeThreads: Int?
    let activeWindowSeconds: Int?
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let menuWidth: CGFloat = 460
    private static let syncOnMenuOpenKey = "syncOnMenuOpen"
    private static let activeRefreshMinutesKey = "activeRefreshMinutes"
    private static let idleRefreshMinutesKey = "idleRefreshMinutes"
    private static let failureRetryMinutesKey = "failureRetryMinutes"
    private static let activityProbeSecondsKey = "activityProbeSeconds"
    private static let defaultActiveRefreshMinutes = 5
    private static let defaultIdleRefreshMinutes = 30
    private static let defaultFailureRetryMinutes = 5
    private static let defaultActivityProbeSeconds = 60
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let iconView = QuotaIconView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
    private let menu = NSMenu()
    private let fiveHourItem = NSMenuItem(title: "5h -", action: nil, keyEquivalent: "")
    private let weekItem = NSMenuItem(title: "1w -", action: nil, keyEquivalent: "")
    private let todayItem = NSMenuItem(title: "Today -", action: nil, keyEquivalent: "")
    private let forecastItem = NSMenuItem(title: "Forecast -", action: nil, keyEquivalent: "")
    private let topItem = NSMenuItem(title: "Top -", action: nil, keyEquivalent: "")
    private let activityItem = NSMenuItem(title: "Activity -", action: nil, keyEquivalent: "")
    private let updatedItem = NSMenuItem(title: "Data at -", action: nil, keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "Refresh", action: nil, keyEquivalent: "")
    private let syncOnOpenItem = NSMenuItem(title: "Sync on open Off", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
    private let useChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
    private var refreshTimer: Timer?
    private var activityProbeTimer: Timer?
    private var isRefreshing = false
    private var nextRefreshInterval: TimeInterval = 300
    private var lastGoodInfo: QuotaInfo?
    private var lastKnownSourceUpdatedAt: String?
    private var lastProbeTriggeredRefreshAt: Date?

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

        configureActionItem(refreshItem, title: t("刷新", "Refresh"), action: #selector(refreshNow))
        configureActionItem(syncOnOpenItem, title: syncOnOpenTitle(), action: #selector(toggleSyncOnOpen))
        configureActionItem(quitItem, title: t("退出", "Quit"), action: #selector(quit))
        menu.delegate = self
        menu.addItem(fiveHourItem)
        menu.addItem(weekItem)
        menu.addItem(todayItem)
        menu.addItem(forecastItem)
        menu.addItem(topItem)
        menu.addItem(activityItem)
        menu.addItem(updatedItem)
        menu.addItem(.separator())
        menu.addItem(refreshItem)
        menu.addItem(syncOnOpenItem)
        menu.addItem(quitItem)
        statusItem.menu = menu

        refreshNow()
        startActivityProbeTimer()
    }

    @objc private func refreshNow() {
        setInfoItem(updatedItem, label: t("数据于", "Data at"), value: t("刷新中...", "Refreshing..."))
        guard !isRefreshing else { return }
        isRefreshing = true
        setInfoItem(fiveHourItem, label: t("5小时剩余", "5h left"), value: t("刷新中...", "Refreshing..."))
        setInfoItem(weekItem, label: t("1周剩余", "1w left"), value: "-")
        setInfoItem(todayItem, label: t("今日消耗", "Today burn"), value: "-")
        setInfoItem(forecastItem, label: t("周预测", "Forecast"), value: "-")
        setInfoItem(topItem, label: "Top", value: "-")
        setInfoItem(activityItem, label: t("后台活动", "Activity"), value: "-")
        DispatchQueue.global(qos: .utility).async {
            let info = Self.readQuota()
            DispatchQueue.main.async {
                if info.ok {
                    self.lastGoodInfo = info
                    self.lastKnownSourceUpdatedAt = info.timestamp
                    self.render(info)
                } else if let cached = self.lastGoodInfo {
                    self.render(cached)
                    self.setInfoItem(
                        self.updatedItem,
                        label: self.t("旧数据", "Stale"),
                        value: self.formatDataTimestamp(cached.timestamp)
                    )
                    self.iconView.tooltipText = info.error ?? self.t("读取失败，显示上次成功数据", "Read failed, showing last successful data")
                } else {
                    self.render(info)
                }
                self.isRefreshing = false
                self.scheduleNextRefresh(for: info)
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        configureActionItem(syncOnOpenItem, title: syncOnOpenTitle(), action: #selector(toggleSyncOnOpen))
        if UserDefaults.standard.bool(forKey: Self.syncOnMenuOpenKey) {
            refreshNow()
        }
    }

    private func render(_ info: QuotaInfo) {
        guard info.ok else {
            let message = info.error ?? "No quota data"
            iconView.fiveHour = 0
            iconView.week = 0
            iconView.serviceTier = "standard"
            iconView.needsDisplay = true
            setInfoItem(fiveHourItem, label: t("错误", "Error"), value: message)
            setInfoItem(weekItem, label: t("1周剩余", "1w left"), value: "-")
            setInfoItem(todayItem, label: t("今日消耗", "Today burn"), value: "-")
            setInfoItem(forecastItem, label: t("周预测", "Forecast"), value: "-")
            setInfoItem(topItem, label: "Top", value: "-")
            setInfoItem(activityItem, label: t("后台活动", "Activity"), value: "-")
            setInfoItem(updatedItem, label: t("数据于", "Data at"), value: "-")
            iconView.tooltipText = message
            return
        }

        let primaryExpired = isResetExpired(info.primaryReset)
        let secondaryExpired = isResetExpired(info.secondaryReset)
        let fiveHour = primaryExpired ? 100 : max(0, 100 - Int(round(info.primaryUsed ?? 0)))
        let week = secondaryExpired ? 100 : max(0, 100 - Int(round(info.secondaryUsed ?? 0)))
        iconView.fiveHour = fiveHour
        iconView.week = week
        iconView.serviceTier = info.serviceTier ?? "standard"
        iconView.needsDisplay = true

        let primaryReset = formatReset(info.primaryReset)
        let secondaryReset = formatReset(info.secondaryReset)
        let today = info.todayTokens.map { Self.formatCompact($0) } ?? "-"
        let ratio = info.todayVs3DayAvg.map { String(format: "%.1fx", $0) } ?? "-"
        let weeklyPrediction = formatWeeklyPrediction(
            budgetRatio: info.weeklyBudgetRatio,
            activeBudgetRatio: info.weeklyActiveBudgetRatio,
            daysEarly: info.weeklyDaysEarly
        )
        let todayFlag = formatTodayFlag(info.todayVs3DayAvg)
        let topThread = info.topThread ?? "-"
        let topThreadTokens = info.topThreadTokens.map { Self.formatCompact($0) } ?? "-"
        let activity = formatActivity(info)
        let dataAt = formatDataTimestamp(info.timestamp)
        let detail = useChinese ? """
        5小时剩余: \(fiveHour)%  \(primaryReset)
        1周剩余: \(week)%  \(secondaryReset)
        今日: \(today)  \(ratio)\(todayFlag)
        周预测: \(weeklyPrediction.status)  \(weeklyPrediction.detail ?? "")
        Top: \(topThread)  \(topThreadTokens)
        后台活动: \(activity)
        数据于: \(dataAt)
        """ : """
        5h left: \(fiveHour)%  \(primaryReset)
        1w left: \(week)%  \(secondaryReset)
        Today: \(today)  \(ratio)\(todayFlag)
        Weekly forecast: \(weeklyPrediction.status)  \(weeklyPrediction.detail ?? "")
        Top: \(topThread)  \(topThreadTokens)
        Activity: \(activity)
        Data at: \(dataAt)
        """
        setInfoItem(fiveHourItem, label: t("5小时剩余", "5h left"), value: "\(fiveHour)%", detail: primaryReset)
        setInfoItem(weekItem, label: t("1周剩余", "1w left"), value: "\(week)%", detail: secondaryReset)
        setInfoItem(todayItem, label: t("今日消耗", "Today burn"), value: today, detail: "\(ratio)\(todayFlag)")
        setInfoItem(forecastItem, label: t("周预测", "Forecast"), value: weeklyPrediction.status, detail: weeklyPrediction.detail)
        setInfoItem(topItem, label: "Top", value: topThread, detail: topThreadTokens)
        setInfoItem(activityItem, label: t("后台活动", "Activity"), value: activity)
        setInfoItem(updatedItem, label: t("数据于", "Data at"), value: dataAt)
        iconView.tooltipText = detail
    }

    private func setInfoItem(_ item: NSMenuItem, label: String, value: String, detail: String? = nil) {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: Self.menuWidth, height: 30))
        let tooltip = detail.map { "\(label)  \(value)  \($0)" } ?? "\(label)  \(value)"
        row.toolTip = tooltip

        let labelField = makeLabel(label, frame: NSRect(x: 16, y: 5, width: 90, height: 20))
        let valueWidth: CGFloat = detail == nil ? 326 : 150
        let valueField = makeLabel(value, frame: NSRect(x: 112, y: 5, width: valueWidth, height: 20))
        valueField.lineBreakMode = .byTruncatingTail
        valueField.toolTip = value
        row.addSubview(labelField)
        row.addSubview(valueField)

        if let detail {
            let detailField = makeLabel(detail, frame: NSRect(x: 270, y: 5, width: 174, height: 20))
            detailField.lineBreakMode = .byTruncatingTail
            detailField.toolTip = detail
            row.addSubview(detailField)
        }
        item.view = row
    }

    private func makeLabel(_ text: String, frame: NSRect) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = frame
        field.font = .menuFont(ofSize: NSFont.systemFontSize)
        field.textColor = .labelColor
        field.alignment = .left
        return field
    }

    private func configureActionItem(_ item: NSMenuItem, title: String, action: Selector) {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: Self.menuWidth, height: 30))

        let button = NSButton(frame: NSRect(x: 16, y: 1, width: Self.menuWidth - 32, height: 28))
        button.title = title
        button.target = self
        button.action = action
        button.isBordered = false
        button.alignment = .left
        button.font = .menuFont(ofSize: NSFont.systemFontSize)
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryChange)
        button.autoresizingMask = [.width, .height]
        button.contentTintColor = .labelColor

        row.addSubview(button)
        item.view = row
    }

    private func syncOnOpenTitle() -> String {
        let enabled = UserDefaults.standard.bool(forKey: Self.syncOnMenuOpenKey)
        return enabled ? t("打开菜单时刷新：开", "Sync on open: On") : t("打开菜单时刷新：关", "Sync on open: Off")
    }

    @objc private func toggleSyncOnOpen() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: Self.syncOnMenuOpenKey), forKey: Self.syncOnMenuOpenKey)
        configureActionItem(syncOnOpenItem, title: syncOnOpenTitle(), action: #selector(toggleSyncOnOpen))
    }

    private func scheduleNextRefresh(for info: QuotaInfo) {
        refreshTimer?.invalidate()
        if !info.ok {
            nextRefreshInterval = Self.refreshInterval(for: Self.failureRetryMinutesKey, defaultMinutes: Self.defaultFailureRetryMinutes)
        } else {
            let activeThreads = info.activeThreads ?? 0
            nextRefreshInterval = activeThreads > 0
                ? Self.refreshInterval(for: Self.activeRefreshMinutesKey, defaultMinutes: Self.defaultActiveRefreshMinutes)
                : Self.refreshInterval(for: Self.idleRefreshMinutesKey, defaultMinutes: Self.defaultIdleRefreshMinutes)
        }
        refreshTimer = Timer.scheduledTimer(
            timeInterval: nextRefreshInterval,
            target: self,
            selector: #selector(refreshNow),
            userInfo: nil,
            repeats: false
        )
    }

    private func startActivityProbeTimer() {
        activityProbeTimer?.invalidate()
        activityProbeTimer = Timer.scheduledTimer(
            timeInterval: Self.activityProbeInterval(),
            target: self,
            selector: #selector(probeActivity),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func probeActivity() {
        guard !isRefreshing else { return }
        DispatchQueue.global(qos: .utility).async {
            let probe = Self.readActivityProbe()
            DispatchQueue.main.async {
                guard probe.ok else { return }
                let activeThreads = probe.activeThreads ?? 0
                let windowSeconds = probe.activeWindowSeconds ?? 120
                let sourceAdvanced = Self.isLaterTimestamp(probe.sourceUpdatedAt, than: self.lastKnownSourceUpdatedAt)
                let becameActive = activeThreads > 0 && (self.lastGoodInfo?.activeThreads ?? 0) == 0

                if let cached = self.lastGoodInfo, (cached.activeThreads ?? 0) == 0 {
                    self.setInfoItem(
                        self.activityItem,
                        label: self.t("后台活动", "Activity"),
                        value: self.formatActivity(count: activeThreads, seconds: windowSeconds)
                    )
                }

                guard sourceAdvanced || becameActive else { return }
                if becameActive, let last = self.lastProbeTriggeredRefreshAt, Date().timeIntervalSince(last) < 240 {
                    return
                }
                self.lastProbeTriggeredRefreshAt = Date()
                self.refreshNow()
            }
        }
    }

    private static func refreshInterval(for key: String, defaultMinutes: Int) -> TimeInterval {
        let configured = UserDefaults.standard.integer(forKey: key)
        let minutes = configured > 0 ? configured : defaultMinutes
        return TimeInterval(max(1, minutes) * 60)
    }

    private static func activityProbeInterval() -> TimeInterval {
        let configured = UserDefaults.standard.integer(forKey: activityProbeSecondsKey)
        let seconds = configured > 0 ? configured : defaultActivityProbeSeconds
        return TimeInterval(max(30, seconds))
    }

    private static func isLaterTimestamp(_ lhs: String?, than rhs: String?) -> Bool {
        guard let lhsDate = parseCodexTimestamp(lhs) else { return false }
        guard let rhsDate = parseCodexTimestamp(rhs) else { return true }
        return lhsDate.timeIntervalSince(rhsDate) > 0.5
    }

    private static func parseCodexTimestamp(_ timestamp: String?) -> Date? {
        guard var timestamp, !timestamp.isEmpty else { return nil }
        if timestamp.hasSuffix("Z") {
            timestamp = String(timestamp.dropLast()) + "+00:00"
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp) ?? fallbackFormatter.date(from: timestamp)
    }

    private static func readQuota() -> QuotaInfo {
        return readPythonOutput(as: QuotaInfo.self, arguments: [])
    }

    private static func readActivityProbe() -> ActivityProbeInfo {
        return readPythonOutput(as: ActivityProbeInfo.self, arguments: ["--activity-probe"])
    }

    private static func readPythonOutput<T: Decodable>(as type: T.Type, arguments: [String]) -> T {
        let script = pythonScript
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script] + arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let fallback = QuotaInfo(
                ok: false,
                error: error.localizedDescription,
                timestamp: nil,
                planType: nil,
                limitId: nil,
                limitName: nil,
                serviceTier: nil,
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
                weeklyActiveBudgetRatio: nil,
                risk: nil,
                topThread: nil,
                topThreadTokens: nil,
                activeThreads: nil,
                activeWindowSeconds: nil
            )
            if let typed = fallback as? T {
                return typed
            }
            return ActivityProbeInfo(
                ok: false,
                error: error.localizedDescription,
                timestamp: nil,
                sourceUpdatedAt: nil,
                activeThreads: nil,
                activeWindowSeconds: nil
            ) as! T
        }
    }

    private func formatReset(_ seconds: Int?) -> String {
        guard let seconds else { return "-" }
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        if date <= Date() {
            return t("已重置", "reset")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: useChinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : (useChinese ? "M月d日 HH:mm" : "MMM d HH:mm")
        return formatter.string(from: date)
    }

    private func isResetExpired(_ seconds: Int?) -> Bool {
        guard let seconds else { return false }
        return Date(timeIntervalSince1970: TimeInterval(seconds)) <= Date()
    }

    private func formatUpdated(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: useChinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm:ss" : (useChinese ? "M月d日 HH:mm" : "MMM d HH:mm")
        return formatter.string(from: date)
    }

    private func formatDataTimestamp(_ timestamp: String?) -> String {
        guard var timestamp, !timestamp.isEmpty else { return "-" }
        if timestamp.hasSuffix("Z") {
            timestamp = String(timestamp.dropLast()) + "+00:00"
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: timestamp) ?? fallbackFormatter.date(from: timestamp) else {
            return "-"
        }
        return formatUpdated(date)
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

    private func formatWeeklyPrediction(budgetRatio: Double?, activeBudgetRatio: Double?, daysEarly: Double?) -> (status: String, detail: String?) {
        let preferredRatio = activeBudgetRatio ?? budgetRatio
        guard let ratioValue = preferredRatio, ratioValue.isFinite else {
            return ("-", nil)
        }
        let ratio = useChinese ? String(format: "活跃节奏 %.1fx", ratioValue) : String(format: "active pace %.1fx", ratioValue)
        if let daysEarly, daysEarly.isFinite, daysEarly > 0 {
            return (useChinese ? "会提前耗尽" : "runs out early", ratio)
        }
        if ratioValue <= 0.7 {
            return (useChinese ? "很安全" : "safe", ratio)
        }
        if ratioValue <= 1.05 {
            return (useChinese ? "可撑到重置" : "lasts to reset", ratio)
        }
        return (useChinese ? "偏快" : "fast", ratio)
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

    private func formatActivity(_ info: QuotaInfo) -> String {
        formatActivity(count: info.activeThreads ?? 0, seconds: info.activeWindowSeconds ?? 120)
    }

    private func formatActivity(count: Int, seconds: Int) -> String {
        if count <= 0 {
            return t("空闲", "idle")
        }
        let minutes = max(1, Int(round(Double(seconds) / 60)))
        return t("近\(minutes)分钟 \(count) 个线程仍在消耗", "\(count) thread(s) active in \(minutes)m")
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private let pythonScript = #"""
import json
import os
import pathlib
import select
import sqlite3
import subprocess
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

home = pathlib.Path.home()
db_path = home / ".codex" / "state_5.sqlite"
session_index_path = home / ".codex" / "session_index.jsonl"
global_state_path = home / ".codex" / ".codex-global-state.json"
codex_binary = pathlib.Path("/Applications/Codex.app/Contents/Resources/codex")
tz = timezone(timedelta(hours=8))
now = datetime.now(tz)
today = now.date()
ACTIVE_WINDOW_SECONDS = 120

def fail(message):
    print(json.dumps({"ok": False, "error": message}))
    raise SystemExit(0)

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

def read_service_tier(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        state = data.get("electron-persisted-atom-state") or {}
        value = state.get("default-service-tier")
        if value is None:
            return "standard"
        text = str(value).strip()
        return text or "standard"
    except Exception:
        return "standard"

def load_thread_names(path):
    names = {}
    if not path.exists():
        return names
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                if '"thread_name"' not in line:
                    continue
                try:
                    item = json.loads(line)
                except Exception:
                    continue
                thread_id = item.get("id")
                name = item.get("thread_name")
                updated_at = item.get("updated_at") or ""
                if not thread_id or not name:
                    continue
                previous = names.get(thread_id)
                if previous is None or updated_at >= previous[0]:
                    names[thread_id] = (updated_at, name)
    except Exception:
        return {}
    return {thread_id: name for thread_id, (_, name) in names.items()}

def read_recent_json(path, max_lines=1200):
    lines = []
    for line in reversed_lines(path):
        lines.append(line)
        if len(lines) >= max_lines:
            break
    return reversed(lines)

def read_app_server_quota(timeout_seconds=8):
    if not codex_binary.exists():
        return None
    try:
        proc = subprocess.Popen(
            [str(codex_binary), "app-server", "--analytics-default-enabled"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
    except Exception:
        return None

    def send(message):
        if proc.stdin is None:
            return
        proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        proc.stdin.flush()

    try:
        send({
            "method": "initialize",
            "id": 1,
            "params": {
                "clientInfo": {"name": "codex-battery", "version": "0.1.27"},
                "capabilities": {
                    "experimentalApi": True,
                    "optOutNotificationMethods": [
                        "thread/started",
                        "thread/status/changed",
                        "thread/tokenUsage/updated",
                        "app/list/updated",
                        "remoteControl/status/changed",
                    ],
                },
            },
        })
        deadline = time.monotonic() + timeout_seconds
        requested = False
        while time.monotonic() < deadline:
            if proc.stdout is None:
                break
            readable, _, _ = select.select([proc.stdout], [], [], max(0.1, deadline - time.monotonic()))
            if not readable:
                continue
            line = proc.stdout.readline()
            if not line:
                break
            try:
                message = json.loads(line)
            except Exception:
                continue
            if message.get("id") == 1 and not requested:
                send({"method": "initialized"})
                send({"method": "account/rateLimits/read", "id": 2, "params": None})
                requested = True
                continue
            if message.get("id") == 2:
                result = message.get("result") or {}
                by_id = result.get("rateLimitsByLimitId") or {}
                snapshot = by_id.get("codex") or result.get("rateLimits")
                if not snapshot:
                    return None
                primary = snapshot.get("primary") or {}
                secondary = snapshot.get("secondary") or {}
                return {
                    "timestamp": datetime.now(tz).isoformat(),
                    "planType": snapshot.get("planType"),
                    "limitId": snapshot.get("limitId"),
                    "limitName": snapshot.get("limitName"),
                    "primaryUsed": primary.get("usedPercent"),
                    "secondaryUsed": secondary.get("usedPercent"),
                    "primaryReset": primary.get("resetsAt"),
                    "secondaryReset": secondary.get("resetsAt"),
                }
    except Exception:
        return None
    finally:
        try:
            if proc.stdin:
                proc.stdin.close()
        except Exception:
            pass
        try:
            proc.terminate()
            proc.wait(timeout=1)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
    return None

def empty_stats_out(snapshot):
    out = dict(snapshot)
    out.update({
        "ok": True,
        "title": None,
        "model": None,
        "effort": None,
        "serviceTier": read_service_tier(global_state_path),
        "totalTokens": None,
        "todayTokens": 0,
        "todayVs3DayAvg": None,
        "weeklyBurnPctPerHour": None,
        "weeklyEtaHours": None,
        "weeklyBudgetRatio": None,
        "weeklyDaysEarly": None,
        "weeklyActiveBudgetRatio": None,
        "risk": "OK",
        "topThread": None,
        "topThreadTokens": None,
        "activeThreads": 0,
        "activeWindowSeconds": ACTIVE_WINDOW_SECONDS,
    })
    return out

def read_activity_probe():
    try:
        if not db_path.exists():
            return {"ok": False, "error": "No Codex state database found"}
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=1.0)
        rows = con.execute(
            """
            SELECT id, rollout_path, updated_at, updated_at_ms
            FROM threads
            WHERE rollout_path IS NOT NULL
            ORDER BY updated_at DESC
            LIMIT 20
            """
        ).fetchall()
        active = set()
        latest_source_at = 0.0
        try:
            if global_state_path.exists():
                latest_source_at = max(latest_source_at, global_state_path.stat().st_mtime)
        except Exception:
            pass
        cutoff_dt = now - timedelta(seconds=ACTIVE_WINDOW_SECONDS)
        cutoff_epoch = cutoff_dt.timestamp()
        for thread_id, rollout_path, updated_at, updated_at_ms in rows:
            try:
                if updated_at:
                    latest_source_at = max(latest_source_at, float(updated_at))
            except Exception:
                pass
            try:
                if updated_at_ms:
                    latest_source_at = max(latest_source_at, float(updated_at_ms) / 1000)
            except Exception:
                pass
            if updated_at and float(updated_at) >= cutoff_epoch:
                active.add(thread_id)
                continue
            if updated_at_ms and float(updated_at_ms) / 1000 >= cutoff_epoch:
                active.add(thread_id)
                continue
            path = pathlib.Path(rollout_path)
            if not path.exists():
                continue
            try:
                stat_mtime = path.stat().st_mtime
                latest_source_at = max(latest_source_at, stat_mtime)
                if stat_mtime >= cutoff_epoch:
                    active.add(thread_id)
                    continue
            except Exception:
                pass
            scanned = 0
            for line in reversed_lines(path):
                scanned += 1
                if scanned > 200:
                    break
                if '"token_count"' not in line:
                    continue
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
                latest_source_at = max(latest_source_at, ts.timestamp())
                if ts >= cutoff_dt:
                    active.add(thread_id)
                break
        source_updated_at = datetime.fromtimestamp(latest_source_at, tz).isoformat() if latest_source_at > 0 else None
        return {
            "ok": True,
            "timestamp": datetime.now(tz).isoformat(),
            "sourceUpdatedAt": source_updated_at,
            "activeThreads": len(active),
            "activeWindowSeconds": ACTIVE_WINDOW_SECONDS,
        }
    except Exception as exc:
        return {"ok": False, "error": str(exc)}

if len(sys.argv) > 1 and sys.argv[1] == "--activity-probe":
    print(json.dumps(read_activity_probe(), ensure_ascii=False))
    raise SystemExit(0)

app_server_snapshot = read_app_server_quota()

if not db_path.exists():
    if app_server_snapshot:
        print(json.dumps(empty_stats_out(app_server_snapshot), ensure_ascii=False))
        raise SystemExit(0)
    fail("No Codex state database found")

last_db_error = None
rows = None
for attempt in range(6):
    try:
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=2.0)
        rows = con.execute(
            """
            SELECT id, rollout_path, title, model, reasoning_effort
            FROM threads
            WHERE rollout_path IS NOT NULL
            ORDER BY updated_at DESC
            LIMIT 20
            """
        ).fetchall()
        break
    except Exception as exc:
        last_db_error = exc
        time.sleep(0.15 * (attempt + 1))

if rows is None:
    fail(f"Cannot read Codex state after retry: {last_db_error}")

latest = None
daily = defaultdict(Counter)
top_by_thread = defaultdict(Counter)
weekly_points = []
rate_snapshots = []
active_thread_ids = set()
active_bins_by_day = defaultdict(set)
thread_names = load_thread_names(session_index_path)

for thread_id, rollout_path, title, model, effort in rows:
    if not rollout_path:
        continue
    path = pathlib.Path(rollout_path)
    if not path.exists():
        continue
    display_title = thread_names.get(thread_id) or title
    try:
        if path.stat().st_mtime >= (now - timedelta(seconds=ACTIVE_WINDOW_SECONDS)).timestamp():
            active_thread_ids.add(thread_id)
    except Exception:
        pass
    events = []
    try:
        for line in read_recent_json(path):
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
            if ts >= now - timedelta(seconds=ACTIVE_WINDOW_SECONDS):
                active_thread_ids.add(thread_id)
            active_bin = ts.replace(minute=(ts.minute // 5) * 5, second=0, microsecond=0)
            active_bins_by_day[ts.date()].add(active_bin)
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
                    "title": display_title,
                    "model": model,
                    "effort": effort,
                    "totalTokens": total.get("total_tokens")
                })
                used = secondary.get("used_percent")
                # Codex may emit additional model-specific quota windows
                # (for example codex_bengalfox) whose reset time is not the
                # main "Remaining quota" window shown in the Codex UI. Keep
                # weekly trend math anchored to the official aggregate window.
                if used is not None and rate_limits.get("limit_id") == "codex":
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
                        "title": display_title,
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
                label = compact_title(display_title)
                top_by_thread[(day, label)]["total_tokens"] += diff
                top_by_thread[(day, label)]["turns"] += 1
    except Exception:
        continue

if not latest:
    if app_server_snapshot:
        print(json.dumps(empty_stats_out(app_server_snapshot), ensure_ascii=False))
        raise SystemExit(0)
    fail("No recent Codex rate-limit data found")

# Prefer the aggregate Codex quota window. Some model-specific windows report
# their own 0% used / now+5h reset values and should not drive the menu.
official_snapshots = [
    snap for snap in rate_snapshots
    if snap.get("limitId") == "codex"
]
if official_snapshots:
    latest = max(official_snapshots, key=lambda snap: snap["ts"])

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

if app_server_snapshot:
    latest.update({
        "timestamp": app_server_snapshot.get("timestamp"),
        "planType": app_server_snapshot.get("planType"),
        "limitId": app_server_snapshot.get("limitId"),
        "limitName": app_server_snapshot.get("limitName"),
        "primaryUsed": app_server_snapshot.get("primaryUsed"),
        "secondaryUsed": app_server_snapshot.get("secondaryUsed"),
        "primaryReset": app_server_snapshot.get("primaryReset"),
        "secondaryReset": app_server_snapshot.get("secondaryReset"),
    })

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
weekly_active_budget_ratio = None
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

        week_start = datetime.fromtimestamp(start_at, tz)
        active_bins_this_week = set()
        for bins in active_bins_by_day.values():
            for active_bin in bins:
                if week_start <= active_bin <= now:
                    active_bins_this_week.add(active_bin)
        active_hours_elapsed = len(active_bins_this_week) * 5 / 60
        # Do not assume an always-on 24h/day workload. Budget only actual
        # observed active buckets, compared against an 8h/day workday budget.
        active_hours_per_day = 8.0
        expected_active_used = active_hours_elapsed / (active_hours_per_day * 7) * 100.0
        if expected_active_used >= 0.5:
            weekly_active_budget_ratio = used_week / expected_active_used
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
    "serviceTier": read_service_tier(global_state_path),
    "weeklyBurnPctPerHour": weekly_burn,
    "weeklyEtaHours": weekly_eta,
    "weeklyBudgetRatio": weekly_budget_ratio,
    "weeklyDaysEarly": weekly_days_early,
    "weeklyActiveBudgetRatio": weekly_active_budget_ratio,
    "risk": risk,
    "topThread": top_thread,
    "topThreadTokens": top_thread_tokens,
    "activeThreads": len(active_thread_ids),
    "activeWindowSeconds": ACTIVE_WINDOW_SECONDS
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
