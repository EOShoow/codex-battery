#!/usr/bin/env python3
"""Render the real Tibo menu views and verify states without network or installed-app changes."""

import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).parents[1]
text = (root / "Sources/main.swift").read_text(encoding="utf-8")
entrypoint = """let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
"""
assert entrypoint in text
# Architectural guards: automatic RSS requests must borrow an existing quota
# refresh opportunity, with no independent Tibo wake-up scheduler.
menu_source = (root / "Sources/TiboResetMenu.swift").read_text(encoding="utf-8")
for independent_scheduler in ("Timer(", "Timer.", "Timer?", "didWakeNotification", "scheduleNextCheck"):
    assert independent_scheduler not in menu_source, independent_scheduler
refresh_start = text.index("    private func performRefresh(")
refresh_end = text.index("    func menuWillOpen(", refresh_start)
quota_refresh = text[refresh_start:refresh_end]
quota_hook = "tiboResetMenu.quotaRefreshDidStart()"
assert quota_hook in quota_refresh
assert quota_refresh.index("guard !isRefreshing") < quota_refresh.index(quota_hook)
assert "tiboResetMenu.start()" not in text
harness = r'''
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let suite = "local.codex.battery.tibo.test." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let now = Date()
let post = TiboResetEntry(
    id: "2113492187770175603", url: URL(string: "https://x.com/thsottiaux/status/2113492187770175603")!,
    publishedAt: now.addingTimeInterval(-3600),
    text: "Day 18/ Decisions API is GA, OpenResponses joined the Linux Foundation, we shipped some performance improvements and Uber is going all-in on codex & work. But yes… that’s a reset!"
)
let feed = TiboResetFetchResult(entries: [post], sourceURL: TiboResetMenuController.defaultFeedURL, checkedAt: now)
let store = TiboResetStore(defaults: defaults)
var state = TiboResetState()
let off = TiboResetMenuController(defaults: defaults, useChinese: true)
precondition(off.item.title.contains("未启用"))
precondition(off.item.submenu!.items.first!.state == .off)
precondition(off.item.submenu!.items.first!.title == "省电联网检查（约每 2 小时）")
let offCheck = off.item.submenu!.items.first { $0.title == "立即检查" }!
precondition(!offCheck.isEnabled)
precondition(TiboResetMenuController.validFeedURL("http://example.org/feed") == nil)
precondition(TiboResetMenuController.validFeedURL("https://user:password@example.org/feed") == nil)
precondition(TiboResetMenuController.validFeedURL("https://example.org/feed#x") == nil)
precondition(TiboResetMenuController.validFeedURL("https://example.org/feed") != nil)

defaults.set(true, forKey: TiboResetMenuController.enabledKey)
let untested = TiboResetMenuController(defaults: defaults, useChinese: true)
precondition(untested.item.title.contains("尚未检查"))
var initialFailureState = TiboResetState()
initialFailureState.recordFailure(.networkError, now: now)
store.save(initialFailureState)
let initialFailure = TiboResetMenuController(defaults: defaults, useChinese: true)
precondition(initialFailure.item.title.contains("检查失败 · 尚无结果"))
precondition(!initialFailure.item.submenu!.items.contains { $0.title == "查看原帖" })
state.recordSuccess(feed)
store.save(state)
let success = TiboResetMenuController(defaults: defaults, useChinese: true)
precondition(success.item.title.contains("reset 提及"))
precondition(success.item.submenu!.items.contains { $0.title == "查看原帖" })
precondition(success.item.submenu!.items.contains { $0.title.hasPrefix("源中最新帖子：") })
precondition(success.item.submenu!.items.contains { $0.title.hasPrefix("下次到期（随额度刷新）：") })
precondition(success.item.submenu!.items.first { $0.title == "立即检查" }!.isEnabled == false)
state.recordFailure(.networkError, now: now)
store.save(state)
let failure = TiboResetMenuController(defaults: defaults, useChinese: true)
precondition(failure.item.title.contains("检查失败"))
precondition(failure.item.submenu!.items.contains { $0.title == "查看原帖" })
let english = TiboResetMenuController(defaults: defaults, useChinese: false)
precondition(english.item.title.contains("Check failed"))
precondition(english.item.submenu!.items.first!.title == "Low-power check (about every 2h)")
precondition(english.item.submenu!.items.contains { $0.title.hasPrefix("Next due (with quota refresh): ") })

var staleState = TiboResetState()
let oldPost = TiboResetEntry(id: "10001", url: URL(string: "https://x.com/thsottiaux/status/10001")!, publishedAt: now.addingTimeInterval(-8 * 24 * 3600), text: "Reset day today")
staleState.recordSuccess(TiboResetFetchResult(entries: [oldPost], sourceURL: feed.sourceURL, checkedAt: now))
store.save(staleState)
let stale = TiboResetMenuController(defaults: defaults, useChinese: true)
precondition(stale.item.title.contains("来源内容较旧"))

// An actual URLSession/URLProtocol boundary, with a held response to prove that
// multiple shared quota refresh events cannot start concurrent RSS requests.
final class LowPowerFeedProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0
    private static var status = 200
    private static var body = Data()
    private static var hold = false
    private static var pending: [LowPowerFeedProtocol] = []
    private var responseStatus = 200
    private var responseBody = Data()
    private var stopped = false

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    static func configure(status: Int = 200, body: Data, hold: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        precondition(pending.isEmpty, "previous response still pending")
        count = 0
        Self.status = status
        Self.body = body
        Self.hold = hold
    }
    static func releaseHeldResponse() {
        lock.lock()
        let held = pending
        pending = []
        hold = false
        lock.unlock()
        for item in held { item.deliver() }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.count += 1
        responseStatus = Self.status
        responseBody = Self.body
        let shouldHold = Self.hold
        if shouldHold { Self.pending.append(self) }
        Self.lock.unlock()
        if !shouldHold { deliver() }
    }
    private func deliver() {
        Self.lock.lock()
        let cancelled = stopped
        Self.lock.unlock()
        guard !cancelled else { return }
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        precondition(request.value(forHTTPHeaderField: "Cookie") == nil)
        let response = HTTPURLResponse(url: request.url!, statusCode: responseStatus, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/rss+xml"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        Self.lock.lock()
        stopped = true
        Self.lock.unlock()
    }
}
func pumpMainRunLoop(for duration: TimeInterval = 0.1) {
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline { RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.01))) }
}
func waitFor(_ description: String, _ predicate: () -> Bool) {
    let deadline = Date().addingTimeInterval(4)
    while !predicate(), Date() < deadline { pumpMainRunLoop(for: 0.01) }
    precondition(predicate(), "timed out: \(description)")
}
let networkSuite = suite + ".network"
let networkDefaults = UserDefaults(suiteName: networkSuite)!
defer { networkDefaults.removePersistentDomain(forName: networkSuite) }
let networkStore = TiboResetStore(defaults: networkDefaults)
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [LowPowerFeedProtocol.self]
let networkClient = TiboResetClient(configuration: config)
let publicationDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30))
let networkRSS = Data("""
<rss version="2.0"><channel><title>Tibo</title><item><title>A reset today</title><pubDate>\(publicationDate)</pubDate><link>https://x.com/thsottiaux/status/2113492187770175604</link></item></channel></rss>
""".utf8)
let cachedPost = TiboResetEntry(id: "2113492187770175603", url: post.url,
    publishedAt: Date().addingTimeInterval(-7300), text: "An earlier reset")
var dueState = TiboResetState()
dueState.recordSuccess(TiboResetFetchResult(entries: [cachedPost], sourceURL: feed.sourceURL,
                                          checkedAt: Date().addingTimeInterval(-7201)))
LowPowerFeedProtocol.configure(body: networkRSS)
networkStore.save(dueState)
networkDefaults.set(false, forKey: TiboResetMenuController.enabledKey)
let disabledNetwork = TiboResetMenuController(defaults: networkDefaults, useChinese: true, client: networkClient)
disabledNetwork.quotaRefreshDidStart()
disabledNetwork.menuWillOpen()
pumpMainRunLoop()
precondition(LowPowerFeedProtocol.requestCount == 0, "disabled monitoring must never request RSS")

networkDefaults.set(true, forKey: TiboResetMenuController.enabledKey)
var freshState = TiboResetState()
freshState.recordSuccess(feed)
networkStore.save(freshState)
let freshNetwork = TiboResetMenuController(defaults: networkDefaults, useChinese: true, client: networkClient)
freshNetwork.quotaRefreshDidStart()
pumpMainRunLoop()
precondition(LowPowerFeedProtocol.requestCount == 0, "fresh cache must not request RSS on quota refresh")

networkStore.save(dueState)
let overdueNetwork = TiboResetMenuController(defaults: networkDefaults, useChinese: true, client: networkClient)
overdueNetwork.menuWillOpen()
pumpMainRunLoop()
precondition(LowPowerFeedProtocol.requestCount == 0, "opening the Tibo menu must not create an automatic request")
LowPowerFeedProtocol.configure(body: networkRSS, hold: true)
for _ in 0..<6 { overdueNetwork.quotaRefreshDidStart() }
waitFor("one shared refresh request") { LowPowerFeedProtocol.requestCount == 1 }
for _ in 0..<6 { overdueNetwork.quotaRefreshDidStart() }
pumpMainRunLoop()
precondition(LowPowerFeedProtocol.requestCount == 1, "in-flight RSS requests must not re-enter")
LowPowerFeedProtocol.releaseHeldResponse()
waitFor("RSS success cached") {
    networkStore.load().latestAnnouncement?.id == "2113492187770175604" &&
        networkStore.load().lastSuccess.map { Date().timeIntervalSince($0) < 10 } == true
}
overdueNetwork.quotaRefreshDidStart()
pumpMainRunLoop()
precondition(LowPowerFeedProtocol.requestCount == 1, "successful checks must wait for the next 2h due time")

networkStore.save(dueState)
LowPowerFeedProtocol.configure(status: 503, body: Data("unavailable".utf8))
let failedNetwork = TiboResetMenuController(defaults: networkDefaults, useChinese: true, client: networkClient)
failedNetwork.quotaRefreshDidStart()
waitFor("RSS failure cached") { networkStore.load().lastError == .httpError }
precondition(networkStore.load().latestAnnouncement?.id == cachedPost.id, "failure must preserve the prior announcement")
for _ in 0..<6 { failedNetwork.quotaRefreshDidStart() }
failedNetwork.menuWillOpen()
pumpMainRunLoop()
precondition(LowPowerFeedProtocol.requestCount == 1, "failure backoff must also apply to shared quota refresh events")

let controllers = [off, untested, success, failure, stale, english]
func snapshotAnnouncement(_ view: NSView) -> NSImage {
    // NSMenuItem resets its custom view's origin to zero. Render that real native
    // row on its own, then place its pixels into the offscreen contact sheet.
    for label in view.subviews {
        precondition(view.bounds.contains(label.frame), "announcement text outside its row")
    }
    let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = view
    view.appearance = NSAppearance(named: .aqua)
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.white.cgColor
    view.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    var darkPixels = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  color.alphaComponent > 0.5,
                  max(color.redComponent, color.greenComponent, color.blueComponent) < 0.7 else { continue }
            darkPixels += 1
            precondition(x > 2 && y > 2 && x < rep.pixelsWide - 3 && y < rep.pixelsHigh - 3,
                         "announcement glyph touches or crosses its row boundary")
        }
    }
    precondition(darkPixels > 30, "native announcement snapshot contains no rendered text")
    let image = NSImage(size: view.bounds.size)
    image.addRepresentation(rep)
    return image
}
if CommandLine.arguments.count > 1 {
    // Native view contact sheet; this is not a screenshot of an opened system menu.
    let width: CGFloat = 480
    let cardHeight: CGFloat = 650
    let board = NSView(frame: NSRect(x: 0, y: 0, width: width * 3, height: cardHeight * 2))
    board.wantsLayer = true
    board.layer?.backgroundColor = NSColor.white.cgColor
    for (index, controller) in controllers.enumerated() {
        let card = NSView(frame: NSRect(x: CGFloat(index % 3) * width, y: CGFloat(1 - index / 3) * cardHeight, width: width, height: cardHeight))
        let heading = NSTextField(wrappingLabelWithString: controller.item.title)
        heading.frame = NSRect(x: 16, y: cardHeight - 56, width: width - 32, height: 42)
        heading.font = .boldSystemFont(ofSize: 14)
        card.addSubview(heading)
        var top = cardHeight - 66
        for entry in controller.item.submenu!.items {
            if entry.isSeparatorItem { top -= 12; continue }
            if let view = entry.view {
                let image = snapshotAnnouncement(view)
                let preview = NSImageView(frame: NSRect(x: 8, y: top - view.frame.height,
                                                       width: view.frame.width, height: view.frame.height))
                preview.image = image
                top -= view.frame.height
                card.addSubview(preview)
            } else {
                let label = NSTextField(labelWithString: (entry.state == .on ? "✓ " : "") + entry.title)
                label.frame = NSRect(x: 24, y: top - 24, width: width - 48, height: 24)
                label.font = .menuFont(ofSize: NSFont.systemFontSize)
                label.textColor = entry.isEnabled ? .labelColor : .secondaryLabelColor
                label.lineBreakMode = .byTruncatingTail
                card.addSubview(label)
                top -= 27
            }
        }
        precondition(top > 0, "menu preview overflow")
        board.addSubview(card)
    }
    board.appearance = NSAppearance(named: .aqua)
    let rep = board.bitmapImageRepForCachingDisplay(in: board.bounds)!
    board.cacheDisplay(in: board.bounds, to: rep)
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print("Tibo menu states, shared quota refresh gating and native views: ok")
'''
with tempfile.TemporaryDirectory() as temporary:
    folder = Path(temporary)
    main = folder / "main.swift"
    binary = folder / "tibo-menu-check"
    main.write_text(text.replace(entrypoint, harness), encoding="utf-8")
    subprocess.run(["swiftc", str(main),
                    *[str(p) for p in sorted((root / "Sources").glob("*.swift")) if p.name != "main.swift"],
                    "-framework", "AppKit", "-module-cache-path", str(folder / "module-cache"), "-o", str(binary)], check=True)
    command = [str(binary)]
    preview = os.environ.get("CODEX_BATTERY_TIBO_PREVIEW")
    if preview:
        target = Path(preview)
        target.parent.mkdir(parents=True, exist_ok=True)
        command.append(str(target))
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    print(result.stdout.strip())
