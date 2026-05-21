import Foundation
import Darwin

// MARK: - Provider

enum AgentProvider: String, CaseIterable {
    case hermes, claude, codex, copilot

    private static let defaultsKey = "selectedProvider"
    private static let defaultProvider: AgentProvider = .hermes

    static var current: AgentProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? defaultProvider.rawValue
            let stored = AgentProvider(rawValue: raw) ?? defaultProvider
            return stored == .hermes ? stored : defaultProvider
        }
        set {
            UserDefaults.standard.set(AgentProvider.hermes.rawValue, forKey: defaultsKey)
        }
    }

    var displayName: String {
        switch self {
        case .hermes: return "Hermes 小橘子"
        case .claude:  return "Claude"
        case .codex:   return "Codex"
        case .copilot: return "Copilot"
        }
    }

    var inputPlaceholder: String {
        switch self {
        case .hermes:
            return "主人，想聊天或工作都直接交给 Hermes 小橘子..."
        case .codex:
            return "主人，这里是 Codex 工作入口，代码、文件和自动化可以交给它..."
        default:
            return "Ask \(displayName)..."
        }
    }

    /// Returns provider name styled per theme format.
    func titleString(format: TitleFormat) -> String {
        switch format {
        case .uppercase:      return displayName.uppercased()
        case .lowercaseTilde: return "\(displayName.lowercased()) ~"
        case .capitalized:    return displayName
        }
    }

    var installInstructions: String {
        switch self {
        case .hermes:
            return "Hermes should be installed at:\n  ~/.local/bin/hermes\n\n小橘子桌宠会通过 Hermes Bridge 读取 Hermes 配置、灵魂档案、长期记忆和今日备忘录。"
        case .claude:
            return "To install, run this in Terminal:\n  curl -fsSL https://claude.ai/install.sh | sh\n\nOr download from https://claude.ai/download"
        case .codex:
            return "To install, run this in Terminal:\n  npm install -g @openai/codex"
        case .copilot:
            return "To install, run this in Terminal:\n  brew install copilot-cli\n\nOr: npm install -g @github/copilot-cli"
        }
    }

    func createSession() -> any AgentSession {
        switch self {
        case .hermes: return HermesSession()
        case .claude:  return ClaudeSession()
        case .codex:   return CodexSession()
        case .copilot: return CopilotSession()
        }
    }
}

// MARK: - Title Format

enum TitleFormat {
    case uppercase       // "CLAUDE"
    case lowercaseTilde  // "claude ~"
    case capitalized     // "Claude"
}

// MARK: - Message

struct AgentMessage: Codable {
    enum Role: String, Codable { case user, assistant, error, toolUse, toolResult }
    let role: Role
    let text: String
}

struct AgentAttachment: Equatable {
    enum Kind {
        case image
        case file
    }

    let kind: Kind
    let url: URL

    var displayName: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
}

struct InputSuggestion {
    let title: String
    let subtitle: String
    let replacement: String
}

enum HermesPermissionDecision: String {
    case allowOnce = "once"
    case allowSession = "session"
    case allowAlways = "always"
    case deny = "deny"

    var title: String {
        switch self {
        case .allowOnce: return "只允许这次"
        case .allowSession: return "允许"
        case .allowAlways: return "记住选择"
        case .deny: return "拒绝"
        }
    }

    var stdinToken: String {
        rawValue
    }
}

struct HermesPermissionRequest {
    let id: String
    let title: String
    let detail: String
    let command: String
    let rawText: String
    let allowPermanent: Bool
}

enum HermesGatewayInputKind {
    case clarify
    case sudo
    case secret
}

struct HermesGatewayInputRequest {
    let id: String
    let kind: HermesGatewayInputKind
    let title: String
    let prompt: String
    let choices: [String]
    let envVar: String
}

struct HermesVoiceStatus: Equatable {
    var enabled = false
    var recording = false
    var processing = false
    var speaking = false
    var ttsEnabled = false
    var available: Bool?
    var audioAvailable: Bool?
    var sttAvailable: Bool?
    var recordKey = "ctrl+b"
    var details = ""
}

struct HermesRuntimeModel: Equatable {
    let provider: String
    let model: String
}

// MARK: - Session Protocol

protocol AgentSession: AnyObject {
    var isRunning: Bool { get }
    var isBusy: Bool { get }
    var history: [AgentMessage] { get }

    var onText: ((String) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onToolUse: ((String, [String: Any]) -> Void)? { get set }
    var onToolResult: ((String, Bool) -> Void)? { get set }
    var onSessionReady: (() -> Void)? { get set }
    var onTurnComplete: (() -> Void)? { get set }
    var onProcessExit: (() -> Void)? { get set }

    func start()
    func send(message: String)
    func send(message: String, attachments: [AgentAttachment])
    func terminate()
}

extension AgentSession {
    func send(message: String, attachments: [AgentAttachment]) {
        send(message: message)
    }
}

// MARK: - Hermes Session

class HermesSession: AgentSession {
    private enum DefaultsKeys {
        static let binaryPath = "hermesBinaryPath"
        static let workingDirectory = "hermesWorkingDirectory"
        static let desktopSessionID = "hermesDesktopSessionID"
        static let effectiveModelPrefix = "hermesEffectiveModel."
        static let livePTYEnabled = "hermesLivePTYEnabled"
        static let tuiGatewayEnabled = "hermesTUIGatewayEnabled"
        static let pendingTranscriptPrefix = "hermesPendingTranscript."
        static let voiceTTSEnabled = "hermesVoiceTTSEnabled"
    }

    private struct GatewayPrompt {
        let normalizedMessage: String
        let userMessage: String
        let imageURLs: [URL]
        let launchTime: TimeInterval
    }

    private typealias GatewayResponseHandler = ([String: Any]) -> Void

    private var process: Process?
    private var quickProcess: Process?
    private var gatewayProcess: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var inputPipe: Pipe?
    private var gatewayInputPipe: Pipe?
    private var gatewayOutputPipe: Pipe?
    private var gatewayErrorPipe: Pipe?
    private var ptyMasterHandle: FileHandle?
    private var isLivePTYActive = false
    private var isGatewayActive = false
    private var isGatewayReady = false
    private var isGatewayStarting = false
    private var gatewaySessionID: String?
    private var gatewayRequestID = 0
    private var gatewayResponseHandlers: [Int: GatewayResponseHandler] = [:]
    private var gatewayQueuedPrompts: [GatewayPrompt] = []
    private var gatewayReadyCallbacks: [(String) -> Void] = []
    private var gatewayStdoutBuffer = ""
    private var gatewayStderrBuffer = ""
    private var gatewayTurnBuffer = ""
    private var gatewayLastUserMessage = ""
    private var gatewayTurnLaunchTime: TimeInterval = 0
    private var gatewayFallbackToken = 0
    private var isGatewayFallbackActive = false
    private var liveTurnBuffer = ""
    private var liveLastUserMessage = ""
    private var pendingPTYEcho: String?
    private var ptyIdleToken = 0
    private var lastMirrorSignature = ""
    private var lastMirrorAt = Date.distantPast
    private var pendingPermissionRequest: HermesPermissionRequest?
    private var pendingGatewayInputRequest: HermesGatewayInputRequest?
    private var lastPermissionSignature = ""
    private var approvalScanBuffer = ""
    private var effectiveModel: HermesRuntimeModel?
    private var modelScanBuffer = ""
    private var voiceStatus = HermesVoiceStatus()
    private var voiceSpeakingResetToken = 0
    private var voiceRecordingGraceUntil = Date.distantPast
    private var ignoreVoiceIdleUntil = Date.distantPast
    private(set) var isRunning = false
    private(set) var isBusy = false
    private static var binaryPath: String?

    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onToolUse: ((String, [String: Any]) -> Void)?
    var onToolResult: ((String, Bool) -> Void)?
    var onPermissionRequest: ((HermesPermissionRequest) -> Void)?
    var onGatewayInputRequest: ((HermesGatewayInputRequest) -> Void)?
    var onModelChanged: ((HermesRuntimeModel) -> Void)?
    var onVoiceStatus: ((HermesVoiceStatus) -> Void)?
    var onVoiceTranscript: ((String) -> Void)?
    var onSessionReady: (() -> Void)?
    var onTurnComplete: (() -> Void)?
    var onProcessExit: (() -> Void)?

    var history: [AgentMessage] = []

    init() {
        voiceStatus.ttsEnabled = UserDefaults.standard.bool(forKey: DefaultsKeys.voiceTTSEnabled)
    }

    static var desktopSessionID: String? {
        UserDefaults.standard.string(forKey: DefaultsKeys.desktopSessionID)
    }

    static func setDesktopSessionID(_ sessionID: String?) {
        let clean = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let clean, !clean.isEmpty {
            UserDefaults.standard.set(clean, forKey: DefaultsKeys.desktopSessionID)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKeys.desktopSessionID)
        }
    }

    private static func pendingTranscriptKey(for sessionID: String?) -> String {
        let clean = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return DefaultsKeys.pendingTranscriptPrefix + ((clean?.isEmpty == false) ? clean! : "current")
    }

    private static func loadPendingTranscript(for sessionID: String?) -> [AgentMessage] {
        guard let data = UserDefaults.standard.data(forKey: pendingTranscriptKey(for: sessionID)),
              let messages = try? JSONDecoder().decode([AgentMessage].self, from: data) else {
            return []
        }
        return messages
    }

