import AppKit
import Foundation

final class TaskLauncherMenuController: NSObject, NSWindowDelegate {
    typealias Quotas = (codex: ProviderQuotaSnapshot?, claude: ProviderQuotaSnapshot?, codexReliable: Bool, claudeReliable: Bool)
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let quotas: () -> Quotas
    private let refresh: () -> Void
    private let defaults: UserDefaults
    private let chinese: Bool
    private let execution = TaskExecution()
    private var enabled = true
    private var window: NSWindow?
    private let pathField = NSTextField()
    private let providerField = NSPopUpButton()
    private let modeField = NSPopUpButton()
    private let promptField = NSTextView()
    private let outputField = NSTextView()
    private let routeField = NSTextField(labelWithString: "")
    private let stateField = NSTextField(labelWithString: "")
    private let startButton = NSButton()
    private let cancelButton = NSButton()
    private let resultButton = NSButton()
    private var lastJob: URL?

    init(defaults: UserDefaults = .standard, chinese: Bool? = nil,
         quotas: @escaping () -> Quotas, refresh: @escaping () -> Void) {
        self.defaults = defaults
        self.chinese = chinese ?? (Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false)
        self.quotas = quotas
        self.refresh = refresh
        super.init()
        item.title = t("新任务：自动分派…", "New task: automatic routing…")
        item.target = self
        item.action = #selector(show)
        execution.onCompletion = { [weak self] state, message in
            guard let self else { return }
            let names = ["completed": self.t("已完成", "Completed"), "failed": self.t("执行失败", "Failed"),
                         "cancelled": self.t("已取消", "Cancelled"), "timed_out": self.t("已达 15 分钟上限", "15-minute limit reached"),
                         "busy": self.t("已有任务运行，未重复分派", "Another task is running; not dispatched"),
                         "output_limit": self.t("输出过大，已停止", "Output limit reached")]
            self.stateField.stringValue = names[state] ?? state
            self.outputField.string = message
            self.setBusy(false)
        }
    }

    private func t(_ zh: String, _ en: String) -> String { chinese ? zh : en }

    func setEnabled(_ value: Bool) {
        enabled = value
        item.isHidden = !enabled && !execution.isRunning
        quotaDidChange()
    }

