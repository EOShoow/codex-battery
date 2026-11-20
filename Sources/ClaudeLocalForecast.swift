import AppKit
import Foundation

/// Claude Desktop's v2 tray history. Times and percentages come from the samples, not the file's mtime.
struct ClaudePlanHistory {
    struct Sample: Equatable {
        let time: Date
        let week: Double
        let fiveHour: Double?
    }
    let organization: String
    let samples: [Sample]     // current organization's uninterrupted run, in chronological order
    let singleOrganization: Bool
    var latest: Sample { samples[samples.count - 1] }
    private static let sizeLimit = 256 * 1024

    static func read(_ url: URL?, at now: Date) -> Self? {
        guard let url, let info = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              info.isRegularFile == true, let size = info.fileSize, size <= sizeLimit,
              let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: sizeLimit + 1), data.count <= sizeLimit,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              number(root["version"]) == 2, let raw = root["samples"] as? [[String: Any]] else { return nil }

        var timed: [(Date, [String: Any])] = []
        for entry in raw {
            guard let ms = number(entry["t"]), ms > 0, ms <= now.timeIntervalSince1970 * 1000 else { continue }
            timed.append((Date(timeIntervalSince1970: ms / 1000), entry))
        }
        timed.sort { $0.0 > $1.0 }
        guard let org = timed.first?.1["org"] as? String, !org.isEmpty else { return nil }
        var samples: [Sample] = []
        let singleOrganization = timed.allSatisfy { $0.1["org"] as? String == org }
        for (time, entry) in timed {
            guard entry["org"] as? String == org else {
                // Different organizations at the same instant leave the active organization ambiguous.
                if time == timed.first?.0 { return nil }
                break
            }
            guard let usage = entry["u"] as? [String: Any], let week = percent(usage["sd"]) else {
                if samples.isEmpty { return nil }
                break
            }
            let sample = Sample(time: time, week: week, fiveHour: percent(usage["fh"]))
            if let newer = samples.last, newer.time == time {
                guard newer == sample else { return nil }
            } else {
                samples.append(sample)
            }
        }
        guard !samples.isEmpty else { return nil }
        return Self(organization: org, samples: samples.reversed(), singleOrganization: singleOrganization)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }

    private static func percent(_ value: Any?) -> Double? {
        number(value).flatMap { (0...100).contains($0) ? $0 : nil }
    }

    var currentRun: ArraySlice<Sample> {
        let lastDrop = samples.indices.dropFirst().last { samples[$0].week < samples[$0 - 1].week }
        return samples[(lastDrop ?? 0)...]
    }

    /// Old Battery histories have no organization field. Require two distinct matching levels in
    /// the same uninterrupted week before using their reset or model data as a forecast reference.
    func matchingAccount(_ history: ClaudeUsageHistory) -> ProviderQuotaSnapshot? {
        guard singleOrganization, let snapshot = history.lastWeeklySnapshot(at: latest.time),
              let reset = snapshot.week?.resetsAt, let total = snapshot.week?.used,
              let stored = history.windows["seven_day"] else { return nil }
        let run = currentRun
        guard let first = run.first, first.time <= snapshot.checkedAt,
              latest.time >= snapshot.checkedAt, latest.time < reset, latest.week >= total.rounded(.down) else { return nil }
        let start = reset.addingTimeInterval(-ClaudeUsageHistory.weekSeconds)
        let accountSamples = stored.samples.filter {
            $0.count == 2 && $0[0].isFinite && (0...100).contains($0[1]) && $0[0] <= snapshot.checkedAt.timeIntervalSince1970
        }.sorted { $0[0] < $1[0] }
        var cursor = 0
        var matchedLow = Double.infinity
        var matchedHigh = -Double.infinity
        for sample in run where sample.time >= start {
            let t = sample.time.timeIntervalSince1970
            while cursor < accountSamples.count && accountSamples[cursor][0] < t - 300 { cursor += 1 }
            var difference = Double.infinity
            for candidate in accountSamples[cursor...] {
                if candidate[0] > t + 300 { break }
                difference = min(difference, abs(candidate[1] - sample.week))
            }
            if difference.isFinite && difference > 1 { return nil }
            if difference <= 0.5 {
                matchedLow = min(matchedLow, sample.week)
                matchedHigh = max(matchedHigh, sample.week)
            }
        }
        return matchedHigh - matchedLow >= 2 ? snapshot : nil
    }

    /// Only two closely bracketed drops one week apart support an estimated weekly boundary.
    /// An isolated drop may be a manually redeemed reset. Never roll a missed week forward.
    func estimatedReset(at now: Date) -> Date? {
        let drops = zip(samples, samples.dropFirst()).filter { $0.0.week > $0.1.week }
        guard drops.count >= 2 else { return nil }
        let week = ClaudeUsageHistory.weekSeconds
        let pair = drops.suffix(2)
        guard pair.allSatisfy({ $0.0.week - $0.1.week >= 2 && $0.1.week <= 5 && $0.1.time.timeIntervalSince($0.0.time) <= 6 * 3600 }),
              let previous = pair.first, let recent = pair.last else { return nil }
        let lower = max(previous.0.time.addingTimeInterval(week), recent.0.time)
        let upper = min(previous.1.time.addingTimeInterval(week), recent.1.time)
        guard lower <= upper, lower.addingTimeInterval(week) > now else { return nil }
        return lower.addingTimeInterval(week + upper.timeIntervalSince(lower) / 2)
    }

    func matchesPage(_ page: ClaudeDesktopQuotaSnapshot) -> Bool {
        currentRun.contains {
            abs($0.time.timeIntervalSince(page.updatedAt)) <= 300 && $0.week == page.weekUsed &&
                (page.fiveHourUsed == nil || $0.fiveHour == page.fiveHourUsed)
        }
    }
}

