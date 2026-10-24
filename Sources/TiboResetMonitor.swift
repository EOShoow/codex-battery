import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A public post is an announcement signal, never proof that account quota was reset.
enum TiboResetAnnouncementKind: String, Codable {
    case mention
    case planned
}

struct TiboResetAnnouncement: Codable, Equatable {
    let id: String
    let url: URL
    let publishedAt: Date
    /// Only the feed's title (the author's own post); embedded descriptions/quotes are ignored.
    let text: String
    let kind: TiboResetAnnouncementKind
}

struct TiboResetEntry: Equatable {
    let id: String
    let url: URL
    let publishedAt: Date
    let text: String

    var announcement: TiboResetAnnouncement? {
        guard let kind = TiboResetClassifier.classify(text) else { return nil }
        return TiboResetAnnouncement(id: id, url: url, publishedAt: publishedAt, text: text, kind: kind)
    }
}

enum TiboResetClassifier {
    static func classify(_ text: String) -> TiboResetAnnouncementKind? {
        let normalized = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
        guard matches(#"\bresets?\b"#, normalized), !isRepost(normalized) else { return nil }
        // A deliberately conservative filter: even an ambiguous denial is not an announcement.
        let denials = [
            #"\bno\s+(?:(?:new|quota|usage|daily|weekly|full)\s+)*resets?\b"#,
            #"\bnot\s+(?:(?:a|another|the|new|quota|usage|daily|weekly|full)\s+)*resets?\b"#,
            #"\b(?:don't|do not|doesn't|does not|won't|will not|can't|cannot|never)\b[^.!?]{0,60}\bresets?\b"#,
            #"\bresets?\b[^.!?]{0,35}\b(?:cancelled|canceled|not happening|didn't happen)\b"#,
        ]
        guard !denials.contains(where: { matches($0, normalized) }) else { return nil }
        if matches(#"\b(?:tomorrow|upcoming|soon|later|next\s+(?:day|week)|will|planning|planned|scheduled)\b"#, normalized) {
            return .planned
        }
        return .mention
    }

    static func isRepost(_ text: String) -> Bool {
        matches(#"^\s*(?:rt\s+(?:by\s+)?@|repost(?:ed)?\s+(?:by\s+)?@)"#, text.lowercased())
    }

    private static func matches(_ pattern: String, _ value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}

enum TiboResetError: String, Error, LocalizedError, Codable {
    case noSources
    case invalidSource
    case httpError
    case tooLarge
    case invalidFeed
    case noOriginalEntries
    case networkError

    var errorDescription: String? { rawValue }
}

struct TiboResetFetchResult {
    let entries: [TiboResetEntry]
    let sourceURL: URL
    let checkedAt: Date
}

/// A bounded RSS 2.0 / Atom reader. No description, embedded quote, media or script is read.
enum TiboResetFeed {
    static let maximumBytes = 512 * 1024
    static let maximumEntries = 100
    static let maximumTextLength = 4_096

    static func parse(
        data: Data,
        sourceURL: URL,
        trustedNitterHosts: Set<String> = [],
        now: Date = Date()
    ) throws -> TiboResetFetchResult {
        guard isSafeSource(sourceURL) else { throw TiboResetError.invalidSource }
        guard data.count <= maximumBytes else { throw TiboResetError.tooLarge }
        guard let xml = String(data: data, encoding: .utf8),
              xml.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              xml.range(of: "<!ENTITY", options: .caseInsensitive) == nil else {
            throw TiboResetError.invalidFeed
        }
        let reader = TiboFeedXMLReader(sourceURL: sourceURL, trustedNitterHosts: trustedNitterHosts, now: now)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.validRoot, !reader.rejected else { throw TiboResetError.invalidFeed }
        guard !reader.entries.isEmpty else { throw TiboResetError.noOriginalEntries }
        let entries = reader.entries.sorted {
            if $0.publishedAt != $1.publishedAt { return $0.publishedAt > $1.publishedAt }
            return newerID($0.id, than: $1.id)
        }
        return TiboResetFetchResult(entries: entries, sourceURL: sourceURL, checkedAt: now)
    }

    static func isSafeSource(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil && url.password == nil
    }

    static func canonicalPostURL(_ value: String, sourceURL: URL, trustedNitterHosts: Set<String>) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: sourceURL)?.absoluteURL,
              isSafeSource(url), let host = url.host?.lowercased() else { return nil }
        let allowedHosts = Set(["x.com", "www.x.com", "twitter.com", "www.twitter.com"])
            .union(trustedNitterHosts.map { $0.lowercased() })
        guard allowedHosts.contains(host), url.port == nil || url.port == 443 else { return nil }
        let components = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 3,
              components[0].lowercased() == "thsottiaux", components[1] == "status",
              !components[2].isEmpty, components[2].count <= 25,
              components[2].allSatisfy({ $0.isASCII && $0.isNumber }),
              components[2].contains(where: { $0 != "0" }) else { return nil }
        return URL(string: "https://x.com/thsottiaux/status/\(components[2])")
    }

    fileprivate static func newerID(_ lhs: String, than rhs: String) -> Bool {
        lhs.count != rhs.count ? lhs.count > rhs.count : lhs > rhs
    }

    fileprivate static func date(_ value: String) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

private final class TiboFeedXMLReader: NSObject, XMLParserDelegate {
    private struct Draft {
        var fields: [String: String] = [:]
        var link: String?
    }
    let sourceURL: URL
    let trustedNitterHosts: Set<String>
    let now: Date
    var validRoot = false
    var rejected = false
    var entries: [TiboResetEntry] = []
    private var path: [String] = []
    private var draft: Draft?
    private var entryDepth = 0
    private var entryCount = 0
    private var seenIDs = Set<String>()

    init(sourceURL: URL, trustedNitterHosts: Set<String>, now: Date) {
        self.sourceURL = sourceURL
        self.trustedNitterHosts = trustedNitterHosts
        self.now = now
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        let name = elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? elementName.lowercased()
        path.append(name)
        if path.count == 1 {
            validRoot = name == "rss" || name == "feed"
            if !validRoot { reject(parser); return }
        }
        guard path.count <= 24 else { reject(parser); return }
        if name == "item" || name == "entry" {
            guard draft == nil else { reject(parser); return }
            entryCount += 1
            guard entryCount <= TiboResetFeed.maximumEntries else { reject(parser); return }
            draft = Draft()
            entryDepth = path.count
        } else if draft != nil, path.count == entryDepth + 1, name == "link",
                  let href = attributes["href"], attributes["rel"] == nil || attributes["rel"] == "alternate" {
            draft?.link = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { append(string, parser: parser) }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { reject(parser); return }
        append(string, parser: parser)
    }

    private func field() -> String? {
        guard draft != nil, let current = path.last else { return nil }
        if path.count == entryDepth + 1,
           ["title", "link", "guid", "pubdate", "published", "updated", "creator", "author"].contains(current) { return current }
        if path.count == entryDepth + 2, path.dropLast().last == "author", ["name", "uri"].contains(current) {
            return "author_\(current)"
        }
        return nil
    }

    private func append(_ string: String, parser: XMLParser) {
        guard let field = field() else { return }
        let existing = draft?.fields[field] ?? ""
        guard existing.count + string.count <= TiboResetFeed.maximumTextLength else { reject(parser); return }
        draft?.fields[field] = existing + string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if draft != nil, path.count == entryDepth, ["item", "entry"].contains(path.last ?? "") {
            if let draft { finish(draft) }
            draft = nil
        }
        if !path.isEmpty { path.removeLast() }
    }

    private func finish(_ draft: Draft) {
        let fields = draft.fields
        guard let rawTitle = fields["title"],
              let rawLink = draft.link ?? fields["link"] ?? fields["guid"],
              let url = TiboResetFeed.canonicalPostURL(rawLink, sourceURL: sourceURL, trustedNitterHosts: trustedNitterHosts),
              let rawDate = fields["pubdate"] ?? fields["published"] ?? fields["updated"],
              let date = TiboResetFeed.date(rawDate),
              date.timeIntervalSince1970 >= 1_262_304_000, // A malformed epoch date is not a usable publication date.
              date <= now.addingTimeInterval(5 * 60) else { return }
        let text = rawTitle.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty, !TiboResetClassifier.isRepost(text) else { return }
        // A status path identifies its author. If the feed additionally supplies an author,
        // require the handle to agree rather than accepting a repost/quote by someone else.
        for key in ["creator", "author", "author_name", "author_uri"] {
            guard let author = fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty else { continue }
            if key == "author_name", fields["author_uri"] != nil { continue }
            guard isTiboAuthor(author) else { return }
        }
        let id = url.lastPathComponent
        guard seenIDs.insert(id).inserted else { return }
        entries.append(TiboResetEntry(id: id, url: url, publishedAt: date, text: text))
    }

    private func isTiboAuthor(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower == "@thsottiaux" || lower == "thsottiaux" { return true }
        guard let url = URL(string: value), TiboResetFeed.isSafeSource(url), let host = url.host?.lowercased() else { return false }
        let allowed = Set(["x.com", "www.x.com", "twitter.com", "www.twitter.com"]).union(trustedNitterHosts)
        return allowed.contains(host) && url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() == "thsottiaux"
    }

    private func reject(_ parser: XMLParser) {
        rejected = true
        parser.abortParsing()
    }
}

struct TiboResetState: Codable {
    var lastAttempt: Date?
    var lastSuccess: Date?
    var lastFeedPostAt: Date?
    var latestAnnouncement: TiboResetAnnouncement?
    var lastSeenIDs: [String] = []
    var lastError: TiboResetError?
    var consecutiveFailures = 0
    var sourceURL: URL?
    private(set) var hasBaseline = false

    /// Success means an actual feed with at least one verified original post, even if no post mentions reset.
    @discardableResult
    mutating func recordSuccess(_ result: TiboResetFetchResult) -> [TiboResetAnnouncement] {
        let previousIDs = Set(lastSeenIDs)
        let wasEstablished = hasBaseline
        let previousSuccess = lastSuccess
        let announcements = result.entries.compactMap(\.announcement)
        let fresh = announcements.filter { announcement in
            guard wasEstablished, !previousIDs.contains(announcement.id) else { return false }
            // A source switching to a longer archive must not announce old posts as new.
            if let previousSuccess, announcement.publishedAt < previousSuccess.addingTimeInterval(-5 * 60) { return false }
            return true
        }
        if let latest = announcements.max(by: {
            $0.publishedAt != $1.publishedAt ? $0.publishedAt < $1.publishedAt : TiboResetFeed.newerID($1.id, than: $0.id)
        }),
           latestAnnouncement == nil || latest.publishedAt > latestAnnouncement!.publishedAt ||
            (latest.publishedAt == latestAnnouncement!.publishedAt && TiboResetFeed.newerID(latest.id, than: latestAnnouncement!.id)) {
            latestAnnouncement = latest
        }
        lastSeenIDs = Array((result.entries.map(\.id) + lastSeenIDs).reduce(into: [String]()) { ids, id in
            if !ids.contains(id) { ids.append(id) }
        }.prefix(300))
        lastAttempt = result.checkedAt
        lastSuccess = result.checkedAt
        lastFeedPostAt = result.entries.map(\.publishedAt).max()
        lastError = nil
        consecutiveFailures = 0
        sourceURL = result.sourceURL
        hasBaseline = true
        return fresh.sorted { $0.publishedAt < $1.publishedAt }
    }

    mutating func recordFailure(_ error: TiboResetError, now: Date = Date()) {
        lastAttempt = now
        lastError = error
        consecutiveFailures = min(consecutiveFailures + 1, 10)
    }

    /// Due after 2h of success, checked on an existing quota refresh. Failures back off from 1h to 12h.
    func nextCheckDate(now: Date = Date()) -> Date {
        if lastError != nil, let attempt = sensible(lastAttempt, now: now) {
            let delay = min(12 * 3_600.0, 3_600.0 * pow(2, Double(max(0, min(consecutiveFailures - 1, 4)))))
            return attempt.addingTimeInterval(delay)
        }
        if let success = sensible(lastSuccess, now: now) { return success.addingTimeInterval(2 * 3_600) }
        return now
    }

    func isDue(now: Date = Date()) -> Bool { nextCheckDate(now: now) <= now }

    private func sensible(_ date: Date?, now: Date) -> Date? {
        guard let date, date <= now.addingTimeInterval(5 * 60) else { return nil }
        return date
    }
}

struct TiboResetStore {
    let defaults: UserDefaults
    var key = "tiboResetState.v1"

    func load() -> TiboResetState {
        guard let data = defaults.data(forKey: key), data.count <= 128 * 1024,
              let state = try? JSONDecoder().decode(TiboResetState.self, from: data) else { return TiboResetState() }
        return state
    }

    func save(_ state: TiboResetState) {
        guard let data = try? JSONEncoder().encode(state), data.count <= 128 * 1024 else { return }
        defaults.set(data, forKey: key)
    }
}

final class TiboResetClient {
    let trustedNitterHosts: Set<String>
    private let configuration: URLSessionConfiguration
    private let callbackQueue: DispatchQueue

    init(trustedNitterHosts: Set<String> = [], configuration: URLSessionConfiguration? = nil, callbackQueue: DispatchQueue = .main) {
        self.trustedNitterHosts = Set(trustedNitterHosts.map { $0.lowercased() })
        self.configuration = configuration ?? .ephemeral
        self.callbackQueue = callbackQueue
    }

    @discardableResult
    func fetch(sources: [URL], completion: @escaping (Result<TiboResetFetchResult, TiboResetError>) -> Void) -> TiboResetRequest {
        TiboResetRequest(sources: sources, trustedNitterHosts: trustedNitterHosts, configuration: configuration, callbackQueue: callbackQueue, completion: completion)
    }
}

/// Retain this handle while checking. Cancellation suppresses its completion callback.
final class TiboResetRequest: NSObject, URLSessionDataDelegate {
    private let lock = NSLock()
    private let sources: [URL]
    private let trustedNitterHosts: Set<String>
    private let callbackQueue: DispatchQueue
    private var completion: ((Result<TiboResetFetchResult, TiboResetError>) -> Void)?
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var sourceIndex = 0
    private var currentSource: URL?
    private var buffer = Data()
    private var responseError: TiboResetError?
    private var lastError = TiboResetError.noSources
    private var finished = false
    private var cancelled = false

    fileprivate init(sources: [URL], trustedNitterHosts: Set<String>, configuration: URLSessionConfiguration, callbackQueue: DispatchQueue, completion: @escaping (Result<TiboResetFetchResult, TiboResetError>) -> Void) {
        self.sources = Array(sources.prefix(4))
        self.trustedNitterHosts = trustedNitterHosts
        self.callbackQueue = callbackQueue
        self.completion = completion
        super.init()
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.httpMaximumConnectionsPerHost = 1
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        startNext()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        finished = true
        completion = nil
        let task = self.task
        let session = self.session
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
    }

    private func startNext() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        while sourceIndex < sources.count, !TiboResetFeed.isSafeSource(sources[sourceIndex]) {
            lastError = .invalidSource
            sourceIndex += 1
        }
        guard sourceIndex < sources.count else {
            let error = lastError
            lock.unlock()
            finish(.failure(error))
            return
        }
        let source = sources[sourceIndex]
        sourceIndex += 1
        currentSource = source
        buffer = Data()
        responseError = nil
        var request = URLRequest(url: source)
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
        request.setValue("CodexBattery/1.0 (public RSS check)", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request)
        self.task = task
        lock.unlock()
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { completionHandler(.cancel); return }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { responseError = .httpError }
        else if !(response is HTTPURLResponse) { responseError = .httpError }
        else if response.expectedContentLength > TiboResetFeed.maximumBytes { responseError = .tooLarge }
        else if response.mimeType?.lowercased() == "text/html" { responseError = .invalidFeed }
        completionHandler(responseError == nil ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        if buffer.count + data.count > TiboResetFeed.maximumBytes {
            responseError = .tooLarge
            lock.unlock()
            dataTask.cancel()
            return
        }
        buffer.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // A feed may redirect its own path; cross-host redirects need an explicit configured source.
        lock.lock()
        let allowed = !finished && request.url.map { TiboResetFeed.isSafeSource($0) && $0.host?.lowercased() == currentSource?.host?.lowercased() } == true
        if !allowed { responseError = .invalidSource }
        lock.unlock()
        completionHandler(allowed ? request : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard !finished, let source = currentSource else { lock.unlock(); return }
        let data = buffer
        let failure = responseError ?? (error == nil ? nil : .networkError)
        lock.unlock()
        if let failure {
            failSource(failure)
            return
        }
        do {
            let result = try TiboResetFeed.parse(data: data, sourceURL: source, trustedNitterHosts: trustedNitterHosts)
            finish(.success(result))
        } catch {
            failSource((error as? TiboResetError) ?? .invalidFeed)
        }
    }

    private func failSource(_ error: TiboResetError) {
        lock.lock()
        lastError = error
        lock.unlock()
        startNext()
    }

    private func finish(_ result: Result<TiboResetFetchResult, TiboResetError>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let session = self.session
        lock.unlock()
        session?.finishTasksAndInvalidate()
        callbackQueue.async { [self] in
            lock.lock()
            let callback = cancelled ? nil : completion
            completion = nil
            lock.unlock()
            callback?(result)
        }
    }
}
