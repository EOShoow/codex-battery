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

    /// The last successful weekly reading is for display only. Model readings must come from the same check.
    func lastWeeklySnapshot(at now: Date) -> ProviderQuotaSnapshot? {
        let nowAt = now.timeIntervalSince1970
        func latest(_ window: Window) -> (time: Double, value: ProviderQuotaWindow)? {
            guard window.resetsAt.isFinite, window.resetsAt > nowAt,
                  let sample = window.samples.last, sample.count == 2,
                  sample[0].isFinite, sample[0] <= nowAt,
                  (0...1000).contains(sample[1]), window.resetsAt - sample[0] <= Self.weekSeconds + 600 else { return nil }
            return (sample[0], ProviderQuotaWindow(used: sample[1], resetsAt: Date(timeIntervalSince1970: window.resetsAt)))
        }
        guard let week = windows["seven_day"].flatMap(latest) else { return nil }
        var models: [String: ProviderQuotaWindow] = [:]
        for (key, window) in windows where key.hasPrefix("seven_day_") {
            if let model = latest(window), model.time == week.time { models[key] = model.value }
        }
        return ProviderQuotaSnapshot(checkedAt: Date(timeIntervalSince1970: week.time), fiveHour: nil,
                                     week: week.value, modelWindows: models)
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

    /// Each window's average consumption is projected across the same local activity hours as Codex.
    static func rows(history: ClaudeUsageHistory, now: Date, chinese: Bool,
                     reliable: Bool = true, windowKeys: Set<String>? = nil,
                     activitySchedule: WeeklyActivitySchedule? = nil) -> [PaceRow] {
        let nowAt = now.timeIntervalSince1970
        let week = ClaudeUsageHistory.weekSeconds
        let keys = history.windows.keys.filter { windowKeys?.contains($0) ?? true }.sorted { a, b in
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
            let stale = !reliable || nowAt - last[0] > 15 * 60
            let elapsedHours = (last[0] - start) / 3600
            let remainingHours = (window.resetsAt - last[0]) / 3600
            let usedText = chinese ? "本周已用 \(Int(used.rounded()))%" : "\(Int(used.rounded()))% used this week"
            if stale {
                let remaining = Int((100 - used).rounded(.down))
                result.append(PaceRow(name: name, color: color, used: used, projectedUsed: nil, pace: nil,
                                      endText: chinese ? "上次剩 \(remaining)% · 旧" : "Last left \(remaining)% · stale",
                                      tone: .secondaryLabelColor,
                                      tooltip: chinese ? "上次读数，\(usedText)。等待账户额度更新。"
                                                       : "Last reading, \(usedText). Waiting for updated account quota."))
                continue
            }
            guard elapsedHours >= 6 else {
                result.append(PaceRow(name: name, color: color, used: used, projectedUsed: nil, pace: pace,
                                      endText: chinese ? "积累中" : "building", tone: .secondaryLabelColor,
                                      tooltip: chinese ? "\(name)：\(usedText)。开周不足 6 小时，暂不推算。"
                                                       : "\(name): \(usedText). Under 6 hours into the week; no projection yet."))
                continue
            }
            let elapsedWeight = activitySchedule.map { max($0.weight(from: start, to: last[0]), 1 / 60) } ?? elapsedHours
            let remainingWeight = activitySchedule?.weight(from: last[0], to: window.resetsAt) ?? remainingHours
            let rate = used / elapsedWeight
            let projected = used + rate * remainingWeight
            let endText: String
            if projected >= 100, rate > 0 {
                let weightToExhaust = (100 - used) / rate
                let exhaustAt: Double
                if let activitySchedule {
                    exhaustAt = activitySchedule.timestamp(from: last[0], to: window.resetsAt,
                                                            requiring: weightToExhaust) ?? window.resetsAt
                } else {
                    exhaustAt = last[0] + weightToExhaust * 3600
                }
                let early = max(0, (window.resetsAt - exhaustAt) / 3600)
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
            let method: String
            if activitySchedule != nil {
                method = chinese ? "与 Codex 共用本机作息，按此额度本周的活跃时段消耗速度推算。"
                                 : "Uses the same local activity hours as Codex and this quota's pace during those hours."
            } else {
                method = chinese ? "作息样本不足，暂按本周平均速度推算。"
                                 : "While activity history builds, this uses the average pace over elapsed hours."
            }
            result.append(PaceRow(
                name: name, color: color, used: used, projectedUsed: projected, pace: pace, endText: endText,
                tone: PaceRow.tone(remaining: 100 - projected, runsOut: projected >= 100),
                tooltip: chinese
                    ? "\(name) · \(usedText)，\(endText)（\(resetText) 重置）。\(method)竖线是均匀用到重置时此刻应在的位置。"
                    : "\(name) · \(usedText), \(endText) (resets \(resetText)). \(method) The tick marks where even pacing would be now."))
        }
        return result
    }
}
