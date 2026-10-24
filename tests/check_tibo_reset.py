#!/usr/bin/env python3
"""Offline Swift regression checks for the optional public Tibo RSS monitor."""

from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).parents[1]
swift_test = r'''
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

let source = URL(string: "https://nitter.example/thsottiaux/rss")!
let trusted: Set<String> = ["nitter.example"]
let now = ISO8601DateFormatter().date(from: "2026-10-24T02:00:00Z")!
func rss(_ items: String) -> Data {
    Data("<rss version=\"2.0\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><channel><title>Tibo</title>\(items)</channel></rss>".utf8)
}
func item(_ id: String, title: String = "A reset today &amp; another update", date: String = "Fri, 23 Oct 2026 04:46:19 GMT", author: String = "@thsottiaux", link: String? = nil, description: String = "") -> String {
    "<item><title>\(title)</title><dc:creator>\(author)</dc:creator><pubDate>\(date)</pubDate><link>\(link ?? "https://nitter.example/thsottiaux/status/\(id)#m")</link><description><![CDATA[\(description)]]></description></item>"
}
func parse(_ data: Data, at: Date = now) throws -> TiboResetFetchResult {
    try TiboResetFeed.parse(data: data, sourceURL: source, trustedNitterHosts: trusted, now: at)
}
func fails(_ data: Data, _ expected: TiboResetError) {
    do { _ = try parse(data); preconditionFailure("unexpected successful feed") }
    catch { precondition((error as? TiboResetError) == expected, "wrong error: \(error)") }
}

let first = try parse(rss(item("100")))
precondition(first.entries.count == 1)
precondition(first.entries[0].text == "A reset today & another update")
precondition(first.entries[0].url.absoluteString == "https://x.com/thsottiaux/status/100")
precondition(first.entries[0].announcement?.kind == .mention)
let quotedOnly = try parse(rss(item("101", title: "New cache changes", description: "<p>Quoted @other: reset today!</p>")))
precondition(quotedOnly.entries[0].announcement == nil, "quotes must not become author evidence")
let cdata = try parse(rss(item("102", title: "<![CDATA[A reset & more]]>")))
precondition(cdata.entries[0].text == "A reset & more")
let unordered = try parse(rss(item("100") + item("102", date: "Sat, 24 Oct 2026 01:00:00 +0000") + item("102")))
precondition(unordered.entries.map(\.id) == ["102", "100"])
let atom = Data("""
<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Reset tomorrow</title><author><name>Tibo</name><uri>https://x.com/thsottiaux</uri></author><published>2026-10-24T01:30:00.000Z</published><link rel="self" href="https://invalid.example/1"/><link rel="alternate" href="https://twitter.com/thsottiaux/status/103"/></entry></feed>
""".utf8)
let parsedAtom = try parse(atom)
precondition(parsedAtom.entries[0].announcement?.kind == .planned)

fails(Data("<html><title>Just a moment</title></html>".utf8), .invalidFeed)
fails(rss(""), .noOriginalEntries)
fails(rss(item("1", author: "@other")), .noOriginalEntries)
fails(rss(item("1", title: "RT by @thsottiaux: reset today")), .noOriginalEntries)
fails(rss(item("1", date: "not a date")), .noOriginalEntries)
fails(rss(item("1", date: "Sat, 24 Oct 2026 02:06:00 GMT")), .noOriginalEntries)
fails(rss(item("1", date: "Thu, 01 Jan 1970 00:00:00 GMT")), .noOriginalEntries)
fails(rss(item("1", link: "https://x.com/other/status/1")), .noOriginalEntries)
fails(rss(item("1", link: "https://x.com.attacker.example/thsottiaux/status/1")), .noOriginalEntries)
fails(rss(item("1", link: "http://x.com/thsottiaux/status/1")), .noOriginalEntries)
fails(rss(item("1", link: "https://unknown.example/thsottiaux/status/1")), .noOriginalEntries)
fails(rss(item("1", title: String(repeating: "x", count: 4097))), .invalidFeed)
fails(Data(repeating: 65, count: TiboResetFeed.maximumBytes + 1), .tooLarge)
fails(Data("<!DOCTYPE rss [<!ENTITY bad SYSTEM 'file:///etc/passwd'>]><rss><channel/></rss>".utf8), .invalidFeed)
precondition(TiboResetFeed.canonicalPostURL("/thsottiaux/status/42#m", sourceURL: source, trustedNitterHosts: trusted)?.lastPathComponent == "42")
precondition(TiboResetFeed.canonicalPostURL("https://x.com/thsottiaux/status/abc", sourceURL: source, trustedNitterHosts: trusted) == nil)
precondition(TiboResetFeed.canonicalPostURL("https://user@x.com/thsottiaux/status/42", sourceURL: source, trustedNitterHosts: trusted) == nil)

for title in ["No reset today", "Not a reset", "We won't reset today", "Don't expect a reset", "Reset cancelled", "reusable prompt presets", "Landing tomorrow before 10am", "RT @other: a reset"] {
    precondition(TiboResetClassifier.classify(title) == nil, "false positive: \(title)")
}
precondition(TiboResetClassifier.classify("That's a reset!") == .mention)
precondition(TiboResetClassifier.classify("It's reset day today") == .mention)
precondition(TiboResetClassifier.classify("A reset lands tomorrow") == .planned)
precondition(TiboResetClassifier.classify("We will reset next week") == .planned)

var state = TiboResetState()
precondition(state.isDue(now: now))
precondition(state.recordSuccess(first).isEmpty, "first check establishes a quiet baseline")
precondition(state.lastFeedPostAt == first.entries[0].publishedAt)
precondition(!state.isDue(now: now.addingTimeInterval(7199)))
precondition(state.isDue(now: now.addingTimeInterval(7200)))
let newCheck = now.addingTimeInterval(7200)
let newEntries = try parse(rss(item("103", title: "A reset tomorrow", date: "Sat, 24 Oct 2026 03:00:00 GMT") + item("100")), at: newCheck)
precondition(state.recordSuccess(newEntries).map(\.id) == ["103"])
precondition(state.recordSuccess(newEntries).isEmpty, "same post must not notify twice")
precondition(state.latestAnnouncement?.id == "103")
state.recordFailure(.networkError, now: newCheck)
precondition(state.latestAnnouncement?.id == "103", "offline failure preserves the last announcement")
precondition(state.lastSuccess == newCheck)
precondition(!state.isDue(now: newCheck.addingTimeInterval(3599)))
precondition(state.isDue(now: newCheck.addingTimeInterval(3600)))
state.recordFailure(.httpError, now: newCheck)
precondition(state.nextCheckDate(now: newCheck) == newCheck.addingTimeInterval(7200))
for _ in 0..<10 { state.recordFailure(.httpError, now: newCheck) }
precondition(state.nextCheckDate(now: newCheck) == newCheck.addingTimeInterval(12 * 3600))
var badClock = state
badClock.lastAttempt = newCheck.addingTimeInterval(86400 * 40)
badClock.lastSuccess = newCheck.addingTimeInterval(86400 * 40)
precondition(badClock.isDue(now: newCheck), "future persisted timestamps must not suspend checking")
let encoded = try JSONEncoder().encode(state)
var restored = try JSONDecoder().decode(TiboResetState.self, from: encoded)
precondition(restored.hasBaseline && restored.latestAnnouncement?.id == "103")
precondition(restored.recordSuccess(newEntries).isEmpty)
_ = restored.recordSuccess(first)
precondition(restored.latestAnnouncement?.id == "103", "older feed must not replace the latest announcement")
// Literal data saved by the preceding 24h version, rather than re-encoding the
// current model. Foundation's default Date encoding is seconds since 2001-01-01.
let previousVersionJSON = Data("""
{
  "lastAttempt": 814500000,
  "lastSuccess": 814500000,
  "lastFeedPostAt": 814423579,
  "latestAnnouncement": {
    "id": "100",
    "url": "https://x.com/thsottiaux/status/100",
    "publishedAt": 814423579,
    "text": "A reset today & another update",
    "kind": "mention"
  },
  "lastSeenIDs": ["100"],
  "consecutiveFailures": 0,
  "sourceURL": "https://nitter.example/thsottiaux/rss",
  "hasBaseline": true
}
""".utf8)
let previousVersion = try JSONDecoder().decode(TiboResetState.self, from: previousVersionJSON)
precondition(previousVersion.hasBaseline)
precondition(previousVersion.lastSeenIDs == ["100"])
precondition(previousVersion.latestAnnouncement?.id == "100")
precondition(previousVersion.latestAnnouncement?.text == "A reset today & another update")
precondition(previousVersion.lastSuccess == now)
precondition(previousVersion.lastFeedPostAt == first.entries[0].publishedAt)
precondition(previousVersion.nextCheckDate(now: now) == now.addingTimeInterval(7200))
precondition(!previousVersion.isDue(now: now.addingTimeInterval(7199)))
precondition(previousVersion.isDue(now: now.addingTimeInterval(7200)))
let suiteName = "local.codex.battery.tibo-test.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
let store = TiboResetStore(defaults: defaults)
store.save(restored)
precondition(store.load().lastSeenIDs == restored.lastSeenIDs)
defaults.set(previousVersionJSON, forKey: "tiboResetState.v1")
precondition(store.load().hasBaseline)
precondition(store.load().latestAnnouncement?.id == "100")
precondition(store.load().nextCheckDate(now: now) == now.addingTimeInterval(7200))
defaults.removePersistentDomain(forName: suiteName)

final class FeedProtocol: URLProtocol {
    static var responses: [(Int, String, Data)] = []
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let (status, type, body) = Self.responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [FeedProtocol.self]
let callbackQueue = DispatchQueue(label: "tibo.test.callback")
let client = TiboResetClient(trustedNitterHosts: trusted, configuration: config, callbackQueue: callbackQueue)
let semaphore = DispatchSemaphore(value: 0)
FeedProtocol.responses = [(200, "text/html", Data("<html>challenge</html>".utf8)), (200, "application/rss+xml", rss(item("105")))]
let handle = client.fetch(sources: [source, source]) { result in
    precondition((try? result.get().entries[0].id) == "105", "must fall back after HTML challenge")
    semaphore.signal()
}
precondition(semaphore.wait(timeout: .now() + 5) == .success)
precondition(FeedProtocol.requests.count == 2)
precondition(FeedProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil && $0.value(forHTTPHeaderField: "Authorization") == nil })
FeedProtocol.responses = [(503, "text/plain", Data("unavailable".utf8))]
let failedHandle = client.fetch(sources: [source]) { result in
    if case .failure(.httpError) = result {} else { preconditionFailure("HTTP errors must stay failures") }
    semaphore.signal()
}
precondition(semaphore.wait(timeout: .now() + 5) == .success)
FeedProtocol.responses = [(200, "application/rss+xml", Data(repeating: 65, count: TiboResetFeed.maximumBytes + 1))]
let oversizedHandle = client.fetch(sources: [source]) { result in
    if case .failure(.tooLarge) = result {} else { preconditionFailure("streaming size limit must reject oversized data") }
    semaphore.signal()
}
precondition(semaphore.wait(timeout: .now() + 5) == .success)
callbackQueue.suspend()
FeedProtocol.responses = [(200, "application/rss+xml", rss(item("106")))]
let cancelledHandle = client.fetch(sources: [source]) { _ in
    semaphore.signal()
}
cancelledHandle.cancel()
callbackQueue.resume()
precondition(semaphore.wait(timeout: .now() + 0.25) == .timedOut, "cancelled requests must suppress callbacks")
print("Tibo RSS parsing, classification, cache, scheduling and offline network checks: ok")
'''

with tempfile.TemporaryDirectory(prefix="codex-battery-tibo-test-") as directory:
    temp = Path(directory)
    main = temp / "main.swift"
    main.write_text(swift_test, encoding="utf-8")
    binary = temp / "check-tibo-reset"
    compiled = subprocess.run(
        ["swiftc", "-module-cache-path", str(temp / "module-cache"),
         str(root / "Sources" / "TiboResetMonitor.swift"), str(main), "-o", str(binary)],
        text=True, capture_output=True, check=False,
    )
    if compiled.returncode:
        raise AssertionError(compiled.stdout + compiled.stderr)
    checked = subprocess.run([str(binary)], text=True, capture_output=True, check=False)
    if checked.returncode:
        raise AssertionError(checked.stdout + checked.stderr)
    print(checked.stdout.strip())
