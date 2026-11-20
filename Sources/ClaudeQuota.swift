import Foundation
import Security
import CryptoKit
import LocalAuthentication

struct ProviderQuotaWindow {
    let used: Double
    let resetsAt: Date?

    var remaining: Int { max(0, min(100, Int((100 - used).rounded(.down)))) }
    func isCurrent(at now: Date) -> Bool { resetsAt.map { $0 > now } ?? false }
    /// A model window with no usage and no reset time has not started; it cannot be tight.
    var notStarted: Bool { used <= 0 && resetsAt == nil }
    func needsAttention(at now: Date) -> Bool { !notStarted && (!isCurrent(at: now) || remaining <= 10) }
}

/// One row of `seven_day_breakdown`: how the weekly Claude quota was spent (not a separate limit).
struct ClaudeBreakdownRow: Equatable {
    let key: String
    let name: String
    let percent: Double
    let percentOfLimit: Double
}

/// Manually redeemable limit resets one provider currently holds. `expirations` carries one future
/// expiry per reset when known, so it can be shorter than `count`.
struct ProviderResetStock: Equatable {
    static let soonInterval: TimeInterval = 72 * 3600
    let count: Int
    var expirations: [Date] = []

    func nearestExpiry(at now: Date) -> Date? { expirations.filter { $0 > now }.min() }
    func expiringSoon(at now: Date) -> Bool {
        nearestExpiry(at: now).map { $0.timeIntervalSince(now) <= Self.soonInterval } ?? false
    }
}

/// One Claude Code reset grant. `type` is "session" (5-hour), "weekly" or "full" when the server says.
struct ClaudeResetGrant: Codable, Equatable {
    let label: String
    let type: String?
    let resetsLeft: Int
    let resetsTotal: Int
    let endsAt: Date?
    let paused: Bool

    func isAvailable(at now: Date) -> Bool { resetsLeft > 0 && !paused && (endsAt.map { $0 > now } ?? true) }
}

/// The reset block Claude Code reads next to account usage. An undocumented local-client protocol:
/// every field is optional, and anything unreadable yields no count instead of a guess.
struct ClaudeResetStatus: Equatable {
    let eligible: Bool
    let ineligibleReason: String?
    let grants: [ClaudeResetGrant]

    static func parse(_ raw: Any) -> ClaudeResetStatus? {
        func integer(_ value: Any?) -> Int? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 10_000,
                  number.doubleValue == number.doubleValue.rounded() else { return nil }
            return number.intValue
        }
        func flag(_ value: Any?) -> Bool? {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
            return number.boolValue
        }
        guard let object = raw as? [String: Any], let eligible = flag(object["eligible"]) else { return nil }
        let grants: [ClaudeResetGrant] = ((object["grants"] as? [Any]) ?? []).compactMap { item in
            // A grant without a readable remaining count is skipped, never counted as zero or one.
            guard let grant = item as? [String: Any], let left = integer(grant["resets_left"]) else { return nil }
            let type = (grant["type"] as? String).flatMap { ["session", "weekly", "full"].contains($0) ? $0 : nil }
            return ClaudeResetGrant(
                label: String(((grant["label"] as? String) ?? "").prefix(60)), type: type, resetsLeft: left,
                resetsTotal: max(left, integer(grant["resets_total"]) ?? left),
                endsAt: (grant["ends_at"] as? String).flatMap(ProviderQuotaSnapshot.date),
                paused: flag(grant["paused"]) ?? false)
        }
        let reason = (object["ineligible_reason"] as? String).map { String($0.prefix(40)) }
        return ClaudeResetStatus(eligible: eligible, ineligibleReason: reason, grants: grants)
    }

    /// nil when the account is outside the program for a reason other than simply holding no grant.
    func stock(at now: Date) -> ProviderResetStock? {
        guard eligible || ineligibleReason == "no_grant" else { return nil }
        let available = grants.filter { $0.isAvailable(at: now) }
        let expirations = available.flatMap { grant in
            grant.endsAt.map { Array(repeating: $0, count: min(grant.resetsLeft, 20)) } ?? []
        }
        return ProviderResetStock(count: available.reduce(0) { $0 + $1.resetsLeft }, expirations: expirations.sorted())
    }
}

