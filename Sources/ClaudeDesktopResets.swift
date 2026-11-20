import AppKit
import ApplicationServices
import OSLog

enum ClaudeDesktopUsageRoute {
    static func matches(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == "claude.ai" else { return false }
        let settings = "settings/usage"
        return url.path == "/" + settings
            || url.fragment?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == settings
    }
}

/// Only the derived reset counts and dates are kept. The page text stays in the reader.
struct ClaudeDesktopResetReading: Codable, Equatable {
    let count: Int
    let grants: [ClaudeResetGrant]

    func stock(at now: Date) -> ProviderResetStock {
        let expired = grants.filter { $0.endsAt.map { $0 <= now } ?? false }
        let available = grants.filter { $0.isAvailable(at: now) }
        return ProviderResetStock(count: max(0, count - expired.reduce(0) { $0 + $1.resetsLeft }),
                                  expirations: available.flatMap { grant in
            grant.endsAt.map { Array(repeating: $0, count: min(grant.resetsLeft, 20)) } ?? []
        })
    }

    private static let totalPattern = #"(?i)^([0-9]{1,4})\s*(?:个可用|(?:resets?\s+)?available)$"#
    private static let grantPattern = #"(?i)^(完全重置|完整重置|full (?:limit )?reset|Fable (?:限额)?重置|Fable (?:limit )?reset|每周(?:限额)?重置|weekly (?:limit )?reset|5\s*小时(?:限额)?重置|(?:5|five)-hour (?:limit )?reset)(?:\s*[·×]\s*([0-9]{1,4}))?$"#
    private static let chineseExpiry = #"于\s*(?:([0-9]{4})年\s*)?([0-9]{1,2})月\s*([0-9]{1,2})日\s*(?:(?:GMT|UTC)([+-][0-9]{1,2}(?::[0-9]{2})?)\s*)?([0-9]{1,2}):([0-9]{2})\s*到期"#
    private static let englishExpiry = #"(?i)\bexpires\s+(?:on\s+)?([a-z]{3,9})\s+([0-9]{1,2})(?:,\s*([0-9]{4}))?(?:\s+at|,)?\s+(?:(?:GMT|UTC)([+-][0-9]{1,2}(?::[0-9]{2})?)\s+)?([0-9]{1,2}):([0-9]{2})(?:\s*(AM|PM))?(?:\s+(?:GMT|UTC)([+-][0-9]{1,2}(?::[0-9]{2})?))?"#
    static let sectionNames: Set = ["Limit resets", "Limit Resets", "限额重置"]
    static let nextSectionNames: Set = ["Usage credits", "Usage Credits", "用量额度", "本周各产品的用量"]

    /// Electron may expose the reset heading, total, and rows at different tree depths.
    static func parseUsageLabels(_ labels: [String], at now: Date, timeZone: TimeZone = .current) -> Self? {
        let labels = labels.map(normalized)
        guard let heading = labels.firstIndex(where: sectionNames.contains) else { return nil }
        let resetLabels = labels.dropFirst(heading + 1).prefix { !nextSectionNames.contains($0) }
        var rows: [[String]] = []
        for label in resetLabels {
            if match(grantPattern, in: label) != nil {
                if rows.last?.first != label { rows.append([label]) }
            } else if !rows.isEmpty {
                rows[rows.count - 1].append(label)
            }
        }
        return parse(totalLabels: Array(resetLabels), rows: rows, at: now, timeZone: timeZone)
    }