    @objc func show() {
        guard enabled || execution.isRunning else { return }
        if window == nil { buildWindow() }
        updateRoute()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = t("新任务 · Codex / Claude", "New task · Codex / Claude")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        guard let view = window.contentView else { return }
        func label(_ text: String, _ rect: NSRect, secondary: Bool = false) {
            let field = NSTextField(wrappingLabelWithString: text)
            field.frame = rect
            field.font = .systemFont(ofSize: 12)
            if secondary { field.textColor = .secondaryLabelColor }
            view.addSubview(field)
        }
        func button(_ button: NSButton, _ title: String, _ action: Selector, _ rect: NSRect) {
            button.title = title
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
            button.frame = rect
            view.addSubview(button)
        }
        label(t("工作目录", "Working folder"), NSRect(x: 20, y: 642, width: 120, height: 20))
        pathField.frame = NSRect(x: 20, y: 610, width: 540, height: 26)
        pathField.placeholderString = t("选择本机文件夹", "Choose a local folder")
        pathField.stringValue = defaults.string(forKey: "taskLastDirectory") ?? ""
        view.addSubview(pathField)
        button(NSButton(), t("选择…", "Choose…"), #selector(chooseFolder), NSRect(x: 568, y: 609, width: 92, height: 28))
        providerField.frame = NSRect(x: 20, y: 570, width: 235, height: 28)
        providerField.addItems(withTitles: [t("自动选择执行工具", "Choose provider automatically"), "Codex", "Claude Code"])
        providerField.target = self
        providerField.action = #selector(updateRoute)
        view.addSubview(providerField)
        modeField.frame = NSRect(x: 270, y: 570, width: 230, height: 28)
        modeField.addItems(withTitles: [t("只读分析", "Read-only analysis"), t("允许修改项目文件", "Allow project file edits")])
        view.addSubview(modeField)
        button(NSButton(), t("刷新额度", "Refresh quotas"), #selector(refreshQuotas), NSRect(x: 525, y: 569, width: 135, height: 28))
        routeField.frame = NSRect(x: 20, y: 538, width: 640, height: 24)
        routeField.font = .boldSystemFont(ofSize: 13)
        routeField.lineBreakMode = .byTruncatingTail
        view.addSubview(routeField)
        label(t("任务", "Task"), NSRect(x: 20, y: 509, width: 100, height: 22))
        promptField.isRichText = false
        promptField.font = .systemFont(ofSize: 13)
        addEditor(promptField, to: view, rect: NSRect(x: 20, y: 332, width: 640, height: 175))
        label(t("开始后向选定工具发送任务，使用其额度；每次仅启动 1 个会话，最多运行 15 分钟。失败或取消后不自动重试；已发生的文件修改会保留。",
                "Starting sends the task to the chosen provider and uses its quota: one session, up to 15 minutes. No automatic retry; any file edits remain after failure or cancellation."),
              NSRect(x: 20, y: 279, width: 640, height: 45), secondary: true)
        label(t("Claude 仅使用文件读取/编辑工具；需要运行构建或测试命令时请选择 Codex。结果保存在本机，不会接管已有对话。",
                "Claude uses file read/edit tools only. Choose Codex for build or test commands. Results stay local; existing chats are not taken over."),
              NSRect(x: 20, y: 235, width: 640, height: 40), secondary: true)
        button(startButton, t("开始任务（1 个会话）", "Start task (one session)"), #selector(start), NSRect(x: 20, y: 195, width: 220, height: 32))
        button(cancelButton, t("停止", "Stop"), #selector(cancel), NSRect(x: 250, y: 195, width: 90, height: 32))
        button(resultButton, t("打开结果目录", "Open results"), #selector(openResults), NSRect(x: 480, y: 195, width: 180, height: 32))
        stateField.frame = NSRect(x: 20, y: 164, width: 640, height: 24)
        stateField.stringValue = t("尚未提交", "Not submitted")
        view.addSubview(stateField)
        outputField.isEditable = false
        outputField.isRichText = false
        outputField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        addEditor(outputField, to: view, rect: NSRect(x: 20, y: 20, width: 640, height: 140))
        setBusy(false)
    }

    private func addEditor(_ editor: NSTextView, to view: NSView, rect: NSRect) {
        let scroll = NSScrollView(frame: rect)
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        editor.frame = NSRect(origin: .zero, size: rect.size)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        scroll.documentView = editor
        view.addSubview(scroll)
    }

    private func decision() -> TaskRouteDecision {
        guard enabled else {
            return TaskRouteDecision(provider: nil, reason: t("请启用 Claude 账户额度检查", "Enable Claude account quota checks"))
        }
        let values = quotas()
        let requested: QuotaProvider? = providerField.indexOfSelectedItem == 1 ? .codex
            : (providerField.indexOfSelectedItem == 2 ? .claude : nil)
        return TaskRouter.choose(codex: values.codex, claude: values.claude,
                                codexReliable: values.codexReliable, claudeReliable: values.claudeReliable,
                                requested: requested, lastProvider: defaults.string(forKey: "taskLastProvider").flatMap(QuotaProvider.init), chinese: chinese)
    }

    @objc private func updateRoute() {
        guard !execution.isRunning else { return }
        let route = decision()
        routeField.stringValue = route.reason
        routeField.toolTip = route.reason
        if !execution.isRunning { startButton.isEnabled = route.provider != nil }
    }

    @objc private func chooseFolder() {
        guard !execution.isRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { pathField.stringValue = url.path }
    }

    @objc private func refreshQuotas() {
        refresh()
        updateRoute()
        stateField.stringValue = t("已请求刷新；提交前会再次检查额度", "Refresh requested; quota is checked again before launch")
    }

    /// Called when either provider publishes a new snapshot; keeps an open task window current.
    func quotaDidChange() { if window != nil { updateRoute() } }

    @objc private func start() {
        guard !execution.isRunning else { return }
        let route = decision()
        guard let provider = route.provider else { updateRoute(); return }
        let prompt = promptField.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.utf8.count <= 128 * 1024 else {
            stateField.stringValue = t("请填写任务（最多 128 KB）", "Enter a task (up to 128 KB)"); return
        }
        let path = (pathField.stringValue as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            stateField.stringValue = t("请选择有效的本机工作目录", "Choose a valid local working folder"); return
        }
        guard let executable = TaskExecutableResolver.resolve(provider),
              let supervisor = Bundle.main.url(forResource: "task_runner", withExtension: "py") else {
            stateField.stringValue = t("未找到执行工具或启动器，请检查安装", "CLI or supervisor missing; check installation"); return
        }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexBattery/tasks")
        let job = folder.appendingPathComponent(UUID().uuidString)
        let directory = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let spec = TaskLaunchSpec(provider: provider, executable: executable, directory: directory,
                                  prompt: prompt, allowEdits: modeField.indexOfSelectedItem == 1, jobDirectory: job)
        do {
            try execution.start(spec, supervisor: supervisor)
            lastJob = job
            defaults.set(provider.rawValue, forKey: "taskLastProvider")
            defaults.set(directory.path, forKey: "taskLastDirectory")
            routeField.stringValue = "\(provider.title) · " + route.reason
            stateField.stringValue = t("正在运行 \(provider.title)…", "Running \(provider.title)…")
            outputField.string = t("结果完成后显示在这里；运行中可打开结果目录查看输出。", "Results appear here on completion. Open the results folder for output while running.")
            setBusy(true)
        } catch {
            stateField.stringValue = t("启动失败：", "Could not start: ") + error.localizedDescription
        }
    }

    private func setBusy(_ busy: Bool) {
        item.isHidden = !enabled && !busy
        startButton.isEnabled = !busy && decision().provider != nil
        cancelButton.isEnabled = busy
        resultButton.isEnabled = lastJob != nil
        providerField.isEnabled = !busy
        modeField.isEnabled = !busy
        pathField.isEditable = !busy
        promptField.isEditable = !busy
        item.title = busy ? t("查看运行中的任务…", "View running task…") : t("新任务：自动分派…", "New task: automatic routing…")
    }

    @objc private func cancel() {
        execution.cancel()
        stateField.stringValue = t("正在停止…", "Stopping…")
        cancelButton.isEnabled = false
    }
    @objc private func openResults() { if let lastJob { NSWorkspace.shared.open(lastJob) } }
    func terminate() { execution.cancel() }
}