/// Optional readings the user entered from Usage. Each meter keeps its own reset and sample time.
struct ClaudeLocalCalibration: Codable {
    struct Reading: Codable {
        let used: Double
        let time: Date
        let reset: Date

        func isInCycle(at now: Date) -> Bool {
            (0...100).contains(used) && time <= now && reset > now &&
                reset.timeIntervalSince(time) <= ClaudeUsageHistory.weekSeconds
        }
    }
    let organization: String
    var total: Reading?
    var fable: Reading?
}

struct ClaudeLocalForecast {
    typealias Reading = ClaudeLocalCalibration.Reading
    enum Source { case matchedHistory, estimatedReset, manual, desktop }
    let plan: ClaudePlanHistory
    let weekReset: Date?
    let resetSource: Source
    let fable: Reading?
    let fableSource: Source

    init(plan: ClaudePlanHistory, history: ClaudeUsageHistory?, page: ClaudeDesktopQuotaSnapshot?,
         calibration: ClaudeLocalCalibration?, now: Date) {
        self.plan = plan
        let manual = calibration?.organization == plan.organization ? calibration : nil
        let account = history.flatMap { plan.matchingAccount($0) }
        let run = plan.currentRun
        let lastDrop = run.startIndex > 0 ? run.first?.time : nil
        if let entry = manual?.total, entry.isInCycle(at: max(plan.latest.time, entry.time)), entry.time <= now,
           plan.latest.time >= entry.reset.addingTimeInterval(-ClaudeUsageHistory.weekSeconds),
           lastDrop.map({ $0 <= entry.time }) ?? true,
           plan.latest.time <= entry.time || plan.latest.week >= entry.used {
            weekReset = entry.reset
            resetSource = .manual
        } else if let reset = account?.week?.resetsAt {
            weekReset = reset
            resetSource = .matchedHistory
        } else {
            weekReset = plan.estimatedReset(at: now)
            resetSource = .estimatedReset
        }

        var model: Reading?
        var source = Source.matchedHistory
        if let account, let window = account.modelWindows["seven_day_fable"], let reset = window.resetsAt {
            let previous = Reading(used: window.used, time: account.checkedAt, reset: reset)
            if previous.isInCycle(at: now) { model = previous }
        }
        if let entry = manual?.fable, entry.isInCycle(at: now), model.map({ $0.time <= entry.time }) ?? true {
            model = entry
            source = .manual
        }
        if let previous = model, account != nil, let page, page.updatedAt >= previous.time, page.updatedAt <= now,
           let used = page.fableUsed, plan.matchesPage(page) {
            // A drop in Fable may mean it was separately reset. Its old reset is then unusable.
            let reading = Reading(used: used, time: page.updatedAt, reset: previous.reset)
            model = used >= previous.used && reading.isInCycle(at: now) ? reading : nil
            source = .desktop
        }
        self.fable = model
        self.fableSource = source
    }

    var snapshot: ProviderQuotaSnapshot {
        let last = plan.latest
        return ProviderQuotaSnapshot(checkedAt: last.time,
            fiveHour: last.fiveHour.map { ProviderQuotaWindow(used: $0, resetsAt: nil) },
            week: ProviderQuotaWindow(used: last.week, resetsAt: weekReset))
    }