    static func parse(totalLabels: [String], rows: [[String]], at now: Date,
                      timeZone: TimeZone = .current) -> Self? {
        let totals = Set(totalLabels.compactMap { match(totalPattern, in: $0).flatMap { Int($0[0]) } })
        guard totals.count == 1, let count = totals.first else { return nil }
        let grants = rows.compactMap { row -> ClaudeResetGrant? in
            guard let title = row.lazy.compactMap({ match(grantPattern, in: $0) }).first else { return nil }
            let label = title[0].lowercased()
            let kind: String
            if label.hasPrefix("fable") { kind = "fable" }
            else if label.hasPrefix("weekly") || label.hasPrefix("每周") { kind = "weekly" }
            else if label.hasPrefix("full") || label.hasPrefix("完全") || label.hasPrefix("完整") { kind = "full" }
            else { kind = "session" }
            let left = Int(title[1]) ?? 1
            let dates = Set(row.compactMap { expiry(in: $0, at: now, timeZone: timeZone) })
            return ClaudeResetGrant(label: "", type: kind, resetsLeft: left, resetsTotal: left,
                                    endsAt: dates.count == 1 ? dates.first : nil, paused: false)
        }
        // The explicit total is still useful if a new kind or layout makes the details ambiguous.
        return Self(count: count, grants: grants.reduce(0) { $0 + $1.resetsLeft } <= count ? grants : [])
    }

    private static func match(_ pattern: String, in value: String) -> [String]? {
        let text = normalized(value)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }

