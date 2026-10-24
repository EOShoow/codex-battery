import AppKit
import Foundation

/// Public announcements keep separate state and reuse account-quota refresh opportunities.
final class TiboResetMenuController: NSObject {
    static let enabledKey = "tiboResetCheckEnabled"
    static let feedURLKey = "tiboResetFeedURL"
    static let defaultFeedURL = URL(string: "https://nitter.kareem.one/thsottiaux/rss")!

    let item = NSMenuItem(title: "Tibo", action: nil, keyEquivalent: "")
    private let defaults: UserDefaults
    private let useChinese: Bool
    private let store: TiboResetStore
    private let client: TiboResetClient?
    private var state: TiboResetState
    private var request: TiboResetRequest?
    private var generation = 0
    private var isChecking = false

    init(defaults: UserDefaults = .standard, useChinese: Bool? = nil, client: TiboResetClient? = nil) {
        self.defaults = defaults
        self.useChinese = useChinese ?? (Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false)
        self.client = client
        let store = TiboResetStore(defaults: defaults)
        self.store = store
        self.state = store.load()
        super.init()
        rebuildMenu()
    }

    deinit {
        request?.cancel()
    }

    private var enabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    private var feedURL: URL {
        if let raw = defaults.string(forKey: Self.feedURLKey), let url = Self.validFeedURL(raw) {
            return url
        }
        return Self.defaultFeedURL
    }

    static func validFeedURL(_ raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 2048,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return url
    }

    private func t(_ zh: String, _ en: String) -> String { useChinese ? zh : en }

    /// Called at the start of an existing quota refresh, independent of its eventual result.
    func quotaRefreshDidStart() {
        checkIfDue()
    }

    func menuWillOpen() {
        rebuildMenu()
    }

    private func checkIfDue() {
        guard enabled, !isChecking, state.isDue(now: Date()) else { return }
        performCheck()
    }

    @objc private func checkNow() {
        guard enabled, !isChecking else { return }
        if let last = state.lastAttempt, Date().timeIntervalSince(last) >= 0,
           Date().timeIntervalSince(last) < 60 { return }
        performCheck()
    }

