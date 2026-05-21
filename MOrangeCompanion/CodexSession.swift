import Foundation

struct CodexConfigSnapshot {
    let model: String
    let reasoningEffort: String
    let configURL: URL
}

struct CodexThreadSummary {
    let id: String
    let title: String
    let preview: String
    let updatedAtMS: Int64
    let model: String
    let reasoningEffort: String
    let cwd: String
    let rolloutPath: String
}

final class CodexConfig {
    static let shared = CodexConfig()

    let configURL: URL

    private init() {
        configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("config.toml")
    }

    var snapshot: CodexConfigSnapshot {
        let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        return CodexConfigSnapshot(
            model: value(for: "model", in: text) ?? "gpt-5.5",
            reasoningEffort: value(for: "model_reasoning_effort", in: text) ?? "medium",
            configURL: configURL
        )
    }

    func update(model: String? = nil, reasoningEffort: String? = nil) throws {
        var text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = """
            model = "\(model ?? "gpt-5.5")"
            model_reasoning_effort = "\(reasoningEffort ?? "medium")"

            """
        } else {
            if let model {
                text = upsert(key: "model", value: model, in: text)
            }
            if let reasoningEffort {
                text = upsert(key: "model_reasoning_effort", value: reasoningEffort, in: text)
            }
        }
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func value(for key: String, in text: String) -> String? {
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("\(key) =") else { continue }
            let rawValue = line
                .dropFirst("\(key) =".count)
                .trimmingCharacters(in: .whitespaces)
            return rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    private func upsert(key: String, value: String, in text: String) -> String {
        var didReplace = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { raw -> String in
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key) =") else { return line }
            didReplace = true
            return "\(key) = \"\(value)\""
        }
        if didReplace {
            return lines.joined(separator: "\n")
        }
        return "\(key) = \"\(value)\"\n" + text
    }
}

final class CodexConversationStore {
    static let shared = CodexConversationStore()

    private let codexHome: URL
    private let stateDBURL: URL

    private init() {
        codexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        stateDBURL = codexHome.appendingPathComponent("state_5.sqlite")
    }

    func recentThreads(limit: Int = 12) -> [CodexThreadSummary] {
        let sql = """
        select id, title, preview, coalesce(updated_at_ms, updated_at * 1000), coalesce(model,''), coalesce(reasoning_effort,''), cwd, rollout_path
        from threads
        where archived = 0
        order by coalesce(updated_at_ms, updated_at * 1000) desc
        limit \(limit);
        """
        return runSQLite(sql).compactMap(parseThreadSummary)
    }

    func thread(id: String) -> CodexThreadSummary? {
        queryThread(id: id, includeArchived: false)
    }

    @discardableResult
    func syncForDesktop(threadID: String) -> CodexThreadSummary? {
        markAsMOrangeThread(threadID: threadID)
    }

    @discardableResult
    func markAsMOrangeThread(threadID: String) -> CodexThreadSummary? {
        let id = sql(threadID)
        let update = """
        update threads
        set source = case when source = 'exec' then 'vscode' else source end,
            thread_source = case when coalesce(thread_source, '') = '' then 'user' else thread_source end,
            has_user_event = 1,
            title = case
                when title like '小橘子：%' then title
                when coalesce(title, '') = '' then '小橘子：未命名对话'
                else '小橘子：' || title
            end,
            preview = case when coalesce(preview, '') = '' then first_user_message else preview end
        where id = '\(id)' and archived = 0
          and (source = 'exec' or title like '小橘子：%');
        """
        _ = runSQLite(update)
        guard let thread = queryThread(id: threadID, includeArchived: false) else { return nil }
        guard thread.title.hasPrefix("小橘子：") else { return thread }
        updateSessionIndex(with: thread)
        updateDesktopGlobalState(with: thread)
        return thread
    }

    @discardableResult
    func archiveThread(id threadID: String) -> Bool {
        let id = sql(threadID)
        let update = """
        update threads
        set archived = 1,
            archived_at = cast(strftime('%s','now') as integer),
            updated_at = cast(strftime('%s','now') as integer),
            updated_at_ms = cast(strftime('%s','now') as integer) * 1000
        where id = '\(id)';
        select changes();
        """
        let changed = runSQLite(update).last.flatMap(Int.init) ?? 0
        if changed > 0 {
            removeSessionIndexEntry(id: threadID)
        }
        return changed > 0
    }