    private static func savePendingTranscript(_ messages: [AgentMessage], for sessionID: String?) {
        guard !messages.isEmpty,
              let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: pendingTranscriptKey(for: sessionID))
    }

    private static func removePendingTranscript(for sessionID: String?) {
        UserDefaults.standard.removeObject(forKey: pendingTranscriptKey(for: sessionID))
    }

    private func persistPendingTranscript() {
        Self.savePendingTranscript(history, for: currentSessionID)
    }

    private func adoptPendingTranscript(for sessionID: String?) {
        let exact = Self.loadPendingTranscript(for: sessionID)
        let current = sessionID == nil ? [] : Self.loadPendingTranscript(for: nil)
        let best = [history, exact, current].max { $0.count < $1.count } ?? history
        if best.count > history.count {
            history = best
        }
        Self.savePendingTranscript(history, for: sessionID)
        if sessionID != nil {
            Self.removePendingTranscript(for: nil)
        }
    }

    var currentSessionID: String? {
        Self.desktopSessionID
    }

    var currentEffectiveModel: HermesRuntimeModel? {
        effectiveModel
            ?? Self.effectiveModel(for: currentSessionID)
            ?? Self.effectiveModel(for: nil)
    }

    static func effectiveModel(for sessionID: String?) -> HermesRuntimeModel? {
        guard let raw = UserDefaults.standard.string(forKey: effectiveModelDefaultsKey(for: sessionID)) else {
            return nil
        }
        let parts = raw.components(separatedBy: "|")
        guard parts.count >= 2 else { return nil }
        let provider = normalizedProvider(parts[0])
        let model = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return nil }
        return HermesRuntimeModel(provider: provider, model: model)
    }

    static func setEffectiveModel(_ model: HermesRuntimeModel?, for sessionID: String?) {
        let key = effectiveModelDefaultsKey(for: sessionID)
        if let model {
            let provider = normalizedProvider(model.provider)
            let cleanModel = model.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanModel.isEmpty else {
                UserDefaults.standard.removeObject(forKey: key)
                return
            }
            UserDefaults.standard.set("\(provider)|\(cleanModel)", forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func effectiveModelDefaultsKey(for sessionID: String?) -> String {
        let clean = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return DefaultsKeys.effectiveModelPrefix + ((clean?.isEmpty == false) ? clean! : "current")
    }

    private static func runtimeModel(from thread: HermesThreadSummary?) -> HermesRuntimeModel? {
        guard let thread else { return nil }
        let model = thread.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return nil }
        let provider = provider(for: model, hint: thread.provider, fallback: nil)
        return HermesRuntimeModel(provider: provider, model: model)
    }

    private static func runtimeModelFromConfig() -> HermesRuntimeModel {
        let config = HermesConfig.shared.snapshot
        return HermesRuntimeModel(
            provider: provider(for: config.model, hint: config.provider, fallback: nil),
            model: config.model
        )
    }

    private static func provider(for model: String, hint: String?, fallback: String?) -> String {
        let hinted = normalizedProvider(hint ?? "")
        if !hinted.isEmpty { return hinted }
        let lower = model.lowercased()
        if lower.contains("grok") { return "xai" }
        if lower.contains("deepseek") { return "deepseek" }
        if lower.contains("claude") { return "anthropic" }
        if lower.contains("gemini") { return "google" }
        if lower.hasPrefix("gpt") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") {
            return "openai"
        }
        let fallbackProvider = normalizedProvider(fallback ?? "")
        return fallbackProvider.isEmpty ? normalizedProvider(HermesConfig.shared.snapshot.provider) : fallbackProvider
    }

    private static func normalizedProvider(_ provider: String) -> String {
        let clean = provider
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        if clean == "x.ai" || clean == "x-ai" || clean == "xai" { return "xai" }
        if clean.contains("deepseek") { return "deepseek" }
        if clean.contains("anthropic") || clean.contains("claude") { return "anthropic" }
        if clean.contains("openai") { return "openai" }
        if clean.contains("google") || clean.contains("gemini") { return "google" }
        return clean
    }

    func start() {
        adoptPendingTranscript(for: currentSessionID)
        if Self.binaryPath != nil {
            isRunning = true
            launchLivePTYIfNeeded()
            onSessionReady?()
            return
        }

        if let configuredPath = configuredBinaryPath() {
            Self.binaryPath = configuredPath
            isRunning = true
            launchLivePTYIfNeeded()
            onSessionReady?()
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        ShellEnvironment.findBinary(name: "hermes", fallbackPaths: [
            "\(home)/.local/bin/hermes",
            "/opt/homebrew/bin/hermes",
            "/usr/local/bin/hermes"
        ]) { [weak self] path in
            guard let self = self else { return }
            guard let binaryPath = path else {
                let msg = "Hermes CLI not found.\n\n\(AgentProvider.hermes.installInstructions)"
                self.onError?(msg)
                self.history.append(AgentMessage(role: .error, text: msg))
                self.persistPendingTranscript()
                return
            }
            Self.binaryPath = binaryPath
            self.isRunning = true
            self.launchLivePTYIfNeeded()
            self.onSessionReady?()
        }
    }

    func send(message: String) {
        send(message: message, attachments: [])
    }

    func send(message: String, attachments: [AgentAttachment]) {
        guard isRunning else { return }
        if sendViaGatewayIfPossible(message: message, attachments: attachments) {
            return
        }
        if sendViaLivePTYIfPossible(message: message, attachments: attachments) {
            return
        }
        let normalizedMessage = messageWithAttachmentReferences(message, attachments: attachments)
        let userMessage = displayMessage(message, attachments: attachments)
        sendViaQuickProcess(normalizedMessage: normalizedMessage, userMessage: userMessage, attachments: attachments, recordUser: true)
    }

    private func sendViaQuickProcess(normalizedMessage: String, userMessage: String, attachments: [AgentAttachment], recordUser: Bool) {
        guard let binaryPath = Self.binaryPath else { return }
        effectiveModel = restoreEffectiveModel(for: currentSessionID)
        modelScanBuffer = ""
        approvalScanBuffer = ""
        lastPermissionSignature = ""
        if let requestedModel = runtimeModelFromSlashModelCommand(normalizedMessage) {
            updateEffectiveModel(requestedModel)
        }
        isBusy = true
        if recordUser {
            history.append(AgentMessage(role: .user, text: userMessage))
            persistPendingTranscript()
        }
        let launchTime = Date().timeIntervalSince1970

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = hermesArguments(for: normalizedMessage, attachments: attachments)
        proc.currentDirectoryURL = resolvedWorkingDirectoryURL()
        proc.environment = ShellEnvironment.processEnvironment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = inPipe

        var stdout = ""
        var stderr = ""
        emitMirrorToolUse("Hermes 接管中", [
            "状态": "读取上下文、记忆和工具配置",
            "会话": UserDefaults.standard.string(forKey: DefaultsKeys.desktopSessionID) ?? "新会话"
        ])
        if !attachments.isEmpty {
            emitMirrorToolUse("Hermes 收到附件", [
                "附件": attachmentSummary(attachments),
                "说明": "图片会走 Hermes --image；文件路径会交给 Hermes 工具读取"
            ])
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            stdout += text
            DispatchQueue.main.async {
                self?.mirrorHermesOutput(text, isDiagnostic: false)
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            stderr += text
            DispatchQueue.main.async {
                self?.mirrorHermesOutput(text, isDiagnostic: true)
            }
        }

        proc.terminationHandler = { [weak self] p in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.quickProcess = nil
                self.outputPipe = nil
                self.errorPipe = nil
                self.inputPipe = nil
                self.pendingPermissionRequest = nil
                self.approvalScanBuffer = ""
                self.isBusy = false

                if let sessionID = self.extractSessionID(from: stderr + "\n" + stdout) {
                    Self.setDesktopSessionID(sessionID)
                } else if Self.desktopSessionID == nil,
                          let created = HermesConversationStore.shared.latestThread(startedAfter: launchTime - 5) {
                    Self.setDesktopSessionID(created.id)
                    self.emitMirrorToolUse("Hermes 会话已接上", ["session_id": created.id])
                }
                self.adoptPendingTranscript(for: Self.desktopSessionID)
                if let current = self.effectiveModel {
                    Self.setEffectiveModel(current, for: Self.desktopSessionID)
                }
                self.syncRuntimeModel(from: stderr + "\n" + stdout)

                let text = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    self.history.append(AgentMessage(role: .assistant, text: text))
                    self.persistPendingTranscript()
                    HermesBridge.shared.recordConversation(user: userMessage, assistant: text)
                    self.emitMirrorToolResult("Hermes 回复完成", false)
                    self.onText?(text)
                    self.speakCompletedResponseIfNeeded(text)
                } else {
                    let diagnostic = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let msg = p.terminationStatus == 0
                        ? "小橘子这次没有返回文字。"
                        : "Hermes returned an error:\n\(diagnostic.isEmpty ? "exit \(p.terminationStatus)" : diagnostic)"
                    self.history.append(AgentMessage(role: .error, text: msg))
                    self.persistPendingTranscript()
                    HermesBridge.shared.appendMemoryEvent(category: "Hermes 错误", title: "Hermes 调用失败", detail: msg)
                    self.emitMirrorToolResult("Hermes 没有返回文字或执行失败", true)
                    self.onError?(msg)
                }

                self.onTurnComplete?()
            }
        }

        do {
            try proc.run()
            quickProcess = proc
            outputPipe = outPipe
            errorPipe = errPipe
            inputPipe = inPipe
        } catch {
            isBusy = false
            let msg = "Failed to launch Hermes CLI: \(error.localizedDescription)"
            history.append(AgentMessage(role: .error, text: msg))
            persistPendingTranscript()
            HermesBridge.shared.appendMemoryEvent(category: "Hermes 错误", title: "Hermes 启动失败", detail: msg)
            onError?(msg)
        }
    }

    func terminate() {
        process?.terminate()
        quickProcess?.terminate()
        gatewayProcess?.terminate()
        process = nil
        quickProcess = nil
        gatewayProcess = nil
        outputPipe = nil
        errorPipe = nil
        inputPipe = nil
        gatewayInputPipe = nil
        gatewayOutputPipe = nil
        gatewayErrorPipe = nil
        ptyMasterHandle?.readabilityHandler = nil
        try? ptyMasterHandle?.close()
        ptyMasterHandle = nil
        isLivePTYActive = false
        isGatewayActive = false
        isGatewayReady = false
        isGatewayStarting = false
        gatewaySessionID = nil
        gatewayResponseHandlers.removeAll()
        gatewayQueuedPrompts.removeAll()
        gatewayReadyCallbacks.removeAll()
        gatewayStdoutBuffer = ""
        gatewayStderrBuffer = ""
        gatewayTurnBuffer = ""
        gatewayLastUserMessage = ""
        liveTurnBuffer = ""
        liveLastUserMessage = ""
        pendingPTYEcho = nil
        ptyIdleToken += 1
        pendingPermissionRequest = nil
        pendingGatewayInputRequest = nil
        approvalScanBuffer = ""
        voiceStatus = HermesVoiceStatus()
        notifyVoiceStatus()
        isRunning = false
        isBusy = false
    }

    func respondToPermission(_ decision: HermesPermissionDecision) {
        let request = pendingPermissionRequest
        pendingPermissionRequest = nil
        approvalScanBuffer = ""
        if let gatewaySessionID, isGatewayActive {
            sendGatewayRequest(method: "approval.respond", params: [
                "session_id": gatewaySessionID,
                "choice": decision.rawValue
            ])
        } else {
            let token = permissionResponseToken(for: decision, request: request) + "\n"
            if let data = token.data(using: .utf8) {
                if isLivePTYActive {
                    try? ptyMasterHandle?.write(contentsOf: data)
                } else {
                    try? inputPipe?.fileHandleForWriting.write(contentsOf: data)
                }
            }
        }
        HermesBridge.shared.recordPermissionDecision(
            decision: decision.title,
            command: request?.command ?? "",
            detail: request?.detail ?? request?.rawText ?? ""
        )
        emitMirrorToolUse("Hermes 权限已处理", [
            "选择": decision.title,
            "命令": request?.command ?? "未捕获命令"
        ])
    }

    func refreshVoiceStatus() {
        performWithGatewaySession { [weak self] _ in
            self?.sendGatewayRequest(method: "voice.toggle", params: ["action": "status"]) { [weak self] frame in
                self?.handleGatewayVoiceToggleResponse(frame, recordingOverride: nil, processingOverride: nil)
            }
        }
    }

    func toggleVoiceRecording() {
        performWithGatewaySession { [weak self] sessionID in
            guard let self else { return }
            if !self.voiceStatus.enabled {
                self.sendGatewayRequest(method: "voice.toggle", params: ["action": "on"]) { [weak self] frame in
                    guard let self else { return }
                    self.handleGatewayVoiceToggleResponse(frame, recordingOverride: nil, processingOverride: nil)
                    guard frame["error"] == nil, self.voiceStatus.enabled else {
                        self.emitMirrorToolUse("Hermes 语音未能开启", [
                            "协议": "voice.toggle",
                            "说明": self.voiceStatus.details.isEmpty ? "Hermes 未返回 enabled=true" : self.voiceStatus.details
                        ])
                        return
                    }
                    self.setVoiceRecording(start: true, sessionID: sessionID)
                }
                return
            }
            self.setVoiceRecording(start: !self.voiceStatus.recording, sessionID: sessionID)
        }
    }

    func toggleVoiceTTS() {
        voiceStatus.ttsEnabled.toggle()
        UserDefaults.standard.set(voiceStatus.ttsEnabled, forKey: DefaultsKeys.voiceTTSEnabled)
        if !voiceStatus.ttsEnabled {
            interruptHermesTTSPlayback(reason: "朗读关闭")
            voiceStatus.speaking = false
            voiceSpeakingResetToken += 1
            voiceStatus.details = ""
        } else {
            voiceStatus.details = ""
            refreshVoiceStatus()
        }
        notifyVoiceStatus()
        emitMirrorToolUse(voiceStatus.ttsEnabled ? "Hermes 回复朗读已开启" : "Hermes 回复朗读已关闭", [
            "模式": "桌宠本地 ON/OFF",
            "协议": "回复完成时调用官方 voice.tts"
        ])
    }

    func speakViaHermesVoice(_ text: String) {
        let clean = speechTextForHermesVoice(text)
        guard !clean.isEmpty else { return }
        performWithGatewaySession { [weak self] _ in
            guard let self else { return }
            self.interruptHermesTTSPlayback(reason: "新回复开始朗读")
            self.voiceStatus.speaking = true
            self.voiceStatus.details = ""
            self.notifyVoiceStatus()
            self.sendGatewayRequest(method: "voice.tts", params: ["text": clean, "interrupt": true]) { [weak self] frame in
                guard let self else { return }
                if let error = frame["error"] as? [String: Any] {
                    let rawMessage = self.stringValue(error["message"]) ?? "Hermes 朗读失败"
                    let message = self.localizedVoiceTTSFailure(rawMessage)
                    self.voiceStatus.speaking = false
                    self.voiceStatus.details = message
                    self.notifyVoiceStatus()
                    self.emitMirrorToolUse("Hermes 回复朗读失败", [
                        "协议": "voice.tts",
                        "错误": message,
                        "原始错误": rawMessage
                    ])
                    self.onError?(message)
                } else if frame["result"] != nil {
                    self.voiceStatus.details = ""
                    self.notifyVoiceStatus()
                }
            }
            self.scheduleVoiceSpeakingReset(after: min(max(Double(clean.count) / 8.5, 3.0), 18.0))
        }
    }

    private func speakCompletedResponseIfNeeded(_ text: String) {
        guard voiceStatus.ttsEnabled else { return }
        speakViaHermesVoice(text)
    }

    private func speechTextForHermesVoice(_ text: String) -> String {
        var clean = stripANSI(text)
        let patterns = [
            #"(?s)```.*?```"#,
            #"(?m)^\s*\{.*"method"\s*:\s*"event".*$"#,
            #"(?m)^\s*\{.*"type"\s*:\s*"(?:tool|status|gateway|thinking|reasoning)\.[^"]+".*$"#,
            #"（[^（）\n]{1,180}）"#,
            #"\([^()\n]{1,180}\)"#
        ]
        for pattern in patterns {
            clean = clean.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        clean = clean
            .components(separatedBy: .newlines)
            .filter { !isNonSpeechHermesLine($0) }
            .joined(separator: "\n")

        clean = clean
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"^[\s，。！？、~～…—-]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\s，、~～…—-]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return clean
    }

    private func isNonSpeechHermesLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()

        if trimmed.hasPrefix(">") || trimmed.hasPrefix("❯") || trimmed.hasPrefix("⚕ ❯") {
            return true
        }
        if lower.hasPrefix("[") && lower.contains("] hermes") {
            return true
        }
        if firstMatch(in: trimmed, pattern: #"^\d{2}:\d{2}:\d{2}\s+-\s+"#) != nil {
            return true
        }
        if firstMatch(in: trimmed, pattern: #"^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}"#) != nil {
            return true
        }
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            return true
        }

        let blockedFragments = [
            "工具/工作流",
            "小橘子工具记录",
            "Hermes 事件",
            "Hermes Gateway",
            "Hermes 调用工具",
            "Hermes 工具",
            "Hermes 执行命令",
            "Hermes 读取文件",
            "Hermes 修改文件",
            "Hermes 搜索内容",
            "Hermes 正在思考",
            "Hermes 正在生成",
            "Hermes 正在输出",
            "Hermes 回复完成",
            "工具失败",
            "工具完成",
            "正在编辑",
            "已编辑",
            "已探索",
            "已处理",
            "已更改",
            "api_calls=",
            "tool_executor",
            "tools.",
            "agent.conversation_loop",
            "run_agent:",
            "file_path",
            "media_tag",
            "image_generate",
            "video_generate",
            "text_to_speech",
            "voice.tts",
            "voice.record",
            "prompt.submit",
            "image.attach",
            "session.create",
            "session.resume"
        ]
        if blockedFragments.contains(where: { trimmed.localizedCaseInsensitiveContains($0) }) {
            return true
        }

        if lower.hasPrefix("tool ") || lower.hasPrefix("tool:") || lower.hasPrefix("tool_name") {
            return true
        }
        if lower.contains("/users/") || lower.contains(".swift") || lower.contains(".md") || lower.contains(".py") {
            return true
        }
        return false
    }

    private func interruptHermesTTSPlayback(reason: String) {
        voiceSpeakingResetToken += 1
        let currentPID = getpid()
        DispatchQueue.global(qos: .utility).async {
            let proc = Process()
            let pipe = Pipe()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            proc.arguments = ["-f", "hermes_voice/tts_.*\\.(mp3|ogg|wav)"]
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let pids = output
                .split(whereSeparator: \.isNewline)
                .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { $0 > 0 && $0 != currentPID }
            guard !pids.isEmpty else { return }
            for pid in pids {
                kill(pid, SIGTERM)
            }
            DispatchQueue.main.async { [weak self] in
                self?.emitMirrorToolUse("Hermes 朗读已打断", [
                    "原因": reason,
                    "进程数": pids.count
                ])
            }
        }
    }

    private var gatewayEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["MORANGE_HERMES_TRANSPORT"] ?? env["MORANGE_HERMES_TUI_GATEWAY"] {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["0", "false", "off", "quick", "pipe", "pty"].contains(normalized) { return false }
            if ["1", "true", "on", "gateway", "tui-gateway", "rpc", "tui_gateway"].contains(normalized) { return true }
        }
        if UserDefaults.standard.object(forKey: DefaultsKeys.tuiGatewayEnabled) != nil {
            return UserDefaults.standard.bool(forKey: DefaultsKeys.tuiGatewayEnabled)
        }
        return true
    }

    private func sendViaGatewayIfPossible(message: String, attachments: [AgentAttachment]) -> Bool {
        guard gatewayEnabled else { return false }
        let normalizedMessage = gatewayMessageWithAttachmentReferences(message, attachments: attachments)
        let userMessage = displayMessage(message, attachments: attachments)
        prepareGatewayTurn(normalizedMessage: normalizedMessage, userMessage: userMessage)
        gatewayQueuedPrompts.append(GatewayPrompt(
            normalizedMessage: normalizedMessage,
            userMessage: userMessage,
            imageURLs: attachments.filter { $0.kind == .image }.map(\.url),
            launchTime: Date().timeIntervalSince1970
        ))
        if let prompt = gatewayQueuedPrompts.last {
            scheduleGatewayFallbackIfNeeded(for: prompt)
        }
        launchGatewayIfNeeded()
        flushQueuedGatewayPromptsIfReady()
        return true
    }

    private func prepareGatewayTurn(normalizedMessage: String, userMessage: String) {
        effectiveModel = restoreEffectiveModel(for: currentSessionID)
        modelScanBuffer = ""
        approvalScanBuffer = ""
        lastPermissionSignature = ""
        gatewayTurnBuffer = ""
        gatewayLastUserMessage = userMessage
        gatewayTurnLaunchTime = Date().timeIntervalSince1970
        if let requestedModel = runtimeModelFromSlashModelCommand(normalizedMessage) {
            updateEffectiveModel(requestedModel)
        }
        isBusy = true
        history.append(AgentMessage(role: .user, text: userMessage))
        persistPendingTranscript()
        emitMirrorToolUse("Hermes Gateway 接管中", [
            "协议": "TUI gateway JSON-RPC",
            "会话": UserDefaults.standard.string(forKey: DefaultsKeys.desktopSessionID) ?? "新会话"
        ])
    }

    private func scheduleGatewayFallbackIfNeeded(for prompt: GatewayPrompt) {
        gatewayFallbackToken += 1
        let token = gatewayFallbackToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 14.0) { [weak self] in
            guard let self else { return }
            guard self.gatewayFallbackToken == token,
                  self.isBusy,
                  self.gatewayLastUserMessage == prompt.userMessage,
                  self.gatewayTurnBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  self.pendingPermissionRequest == nil,
                  self.pendingGatewayInputRequest == nil else {
                return
            }
            self.fallbackGatewayPromptToQuick(prompt)
        }
    }

    private func fallbackGatewayPromptToQuick(_ prompt: GatewayPrompt) {
        gatewayQueuedPrompts.removeAll {
            $0.launchTime == prompt.launchTime && $0.userMessage == prompt.userMessage
        }
        emitMirrorToolUse("Hermes Gateway 卡住，回退 quick 模式", [
            "位置": gatewayFallbackStage(),
            "回退": "hermes chat -q --resume",
            "说明": "gateway 没有返回正文增量，避免主人消息悬空"
        ])
        isGatewayFallbackActive = true
        gatewayResponseHandlers.removeAll()
        gatewayReadyCallbacks.removeAll()
        gatewayInputPipe = nil
        gatewayOutputPipe = nil
        gatewayErrorPipe = nil
        isGatewayActive = false
        isGatewayReady = false
        isGatewayStarting = false
        gatewayProcess?.terminate()
        gatewayProcess = nil
        gatewaySessionID = nil
        gatewayTurnBuffer = ""
        let fallbackAttachments = prompt.imageURLs.map { AgentAttachment(kind: .image, url: $0) }
        sendViaQuickProcess(
            normalizedMessage: prompt.normalizedMessage,
            userMessage: prompt.userMessage,
            attachments: fallbackAttachments,
            recordUser: false
        )
    }

    private func gatewayFallbackStage() -> String {
        if isGatewayStarting { return "gateway 启动中" }
        if !isGatewayReady { return "等待 gateway.ready" }
        if gatewaySessionID == nil { return "等待 session.resume/create" }
        return "等待 prompt.submit 输出"
    }

    private func launchGatewayIfNeeded() {
        guard !isGatewayActive, !isGatewayStarting else { return }
        guard let launch = gatewayLaunchConfiguration() else {
            emitMirrorToolUse("Hermes Gateway 不可用", ["回退": "继续使用 hermes chat -q"])
            return
        }

        isGatewayStarting = true
        let proc = Process()
        proc.executableURL = launch.python
        proc.arguments = ["-m", "tui_gateway.entry"]
        proc.currentDirectoryURL = launch.root
        proc.environment = launch.environment

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async { self?.handleGatewayStdout(text) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async { self?.handleGatewayStderr(text) }
        }
        proc.terminationHandler = { [weak self] p in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self else { return }
                let suppressGatewayExit = self.isGatewayFallbackActive
                self.isGatewayActive = false
                self.isGatewayReady = false
                self.isGatewayStarting = false
                self.gatewayProcess = nil
                self.gatewayInputPipe = nil
                self.gatewayOutputPipe = nil
                self.gatewayErrorPipe = nil
                self.gatewaySessionID = nil
                self.gatewayResponseHandlers.removeAll()
                self.gatewayReadyCallbacks.removeAll()
                self.voiceStatus.recording = false
                self.voiceStatus.processing = false
                self.voiceStatus.speaking = false
                self.notifyVoiceStatus()
                if suppressGatewayExit {
                    self.isGatewayFallbackActive = false
                    return
                }
                if self.isBusy {
                    self.finishGatewayTurn(text: self.gatewayTurnBuffer, isError: true, summary: "Hermes Gateway 已退出：\(p.terminationStatus)")
                }
                self.onProcessExit?()
            }
        }

        do {
            try proc.run()
            gatewayProcess = proc
            gatewayInputPipe = inPipe
            gatewayOutputPipe = outPipe
            gatewayErrorPipe = errPipe
            isGatewayActive = true
            emitMirrorToolUse("Hermes Gateway 已启动", [
                "入口": "python -m tui_gateway.entry",
                "协议": "JSON-RPC over stdio"
            ])
        } catch {
            isGatewayStarting = false
            emitMirrorToolUse("Hermes Gateway 启动失败", [
                "错误": error.localizedDescription,
                "回退": "继续使用 hermes chat -q"
            ])
        }
    }

    private func gatewayLaunchConfiguration() -> (python: URL, root: URL, environment: [String: String])? {
        let env = ProcessInfo.processInfo.environment
        let rootPath = env["HERMES_PYTHON_SRC_ROOT"]
            ?? HermesBridge.shared.hermesHomeURL.appendingPathComponent("hermes-agent", isDirectory: true).path
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        let venvPython = root
            .appendingPathComponent("venv")
            .appendingPathComponent("bin")
            .appendingPathComponent("python")
        let python = FileManager.default.isExecutableFile(atPath: venvPython.path)
            ? venvPython
            : URL(fileURLWithPath: "/usr/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return nil }

        var processEnv = ShellEnvironment.processEnvironment(extraPaths: [
            root.appendingPathComponent("venv").appendingPathComponent("bin").path
        ])
        let existingPythonPath = processEnv["PYTHONPATH"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        processEnv["PYTHONPATH"] = existingPythonPath.isEmpty ? root.path : "\(root.path):\(existingPythonPath)"
        processEnv["HERMES_PYTHON_SRC_ROOT"] = root.path
        processEnv["HERMES_PYTHON"] = python.path
        processEnv["HERMES_CWD"] = resolvedWorkingDirectoryURL().path
        processEnv["TERMINAL_CWD"] = resolvedWorkingDirectoryURL().path
        processEnv["HERMES_SESSION_SOURCE"] = "morange_desktop"
        processEnv["HERMES_TUI_TOOL_PROGRESS"] = "verbose"
        processEnv["HERMES_TUI_GATEWAY_SHUTDOWN_GRACE_S"] = "1"
        processEnv["TERM"] = "dumb"
        return (python, root, processEnv)
    }

    private func handleGatewayStdout(_ text: String) {
        gatewayStdoutBuffer += text
        let lines = gatewayStdoutBuffer.components(separatedBy: .newlines)
        gatewayStdoutBuffer = lines.last ?? ""
        for line in lines.dropLast() {
            handleGatewayLine(line)
        }
    }

    private func handleGatewayStderr(_ text: String) {
        gatewayStderrBuffer += text
        let lines = gatewayStderrBuffer.components(separatedBy: .newlines)
        gatewayStderrBuffer = lines.last ?? ""
        for raw in lines.dropLast() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            mirrorHermesOutput(line, isDiagnostic: true)
        }
    }

    private func handleGatewayLine(_ line: String) {
        guard !isGatewayFallbackActive else { return }
        let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard let data = clean.data(using: .utf8),
              let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            emitMirrorToolUse("Hermes Gateway 协议输出无法解析", ["内容": clipped(clean, limit: 220)])
            return
        }
        if let idNumber = frame["id"] as? NSNumber {
            gatewayResponseHandlers.removeValue(forKey: idNumber.intValue)?(frame)
            return
        }
        if let method = frame["method"] as? String, method == "event" {
            handleGatewayEvent(frame: frame, rawLine: clean)
        }
    }

    private func handleGatewayEvent(frame: [String: Any], rawLine: String) {
        mirrorHermesOutput(rawLine, isDiagnostic: false)
        guard let params = frame["params"] as? [String: Any],
              let type = params["type"] as? String else { return }
        let payload = params["payload"] as? [String: Any] ?? [:]

        switch type {
        case "gateway.ready":
            isGatewayReady = true
            isGatewayStarting = false
            ensureGatewaySession()
        case "message.delta":
            let text = stringValue(payload["text"]) ?? ""
            if !text.isEmpty {
                gatewayTurnBuffer += text
                onText?(text)
            }
        case "message.complete":
            let text = stringValue(payload["text"]) ?? gatewayTurnBuffer
            let finalText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : gatewayTurnBuffer
            finishGatewayTurn(text: finalText, isError: false, summary: "Hermes Gateway 回复完成")
            speakCompletedResponseIfNeeded(finalText)
        case "voice.status":
            applyGatewayVoiceEventState(stringValue(payload["state"]) ?? "")
        case "voice.transcript":
            if boolValue(payload["no_speech_limit"]) == true {
                ignoreVoiceIdleUntil = .distantPast
                voiceStatus.enabled = false
                voiceStatus.recording = false
                voiceStatus.processing = false
                notifyVoiceStatus()
                emitMirrorToolUse("Hermes 语音已暂停", ["原因": "连续多次未检测到语音"])
                return
            }
            let text = stringValue(payload["text"]) ?? ""
            guard !text.isEmpty else {
                ignoreVoiceIdleUntil = .distantPast
                voiceStatus.recording = false
                voiceStatus.processing = false
                notifyVoiceStatus()
                return
            }
            ignoreVoiceIdleUntil = .distantPast
            voiceStatus.recording = false
            voiceStatus.processing = false
            notifyVoiceStatus()
            onVoiceTranscript?(text)
            send(message: text, attachments: [])
        case "clarify.request":
            let request = HermesGatewayInputRequest(
                id: stringValue(payload["request_id"]) ?? stablePermissionID(kind: type, command: "", detail: stringValue(payload["question"]) ?? ""),
                kind: .clarify,
                title: "小橘子 · Hermes 想确认",
                prompt: stringValue(payload["question"]) ?? "Hermes 需要主人选择。",
                choices: stringArrayValue(payload["choices"]),
                envVar: ""
            )
            pendingGatewayInputRequest = request
            onGatewayInputRequest?(request)
        case "sudo.request":
            let request = HermesGatewayInputRequest(
                id: stringValue(payload["request_id"]) ?? stablePermissionID(kind: type, command: "", detail: "sudo"),
                kind: .sudo,
                title: "小橘子 · sudo 密码",
                prompt: "Hermes 需要 sudo 密码来继续。",
                choices: [],
                envVar: ""
            )
            pendingGatewayInputRequest = request
            onGatewayInputRequest?(request)
        case "secret.request":
            let prompt = stringValue(payload["prompt"]) ?? "Hermes 需要密钥或环境变量。"
            let request = HermesGatewayInputRequest(
                id: stringValue(payload["request_id"]) ?? stablePermissionID(kind: type, command: "", detail: prompt),
                kind: .secret,
                title: "小橘子 · Secret 输入",
                prompt: prompt,
                choices: [],
                envVar: stringValue(payload["env_var"]) ?? ""
            )
            pendingGatewayInputRequest = request
            onGatewayInputRequest?(request)
        case "error":
            let message = stringValue(payload["message"]) ?? "Hermes Gateway 返回错误"
            if isBusy {
                finishGatewayTurn(text: message, isError: true, summary: "Hermes Gateway 出错")
            } else {
                onError?(message)
            }
        case "session.info":
            if let model = stringValue(payload["model"]) {
                let provider = Self.provider(for: model, hint: stringValue(payload["provider"]), fallback: nil)
                updateEffectiveModel(HermesRuntimeModel(provider: provider, model: model))
            }
        default:
            break
        }
    }

    private func ensureGatewaySession() {
        guard isGatewayReady, gatewaySessionID == nil else {
            flushQueuedGatewayPromptsIfReady()
            flushGatewayReadyCallbacksIfReady()
            return
        }
        if let existing = Self.desktopSessionID,
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sendGatewayRequest(method: "session.resume", params: [
                "session_id": existing,
                "cols": 96
            ]) { [weak self] frame in
                guard let self else { return }
                if let result = frame["result"] as? [String: Any],
                   let sid = result["session_id"] as? String {
                    self.gatewaySessionID = sid
                    if let resumed = result["resumed"] as? String {
                        Self.setDesktopSessionID(resumed)
                    }
                    self.emitMirrorToolUse("Hermes Gateway 已继续会话", ["session_id": existing])
                    self.flushQueuedGatewayPromptsIfReady()
                    self.flushGatewayReadyCallbacksIfReady()
                } else {
                    Self.setDesktopSessionID(nil)
                    self.createGatewaySession()
                }
            }
        } else {
            createGatewaySession()
        }
    }

    private func createGatewaySession() {
        sendGatewayRequest(method: "session.create", params: ["cols": 96]) { [weak self] frame in
            guard let self else { return }
            guard let result = frame["result"] as? [String: Any],
                  let sid = result["session_id"] as? String else {
                self.finishGatewayTurn(text: "Hermes Gateway session.create 失败", isError: true, summary: "Hermes Gateway 建立会话失败")
                return
            }
            self.gatewaySessionID = sid
            self.emitMirrorToolUse("Hermes Gateway 会话已建立", ["gateway_session_id": sid])
            self.flushQueuedGatewayPromptsIfReady()
            self.flushGatewayReadyCallbacksIfReady()
        }
    }

    private func flushQueuedGatewayPromptsIfReady() {
        guard isGatewayReady, let gatewaySessionID else { return }
        while !gatewayQueuedPrompts.isEmpty {
            submitGatewayPrompt(gatewayQueuedPrompts.removeFirst(), gatewaySessionID: gatewaySessionID)
        }
    }

    private func performWithGatewaySession(_ callback: @escaping (String) -> Void) {
        guard gatewayEnabled else {
            onError?("Hermes 语音需要 TUI gateway。")
            return
        }
        gatewayReadyCallbacks.append(callback)
        launchGatewayIfNeeded()
        if isGatewayReady, gatewaySessionID == nil {
            ensureGatewaySession()
        }
        flushGatewayReadyCallbacksIfReady()
    }

    private func flushGatewayReadyCallbacksIfReady() {
        guard isGatewayReady, let gatewaySessionID else { return }
        let callbacks = gatewayReadyCallbacks
        gatewayReadyCallbacks.removeAll()
        callbacks.forEach { $0(gatewaySessionID) }
    }

    private func submitGatewayPrompt(_ prompt: GatewayPrompt, gatewaySessionID: String) {
        gatewayLastUserMessage = prompt.userMessage
        gatewayTurnLaunchTime = prompt.launchTime
        if !prompt.imageURLs.isEmpty {
            attachGatewayImages(prompt.imageURLs, gatewaySessionID: gatewaySessionID) { [weak self] failedPaths in
                guard let self else { return }
                var nextPrompt = prompt
                if !failedPaths.isEmpty {
                    let fallback = failedPaths.map { "- \($0)" }.joined(separator: "\n")
                    nextPrompt = GatewayPrompt(
                        normalizedMessage: "\(prompt.normalizedMessage)\n\n这些图片未能通过 image.attach 附加，请按本地路径读取：\n\(fallback)",
                        userMessage: prompt.userMessage,
                        imageURLs: [],
                        launchTime: prompt.launchTime
                    )
                }
                self.submitGatewayPromptWithoutAttachments(nextPrompt, gatewaySessionID: gatewaySessionID)
            }
            return
        }
        submitGatewayPromptWithoutAttachments(prompt, gatewaySessionID: gatewaySessionID)
    }

    private func submitGatewayPromptWithoutAttachments(_ prompt: GatewayPrompt, gatewaySessionID: String) {
        let trimmed = prompt.normalizedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            sendGatewaySlash(trimmed, gatewaySessionID: gatewaySessionID)
            return
        }
        sendGatewayRequest(method: "prompt.submit", params: [
            "session_id": gatewaySessionID,
            "text": prompt.normalizedMessage
        ])
    }

    private func attachGatewayImages(_ imageURLs: [URL], gatewaySessionID: String, completion: @escaping ([String]) -> Void) {
        var remaining = imageURLs
        var failed: [String] = []

        func attachNext() {
            guard !remaining.isEmpty else {
                completion(failed)
                return
            }
            let url = remaining.removeFirst()
            sendGatewayRequest(method: "image.attach", params: [
                "session_id": gatewaySessionID,
                "path": url.path
            ]) { [weak self] frame in
                if frame["error"] != nil {
                    failed.append(url.path)
                    self?.emitMirrorToolUse("Hermes 图片附加失败", ["路径": url.path])
                } else {
                    self?.emitMirrorToolUse("Hermes 已附加图片", ["路径": url.path])
                }
                attachNext()
            }
        }

        attachNext()
    }

    private func sendGatewaySlash(_ command: String, gatewaySessionID: String) {
        sendGatewayRequest(method: "slash.exec", params: [
            "session_id": gatewaySessionID,
            "command": command
        ]) { [weak self] frame in
            guard let self else { return }
            if frame["error"] != nil {
                self.dispatchGatewayCommand(command, gatewaySessionID: gatewaySessionID)
                return
            }
            self.handleGatewayCommandResult(frame, gatewaySessionID: gatewaySessionID)
        }
    }

    private func dispatchGatewayCommand(_ command: String, gatewaySessionID: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        let name = parts.first.map(String.init) ?? ""
        let arg = parts.count > 1 ? String(parts[1]) : ""
        sendGatewayRequest(method: "command.dispatch", params: [
            "session_id": gatewaySessionID,
            "name": name,
            "arg": arg
        ]) { [weak self] frame in
            self?.handleGatewayCommandResult(frame, gatewaySessionID: gatewaySessionID)
        }
    }

    private func handleGatewayCommandResult(_ frame: [String: Any], gatewaySessionID: String) {
        if let error = frame["error"] as? [String: Any] {
            let message = stringValue(error["message"]) ?? "Hermes 指令执行失败"
            finishGatewayTurn(text: message, isError: true, summary: "Hermes 指令执行失败")
            return
        }
        guard let result = frame["result"] as? [String: Any] else { return }
        if let message = stringValue(result["message"]) {
            sendGatewayRequest(method: "prompt.submit", params: [
                "session_id": gatewaySessionID,
                "text": message
            ])
            return
        }
        if let output = stringValue(result["output"]) {
            finishGatewayTurn(text: output, isError: false, summary: "Hermes 指令完成")
            return
        }
        if let target = stringValue(result["target"]) {
            sendGatewaySlash(target, gatewaySessionID: gatewaySessionID)
            return
        }
        finishGatewayTurn(text: "Hermes 指令已处理。", isError: false, summary: "Hermes 指令完成")
    }

    private func setVoiceRecording(start: Bool, sessionID: String) {
        let graceDeadline = start ? Date().addingTimeInterval(6.0) : .distantPast
        ignoreVoiceIdleUntil = graceDeadline
        voiceRecordingGraceUntil = graceDeadline
        voiceStatus.recording = start
        voiceStatus.processing = false
        if start { voiceStatus.details = "" }
        notifyVoiceStatus()
        sendGatewayRequest(method: "voice.record", params: [
            "action": start ? "start" : "stop",
            "session_id": sessionID
        ]) { [weak self] frame in
            guard let self else { return }
            if let error = frame["error"] as? [String: Any] {
                self.ignoreVoiceIdleUntil = .distantPast
                self.voiceStatus.recording = false
                self.voiceStatus.processing = false
                self.voiceStatus.available = false
                self.notifyVoiceStatus()
                let message = self.stringValue(error["message"]) ?? "Hermes 语音录制失败"
                self.voiceStatus.details = message
                self.notifyVoiceStatus()
                self.emitMirrorToolUse("Hermes 语音启动失败", [
                    "协议": "voice.record",
                    "错误": message
                ])
                self.onError?(message)
                return
            }
            let result = frame["result"] as? [String: Any] ?? [:]
            let status = (self.stringValue(result["status"]) ?? "").lowercased()
            if ["recording", "listening", "started", "active"].contains(status) {
                self.voiceStatus.details = ""
                self.voiceStatus.recording = true
                self.voiceStatus.processing = false
            } else if status == "stopped" {
                self.ignoreVoiceIdleUntil = .distantPast
                self.voiceRecordingGraceUntil = .distantPast
                self.voiceStatus.recording = false
                self.voiceStatus.processing = true
            } else if status == "busy" {
                self.ignoreVoiceIdleUntil = .distantPast
                self.voiceRecordingGraceUntil = .distantPast
                self.voiceStatus.recording = false
                self.voiceStatus.processing = true
                self.voiceStatus.details = "上一段语音还在转写，等小橘子听写完。"
            } else if status == "idle" {
                if start && Date() < self.voiceRecordingGraceUntil {
                    self.voiceStatus.recording = true
                    self.voiceStatus.processing = false
                } else {
                    self.voiceStatus.recording = false
                    self.voiceStatus.processing = false
                }
            }
            self.notifyVoiceStatus()
        }
        emitMirrorToolUse(start ? "Hermes 语音开始听" : "Hermes 语音停止并转写", [
            "协议": "voice.record",
            "会话": sessionID
        ])
    }

    private func handleGatewayVoiceToggleResponse(_ frame: [String: Any], recordingOverride: Bool?, processingOverride: Bool?) {
        if let error = frame["error"] as? [String: Any] {
            let message = stringValue(error["message"]) ?? "Hermes 语音状态更新失败"
            onError?(message)
            voiceStatus.recording = false
            voiceStatus.processing = false
            voiceStatus.available = false
            voiceStatus.details = message
            notifyVoiceStatus()
            return
        }
        guard let result = frame["result"] as? [String: Any] else { return }
        if let enabled = boolValue(result["enabled"]) { voiceStatus.enabled = enabled }
        if let available = boolValue(result["available"]) { voiceStatus.available = available }
        if let audioAvailable = boolValue(result["audio_available"]) { voiceStatus.audioAvailable = audioAvailable }
        if let sttAvailable = boolValue(result["stt_available"]) { voiceStatus.sttAvailable = sttAvailable }
        if let tts = boolValue(result["tts"]) { voiceStatus.ttsEnabled = tts || voiceStatus.ttsEnabled }
        if let recordKey = stringValue(result["record_key"]) { voiceStatus.recordKey = recordKey }
        if let details = stringValue(result["details"]) { voiceStatus.details = details }
        if voiceStatus.available == true && voiceStatus.audioAvailable != false && voiceStatus.sttAvailable != false {
            voiceStatus.details = ""
        }
        if let recordingOverride { voiceStatus.recording = recordingOverride }
        if let processingOverride { voiceStatus.processing = processingOverride }
        notifyVoiceStatus()
        emitMirrorToolUse("Hermes 语音状态", [
            "voice": voiceStatus.enabled ? "on" : "off",
            "auto_read": voiceStatus.ttsEnabled ? "on" : "off",
            "record_key": voiceStatus.recordKey
        ])
    }

    private func applyGatewayVoiceEventState(_ state: String) {
        let normalized = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "listening", "recording":
            voiceStatus.recording = true
            voiceStatus.processing = false
            voiceStatus.speaking = false
        case "transcribing", "processing":
            ignoreVoiceIdleUntil = .distantPast
            voiceRecordingGraceUntil = .distantPast
            voiceStatus.recording = false
            voiceStatus.processing = true
        case "idle", "stopped":
            if voiceStatus.recording && Date() < voiceRecordingGraceUntil {
                return
            }
            ignoreVoiceIdleUntil = .distantPast
            voiceRecordingGraceUntil = .distantPast
            voiceStatus.recording = false
            voiceStatus.processing = false
        default:
            return
        }
        notifyVoiceStatus()
    }

    private func notifyVoiceStatus() {
        onVoiceStatus?(voiceStatus)
    }

    private func localizedVoiceTTSFailure(_ rawMessage: String) -> String {
        let lower = rawMessage.lowercased()
        if lower.contains("no audio was received") || lower.contains("parameters are correct") {
            return "朗读没有生成音频：通常是 TTS 声音/模型参数不匹配。请检查 Hermes 的 tts.provider 和 tts.<provider>.voice/model。"
        }
        if lower.contains("model") && (lower.contains("not found") || lower.contains("does not exist") || lower.contains("no such model")) {
            return "朗读模型不存在或当前账号无权限使用：请在 Hermes 配置里换一个可用的 TTS 模型。"
        }
        if lower.contains("voice module not available") {
            return "Hermes 语音模块不可用：请检查 Hermes 语音依赖是否安装完整。"
        }
        if lower.contains("api key") || lower.contains("unauthorized") || lower.contains("permission") {
            return "朗读 provider 鉴权失败：请检查对应 TTS 服务的 API key 或账号权限。"
        }
        return rawMessage.isEmpty ? "Hermes 朗读失败" : "Hermes 朗读失败：\(rawMessage)"
    }

    private func scheduleVoiceSpeakingReset(after delay: TimeInterval) {
        voiceSpeakingResetToken += 1
        let token = voiceSpeakingResetToken
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.voiceSpeakingResetToken == token else { return }
            self.voiceStatus.speaking = false
            self.notifyVoiceStatus()
        }
    }

    private func sendGatewayRequest(method: String, params: [String: Any], handler: GatewayResponseHandler? = nil) {
        guard let input = gatewayInputPipe?.fileHandleForWriting else { return }
        gatewayRequestID += 1
        let id = gatewayRequestID
        if let handler {
            gatewayResponseHandlers[id] = handler
        }
        let frame: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        guard JSONSerialization.isValidJSONObject(frame),
              let data = try? JSONSerialization.data(withJSONObject: frame),
              let line = String(data: data, encoding: .utf8)?.appending("\n"),
              let lineData = line.data(using: .utf8) else { return }
        do {
            try input.write(contentsOf: lineData)
        } catch {
            gatewayResponseHandlers.removeValue(forKey: id)
            emitMirrorToolUse("Hermes Gateway 写入失败", [
                "错误": error.localizedDescription,
                "方法": method
            ])
        }
    }

    private func finishGatewayTurn(text: String, isError: Bool, summary: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            history.append(AgentMessage(role: isError ? .error : .assistant, text: clean))
            persistPendingTranscript()
            if isError {
                onError?(clean)
            } else {
                HermesBridge.shared.recordConversation(user: gatewayLastUserMessage, assistant: clean)
            }
        }
        if let sessionID = extractSessionID(from: clean) {
            Self.setDesktopSessionID(sessionID)
        } else if Self.desktopSessionID == nil,
                  let created = HermesConversationStore.shared.latestThread(startedAfter: gatewayTurnLaunchTime - 5) {
            Self.setDesktopSessionID(created.id)
            emitMirrorToolUse("Hermes 会话已接上", ["session_id": created.id])
        }
        adoptPendingTranscript(for: Self.desktopSessionID)
        persistPendingTranscript()
        if let current = effectiveModel {
            Self.setEffectiveModel(current, for: Self.desktopSessionID)
        }
        syncRuntimeModel(from: clean)
        gatewayTurnBuffer = ""
        gatewayLastUserMessage = ""
        pendingPermissionRequest = nil
        pendingGatewayInputRequest = nil
        approvalScanBuffer = ""
        isBusy = false
        emitMirrorToolResult(summary, isError)
        onTurnComplete?()
    }

    func respondToGatewayInput(_ request: HermesGatewayInputRequest, value: String) {
        guard isGatewayActive else { return }
        pendingGatewayInputRequest = nil
        let method: String
        let key: String
        switch request.kind {
        case .clarify:
            method = "clarify.respond"
            key = "answer"
        case .sudo:
            method = "sudo.respond"
            key = "password"
        case .secret:
            method = "secret.respond"
            key = "value"
        }
        sendGatewayRequest(method: method, params: [
            "request_id": request.id,
            key: value
        ])
        emitMirrorToolUse("Hermes 输入已提交", [
            "类型": request.title,
            "请求": request.id
        ])
    }

    private func permissionResponseToken(for decision: HermesPermissionDecision, request: HermesPermissionRequest?) -> String {
        let raw = request?.rawText.lowercased() ?? ""
        if raw.contains("type 1/2/3") || raw.contains("use ↑/↓") || raw.contains("use up/down") {
            switch decision {
            case .allowOnce: return "1"
            case .allowSession: return "2"
            case .allowAlways: return request?.allowPermanent == false ? "2" : "3"
            case .deny: return request?.allowPermanent == false ? "3" : "4"
            }
        }
        return decision.stdinToken
    }

    func attach(sessionID: String, history: [AgentMessage]) {
        Self.setDesktopSessionID(sessionID)
        self.history = history
        adoptPendingTranscript(for: sessionID)
        effectiveModel = restoreEffectiveModel(for: sessionID)
    }

    private var livePTYEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["MORANGE_HERMES_PTY"] ?? env["MORANGE_HERMES_TRANSPORT"] {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["0", "false", "off", "quick", "pipe"].contains(normalized) { return false }
            if ["1", "true", "on", "pty", "live"].contains(normalized) { return true }
        }
        if UserDefaults.standard.object(forKey: DefaultsKeys.livePTYEnabled) != nil {
            return UserDefaults.standard.bool(forKey: DefaultsKeys.livePTYEnabled)
        }
        return false
    }

    private func launchLivePTYIfNeeded() {
        guard livePTYEnabled,
              !isLivePTYActive,
              process == nil,
              let binaryPath = Self.binaryPath else { return }

        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            emitMirrorToolUse("Hermes PTY 不可用", ["说明": String(cString: strerror(errno))])
            return
        }

        let masterHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = hermesPTYArguments()
        proc.currentDirectoryURL = resolvedWorkingDirectoryURL()
        proc.environment = hermesPTYEnvironment()
        proc.standardInput = slaveHandle
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle

        masterHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self?.handleLivePTYOutput(text)
            }
        }

        proc.terminationHandler = { [weak self, weak masterHandle] _ in
            masterHandle?.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLivePTYActive = false
                self.ptyMasterHandle = nil
                self.process = nil
                self.pendingPTYEcho = nil
                self.pendingPermissionRequest = nil
                self.approvalScanBuffer = ""
                self.ptyIdleToken += 1
                if self.isBusy {
                    self.finishLivePTYTurn(reason: "Hermes PTY 已结束", isError: true)
                }
                self.onProcessExit?()
            }
        }

        do {
            try proc.run()
            try? slaveHandle.close()
            process = proc
            ptyMasterHandle = masterHandle
            isLivePTYActive = true
            emitMirrorToolUse("Hermes PTY 已连接", [
                "模式": "原生交互会话",
                "回退": "发送图片或 PTY 断开时自动使用 hermes chat -q"
            ])
        } catch {
            masterHandle.readabilityHandler = nil
            try? masterHandle.close()
            try? slaveHandle.close()
            emitMirrorToolUse("Hermes PTY 启动失败", [
                "错误": error.localizedDescription,
                "回退": "继续使用 hermes chat -q"
            ])
        }
    }

    private func hermesPTYArguments() -> [String] {
        var args = ["chat", "--source", "morange_desktop"]
        if let sessionID = UserDefaults.standard.string(forKey: DefaultsKeys.desktopSessionID),
           !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["--resume", sessionID])
        }
        return args
    }

    private func hermesPTYEnvironment() -> [String: String] {
        var env = ShellEnvironment.processEnvironment()
        env["TERM"] = env["TERM"] ?? "xterm-256color"
        env["COLORTERM"] = env["COLORTERM"] ?? "truecolor"
        env["COLUMNS"] = env["COLUMNS"] ?? "96"
        env["LINES"] = env["LINES"] ?? "30"
        env["HERMES_SESSION_SOURCE"] = "morange_desktop"
        env["MORANGE_HERMES_PTY"] = "1"
        return env
    }

    private func sendViaLivePTYIfPossible(message: String, attachments: [AgentAttachment]) -> Bool {
        guard livePTYEnabled else { return false }
        if !isLivePTYActive {
            launchLivePTYIfNeeded()
        }
        guard isLivePTYActive, let ptyMasterHandle else { return false }

        // Hermes interactive sessions do not accept per-turn --image flags.
        // Keep the existing quick path for image turns until native attachment
        // bridging is implemented.
        if attachments.contains(where: { $0.kind == .image }) {
            emitMirrorToolUse("Hermes PTY 暂让图片走 quick 模式", [
                "说明": "图片仍通过 hermes chat -q --image 保持兼容"
            ])
            return false
        }

        let normalizedMessage = messageWithAttachmentReferences(message, attachments: attachments)
        let userMessage = displayMessage(message, attachments: attachments)
        guard let data = (normalizedMessage + "\n").data(using: .utf8) else { return false }
        do {
            pendingPTYEcho = normalizedMessage
            try ptyMasterHandle.write(contentsOf: data)
            prepareLiveTurn(normalizedMessage: normalizedMessage, userMessage: userMessage)
            return true
        } catch {
            pendingPTYEcho = nil
            emitMirrorToolUse("Hermes PTY 写入失败", [
                "错误": error.localizedDescription,
                "回退": "改用 hermes chat -q"
            ])
            return false
        }
    }

    private func prepareLiveTurn(normalizedMessage: String, userMessage: String) {
        effectiveModel = restoreEffectiveModel(for: currentSessionID)
        modelScanBuffer = ""
        approvalScanBuffer = ""
        lastPermissionSignature = ""
        liveTurnBuffer = ""
        liveLastUserMessage = userMessage
        ptyIdleToken += 1
        if let requestedModel = runtimeModelFromSlashModelCommand(normalizedMessage) {
            updateEffectiveModel(requestedModel)
        }
        isBusy = true
        history.append(AgentMessage(role: .user, text: userMessage))
        persistPendingTranscript()
        emitMirrorToolUse("Hermes PTY 实时接管中", [
            "状态": "复用原生 Hermes 交互会话",
            "会话": UserDefaults.standard.string(forKey: DefaultsKeys.desktopSessionID) ?? "新会话"
        ])
    }

    private func handleLivePTYOutput(_ rawText: String) {
        mirrorHermesOutput(rawText, isDiagnostic: false)
        var displayText = displayablePTYText(rawText)
        if let echo = pendingPTYEcho, !echo.isEmpty {
            let filtered = removingPendingEcho(echo, from: displayText)
            if filtered != displayText {
                pendingPTYEcho = nil
            }
            displayText = filtered
        }
        guard !displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        liveTurnBuffer += displayText
        onText?(displayText)
        scheduleLivePTYIdleCompletion()
    }

    private func displayablePTYText(_ text: String) -> String {
        let cleaned = stripANSI(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0007}", with: "")
        return cleaned
            .components(separatedBy: .newlines)
            .filter { !isPTYChromeLine($0) }
            .joined(separator: "\n")
    }

    private func removingPendingEcho(_ echo: String, from text: String) -> String {
        let normalizedEcho = echo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEcho.isEmpty,
              let range = text.range(of: normalizedEcho) else { return text }
        let prefix = text[..<range.lowerBound]
        guard prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        return String(text[range.upperBound...])
    }

    private func scheduleLivePTYIdleCompletion() {
        guard isLivePTYActive, isBusy else { return }
        ptyIdleToken += 1
        let token = ptyIdleToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            guard let self = self,
                  self.ptyIdleToken == token,
                  self.isLivePTYActive,
                  self.isBusy,
                  self.pendingPermissionRequest == nil else { return }
            self.finishLivePTYTurn(reason: "Hermes PTY 已回到可输入状态", isError: false)
        }
    }

    private func finishLivePTYTurn(reason: String, isError: Bool) {
        let text = liveTurnBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            history.append(AgentMessage(role: isError ? .error : .assistant, text: text))
            persistPendingTranscript()
            if !isError {
                HermesBridge.shared.recordConversation(user: liveLastUserMessage, assistant: text)
            }
        }
        liveTurnBuffer = ""
        liveLastUserMessage = ""
        isBusy = false
        if let sessionID = extractSessionID(from: text) {
            Self.setDesktopSessionID(sessionID)
        }
        adoptPendingTranscript(for: Self.desktopSessionID)
        persistPendingTranscript()
        syncRuntimeModel(from: text)
        emitMirrorToolResult(reason, isError)
        if !isError {
            speakCompletedResponseIfNeeded(text)
        }
        onTurnComplete?()
    }

    private func configuredBinaryPath() -> String? {
        if let envPath = ProcessInfo.processInfo.environment["MORANGE_HERMES_PATH"],
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
        if let envPath = ProcessInfo.processInfo.environment["MORANGE_HERMES_CWD"],
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

    private func hermesArguments(for message: String, attachments: [AgentAttachment]) -> [String] {
        var args = ["chat", "-q", message, "-Q", "--source", "morange_desktop"]
        if let image = attachments.first(where: { $0.kind == .image }) {
            args.append(contentsOf: ["--image", image.url.path])
        }
        if let sessionID = UserDefaults.standard.string(forKey: DefaultsKeys.desktopSessionID),
           !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["--resume", sessionID])
        }
        return args
    }

    private func messageWithAttachmentReferences(_ message: String, attachments: [AgentAttachment]) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = trimmed.isEmpty ? defaultPrompt(for: attachments) : trimmed
        let extraImages = attachments.filter { $0.kind == .image }.dropFirst()
        let files = attachments.filter { $0.kind == .file }

        var lines: [String] = []
        if !extraImages.isEmpty {
            lines.append("Hermes CLI 当前只接收第一张 --image；其余图片请按本地路径读取/分析：")
            lines.append(contentsOf: extraImages.map { "- \($0.url.path)" })
        }
        if !files.isEmpty {
            lines.append("附加本地文件路径，请按需要读取：")
            lines.append(contentsOf: files.map { "- \($0.url.path)" })
        }
        if !lines.isEmpty {
            result += "\n\n" + lines.joined(separator: "\n")
        }
        return result
    }

    private func gatewayMessageWithAttachmentReferences(_ message: String, attachments: [AgentAttachment]) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = trimmed.isEmpty ? defaultPrompt(for: attachments) : trimmed
        let files = attachments.filter { $0.kind == .file }
        guard !files.isEmpty else { return result }
        var lines = ["附加本地文件路径，请按需要读取："]
        lines.append(contentsOf: files.map { "- \($0.url.path)" })
        result += "\n\n" + lines.joined(separator: "\n")
        return result
    }

    private func displayMessage(_ message: String, attachments: [AgentAttachment]) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = trimmed.isEmpty ? defaultPrompt(for: attachments) : trimmed
        if !attachments.isEmpty {
            result += "\n\n附件：\(attachmentSummary(attachments))"
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

    private func attachmentSummary(_ attachments: [AgentAttachment]) -> String {
        attachments.map { attachment in
            let prefix = attachment.kind == .image ? "图片" : "文件"
            return "\(prefix): \(attachment.displayName)"
        }.joined(separator: "；")
    }

    private func mirrorHermesOutput(_ text: String, isDiagnostic: Bool) {
        let clean = stripANSI(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        if let sessionID = extractSessionID(from: clean) {
            Self.setDesktopSessionID(sessionID)
            if let current = effectiveModel {
                Self.setEffectiveModel(current, for: sessionID)
            }
            emitMirrorToolUse("Hermes 会话已接上", ["session_id": sessionID])
        }

        syncRuntimeModel(from: clean)

        let lower = clean.lowercased()
        let approvalText = approvalScanText(adding: clean)
        if let permission = permissionRequest(from: approvalText) {
            pendingPermissionRequest = permission
            emitMirrorToolUse("Hermes 等待主人确认", [
                "说明": permission.detail,
                "命令": permission.command.isEmpty ? "未捕获命令" : permission.command
            ])
            if permission.id != lastPermissionSignature {
                lastPermissionSignature = permission.id
                onPermissionRequest?(permission)
            }
            return
        }
        if pendingPermissionRequest == nil && !looksPermissionRelated(clean) {
            approvalScanBuffer = ""
        }

        if handleHermesOfficialEvent(from: clean) {
            return
        }

        if mirrorStructuredState(from: clean, lower: lower, isDiagnostic: isDiagnostic) {
            return
        }

        if let tool = firstMatch(in: clean, pattern: #"Tool\s+([A-Za-z0-9_.:-]+)\s+returned\s+error"#) {
            emitMirrorToolResult("Hermes 工具 \(tool) 执行失败", true)
            return
        }

        if let tool = firstMatch(in: clean, pattern: #"Tool\s+([A-Za-z0-9_.:-]+)\s+returned"#) {
            emitMirrorToolResult("Hermes 工具 \(tool) 完成", false)
            return
        }

        if let tool = firstMatch(in: clean, pattern: #"(?:Tool|tool)\s+([A-Za-z0-9_.:-]+)"#),
           lower.contains("tool") {
            emitMirrorToolUse("Hermes 调用工具", ["工具": tool, "线索": String(clean.prefix(220))])
            return
        }

        if lower.contains("thinking") || lower.contains("reasoning") || clean.contains("思考") {
            emitMirrorToolUse("Hermes 正在思考", ["状态": String(clean.prefix(180))])
            return
        }

        if isDiagnostic {
            if lower.contains("warning") {
                emitMirrorToolUse("Hermes 发现警告", ["日志": String(clean.prefix(220))])
            } else if lower.contains("error") || clean.contains("失败") {
                emitMirrorToolResult("Hermes 日志出现错误：\(String(clean.prefix(180)))", true)
            }
            return
        }

        if isBusy {
            emitMirrorToolUse("Hermes 正在整理回复", ["状态": "收到 Hermes 输出，正在收束成给主人看的回答"])
        }
    }

    private func restoreEffectiveModel(for sessionID: String?) -> HermesRuntimeModel {
        if let stored = Self.effectiveModel(for: sessionID) {
            return stored
        }
        if let threadModel = Self.runtimeModel(from: HermesConversationStore.shared.thread(id: sessionID ?? "")) {
            return threadModel
        }
        if let currentStored = Self.effectiveModel(for: nil) {
            return currentStored
        }
        return Self.runtimeModelFromConfig()
    }

    private func syncRuntimeModel(from text: String) {
        let clean = stripANSI(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let combined = modelScanBuffer.isEmpty ? clean : "\(modelScanBuffer)\n\(clean)"
        if combined.count > 5000 {
            modelScanBuffer = String(combined.suffix(5000))
        } else {
            modelScanBuffer = combined
        }

        if let runtimeModel = detectedRuntimeModel(from: clean) ?? detectedRuntimeModel(from: modelScanBuffer) {
            updateEffectiveModel(runtimeModel)
        }
    }

    private func detectedRuntimeModel(from clean: String) -> HermesRuntimeModel? {
        let patterns = [
            #"切换到\s*[`'"]?([A-Za-z0-9_.:/-]+)[`'"]?\s*[（(]([^)）]+)[)）]"#,
            #"模型(?:已经|已)?切换(?:到|为)\s*[`'"]?([A-Za-z0-9_.:/-]+)[`'"]?(?:\s*[（(]([^)）]+)[)）])?"#,
            #"(?:当前模型|目前模型)\s*[:：]\s*[`'"]?([A-Za-z0-9_.:/-]+)[`'"]?(?:\s*[（(]([^)）]+)[)）])?"#,
            #"(?:使用|用)的是\s*[`'"]?([A-Za-z0-9_.:/-]+)[`'"]?"#,
            #"current\s+model\s*[:：]\s*[`'"]?([A-Za-z0-9_.:/-]+)[`'"]?(?:\s*[（(]([^)）]+)[)）])?"#,
            #"model\s+(?:set|changed|switched)\s+to\s+[`'"]?([A-Za-z0-9_.:/-]+)[`'"]?(?:\s*[（(]([^)）]+)[)）])?"#,
            #"switched\s+(?:the\s+model\s+)?(?:to|into)\s+[`'"]?([A-Za-z0-9_.:/-]+)[`'"]?(?:\s*[（(]([^)）]+)[)）])?"#,
            #"now\s+(?:this\s+chat\s+)?(?:uses|using|is\s+using)\s+[`'"]?([A-Za-z0-9_.:/-]+)[`'"]?"#
        ]

        for pattern in patterns {
            guard let captures = firstCaptureGroups(in: clean, pattern: pattern),
                  let rawModel = captures.first else { continue }
            let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else { continue }
            let providerHint = captures.count > 1 ? captures[1] : nil
            let provider = Self.provider(for: model, hint: providerHint, fallback: currentEffectiveModel?.provider)
            return HermesRuntimeModel(provider: provider, model: model)
        }
        return nil
    }

    private func runtimeModelFromSlashModelCommand(_ message: String) -> HermesRuntimeModel? {
        let firstLine = message
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? message
        let tokens = splitCommandLine(firstLine)
        guard let commandToken = tokens.first?.lowercased(),
              commandToken == "/model" || commandToken == "/provider",
              tokens.count > 1 else {
            return nil
        }

        var model = ""
        var providerHint: String?
        var skipNext = false
        for index in tokens.indices.dropFirst() {
            if skipNext {
                skipNext = false
                continue
            }
            let token = tokens[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = token.lowercased()
            if lower == "--provider" {
                if tokens.indices.contains(index + 1) {
                    providerHint = tokens[index + 1]
                    skipNext = true
                }
                continue
            }
            if lower.hasPrefix("--provider=") {
                providerHint = String(token.dropFirst("--provider=".count))
                continue
            }
            if lower == "--global" || lower.hasPrefix("-") {
                continue
            }
            if model.isEmpty {
                model = token
            }
        }

        let ignored = ["", "list", "ls", "show", "current", "help", "--help", "-h"]
        guard !ignored.contains(model.lowercased()) else { return nil }
        return HermesRuntimeModel(
            provider: Self.provider(for: model, hint: providerHint, fallback: currentEffectiveModel?.provider),
            model: model
        )
    }

    private func splitCommandLine(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        for char in line {
            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                } else {
                    current.append(char)
                }
                continue
            }

            if char == "\"" || char == "'" || char == "`" {
                quote = char
            } else if char == " " || char == "\t" {
                flush()
            } else {
                current.append(char)
            }
        }
        flush()
        return tokens
    }

    private func updateEffectiveModel(_ runtimeModel: HermesRuntimeModel) {
        let normalized = HermesRuntimeModel(
            provider: Self.normalizedProvider(runtimeModel.provider),
            model: runtimeModel.model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !normalized.model.isEmpty else { return }
        let previous = currentEffectiveModel
        effectiveModel = normalized
        Self.setEffectiveModel(normalized, for: currentSessionID)
        Self.setEffectiveModel(normalized, for: nil)
        if let sessionID = currentSessionID {
            HermesConversationStore.shared.updateThreadModel(id: sessionID, model: normalized.model, provider: normalized.provider)
        }
        guard previous != normalized else { return }
        emitMirrorToolUse("Hermes 模型已同步", [
            "模型": normalized.model,
            "Provider": normalized.provider
        ])
        onModelChanged?(normalized)
    }

    private func permissionRequest(from clean: String) -> HermesPermissionRequest? {
        let lower = clean.lowercased()
        guard looksPermissionRelated(clean),
              !isPermissionResolutionMessage(clean, lower: lower) else { return nil }

        let hasOfficialPrompt = lower.contains("dangerous command")
            || clean.contains("危险命令")
            || lower.contains("choice [o/s")
            || clean.contains("选择 [o/s")
            || lower.contains("[o]nce")
            || clean.contains("[o]仅此一次")
        let hasGatewayPrompt = lower.contains("approval")
            || lower.contains("permission")
            || clean.contains("需要主人确认")
            || clean.contains("等待主人确认")
        guard hasOfficialPrompt || hasGatewayPrompt else { return nil }

        let command = approvalCommand(in: clean)
        if hasOfficialPrompt && command.isEmpty {
            return nil
        }
        let detail = approvalDescription(in: clean)
            ?? firstMatch(in: clean, pattern: #"(?im)^\s*(?:description|reason|说明|原因)[:：]\s*(.+)$"#)
            ?? "Hermes 请求执行需要确认的操作"
        let allowPermanent = approvalAllowsPermanent(in: clean, lower: lower)
        let signature = "\(detail)|\(command)|\(allowPermanent)"
        return HermesPermissionRequest(
            id: stableID(for: signature),
            title: "Hermes 需要主人确认",
            detail: clipped(detail, limit: 180),
            command: clipped(command, limit: 240),
            rawText: clipped(clean, limit: 800),
            allowPermanent: allowPermanent
        )
    }

    private func approvalScanText(adding clean: String) -> String {
        let combined = approvalScanBuffer.isEmpty ? clean : "\(approvalScanBuffer)\n\(clean)"
        approvalScanBuffer = combined.count > 3000 ? String(combined.suffix(3000)) : combined
        return approvalScanBuffer
    }

    private func looksPermissionRelated(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("dangerous command")
            || lower.contains("approval")
            || lower.contains("permission")
            || lower.contains("choice [o/s")
            || lower.contains("[o]nce")
            || lower.contains("[s]ession")
            || lower.contains("[a]lways")
            || lower.contains("[d]eny")
            || text.contains("危险命令")
            || text.contains("选择 [o/s")
            || text.contains("[o]仅此一次")
            || text.contains("[s]本次会话")
            || text.contains("[a]永久允许")
            || text.contains("[d]拒绝")
            || text.contains("需要主人确认")
            || text.contains("等待主人确认")
    }

    private func isPermissionResolutionMessage(_ text: String, lower: String) -> Bool {
        let isPrompt = lower.contains("dangerous command")
            || text.contains("危险命令")
            || lower.contains("choice [o/s")
            || text.contains("选择 [o/s")
        if isPrompt { return false }
        return lower.contains("allowed once")
            || lower.contains("allowed for this session")
            || lower.contains("permanent allowlist")
            || lower.contains("denied")
            || text.contains("本次允许")
            || text.contains("本次会话内允许")
            || text.contains("永久允许")
            || text.contains("已拒绝")
            || text.contains("已取消")
    }

    private func approvalDescription(in text: String) -> String? {
        let patterns = [
            #"(?im)^\s*(?:⚠️?\s*)?DANGEROUS COMMAND\s*[:：]\s*(.+)$"#,
            #"(?im)^\s*(?:⚠️?\s*)?危险命令\s*[:：]\s*(.+)$"#
        ]
        for pattern in patterns {
            if let value = firstMatch(in: text, pattern: pattern)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func approvalCommand(in text: String) -> String {
        let explicit = firstMatch(in: text, pattern: #"(?im)^\s*(?:command|cmd|命令|执行)[:：]\s*(.+)$"#)
            ?? firstMatch(in: text, pattern: #"(?im)["']command["']\s*:\s*["']([^"']+)["']"#)
        if let explicit {
            return clipped(cleanApprovalLine(explicit), limit: 240)
        }

        let lines = text.components(separatedBy: .newlines)
        for (index, rawLine) in lines.enumerated() {
            let lower = rawLine.lowercased()
            guard lower.contains("dangerous command") || rawLine.contains("危险命令") else { continue }
            for candidate in lines.dropFirst(index + 1) {
                let cleaned = cleanApprovalLine(candidate)
                if cleaned.isEmpty { continue }
                if isApprovalChoiceLine(cleaned) { continue }
                return clipped(cleaned, limit: 240)
            }
        }

        for rawLine in lines {
            guard rawLine.prefix(while: { $0 == " " || $0 == "\t" }).count >= 4 else { continue }
            let cleaned = cleanApprovalLine(rawLine)
            if cleaned.isEmpty || isApprovalChoiceLine(cleaned) { continue }
            return clipped(cleaned, limit: 240)
        }
        return ""
    }

    private func cleanApprovalLine(_ line: String) -> String {
        line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
    }

    private func isApprovalChoiceLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("[o]")
            || lower.contains("choice [")
            || lower.contains("allowed once")
            || lower.contains("allowed for this session")
            || lower.contains("permanent allowlist")
            || lower.contains("denied")
            || line.contains("选择 [")
            || line.contains("本次允许")
            || line.contains("本次会话内允许")
            || line.contains("已加入永久允许")
            || line.contains("已拒绝")
            || line.contains("已取消")
    }

    private func approvalAllowsPermanent(in text: String, lower: String) -> Bool {
        if lower.contains("[a]lways") || text.contains("[a]永久允许") {
            return true
        }
        if lower.contains("choice [o/s/d]") || text.contains("选择 [o/s/D]") || text.contains("选择 [o/s/d]") {
            return false
        }
        return !lower.contains("always option hidden") && !lower.contains("hide the always")
    }

    private func mirrorStructuredState(from clean: String, lower: String, isDiagnostic: Bool) -> Bool {
        if let eventMirror = hermesOfficialEventMirror(from: clean) {
            emitMirrorToolUse(eventMirror.name, eventMirror.input)
            return true
        }

        if lower.contains("compress") || clean.contains("压缩上下文") || clean.contains("总结上下文") {
            emitMirrorToolUse("Hermes 压缩上下文", ["状态": clipped(clean, limit: 220)])
            return true
        }

        if let status = hermesTerminalStatus(from: clean) {
            emitMirrorToolUse("Hermes 正在生成", status)
            return true
        }

        if let mirror = hermesToolMirror(from: clean) {
            emitMirrorToolUse(mirror.name, mirror.input)
            return true
        }

        if lower.contains("memory") || clean.contains("记忆") || clean.contains("备忘录") {
            if lower.contains("write") || lower.contains("remember") || clean.contains("写入") || clean.contains("记住") {
                emitMirrorToolUse("Hermes 写入记忆", ["线索": clipped(clean, limit: 220)])
            } else {
                emitMirrorToolUse("Hermes 读取记忆", ["线索": clipped(clean, limit: 220)])
            }
            return true
        }

        if let tool = firstMatch(in: clean, pattern: #""tool_name"\s*:\s*"([^"]+)""#)
            ?? firstMatch(in: clean, pattern: #""name"\s*:\s*"([A-Za-z0-9_.:-]+)""#) {
            emitMirrorToolUse("Hermes 调用工具", ["工具": tool, "线索": clipped(clean, limit: 220)])
            return true
        }

        if let command = firstMatch(in: clean, pattern: #"(?im)^\s*(?:running|executing|execute|command|shell|bash|zsh|运行|执行命令|命令)[:：]\s*(.+)$"#) {
            emitMirrorToolUse("Hermes 执行命令", ["命令": clipped(command, limit: 220)])
            return true
        }

        if lower.contains("exec_command") || lower.contains("terminal_tool") || lower.contains("bash ") || lower.contains("zsh ") {
            emitMirrorToolUse("Hermes 执行命令", ["线索": clipped(clean, limit: 220)])
            return true
        }

        if let path = firstMatch(in: clean, pattern: #"(?im)^\s*(?:reading|read file|open file|读取文件|读取)[:：]\s*(.+)$"#) {
            emitMirrorToolUse("Hermes 读取文件", ["路径": clipped(path, limit: 220)])
            return true
        }

        if lower.contains("read_file") || lower.contains("cat ") || lower.contains("sed -n") || lower.contains("opened file") || clean.contains("读取文件") {
            emitMirrorToolUse("Hermes 读取文件", ["线索": clipped(clean, limit: 220)])
            return true
        }

        if lower.contains("apply_patch") || lower.contains("write_file") || lower.contains("editing") || lower.contains("updated file") || clean.contains("写入") || clean.contains("修改文件") {
            emitMirrorToolUse("Hermes 修改文件", ["线索": clipped(clean, limit: 220)])
            return true
        }

        if lower.contains("search") || lower.contains("ripgrep") || lower.contains("grep") || lower.contains("rg ") || clean.contains("搜索") || clean.contains("查找") {
            emitMirrorToolUse("Hermes 搜索内容", ["线索": clipped(clean, limit: 220)])
            return true
        }

        if lower.contains("waiting") || lower.contains("pending") || lower.contains("clarify") || clean.contains("等待") || clean.contains("需要主人") {
            emitMirrorToolUse("Hermes 等待下一步", ["状态": clipped(clean, limit: 220)])
            return true
        }

        if isDiagnostic && (lower.contains("warning") || clean.contains("警告")) {
            emitMirrorToolUse("Hermes 发现警告", ["日志": clipped(clean, limit: 220)])
            return true
        }

        if isDiagnostic && (lower.contains("error") || clean.contains("失败") || clean.contains("错误")) {
            emitMirrorToolResult("Hermes 日志出现错误：\(clipped(clean, limit: 180))", true)
            return true
        }

        return false
    }

    private func handleHermesOfficialEvent(from text: String) -> Bool {
        guard let event = hermesOfficialEvent(from: text) else { return false }
        let eventType = event.type
        let payload = event.payload

        switch eventType {
        case "approval.request", "approval_requested":
            let command = stringValue(payload["command"]) ?? stringValue(payload["cmd"]) ?? ""
            let detail = stringValue(payload["description"])
                ?? stringValue(payload["reason"])
                ?? stringValue(payload["pattern_key"])
                ?? "Hermes 请求执行需要确认的操作。"
            let id = stringValue(payload["request_id"])
                ?? stringValue(payload["approval_id"])
                ?? stablePermissionID(kind: eventType, command: command, detail: detail)
            let permission = HermesPermissionRequest(
                id: id,
                title: "Hermes 权限确认",
                detail: detail,
                command: command,
                rawText: text,
                allowPermanent: true
            )
            pendingPermissionRequest = permission
            emitMirrorToolUse("Hermes 等待主人确认", [
                "Hermes 事件": eventType,
                "命令": command.isEmpty ? "未捕获命令" : command,
                "说明": detail
            ])
            if permission.id != lastPermissionSignature {
                lastPermissionSignature = permission.id
                onPermissionRequest?(permission)
            }
            return true
        case "clarify.request":
            let question = stringValue(payload["question"]) ?? "Hermes 需要主人补充选择。"
            let choices = stringArrayValue(payload["choices"]).joined(separator: " / ")
            emitMirrorToolUse("Hermes 等待主人选择", [
                "Hermes 事件": eventType,
                "问题": clipped(question, limit: 220),
                "选项": clipped(choices, limit: 220)
            ])
            return true
        case "sudo.request":
            emitMirrorToolUse("Hermes 等待 sudo 密码", [
                "Hermes 事件": eventType,
                "说明": "官方 TUI gateway 的 sudo.request"
            ])
            return true
        case "secret.request":
            let prompt = stringValue(payload["prompt"]) ?? "Hermes 需要密钥/环境变量。"
            let envVar = stringValue(payload["env_var"]) ?? ""
            emitMirrorToolUse("Hermes 等待密钥输入", [
                "Hermes 事件": eventType,
                "提示": clipped(prompt, limit: 220),
                "变量": envVar
            ])
            return true
        case "approval_resolved":
            emitMirrorToolUse("Hermes 权限已处理", [
                "Hermes 事件": eventType,
                "结果": stringValue(payload["decision"]) ?? stringValue(payload["choice"]) ?? "resolved"
            ])
            return true
        default:
            return false
        }
    }

    private func hermesOfficialEventMirror(from text: String) -> (name: String, input: [String: Any])? {
        guard let event = hermesOfficialEvent(from: text) else { return nil }
        let payload = event.payload
        var input: [String: Any] = ["Hermes 事件": event.type]
        if let sessionID = stringValue(event.params["session_id"]) {
            input["会话"] = clipped(sessionID, limit: 80)
        }
        if let tool = stringValue(payload["name"]) ?? stringValue(payload["tool_name"]) ?? stringValue(payload["tool"]) {
            input["工具"] = clipped(tool, limit: 80)
        }
        if let context = stringValue(payload["context"]) ?? stringValue(payload["summary"]) ?? stringValue(payload["text"]) ?? stringValue(payload["delta"]) {
            input["内容"] = clipped(context, limit: 220)
        }
        if let command = stringValue(payload["command"]) ?? stringValue(payload["cmd"]) {
            input["命令"] = clipped(command, limit: 220)
        }
        if let path = stringValue(payload["file_path"]) ?? stringValue(payload["path"]) ?? stringValue(payload["media_path"]) {
            input["产物"] = clipped(path, limit: 220)
        }
        if let url = stringValue(payload["url"]) ?? stringValue(payload["image"]) ?? stringValue(payload["video"]) ?? stringValue(payload["media_url"]) {
            input["媒体"] = clipped(url, limit: 220)
        }
        if let mediaTag = stringValue(payload["media_tag"]) {
            input["媒体标签"] = clipped(mediaTag, limit: 220)
        }
        if let requestID = stringValue(payload["request_id"]) {
            input["请求"] = requestID
        }

        switch event.type {
        case "message.delta":
            return ("Hermes 正在输出", input)
        case "message.complete":
            return ("Hermes 回复完成", input)
        case "thinking.delta", "reasoning.delta":
            return ("Hermes 正在思考", input)
        case "tool.start", "tool.generating":
            return ("Hermes 工具开始", input)
        case "tool.progress":
            return ("Hermes 工具进度", input)
        case "tool.complete":
            return ("Hermes 工具完成", input)
        case "status.update", "session.status":
            return ("Hermes 状态更新", input)
        case "gateway.ready":
            return ("Hermes Gateway 已就绪", input)
        case "message":
            return ("Hermes 收到消息事件", input)
        default:
            if event.type.contains(".") || event.type.hasPrefix("approval_") {
                return ("Hermes 官方事件", input)
            }
            return nil
        }
    }

    private func hermesOfficialEvent(from text: String) -> (type: String, params: [String: Any], payload: [String: Any])? {
        for object in jsonDictionaries(in: text) {
            if let params = object["params"] as? [String: Any],
               let method = object["method"] as? String,
               method == "event",
               let type = params["type"] as? String {
                let payload = params["payload"] as? [String: Any] ?? [:]
                return (type, params, payload)
            }
            if let type = object["type"] as? String,
               ["message", "approval_requested", "approval_resolved"].contains(type) {
                return (type, object, object)
            }
        }
        return nil
    }

    private func jsonDictionaries(in text: String) -> [[String: Any]] {
        let lines = text.components(separatedBy: .newlines)
        var results: [[String: Any]] = []
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { continue }
            if let data = trimmed.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                results.append(object)
            }
        }
        if results.isEmpty,
           let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start < end {
            let raw = String(text[start...end])
            if let data = raw.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                results.append(object)
            }
        }
        return results
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let value as NSNumber:
            return value.stringValue
        case let value as [String: Any]:
            if let text = value["text"] as? String { return text }
            if let command = value["command"] as? String { return command }
            return nil
        default:
            return nil
        }
    }

    private func stringArrayValue(_ value: Any?) -> [String] {
        if let values = value as? [String] { return values }
        if let values = value as? [Any] {
            return values.compactMap { stringValue($0) }
        }
        return []
    }

    private func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "on"].contains(normalized) { return true }
            if ["0", "false", "no", "off"].contains(normalized) { return false }
            return nil
        default:
            return nil
        }
    }

    private func stablePermissionID(kind: String, command: String, detail: String) -> String {
        "\(kind)|\(command)|\(detail)".unicodeScalars.reduce(UInt64(1469598103934665603)) { hash, scalar in
            (hash ^ UInt64(scalar.value)) &* 1099511628211
        }.description
    }

    private func hermesTerminalStatus(from text: String) -> [String: Any]? {
        guard text.contains("│"),
              text.contains("%") || text.contains("░") || text.contains("█") else { return nil }
        let pattern = #"⚕?\s*([A-Za-z0-9_.:/-]+)\s*│\s*([^│]+?)\s*│.*?([0-9]{1,3})%"#
        guard let captures = firstCaptureGroups(in: text, pattern: pattern),
              captures.count >= 3 else { return nil }
        let model = captures[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let context = captures[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let progress = captures[2].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return nil }
        return [
            "模型": clipped(model, limit: 80),
            "上下文": clipped(context, limit: 40),
            "进度": "\(progress)%"
        ]
    }

    private func hermesToolMirror(from text: String) -> (name: String, input: [String: Any])? {
        let lower = text.lowercased()
        let tool = firstKeyedValue(in: text, keys: ["tool_name", "tool", "name"])
            ?? firstMatch(in: text, pattern: #"(?im)^\s*(?:calling|invoking|using)\s+tool\s*[:：]?\s*([A-Za-z0-9_.:-]+)"#)
            ?? firstMatch(in: text, pattern: #"(?im)^\s*(?:调用工具|使用工具|工具)\s*[:：]\s*([A-Za-z0-9_.:-]+)"#)
        let command = firstKeyedValue(in: text, keys: ["command", "cmd", "shell_command"])
            ?? firstArrayValue(in: text, keys: ["cmd", "command", "args"])
            ?? firstMatch(in: text, pattern: #"(?im)^\s*(?:running|executing|execute|command|shell|bash|zsh|运行|执行命令|命令)[:：]\s*(.+)$"#)
        let path = firstKeyedValue(in: text, keys: ["file_path", "filepath", "path", "abs_path", "filename", "target_file"])
            ?? firstPathLikeValue(in: text)
        let query = firstKeyedValue(in: text, keys: ["query", "pattern", "search", "regex"])
        let url = firstKeyedValue(in: text, keys: ["url", "uri"])
        let action = firstKeyedValue(in: text, keys: ["action", "operation", "description"])

        var input: [String: Any] = [:]
        if let tool, !tool.isEmpty { input["工具"] = clipped(tool, limit: 80) }
        if let command, !command.isEmpty { input["命令"] = clipped(command, limit: 220) }
        if let path, !path.isEmpty { input["路径"] = clipped(path, limit: 220) }
        if let query, !query.isEmpty { input["查询"] = clipped(query, limit: 160) }
        if let url, !url.isEmpty { input["网址"] = clipped(url, limit: 180) }
        if let action, !action.isEmpty { input["动作"] = clipped(action, limit: 160) }
        if input.isEmpty { return nil }

        let combined = ([tool, command, path, query, url, action].compactMap { $0 }.joined(separator: " ") + " " + lower).lowercased()
        if containsAny(combined, ["apply_patch", "write", "edit", "patch", "create_file", "delete", "rename", "move", "修改", "写入", "删除"]) {
            return ("Hermes 修改文件", input)
        }
        if containsAny(combined, ["rg ", "ripgrep", "grep", "search", "find", "glob", "query", "搜索", "查找"]) {
            return ("Hermes 搜索内容", input)
        }
        if containsAny(combined, ["read", "open_file", "cat ", "sed -n", "list_dir", "ls ", "view", "读取", "打开文件"]) {
            return ("Hermes 读取文件", input)
        }
        if containsAny(combined, ["exec", "terminal", "shell", "bash", "zsh", "run_command", "command", "执行命令", "运行"]) {
            return ("Hermes 执行命令", input)
        }
        if containsAny(combined, ["web", "browser", "url", "http://", "https://", "网页", "联网", "搜索网页"]) {
            return ("Hermes 浏览网页", input)
        }
        if containsAny(combined, ["computer", "click", "keypress", "mouse", "screenshot", "电脑", "点击", "截图"]) {
            return ("Hermes 操作电脑", input)
        }
        if containsAny(combined, ["memory", "remember", "memo", "备忘录", "记忆", "记住"]) {
            return containsAny(combined, ["write", "append", "remember", "写入", "记住"])
                ? ("Hermes 写入记忆", input)
                : ("Hermes 读取记忆", input)
        }
        if let tool, !tool.isEmpty {
            input["线索"] = clipped(text, limit: 220)
            return ("Hermes 调用工具", input)
        }
        return nil
    }

    private func firstKeyedValue(in text: String, keys: [String]) -> String? {
        for key in keys {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let patterns = [
                #""\#(escaped)"\s*:\s*"((?:\\.|[^"\\])*)""#,
                #""\#(escaped)"\s*:\s*'([^']*)'"#,
                #"(?im)^\s*\#(escaped)\s*[:=]\s*(.+)$"#
            ]
            for pattern in patterns {
                if let value = firstMatch(in: text, pattern: pattern)?
                    .replacingOccurrences(of: #"\""#, with: "\"")
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private func firstArrayValue(in text: String, keys: [String]) -> String? {
        for key in keys {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let pattern = #""\#(escaped)"\s*:\s*\[([^\]]+)\]"#
            guard let raw = firstMatch(in: text, pattern: pattern) else { continue }
            let cleaned = raw
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: ",", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    private func firstPathLikeValue(in text: String) -> String? {
        let patterns = [
            #"(/Users/[^\s"'`]+)"#,
            #"(\./[^\s"'`]+)"#,
            #"(\~/[^\s"'`]+)"#
        ]
        for pattern in patterns {
            if let value = firstMatch(in: text, pattern: pattern) {
                return value
            }
        }
        return nil
    }

    private func containsAny(_ text: String, _ markers: [String]) -> Bool {
        markers.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func isPTYChromeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if trimmed == "❯" { return true }
        if trimmed.hasPrefix("⚕ ❯") || trimmed.contains("msg=interrupt") || trimmed.contains("Ctrl+C cancel") {
            return true
        }
        if trimmed.contains("│"),
           (trimmed.contains("░") || trimmed.contains("█")),
           trimmed.contains("%") {
            return true
        }
        let borderScalars = CharacterSet(charactersIn: "─━│┃╭╮╰╯┌┐└┘├┤┬┴┼ ")
        let scalars = trimmed.unicodeScalars.filter { !$0.properties.isWhitespace }
        if !scalars.isEmpty && scalars.allSatisfy({ borderScalars.contains($0) }) {
            return true
        }
        return false
    }

    private func emitMirrorToolUse(_ name: String, _ input: [String: Any]) {
        let signature = "\(name)|\(input.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "&"))"
        let now = Date()
        if signature == lastMirrorSignature && now.timeIntervalSince(lastMirrorAt) < 2.5 {
            return
        }
        lastMirrorSignature = signature
        lastMirrorAt = now
        let summary = input
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: "\n")
        history.append(AgentMessage(role: .toolUse, text: summary.isEmpty ? name : "\(name)\n\(summary)"))
        persistPendingTranscript()
        onToolUse?(name, input)
    }

    private func emitMirrorToolResult(_ summary: String, _ isError: Bool) {
        let clean = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = isError ? "工具失败" : "工具完成"
        history.append(AgentMessage(role: .toolResult, text: clean.isEmpty ? title : "\(title)\n\(clean)"))
        persistPendingTranscript()
        onToolResult?(clean.isEmpty ? title : clean, isError)
    }

    private func stripANSI(_ text: String) -> String {
        var cleaned = text
        let patterns = [
            "\u{001B}\\][^\u{0007}\u{001B}]*(?:\u{0007}|\u{001B}\\\\)",
            "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            "\u{001B}[()][A-Za-z0-9]",
            "\u{001B}[@-Z\\\\-_]"
        ]
        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        let controls = CharacterSet(charactersIn: "\u{0000}\u{0001}\u{0002}\u{0003}\u{0004}\u{0005}\u{0006}\u{0007}\u{0008}\u{000B}\u{000C}\u{000E}\u{000F}")
        return cleaned.components(separatedBy: controls).joined()
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              match.range(at: 1).location != NSNotFound,
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    private func firstCaptureGroups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }

        var captures: [String] = []
        for index in 1..<match.numberOfRanges {
            let captureRange = match.range(at: index)
            guard captureRange.location != NSNotFound,
                  let range = Range(captureRange, in: text) else {
                captures.append("")
                continue
            }
            captures.append(String(text[range]))
        }
        return captures
    }

    private func extractSessionID(from text: String) -> String? {
        for rawLine in text.split(separator: "\n").reversed() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()
            if lower.hasPrefix("session_id:") {
                return line
                    .dropFirst("session_id:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if lower.hasPrefix("session id:") {
                return line
                    .dropFirst("session id:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func stableID(for text: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }

    private func clipped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "..."
    }
}

// MARK: - Hermes Config + Conversation Store

struct HermesConfigSnapshot {
    let model: String
    let provider: String
    let baseURL: String
    let reasoningEffort: String
    let imageGenProvider: String
    let imageGenModel: String
    let videoGenProvider: String
    let videoGenModel: String
    let ttsProvider: String
    let ttsVoice: String
    let sttProvider: String
    let configURL: URL
}

struct HermesThreadSummary {
    let id: String
    let title: String
    let preview: String
    let updatedAt: TimeInterval
    let model: String
    let provider: String
    let source: String
    let messageCount: Int
}

struct HermesSlashCommand {
    let name: String
    let description: String
    let category: String
    let aliases: [String]
    let argsHint: String
    let subcommands: [String]
    let cliOnly: Bool
    let gatewayOnly: Bool

    init(
        name: String,
        description: String,
        category: String,
        aliases: [String],
        argsHint: String,
        subcommands: [String],
        cliOnly: Bool = false,
        gatewayOnly: Bool = false
    ) {
        self.name = name
        self.description = description
        self.category = category
        self.aliases = aliases
        self.argsHint = argsHint
        self.subcommands = subcommands
        self.cliOnly = cliOnly
        self.gatewayOnly = gatewayOnly
    }

    var slash: String { "/\(name)" }

    func matches(prefix: String) -> Bool {
        let clean = prefix.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return name.lowercased().hasPrefix(clean) || aliases.contains { $0.lowercased().hasPrefix(clean) }
    }
}

struct HermesToolEntry {
    let name: String
    let toolset: String
    let sourceFile: String
}

struct HermesModelOption {
    let provider: String
    let id: String
    let name: String
    let baseURL: String
    let context: Int
    let reasoning: Bool

    var displayTitle: String {
        name.isEmpty ? id : name
    }

    var payload: String {
        "__hermes_model:\(provider)|\(id)|\(baseURL)"
    }
}

final class HermesCatalog {
    static let shared = HermesCatalog()

    private let hermesHome: URL

    private init() {
        if let home = ProcessInfo.processInfo.environment["HERMES_HOME"],
           !home.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hermesHome = URL(fileURLWithPath: home, isDirectory: true)
        } else {
            hermesHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes")
        }
    }

    func syncSignature() -> String {
        let paths = [
            hermesHome.appendingPathComponent("hermes-agent/hermes_cli/commands.py"),
            hermesHome.appendingPathComponent("models_dev_cache.json"),
            hermesHome.appendingPathComponent("cache/model_catalog.json"),
            hermesHome.appendingPathComponent("config.yaml"),
            hermesHome.appendingPathComponent("skills"),
            hermesHome.appendingPathComponent("state.db")
        ]
        return paths.map { "\($0.lastPathComponent):\(modificationToken(for: $0))" }.joined(separator: "|")
    }

    func suggestions(for text: String, limit: Int = 7) -> [InputSuggestion] {
        let raw = text.trimmingCharacters(in: .newlines)
        guard raw.hasPrefix("/") else { return [] }

        let commandToken = firstToken(in: raw)
        let commandName = String(commandToken.dropFirst()).lowercased()
        let argumentText = raw.dropFirst(commandToken.count).trimmingCharacters(in: .whitespaces)
        let hasArgumentPosition = raw.count > commandToken.count
        let resolved = resolveSlashCommand(commandName)

        if hasArgumentPosition, resolved?.name == "model" {
            return modelSuggestions(query: argumentText, limit: limit)
        }
        if hasArgumentPosition, resolved?.name == "skin", !argumentText.contains(where: { $0 == " " || $0 == "\t" }) {
            return skinSuggestions(command: commandToken, query: argumentText, limit: limit)
        }
        if hasArgumentPosition, resolved?.name == "personality", !argumentText.contains(where: { $0 == " " || $0 == "\t" }) {
            return personalitySuggestions(command: commandToken, query: argumentText, limit: limit)
        }
        if hasArgumentPosition, let name = resolved?.name, name == "sessions" || name == "resume" {
            return sessionSuggestions(command: commandToken, query: argumentText, limit: limit)
        }

        if hasArgumentPosition, let command = resolved, !argumentText.contains(where: { $0 == " " || $0 == "\t" }) {
            let query = argumentText.lowercased()
            let subcommands = command.subcommands
                .filter { query.isEmpty || ($0.lowercased().hasPrefix(query) && $0.lowercased() != query) }
                .prefix(limit)
            if !subcommands.isEmpty {
                return subcommands.map {
                    InputSuggestion(
                        title: "\(command.slash) \($0)",
                        subtitle: command.description,
                        replacement: "\(commandToken) \($0)"
                    )
                }
            }
        }

        let typedWord = commandName
        return commandCompletionEntries()
            .filter { entry in entry.token.lowercased().hasPrefix(typedWord) }
            .prefix(limit)
            .map { entry in
                let command = entry.command
                let aliasText = entry.isAlias ? " · alias for /\(command.name)" : aliasSummary(for: command)
                let replacement = "/\(completionText(commandName: entry.token, typedWord: typedWord))"
                let args = command.argsHint.isEmpty ? "" : " \(command.argsHint)"
                return InputSuggestion(
                    title: "/\(entry.token)\(args)",
                    subtitle: "\(command.category) · \(command.description)\(aliasText)",
                    replacement: replacement
                )
            }
    }

    func quickModelOptions(limit: Int = 4) -> [HermesModelOption] {
        let config = HermesConfig.shared.snapshot
        var models = modelOptions(provider: config.provider)
            .filter(isLikelyChatModel)
        if models.isEmpty {
            return [
                HermesModelOption(provider: config.provider, id: config.model, name: config.model, baseURL: config.baseURL, context: 0, reasoning: false)
            ]
        }

        models.sort { left, right in
            if left.id == config.model { return true }
            if right.id == config.model { return false }
            let leftPriority = quickModelPriority(left)
            let rightPriority = quickModelPriority(right)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            if left.reasoning != right.reasoning { return left.reasoning && !right.reasoning }
            if left.context != right.context { return left.context > right.context }
            return left.id < right.id
        }

        var picked: [HermesModelOption] = []
        for model in models where !picked.contains(where: { $0.id == model.id }) {
            picked.append(model)
            if picked.count >= limit { break }
        }
        return picked
    }

    func slashCommands() -> [HermesSlashCommand] {
        let commands = parseCommandRegistry()
        if !commands.isEmpty { return commands }
        return fallbackSlashCommands()
    }

    func registeredTools() -> [HermesToolEntry] {
        let toolsRoot = hermesHome
            .appendingPathComponent("hermes-agent")
            .appendingPathComponent("tools", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: toolsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [HermesToolEntry] = []
        for case let file as URL in enumerator {
            guard file.pathExtension == "py",
                  let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for block in callBlocks(named: "registry.register", in: text) {
                guard let name = stringArgument(named: "name", in: block), !name.isEmpty else { continue }
                entries.append(HermesToolEntry(
                    name: name,
                    toolset: stringArgument(named: "toolset", in: block) ?? "default",
                    sourceFile: file.lastPathComponent
                ))
            }
        }

        var seen: Set<String> = []
        return entries
            .filter { seen.insert("\($0.toolset)|\($0.name)").inserted }
            .sorted {
                if $0.toolset != $1.toolset { return $0.toolset < $1.toolset }
                return $0.name < $1.name
            }
    }

    func mediaCapabilityLines() -> [String] {
        let config = HermesConfig.shared.snapshot
        let tools = Set(registeredTools().map(\.name))
        return [
            "图像创作能力：`image_generate` \(tools.contains("image_generate") ? "已注册" : "未注册")；provider=\(config.imageGenProvider.isEmpty ? "未配置" : config.imageGenProvider)，model=\(config.imageGenModel.isEmpty ? "默认" : config.imageGenModel)",
            "视频创作能力：`video_generate` \(tools.contains("video_generate") ? "已注册" : "未注册")；provider=\(config.videoGenProvider.isEmpty ? "未配置" : config.videoGenProvider)，model=\(config.videoGenModel.isEmpty ? "默认" : config.videoGenModel)",
            "文字转语音能力：`text_to_speech` \(tools.contains("text_to_speech") ? "已注册" : "未注册")；provider=\(config.ttsProvider.isEmpty ? "未配置" : config.ttsProvider)，voice=\(config.ttsVoice.isEmpty ? "默认" : config.ttsVoice)",
            "语音输入能力：`voice.toggle` / `voice.record` / `voice.transcript`；STT provider=\(config.sttProvider.isEmpty ? "未配置" : config.sttProvider)"
        ]
    }

    private func firstToken(in text: String) -> String {
        guard let space = text.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return text
        }
        return String(text[..<space])
    }

    private func interactiveSlashCommands() -> [HermesSlashCommand] {
        slashCommands().filter { !$0.gatewayOnly }
    }

    private func commandCompletionEntries() -> [(token: String, command: HermesSlashCommand, isAlias: Bool)] {
        var entries: [(String, HermesSlashCommand, Bool)] = []
        for command in interactiveSlashCommands() {
            entries.append((command.name, command, false))
            for alias in command.aliases {
                entries.append((alias, command, true))
            }
        }
        entries.append(contentsOf: quickCommandEntries())
        entries.append(contentsOf: skillCommandEntries())
        return entries
    }

    private func resolveSlashCommand(_ rawName: String) -> HermesSlashCommand? {
        let clean = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard !clean.isEmpty else { return nil }
        let commands = interactiveSlashCommands()

        for command in commands where command.name.lowercased() == clean {
            return command
        }
        for command in commands where command.aliases.contains(where: { $0.lowercased() == clean }) {
            return command
        }
        for command in commands where command.name.lowercased().hasPrefix(clean) {
            return command
        }
        for command in commands where command.aliases.contains(where: { $0.lowercased().hasPrefix(clean) }) {
            return command
        }
        return nil
    }

    private func completionText(commandName: String, typedWord: String) -> String {
        let pickerCommands: Set<String> = ["model", "skin", "personality"]
        if commandName != typedWord {
            return commandName
        }
        if pickerCommands.contains(commandName) {
            return commandName
        }
        return "\(commandName) "
    }

    private func aliasSummary(for command: HermesSlashCommand) -> String {
        guard !command.aliases.isEmpty else { return "" }
        return " · alias: " + command.aliases.map { "/\($0)" }.joined(separator: ", ")
    }

    private func quickCommandEntries() -> [(token: String, command: HermesSlashCommand, isAlias: Bool)] {
        let text = (try? String(contentsOf: HermesConfig.shared.configURL, encoding: .utf8)) ?? ""
        return yamlMappingKeys(section: "quick_commands", in: text).map { rawName in
            let name = normalizedCommandName(rawName)
            let command = HermesSlashCommand(
                name: name,
                description: "Hermes quick command",
                category: "Quick Commands",
                aliases: [],
                argsHint: "[text]",
                subcommands: []
            )
            return (name, command, false)
        }
    }

    private func skillCommandEntries() -> [(token: String, command: HermesSlashCommand, isAlias: Bool)] {
        let skillsRoot = hermesHome.appendingPathComponent("skills")
        guard let enumerator = FileManager.default.enumerator(
            at: skillsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var seen: Set<String> = []
        var entries: [(String, HermesSlashCommand, Bool)] = []
        for case let file as URL in enumerator {
            guard file.lastPathComponent == "SKILL.md" else { continue }
            let parts = Set(file.pathComponents)
            if !parts.intersection([".git", ".github", ".hub", ".archive"]).isEmpty {
                continue
            }
            let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let displayName = frontmatterValue("name", in: content)
                ?? file.deletingLastPathComponent().lastPathComponent
            let commandName = normalizedSkillCommandName(displayName)
            guard !commandName.isEmpty, seen.insert(commandName).inserted else { continue }
            let description = frontmatterValue("description", in: content)
                ?? firstMarkdownBodyLine(in: content)
                ?? "Invoke the \(displayName) skill"
            let command = HermesSlashCommand(
                name: commandName,
                description: description,
                category: "Skill",
                aliases: [],
                argsHint: "[instruction]",
                subcommands: []
            )
            entries.append((commandName, command, false))
        }
        return entries.sorted { $0.0 < $1.0 }
    }

    private func normalizedCommandName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    private func normalizedSkillCommandName(_ raw: String) -> String {
        normalizedCommandName(raw)
            .replacingOccurrences(of: #"[^a-z0-9-]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func frontmatterValue(_ key: String, in content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return nil }
        for rawLine in lines.dropFirst() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "---" { return nil }
            guard line.hasPrefix("\(key):") else { continue }
            return line
                .dropFirst(key.count + 1)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    private func firstMarkdownBodyLine(in content: String) -> String? {
        let hasFrontmatter = content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---")
        var fenceCount = 0
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "---" {
                fenceCount += 1
                continue
            }
            let inBody = hasFrontmatter ? fenceCount >= 2 : true
            guard inBody, !line.isEmpty, !line.hasPrefix("#") else { continue }
            return String(line.prefix(80))
        }
        return nil
    }

    private func yamlMappingKeys(section: String, in text: String) -> [String] {
        let block = sectionBlock(named: section, in: text)
        var keys: [String] = []
        for rawLine in block {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("-") else { continue }
            guard indentationLevel(rawLine) <= 2, let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty {
                keys.append(key)
            }
        }
        return keys
    }

    private func sectionBlock(named section: String, in text: String) -> [String] {
        var inSection = false
        var result: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if !inSection {
                if indentationLevel(rawLine) == 0 && trimmed == "\(section):" {
                    inSection = true
                }
                continue
            }
            if indentationLevel(rawLine) == 0 && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                break
            }
            result.append(rawLine)
        }
        return result
    }

    private func indentationLevel(_ line: String) -> Int {
        var count = 0
        for char in line {
            if char == " " {
                count += 1
            } else if char == "\t" {
                count += 2
            } else {
                break
            }
        }
        return count
    }

    func modelOptions(provider preferredProvider: String? = nil) -> [HermesModelOption] {
        let config = HermesConfig.shared.snapshot
        let provider = normalizedProviderName(preferredProvider ?? config.provider)
        let url = hermesHome.appendingPathComponent("models_dev_cache.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providerNode = root[provider] as? [String: Any],
              let models = providerNode["models"] as? [String: Any] else {
            return []
        }

        let baseURL = (providerNode["api"] as? String) ?? config.baseURL
        return models.compactMap { _, raw -> HermesModelOption? in
            guard let info = raw as? [String: Any],
                  let id = info["id"] as? String else { return nil }
            let name = info["name"] as? String ?? id
            let limit = info["limit"] as? [String: Any]
            let context = limit?["context"] as? Int
                ?? Int(limit?["context"] as? Double ?? 0)
            let reasoning = info["reasoning"] as? Bool ?? false
            return HermesModelOption(
                provider: provider,
                id: id,
                name: name,
                baseURL: baseURL,
                context: context,
                reasoning: reasoning
            )
        }
        .sorted { left, right in
            if left.reasoning != right.reasoning { return left.reasoning && !right.reasoning }
            if left.context != right.context { return left.context > right.context }
            return left.id < right.id
        }
    }

    private func isLikelyChatModel(_ model: HermesModelOption) -> Bool {
        let lower = "\(model.id) \(model.name)".lowercased()
        let blocked = ["image", "video", "vision", "tts", "whisper", "embedding", "audio"]
        return !blocked.contains { lower.contains($0) }
    }

    private func quickModelPriority(_ model: HermesModelOption) -> Int {
        let id = model.id.lowercased()
        let preferred = [
            "grok-4.3",
            "grok-4.20-0309-reasoning",
            "grok-4.20-0309-non-reasoning",
            "grok-4.20-multi-agent-0309",
            "grok-4-1-fast-reasoning",
            "grok-4-1-fast-non-reasoning",
            "grok-4",
            "grok-2-latest"
        ]
        if let idx = preferred.firstIndex(where: { id == $0 || id.contains($0) }) {
            return idx
        }
        if id.contains("grok-4") { return 20 }
        if id.contains("grok") { return 30 }
        return 100
    }

    private func modelSuggestions(query: String, limit: Int) -> [InputSuggestion] {
        if let providerQuery = modelProviderQuery(from: query) {
            return providerSuggestions(query: providerQuery, originalQuery: query, limit: limit)
        }

        let modelQuery = modelNameQuery(from: query)
        let needle = modelQuery.lowercased()
        var suggestions: [InputSuggestion] = []
        suggestions.append(contentsOf: modelAliasSuggestions(query: modelQuery, limit: limit))
        suggestions.append(contentsOf: modelOptions(provider: HermesConfig.shared.snapshot.provider)
            .filter { model in
                needle.isEmpty
                    || model.id.lowercased().contains(needle)
                    || model.name.lowercased().contains(needle)
            }
            .map { model in
                let ctx = model.context > 0 ? " · \(formatContext(model.context)) ctx" : ""
                let reasoning = model.reasoning ? " · reasoning" : ""
                return InputSuggestion(
                    title: model.id,
                    subtitle: "\(model.displayTitle)\(ctx)\(reasoning)",
                    replacement: modelReplacement(model.id, originalQuery: query)
                )
            })
        suggestions.append(contentsOf: ["--provider", "--global"]
            .filter { needle.isEmpty || $0.hasPrefix(needle) }
            .map { flag in
                InputSuggestion(
                    title: "/model \(flag)",
                    subtitle: flag == "--global" ? "Persist model change to config.yaml" : "Switch provider for this invocation",
                    replacement: appendModelToken(flag, originalQuery: query)
                )
            })
        return dedupeSuggestions(suggestions).prefix(limit).map { $0 }
    }

    private func modelProviderQuery(from query: String) -> String? {
        let tokens = tokenizeCommand(query)
        for index in tokens.indices {
            let token = tokens[index]
            let lower = token.lowercased()
            if lower == "--provider" {
                if tokens.indices.contains(index + 1), !query.hasSuffix(" ") {
                    return tokens[index + 1]
                }
                return ""
            }
            if lower.hasPrefix("--provider=") {
                return String(token.dropFirst("--provider=".count))
            }
        }
        return nil
    }

    private func providerSuggestions(query: String, originalQuery: String, limit: Int) -> [InputSuggestion] {
        let needle = query.lowercased()
        return providerNames()
            .filter { needle.isEmpty || $0.lowercased().hasPrefix(needle) }
            .prefix(limit)
            .map { provider in
                InputSuggestion(
                    title: "--provider \(provider)",
                    subtitle: "Hermes provider",
                    replacement: providerReplacement(provider, originalQuery: originalQuery)
                )
            }
    }

    private func modelNameQuery(from query: String) -> String {
        let tokens = tokenizeCommand(query)
        guard let last = tokens.last, !query.hasSuffix(" ") else { return "" }
        return last
    }

    private func modelAliasSuggestions(query: String, limit: Int) -> [InputSuggestion] {
        let needle = query.lowercased()
        var suggestions: [InputSuggestion] = []

        for alias in directModelAliases() {
            guard needle.isEmpty || (alias.name.hasPrefix(needle) && alias.name != needle) else { continue }
            suggestions.append(InputSuggestion(
                title: alias.name,
                subtitle: "\(alias.model) (\(alias.provider))",
                replacement: modelReplacement(alias.name, originalQuery: query)
            ))
        }

        let directNames = Set(directModelAliases().map(\.name))
        for alias in builtinModelAliases() where !directNames.contains(alias.name) {
            guard needle.isEmpty || (alias.name.hasPrefix(needle) && alias.name != needle) else { continue }
            suggestions.append(InputSuggestion(
                title: alias.name,
                subtitle: "\(alias.vendor)/\(alias.family)",
                replacement: modelReplacement(alias.name, originalQuery: query)
            ))
        }

        return Array(dedupeSuggestions(suggestions).prefix(limit))
    }

    private func modelReplacement(_ model: String, originalQuery: String) -> String {
        var tokens = tokenizeCommand(originalQuery)
        var replaced = false
        var index = 0
        while index < tokens.count {
            let lower = tokens[index].lowercased()
            if lower == "--provider" {
                index += 2
                continue
            }
            if lower == "--global" || lower.hasPrefix("--provider=") || lower.hasPrefix("-") {
                index += 1
                continue
            }
            tokens[index] = model
            replaced = true
            break
        }
        if !replaced {
            tokens.insert(model, at: 0)
        }
        return "/model \(tokens.joined(separator: " "))"
    }

    private func providerReplacement(_ provider: String, originalQuery: String) -> String {
        var tokens = tokenizeCommand(originalQuery)
        var replaced = false
        var index = 0
        while index < tokens.count {
            let lower = tokens[index].lowercased()
            if lower == "--provider" {
                if tokens.indices.contains(index + 1) {
                    tokens[index + 1] = provider
                } else {
                    tokens.append(provider)
                }
                replaced = true
                break
            }
            if lower.hasPrefix("--provider=") {
                tokens[index] = "--provider=\(provider)"
                replaced = true
                break
            }
            index += 1
        }
        if !replaced {
            tokens.append(contentsOf: ["--provider", provider])
        }
        return "/model \(tokens.joined(separator: " "))"
    }

    private func appendModelToken(_ token: String, originalQuery: String) -> String {
        var tokens = tokenizeCommand(originalQuery)
        if let last = tokens.indices.last,
           tokens[last].hasPrefix("-"),
           !originalQuery.hasSuffix(" ") {
            tokens[last] = token
        } else if !tokens.contains(token) {
            tokens.append(token)
        }
        let suffix = token == "--provider" ? " " : ""
        return "/model \(tokens.joined(separator: " "))\(suffix)"
    }

    private func tokenizeCommand(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        for char in text {
            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                } else {
                    current.append(char)
                }
                continue
            }
            if char == "\"" || char == "'" || char == "`" {
                quote = char
            } else if char == " " || char == "\t" {
                flush()
            } else {
                current.append(char)
            }
        }
        flush()
        return tokens
    }

    private func dedupeSuggestions(_ suggestions: [InputSuggestion]) -> [InputSuggestion] {
        var seen: Set<String> = []
        var result: [InputSuggestion] = []
        for suggestion in suggestions {
            let key = "\(suggestion.replacement)|\(suggestion.title)"
            guard seen.insert(key).inserted else { continue }
            result.append(suggestion)
        }
        return result
    }

    private func providerNames() -> [String] {
        var names: Set<String> = []
        let current = normalizedProviderName(HermesConfig.shared.snapshot.provider)
        if !current.isEmpty { names.insert(current) }

        let catalogURL = hermesHome.appendingPathComponent("models_dev_cache.json")
        if let data = try? Data(contentsOf: catalogURL),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in root.keys {
                let normalized = normalizedProviderName(key)
                if !normalized.isEmpty { names.insert(normalized) }
            }
        }

        for alias in directModelAliases() {
            let normalized = normalizedProviderName(alias.provider)
            if !normalized.isEmpty { names.insert(normalized) }
        }
        for alias in builtinModelAliases() {
            let normalized = normalizedProviderName(alias.vendor)
            if !normalized.isEmpty { names.insert(normalized) }
        }

        return names.sorted { left, right in
            if left == current { return true }
            if right == current { return false }
            return left < right
        }
    }

    private func normalizedProviderName(_ provider: String) -> String {
        let clean = provider
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        if clean == "x.ai" || clean == "x-ai" || clean == "xai" { return "xai" }
        return clean
    }

    private func directModelAliases() -> [(name: String, model: String, provider: String)] {
        let text = (try? String(contentsOf: HermesConfig.shared.configURL, encoding: .utf8)) ?? ""
        var aliases: [(String, String, String)] = []

        let block = sectionBlock(named: "model_aliases", in: text)
        var currentName = ""
        var currentModel = ""
        var currentProvider = "custom"
        func flushCurrent() {
            guard !currentName.isEmpty, !currentModel.isEmpty else { return }
            aliases.append((currentName.lowercased(), currentModel, currentProvider))
        }

        for rawLine in block {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if indentationLevel(rawLine) <= 2, trimmed.hasSuffix(":") {
                flushCurrent()
                currentName = String(trimmed.dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                currentModel = ""
                currentProvider = "custom"
                continue
            }
            if trimmed.hasPrefix("model:") {
                currentModel = yamlScalar(after: "model:", in: trimmed)
            } else if trimmed.hasPrefix("provider:") {
                currentProvider = yamlScalar(after: "provider:", in: trimmed)
            }
        }
        flushCurrent()

        aliases.append(contentsOf: simpleModelAliases(from: text))
        var seen: Set<String> = []
        return aliases.filter { seen.insert($0.0).inserted }
    }

    private func simpleModelAliases(from text: String) -> [(name: String, model: String, provider: String)] {
        let config = HermesConfig.shared.snapshot
        var aliases: [(String, String, String)] = []
        var inModel = false
        var inAliases = false

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let indent = indentationLevel(rawLine)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            if indent == 0 {
                inModel = trimmed == "model:"
                inAliases = false
                continue
            }
            if inModel, indent == 2 {
                inAliases = trimmed == "aliases:"
                continue
            }
            guard inModel, inAliases, indent >= 4, let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .lowercased()
            let value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !key.isEmpty, !value.isEmpty else { continue }
            if let slash = value.firstIndex(of: "/") {
                let provider = String(value[..<slash])
                let model = String(value[value.index(after: slash)...])
                aliases.append((key, model, provider))
            } else {
                aliases.append((key, value, config.provider))
            }
        }
        return aliases
    }

    private func builtinModelAliases() -> [(name: String, vendor: String, family: String)] {
        let url = hermesHome
            .appendingPathComponent("hermes-agent")
            .appendingPathComponent("hermes_cli")
            .appendingPathComponent("model_switch.py")
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let regex = try? NSRegularExpression(
                pattern: #""([^"]+)"\s*:\s*ModelIdentity\("([^"]+)",\s*"([^"]+)"\)"#,
                options: []
              ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: text),
                  let vendorRange = Range(match.range(at: 2), in: text),
                  let familyRange = Range(match.range(at: 3), in: text) else { return nil }
            return (
                String(text[nameRange]).lowercased(),
                String(text[vendorRange]),
                String(text[familyRange])
            )
        }.sorted { $0.name < $1.name }
    }

    private func yamlScalar(after key: String, in line: String) -> String {
        line.dropFirst(key.count)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private func skinSuggestions(command: String, query: String, limit: Int) -> [InputSuggestion] {
        let needle = query.lowercased()
        return availableSkins()
            .filter { needle.isEmpty || ($0.name.lowercased().hasPrefix(needle) && $0.name.lowercased() != needle) }
            .prefix(limit)
            .map { skin in
                InputSuggestion(
                    title: "\(command) \(skin.name)",
                    subtitle: skin.description.isEmpty ? "Hermes skin" : skin.description,
                    replacement: "\(command) \(skin.name)"
                )
            }
    }

    private func personalitySuggestions(command: String, query: String, limit: Int) -> [InputSuggestion] {
        let needle = query.lowercased()
        return availablePersonalities()
            .filter { needle.isEmpty || ($0.name.lowercased().hasPrefix(needle) && $0.name.lowercased() != needle) }
            .prefix(limit)
            .map { personality in
                InputSuggestion(
                    title: "\(command) \(personality.name)",
                    subtitle: personality.description,
                    replacement: "\(command) \(personality.name)"
                )
            }
    }

    private func availableSkins() -> [(name: String, description: String)] {
        var skins: [(String, String)] = []
        let skinEngineURL = hermesHome
            .appendingPathComponent("hermes-agent")
            .appendingPathComponent("hermes_cli")
            .appendingPathComponent("skin_engine.py")
        if let text = try? String(contentsOf: skinEngineURL, encoding: .utf8),
           let regex = try? NSRegularExpression(pattern: #"(?m)^    "([^"]+)":\s*\{"#, options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            skins.append(contentsOf: regex.matches(in: text, options: [], range: range).compactMap { match in
                guard let nameRange = Range(match.range(at: 1), in: text) else { return nil }
                let name = String(text[nameRange])
                return (name, "Hermes built-in skin")
            })
        }

        let userSkins = hermesHome.appendingPathComponent("skins")
        if let files = try? FileManager.default.contentsOfDirectory(at: userSkins, includingPropertiesForKeys: nil) {
            for file in files where ["yaml", "yml"].contains(file.pathExtension.lowercased()) {
                let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                let name = yamlTopLevelValue("name", in: content) ?? file.deletingPathExtension().lastPathComponent
                let description = yamlTopLevelValue("description", in: content) ?? "User skin"
                skins.append((name, description))
            }
        }

        var seen: Set<String> = []
        return skins.filter { seen.insert($0.0).inserted }.sorted { $0.0 < $1.0 }
    }

    private func availablePersonalities() -> [(name: String, description: String)] {
        let text = (try? String(contentsOf: HermesConfig.shared.configURL, encoding: .utf8)) ?? ""
        var personalities: [(String, String)] = [("none", "clear personality overlay")]
        personalities.append(contentsOf: nestedAgentPersonalities(in: text))
        personalities.append(contentsOf: yamlMappingKeys(section: "personalities", in: text).map { ($0, "Hermes personality") })
        var seen: Set<String> = []
        return personalities.filter { seen.insert($0.0).inserted }.sorted { $0.0 < $1.0 }
    }

    private func nestedAgentPersonalities(in text: String) -> [(name: String, description: String)] {
        var inAgent = false
        var inPersonalities = false
        var result: [(String, String)] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let indent = indentationLevel(rawLine)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            if indent == 0 {
                inAgent = trimmed == "agent:"
                inPersonalities = false
                continue
            }
            if inAgent, indent == 2 {
                inPersonalities = trimmed == "personalities:"
                continue
            }
            guard inAgent, inPersonalities, indent == 4, let colon = trimmed.firstIndex(of: ":") else { continue }
            let name = String(trimmed[..<colon])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let desc = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !name.isEmpty {
                result.append((name, desc.isEmpty ? "Hermes personality" : String(desc.prefix(64))))
            }
        }
        return result
    }

    private func yamlTopLevelValue(_ key: String, in text: String) -> String? {
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard indentationLevel(rawLine) == 0, trimmed.hasPrefix("\(key):") else { continue }
            return yamlScalar(after: "\(key):", in: trimmed)
        }
        return nil
    }

    private func reasoningSuggestions(query: String, limit: Int) -> [InputSuggestion] {
        let levels = ["none", "minimal", "low", "medium", "high", "xhigh", "show", "hide"]
        let needle = query.lowercased()
        return levels
            .filter { needle.isEmpty || $0.hasPrefix(needle) }
            .prefix(limit)
            .map { level in
                InputSuggestion(
                    title: "/reasoning \(level)",
                    subtitle: "Hermes reasoning/display setting",
                    replacement: "/reasoning \(level)"
                )
            }
    }

    private func skillSuggestions(command: String, query: String, limit: Int) -> [InputSuggestion] {
        let needle = query.lowercased()
        let skillsRoot = hermesHome.appendingPathComponent("skills")
        guard let enumerator = FileManager.default.enumerator(at: skillsRoot, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var names: [String] = []
        for case let file as URL in enumerator {
            guard file.lastPathComponent == "SKILL.md" else { continue }
            let folder = file.deletingLastPathComponent().path
            let prefix = skillsRoot.path + "/"
            guard folder.hasPrefix(prefix) else { continue }
            let name = String(folder.dropFirst(prefix.count))
            if needle.isEmpty || name.lowercased().contains(needle) {
                names.append(name)
            }
        }
        return names.sorted().prefix(limit).map { name in
            InputSuggestion(
                title: name,
                subtitle: "Hermes skill · ~/.hermes/skills/\(name)",
                replacement: command == "/skills" ? "/skills inspect \(name)" : "/skill \(name)"
            )
        }
    }

    private func sessionSuggestions(command: String, query: String, limit: Int) -> [InputSuggestion] {
        let needle = query.lowercased()
        return HermesConversationStore.shared.recentThreads(limit: 30)
            .filter { thread in
                needle.isEmpty
                    || thread.id.lowercased().contains(needle)
                    || thread.title.lowercased().contains(needle)
            }
            .prefix(limit)
            .map { thread in
                InputSuggestion(
                    title: thread.title,
                    subtitle: "\(thread.id) · \(thread.model.isEmpty ? HermesConfig.shared.snapshot.model : thread.model)",
                    replacement: "\(command) \(thread.id)"
                )
            }
    }

    private func parseCommandRegistry() -> [HermesSlashCommand] {
        let url = hermesHome
            .appendingPathComponent("hermes-agent")
            .appendingPathComponent("hermes_cli")
            .appendingPathComponent("commands.py")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return commandDefBlocks(in: text).compactMap { block in
            guard let captures = captureGroups(
                in: block,
                pattern: #"^\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"(.*)$"#,
                options: [.dotMatchesLineSeparators]
            ), captures.count >= 4 else { return nil }
            let argsHint = stringArgument(named: "args_hint", in: captures[3]) ?? ""
            let explicitSubcommands = tupleStrings(named: "subcommands", in: captures[3])
            let subcommands = explicitSubcommands.isEmpty ? pipeSubcommands(from: argsHint) : explicitSubcommands
            return HermesSlashCommand(
                name: captures[0],
                description: captures[1],
                category: captures[2],
                aliases: tupleStrings(named: "aliases", in: captures[3]),
                argsHint: argsHint,
                subcommands: subcommands,
                cliOnly: boolArgument(named: "cli_only", in: captures[3]),
                gatewayOnly: boolArgument(named: "gateway_only", in: captures[3])
            )
        }
    }

    private func commandDefBlocks(in text: String) -> [String] {
        callBlocks(named: "CommandDef", in: text)
    }

    private func callBlocks(named callee: String, in text: String) -> [String] {
        var blocks: [String] = []
        var searchStart = text.startIndex

        while let range = text.range(of: "\(callee)(", range: searchStart..<text.endIndex) {
            var index = range.upperBound
            var depth = 1
            var quote: Character?
            var escaped = false

            while index < text.endIndex {
                let char = text[index]
                if let activeQuote = quote {
                    if escaped {
                        escaped = false
                    } else if char == "\\" {
                        escaped = true
                    } else if char == activeQuote {
                        quote = nil
                    }
                } else if char == "\"" || char == "'" {
                    quote = char
                } else if char == "(" {
                    depth += 1
                } else if char == ")" {
                    depth -= 1
                    if depth == 0 {
                        blocks.append(String(text[range.upperBound..<index]))
                        searchStart = text.index(after: index)
                        break
                    }
                }
                index = text.index(after: index)
            }

            if index >= text.endIndex { break }
        }

        return blocks
    }

    private func captureGroups(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)) else {
            return nil
        }
        var captures: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text) else {
                captures.append("")
                continue
            }
            captures.append(String(text[range]))
        }
        return captures
    }

    private func tupleStrings(named name: String, in text: String) -> [String] {
        let pattern = "\(name)\\s*=\\s*\\(([^)]*)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text) else { return [] }
        let body = String(text[range])
        let itemRegex = try? NSRegularExpression(pattern: #""([^"]+)""#, options: [])
        let bodyRange = NSRange(body.startIndex..<body.endIndex, in: body)
        return itemRegex?.matches(in: body, options: [], range: bodyRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: body) else { return nil }
            return String(body[range])
        } ?? []
    }

    private func stringArgument(named name: String, in text: String) -> String? {
        let pattern = "\(name)\\s*=\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func boolArgument(named name: String, in text: String) -> Bool {
        let pattern = "\(name)\\s*=\\s*True"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        return regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil
    }

    private func pipeSubcommands(from argsHint: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9_-]+(?:\|[A-Za-z0-9_-]+)+"#, options: []),
              let match = regex.firstMatch(in: argsHint, options: [], range: NSRange(argsHint.startIndex..<argsHint.endIndex, in: argsHint)),
              let range = Range(match.range, in: argsHint) else { return [] }
        return String(argsHint[range]).components(separatedBy: "|")
    }

    private func fallbackSlashCommands() -> [HermesSlashCommand] {
        [
            HermesSlashCommand(name: "model", description: "Show or change model", category: "Configuration", aliases: ["provider"], argsHint: "[model]", subcommands: []),
            HermesSlashCommand(name: "reasoning", description: "Set reasoning", category: "Configuration", aliases: [], argsHint: "[level]", subcommands: ["none", "minimal", "low", "medium", "high", "xhigh", "show", "hide"]),
            HermesSlashCommand(name: "sessions", description: "Browse sessions", category: "Session", aliases: [], argsHint: "[id]", subcommands: []),
            HermesSlashCommand(name: "skills", description: "Search/install skills", category: "Tools & Skills", aliases: [], argsHint: "[subcommand]", subcommands: ["search", "browse", "inspect", "install"]),
            HermesSlashCommand(name: "tools", description: "Manage tools", category: "Tools & Skills", aliases: [], argsHint: "[list|disable|enable]", subcommands: ["list", "disable", "enable"]),
            HermesSlashCommand(name: "help", description: "Show commands", category: "Info", aliases: [], argsHint: "", subcommands: [])
        ]
    }

    private func formatContext(_ value: Int) -> String {
        if value >= 1_000_000 {
            let millions = Double(value) / 1_000_000.0
            return millions == floor(millions) ? "\(Int(millions))M" : String(format: "%.1fM", millions)
        }
        if value >= 1_000 {
            return "\(value / 1_000)K"
        }
        return "\(value)"
    }

    private func modificationToken(for url: URL) -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else { return 0 }
        return Int(date.timeIntervalSince1970)
    }
}