struct ProviderQuotaSnapshot {
    let checkedAt: Date
    let fiveHour: ProviderQuotaWindow?
    let week: ProviderQuotaWindow?
    /// Resets this provider holds; nil when the provider did not report a readable count.
    var resets: ProviderResetStock?
    /// Claude Code only: grant details behind `resets`, for the menu and local diagnostics.
    var claudeResets: ClaudeResetStatus?
    var modelWindows: [String: ProviderQuotaWindow] = [:]
    /// Model windows present in the response but in an unknown shape; a limit may exist that we cannot read.
    var unreadableModelWindows: [String] = []
    /// Field names and JSON types of unreadable windows (no values), for local diagnostics only.
    var unreadableShapes: [String: String] = [:]
    var weekBreakdown: [ClaudeBreakdownRow] = []
    /// Top-level field names of the last response (no values), for local diagnostics only.
    var responseKeys: [String] = []
    var hasModelLimitConcern: Bool { !unreadableModelWindows.isEmpty }

    func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(checkedAt)
        return age >= 0 && age <= 15 * 60
    }

    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

enum ClaudeQuotaError: Error, Equatable {
    case loginRequired, loginExpired, accessDenied, keychainLocked, network, invalidResponse, unsupported
    case rateLimited(TimeInterval)

    func message(chinese: Bool) -> String {
        switch self {
        case .loginRequired: return chinese ? "请先登录或更新 Claude Code 登录" : "Sign in again to Claude Code"
        case .loginExpired: return chinese ? "Claude Code 登录已过期 · 请在终端更新登录" : "Claude Code login expired · renew it in the terminal"
        case .accessDenied: return chinese ? "登录凭据无权读取账户用量" : "Login cannot read account usage"
        case .keychainLocked: return chinese ? "Claude Code 登录凭据暂不可读" : "Claude Code credentials are unavailable"
        case .network: return chinese ? "连接失败，稍后重试" : "Connection failed; retrying later"
        case .invalidResponse: return chinese ? "额度格式已变或数据无效" : "Quota format changed or invalid data"
        case .unsupported: return chinese ? "账户未返回订阅额度" : "No subscription quota returned"
        case .rateLimited: return chinese ? "查询受限，已暂停重试" : "Rate limited; retries paused"
        }
    }

    /// Non-secret outcome code for the local diagnostic file.
    var outcome: String {
        switch self {
        case .loginRequired: return "credential_missing"
        case .loginExpired: return "credential_expired"
        case .accessDenied: return "http_403"
        case .keychainLocked: return "keychain_unavailable"
        case .network: return "network"
        case .invalidResponse: return "invalid_response"
        case .unsupported: return "unsupported"
        case .rateLimited: return "http_429"
        }
    }

    var clearsAccountData: Bool { [.loginRequired, .loginExpired, .accessDenied].contains(self) }
}

struct ClaudeQuotaCredential {
    let accessToken: String
    // In-memory identity only. Never persist tokens or fingerprints to preferences or logs.
    var identity: String { SHA256.hash(data: Data(accessToken.utf8)).map { String(format: "%02x", $0) }.joined() }

    static func decode(_ data: Data, now: Date = Date()) throws -> ClaudeQuotaCredential {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty,
              !token.contains("\n"), !token.contains("\r") else { throw ClaudeQuotaError.loginRequired }
        if let expiry = oauth["expiresAt"] as? Double, expiry / 1000 <= now.timeIntervalSince1970 + 30 {
            throw ClaudeQuotaError.loginExpired
        }
        return ClaudeQuotaCredential(accessToken: token)
    }

    static func load() throws -> ClaudeQuotaCredential {
        // Match the standard Claude Code login. Do not inspect browser cookies or Desktop secrets.
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return try decode(data) }
        if status != errSecItemNotFound { throw ClaudeQuotaError.keychainLocked }
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 64 * 1024,
              let data = try? Data(contentsOf: file) else { throw ClaudeQuotaError.loginRequired }
        return try decode(data)
    }
}

