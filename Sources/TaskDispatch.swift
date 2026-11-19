import Foundation

struct TaskRouteDecision {
    let provider: QuotaProvider?
    let reason: String
}

enum TaskRouter {
    static func choose(codex: ProviderQuotaSnapshot?, claude: ProviderQuotaSnapshot?,
                       codexReliable: Bool, claudeReliable: Bool, requested: QuotaProvider?,
                       lastProvider: QuotaProvider?, now: Date = Date(), chinese: Bool) -> TaskRouteDecision {
        func ready(_ snapshot: ProviderQuotaSnapshot?, reliable: Bool, provider: QuotaProvider) -> Bool {
            guard reliable, let snapshot, snapshot.isFresh(at: now), let week = snapshot.week,
                  week.isCurrent(at: now), week.remaining > 10 else { return false }
            if let five = snapshot.fiveHour, !five.isCurrent(at: now) || five.remaining <= 10 { return false }
            if provider == .claude, snapshot.hasModelLimitConcern || snapshot.modelWindows.values.contains(where: { $0.needsAttention(at: now) }) { return false }
            return true
        }
        if let requested {
            let usable = requested == .codex ? ready(codex, reliable: codexReliable, provider: .codex)
                : ready(claude, reliable: claudeReliable, provider: .claude)
            return TaskRouteDecision(provider: usable ? requested : nil, reason: usable
                ? (chinese ? "按你的选择使用 \(requested.title)" : "Using your choice: \(requested.title)")
                : (chinese ? "所选工具额度不足或待更新，请先刷新。" : "Selected quota is low or needs refreshing."))
        }
        let advice = QuotaBalanceAdvice.make(codex: codex, claude: claude, codexReliable: codexReliable,
                                             claudeReliable: claudeReliable, now: now, chinese: chinese)
        guard advice.canDispatch else { return TaskRouteDecision(provider: nil, reason: advice.title) }
        let preferred = advice.preferred ?? (lastProvider == .codex ? .claude : .codex)
        guard preferred == .codex ? ready(codex, reliable: codexReliable, provider: .codex)
                : ready(claude, reliable: claudeReliable, provider: .claude) else {
            return TaskRouteDecision(provider: nil, reason: chinese ? "请刷新额度后再提交" : "Refresh quota before submitting")
        }
        return TaskRouteDecision(provider: preferred, reason: advice.preferred != nil ? advice.title
            : (chinese ? "余量接近，轮换使用 \(preferred.title)" : "Similar headroom; alternate to \(preferred.title)"))
    }
}

enum TaskExecutableResolver {
    static func resolve(_ provider: QuotaProvider, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let fm = FileManager.default
        var paths: [URL]
        if provider == .codex {
            paths = ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                     "/Applications/Codex.app/Contents/Resources/codex", "/Applications/ChatGPT.app/Contents/Resources/codex"]
                .map { URL(fileURLWithPath: $0) }
        } else {
            paths = [home.appendingPathComponent(".local/bin/claude"), URL(fileURLWithPath: "/opt/homebrew/bin/claude")]
            let root = home.appendingPathComponent("Library/Application Support/Claude/claude-code")
            let versions = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for version in versions.sorted(by: { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }) {
                for folder in ((try? fm.contentsOfDirectory(at: version, includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.path < $1.path }) {
                    paths.append(folder.appendingPathComponent("claude.app/Contents/MacOS/claude"))
                }
            }
        }
        return paths.first { fm.isExecutableFile(atPath: $0.path) }
    }
}

struct TaskLaunchSpec {
    let provider: QuotaProvider
    let executable: URL
    let directory: URL
    let prompt: String
    let allowEdits: Bool
    let jobDirectory: URL

    var arguments: [String] {
        if provider == .codex {
            return ["exec", "--ephemeral", "--json", "--color", "never", "--skip-git-repo-check",
                    "--sandbox", allowEdits ? "workspace-write" : "read-only", "-c", "approval_policy=\"never\"",
                    "-C", directory.path, "--output-last-message", jobDirectory.appendingPathComponent("result.txt").path, "-"]
        }
        let allowed = allowEdits ? "Read,Glob,Grep,Edit,Write" : "Read,Glob,Grep"
        return ["--print", "--output-format", "json", "--no-session-persistence", "--restricted",
                "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
                "--permission-mode", "dontAsk", "--tools", allowed, "--allowedTools", allowed,
                "--permission-prompts", "none", "--settings", "{\"disableAllHooks\":true}"]
    }

    var payload: [String: Any] {
        ["provider": provider.rawValue, "executable": executable.path, "arguments": arguments,
         "cwd": directory.path, "prompt": prompt, "job_dir": jobDirectory.path, "timeout_seconds": 900,
         "owner_pid": ProcessInfo.processInfo.processIdentifier]
    }
}

/// The supervisor owns the process group and kills it on cancellation, timeout or app death.
final class TaskExecution {
    private(set) var process: Process?
    private(set) var jobDirectory: URL?
    var onCompletion: ((String, String) -> Void)?
    var isRunning: Bool { process != nil }

    func start(_ spec: TaskLaunchSpec, supervisor: URL) throws {
        guard process == nil else { throw NSError(domain: "TaskExecution", code: 1, userInfo: [NSLocalizedDescriptionKey: "A task is already running"]) }
        let data = try JSONSerialization.data(withJSONObject: spec.payload)
        let task = Process()
        let input = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = [supervisor.path]
        task.standardInput = input
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] completed in
            let resultURL = spec.jobDirectory.appendingPathComponent("result.txt")
            let statusURL = spec.jobDirectory.appendingPathComponent("status.json")
            let statusData = (try? Data(contentsOf: statusURL)) ?? Data()
            let status = (try? JSONSerialization.jsonObject(with: statusData)) as? [String: Any]
            var result = ""
            if let file = try? FileHandle(forReadingFrom: resultURL) {
                result = String(data: (try? file.read(upToCount: 512 * 1024)) ?? Data(), encoding: .utf8) ?? ""
                try? file.close()
            }
            let state = status?["state"] as? String ?? "failed"
            let message = result.isEmpty ? (status?["message"] as? String ?? "Runner exited: \(completed.terminationStatus)") : result
            DispatchQueue.main.async {
                guard let self, self.process === completed else { return }
                self.process = nil
                self.onCompletion?(state, message)
            }
        }
        process = task
        jobDirectory = spec.jobDirectory
        do { try task.run() }
        catch { process = nil; throw error }
        DispatchQueue.global(qos: .utility).async {
            try? input.fileHandleForWriting.write(contentsOf: data)
            try? input.fileHandleForWriting.close()
        }
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        process.terminate()
    }
}