final class HermesConfig {
    static let shared = HermesConfig()

    let configURL: URL

    private init() {
        configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes")
            .appendingPathComponent("config.yaml")
    }

    var snapshot: HermesConfigSnapshot {
        let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        return HermesConfigSnapshot(
            model: yamlValue(section: "model", key: "default", in: text) ?? "grok-4.20-0309-reasoning",
            provider: yamlValue(section: "model", key: "provider", in: text) ?? "xai",
            baseURL: yamlValue(section: "model", key: "base_url", in: text) ?? "https://api.x.ai/v1",
            reasoningEffort: yamlValue(section: "agent", key: "reasoning_effort", in: text) ?? "medium",
            imageGenProvider: yamlValue(section: "image_gen", key: "provider", in: text) ?? "",
            imageGenModel: yamlValue(section: "image_gen", key: "model", in: text) ?? "",
            videoGenProvider: yamlValue(section: "video_gen", key: "provider", in: text) ?? "",
            videoGenModel: yamlValue(section: "video_gen", key: "model", in: text) ?? "",
            ttsProvider: yamlValue(section: "tts", key: "provider", in: text) ?? "",
            ttsVoice: nestedYamlValue(path: ["tts", yamlValue(section: "tts", key: "provider", in: text) ?? "", "voice"], in: text)
                ?? nestedYamlValue(path: ["tts", yamlValue(section: "tts", key: "provider", in: text) ?? "", "voice_id"], in: text)
                ?? "",
            sttProvider: yamlValue(section: "stt", key: "provider", in: text) ?? "",
            configURL: configURL
        )
    }