    private static func normalized(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func expiry(in text: String, at now: Date, timeZone: TimeZone) -> Date? {
        if let parts = match(chineseExpiry, in: text) {
            return date(year: Int(parts[0]), month: Int(parts[1]), day: Int(parts[2]),
                        hour: Int(parts[4]), minute: Int(parts[5]), offset: parts[3], at: now, timeZone: timeZone)
        }
        guard let parts = match(englishExpiry, in: text) else { return nil }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let month = months.firstIndex(of: parts[0].prefix(3).lowercased()).map { $0 + 1 }
        guard var hour = Int(parts[4]) else { return nil }
        if !parts[6].isEmpty {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (parts[6].uppercased() == "PM" ? 12 : 0)
        }
        return date(year: Int(parts[2]), month: month, day: Int(parts[1]), hour: hour,
                    minute: Int(parts[5]), offset: parts[3].isEmpty ? parts[7] : parts[3], at: now, timeZone: timeZone)
    }

    private static func date(year: Int?, month: Int?, day: Int?, hour: Int?, minute: Int?,
                             offset: String, at now: Date, timeZone: TimeZone) -> Date? {
        guard let month, let day, let hour, let minute, (1...12).contains(month),
              (1...31).contains(day), (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if let sign = offset.first {
            let parts = offset.dropFirst().split(separator: ":")
            guard let hours = parts.first.flatMap({ Int($0) }), hours <= 14 else { return nil }
            let minutes = parts.count == 2 ? Int(parts[1]) ?? 60 : 0
            guard minutes < 60, let zone = TimeZone(secondsFromGMT: (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60)) else { return nil }
            calendar.timeZone = zone
        }
        let components = DateComponents(year: year ?? calendar.component(.year, from: now), month: month,
                                        day: day, hour: hour, minute: minute)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }
}

struct ClaudeDesktopResetSnapshot: Codable {
    let reading: ClaudeDesktopResetReading
    let syncedAt: Date
}

/// Display-only values from the visible Usage page. The date is derived from its update label.
struct ClaudeDesktopQuotaSnapshot: Codable, Equatable {
    let fiveHourUsed: Double?
    let weekUsed: Double
    let fableUsed: Double?
    let updatedAt: Date

    var quota: ProviderQuotaSnapshot {
        ProviderQuotaSnapshot(checkedAt: updatedAt,
            fiveHour: fiveHourUsed.map { ProviderQuotaWindow(used: $0, resetsAt: nil) },
            week: ProviderQuotaWindow(used: weekUsed, resetsAt: nil),
            modelWindows: fableUsed.map { ["seven_day_fable": ProviderQuotaWindow(used: $0, resetsAt: nil)] } ?? [:])
    }
}

struct ClaudeDesktopQuotaReading: Equatable {
    enum Window {
        case fiveHour, week, fable

        static func isIndicator(role: String) -> Bool {
            role == kAXLevelIndicatorRole || role == kAXProgressIndicatorRole
        }

        init?(role: String, labels: [String]) {
            guard Self.isIndicator(role: role), let window = labels.lazy.compactMap(Self.init(label:)).first else { return nil }
            self = window
        }

        init?(label: String) {
            switch label.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased() {
            case "当前会话", "5 小时限额", "current session", "5-hour limit": self = .fiveHour
            case "本周", "所有模型", "每周 · 所有模型", "this week", "all models", "weekly · all models": self = .week
            case "fable", "每周 · fable", "weekly · fable": self = .fable
            default: return nil
            }
        }
    }

    let fiveHourUsed: Double?
    let weekUsed: Double
    let fableUsed: Double?
    let updateAge: TimeInterval
    private static let relativeAge = try! NSRegularExpression(
        pattern: #"^(?:约\s*|大约\s*|about\s+)?(\d{1,5}|一|a|an)\s*(秒|分钟|小时|天|seconds?|minutes?|hours?|days?)\s*(?:前|ago)$"#)

    static func parse(progress: [(Window, Double?)], updateAge: TimeInterval) -> Self? {
        var usage: [Window: Double] = [:]
        for (window, percentage) in progress {
            guard let percentage, (0...100).contains(percentage),
                  usage[window].map({ $0 == percentage }) ?? true else { return nil }
            usage[window] = percentage
        }
        guard let week = usage[.week] else { return nil }
        return Self(fiveHourUsed: usage[.fiveHour], weekUsed: week, fableUsed: usage[.fable], updateAge: updateAge)
    }

    static func updateAge(in label: String) -> TimeInterval? {
        let text = label.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        guard let heading = text.range(of: #"^(?:最后更新|上次更新|last updated)\s*[:：]?\s*"#, options: .regularExpression) else { return nil }
        let age = String(text[heading.upperBound...])
        let compactAge = age.replacingOccurrences(of: " ", with: "")
        if ["刚刚", "不到一分钟前", "不到1分钟前"].contains(compactAge)
            || ["just now", "less than a minute ago", "less than 1 minute ago"].contains(age) { return 0 }
        let value = age as NSString
        guard let match = relativeAge.firstMatch(in: age, range: NSRange(location: 0, length: value.length)) else { return nil }
        let amount = value.substring(with: match.range(at: 1))
        guard let count = ["一", "a", "an"].contains(amount) ? 1 : Double(amount) else { return nil }
        switch value.substring(with: match.range(at: 2)) {
        case "秒", "second", "seconds": return count
        case "分钟", "minute", "minutes": return count * 60
        case "小时", "hour", "hours": return count * 3600
        case "天", "day", "days": return count * 86400
        default: return nil
        }
    }

    func snapshot(observedAt: Date) -> ClaudeDesktopQuotaSnapshot {
        let time = observedAt.timeIntervalSince1970 - updateAge
        let updatedAt = Date(timeIntervalSince1970: floor(time / 60) * 60)
        return ClaudeDesktopQuotaSnapshot(fiveHourUsed: fiveHourUsed, weekUsed: weekUsed,
                                         fableUsed: fableUsed, updatedAt: updatedAt)
    }
}

/// An independent, read-only source. Poll only while the official desktop app is active.
final class ClaudeDesktopResetMonitor {
    private static let bundleID = "com.anthropic.claudefordesktop"
    private static let logger = Logger(subsystem: "local.codex.battery.menu", category: "ClaudeDesktopResets")
    static var hasAccess: Bool { AXIsProcessTrusted() }
    private let didRead: (ClaudeDesktopResetReading?) -> Void
    private let shouldReadQuota: () -> Bool
    private let didReadQuota: (ClaudeDesktopQuotaSnapshot) -> Void
    private let worker = DispatchQueue(label: "local.codex.battery.claude-desktop-resets", qos: .utility)
    private var activationObserver: NSObjectProtocol?
    private var timer: Timer?
    private var reading = false
    private var pendingOpenPageSync: pid_t?
    private var lastResetSection: ClaudeDesktopUsageReader.ResetSection?
    private var lastQuotaReading: ClaudeDesktopQuotaReading?
    private var lastReadStage: String?
    private var pendingAbsence = false

    init(didRead: @escaping (ClaudeDesktopResetReading?) -> Void,
         shouldReadQuota: @escaping () -> Bool,
         didReadQuota: @escaping (ClaudeDesktopQuotaSnapshot) -> Void) {
        self.didRead = didRead
        self.shouldReadQuota = shouldReadQuota
        self.didReadQuota = didReadQuota
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.checkForeground() }
        syncOpenPage()
    }

    deinit {
        timer?.invalidate()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    private func checkForeground(pollImmediately: Bool = true) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == Self.bundleID, Self.hasAccess else {
            timer?.invalidate()
            timer = nil
            lastResetSection = nil
            pendingAbsence = false
            return
        }
        guard timer == nil else { return }
        let next = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        next.tolerance = 0.5
        RunLoop.main.add(next, forMode: .common)
        timer = next
        if pollImmediately { poll() }
    }

    /// Check an already open usage page even when another app is in front.
    func syncOpenPage() {
        checkForeground(pollImmediately: false)
        guard Self.hasAccess, let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else { return }
        poll(pid: app.processIdentifier, requireForeground: false)
    }

    private func poll() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == Self.bundleID, Self.hasAccess else {
            checkForeground()
            return
        }
        poll(pid: app.processIdentifier, requireForeground: true)
    }

    private func poll(pid: pid_t, requireForeground: Bool) {
        if reading {
            // A scan already underway may have started before the terminal login expired.
            if !requireForeground { pendingOpenPageSync = pid }
            return
        }
        let includeQuota = shouldReadQuota()
        if !includeQuota { lastQuotaReading = nil }
        reading = true
        worker.async { [weak self] in
            let reader = ClaudeDesktopUsageReader(includeQuota: includeQuota)
            let page = reader.read(pid: pid)
            let stage = reader.stage
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reading = false
                let pending = self.pendingOpenPageSync
                self.pendingOpenPageSync = nil
                defer {
                    if let pending, Self.hasAccess { self.poll(pid: pending, requireForeground: false) }
                }
                guard Self.hasAccess,
                      !requireForeground || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                if self.lastReadStage != stage {
                    Self.logger.info("Desktop sync: \(stage, privacy: .public)")
                    self.lastReadStage = stage
                }
                self.publish(page, usagePageMissing: stage == "usage_page_not_found")
            }
        }
    }

    private func publish(_ page: ClaudeDesktopUsageReader.Page?, usagePageMissing: Bool) {
        if usagePageMissing { lastQuotaReading = nil }
        // Keep the timestamp for the same relative label while the page stays open.
        if let quota = page?.quota, quota != lastQuotaReading, shouldReadQuota() {
            lastQuotaReading = quota
            didReadQuota(quota.snapshot(observedAt: Date()))
        }
        let section = page?.resets
        // A loaded page without a reset section can arrive before the grants. Confirm on the next read.
        if section == .absent, !pendingAbsence {
            pendingAbsence = true
            return
        }
        pendingAbsence = section == .absent
        guard section != lastResetSection else { return }
        lastResetSection = section
        switch section {
        case .resets(let value): didRead(value)
        case .absent: didRead(nil)
        case nil: break
        }
    }
}

private final class ClaudeDesktopUsageReader {
    enum ResetSection: Equatable { case resets(ClaudeDesktopResetReading), absent }
    struct Page {
        let resets: ResetSection?
        let quota: ClaudeDesktopQuotaReading?
    }