    func rows(at now: Date, chinese: Bool, activity: WeeklyActivitySchedule?) -> [PaceRow] {
        let last = plan.latest
        let fresh = snapshot.isFresh(at: now)
        func t(_ zh: String, _ en: String) -> String { chinese ? zh : en }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        func weekly(_ key: String, _ reading: Reading, _ source: String, historical: Bool, stale: Bool) -> PaceRow {
            var row = ClaudeForecast.weeklyRow(key: key, index: 0, usage: reading.used, sampledAt: reading.time.timeIntervalSince1970,
                                               resetAt: reading.reset.timeIntervalSince1970, now: now, chinese: chinese,
                                               stale: stale, activitySchedule: activity)
            let stamp = formatter.string(from: reading.time)
            if historical && row.projectedUsed != nil { row.name += t(" · 旧", " · old") }
            let note = t("\(source) · 读数于 \(stamp)。", "\(source) · sampled \(stamp). ")
            row.tooltip = note + (stale ? t("样本过旧，预测已暂停。", "Sample too old to project.") : row.tooltip)
            return row
        }
        var rows: [PaceRow] = []
        if let reset = weekReset {
            let source: String
            switch resetSource {
            case .manual: source = t("本机记录，手动校准周重置", "Tray history, manually set reset")
            case .matchedHistory: source = t("本机记录，周重置取自同期匹配的历史", "Tray history, reset from matching account history")
            default: source = t("本机记录，重置时间按连续两周的用量回落估算", "Tray history, reset estimated from two weekly drops")
            }
            let total = Reading(used: last.week, time: last.time, reset: reset)
            rows.append(weekly("seven_day", total, source, historical: false, stale: !fresh || reset <= now))
        } else {
            rows.append(shortTermRow(now: now, chinese: chinese))
        }

        if let fable, fable.isInCycle(at: now) {
            let age = now.timeIntervalSince(fable.time)
            let source = fableSource == .manual ? t("手动录入 Fable", "Manual Fable reading")
                : (fableSource == .desktop ? t("Claude Desktop 上次 Fable 读数", "Last Fable reading from Claude Desktop")
                                           : t("本机保存的 Fable 账户读数", "Saved Fable account reading"))
            rows.append(weekly("seven_day_fable", fable, source, historical: age > 900, stale: age > 86400))
        } else {
            rows.append(PaceRow(name: "Fable", color: ClaudeForecast.color("seven_day_fable", index: 0), used: nil,
                                projectedUsed: nil, pace: nil, endText: t("待录入读数", "Reading needed"), tone: .secondaryLabelColor,
                                tooltip: t("在 Claude Code 子菜单录入本周 Fable 已用百分比和它的重置时间。", "Enter Fable usage and its reset in the Claude Code submenu.")))
        }
        return rows
    }

    /// Without a cycle boundary, estimate 24 hours ahead from this run's observed change.
    private func shortTermRow(now: Date, chinese: Bool) -> PaceRow {
        let last = plan.latest
        let fresh = snapshot.isFresh(at: now)
        let ageLimit: TimeInterval = 24 * 3600
        let first = plan.currentRun.first { last.time.timeIntervalSince($0.time) <= ageLimit }
        let left = 100 - last.week
        var end = fresh ? (chinese ? "积累中" : "Building history")
                        : (chinese ? "上次剩 \(Int(left))% · 旧" : "Last left \(Int(left))% · stale")
        var projected: Double?
        var tip = chinese ? "周重置时间未知。积累至少 6 小时的用量记录，或在子菜单校准重置时间。" :
                            "Weekly reset unknown. Allow 6 hours of samples or set the reset in the submenu."
        if fresh, let first, last.time.timeIntervalSince(first.time) >= 6 * 3600 {
            let span = last.time.timeIntervalSince(first.time)
            let used = last.week + (last.week - first.week) * ageLimit / span
            projected = used
            let remaining = Int(max(0, 100 - used).rounded())
            end = chinese ? "24h 后约剩 \(remaining)%" : "~\(remaining)% left in 24h"
            let hours = Int((span / 3600).rounded())
            tip = chinese ? "按最近 \(hours) 小时的实际用量变化估算未来 24 小时，假设期间没有重置。" :
                            "Projects the next 24 hours from the last \(hours) hours of measured use, assuming no reset."
        } else if !fresh {
            tip = chinese ? "Claude Desktop 的本机记录已过期。打开一次 Claude 自带的菜单栏图标可恢复采样。" :
                            "The tray sample is stale. Open Claude's own menu bar icon to resume sampling."
        }
        return PaceRow(name: "Claude", color: .systemPurple, used: last.week, projectedUsed: projected, pace: nil,
                       endText: end, tone: projected.map { PaceRow.tone(remaining: 100 - $0, runsOut: $0 >= 100) } ?? .secondaryLabelColor,
                       tooltip: tip)
    }
}