    func update(provider: String? = nil, model: String? = nil, baseURL: String? = nil, reasoningEffort: String? = nil) throws {
        var text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = """
            model:
              default: \(model ?? "grok-4.20-0309-reasoning")
              provider: \(provider ?? "xai")
              base_url: \(baseURL ?? "https://api.x.ai/v1")
            agent:
              reasoning_effort: \(reasoningEffort ?? "medium")

            """
        } else {
            if let provider {
                text = upsertYAML(section: "model", key: "provider", value: provider, in: text)
            }
            if let model {
                text = upsertYAML(section: "model", key: "default", value: model, in: text)
            }
            if let baseURL {
                text = upsertYAML(section: "model", key: "base_url", value: baseURL, in: text)
            }
            if let reasoningEffort {
                text = upsertYAML(section: "agent", key: "reasoning_effort", value: reasoningEffort, in: text)
            }
        }
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func yamlValue(section: String, key: String, in text: String) -> String? {
        var inSection = false
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if !rawLine.hasPrefix(" ") && !rawLine.hasPrefix("\t") {
                inSection = line == "\(section):"
                continue
            }
            guard inSection, line.hasPrefix("\(key):") else { continue }
            return line
                .dropFirst("\(key):".count)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    private func nestedYamlValue(path: [String], in text: String) -> String? {
        guard path.count >= 2 else { return nil }
        let targetKey = path.last ?? ""
        var stack: [(indent: Int, key: String)] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let indent = rawLine.prefix { $0 == " " || $0 == "\t" }.reduce(0) { count, char in
                count + (char == "\t" ? 2 : 1)
            }
            while let last = stack.last, indent <= last.indent {
                stack.removeLast()
            }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let currentPath = stack.map(\.key) + [key]
            if currentPath == path, key == targetKey, !value.isEmpty {
                return value
            }
            if value.isEmpty {
                stack.append((indent, key))
            }
        }
        return nil
    }

