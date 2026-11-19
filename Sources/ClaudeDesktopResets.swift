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

/// An independent, read-only source. Poll only while the official desktop app is active.
final class ClaudeDesktopResetMonitor {
    private static let bundleID = "com.anthropic.claudefordesktop"
    private static let logger = Logger(subsystem: "local.codex.battery.menu", category: "ClaudeDesktopResets")
    static var hasAccess: Bool { AXIsProcessTrusted() }
    private let didRead: (ClaudeDesktopResetReading?) -> Void
    private let worker = DispatchQueue(label: "local.codex.battery.claude-desktop-resets", qos: .utility)
    private var activationObserver: NSObjectProtocol?
    private var timer: Timer?
    private var reading = false
    private var lastPage: ClaudeDesktopUsageReader.Page?
    private var lastReadStage: String?
    private var pendingAbsence = false

    init(didRead: @escaping (ClaudeDesktopResetReading?) -> Void) {
        self.didRead = didRead
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.checkForeground() }
        syncOpenPage()
    }

    deinit {
        timer?.invalidate()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    func checkForeground() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == Self.bundleID, Self.hasAccess else {
            timer?.invalidate()
            timer = nil
            lastPage = nil
            pendingAbsence = false
            return
        }
        guard timer == nil else { return }
        let next = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        next.tolerance = 0.5
        RunLoop.main.add(next, forMode: .common)
        timer = next
        poll()
    }

    /// A one-shot read handles an already open usage page at startup or when the menu is opened.
    func syncOpenPage() {
        checkForeground()
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
        guard !reading else { return }
        reading = true
        worker.async { [weak self] in
            let reader = ClaudeDesktopUsageReader()
            let page = reader.read(pid: pid)
            let stage = reader.stage
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reading = false
                guard Self.hasAccess,
                      !requireForeground || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                if self.lastReadStage != stage {
                    Self.logger.info("Desktop sync: \(stage, privacy: .public)")
                    self.lastReadStage = stage
                }
                self.publish(page)
            }
        }
    }

    private func publish(_ page: ClaudeDesktopUsageReader.Page?) {
        // A loaded page without a reset section can arrive before the grants. Confirm on the next read.
        if page == .absent, !pendingAbsence {
            pendingAbsence = true
            return
        }
        pendingAbsence = page == .absent
        guard page != lastPage else { return }
        lastPage = page
        switch page {
        case .resets(let value): didRead(value)
        case .absent: didRead(nil)
        case nil: break
        }
    }
}

private final class ClaudeDesktopUsageReader {
    enum Page: Equatable { case resets(ClaudeDesktopResetReading), absent }

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
    private(set) var stage = "window_unavailable"

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
        for _ in 0..<9 {
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
        if let reading = ClaudeDesktopResetReading.parseUsageLabels(labels, at: Date()) {
            stage = "read_resets"
            return .resets(reading)
        }
        if labels.contains(where: ClaudeDesktopResetReading.sectionNames.contains) {
            stage = "reset_count_unreadable"
            return nil
        }
        let loaded = labels.contains(where: ClaudeDesktopResetReading.nextSectionNames.contains)
            && children.contains { element, node in
                guard node.role == kAXProgressIndicatorRole else { return false }
                let value = attribute(kAXValueAttribute, of: element)
                return value is NSNumber || (value as? String)?.isEmpty == false
            }
        if loaded { stage = "no_reset_section" }
        return loaded ? .absent : nil
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