    func loadMessages(for thread: CodexThreadSummary) -> [AgentMessage] {
        let url = URL(fileURLWithPath: thread.rolloutPath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var eventMessages: [AgentMessage] = []
        var fallbackMessages: [AgentMessage] = []

        for line in text.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = json["payload"] as? [String: Any] else { continue }

            if json["type"] as? String == "event_msg",
               let payloadType = payload["type"] as? String,
               let message = payload["message"] as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if payloadType == "user_message" {
                    eventMessages.append(AgentMessage(role: .user, text: message))
                } else if payloadType == "agent_message" {
                    eventMessages.append(AgentMessage(role: .assistant, text: message))
                }
            }

            if json["type"] as? String == "response_item",
               payload["type"] as? String == "message",
               let role = payload["role"] as? String,
               let content = payload["content"] as? [[String: Any]] {
                let text = content.compactMap { item -> String? in
                    if let text = item["text"] as? String { return text }
                    if let text = item["output_text"] as? String { return text }
                    return nil
                }.joined(separator: "\n")
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty,
                      !clean.hasPrefix("<permissions instructions>"),
                      !clean.hasPrefix("# AGENTS.md instructions"),
                      !clean.hasPrefix("<environment_context>") else { continue }
                if role == "user" {
                    fallbackMessages.append(AgentMessage(role: .user, text: clean))
                } else if role == "assistant" {
                    fallbackMessages.append(AgentMessage(role: .assistant, text: clean))
                }
            }
        }