    private func upsertYAML(section: String, key: String, value: String, in text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var sectionIndex: Int?
        var sectionEnd = lines.count

        for idx in lines.indices {
            let raw = lines[idx]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !raw.hasPrefix(" ") && !raw.hasPrefix("\t") && trimmed.hasSuffix(":") {
                if trimmed == "\(section):" {
                    sectionIndex = idx
                } else if sectionIndex != nil {
                    sectionEnd = idx
                    break
                }
            }
        }

        guard let start = sectionIndex else {
            if !lines.isEmpty && lines.last != "" {
                lines.append("")
            }
            lines.append("\(section):")
            lines.append("  \(key): \(value)")
            return lines.joined(separator: "\n")
        }

        for idx in (start + 1)..<sectionEnd {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key):") {
                lines[idx] = "  \(key): \(value)"
                return lines.joined(separator: "\n")
            }
        }

        lines.insert("  \(key): \(value)", at: min(start + 1, lines.count))
        return lines.joined(separator: "\n")
    }
}

final class HermesConversationStore {
    static let shared = HermesConversationStore()

    private let stateDBURL: URL

    private init() {
        stateDBURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes")
            .appendingPathComponent("state.db")
    }

    func recentThreads(limit: Int = 12) -> [HermesThreadSummary] {
        let sql = """
        select
          s.id,
          coalesce(nullif(s.title,''), nullif((select trim(replace(replace(substr(case when instr(m.content, '主人的消息：') > 0 then substr(m.content, instr(m.content, '主人的消息：') + length('主人的消息：')) else m.content end, 1, 64), char(10), ' '), char(9), ' ')) from messages m where m.session_id = s.id and m.role = 'user' and coalesce(m.content,'') != '' order by m.timestamp asc limit 1), ''), '未命名 Hermes 对话') as title,
          coalesce((select replace(replace(substr(m.content, 1, 90), char(10), ' '), char(9), ' ') from messages m where m.session_id = s.id and coalesce(m.content,'') != '' order by m.timestamp desc limit 1), '') as preview,
          cast(coalesce((select max(m.timestamp) from messages m where m.session_id = s.id), s.started_at) as real) as updated_at,
          coalesce(s.model,''),
          coalesce(s.billing_provider,''),
          coalesce(s.source,''),
          coalesce(s.message_count,0)
        from sessions s
        order by updated_at desc
        limit \(max(1, limit));
        """
        return runSQLite(sql).compactMap(parseThreadSummary)
    }

