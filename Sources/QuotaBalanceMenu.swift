import AppKit
import Foundation

/// Two account windows stay separate; the existing Codex icon and detail views keep their meaning.
final class QuotaBalanceView: NSView {
    static let height: CGFloat = 222
    override var isFlipped: Bool { true }

    init(codex: ProviderQuotaSnapshot?, claude: ProviderQuotaSnapshot?, codexReliable: Bool,
         claudeReliable: Bool, claudeStatus: String, now: Date, chinese: Bool,
         desktopResets: ClaudeDesktopResetSnapshot? = nil, claudeFromDesktop: Bool = false,
         localOnly: Bool = false, localForecast: ClaudeLocalForecast? = nil,
         localResets: ClaudeUsageCache.ResetSample? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: Self.height))
        func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, bold: Bool = false,
                  secondary: Bool = false, tooltip: String? = nil) {
            let field = NSTextField(labelWithString: value)
            field.frame = NSRect(x: x, y: y, width: width, height: 22)
            field.font = bold ? .boldSystemFont(ofSize: 13) : .menuFont(ofSize: 12)
            field.textColor = secondary ? .secondaryLabelColor : .labelColor
            field.lineBreakMode = .byTruncatingTail
            field.toolTip = tooltip ?? value
            addSubview(field)
        }
        func date(_ value: Date?, format: String) -> String {
            guard let value else { return "—" }
            let formatter = DateFormatter()
            formatter.dateFormat = format
            return formatter.string(from: value)
        }
        func window(_ value: ProviderQuotaWindow?) -> String {
            guard let value else { return "—" }
            if let reset = value.resetsAt, reset <= now { return chinese ? "待更新" : "Reset; refresh needed" }
            return "\(value.remaining)%"
        }
        text(chinese ? "剩余额度" : "Remaining", x: 16, y: 8, width: 88, bold: true)
        text("Codex", x: 112, y: 8, width: 155, bold: true)
        text("Claude Code", x: 282, y: 8, width: 162, bold: true)
        text(chinese ? "5 小时" : "5 hours", x: 16, y: 36, width: 88)
        text(chinese ? "每周" : "Weekly", x: 16, y: 64, width: 88)
        text(chinese ? "可用重置" : "Resets", x: 16, y: 92, width: 88,
             tooltip: chinese ? "可手动使用的额度重置次数；两家各自独立" : "Manually redeemable limit resets; separate per provider")
        text(chinese ? "周重置" : "Week reset", x: 16, y: 118, width: 88, secondary: true)
        text(chinese ? "数据于" : "Data at", x: 16, y: 144, width: 88, secondary: true)
        func resets(_ stock: ProviderResetStock?) -> String {
            guard let stock else { return "—" }
            let count = chinese ? "\(stock.count) 次" : "\(stock.count)"
            guard stock.count > 0, let nearest = stock.nearestExpiry(at: now) else { return count }
            let day = date(nearest, format: "M/d")
            return count + (chinese ? " · 最近 \(day) 到期" : " · next expires \(day)")
        }
        for (snapshot, reliable, x, desktop, fromDesktop) in [(codex, codexReliable, CGFloat(112), nil, false),
                                                            (claude, claudeReliable, CGFloat(282), desktopResets, claudeFromDesktop)] {
            let stale = snapshot.map { !reliable || !$0.isFresh(at: now) } ?? false
            let suffix = stale ? (chinese ? " · 旧" : " · stale") : ""
            let reset = date(snapshot?.fiveHour?.resetsAt, format: "M/d HH:mm")
            let desktopLabel = chinese ? "Claude Desktop 用量页" : "Claude Desktop Usage page"
            let local = localOnly && x == 282
            let localLabel = chinese ? "Claude Desktop 本机用量记录" : "Claude Desktop tray history"
            text(window(snapshot?.fiveHour) + (snapshot?.fiveHour == nil ? "" : suffix), x: x, y: 36, width: 162,
                 tooltip: local ? localLabel : (fromDesktop ? desktopLabel : (chinese ? "5 小时窗口重置：" : "5-hour reset: ") + reset))
            // Model-specific weekly limits (e.g. Fable) are limits of their own; show them beside the week.
            let models = (snapshot?.modelWindows ?? [:]).sorted { $0.key < $1.key }
                .filter { fromDesktop || (!$0.value.notStarted && $0.value.isCurrent(at: now)) }
            var modelText = models.prefix(2).map { " · \(ClaudeForecast.displayName($0.key)) \($0.value.remaining)%" }.joined()
            var modelTip = models.map { key, value in
                let reading = ClaudeForecast.displayName(key) + (chinese ? " 周剩余 \(value.remaining)%" : " weekly left \(value.remaining)%")
                guard value.resetsAt != nil else { return reading }
                return reading + (chinese ? "，重置 " : ", resets ") + date(value.resetsAt, format: "M/d HH:mm")
            }
            if local, let forecast = localForecast, let fable = forecast.fable, fable.isInCycle(at: now) {
                let remaining = ProviderQuotaWindow(used: fable.used, resetsAt: fable.reset).remaining
                let old = now.timeIntervalSince(fable.time) > 15 * 60
                modelText += " · Fable \(remaining)%" + (old ? (chinese ? " · 旧" : " · old") : "")
                modelTip.append("Fable \(remaining)% · " + forecast.fableSourceLabel(chinese: chinese) + " · " +
                    date(fable.time, format: "M/d HH:mm:ss") + (chinese ? "，重置 " : ", resets ") + date(fable.reset, format: "M/d HH:mm"))
            }
            let historyTip = stale && !fromDesktop ? [
                (chinese ? "上次读数 " : "Last reading ") + date(snapshot?.checkedAt, format: "M/d HH:mm")
            ] : []
            let weeklyTip = historyTip + modelTip
            text(window(snapshot?.week) + (snapshot?.week == nil ? "" : suffix) + modelText, x: x, y: 64, width: 162,
                 tooltip: weeklyTip.isEmpty ? nil : weeklyTip.joined(separator: "\n"))
            let stock = desktop?.reading.stock(at: now) ?? snapshot?.claudeResets?.stock(at: now) ?? snapshot?.resets
            let grants = desktop?.reading.grants ?? snapshot?.claudeResets?.grants ?? []
            var grantLines = grants.filter { $0.isAvailable(at: now) }
                .map { QuotaBalanceView.describe($0, chinese: chinese) }
            if let desktop { grantLines.append(Self.desktopSyncLabel(desktop.syncedAt, chinese: chinese)) }
            let resetSuffix = stock != nil && desktop == nil ? suffix : ""
            if local {
                let labels = Self.localResetLabels(localResets, at: now, chinese: chinese)
                text(labels.summary, x: x, y: 92, width: 162, tooltip: labels.details.joined(separator: "\n"))
            } else {
                text(resets(stock) + resetSuffix, x: x, y: 92, width: 162,
                     tooltip: grantLines.isEmpty ? nil : grantLines.joined(separator: "\n"))
            }
            let approximate = local && localForecast?.resetSource == .estimatedReset && snapshot?.week?.resetsAt != nil
            text((approximate ? "≈ " : "") + date(snapshot?.week?.resetsAt, format: "M/d HH:mm"), x: x, y: 118, width: 162, secondary: true)
            let timestamp = fromDesktop ? (chinese ? "约 " : "≈ ") + date(snapshot?.checkedAt, format: "M/d HH:mm")
                : date(snapshot?.checkedAt, format: "M/d HH:mm:ss")
            text(timestamp, x: x, y: 144, width: 162, secondary: true,
                 tooltip: local ? localLabel : (fromDesktop ? desktopLabel + " · " + timestamp : nil))
        }
        let advice = QuotaBalanceAdvice.make(codex: codex, claude: claude, codexReliable: codexReliable,
                                             claudeReliable: claudeReliable && !claudeFromDesktop, now: now, chinese: chinese)
        let title = localOnly ? (chinese ? "Claude 本机用量预测" : "Local Claude usage forecast") : advice.title
        text(title, x: 16, y: 172, width: 428, bold: true, tooltip: localOnly ? claudeStatus : advice.detail)
        text(claudeStatus, x: 16, y: 194, width: 428, secondary: true)
        toolTip = localOnly ? claudeStatus : advice.detail
    }

    /// "5-hour reset ×2 · expires 12/1": what one Claude Code grant clears, how many are left, and until when.
    static func describe(_ grant: ClaudeResetGrant, chinese: Bool) -> String {
        let kind: String
        switch grant.type {
        case "session": kind = chinese ? "5 小时重置" : "5-hour reset"
        case "weekly": kind = chinese ? "每周重置" : "Weekly reset"
        case "full": kind = chinese ? "完整重置" : "Full reset"
        case "fable": kind = chinese ? "Fable 重置" : "Fable reset"
        default: kind = grant.label.isEmpty ? (chinese ? "重置" : "Reset") : grant.label
        }
        var line = "\(kind) ×\(grant.resetsLeft)"
        if let end = grant.endsAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/M/d HH:mm"
            line += (chinese ? " · 到期 " : " · expires ") + formatter.string(from: end)
        }
        return line
    }

    static func localResetLabels(_ sample: ClaudeUsageCache.ResetSample?, at now: Date, chinese: Bool) -> (summary: String, details: [String]) {
        guard let sample else {
            return ("—", [chinese ? "等待 Claude Desktop 缓存重置明细，可在「设置 → 使用情况」查看。" :
                                   "Waiting for reset details from Claude Desktop. See Settings → Usage."])
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm:ss"
        var details = [(chinese ? "Claude Desktop 重置明细采样于 " : "Claude Desktop resets sampled ") + formatter.string(from: sample.time)]
        guard let stock = sample.value?.stock(at: now) else {
            return ("—", details + [chinese ? "重置数量暂不可用" : "Reset count unavailable"])
        }
        var summary = chinese ? "\(stock.count) 次" : "\(stock.count)"
        if let nearest = stock.nearestExpiry(at: now) {
            formatter.dateFormat = "M/d HH:mm"
            let short = formatter.string(from: nearest)
            summary += chinese ? " · \(short) 到期" : " · exp \(short)"
            formatter.dateFormat = "yyyy/M/d HH:mm"
            details.append((chinese ? "最近已知到期时间 " : "Next known expiry ") + formatter.string(from: nearest))
        } else if stock.count > 0 {
            details.append(chinese ? "尚无到期时间" : "Expiry time unavailable")
        }
        if sample.isStale(at: now) { summary += chinese ? " · 旧" : " · old" }
        return (summary, details)
    }

    static func desktopSyncLabel(_ syncedAt: Date, chinese: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        let time = formatter.string(from: syncedAt)
        return chinese ? "Claude Desktop 同步于 \(time)" : "Synced from Claude Desktop at \(time)"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

final class QuotaBalanceMenuController: NSObject {
    static let enabledKey = "claudeQuotaEnabled"
    static let localOnlyKey = "claudeLocalForecastOnly"
    private static let calibrationKey = "claudeLocalForecastCalibration"
    private static let localResetKey = "claudeLocalResetInventory"
    private struct StoredLocalResets: Codable {
        let organization: String
        let sample: ClaudeUsageCache.ResetSample
    }
    private static let desktopSyncKey = "claudeDesktopSyncEnabled"
    private static let nextCheckKey = "claudeQuotaNextCheck"
    private static let cooldownKey = "claudeQuotaCooldown"
    private static let lastHTTPAttemptKey = "claudeQuotaLastHTTPAttempt"
    private static let credentialBlockedKey = "claudeQuotaCredentialBlocked"
    private static let lastOutcomeKey = "claudeQuotaLastOutcome"
    private static let lastOutcomeAtKey = "claudeQuotaLastOutcomeAt"
    private static let lastShapeKey = "claudeQuotaLastResponseShape"
    private static let desktopResetsKey = "claudeDesktopResets"
    private static let desktopQuotaKey = "claudeDesktopQuota"
    let item = NSMenuItem(title: "Codex + Claude", action: nil, keyEquivalent: "")
    let settingsItem = NSMenuItem(title: "Claude Code", action: nil, keyEquivalent: "")
    var onChange: (() -> Void)?
    var onSettingsChange: (() -> Void)?
    var onDesktopQuotaSync: (() -> Void)?
    private let defaults: UserDefaults
    private let chinese: Bool
    private let client: ClaudeQuotaClient
    private let credentialLoader: () throws -> ClaudeQuotaCredential
    private let desktopAccess: () -> Bool
    private let diagnosticURL: URL?
    private let historyURL: URL?
    private let planHistoryURL: URL?
    private var cachedUsage: (organization: String, readings: ClaudeUsageCache.Readings)?
    var localResetSample: ClaudeUsageCache.ResetSample? { localOnly ? cachedUsage?.readings.resets : nil }
    private(set) var localForecast: ClaudeLocalForecast?
    private(set) lazy var history = ClaudeUsageHistory(url: historyURL)
    private var requestsStarted = 0
    private var request: URLSessionDataTask?
    private var generation = 0
    private var checking = false
    private var failures = 0
    private var identity: String?
    private var claude: ProviderQuotaSnapshot?
    private(set) var desktopResets: ClaudeDesktopResetSnapshot?
    private lazy var desktopQuota = defaults.data(forKey: Self.desktopQuotaKey)
        .flatMap { try? JSONDecoder().decode(ClaudeDesktopQuotaSnapshot.self, from: $0) }
    private var codex: ProviderQuotaSnapshot?
    private var codexReliable = false
    private var lastError: ClaudeQuotaError?
    private var wasUsingDesktopQuotaFallback = false

    init(defaults: UserDefaults = .standard, chinese: Bool? = nil,
         client: ClaudeQuotaClient = ClaudeQuotaClient(),
         diagnosticURL: URL? = nil,
         historyURL: URL? = nil,
         planHistoryURL: URL? = nil,
         desktopAccess: @escaping () -> Bool = { ClaudeDesktopResetMonitor.hasAccess },
         credentialLoader: @escaping () throws -> ClaudeQuotaCredential = ClaudeQuotaCredential.load) {
        self.defaults = defaults
        self.chinese = chinese ?? (Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false)
        self.client = client
        self.diagnosticURL = diagnosticURL
        self.historyURL = historyURL
        self.planHistoryURL = planHistoryURL
        self.desktopAccess = desktopAccess
        self.credentialLoader = credentialLoader
        super.init()
        if defaults.object(forKey: Self.desktopSyncKey) == nil, let snapshot = storedDesktopResets() {
            // Earlier builds saved a snapshot only after the user's Accessibility grant and a successful read.
            defaults.set(true, forKey: Self.desktopSyncKey)
            if !localOnly { desktopResets = snapshot }
        } else if desktopSyncEnabled {
            desktopResets = storedDesktopResets()
        }
        // Older versions stored a local credential retry in both scheduling fields.
        // An HTTP attempt always cleared the credential-blocked flag before setting its own cooldown.
        if defaults.bool(forKey: Self.credentialBlockedKey),
           defaults.object(forKey: Self.lastOutcomeKey) == nil,
           let legacyCooldown = defaults.object(forKey: Self.cooldownKey) as? Date,
           defaults.object(forKey: Self.nextCheckKey) as? Date == legacyCooldown {
            defaults.removeObject(forKey: Self.cooldownKey)
            defaults.removeObject(forKey: Self.nextCheckKey)
        }
        if localOnly { readLocalForecast(at: Date()) }
        rebuild()
    }

    var localOnly: Bool { defaults.bool(forKey: Self.localOnlyKey) }
    var enabled: Bool { !localOnly && defaults.bool(forKey: Self.enabledKey) }
    var desktopSyncEnabled: Bool { !localOnly && defaults.bool(forKey: Self.desktopSyncKey) }
    var active: Bool { localOnly || enabled || desktopSyncEnabled }
    var desktopQuotaFallbackActive: Bool {
        enabled && desktopSyncEnabled && defaults.string(forKey: Self.lastOutcomeKey) == ClaudeQuotaError.loginExpired.outcome
    }
    var currentQuotas: (codex: ProviderQuotaSnapshot?, claude: ProviderQuotaSnapshot?, codexReliable: Bool, claudeReliable: Bool) {
        (codex, enabled ? claude : nil, codexReliable, enabled && lastError == nil)
    }

    func displayedClaude(at now: Date) -> (snapshot: ProviderQuotaSnapshot?, reliable: Bool, fromDesktop: Bool) {
        if localOnly {
            let snapshot = localForecast?.snapshot
            let currentWeek = snapshot?.week?.resetsAt.map { $0 > now } ?? true
            return (snapshot, currentWeek && snapshot?.isFresh(at: now) == true, false)
        }
        guard enabled else { return (nil, false, false) }
        if let claude { return (claude, lastError == nil && claude.isFresh(at: now), false) }
        if desktopQuotaFallbackActive, let desktopQuota {
            let snapshot = desktopQuota.quota
            return (snapshot, snapshot.isFresh(at: now), true)
        }
        // A missing login or a rejected account may be a sign-out or account change.
        let lastOutcome = defaults.string(forKey: Self.lastOutcomeKey)
        guard lastOutcome == "ok" || lastOutcome == ClaudeQuotaError.loginExpired.outcome else { return (nil, false, false) }
        return (history.lastWeeklySnapshot(at: now), false, false)
    }
    private func t(_ zh: String, _ en: String) -> String { chinese ? zh : en }

    private var calibration: ClaudeLocalCalibration? {
        defaults.data(forKey: Self.calibrationKey).flatMap { try? JSONDecoder().decode(ClaudeLocalCalibration.self, from: $0) }
    }

    private func readLocalForecast(at now: Date) {
        let outcome = defaults.string(forKey: Self.lastOutcomeKey)
        let allowHistory = outcome == "ok" || outcome == ClaudeQuotaError.loginExpired.outcome
        guard let planHistoryURL, let plan = ClaudePlanHistory.read(planHistoryURL, at: now) else {
            cachedUsage = nil
            localForecast = nil
            return
        }
        let directory = planHistoryURL.deletingLastPathComponent().appendingPathComponent("Cache/Cache_Data", isDirectory: true)
        let previous = previousLocalReadings(organization: plan.organization)
        let readings = ClaudeUsageCache.latest(in: directory, organization: plan.organization, at: now, previous: previous)
        if let resets = readings.resets, resets != previous.resets {
            let record = StoredLocalResets(organization: plan.organization, sample: resets)
            if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: Self.localResetKey) }
        }
        cachedUsage = (plan.organization, readings)
        localForecast = ClaudeLocalForecast(plan: plan, history: allowHistory ? history : nil, page: allowHistory ? desktopQuota : nil,
                                           calibration: calibration, cachedUsage: readings.fable, now: now)
    }

    private func previousLocalReadings(organization: String) -> ClaudeUsageCache.Readings {
        if let cachedUsage, cachedUsage.organization == organization { return cachedUsage.readings }
        guard let data = defaults.data(forKey: Self.localResetKey), data.count <= 256 * 1024,
              let record = try? JSONDecoder().decode(StoredLocalResets.self, from: data),
              record.organization == organization else { return .init() }
        let grants = record.sample.value?.grants ?? []
        guard grants.count <= 256, grants.allSatisfy({ (0...10_000).contains($0.resetsLeft) }) else { return .init() }
        return .init(resets: record.sample)
    }

    @objc private func toggleLocalForecast() { setLocalOnly(!localOnly) }

    func setLocalOnly(_ value: Bool) {
        guard localOnly != value else { return }
        cancelAccountCheck()
        defaults.set(value, forKey: Self.localOnlyKey)
        desktopResets = desktopSyncEnabled ? storedDesktopResets() : nil
        if value { readLocalForecast(at: Date()) } else { localForecast = nil; cachedUsage = nil }
        rebuild()
        onSettingsChange?()
    }

    func updateCodex(_ snapshot: ProviderQuotaSnapshot?, reliable: Bool) {
        codex = snapshot
        codexReliable = reliable
        rebuild()
    }

    func updateDesktopResets(_ reading: ClaudeDesktopResetReading?, now: Date = Date()) {
        guard desktopSyncEnabled else { return }
        guard reading != nil || desktopResets != nil else { return }
        desktopResets = reading.map { ClaudeDesktopResetSnapshot(reading: $0, syncedAt: now) }
        defaults.set(desktopResets.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.desktopResetsKey)
        rebuild()
    }

    func updateDesktopQuota(_ snapshot: ClaudeDesktopQuotaSnapshot) {
        guard desktopQuotaFallbackActive, snapshot != desktopQuota else { return }
        desktopQuota = snapshot
        defaults.set(try? JSONEncoder().encode(snapshot), forKey: Self.desktopQuotaKey)
        rebuild()
    }

    private func storedDesktopResets() -> ClaudeDesktopResetSnapshot? {
        defaults.data(forKey: Self.desktopResetsKey)
            .flatMap { try? JSONDecoder().decode(ClaudeDesktopResetSnapshot.self, from: $0) }
    }

    @objc private func toggleDesktopSync() { setDesktopSyncEnabled(!desktopSyncEnabled) }

    func setDesktopSyncEnabled(_ value: Bool) {
        guard !localOnly else { return }
        defaults.set(value, forKey: Self.desktopSyncKey)
        desktopResets = value ? storedDesktopResets() : nil
        rebuild()
        onSettingsChange?()
    }

    func claudeResetStock(at now: Date) -> ProviderResetStock? {
        if localOnly { return localResetSample?.value?.stock(at: now) }
        return desktopResets?.reading.stock(at: now) ?? claude?.claudeResets?.stock(at: now) ?? claude?.resets
    }

    func menuWillOpen() {
        if localOnly { refreshIfDue(); return }
        rebuild()
        refreshIfDue()
    }

    /// Shares existing refresh opportunities; no timer and no model request.
    func refreshIfDue(manual: Bool = false, now: Date = Date()) {
        if localOnly {
            readLocalForecast(at: now)
            rebuild(at: now)
            return
        }
        guard enabled, !checking else { return }
        let next = defaults.object(forKey: Self.nextCheckKey) as? Date ?? .distantPast
        let cooldown = defaults.object(forKey: Self.cooldownKey) as? Date ?? .distantPast
        let credentialRecovery = manual && defaults.bool(forKey: Self.credentialBlockedKey)
        guard now >= cooldown || credentialRecovery else { return }
        if let last = defaults.object(forKey: Self.lastHTTPAttemptKey) as? Date,
           now.timeIntervalSince(last) < (manual ? 60 : 300) { return }
        if manual {
            guard claude.map({ now.timeIntervalSince($0.checkedAt) >= 60 }) ?? true else { return }
        } else if now < next { return }
        checking = true
        generation += 1
        let attempt = generation
        rebuild()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let credentials = Result { try self.credentialLoader() }
            DispatchQueue.main.async { [self] in
                guard self.enabled, attempt == self.generation else { return }
                switch credentials {
                case .failure(let error):
                    self.finishLocal(error as? ClaudeQuotaError ?? .loginRequired, at: now)
                case .success(let credential):
                    if self.identity != credential.identity { self.claude = nil }
                    self.identity = credential.identity
                    self.defaults.set(false, forKey: Self.credentialBlockedKey)
                    self.defaults.set(Date(), forKey: Self.lastHTTPAttemptKey)
                    self.requestsStarted += 1
                    let defaults = self.defaults
                    self.request = self.client.fetch(credential: credential, invalidShape: { shape in
                        DispatchQueue.main.async { defaults.set(shape, forKey: Self.lastShapeKey) }
                    }) { [weak self] result in
                        DispatchQueue.main.async {
                            guard let self, self.enabled, attempt == self.generation else { return }
                            self.finish(result, at: Date())
                        }
                    }
                }
            }
        }
    }

    /// A local credential failure sent nothing to the server, so it neither escalates backoff nor sets
    /// a server cooldown. The keychain is re-read at the next shared refresh opportunity (>= 5 minutes).
    private func finishLocal(_ error: ClaudeQuotaError, at now: Date) {
        checking = false
        request = nil
        claude = nil
        lastError = error
        defaults.set(true, forKey: Self.credentialBlockedKey)
        defaults.set(now.addingTimeInterval(5 * 60), forKey: Self.nextCheckKey)
        record(error.outcome, at: now)
        rebuild()
    }

    private func record(_ outcome: String, at now: Date) {
        if outcome != ClaudeQuotaError.loginExpired.outcome, defaults.object(forKey: Self.desktopQuotaKey) != nil {
            desktopQuota = nil
            defaults.removeObject(forKey: Self.desktopQuotaKey)
        }
        defaults.set(outcome, forKey: Self.lastOutcomeKey)
        defaults.set(now, forKey: Self.lastOutcomeAtKey)
    }

    private func finish(_ result: Result<ProviderQuotaSnapshot, ClaudeQuotaError>, at now: Date) {
        checking = false
        request = nil
        switch result {
        case .success(let snapshot):
            record("ok", at: now)
            history.record(snapshot)
            defaults.removeObject(forKey: Self.lastShapeKey)
            claude = snapshot
            lastError = nil
            failures = 0
            defaults.set(now.addingTimeInterval(5 * 60), forKey: Self.nextCheckKey)
            defaults.removeObject(forKey: Self.cooldownKey)
        case .failure(let error):
            lastError = error
            record(error == .loginRequired ? "http_401" : error.outcome, at: now)
            failures = min(6, failures + 1)
            var delay = min(3600, 300 * pow(2, Double(failures - 1)))
            if case .rateLimited(let retry) = error { delay = max(delay, retry) }
            if error.clearsAccountData { claude = nil }
            defaults.set(now.addingTimeInterval(delay), forKey: Self.nextCheckKey)
            defaults.set(now.addingTimeInterval(delay), forKey: Self.cooldownKey)
        }
        rebuild()
    }

    @objc private func toggle() { setEnabled(!enabled) }

    private func cancelAccountCheck() {
        generation += 1
        request?.cancel()
        request = nil
        checking = false
        claude = nil
        lastError = nil
        identity = nil
    }

    func setEnabled(_ value: Bool) {
        guard !localOnly else { return }
        cancelAccountCheck()
        defaults.set(value, forKey: Self.enabledKey)
        // Keep cooldown across toggles/relaunches; toggling cannot evade a 429.
        rebuild()
        onSettingsChange?()
        if value { refreshIfDue() }
    }

    @objc private func checkNow() {
        if desktopQuotaFallbackActive { onDesktopQuotaSync?() }
        refreshIfDue(manual: true)
    }
    @objc private func openUsage() { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!) }

    @objc private func enterWeeklyReset() { editCalibration(forFable: false) }
    @objc private func enterFable() { editCalibration(forFable: true) }

    private func editCalibration(forFable: Bool) {
        guard localOnly, let localForecast else { return }
        let org = localForecast.plan.organization
        let alert = NSAlert()
        alert.messageText = forFable ? t("录入 Fable 周读数", "Enter Fable weekly reading") : t("校准总周重置时间", "Set weekly reset")
        alert.informativeText = forFable ? t("填写刚看到的 Fable 已用百分比和它自己的重置时间。", "Enter the Fable usage you just observed and its own reset time.")
            : t("填写 Claude 所有模型的本周重置时间。", "Enter this week's reset time for all Claude models.")
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH:mm"
        format.isLenient = false
        let reset = NSTextField(string: "")
        if let known = forFable ? localForecast.fable?.reset : localForecast.weekReset { reset.stringValue = format.string(from: known) }
        reset.placeholderString = "yyyy-MM-dd HH:mm"
        let used = NSTextField(string: "")
        used.placeholderString = "0–100"
        var controls: [NSView] = []
        if forFable { controls += [NSTextField(labelWithString: t("Fable 本周已用（%）", "Fable used this week (%)")), used] }
        controls += [NSTextField(labelWithString: t("重置时间（本地时间）", "Reset in local time")), reset]
        let form = NSStackView(views: controls)
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 5
        for control in [reset, used] { control.widthAnchor.constraint(equalToConstant: 240).isActive = true }
        form.frame = NSRect(x: 0, y: 0, width: 248, height: forFable ? 98 : 48)
        alert.accessoryView = form
        alert.addButton(withTitle: t("保存", "Save"))
        alert.addButton(withTitle: t("取消", "Cancel"))
        alert.window.initialFirstResponder = forFable ? used : reset
        while alert.runModal() == .alertFirstButtonReturn {
            let now = Date()
            let dateInput = reset.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let percentage = Double(used.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            guard let date = format.date(from: dateInput), format.string(from: date) == dateInput, date > now,
                  date.timeIntervalSince(now) <= ClaudeUsageHistory.weekSeconds,
                  !forFable || percentage.map({ (0...100).contains($0) }) == true else {
                alert.informativeText = t("请按 yyyy-MM-dd HH:mm 填写未来七天内的重置时间。已用百分比范围为 0–100。", "Use yyyy-MM-dd HH:mm within the next seven days. Usage must be 0–100 percent.")
                continue
            }
            if !saveCalibration(organization: org, fableUsed: percentage, reset: date, now: now) {
                let message = NSAlert()
                message.messageText = t("本机用量来源已变化，请重读后再录入。", "The local usage source changed. Reload before entering a reading.")
                message.runModal()
            }
            return
        }
    }

    func saveCalibration(organization: String, fableUsed: Double?, reset: Date, now: Date) -> Bool {
        guard localOnly, let plan = ClaudePlanHistory.read(planHistoryURL, at: now), plan.organization == organization else { return false }
        let reading = ClaudeLocalCalibration.Reading(used: fableUsed ?? plan.latest.week, time: now, reset: reset)
        guard reading.isInCycle(at: now) else { return false }
        var saved = calibration.flatMap { $0.organization == organization ? $0 : nil }
            ?? ClaudeLocalCalibration(organization: organization)
        if fableUsed != nil { saved.fable = reading } else { saved.total = reading }
        guard let data = try? JSONEncoder().encode(saved) else { return false }
        defaults.set(data, forKey: Self.calibrationKey)
        refreshIfDue(now: now)
        return true
    }

    private func rebuild(at now: Date = Date()) {
        let fallbackActive = desktopQuotaFallbackActive
        let fallbackStarted = fallbackActive && !wasUsingDesktopQuotaFallback
        wasUsingDesktopQuotaFallback = fallbackActive
        let canReadDesktopQuota = fallbackActive && desktopAccess()
        let shown = displayedClaude(at: now)
        let status: String
        if localOnly {
            if shown.reliable { status = t("用量来自 Claude Desktop 本机记录", "Usage from Claude Desktop's local tray history") }
            else if shown.snapshot != nil { status = t("本机样本已旧 · 打开 Claude 菜单栏可恢复采样", "Tray sample is stale · open Claude's menu bar icon to resume") }
            else { status = t("等待本机用量记录 · 可打开一次 Claude 菜单栏", "Waiting for tray history · open Claude's menu bar icon") }
        }
        else if !enabled { status = t("Claude Desktop 重置同步", "Claude Desktop reset sync") }
        else if fallbackActive && !canReadDesktopQuota { status = t("桌面用量同步 · 等待辅助功能权限", "Desktop quota sync · waiting for Accessibility access") }
        else if shown.fromDesktop {
            status = shown.reliable ? t("Claude Desktop 已同步 · 终端登录已过期", "Synced from Claude Desktop · CLI login expired")
                : t("Claude Desktop 上次读数 · 终端登录已过期", "Last Claude Desktop reading · CLI login expired")
        }
        else if fallbackActive { status = t("Claude Code 登录已过期 · 打开桌面用量页同步", "Claude Code login expired · open Usage in Claude Desktop") }
        else if checking { status = t("正在检查 Claude 账户额度…", "Checking Claude account quota…") }
        else if let lastError { status = "Claude · " + lastError.message(chinese: chinese) }
        else if defaults.bool(forKey: Self.credentialBlockedKey) {
            status = t("Claude 登录凭据待更新 · 更新后自动恢复", "Claude credentials unavailable · recovers after login is renewed")
        }
        else if claude == nil { status = t("Claude 等待下一次额度检查", "Claude awaiting the next quota check") }
        else { status = t("均衡提示仅供参考 · 两家的百分比独立计算", "Pacing hint only · each provider has its own quota") }
        item.view = active ? QuotaBalanceView(codex: codex, claude: shown.snapshot, codexReliable: codexReliable,
                                             claudeReliable: shown.reliable, claudeStatus: status, now: now,
                                             chinese: chinese, desktopResets: desktopResets, claudeFromDesktop: shown.fromDesktop,
                                             localOnly: localOnly, localForecast: localForecast, localResets: localResetSample) : nil
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let local = NSMenuItem(title: t("仅用本机记录预测（免授权）", "Local forecast only (no permissions)"),
                               action: #selector(toggleLocalForecast), keyEquivalent: "")
        local.target = self
        local.state = localOnly ? .on : .off
        submenu.addItem(local)
        let toggle = NSMenuItem(title: t("启用账户额度检查", "Enable account quota checks"), action: #selector(toggle), keyEquivalent: "")
        toggle.target = self
        toggle.isEnabled = !localOnly
        toggle.state = enabled ? .on : .off
        submenu.addItem(toggle)
        let desktopToggle = NSMenuItem(title: t("从 Claude Desktop 同步重置", "Sync resets from Claude Desktop"),
                                       action: #selector(toggleDesktopSync), keyEquivalent: "")
        desktopToggle.target = self
        desktopToggle.isEnabled = !localOnly
        desktopToggle.state = desktopSyncEnabled ? .on : .off
        submenu.addItem(desktopToggle)
        let checkTitle = localOnly ? t("重读本机记录", "Reload local history") : t("立即检查", "Check now")
        let check = NSMenuItem(title: checkTitle, action: #selector(checkNow), keyEquivalent: "")
        check.target = self
        let cooldown = defaults.object(forKey: Self.cooldownKey) as? Date ?? .distantPast
        let lastAttempt = defaults.object(forKey: Self.lastHTTPAttemptKey) as? Date ?? .distantPast
        let canCheckAccount = enabled && !checking && (now >= cooldown || defaults.bool(forKey: Self.credentialBlockedKey))
            && now.timeIntervalSince(lastAttempt) >= 60 && (claude.map { now.timeIntervalSince($0.checkedAt) >= 60 } ?? true)
        check.isEnabled = localOnly || canReadDesktopQuota || canCheckAccount
        submenu.addItem(check)
        if localOnly {
            for (title, action) in [(t("校准总周重置时间…", "Set weekly reset…"), #selector(enterWeeklyReset)),
                                    (t("录入 Fable 周读数…", "Enter Fable reading…"), #selector(enterFable))] {
                let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
                entry.target = self
                entry.isEnabled = localForecast != nil
                submenu.addItem(entry)
            }
        }
        let usage = NSMenuItem(title: t("在浏览器打开 Claude 用量页", "Open Claude usage in browser"), action: #selector(openUsage), keyEquivalent: "")
        usage.target = self
        submenu.addItem(usage)
        submenu.addItem(.separator())
        var notes = localOnly ? [t("只读本机文件，随菜单和现有刷新更新", "Reads local files on menu open and scheduled refresh"),
                                 t("Fable 随 Claude Desktop 用量缓存自动更新", "Fable updates from Claude Desktop’s local usage cache")] :
                    [t("复用本机 Claude Code 登录；仅读取账户用量", "Uses local Claude Code login; account usage only"),
                     t("随现有刷新检查，自动间隔至少 5 分钟", "Shares refreshes; automatic interval at least 5 minutes"),
                     t("额度检查不调用模型；任务由新任务入口发起", "Quota checks do not run models; use New task for work")]
        if enabled, let next = defaults.object(forKey: Self.nextCheckKey) as? Date, next > now {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d HH:mm"
            notes.append(t("下次可检查：", "Next eligible: ") + formatter.string(from: next))
        }
        if let claude {
            for (key, window) in claude.modelWindows.sorted(by: { $0.key < $1.key }) {
                let name = ClaudeForecast.displayName(key)
                notes.append("\(name) · " + (window.notStarted ? t("本周未使用", "unused this week")
                                                   : t("周剩余 \(window.remaining)%", "weekly left \(window.remaining)%")))
            }
            for row in claude.weekBreakdown where row.percentOfLimit > 0 {
                notes.append("\(row.name) · " + t("占本周额度 \(Int(row.percentOfLimit.rounded()))%",
                                                  "\(Int(row.percentOfLimit.rounded()))% of weekly limit"))
            }
            for key in claude.unreadableModelWindows {
                notes.append(key.replacingOccurrences(of: "seven_day_", with: "") + " · " + t("格式未知，暂停建议", "unknown format; advice paused"))
            }
        }
        if localOnly {
            let labels = QuotaBalanceView.localResetLabels(localResetSample, at: now, chinese: chinese)
            notes += labels.details
        } else if let desktopResets {
            notes.append(QuotaBalanceView.desktopSyncLabel(desktopResets.syncedAt, chinese: chinese))
            for grant in desktopResets.reading.grants where grant.isAvailable(at: now) {
                notes.append(QuotaBalanceView.describe(grant, chinese: chinese))
            }
        } else {
            if desktopSyncEnabled {
                let hint = desktopAccess()
                    ? t("桌面重置同步 · 请打开 Claude Desktop 的用量页", "Desktop reset sync · open Usage in Claude Desktop")
                    : t("桌面重置同步 · 等待 macOS 辅助功能权限", "Desktop reset sync · waiting for macOS Accessibility access")
                notes.append(hint)
            }
            if let status = claude?.claudeResets {
                for grant in status.grants where grant.isAvailable(at: now) {
                    notes.append(QuotaBalanceView.describe(grant, chinese: chinese))
                }
                if claude?.resets == nil {
                    notes.append(t("重置次数不可用：", "Resets unavailable: ") + (status.ineligibleReason ?? "unknown"))
                }
            } else if let claude {
                notes.append(claude.unreadableShapes[ClaudeQuotaClient.resetBlockKey] == nil
                    ? t("账户未返回重置次数", "No reset count returned")
                    : t("重置次数格式未知", "Reset count format unknown"))
            }
        }
        for note in notes {
            let row = NSMenuItem(title: note, action: nil, keyEquivalent: "")
            row.isEnabled = false
            submenu.addItem(row)
        }
        settingsItem.title = localOnly ? t("Claude Code：本机预测", "Claude Code: Local forecast")
            : (active ? t("Claude Code：已启用", "Claude Code: On") : t("Claude Code：未启用", "Claude Code: Off"))
        settingsItem.submenu = submenu
        writeDiagnostics(status: status, now: now)
        onChange?()
        if fallbackStarted { onDesktopQuotaSync?() }
    }

    private func writeDiagnostics(status: String, now: Date) {
        guard active, let diagnosticURL else { return }
        let fields = (item.view?.subviews.compactMap { ($0 as? NSTextField)?.stringValue }) ?? []
        var summary: [String: Any] = [
            "updated_at": ISO8601DateFormatter().string(from: now), "enabled": enabled,
            "claude_local_forecast_only": localOnly,
            "claude_desktop_accessibility": desktopSyncEnabled && desktopAccess(),
            "claude_requests_started_this_process": requestsStarted, "status": status, "menu_text": fields
        ]
        if localOnly, let forecast = localForecast, let reading = forecast.fable, reading.isInCycle(at: now) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            summary["claude_local_fable"] = ["source": forecast.fableSource.rawValue, "used_percent": reading.used,
                                            "sampled_at": iso.string(from: reading.time), "resets_at": iso.string(from: reading.reset)] as [String: Any]
        }
        if let sample = localResetSample {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var details: [String: Any] = ["sampled_at": iso.string(from: sample.time), "stale": sample.isStale(at: now)]
            if let stock = sample.value?.stock(at: now) {
                details["available"] = stock.count
                details["nearest_expiry"] = stock.nearestExpiry(at: now).map(iso.string(from:))
            }
            summary["claude_local_resets"] = details
        }
        // Outcome codes only (e.g. credential_expired, http_401, ok); never tokens or response bodies.
        if let outcome = defaults.string(forKey: Self.lastOutcomeKey) { summary["claude_last_outcome"] = outcome }
        if let claude { summary["claude_response_keys"] = claude.responseKeys }
        if let shape = defaults.string(forKey: Self.lastShapeKey) { summary["claude_last_response_shape"] = shape }
        if let claude {
            // Window names and percentages only, to explain model-limit advice.
            summary["claude_model_windows"] = claude.modelWindows.sorted { $0.key < $1.key }.map { key, window in
                "\(key): used \(Int(window.used.rounded()))%, reset " + (window.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none")
            } + claude.unreadableModelWindows.map { "\($0): unreadable " + (claude.unreadableShapes[$0] ?? "") }
            summary["claude_week_breakdown"] = claude.weekBreakdown.map {
                "\($0.key) (\($0.name)): percent \($0.percent), percent_of_limit \($0.percentOfLimit)"
            } + claude.unreadableShapes.filter {
                !claude.unreadableModelWindows.contains($0.key) && $0.key != ClaudeQuotaClient.resetBlockKey
            }.map { "\($0.key): unreadable \($0.value)" }
            // Counts, kinds and dates only; grant ids are never read into memory.
            if let status = claude.claudeResets {
                summary["claude_resets"] = [
                    "eligible": status.eligible, "ineligible_reason": status.ineligibleReason ?? "",
                    "available": claude.resets.map { $0.count as Any } ?? "none",
                    "grants": status.grants.map {
                        "\($0.type ?? "untyped"): left \($0.resetsLeft)/\($0.resetsTotal), paused \($0.paused), ends "
                            + ($0.endsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none")
                    }] as [String: Any]
            } else {
                summary["claude_resets"] = claude.unreadableShapes[ClaudeQuotaClient.resetBlockKey].map { "unreadable \($0)" } ?? "absent"
            }
        }
        if let at = defaults.object(forKey: Self.lastOutcomeAtKey) as? Date {
            summary["claude_last_outcome_at"] = ISO8601DateFormatter().string(from: at)
        }
        if let desktopResets {
            summary["claude_desktop_resets"] = [
                "synced_at": ISO8601DateFormatter().string(from: desktopResets.syncedAt),
                "available": desktopResets.reading.stock(at: now).count,
                "grants": desktopResets.reading.grants.map { QuotaBalanceView.describe($0, chinese: false) }
            ] as [String: Any]
        }
        if desktopQuotaFallbackActive, let desktopQuota {
            summary["claude_desktop_quota_updated_at"] = ISO8601DateFormatter().string(from: desktopQuota.updatedAt)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) else { return }
        do {
            try FileManager.default.createDirectory(at: diagnosticURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: diagnosticURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: diagnosticURL.path)
        } catch { /* Diagnostics must never interfere with quota reads. */ }
    }
}