/// Optional account metadata read. No inference, token refresh, CLI subprocess, or conversation upload.
final class ClaudeQuotaClient: NSObject, URLSessionTaskDelegate {
    /// The same read Claude Code uses for its saved limit resets: account windows plus the reset block,
    /// without spend details. Undocumented, so the reset block is parsed leniently and may be absent.
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage?cedar_ember=1&skip_spend=1")!
    static let resetBlockKey = "cedar_ember"
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
        super.init()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward account credentials through redirects.
    }

    @discardableResult
    func fetch(credential: ClaudeQuotaCredential,
               invalidShape: ((String) -> Void)? = nil,
               completion: @escaping (Result<ProviderQuotaSnapshot, ClaudeQuotaError>) -> Void) -> URLSessionDataTask {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer " + credential.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request) { data, response, error in
            defer { session.finishTasksAndInvalidate() }
            guard error == nil, let response = response as? HTTPURLResponse else {
                completion(.failure(.network)); return
            }
            switch response.statusCode {
            case 200:
                guard let data, data.count <= 256 * 1024 else { completion(.failure(.invalidResponse)); return }
                do { completion(.success(try Self.decode(data, now: Date()))) }
                catch {
                    let failure = error as? ClaudeQuotaError ?? .invalidResponse
                    if failure == .invalidResponse || failure == .unsupported { invalidShape?(Self.shape(data)) }
                    completion(.failure(failure))
                }
            case 401: completion(.failure(.loginRequired))
            case 403: completion(.failure(.accessDenied))
            case 429:
                let retry = Self.retryDelay(response.value(forHTTPHeaderField: "Retry-After"), now: Date())
                completion(.failure(.rateLimited(retry)))
            default: completion(.failure(.network))
            }
        }
        task.resume()
        return task
    }

    static func retryDelay(_ value: String?, now: Date) -> TimeInterval {
        var seconds = value.flatMap(Double.init)
        if seconds == nil, let value {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            seconds = formatter.date(from: value)?.timeIntervalSince(now)
        }
        return max(3600, min(24 * 3600, seconds.flatMap { $0.isFinite ? $0 : nil } ?? 3600))
    }

    /// Field names and JSON types only, never values: enough to diagnose a format change locally.
    static func shape(_ data: Data) -> String {
        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return "not-json" }
        guard let root = parsed as? [String: Any] else { return shape(of: parsed, depth: 0) }
        return String(root.keys.sorted().map { "\($0):" + shape(of: root[$0]!, depth: 1) }.joined(separator: "; ").prefix(2000))
    }

    /// Recursive, value-free description; arrays show their first element's shape.
    static func shape(of value: Any, depth: Int) -> String {
        if let object = value as? [String: Any] {
            guard depth < 4 else { return "object" }
            return "{" + object.keys.sorted().map { "\($0):" + shape(of: object[$0]!, depth: depth + 1) }.joined(separator: ",") + "}"
        }
        if let array = value as? [Any] {
            guard depth < 4, let first = array.first else { return "array" }
            return "array<" + shape(of: first, depth: depth + 1) + ">"
        }
        return scalarType(value)
    }

    private static func scalarType(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let number = value as? NSNumber { return CFGetTypeID(number) == CFBooleanGetTypeID() ? "bool" : "number" }
        if value is String { return "string" }
        return "other"
    }

    static func scopedModelKey(_ row: [String: Any]) -> String? {
        guard row["kind"] as? String == "weekly_scoped", let scope = row["scope"] as? [String: Any],
              let model = scope["model"] as? [String: Any], let name = model["display_name"] as? String else { return nil }
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
            .split(separator: "_").joined(separator: "_").prefix(40)
        return slug.isEmpty ? nil : "seven_day_" + slug
    }

    static func scopedWindow(_ row: [String: Any]) -> ProviderQuotaWindow? {
        let reset = row["resets_at"]
        let date = (reset as? String).flatMap(ProviderQuotaSnapshot.date)
        guard let number = row["percent"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, (0...1000).contains(number.doubleValue),
              reset == nil || reset is NSNull || date != nil else { return nil }
        return ProviderQuotaWindow(used: number.doubleValue, resetsAt: date)
    }

    static func decode(_ data: Data, now: Date) throws -> ProviderQuotaSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeQuotaError.invalidResponse
        }
        func window(_ key: String) throws -> ProviderQuotaWindow? {
            guard let raw = root[key], !(raw is NSNull) else { return nil }
            guard let object = raw as? [String: Any] else { throw ClaudeQuotaError.invalidResponse }
            // A window object with null utilization carries no reading (e.g. a model limit not in effect).
            if object["utilization"] is NSNull { return nil }
            // Utilization can exceed 100 when a limit is overrun; remaining clamps to 0.
            guard let number = object["utilization"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, (0...1000).contains(number.doubleValue) else {
                throw ClaudeQuotaError.invalidResponse
            }
            var reset: Date?
            if let value = object["resets_at"], !(value is NSNull) {
                guard let text = value as? String, let date = ProviderQuotaSnapshot.date(text) else {
                    throw ClaudeQuotaError.invalidResponse
                }
                reset = date
            }
            return ProviderQuotaWindow(used: number.doubleValue, resetsAt: reset)
        }
        let five = try window("five_hour")
        let week = try window("seven_day")
        guard five != nil || week != nil else { throw ClaudeQuotaError.unsupported }
        var models: [String: ProviderQuotaWindow] = [:]
        var unreadable: [String] = []
        var shapes: [String: String] = [:]
        var breakdown: [ClaudeBreakdownRow] = []
        if let raw = root["seven_day_breakdown"], !(raw is NSNull) {
            if let rows = (raw as? [String: Any])?["rows"] as? [[String: Any]] {
                breakdown = rows.compactMap { row in
                    func number(_ key: String) -> Double? {
                        guard let n = row[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                              n.doubleValue.isFinite, n.doubleValue >= 0 else { return nil }
                        return n.doubleValue
                    }
                    guard let key = row["key"] as? String, let percent = number("percent"),
                          let ofLimit = number("percent_of_limit") else { return nil }
                    return ClaudeBreakdownRow(key: key, name: (row["display_name"] as? String) ?? key,
                                              percent: percent, percentOfLimit: ofLimit)
                }
            } else {
                shapes["seven_day_breakdown"] = String(shape(of: raw, depth: 1).prefix(1500))
            }
        }
        for key in root.keys.sorted() where key.hasPrefix("seven_day_") && key != "seven_day_breakdown" {
            // An unknown model-window shape must not hide the account windows, but it pauses advice.
            do { if let parsed = try window(key) { models[key] = parsed } }
            catch { unreadable.append(key) }
        }
        for key in unreadable { shapes[key] = String(shape(of: root[key]!, depth: 1).prefix(1500)) }
        // Newer responses list every meter in `limits[]`; a model-scoped weekly row (e.g. Fable) is a
        // limit of its own and joins the model windows under a `seven_day_<model>` key.
        if let raw = root["limits"], !(raw is NSNull) {
            if let rows = raw as? [Any] {
                for case let row as [String: Any] in rows.prefix(64) {
                    guard let key = scopedModelKey(row) else { continue }
                    if let window = scopedWindow(row) {
                        models[key] = window
                        unreadable.removeAll { $0 == key }
                        shapes[key] = nil
                    } else if models[key] == nil, !unreadable.contains(key) {
                        unreadable.append(key)
                        shapes[key] = String(shape(of: row, depth: 1).prefix(1500))
                    }
                }
            } else {
                unreadable.append("limits")
                shapes["limits"] = String(shape(of: raw, depth: 1).prefix(1500))
            }
        }
        // The reset block never invalidates the account windows: unreadable means "no count".
        var resetStatus: ClaudeResetStatus?
        if let raw = root[resetBlockKey], !(raw is NSNull) {
            resetStatus = ClaudeResetStatus.parse(raw)
            if resetStatus == nil { shapes[resetBlockKey] = String(shape(of: raw, depth: 1).prefix(1500)) }
        }
        return ProviderQuotaSnapshot(checkedAt: now, fiveHour: five, week: week,
                                     resets: resetStatus?.stock(at: now), claudeResets: resetStatus,
                                     modelWindows: models,
                                     unreadableModelWindows: unreadable, unreadableShapes: shapes,
                                     weekBreakdown: breakdown, responseKeys: root.keys.sorted())
    }
}