    func thread(id: String) -> HermesThreadSummary? {
        let query = """
        select
          s.id,
          coalesce(nullif(s.title,''), nullif((select trim(replace(replace(substr(case when instr(m.content, '主人的消息：') > 0 then substr(m.content, instr(m.content, '主人的消息：') + length('主人的消息：')) else m.content end, 1, 64), char(10), ' '), char(9), ' ')) from messages m where m.session_id = s.id and m.role = 'user' and coalesce(m.content,'') != '' order by m.timestamp asc limit 1), ''), '未命名 Hermes 对话') as title,
          coalesce((select replace(replace(substr(m.content, 1, 90), char(10), ' '), char(9), ' ') from messages m where m.session_id = s.id and coalesce(m.content,'') != '' order by m.timestamp desc limit 1), '') as preview,
          cast(coalesce((select max(m.timestamp) from messages m where m.session_id = s.id), s.started_at) as real) as updated_at,
          coalesce(s.model,''),
          coalesce(s.billing_provider,''),
          coalesce(s.source,''),
          coalesce(s.message_count,0)
        from sessions s
        where s.id = '\(sql(id))'
        limit 1;
        """
        return runSQLite(query).compactMap(parseThreadSummary).first
    }

    func latestThread(startedAfter timestamp: TimeInterval) -> HermesThreadSummary? {
        let query = """
        select
          s.id,
          coalesce(nullif(s.title,''), nullif((select trim(replace(replace(substr(case when instr(m.content, '主人的消息：') > 0 then substr(m.content, instr(m.content, '主人的消息：') + length('主人的消息：')) else m.content end, 1, 64), char(10), ' '), char(9), ' ')) from messages m where m.session_id = s.id and m.role = 'user' and coalesce(m.content,'') != '' order by m.timestamp asc limit 1), ''), '未命名 Hermes 对话') as title,
          coalesce((select replace(replace(substr(m.content, 1, 90), char(10), ' '), char(9), ' ') from messages m where m.session_id = s.id and coalesce(m.content,'') != '' order by m.timestamp desc limit 1), '') as preview,
          cast(coalesce((select max(m.timestamp) from messages m where m.session_id = s.id), s.started_at) as real) as updated_at,
          coalesce(s.model,''),
          coalesce(s.billing_provider,''),
          coalesce(s.source,''),
          coalesce(s.message_count,0)
        from sessions s
        where s.started_at >= \(timestamp)
        order by s.started_at desc
        limit 1;
        """
        return runSQLite(query).compactMap(parseThreadSummary).first
    }

