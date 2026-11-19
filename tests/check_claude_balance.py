#!/usr/bin/env python3
"""Offline account-boundary, pacing, refresh, and native-panel checks. No real credentials or HTTP."""

import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
harness = r'''
import AppKit
import Foundation

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let now = Date()
let fiveReset = now.addingTimeInterval(4 * 3600)
let weekReset = now.addingTimeInterval(5 * 86400)
let formatter = ISO8601DateFormatter()
let body = Data("""
{"five_hour":{"utilization":1,"resets_at":"\(formatter.string(from: fiveReset))"},
 "seven_day":{"utilization":20,"resets_at":"\(formatter.string(from: weekReset))"}}
""".utf8)
let snapshot = try ClaudeQuotaClient.decode(body, now: now)
precondition(snapshot.fiveHour?.remaining == 99, "1 means 1%, not 100%")
precondition(snapshot.week?.remaining == 80)
let weeklyOnly = try ClaudeQuotaClient.decode(Data("""
{"five_hour":null,"seven_day":{"utilization":0,"resets_at":null}}
""".utf8), now: now)
precondition(weeklyOnly.fiveHour == nil && weeklyOnly.week?.remaining == 100)
precondition(weeklyOnly.week?.isCurrent(at: now) == false)
for bad in ["{}", "[]", "{\"seven_day\":{\"utilization\":true}}",
            "{\"five_hour\":{\"utilization\":1001}}", "{\"five_hour\":{\"utilization\":-1}}",
            "{\"five_hour\":{\"utilization\":20,\"resets_at\":\"nonsense\"}}"] {
    do { _ = try ClaudeQuotaClient.decode(Data(bad.utf8), now: now); fatalError("accepted invalid data") }
    catch { precondition(error is ClaudeQuotaError) }
}
// Real responses carry extra fields, microsecond timestamps, and model windows with no reading.
let realistic = try ClaudeQuotaClient.decode(Data("""
{"five_hour":{"utilization":6.0,"resets_at":"\(formatter.string(from: fiveReset).dropLast())Z"},
 "seven_day":{"utilization":35.0,"resets_at":"2099-01-01T03:59:59.943679+00:00"},
 "seven_day_oauth_apps":null,"seven_day_opus":{"utilization":0.0,"resets_at":null},
 "seven_day_sonnet":{"utilization":null,"resets_at":null},
 "extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null}}
""".utf8), now: now)
precondition(realistic.fiveHour?.remaining == 94 && realistic.week?.remaining == 65)
precondition(realistic.week?.resetsAt != nil, "microsecond timestamps parse")
precondition(Set(realistic.modelWindows.keys) == ["seven_day_opus"], "null utilization means no reading")
precondition(realistic.unreadableModelWindows.isEmpty)
let overrun = try ClaudeQuotaClient.decode(Data("{\"seven_day\":{\"utilization\":104.5,\"resets_at\":null}}".utf8), now: now)
precondition(overrun.week?.remaining == 0, "overrun usage clamps to 0% remaining")
let oddModel = try ClaudeQuotaClient.decode(Data("""
{"seven_day":{"utilization":10,"resets_at":"\(formatter.string(from: weekReset))"},"seven_day_new":{"percent":3}}
""".utf8), now: now)
precondition(oddModel.week?.remaining == 90 && oddModel.unreadableModelWindows == ["seven_day_new"])
precondition(oddModel.unreadableShapes["seven_day_new"] == "{percent:number}", "unreadable windows keep a value-free shape")
let withBreakdown = try ClaudeQuotaClient.decode(Data("""
{"seven_day":{"utilization":13,"resets_at":"\(formatter.string(from: weekReset))"},
 "seven_day_breakdown":{"as_of":"x","window_started_at":"y","rows":[
   {"display_name":"Fable","key":"fable","percent":60,"percent_of_limit":7.8},
   {"display_name":"Other","key":"other","percent":40,"percent_of_limit":5.2}]}}
""".utf8), now: now)
precondition(withBreakdown.unreadableModelWindows.isEmpty && withBreakdown.modelWindows.isEmpty,
             "the weekly breakdown is not a model limit")
precondition(withBreakdown.weekBreakdown.map(\.key) == ["fable", "other"])
precondition(withBreakdown.weekBreakdown[0].percentOfLimit == 7.8)
// Model-scoped weekly meters arrive as rows of `limits[]` (e.g. Fable), not as `seven_day_*` objects.
let withLimits = try ClaudeQuotaClient.decode(Data("""
{"five_hour":{"utilization":8,"resets_at":"\(formatter.string(from: fiveReset))"},
 "seven_day":{"utilization":16,"resets_at":"\(formatter.string(from: weekReset))"},
 "limits":[
   {"kind":"session","group":"session","percent":8,"resets_at":"\(formatter.string(from: fiveReset))","scope":null,"severity":"normal","is_active":true},
   {"kind":"weekly_all","group":"weekly","percent":16,"resets_at":"\(formatter.string(from: weekReset))","scope":null,"severity":"normal","is_active":false},
   {"kind":"weekly_scoped","group":"weekly","percent":30,"resets_at":"\(formatter.string(from: weekReset))","scope":{"model":{"display_name":"Fable"}},"severity":"normal","is_active":false},
   {"kind":"weekly_scoped","group":"weekly","percent":5,"resets_at":null,"scope":{"model":{"display_name":"Opus 5.5"}}},
   {"kind":"weekly_scoped","group":"weekly","percent":40,"resets_at":null,"scope":{"surface":{"display_name":"Cowork"}}},
   {"kind":"weekly_scoped","group":"weekly","percent":"lots","scope":{"model":{"display_name":"Odd"}}},
   "junk"]}
""".utf8), now: now)
precondition(withLimits.week?.remaining == 84 && withLimits.fiveHour?.remaining == 92)
precondition(withLimits.modelWindows["seven_day_fable"]?.remaining == 70, "a model-scoped weekly row is a model window")
precondition(withLimits.modelWindows["seven_day_fable"]?.isCurrent(at: now) == true)
precondition(withLimits.modelWindows["seven_day_opus_5_5"]?.remaining == 95, "display names become stable keys")
precondition(Set(withLimits.modelWindows.keys) == ["seven_day_fable", "seven_day_opus_5_5"], "session, account and surface rows are not model limits")
precondition(withLimits.unreadableModelWindows == ["seven_day_odd"], "an unreadable model row pauses advice")
precondition(withLimits.unreadableShapes["seven_day_odd"]?.contains("percent:string") == true)
precondition(withLimits.responseKeys == ["five_hour", "limits", "seven_day"], "diagnostics keep field names only")
precondition(ClaudeForecast.displayName("seven_day_opus_5_5") == "Opus 5 5")
let limitsWins = try ClaudeQuotaClient.decode(Data("""
{"seven_day":{"utilization":16,"resets_at":null},"seven_day_fable":{"percent":3},
 "limits":[{"kind":"weekly_scoped","percent":30,"resets_at":null,"scope":{"model":{"display_name":"Fable"}}}]}
""".utf8), now: now)
precondition(limitsWins.modelWindows["seven_day_fable"]?.remaining == 70 && limitsWins.unreadableModelWindows.isEmpty,
             "a readable limits row replaces an unreadable legacy window of the same model")
let oddLimits = try ClaudeQuotaClient.decode(Data("{\"seven_day\":{\"utilization\":16,\"resets_at\":null},\"limits\":{\"rows\":1}}".utf8), now: now)
precondition(oddLimits.week?.remaining == 84 && oddLimits.unreadableModelWindows == ["limits"], "an unknown limits shape may hide a model limit")
let fablePanel = QuotaBalanceView(codex: nil, claude: withLimits, codexReliable: false, claudeReliable: true,
                                  claudeStatus: "", now: now, chinese: false)
let fableFields = fablePanel.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
precondition(fableFields.contains("84% · Fable 70%"), "\(fableFields)")
var tightFable = snapshot
tightFable.modelWindows["seven_day_fable"] = ProviderQuotaWindow(used: 95, resetsAt: weekReset)
precondition(QuotaBalanceAdvice.make(codex: snapshot, claude: tightFable, codexReliable: true, claudeReliable: true,
                                     now: now, chinese: false).title == "Check Claude model limits")
// Claude Code reset grants ride on the same read; they never invalidate the account windows.
precondition(ClaudeQuotaClient.endpoint.query == "cedar_ember=1&skip_spend=1", "same read Claude Code uses for resets")
precondition(snapshot.resets == nil && snapshot.claudeResets == nil, "no reset block means no count, not zero")
let soon = now.addingTimeInterval(2 * 86400)
let later = now.addingTimeInterval(20 * 86400)
let withResets = try ClaudeQuotaClient.decode(Data("""
{"seven_day":{"utilization":14,"resets_at":"\(formatter.string(from: weekReset))"},
 "cedar_ember":{"eligible":true,"at_limit":false,"next_grant_id":"g1","weekly_resets_at":null,"grants":[
   {"id":"g1","label":"Thanks","resets_total":3,"resets_left":2,"ends_at":"\(formatter.string(from: soon))","type":"session","paused":false,"usable_now":false},
   {"id":"g2","resets_total":1,"resets_left":1,"ends_at":"\(formatter.string(from: later))","type":"full"},
   {"id":"g3","resets_left":4,"ends_at":"\(formatter.string(from: now.addingTimeInterval(-86400)))","type":"weekly"},
   {"id":"g4","resets_left":5,"paused":true},
   {"id":"g5","resets_left":"7"},
   {"id":"g6","resets_left":true},
   {"id":"g7","resets_left":0,"type":"mystery"}]}}
""".utf8), now: now)
precondition(withResets.week?.remaining == 86)
precondition(withResets.resets?.count == 3, "expired, paused and unreadable grants are not counted")
precondition(withResets.resets?.expirations.count == 3 && withResets.resets?.nearestExpiry(at: now) != nil)
precondition(withResets.resets?.expiringSoon(at: now) == true, "a reset ending within 3 days is expiring soon")
precondition(ProviderResetStock(count: 1, expirations: [later]).expiringSoon(at: now) == false)
precondition(withResets.claudeResets?.grants.count == 5, "grants without a readable count are skipped")
precondition(withResets.claudeResets?.grants.last?.type == nil, "unknown grant kinds stay untyped")
precondition(QuotaBalanceView.describe(withResets.claudeResets!.grants[0], chinese: false).hasPrefix("5-hour reset ×2 · expires "))
precondition(QuotaBalanceView.describe(withResets.claudeResets!.grants[1], chinese: true).hasPrefix("完整重置 ×1 · 到期 "))
func resetBlock(_ block: String) throws -> ProviderQuotaSnapshot {
    try ClaudeQuotaClient.decode(Data("{\"seven_day\":{\"utilization\":10,\"resets_at\":null},\"cedar_ember\":\(block)}".utf8), now: now)
}
let outside = try resetBlock("{\"eligible\":false,\"ineligible_reason\":\"tier\"}")
precondition(outside.resets == nil && outside.claudeResets?.ineligibleReason == "tier", "outside the program is not zero resets")
let holdsNone = try resetBlock("{\"eligible\":false,\"ineligible_reason\":\"no_grant\"}")
precondition(holdsNone.resets?.count == 0, "holding no grant is zero resets")
let emptyGrants = try resetBlock("{\"eligible\":true}")
precondition(emptyGrants.resets?.count == 0)
let nullBlock = try resetBlock("null")
precondition(nullBlock.claudeResets == nil && nullBlock.resets == nil)
let oddResets = try resetBlock("{\"grants\":\"soon\"}")
precondition(oddResets.week?.remaining == 90 && oddResets.resets == nil && oddResets.claudeResets == nil)
precondition(oddResets.unreadableShapes["cedar_ember"] == "{grants:string}", "an unreadable reset block keeps a value-free shape")
precondition(!oddResets.hasModelLimitConcern, "an unreadable reset block does not pause pacing advice")
let shape = ClaudeQuotaClient.shape(Data("{\"seven_day\":{\"utilization\":42.5,\"resets_at\":\"secret-ish\"},\"x\":[1]}".utf8))
precondition(shape == "seven_day:{resets_at:string,utilization:number}; x:array<number>", shape)
precondition(!shape.contains("42") && !shape.contains("secret"), "shape must not carry values")
let expiredCredential = Data("{\"claudeAiOauth\":{\"accessToken\":\"test-only\",\"expiresAt\":1}}".utf8)
do { _ = try ClaudeQuotaCredential.decode(expiredCredential, now: now); fatalError("expired credential") }
catch { precondition(error as? ClaudeQuotaError == .loginExpired, "expired token is not a missing login") }
let missingToken = Data("{\"claudeAiOauth\":{}}".utf8)
do { _ = try ClaudeQuotaCredential.decode(missingToken, now: now); fatalError("missing token") }
catch { precondition(error as? ClaudeQuotaError == .loginRequired) }
precondition(ClaudeQuotaClient.retryDelay("0", now: now) == 3600)
precondition(ClaudeQuotaClient.retryDelay("7200", now: now) == 7200)
precondition(ClaudeQuotaClient.retryDelay("infinity", now: now) == 3600)
precondition(ClaudeQuotaClient.retryDelay("999999", now: now) == 86400)

func quota(_ weekUsed: Double, _ days: Double, fiveUsed: Double? = 10, age: Double = 0) -> ProviderQuotaSnapshot {
    ProviderQuotaSnapshot(checkedAt: now.addingTimeInterval(-age),
        fiveHour: fiveUsed.map { ProviderQuotaWindow(used: $0, resetsAt: fiveReset) },
        week: ProviderQuotaWindow(used: weekUsed, resetsAt: now.addingTimeInterval(days * 86400)))
}
func advice(_ c: ProviderQuotaSnapshot?, _ a: ProviderQuotaSnapshot?, reliable: Bool = true) -> String {
    QuotaBalanceAdvice.make(codex: c, claude: a, codexReliable: reliable, claudeReliable: true,
                            now: now, chinese: false).title
}
precondition(advice(quota(80, 5), quota(20, 5)) == "Prefer Claude next")
precondition(advice(quota(20, 5), quota(80, 5)) == "Prefer Codex next")
// A smaller percentage that resets sooner can have more pacing headroom.
precondition(advice(quota(50, 1), quota(20, 6)) == "Prefer Codex next")
precondition(advice(quota(20, 5), quota(24, 5)) == "Choose by task; stay balanced")
precondition(advice(quota(20, 5, fiveUsed: 95), quota(30, 5)) == "Prefer Claude next")
precondition(advice(quota(95, 5), quota(20, 5, fiveUsed: 99)) == "Conserve both quotas")
precondition(advice(quota(20, 5, fiveUsed: nil), quota(80, 5)) == "Prefer Codex next")
precondition(advice(quota(20, 5, age: 901), snapshot) == "Waiting for fresh quotas")
precondition(advice(quota(20, 0), snapshot) == "Waiting for fresh quotas")
precondition(advice(quota(20, 5), snapshot, reliable: false) == "Waiting for fresh quotas")
precondition(advice(nil, snapshot) == "Waiting for fresh quotas")
precondition(advice(weeklyOnly, snapshot) == "Waiting for fresh quotas")
var limited = snapshot
limited.modelWindows["seven_day_opus"] = ProviderQuotaWindow(used: 99, resetsAt: weekReset)
precondition(advice(snapshot, limited) == "Check Claude model limits")
var unreadable = snapshot
unreadable.unreadableModelWindows = ["seven_day_new"]
precondition(advice(quota(80, 5), unreadable) == "Check Claude model limits", "unknown model window pauses advice")

final class FakeUsageProtocol: URLProtocol {
    static var count = 0
    static var status = 200
    static var responseBody = Data()
    static var held: FakeUsageProtocol?
    static var hold = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.url == ClaudeQuotaClient.endpoint)
        precondition(request.httpMethod == "GET")
        precondition(request.httpBody == nil)
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer offline-test")
        precondition(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        Self.count += 1
        if Self.hold { Self.held = self; return }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
            httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "0"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { Self.held = nil }
}
func pump(until condition: () -> Bool, timeout: Double = 3) {
    let end = Date().addingTimeInterval(timeout)
    while !condition() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    precondition(condition(), "async operation did not complete")
}
func texts(_ view: NSView?) -> [String] {
    guard let view else { return [] }
    return view.subviews.flatMap { child -> [String] in
        if let field = child as? NSTextField { return [field.stringValue] }
        return texts(child)
    }
}
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [FakeUsageProtocol.self]
FakeUsageProtocol.responseBody = body
let suite = "local.codex.battery.claude.offline-test." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let defaultDiagnostics = FileManager.default.temporaryDirectory.appendingPathComponent(suite + ".json")
defer { try? FileManager.default.removeItem(at: defaultDiagnostics) }
let controller = QuotaBalanceMenuController(defaults: defaults, chinese: false,
    client: ClaudeQuotaClient(configuration: config), diagnosticURL: defaultDiagnostics,
    desktopAccess: { fatalError("account checks must not probe macOS Accessibility") },
    credentialLoader: { ClaudeQuotaCredential(accessToken: "offline-test") })
controller.updateCodex(quota(80, 5), reliable: true)
controller.menuWillOpen()
controller.refreshIfDue()
controller.refreshIfDue(manual: true)
precondition(!controller.active && controller.item.view == nil)
precondition(!FileManager.default.fileExists(atPath: defaultDiagnostics.path), "default-off produces no Claude diagnostics")
precondition(FakeUsageProtocol.count == 0, "default-off must not request anything")
controller.setEnabled(true)
pump { texts(controller.item.view).contains("Prefer Claude next") }
precondition(FakeUsageProtocol.count == 1)
controller.menuWillOpen()
controller.refreshIfDue(manual: true)
precondition(FakeUsageProtocol.count == 1, "menu opens and manual clicks must be debounced")

// Force a due refresh in the isolated preferences, then exercise the real callback path.
defaults.removeObject(forKey: "claudeQuotaNextCheck")
defaults.removeObject(forKey: "claudeQuotaLastHTTPAttempt")
FakeUsageProtocol.status = 503
controller.refreshIfDue()
pump { texts(controller.item.view).contains("Claude · Connection failed; retrying later") }
precondition(texts(controller.item.view).contains("80% · stale"), "failure must retain marked cache")
precondition(texts(controller.item.view).contains("Waiting for fresh quotas"))
let beforeCooldown = FakeUsageProtocol.count
controller.refreshIfDue(manual: true)
precondition(FakeUsageProtocol.count == beforeCooldown)

defaults.removeObject(forKey: "claudeQuotaNextCheck")
defaults.removeObject(forKey: "claudeQuotaLastHTTPAttempt")
defaults.removeObject(forKey: "claudeQuotaCooldown")
FakeUsageProtocol.status = 429
controller.refreshIfDue()
pump { texts(controller.item.view).contains("Claude · Rate limited; retries paused") }
let cooldown = defaults.object(forKey: "claudeQuotaCooldown") as! Date
precondition(cooldown.timeIntervalSinceNow > 3590)
let beforeToggle = FakeUsageProtocol.count
controller.setEnabled(false)
controller.setEnabled(true)
precondition(FakeUsageProtocol.count == beforeToggle)
precondition(defaults.object(forKey: "claudeQuotaCooldown") as? Date == cooldown)

defaults.removeObject(forKey: "claudeQuotaNextCheck")
defaults.removeObject(forKey: "claudeQuotaLastHTTPAttempt")
defaults.removeObject(forKey: "claudeQuotaCooldown")
FakeUsageProtocol.status = 401
controller.refreshIfDue()
pump { texts(controller.item.view).contains("Claude · Sign in again to Claude Code") }
precondition(!texts(controller.item.view).contains("80% · stale"), "auth failures clear account data")
precondition(defaults.string(forKey: "claudeQuotaLastOutcome") == "http_401")

defaults.removeObject(forKey: "claudeQuotaNextCheck")
defaults.removeObject(forKey: "claudeQuotaLastHTTPAttempt")
defaults.removeObject(forKey: "claudeQuotaCooldown")
FakeUsageProtocol.status = 403
controller.refreshIfDue()
pump { texts(controller.item.view).contains("Claude · Login cannot read account usage") }
precondition(defaults.string(forKey: "claudeQuotaLastOutcome") == "http_403")

defaults.removeObject(forKey: "claudeQuotaNextCheck")
defaults.removeObject(forKey: "claudeQuotaLastHTTPAttempt")
defaults.removeObject(forKey: "claudeQuotaCooldown")
FakeUsageProtocol.status = 200
FakeUsageProtocol.responseBody = Data("{\"five_hour\":{\"used_pct\":7}}".utf8)
controller.refreshIfDue()
pump { texts(controller.item.view).contains("Claude · Quota format changed or invalid data") }
precondition(defaults.string(forKey: "claudeQuotaLastOutcome") == "invalid_response")
precondition(defaults.string(forKey: "claudeQuotaLastResponseShape") == "five_hour:{used_pct:number}")
FakeUsageProtocol.responseBody = body

// Disabling while a request is outstanding must cancel it and ignore late completion.
defaults.removeObject(forKey: "claudeQuotaNextCheck")
defaults.removeObject(forKey: "claudeQuotaLastHTTPAttempt")
defaults.removeObject(forKey: "claudeQuotaCooldown")
FakeUsageProtocol.hold = true
controller.refreshIfDue()
pump { FakeUsageProtocol.held != nil }
controller.setEnabled(false)
pump { FakeUsageProtocol.held == nil }
precondition(controller.item.view == nil, "disabling the account hides the comparison when Desktop sync is also off")

// A local login failure has made no HTTP request: a manual check can recover
// after credentials are updated, without bypassing server backoff or rate spacing.
let recoverySuite = suite + ".recovery"
let recoveryDefaults = UserDefaults(suiteName: recoverySuite)!
defer { recoveryDefaults.removePersistentDomain(forName: recoverySuite) }
var credentialReady = false
FakeUsageProtocol.hold = false
FakeUsageProtocol.status = 200
let recovery = QuotaBalanceMenuController(defaults: recoveryDefaults, chinese: false,
    client: ClaudeQuotaClient(configuration: config), credentialLoader: {
        if !credentialReady { throw ClaudeQuotaError.loginExpired }
        return ClaudeQuotaCredential(accessToken: "offline-test")
    })
recovery.updateCodex(quota(80, 5), reliable: true)
let beforeRecovery = FakeUsageProtocol.count
recovery.setEnabled(true)
pump { texts(recovery.item.view).contains("Claude · Claude Code login expired · renew it in the terminal") }
precondition(FakeUsageProtocol.count == beforeRecovery)
precondition(recoveryDefaults.object(forKey: "claudeQuotaCooldown") == nil, "local failures set no server cooldown")
let localNext = recoveryDefaults.object(forKey: "claudeQuotaNextCheck") as! Date
precondition(abs(localNext.timeIntervalSinceNow - 300) < 5, "local failures re-read after 5 minutes, no backoff")
precondition(recoveryDefaults.string(forKey: "claudeQuotaLastOutcome") == "credential_expired")
// Repeated local failures must not escalate toward the 1-hour backoff.
for _ in 0..<3 {
    recoveryDefaults.removeObject(forKey: "claudeQuotaNextCheck")
    recovery.refreshIfDue()
    pump { (recoveryDefaults.object(forKey: "claudeQuotaNextCheck") as? Date) != nil }
}
precondition(abs((recoveryDefaults.object(forKey: "claudeQuotaNextCheck") as! Date).timeIntervalSinceNow - 300) < 5)
precondition(FakeUsageProtocol.count == beforeRecovery)
// After the login is renewed, the next automatic opportunity recovers without a manual click.
credentialReady = true
recoveryDefaults.removeObject(forKey: "claudeQuotaNextCheck")
recovery.refreshIfDue()
pump { texts(recovery.item.view).contains("Prefer Claude next") }
precondition(FakeUsageProtocol.count == beforeRecovery + 1)
precondition(recoveryDefaults.string(forKey: "claudeQuotaLastOutcome") == "ok")
recoveryDefaults.removeObject(forKey: "claudeQuotaNextCheck")
let relaunched = QuotaBalanceMenuController(defaults: recoveryDefaults, chinese: false,
    client: ClaudeQuotaClient(configuration: config), credentialLoader: { ClaudeQuotaCredential(accessToken: "offline-test") })
relaunched.refreshIfDue()
precondition(FakeUsageProtocol.count == beforeRecovery + 1, "relaunch must honor HTTP request spacing")

// An older build stored the same timestamp for the next check and server cooldown on local failures.
// Upgrading should remove that delay while retaining a legacy cooldown set by a real request.
let upgradeSuite = suite + ".upgrade"
let upgradeDefaults = UserDefaults(suiteName: upgradeSuite)!
defer { upgradeDefaults.removePersistentDomain(forName: upgradeSuite) }
let legacyCooldown = Date().addingTimeInterval(1800)
upgradeDefaults.set(true, forKey: QuotaBalanceMenuController.enabledKey)
upgradeDefaults.set(legacyCooldown, forKey: "claudeQuotaCooldown")
upgradeDefaults.set(legacyCooldown, forKey: "claudeQuotaNextCheck")
let beforeUpgrade = FakeUsageProtocol.count
let legacyLimited = QuotaBalanceMenuController(defaults: upgradeDefaults, chinese: false,
    client: ClaudeQuotaClient(configuration: config), credentialLoader: { ClaudeQuotaCredential(accessToken: "offline-test") })
legacyLimited.refreshIfDue()
legacyLimited.refreshIfDue(manual: true)
precondition(FakeUsageProtocol.count == beforeUpgrade)
precondition(upgradeDefaults.object(forKey: "claudeQuotaCooldown") as? Date == legacyCooldown)

upgradeDefaults.set(true, forKey: "claudeQuotaCredentialBlocked")
let legacyLocal = QuotaBalanceMenuController(defaults: upgradeDefaults, chinese: false,
    client: ClaudeQuotaClient(configuration: config), credentialLoader: { ClaudeQuotaCredential(accessToken: "offline-test") })
legacyLocal.refreshIfDue()
pump { upgradeDefaults.string(forKey: "claudeQuotaLastOutcome") == "ok" }
precondition(FakeUsageProtocol.count == beforeUpgrade + 1)

// Both providers' reset stocks sit side by side in the comparison panel.
var codexWithResets = quota(20, 5)
codexWithResets.resets = ProviderResetStock(count: 3, expirations: [later])
let dayFormatter = DateFormatter()
dayFormatter.dateFormat = "M/d"
let resetPanel = texts(QuotaBalanceView(codex: codexWithResets, claude: withResets, codexReliable: true,
    claudeReliable: true, claudeStatus: "", now: now, chinese: false))
precondition(resetPanel.contains("Resets"))
precondition(resetPanel.contains("3 · next expires \(dayFormatter.string(from: later))"), "\(resetPanel)")
precondition(resetPanel.contains("3 · next expires \(dayFormatter.string(from: soon))"), "\(resetPanel)")
let noResetPanel = texts(QuotaBalanceView(codex: quota(20, 5), claude: outside, codexReliable: true,
    claudeReliable: true, claudeStatus: "", now: now, chinese: true))
precondition(noResetPanel.contains("可用重置") && noResetPanel.filter { $0 == "—" }.count >= 2, "unknown counts show a dash")
FakeUsageProtocol.responseBody = try JSONSerialization.data(withJSONObject: [
    "seven_day": ["utilization": 14, "resets_at": formatter.string(from: weekReset)],
    "cedar_ember": ["eligible": true, "grants": [["id": "g1", "resets_left": 2, "type": "weekly"]]]])
let resetSuite = suite + ".resets"
let resetDefaults = UserDefaults(suiteName: resetSuite)!
defer { resetDefaults.removePersistentDomain(forName: resetSuite) }
let diagnostics = FileManager.default.temporaryDirectory.appendingPathComponent(resetSuite + ".json")
defer { try? FileManager.default.removeItem(at: diagnostics) }
let resetController = QuotaBalanceMenuController(defaults: resetDefaults, chinese: false,
    client: ClaudeQuotaClient(configuration: config), diagnosticURL: diagnostics,
    credentialLoader: { ClaudeQuotaCredential(accessToken: "offline-test") })
resetController.setEnabled(true)
pump { resetController.currentQuotas.claude?.resets?.count == 2 }
let notes = resetController.settingsItem.submenu!.items.map(\.title)
precondition(notes.contains("Weekly reset ×2"), "\(notes)")
let written = try JSONSerialization.jsonObject(with: Data(contentsOf: diagnostics)) as! [String: Any]
let resetSummary = written["claude_resets"] as! [String: Any]
precondition(resetSummary["available"] as? Int == 2 && resetSummary["eligible"] as? Bool == true)
precondition((resetSummary["grants"] as? [String]) == ["weekly: left 2/2, paused false, ends none"])
let writtenText = String(data: try Data(contentsOf: diagnostics), encoding: .utf8)!
precondition(!writtenText.contains("g1"), "grant ids stay out of diagnostics")
FakeUsageProtocol.responseBody = body

// Startup and locally expired credentials show weekly history without treating it as a live account read.
let expiredSuite = suite + ".expired-history"
let expiredDefaults = UserDefaults(suiteName: expiredSuite)!
defer { expiredDefaults.removePersistentDomain(forName: expiredSuite) }
let expiredHistoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(expiredSuite + ".json")
defer { try? FileManager.default.removeItem(at: expiredHistoryURL) }
ClaudeUsageHistory(url: expiredHistoryURL).record(withLimits)
expiredDefaults.set(true, forKey: QuotaBalanceMenuController.enabledKey)
expiredDefaults.set("ok", forKey: "claudeQuotaLastOutcome")
let expiredController = QuotaBalanceMenuController(defaults: expiredDefaults, chinese: false,
    client: ClaudeQuotaClient(configuration: config), historyURL: expiredHistoryURL,
    credentialLoader: { throw ClaudeQuotaError.loginExpired })
let warmStart = expiredController.displayedClaude(at: now)
precondition(warmStart.snapshot?.week?.remaining == 84 && warmStart.snapshot?.modelWindows["seven_day_fable"]?.remaining == 70)
precondition(warmStart.snapshot?.fiveHour == nil && !warmStart.reliable && expiredController.currentQuotas.claude == nil)
let requestsBeforeExpiry = FakeUsageProtocol.count
expiredController.refreshIfDue()
pump { expiredDefaults.string(forKey: "claudeQuotaLastOutcome") == "credential_expired" }
precondition(texts(expiredController.item.view).contains("84% · stale · Fable 70%"))
precondition(expiredController.currentQuotas.claude == nil && !expiredController.currentQuotas.claudeReliable)
precondition(FakeUsageProtocol.count == requestsBeforeExpiry)
precondition(expiredController.displayedClaude(at: weekReset).snapshot == nil, "history ends with its weekly window")
expiredDefaults.set("http_401", forKey: "claudeQuotaLastOutcome")
let signedOut = QuotaBalanceMenuController(defaults: expiredDefaults, chinese: false, historyURL: expiredHistoryURL)
precondition(signedOut.displayedClaude(at: now).snapshot == nil, "an account rejection cannot revive cached account values")

// The official Desktop page shows one total and grouped grant rows in the accessibility tree.
precondition(ClaudeDesktopUsageRoute.matches(URL(string: "https://claude.ai/settings/usage")!))
precondition(ClaudeDesktopUsageRoute.matches(URL(string: "https://claude.ai/epitaxy/local-test#settings/usage")!))
precondition(!ClaudeDesktopUsageRoute.matches(URL(string: "https://claude.ai/epitaxy/local-test#settings/general")!))
precondition(!ClaudeDesktopUsageRoute.matches(URL(string: "https://example.test/settings/usage#settings/usage")!))
let viewedAt = formatter.date(from: "2026-05-01T00:00:00Z")!
let fullExpiry = formatter.date(from: "2026-05-17T02:15:00Z")!
let fableExpiry = formatter.date(from: "2027-02-03T08:20:00Z")!
let desktop = ClaudeDesktopResetReading.parse(totalLabels: ["限额重置", "3 个可用"], rows: [
    ["完全重置", "完全重置", "于 5月17日 GMT+8 10:15 到期"],
    ["Fable 重置 · 2", "全部于 2027年2月3日 GMT+8 16:20 到期 补满您的 5 小时限额和 Fable 额度。"]
], at: viewedAt, timeZone: TimeZone(secondsFromGMT: 0)!)!
precondition(desktop.stock(at: viewedAt).count == 3 && desktop.grants.map(\.type) == ["full", "fable"])
precondition(desktop.grants.map(\.endsAt) == [fullExpiry, fableExpiry])
precondition(desktop.stock(at: fullExpiry).count == 2 && desktop.stock(at: fableExpiry).count == 0)
let usageLabels = [
    "您的用量", "Ultra", "当前会话", "14:15 重置", "已使用 7%", "本周", "限额重置", "限额重置", "3 个可用",
    "完全重置", "完全重置", "于 5月17日 GMT+8 10:15 到期", "Fable 重置 · 2", "Fable 重置 · 2",
    "全部于 2027年2月3日 GMT+8 16:20 到期 补满您的 5 小时限额和 Fable 额度。", "用量额度", "0 个可用"
]
precondition(ClaudeDesktopResetReading.parseUsageLabels(usageLabels, at: viewedAt) == desktop,
             "the Code settings sheet keeps the count within the reset heading and preserves both grant expiries")
precondition(ClaudeDesktopResetReading.parseUsageLabels(["您的用量", "3 个可用"], at: viewedAt) == nil)
let desktopEnglish = ClaudeDesktopResetReading.parse(totalLabels: ["2 available"], rows: [
    ["Fable limit reset · 2", "Expires Feb 3, 2027 at 4:20 PM GMT+8"]
], at: viewedAt)
precondition(desktopEnglish?.grants.first?.endsAt == fableExpiry)
precondition(ClaudeDesktopResetReading.parse(totalLabels: ["4 available", "3 available"], rows: [], at: viewedAt) == nil)
precondition(ClaudeDesktopResetReading.parse(totalLabels: ["Loading"], rows: [], at: viewedAt) == nil)
let noGrants = ClaudeDesktopResetReading.parse(totalLabels: ["0 个可用"], rows: [], at: viewedAt)!
precondition(noGrants.stock(at: viewedAt).count == 0)
let partialDesktop = ClaudeDesktopResetReading.parse(totalLabels: ["2 available"], rows: [
    ["New limit reset · 2"]
], at: viewedAt)
precondition(partialDesktop?.count == 2 && partialDesktop?.grants.isEmpty == true)

// The Usage page exposes named progress indicators followed by the age of the page data.
let pageAge = ClaudeDesktopQuotaReading.updateAge(in: "最后更新：28 分钟前")!
precondition(pageAge == 28 * 60)
precondition(ClaudeDesktopQuotaReading.updateAge(in: "上次更新：刚刚") == 0)
precondition(ClaudeDesktopQuotaReading.updateAge(in: "上次更新：2 分钟前") == 120)
precondition(ClaudeDesktopQuotaReading.updateAge(in: "Last updated: an hour ago") == 3600)
precondition(ClaudeDesktopQuotaReading.updateAge(in: "Last updated: just now") == 0)
precondition(ClaudeDesktopQuotaReading.updateAge(in: "Last updated: unavailable") == nil)
let quotaProgress: [(ClaudeDesktopQuotaReading.Window, Double?)] = [
    (.init(role: "AXLevelIndicator", labels: ["当前会话"])!, 20),
    (.init(role: "AXLevelIndicator", labels: ["本周"])!, 19),
    (.init(role: "AXLevelIndicator", labels: ["Fable"])!, 36)
]
precondition(ClaudeDesktopQuotaReading.Window(role: "AXProgressIndicator", labels: ["All models"]) == .week)
precondition(ClaudeDesktopQuotaReading.Window(role: "AXButton", labels: ["本周"]) == nil)
let pageQuota = ClaudeDesktopQuotaReading.parse(progress: quotaProgress, updateAge: pageAge)!.snapshot(observedAt: now)
precondition(pageQuota.quota.fiveHour?.remaining == 80 && pageQuota.quota.week?.remaining == 81)
precondition(pageQuota.quota.modelWindows["seven_day_fable"]?.remaining == 64)
let expectedTime = floor((now.timeIntervalSince1970 - pageAge) / 60) * 60
precondition(pageQuota.updatedAt.timeIntervalSince1970 == expectedTime, "use the page's data time, not the sync time")
precondition(ClaudeDesktopQuotaReading.Window(label: "Claude Code") == nil, "product breakdown is not quota")
precondition(ClaudeDesktopQuotaReading.parse(progress: [(.fiveHour, 20)], updateAge: pageAge) == nil)
precondition(ClaudeDesktopQuotaReading.parse(progress: [(.week, 101)], updateAge: pageAge) == nil)
precondition(ClaudeDesktopQuotaReading.parse(progress: quotaProgress + [(.fable, 37)], updateAge: pageAge) == nil)
precondition(ClaudeDesktopQuotaReading.parse(progress: quotaProgress + [(.fable, nil)], updateAge: pageAge) == nil)
let partialPage = ClaudeDesktopQuotaReading.parse(progress: [(.week, 0)], updateAge: 0)!
precondition(partialPage.fiveHourUsed == nil && partialPage.fableUsed == nil && partialPage.weekUsed == 0)

let desktopSuite = suite + ".desktop"
let desktopDefaults = UserDefaults(suiteName: desktopSuite)!
defer { desktopDefaults.removePersistentDomain(forName: desktopSuite) }
let desktopController = QuotaBalanceMenuController(defaults: desktopDefaults, chinese: true,
    client: ClaudeQuotaClient(configuration: config), desktopAccess: { true },
    credentialLoader: { fatalError("Desktop sync used the network path") })
let liveFixture = ClaudeDesktopResetReading(count: desktop.count, grants: desktop.grants.map {
    ClaudeResetGrant(label: $0.label, type: $0.type, resetsLeft: $0.resetsLeft,
                     resetsTotal: $0.resetsTotal, endsAt: $0.type == "full" ? soon : later, paused: false)
})
let beforeDesktop = FakeUsageProtocol.count
desktopController.updateDesktopResets(liveFixture)
desktopController.updateDesktopQuota(pageQuota)
precondition(!desktopController.active && desktopController.desktopResets == nil, "off must ignore desktop readings")
desktopController.setDesktopSyncEnabled(true)
desktopController.updateDesktopResets(liveFixture)
desktopController.updateDesktopQuota(pageQuota)
precondition(!desktopController.desktopQuotaFallbackActive && desktopController.displayedClaude(at: now).snapshot == nil)
precondition(desktopDefaults.object(forKey: "claudeDesktopQuota") == nil, "reset-only users do not store account quota")
precondition(!desktopController.enabled && desktopController.currentQuotas.claude == nil)
precondition(desktopController.claudeResetStock(at: now)?.count == 3, "feeds the menu bar without a quota snapshot")
precondition(texts(desktopController.item.view).contains { $0.hasPrefix("3 次 · 最近") })
precondition(desktopController.settingsItem.submenu!.items.contains { $0.title.hasPrefix("Fable 重置 ×2") })
desktopController.setDesktopSyncEnabled(false)
precondition(!desktopController.active && desktopController.item.view == nil)
precondition(desktopController.claudeResetStock(at: now) == nil, "cached counts are hidden with sync off")
let disabledDesktop = QuotaBalanceMenuController(defaults: desktopDefaults, chinese: true,
    desktopAccess: { fatalError("disabling Desktop sync must survive relaunch") })
precondition(!disabledDesktop.active)
precondition(FakeUsageProtocol.count == beforeDesktop)
// Reproduce the preferences of a pre-toggle installation that had previously synced.
desktopDefaults.removeObject(forKey: "claudeDesktopSyncEnabled")
let restartedDesktop = QuotaBalanceMenuController(defaults: desktopDefaults, chinese: true, desktopAccess: { true })
precondition(restartedDesktop.desktopSyncEnabled && restartedDesktop.desktopResets?.reading == liveFixture,
             "previously synced Desktop users keep their opt-in and cached reading across an upgrade")
restartedDesktop.updateDesktopResets(noGrants)
precondition(restartedDesktop.claudeResetStock(at: now)?.count == 0, "explicit zero replaces the last reading")
restartedDesktop.updateDesktopResets(nil)
let clearedDesktop = QuotaBalanceMenuController(defaults: desktopDefaults, chinese: true, desktopAccess: { true })
precondition(clearedDesktop.desktopResets == nil, "a loaded usage page without a reset section clears the cached reading")

let fallbackSuite = suite + ".desktop-quota"
let fallbackDefaults = UserDefaults(suiteName: fallbackSuite)!
defer { fallbackDefaults.removePersistentDomain(forName: fallbackSuite) }
fallbackDefaults.set(true, forKey: QuotaBalanceMenuController.enabledKey)
var cliLoginReady = false
let fallback = QuotaBalanceMenuController(defaults: fallbackDefaults, chinese: false,
    client: ClaudeQuotaClient(configuration: config), desktopAccess: { true }, credentialLoader: {
        if !cliLoginReady { throw ClaudeQuotaError.loginExpired }
        return ClaudeQuotaCredential(accessToken: "offline-test")
    })
fallback.setDesktopSyncEnabled(true)
fallback.updateDesktopQuota(pageQuota)
precondition(!fallback.desktopQuotaFallbackActive && fallbackDefaults.object(forKey: "claudeDesktopQuota") == nil)
let beforeFallback = FakeUsageProtocol.count
fallback.refreshIfDue()
pump { fallback.desktopQuotaFallbackActive }
precondition(texts(fallback.item.view).contains("Claude Code login expired · open Usage in Claude Desktop"))
fallback.updateDesktopQuota(pageQuota)
fallback.updateDesktopResets(liveFixture)
let pageFields = texts(fallback.item.view)
precondition(pageFields.contains("80% · stale") && pageFields.contains("81% · stale · Fable 64%"))
precondition(pageFields.contains { $0.hasPrefix("≈ ") })
precondition(fallback.claudeResetStock(at: now)?.count == 3)
precondition(fallback.currentQuotas.claude == nil && !fallback.currentQuotas.claudeReliable)
fallback.menuWillOpen()
precondition(fallback.displayedClaude(at: now).snapshot?.checkedAt == pageQuota.updatedAt, "closing the page preserves its date")
let reopenedFallback = QuotaBalanceMenuController(defaults: fallbackDefaults, chinese: false)
precondition(reopenedFallback.displayedClaude(at: now).fromDesktop)
precondition(reopenedFallback.displayedClaude(at: now).snapshot?.checkedAt == pageQuota.updatedAt)
fallback.setDesktopSyncEnabled(false)
fallback.updateDesktopQuota(pageQuota)
precondition(!fallback.desktopQuotaFallbackActive && fallback.displayedClaude(at: now).snapshot == nil)
fallback.setDesktopSyncEnabled(true)
precondition(fallback.displayedClaude(at: now).fromDesktop)
precondition(FakeUsageProtocol.count == beforeFallback, "the Desktop fallback adds no network requests")

// A fresh page can show 100% Fable remaining without borrowing a reset time or authorizing routing.
let freshPage = ClaudeDesktopQuotaReading.parse(progress: [(.week, 19), (.fable, 0)], updateAge: 0)!.snapshot(observedAt: now)
fallback.updateDesktopQuota(freshPage)
precondition(fallback.displayedClaude(at: now).reliable)
precondition(texts(fallback.item.view).contains("81% · Fable 100%"))
precondition(fallback.currentQuotas.claude == nil)

fallbackDefaults.set("http_401", forKey: "claudeQuotaLastOutcome")
precondition(fallback.displayedClaude(at: now).snapshot == nil, "an ambiguous authorization failure cannot display the Desktop cache")
fallbackDefaults.set("credential_expired", forKey: "claudeQuotaLastOutcome")
cliLoginReady = true
fallbackDefaults.removeObject(forKey: "claudeQuotaNextCheck")
FakeUsageProtocol.status = 200
FakeUsageProtocol.responseBody = body
fallback.refreshIfDue()
pump { fallbackDefaults.string(forKey: "claudeQuotaLastOutcome") == "ok" }
precondition(FakeUsageProtocol.count == beforeFallback + 1 && fallback.currentQuotas.claude != nil)
precondition(!fallback.displayedClaude(at: Date()).fromDesktop && fallbackDefaults.object(forKey: "claudeDesktopQuota") == nil)

if CommandLine.arguments.count > 1 {
    let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 920, height: QuotaBalanceView.height * 2))
    canvas.wantsLayer = true
    canvas.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    let cases: [(ProviderQuotaSnapshot?, ProviderQuotaSnapshot?, Bool, Bool, String)] = [
        (codexWithResets, withResets, true, true, "均衡提示仅供参考 · 两家的百分比独立计算"),
        (quota(20, 5), quota(80, 5), true, false, "Pacing hint only · each provider has its own quota"),
        (quota(20, 5), pageQuota.quota, false, true, "Claude Desktop 用量页 · 终端登录已过期"),
        (quota(20, 5), nil, false, false, "Claude is off · enable account quota checks below")]
    for (index, sample) in cases.enumerated() {
        let view = QuotaBalanceView(codex: sample.0, claude: sample.1, codexReliable: sample.2,
            claudeReliable: sample.2, claudeStatus: sample.4, now: now, chinese: sample.3,
            desktopResets: index == 0 || index == 2 ? ClaudeDesktopResetSnapshot(reading: liveFixture, syncedAt: now) : nil,
            claudeFromDesktop: index == 2)
        view.frame.origin = NSPoint(x: CGFloat(index % 2) * 460, y: CGFloat(1 - index / 2) * QuotaBalanceView.height)
        canvas.addSubview(view)
        for field in view.subviews {
            precondition(view.bounds.contains(field.frame), "panel text extends beyond bounds")
        }
    }
    let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
    canvas.cacheDisplay(in: canvas.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print("Claude quota, Desktop reset parsing and sync, auth boundary, cooldown and native panel: ok")
'''

with tempfile.TemporaryDirectory() as folder:
    folder = Path(folder)
    main = folder / "main.swift"
    main.write_text(harness)
    binary = folder / "check-claude-balance"
    subprocess.run([
        "swiftc", str(main), str(root / "Sources/ClaudeQuota.swift"), str(root / "Sources/ClaudeDesktopResets.swift"),
        str(root / "Sources/QuotaBalanceMenu.swift"), str(root / "Sources/ClaudeForecast.swift"),
        str(root / "Sources/WeeklyActivitySchedule.swift"), str(root / "Sources/PaceBars.swift"), "-framework", "AppKit", "-o", str(binary)
    ], check=True)
    command = [str(binary)]
    if preview := os.environ.get("CODEX_BATTERY_BALANCE_PREVIEW"):
        target = Path(preview).resolve()
        target.parent.mkdir(parents=True, exist_ok=True)
        command.append(str(target))
    subprocess.run(command, check=True)