    private struct Node {
        let role: String
        let names: [String]
        let children: [AXUIElement]

        init(_ element: AXUIElement) {
            let keys = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXChildrenAttribute]
            var result: CFArray?
            AXUIElementCopyMultipleAttributeValues(element, keys as CFArray, [], &result)
            let values = result as? [Any] ?? []
            role = values.first as? String ?? ""
            names = values.dropFirst().prefix(2).compactMap { $0 as? String }.filter { !$0.isEmpty }
            children = values.last as? [AXUIElement] ?? []
        }
    }

    private static let settingsNames: Set = ["Settings", "设置"]
    private static let usageNames: Set = ["Your usage", "Your Usage", "您的用量", "你的用量"]
    private static let containers: Set = [kAXWindowRole, kAXGroupRole, kAXScrollAreaRole, kAXSplitGroupRole,
                                          kAXTabGroupRole, "AXDialog", "AXWebArea"]
    private let deadline = ProcessInfo.processInfo.systemUptime + 3
    private let includeQuota: Bool
    private(set) var stage = "window_unavailable"

    init(includeQuota: Bool) { self.includeQuota = includeQuota }

    func read(pid: pid_t) -> Page? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        if let focus = element(attribute(kAXFocusedUIElementAttribute, of: app)) {
            var parent: AXUIElement? = focus
            for _ in 0..<8 {
                guard withinDeadline, let current = parent else { break }
                let node = Node(current)
                if let page = pageAt(current, node: node) { return page }
                if node.role == kAXWindowRole { break }
                parent = element(attribute(kAXParentAttribute, of: current))
            }
        }
        let window = element(attribute(kAXFocusedWindowAttribute, of: app)) ?? element(attribute(kAXMainWindowAttribute, of: app))
        var queue = window.map { [$0] } ?? (attribute(kAXWindowsAttribute, of: app) as? [AXUIElement] ?? [])
        guard !queue.isEmpty else { return nil }
        if stage == "window_unavailable" { stage = "usage_page_not_found" }
        // Claude Code can put its settings under several extra accessibility groups in the background.
        for _ in 0..<16 {
            var children: [AXUIElement] = []
            for element in queue.prefix(60) {
                guard withinDeadline else { return nil }
                let node = Node(element)
                guard Self.containers.contains(node.role) else { continue }
                if node.role == "AXWebArea", let url = url(of: element) {
                    guard url.host == "claude.ai" || url.isFileURL else { continue }
                }
                if let page = pageAt(element, node: node) { return page }
                children.append(contentsOf: node.children.prefix(60))
            }
            if children.isEmpty { break }
            queue = children
        }
        return nil
    }

    private func pageAt(_ element: AXUIElement, node: Node) -> Page? {
        let hasUsageRoute = node.role == "AXWebArea" && url(of: element).map(ClaudeDesktopUsageRoute.matches) == true
        let isSettingsGroup = (node.role == kAXGroupRole || node.role == "AXDialog")
            && !Self.settingsNames.isDisjoint(with: node.names)
        guard hasUsageRoute || isSettingsGroup else { return nil }
        if stage == "window_unavailable" || stage == "usage_page_not_found" { stage = "settings_found" }
        return scanSettings(node)
    }

    private func scanSettings(_ root: Node) -> Page? {
        var group = [root]
        for _ in 0..<5 {
            var nested: [Node] = []
            for node in group.prefix(20) {
                guard withinDeadline else { return nil }
                var children: [(AXUIElement, Node)] = []
                for element in node.children.prefix(70) {
                    guard withinDeadline else { return nil }
                    children.append((element, Node(element)))
                }
                if children.contains(where: { isHeading($0.1, named: Self.usageNames) }),
                   let page = readSections(children) { return page }
                nested.append(contentsOf: children.map(\.1).filter { Self.containers.contains($0.role) })
            }
            if nested.isEmpty { break }
            group = nested
        }
        return nil
    }

    private func readSections(_ children: [(AXUIElement, Node)]) -> Page? {
        stage = "usage_found"
        var labels: [String] = []
        for (element, node) in children {
            guard withinDeadline else { return nil }
            let lines = text(of: element, node: node, depth: 5)
            labels.append(contentsOf: lines)
            if lines.contains(where: ClaudeDesktopResetReading.nextSectionNames.contains) { break }
        }
        guard withinDeadline else { return nil }
        let quota = includeQuota ? readQuota(children) : nil
        if let reading = ClaudeDesktopResetReading.parseUsageLabels(labels, at: Date()) {
            stage = "read_resets"
            return Page(resets: .resets(reading), quota: quota)
        }
        if labels.contains(where: ClaudeDesktopResetReading.sectionNames.contains) {
            stage = "reset_count_unreadable"
            return quota.map { Page(resets: nil, quota: $0) }
        }
        let loaded = labels.contains(where: ClaudeDesktopResetReading.nextSectionNames.contains)
            && children.contains { element, node in
                guard node.role == kAXProgressIndicatorRole else { return false }
                let value = attribute(kAXValueAttribute, of: element)
                return value is NSNumber || (value as? String)?.isEmpty == false
            }
        if loaded { stage = "no_reset_section" }
        return loaded || quota != nil ? Page(resets: loaded ? .absent : nil, quota: quota) : nil
    }

    private func readQuota(_ children: [(AXUIElement, Node)]) -> ClaudeDesktopQuotaReading? {
        let boundary = ClaudeDesktopResetReading.sectionNames.union(ClaudeDesktopResetReading.nextSectionNames)
        let progress = children.prefix { !isHeading($0.1, named: boundary) }.flatMap {
            quotaProgress(of: $0.0, node: $0.1, depth: 4)
        }
        for (element, node) in children.reversed() {
            guard withinDeadline else { break }
            if let age = text(of: element, node: node, depth: 4).lazy.compactMap(ClaudeDesktopQuotaReading.updateAge).first {
                return ClaudeDesktopQuotaReading.parse(progress: progress, updateAge: age)
            }
        }
        return nil
    }

    private func quotaProgress(of element: AXUIElement, node: Node, depth: Int) -> [(ClaudeDesktopQuotaReading.Window, Double?)] {
        guard withinDeadline else { return [] }
        if ClaudeDesktopQuotaReading.Window.isIndicator(role: node.role) {
            var window = ClaudeDesktopQuotaReading.Window(role: node.role, labels: node.names)
            if window == nil, let title = self.element(attribute(kAXTitleUIElementAttribute, of: element)) {
                let titleNode = Node(title)
                window = ClaudeDesktopQuotaReading.Window(role: node.role,
                    labels: titleNode.names + text(of: title, node: titleNode, depth: 2))
            }
            guard let window else { return [] }
            let value = attribute(kAXValueAttribute, of: element) as? NSNumber
            return [(window, value?.doubleValue)]
        }
        guard depth > 0, Self.containers.contains(node.role) else { return [] }
        return node.children.prefix(20).flatMap { quotaProgress(of: $0, node: Node($0), depth: depth - 1) }
    }

    private func isHeading(_ node: Node, named names: Set<String>) -> Bool {
        guard node.role == kAXHeadingRole else { return false }
        if !names.isDisjoint(with: node.names) { return true }
        return node.children.prefix(3).contains { child in
            !names.isDisjoint(with: text(of: child, node: Node(child)))
        }
    }

    private func text(of element: AXUIElement, node: Node, depth: Int = 0) -> [String] {
        guard withinDeadline else { return [] }
        if node.role == kAXStaticTextRole {
            let value = attribute(kAXValueAttribute, of: element)
            let label = (value as? String) ?? (value as? NSAttributedString)?.string
            return node.names + [label].compactMap { $0 }
        }
        guard depth > 0, node.role == kAXGroupRole || node.role == kAXHeadingRole || node.role == kAXScrollAreaRole else { return [] }
        return node.names + node.children.prefix(20).flatMap { text(of: $0, node: Node($0), depth: depth - 1) }
    }

    private var withinDeadline: Bool { ProcessInfo.processInfo.systemUptime < deadline }

    private func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func url(of element: AXUIElement) -> URL? {
        let value = attribute(kAXURLAttribute, of: element)
        return (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
    }

    private func attribute(_ key: String, of element: AXUIElement) -> CFTypeRef? {
        guard withinDeadline else { return nil }
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
}