    private func performCheck() {
        guard enabled, !isChecking else { return }
        isChecking = true
        state.lastAttempt = Date()
        store.save(state)
        generation += 1
        let currentGeneration = generation
        rebuildMenu()
        let source = feedURL
        let client = self.client ?? TiboResetClient(trustedNitterHosts: Set([source.host].compactMap { $0 }))
        request = client.fetch(sources: [source]) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.enabled, self.generation == currentGeneration else { return }
                self.request = nil
                self.isChecking = false
                switch result {
                case .success(let feed):
                    // New matches are intentionally in-menu only; never alter quota or credits.
                    _ = self.state.recordSuccess(feed)
                case .failure(let error):
                    self.state.recordFailure(error, now: Date())
                }
                self.store.save(self.state)
                self.rebuildMenu()
            }
        }
    }

    private func cancelCheck() {
        generation += 1
        request?.cancel()
        request = nil
        isChecking = false
    }

    @objc private func toggleEnabled() {
        cancelCheck()
        defaults.set(!enabled, forKey: Self.enabledKey)
        rebuildMenu()
        checkIfDue()
    }

    @objc private func configureFeed() {
        let alert = NSAlert()
        alert.messageText = t("Tibo RSS 来源", "Tibo RSS source")
        alert.informativeText = t(
            "填写 @thsottiaux 的 HTTPS RSS 地址。只读取公开帖子；第三方来源可能延迟或失效。",
            "Enter an HTTPS RSS URL for @thsottiaux. Only public posts are read; third-party feeds may lag or fail."
        )
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        field.stringValue = feedURL.absoluteString
        alert.accessoryView = field
        alert.addButton(withTitle: t("保存", "Save"))
        alert.addButton(withTitle: t("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = Self.validFeedURL(field.stringValue) else {
            let invalid = NSAlert()
            invalid.messageText = t("请输入有效的 HTTPS 地址", "Enter a valid HTTPS URL")
            invalid.informativeText = t("地址不能包含用户名、密码或 # 片段。", "The URL must not contain a username, password, or fragment.")
            invalid.runModal()
            return
        }
        guard url != feedURL else { return }
        replaceFeed(with: url)
    }

    @objc private func restoreDefaultFeed() { replaceFeed(with: nil) }

    private func replaceFeed(with url: URL?) {
        cancelCheck()
        if let url {
            defaults.set(url.absoluteString, forKey: Self.feedURLKey)
        } else {
            defaults.removeObject(forKey: Self.feedURLKey)
        }
        state = TiboResetState()
        store.save(state)
        rebuildMenu()
        checkIfDue()
    }

    @objc private func openAnnouncement() {
        guard let announcement = state.latestAnnouncement else { return }
        NSWorkspace.shared.open(announcement.url)
    }

    @objc private func openProfile() {
        NSWorkspace.shared.open(URL(string: "https://x.com/thsottiaux")!)
    }

    private func action(_ title: String, _ selector: Selector, enabled: Bool = true) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        entry.target = self
        entry.isEnabled = enabled
        return entry
    }

    private func detail(_ text: String) -> NSMenuItem {
        let entry = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = useChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        let sameYear = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
        formatter.dateFormat = useChinese
            ? (sameYear ? "M月d日 HH:mm" : "yyyy年M月d日 HH:mm")
            : (sameYear ? "MMM d HH:mm" : "MMM d, yyyy HH:mm")
        return formatter.string(from: date)
    }

    private func rebuildMenu() {
        let summary: String
        if !enabled {
            summary = t("未启用", "Off")
        } else if isChecking {
            summary = t("检查中…", "Checking…")
        } else if state.lastError != nil {
            summary = state.lastSuccess == nil
                ? t("检查失败 · 尚无结果", "Check failed · no saved result")
                : t("检查失败 · 保留上次结果", "Check failed · previous result kept")
        } else if let latestPost = state.lastFeedPostAt, Date().timeIntervalSince(latestPost) > 7 * 24 * 3600 {
            summary = t("来源内容较旧", "Feed content is old")
        } else if let announcement = state.latestAnnouncement {
            let label = announcement.kind == .planned ? t("reset 预告", "reset preview") : t("reset 提及", "reset mention")
            summary = "\(label) · \(format(announcement.publishedAt))"
        } else if state.lastSuccess != nil {
            summary = t("订阅内容未检到 reset 提及", "No reset mention in feed")
        } else {
            summary = t("尚未检查", "Not checked")
        }
        item.title = t("Tibo 公告：", "Tibo: ") + summary
        let submenu = NSMenu(title: t("Tibo 公告", "Tibo announcements"))
        submenu.autoenablesItems = false
        let toggle = action(t("省电联网检查（约每 2 小时）", "Low-power check (about every 2h)"), #selector(toggleEnabled))
        toggle.state = enabled ? .on : .off
        submenu.addItem(toggle)
        let justAttempted = state.lastAttempt.map { Date().timeIntervalSince($0) >= 0 && Date().timeIntervalSince($0) < 60 } ?? false
        submenu.addItem(action(t("立即检查", "Check now"), #selector(checkNow), enabled: enabled && !isChecking && !justAttempted))
        if let success = state.lastSuccess {
            submenu.addItem(detail(t("上次成功：", "Last success: ") + format(success)))
        }
        if let latestPost = state.lastFeedPostAt {
            submenu.addItem(detail(t("源中最新帖子：", "Newest post in feed: ") + format(latestPost)))
        }
        if let attempt = state.lastAttempt {
            submenu.addItem(detail(t("上次尝试：", "Last attempt: ") + format(attempt)))
        }
        if let error = state.lastError {
            let message: String
            switch error {
            case .networkError: message = t("网络不可用或请求超时", "Network unavailable or request timed out")
            case .httpError: message = t("来源拒绝请求或暂不可用", "Feed rejected the request or is unavailable")
            case .invalidFeed, .noOriginalEntries: message = t("来源未返回有效的 Tibo 订阅内容", "Feed did not return valid Tibo posts")
            case .tooLarge: message = t("订阅内容超出大小限制", "Feed exceeded the size limit")
            case .invalidSource, .noSources: message = t("RSS 来源地址无效", "Invalid RSS source URL")
            }
            submenu.addItem(detail(message))
        }
        if enabled, !isChecking {
            let now = Date()
            let dueAt = state.nextCheckDate(now: now)
            let dueText = dueAt <= now ? t("已到期", "Due now") : format(dueAt)
            submenu.addItem(detail(t("下次到期（随额度刷新）：", "Next due (with quota refresh): ") + dueText))
        }
        if let announcement = state.latestAnnouncement {
            submenu.addItem(.separator())
            let excerpt = NSMenuItem(title: String(announcement.text.prefix(90)), action: nil, keyEquivalent: "")
            excerpt.view = makeAnnouncementView(announcement.text)
            submenu.addItem(excerpt)
            submenu.addItem(action(t("查看原帖", "Open post"), #selector(openAnnouncement)))
        }
        submenu.addItem(.separator())
        submenu.addItem(detail(t("来源：", "Source: ") + (feedURL.host ?? "RSS")))
        submenu.addItem(action(t("更换 RSS 来源…", "Change RSS source…"), #selector(configureFeed)))
        if defaults.string(forKey: Self.feedURLKey) != nil {
            submenu.addItem(action(t("恢复默认来源", "Restore default source"), #selector(restoreDefaultFeed)))
        }
        submenu.addItem(action(t("打开 Tibo 主页", "Open Tibo profile"), #selector(openProfile)))
        submenu.addItem(detail(t("公告仅供参考，到账以账号额度为准", "Announcements do not confirm account credits")))
        item.submenu = submenu
    }

    // Uses native wrapping text so an English post cannot stretch the menu across the screen.
    func makeAnnouncementView(_ text: String) -> NSView {
        let excerpt = String(text.prefix(600))
        let font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        let field = NSTextField(labelWithString: excerpt)
        field.font = font
        field.textColor = .labelColor
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 10
        let measured = (excerpt as NSString).boundingRect(
            with: NSSize(width: 364, height: 200),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]
        )
        let height = min(200, max(24, ceil(measured.height) + 4))
        field.frame = NSRect(x: 16, y: 8, width: 368, height: height)
        field.autoresizingMask = []
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: height + 16))
        view.toolTip = text
        view.addSubview(field)
        return view
    }
}
