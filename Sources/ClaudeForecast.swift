import AppKit
import Foundation

/// Weekly Claude account percentages sampled by the existing quota checks.
/// Only window keys, reset times, check times and used percentages are stored; never tokens or responses.
final class ClaudeUsageHistory {
    struct Window: Codable, Equatable {
        var resetsAt: Double
        var samples: [[Double]] // [unix time, used percent]
    }
    private struct File: Codable {
        var version = 1
        var windows: [String: Window]
    }

    static let weekSeconds: TimeInterval = 7 * 24 * 3600
    private let url: URL?
    private(set) var windows: [String: Window] = [:]

    init(url: URL?) {
        self.url = url
        guard let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 1024 * 1024,
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data), file.version == 1 else { return }
        windows = file.windows
    }

    /// Weekly windows only (`seven_day` and model-specific `seven_day_*`); 5-hour windows are not charted.
    func record(_ snapshot: ProviderQuotaSnapshot) {
        let now = snapshot.checkedAt.timeIntervalSince1970
        var candidates: [(String, ProviderQuotaWindow)] = snapshot.week.map { [("seven_day", $0)] } ?? []
        candidates += snapshot.modelWindows.map { ($0.key, $0.value) }
        for (key, window) in candidates {
            guard let reset = window.resetsAt?.timeIntervalSince1970, reset > now,
                  reset - now <= Self.weekSeconds + 600, window.used.isFinite else { continue }
            var stored = windows[key]
            if stored == nil || abs(stored!.resetsAt - reset) > 300 { stored = Window(resetsAt: reset, samples: []) }
            stored!.resetsAt = reset
            let start = reset - Self.weekSeconds - 300
            stored!.samples.removeAll { $0.count != 2 || $0[0] < start || $0[0] > now + 300 }
            if let last = stored!.samples.last, now - last[0] < 240 { stored!.samples.removeLast() }
            stored!.samples.append([now, window.used])
            if stored!.samples.count > 2100 { stored!.samples.removeFirst(stored!.samples.count - 2100) }
            windows[key] = stored
        }
        windows = windows.filter { $0.value.resetsAt > now - 86400 }
        save()
    }

    private func save() {
        guard let url, let data = try? JSONEncoder().encode(File(windows: windows)) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { /* History is a display aid; failures must not affect quota reads. */ }
    }
}

enum ClaudeForecast {
    static func displayName(_ key: String) -> String {
        if key == "seven_day" { return "Claude" }
        let model = key.replacingOccurrences(of: "seven_day_", with: "").replacingOccurrences(of: "_", with: " ")
        return model.prefix(1).uppercased() + model.dropFirst()
    }

    static func color(_ key: String, index: Int) -> NSColor {
        if key == "seven_day" { return .systemPurple }
        return [NSColor.systemTeal, .systemPink, .systemBrown, .systemIndigo][index % 4]
    }

    /// Average-pace projection: used percent since the window start, extended to the reset.
    /// The window start (reset − 7 days) is an exact 0% anchor, so a projection exists even with little history.
    static func rows(history: ClaudeUsageHistory, now: Date, chinese: Bool) -> [PaceRow] {
        let nowAt = now.timeIntervalSince1970
        let week = ClaudeUsageHistory.weekSeconds
        let keys = history.windows.keys.sorted { a, b in
            a == "seven_day" ? true : (b == "seven_day" ? false : a < b)
        }
        var modelIndex = 0
        var result: [PaceRow] = []
        for key in keys {
            guard let window = history.windows[key], window.resetsAt > nowAt,
                  let last = window.samples.last, last.count == 2 else { continue }
            let color = color(key, index: key == "seven_day" ? 0 : modelIndex)
            if key != "seven_day" { modelIndex += 1 }
            let start = window.resetsAt - week
            let used = max(0, min(100, last[1]))
            let pace = max(0, min(1, (nowAt - start) / week))
            let name = displayName(key)
            let stale = nowAt - last[0] > 15 * 60
            let staleText = stale ? (chinese ? " · 旧" : " · stale") : ""
            let elapsedHours = (last[0] - start) / 3600
            let remainingHours = (window.resetsAt - last[0]) / 3600
            let usedText = chinese ? "本周已用 \(Int(used.rounded()))%" : "\(Int(used.rounded()))% used this week"
            guard elapsedHours >= 6 else {
                result.append(PaceRow(name: name, color: color, used: used, projectedUsed: nil, pace: pace,
                                      endText: (chinese ? "积累中" : "building") + staleText, tone: .secondaryLabelColor,
                                      tooltip: chinese ? "\(name)：\(usedText)。开周不足 6 小时，暂不推算。"
                                                       : "\(name): \(usedText). Under 6 hours into the week; no projection yet."))
                continue
            }
            let rate = used / elapsedHours
            let projected = used + rate * remainingHours
            let endText: String
            if projected >= 100, rate > 0 {
                let early = (window.resetsAt - (last[0] + (100 - used) / rate * 3600)) / 3600
                let earlyText = early >= 24 ? String(format: chinese ? "%.1f 天" : "%.1f days", early / 24)
                                            : String(format: chinese ? "%.0f 小时" : "%.0f hours", early)
                endText = chinese ? "提前 \(earlyText)用完" : "Out \(earlyText) early"
            } else {
                let left = Int(max(0, 100 - projected).rounded())
                endText = chinese ? "重置时剩 \(left)%" : "\(left)% left at reset"
            }
            let reset = DateFormatter()
            reset.dateFormat = "M/d HH:mm"
            let resetText = reset.string(from: Date(timeIntervalSince1970: window.resetsAt))
            result.append(PaceRow(
                name: name, color: color, used: used, projectedUsed: projected, pace: pace, endText: endText + staleText,
                tone: stale ? .secondaryLabelColor : PaceRow.tone(remaining: 100 - projected, runsOut: projected >= 100),
                tooltip: chinese
                    ? "\(name)：\(usedText)，\(endText)（\(resetText) 重置）。按本周平均速度推算，不考虑作息。竖线是均匀用到重置时此刻应在的位置。"
                    : "\(name): \(usedText); \(endText) (resets \(resetText)). Average weekly pace, no activity-hour model. The tick marks where even pacing would be now."))
        }
        return result
    }
}