enum QuotaProvider: String, Codable {
    case codex, claude
    var title: String { self == .codex ? "Codex" : "Claude Code" }
}

struct QuotaBalanceAdvice {
    let title: String
    let detail: String
    var preferred: QuotaProvider? = nil
    var canDispatch = false

    static func make(codex: ProviderQuotaSnapshot?, claude: ProviderQuotaSnapshot?,
                     codexReliable: Bool, claudeReliable: Bool, now: Date, chinese: Bool) -> QuotaBalanceAdvice {
        func result(_ zh: String, _ en: String, _ zhDetail: String, _ enDetail: String,
                    preferred: QuotaProvider? = nil) -> QuotaBalanceAdvice {
            QuotaBalanceAdvice(title: chinese ? zh : en, detail: chinese ? zhDetail : enDetail,
                               preferred: preferred, canDispatch: preferred != nil)
        }
        guard codexReliable, claudeReliable, let codex, let claude,
              codex.isFresh(at: now), claude.isFresh(at: now),
              let cw = codex.week, let aw = claude.week, cw.isCurrent(at: now), aw.isCurrent(at: now),
              [codex.fiveHour, claude.fiveHour].compactMap({ $0 }).allSatisfy({ $0.isCurrent(at: now) }) else {
            return result("等待两边最新额度", "Waiting for fresh quotas", "旧数据、缺失窗口或已到重置时间时暂停均衡建议。", "Advice pauses for stale data, missing weekly windows, or elapsed resets.")
        }
        if claude.hasModelLimitConcern || claude.modelWindows.values.contains(where: { $0.needsAttention(at: now) }) {
            return result("先核对 Claude 模型额度", "Check Claude model limits", "模型专属窗口已紧张或待更新，账户总余量不能保证该模型可用。", "A model-specific window is tight or needs updating; total quota does not guarantee model availability.")
        }
        let cMinimum = min(cw.remaining, codex.fiveHour?.remaining ?? 100)
        let aMinimum = min(aw.remaining, claude.fiveHour?.remaining ?? 100)
        if cMinimum <= 10 && aMinimum <= 10 {
            return result("两边都需节制", "Conserve both quotas", "至少各有一个窗口余量不超过 10%，宜缩小任务或等待重置。", "Each provider has a window at or below 10%; reduce work or wait for reset.")
        }
        if cMinimum <= 10 && aMinimum > 20 {
            return result("下一项优先 Claude", "Prefer Claude next", "Codex 有窗口余量不超过 10%；Claude 已返回窗口均高于 20%。", "A Codex window is at or below 10%; reported Claude windows exceed 20%.", preferred: .claude)
        }
        if aMinimum <= 10 && cMinimum > 20 {
            return result("下一项优先 Codex", "Prefer Codex next", "Claude 有窗口余量不超过 10%；Codex 已返回窗口均高于 20%。", "A Claude window is at or below 10%; reported Codex windows exceed 20%.", preferred: .codex)
        }
        let cDays = cw.resetsAt!.timeIntervalSince(now) / 86400
        let aDays = aw.resetsAt!.timeIntervalSince(now) / 86400
        guard cDays <= 7.01, aDays <= 7.01 else {
            return result("等待窗口更新", "Waiting for window update", "重置时间不在预期的每周窗口内。", "Reset time falls outside the expected weekly window.")
        }
        let cBuffer = 100 - cw.used - 100 * cDays / 7
        let aBuffer = 100 - aw.used - 100 * aDays / 7
        let explanation = chinese
            ? String(format: "周预算余裕：Codex %+.1f、Claude %+.1f 个百分点。余裕 = 剩余百分比 − 距重置天数 × 100/7；差距达到 10 点才建议倾斜。仅供下一项任务选择，不代表任务能力或等量算力。", cBuffer, aBuffer)
            : String(format: "Weekly headroom: Codex %+.1f, Claude %+.1f points. Headroom = remaining %% − days to reset × 100/7; a 10-point gap favors one provider. A pacing hint, not equivalent capacity or task suitability.", cBuffer, aBuffer)
        if cBuffer - aBuffer >= 10 && cMinimum > 20 {
            return QuotaBalanceAdvice(title: chinese ? "下一项优先 Codex" : "Prefer Codex next", detail: explanation, preferred: .codex, canDispatch: true)
        }
        if aBuffer - cBuffer >= 10 && aMinimum > 20 {
            return QuotaBalanceAdvice(title: chinese ? "下一项优先 Claude" : "Prefer Claude next", detail: explanation, preferred: .claude, canDispatch: true)
        }
        return QuotaBalanceAdvice(title: chinese ? "按任务选择，保持均衡" : "Choose by task; stay balanced", detail: explanation, canDispatch: true)
    }
}