    func loadMessages(for thread: HermesThreadSummary) -> [AgentMessage] {
        let query = """
        select role, hex(coalesce(content,'')), coalesce(tool_name,''), coalesce(timestamp,0)
        from messages
        where session_id = '\(sql(thread.id))'
        order by timestamp asc, id asc;
        """
        return runSQLite(query).compactMap(parseMessage)
    }

    @discardableResult
    func deleteThread(id threadID: String) -> Bool {
        let update = """
        delete from messages where session_id = '\(sql(threadID))';
        delete from sessions where id = '\(sql(threadID))';
        select changes();
        """
        let changed = runSQLite(update).last.flatMap(Int.init) ?? 0
        return changed > 0
    }

    @discardableResult
    func updateThreadModel(id threadID: String, model: String, provider: String) -> Bool {
        let update = """
        update sessions
        set model = '\(sql(model))',
            billing_provider = '\(sql(provider))'
        where id = '\(sql(threadID))';
        select changes();
        """
        let changed = runSQLite(update).last.flatMap(Int.init) ?? 0
        return changed > 0
    }

    private func parseThreadSummary(_ line: String) -> HermesThreadSummary? {
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 8 else { return nil }
        return HermesThreadSummary(
            id: parts[0],
            title: parts[1].isEmpty ? "未命名 Hermes 对话" : parts[1],
            preview: parts[2],
            updatedAt: TimeInterval(parts[3]) ?? 0,
            model: parts[4],
            provider: parts[5],
            source: parts[6],
            messageCount: Int(parts[7]) ?? 0
        )
    }

    private func parseMessage(_ line: String) -> AgentMessage? {
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 4 else { return nil }
        let role = parts[0]
        let content = decodeHex(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        let toolName = parts[2]

        switch role {
        case "user":
            guard !content.isEmpty else { return nil }
            return AgentMessage(role: .user, text: content)
        case "assistant":
            guard !content.isEmpty else { return nil }
            return AgentMessage(role: .assistant, text: content)
        case "tool":
            let text = content.isEmpty ? toolName : content
            guard !text.isEmpty else { return nil }
            return AgentMessage(role: .toolResult, text: text)
        default:
            return nil
        }
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

    private func decodeHex(_ hex: String) -> String {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if next <= hex.endIndex,
               let byte = UInt8(hex[index..<next], radix: 16) {
                bytes.append(byte)
            }
            index = next
        }
        return String(data: Data(bytes), encoding: .utf8) ?? ""
    }

    private func sql(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