        return eventMessages.isEmpty ? fallbackMessages : eventMessages
    }

    private func queryThread(id threadID: String, includeArchived: Bool) -> CodexThreadSummary? {
        let archivedClause = includeArchived ? "" : "and archived = 0"
        let sql = """
        select id, title, preview, coalesce(updated_at_ms, updated_at * 1000), coalesce(model,''), coalesce(reasoning_effort,''), cwd, rollout_path
        from threads
        where id = '\(sql(threadID))' \(archivedClause)
        limit 1;
        """
        return runSQLite(sql).compactMap(parseThreadSummary).first
    }

    private func parseThreadSummary(_ line: String) -> CodexThreadSummary? {
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 8 else { return nil }
        return CodexThreadSummary(
            id: parts[0],
            title: parts[1].isEmpty ? "未命名对话" : parts[1],
            preview: parts[2],
            updatedAtMS: Int64(parts[3]) ?? 0,
            model: parts[4],
            reasoningEffort: parts[5],
            cwd: parts[6],
            rolloutPath: parts[7]
        )
    }

    private func runSQLite(_ sql: String) -> [String] {
        guard FileManager.default.fileExists(atPath: stateDBURL.path) else { return [] }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = ["-noheader", "-separator", "\t", stateDBURL.path, "pragma busy_timeout=2000;\n\(sql)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func updateSessionIndex(with thread: CodexThreadSummary) {
        let url = codexHome.appendingPathComponent("session_index.jsonl")
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { line in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = json["id"] as? String else { return true }
                return id != thread.id
            }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let updated = thread.updatedAtMS > 0 ? Date(timeIntervalSince1970: TimeInterval(thread.updatedAtMS) / 1000.0) : Date()
        let entry: [String: Any] = [
            "id": thread.id,
            "thread_name": thread.title,
            "updated_at": formatter.string(from: updated)
        ]
        if let data = try? JSONSerialization.data(withJSONObject: entry, options: []),
           let line = String(data: data, encoding: .utf8) {
            lines.append(line)
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func updateDesktopGlobalState(with thread: CodexThreadSummary) {
        let url = codexHome.appendingPathComponent(".codex-global-state.json")
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = json
        }

        var projectless = root["projectless-thread-ids"] as? [String] ?? []
        if !projectless.contains(thread.id) {
            projectless.append(thread.id)
        }
        root["projectless-thread-ids"] = projectless

        var hints = root["thread-workspace-root-hints"] as? [String: String] ?? [:]
        hints[thread.id] = HermesBridge.shared.workspaceURL.path
        root["thread-workspace-root-hints"] = hints

        if let data = try? JSONSerialization.data(withJSONObject: root, options: []) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func removeSessionIndexEntry(id threadID: String) {
        let url = codexHome.appendingPathComponent("session_index.jsonl")
        let lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { line in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = json["id"] as? String else { return true }
                return id != threadID
            }
        try? (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).write(to: url, atomically: true, encoding: .utf8)
    }

    private func sql(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}

class CodexSession: AgentSession {
    private enum DefaultsKeys {
        static let binaryPath = "codexBinaryPath"
        static let workingDirectory = "codexWorkingDirectory"
        static let model = "codexModel"
    }

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var lineBuffer = ""
    private(set) var threadID: String?
    private(set) var isRunning = false
    private(set) var isBusy = false
    private var isFirstTurn = true
    private var didShowFriendlyFailure = false
    private static var binaryPath: String?

    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onToolUse: ((String, [String: Any]) -> Void)?
    var onToolResult: ((String, Bool) -> Void)?
    var onSessionReady: (() -> Void)?
    var onTurnComplete: (() -> Void)?
    var onProcessExit: (() -> Void)?

    var history: [AgentMessage] = []

    var currentThreadID: String? { threadID }

    // MARK: - Lifecycle

    func start() {
        if Self.binaryPath != nil {
            isRunning = true
            onSessionReady?()
            return
        }

        if let configuredPath = configuredBinaryPath() {
            Self.binaryPath = configuredPath
            isRunning = true
            onSessionReady?()
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        ShellEnvironment.findBinary(name: "codex", fallbackPaths: [
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex"
        ]) { [weak self] path in
            guard let self = self, let binaryPath = path else {
                let msg = "Codex CLI not found.\n\n\(AgentProvider.codex.installInstructions)"
                self?.onError?(msg)
                self?.history.append(AgentMessage(role: .error, text: msg))
                return
            }
            Self.binaryPath = binaryPath
            self.isRunning = true
            self.onSessionReady?()
        }
    }

    func send(message: String) {
        send(message: message, attachments: [])
    }

    func send(message: String, attachments: [AgentAttachment]) {
        guard isRunning, let binaryPath = Self.binaryPath else { return }
        let normalizedMessage = messageWithAttachmentReferences(message, attachments: attachments)
        let userMessage = displayMessage(message, attachments: attachments)
        isBusy = true
        didShowFriendlyFailure = false
        history.append(AgentMessage(role: .user, text: userMessage))
        lineBuffer = ""

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)

        if isFirstTurn || threadID == nil {
            proc.arguments = baseArguments(message: normalizedMessage, attachments: attachments)
        } else {
            proc.arguments = resumeArguments(for: threadID!, message: normalizedMessage, attachments: attachments)
        }

        proc.currentDirectoryURL = resolvedWorkingDirectoryURL()
        proc.environment = ShellEnvironment.processEnvironment(extraPaths: [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".npm-global/bin").path
        ])

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.process = nil
                // Flush remaining buffer
                if !self.lineBuffer.isEmpty {
                    self.parseLine(self.lineBuffer)
                    self.lineBuffer = ""
                }
                if self.isBusy {
                    self.isBusy = false
                    self.onTurnComplete?()
                }
            }
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.processOutput(text)
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.handleDiagnosticOutput(text)
                }
            }
        }

        do {
            try proc.run()
            process = proc
            outputPipe = outPipe
            errorPipe = errPipe
            isFirstTurn = false
        } catch {
            isBusy = false
            let msg = "Failed to launch Codex CLI: \(error.localizedDescription)"
            onError?(msg)
            history.append(AgentMessage(role: .error, text: msg))
        }
    }

    func terminate() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        threadID = nil
        isFirstTurn = true
        isRunning = false
        isBusy = false
    }

    func attach(threadID: String, history: [AgentMessage]) {
        self.threadID = threadID
        self.history = history
        isFirstTurn = false
    }

    // MARK: - JSONL Parsing

    private func processOutput(_ text: String) {
        lineBuffer += text
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])
            if !line.isEmpty {
                parseLine(line)
            }
        }
    }

    private func parseLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let type = json["type"] as? String ?? ""

        switch type {
        case "thread.started":
            if let threadID = json["thread_id"] as? String, !threadID.isEmpty {
                self.threadID = threadID
            }

        case "item.started":
            if let item = json["item"] as? [String: Any] {
                let itemType = item["type"] as? String ?? ""
                if itemType == "command_execution" {
                    let command = item["command"] as? String ?? ""
                    print("Codex tool started: \(command)")
                }
            }

        case "item.completed":
            if let item = json["item"] as? [String: Any] {
                let itemType = item["type"] as? String ?? ""
                switch itemType {
                case "agent_message":
                    let text = item["text"] as? String ?? ""
                    if !text.isEmpty {
                        history.append(AgentMessage(role: .assistant, text: text))
                        onText?(text)
                    }
                case "command_execution":
                    break
                case "file_change":
                    break
                default:
                    break
                }
            }

        case "turn.completed":
            isBusy = false
            onTurnComplete?()

        case "turn.failed":
            isBusy = false
            let msg = json["message"] as? String ?? "Turn failed"
            showFriendlyFailureIfNeeded(for: msg)
            onTurnComplete?()

        case "error":
            let msg = json["message"] as? String ?? json["error"] as? String ?? "Unknown error"
            showFriendlyFailureIfNeeded(for: msg)

        default:
            break
        }
    }

    private func configuredBinaryPath() -> String? {
        if let envPath = ProcessInfo.processInfo.environment["LIL_AGENTS_CODEX_PATH"],
           FileManager.default.isExecutableFile(atPath: envPath) {
            return envPath
        }

        if let defaultsPath = UserDefaults.standard.string(forKey: DefaultsKeys.binaryPath),
           FileManager.default.isExecutableFile(atPath: defaultsPath) {
            return defaultsPath
        }

        return nil
    }

    private func resolvedWorkingDirectoryURL() -> URL {
        if let envPath = ProcessInfo.processInfo.environment["LIL_AGENTS_CODEX_CWD"],
           FileManager.default.fileExists(atPath: envPath) {
            return URL(fileURLWithPath: envPath, isDirectory: true)
        }

        if let defaultsPath = UserDefaults.standard.string(forKey: DefaultsKeys.workingDirectory),
           FileManager.default.fileExists(atPath: defaultsPath) {
            return URL(fileURLWithPath: defaultsPath, isDirectory: true)
        }

        if FileManager.default.fileExists(atPath: HermesBridge.shared.workspaceURL.path) {
            return HermesBridge.shared.workspaceURL
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }

    private func handleDiagnosticOutput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        print("Codex diagnostic: \(trimmed)")
    }

    private func showFriendlyFailureIfNeeded(for message: String) {
        guard !didShowFriendlyFailure else { return }
        didShowFriendlyFailure = true
        let lower = message.lowercased()
        let friendly: String
        if lower.contains("requires a newer version of codex") {
            friendly = "小橘子需要你再发一次，我已经避开了不兼容的模型设置。"
        } else {
            friendly = "小橘子这次没有成功，但后台日志我不会再显示在聊天框里。你可以再发一次。"
        }
        onError?(friendly)
        history.append(AgentMessage(role: .error, text: friendly))
    }

    private func baseArguments(message: String, attachments: [AgentAttachment]) -> [String] {
        var args = ["exec", "--json", "--full-auto", "--skip-git-repo-check"]
        appendImageArguments(to: &args, attachments: attachments)
        args.append(message)
        return args
    }

    private func resumeArguments(for threadID: String, message: String, attachments: [AgentAttachment]) -> [String] {
        var args = ["exec", "resume", "--json", "--full-auto", "--skip-git-repo-check"]
        appendImageArguments(to: &args, attachments: attachments)
        args.append(threadID)
        args.append(message)
        return args
    }

    private func appendImageArguments(to args: inout [String], attachments: [AgentAttachment]) {
        for image in attachments where image.kind == .image {
            args.append(contentsOf: ["--image", image.url.path])
        }
    }

    private func messageWithAttachmentReferences(_ message: String, attachments: [AgentAttachment]) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = trimmed.isEmpty ? defaultPrompt(for: attachments) : trimmed
        let files = attachments.filter { $0.kind == .file }
        if !files.isEmpty {
            result += "\n\n附加本地文件路径，请按需要读取：\n"
            result += files.map { "- \($0.url.path)" }.joined(separator: "\n")
        }
        return result
    }

    private func displayMessage(_ message: String, attachments: [AgentAttachment]) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = trimmed.isEmpty ? defaultPrompt(for: attachments) : trimmed
        if !attachments.isEmpty {
            let summary = attachments.map { attachment in
                let prefix = attachment.kind == .image ? "图片" : "文件"
                return "\(prefix): \(attachment.displayName)"
            }.joined(separator: "；")
            result += "\n\n附件：\(summary)"
        }
        return result
    }

    private func defaultPrompt(for attachments: [AgentAttachment]) -> String {
        let imageCount = attachments.filter { $0.kind == .image }.count
        let fileCount = attachments.filter { $0.kind == .file }.count
        if imageCount > 0 && fileCount > 0 { return "请分析这些图片和文件附件。" }
        if imageCount > 1 { return "请分析这些图片。" }
        if imageCount == 1 { return "请分析这张图片。" }
        if fileCount > 0 { return "请读取并分析这些文件附件。" }
        return "请继续。"
    }
}
