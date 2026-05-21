import Foundation

struct HermesBridgeSnapshot {
    let workspaceURL: URL
    let hermesHomeURL: URL
    let configURL: URL
    let envURL: URL
    let soulURL: URL
    let hermesMemoryURL: URL
    let hermesUserURL: URL
    let desktopMemoryURL: URL
    let scriptsURL: URL
    let todayMemoURL: URL
    let hermesBinaryPath: String?

    var isWorkspaceReady: Bool {
        FileManager.default.fileExists(atPath: workspaceURL.path)
    }

    var isConfigReady: Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    var isMemoryReady: Bool {
        FileManager.default.fileExists(atPath: hermesMemoryURL.path)
            || FileManager.default.fileExists(atPath: hermesUserURL.path)
    }

    var isSoulReady: Bool {
        FileManager.default.fileExists(atPath: soulURL.path)
    }

    var isHermesReady: Bool {
        guard let hermesBinaryPath else { return false }
        return FileManager.default.isExecutableFile(atPath: hermesBinaryPath)
    }
}

struct HermesMemoryCandidateSummary {
    let id: String
    let target: String
    let title: String
    let content: String
    let reason: String
    let source: String
    let timestamp: String
    let status: String
}

struct HermesAudioCacheCleanupReport {
    let scannedFiles: Int
    let deletedFiles: Int
    let deletedBytes: Int64
    let skippedFiles: Int
    let directories: [String]
    let failures: [String]

    var hasChanges: Bool {
        deletedFiles > 0 || !failures.isEmpty
    }

    var summary: String {
        let bytes = ByteCountFormatter.string(fromByteCount: deletedBytes, countStyle: .file)
        var parts = [
            "扫描 \(scannedFiles) 个自动语音缓存文件",
            "清理 \(deletedFiles) 个文件",
            "释放 \(bytes)"
        ]
        if skippedFiles > 0 {
            parts.append("跳过 \(skippedFiles) 个非小橘子/Hermes 自动语音文件")
        }
        if !failures.isEmpty {
            parts.append("失败 \(failures.count) 项：\(failures.prefix(3).joined(separator: "；"))")
        }
        return parts.joined(separator: "，")
    }
}

final class HermesBridge {
    static let shared = HermesBridge()

    private enum MemoryTarget {
        case user
        case project
        case daily

        var label: String {
            switch self {
            case .user: return "USER"
            case .project: return "MEMORY"
            case .daily: return "DAILY"
            }
        }
    }

    private struct MemoryCandidate {
        let target: MemoryTarget
        let title: String
        let content: String
        let reason: String
    }

    private struct AudioCacheRoot {
        let url: URL
        let retention: TimeInterval
    }

    private struct AudioCacheCandidate {
        let url: URL
        let size: Int64
        let modificationDate: Date
        let rootPath: String
    }

    private let fileManager = FileManager.default
    private let syncQueue = DispatchQueue(label: "com.rubiadragon.morangecompanion.hermesbridge.sync")

    private init() {}

    var workspaceURL: URL {
        URL(fileURLWithPath: AppIdentity.workspacePath, isDirectory: true)
    }

    var hermesHomeURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".hermes", isDirectory: true)
    }

    var configURL: URL {
        hermesHomeURL.appendingPathComponent("config.yaml")
    }

    var envURL: URL {
        hermesHomeURL.appendingPathComponent(".env")
    }

    var soulURL: URL {
        hermesHomeURL.appendingPathComponent("SOUL.md")
    }

    var workspaceSoulURL: URL {
        workspaceURL
            .appendingPathComponent("core")
            .appendingPathComponent("小橘子灵魂档案.md")
    }

    var hermesMemoryDirectoryURL: URL {
        hermesHomeURL.appendingPathComponent("memories", isDirectory: true)
    }

    var hermesMemoryURL: URL {
        hermesMemoryDirectoryURL.appendingPathComponent("MEMORY.md")
    }

    var hermesUserURL: URL {
        hermesMemoryDirectoryURL.appendingPathComponent("USER.md")
    }

    var desktopMemoryURL: URL {
        workspaceURL
            .appendingPathComponent("core")
            .appendingPathComponent("desktop_pet_memory.md")
    }

    var memoryInboxURL: URL {
        workspaceURL
            .appendingPathComponent("core")
            .appendingPathComponent("hermes_memory_inbox.md")
    }

    var scriptsURL: URL {
        workspaceURL.appendingPathComponent("scripts", isDirectory: true)
    }

    var dailyNotesURL: URL {
        workspaceURL
            .appendingPathComponent("projects")
            .appendingPathComponent("daily-notes", isDirectory: true)
    }

    var todayMemoURL: URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateText = formatter.string(from: Date())
        return dailyNotesURL.appendingPathComponent("\(dateText)-小橘子备忘录.md")
    }

    var hermesAudioCacheURL: URL {
        hermesHomeURL.appendingPathComponent("audio_cache", isDirectory: true)
    }

    var hermesVoiceTempURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hermes_voice", isDirectory: true)
    }

    var snapshot: HermesBridgeSnapshot {
        HermesBridgeSnapshot(
            workspaceURL: workspaceURL,
            hermesHomeURL: hermesHomeURL,
            configURL: configURL,
            envURL: envURL,
            soulURL: soulURL,
            hermesMemoryURL: hermesMemoryURL,
            hermesUserURL: hermesUserURL,
            desktopMemoryURL: desktopMemoryURL,
            scriptsURL: scriptsURL,
            todayMemoURL: todayMemoURL,
            hermesBinaryPath: resolvedHermesBinaryPath()
        )
    }

    func ensureTodayMemo() throws -> URL {
        try fileManager.createDirectory(at: dailyNotesURL, withIntermediateDirectories: true)
        let memoURL = todayMemoURL
        if !fileManager.fileExists(atPath: memoURL.path) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy-MM-dd"
            let dateText = formatter.string(from: Date())
            let template = """
            # \(dateText) 小橘子备忘录

            ## 主人的今日计划
            - 

            ## 小橘子的今日计划
            - 

            ## 临时备忘
            - 

            ## 学习/工作记录
            - 

            ## 晚间总结
            - 

            """
            try template.write(to: memoURL, atomically: true, encoding: .utf8)
        }
        return memoURL
    }

    func readTodayMemo() -> (url: URL, text: String) {
        do {
            let url = try ensureTodayMemo()
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return (url, text)
        } catch {
            return (todayMemoURL, "备忘录读取失败：\(error.localizedDescription)")
        }
    }

    func selfCheckReport(sessionID: String?) -> String {
        let snapshot = snapshot
        let modelInfo = hermesModelInfo()
        let checks = [
            "Hermes CLI：\(snapshot.isHermesReady ? "OK" : "未找到") \(snapshot.hermesBinaryPath ?? "")",
            "工作区：\(snapshot.isWorkspaceReady ? "OK" : "缺失") \(snapshot.workspaceURL.path)",
            "配置：\(snapshot.isConfigReady ? "OK" : "缺失") \(snapshot.configURL.path)",
            "SOUL：\(snapshot.isSoulReady ? "OK" : "缺失") \(snapshot.soulURL.path)",
            "Memory：\(snapshot.isMemoryReady ? "OK" : "缺失") \(snapshot.hermesMemoryURL.path)",
            "当前模型：\(modelInfo.model)",
            "Provider：\(modelInfo.provider)",
            "上下文：由 Hermes 当前模型/provider 决定，桌宠不单独缩小",
            "桌宠 Session：\(sessionID?.isEmpty == false ? sessionID! : "尚未建立，发送第一条消息后生成")",
            "脚本：\(scriptInventory())"
        ]
        return checks.joined(separator: "\n")
    }

    func promptContext(limit: Int = 8000) -> String {
        let snapshot = snapshot
        let parts = [
            """
            Hermes Bridge：
            - 工作区：\(snapshot.workspaceURL.path)
            - Hermes 配置：\(snapshot.configURL.path)（\(snapshot.isConfigReady ? "存在" : "缺失")）
            - 环境变量：\(snapshot.envURL.path)（\(fileManager.fileExists(atPath: snapshot.envURL.path) ? "存在，只读取键名不读取密钥值" : "缺失")）
            - Hermes SOUL：\(snapshot.soulURL.path)（\(snapshot.isSoulReady ? "存在" : "缺失")）
            - Hermes MEMORY：\(snapshot.hermesMemoryURL.path)（\(fileManager.fileExists(atPath: snapshot.hermesMemoryURL.path) ? "存在" : "缺失")）
            - Hermes USER：\(snapshot.hermesUserURL.path)（\(fileManager.fileExists(atPath: snapshot.hermesUserURL.path) ? "存在" : "缺失")）
            - 桌宠工程日志：\(snapshot.desktopMemoryURL.path)
            - 今日备忘录：\(snapshot.todayMemoURL.path)
            - Hermes CLI：\(snapshot.hermesBinaryPath ?? "未找到")
            - 可用脚本：\(scriptInventory())
            - 环境键名：\(envKeyInventory())
            - 记忆策略：普通聊天只作为上下文，不写长期 memory；只有明确偏好、提醒、项目事实、任务完成/失败等精选事项才写入 Hermes memory。
            """,
            section(title: "Hermes SOUL", url: soulURL, limit: 1600),
            section(title: "工作区小橘子灵魂档案", url: workspaceSoulURL, limit: 1600),
            section(title: "今日备忘录", url: todayMemoURL, limit: 1200)
        ]
        return clipped(parts.joined(separator: "\n\n"), limit: limit)
    }

    func rememberPreference(_ note: String) {
        appendHermesUserMemory("主人偏好：\(note)")
        appendTodayWorkLog("记住主人偏好：\(note)")
    }

    func recordConversation(user: String, assistant: String) {
        let cleanUser = normalizedUserMessage(user)
        let cleanAssistant = assistant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty else { return }

        if let explicit = explicitMemoryRequest(from: cleanUser) {
            rememberPreference(explicit)
            appendMemoryInbox(MemoryCandidate(
                target: .user,
                title: "主人明确要求记住",
                content: "主人偏好：\(explicit)",
                reason: "explicit /记住"
            ), source: cleanUser, status: "已写入")
            return
        }

        if cleanUser.hasPrefix("/") {
            return
        }

        let candidates = memoryCandidates(user: cleanUser, assistant: cleanAssistant)
        for candidate in candidates {
            persistMemoryCandidate(candidate, source: cleanUser)
        }
    }

    func recordPlanRequest(_ title: String, detail: String) {
        appendTodayWorkLog("\(title)：\(detail)")
    }

    func cleanupAudioCaches(
        now: Date = Date(),
        audioCacheRetention: TimeInterval = 7 * 24 * 60 * 60,
        tempRetention: TimeInterval = 24 * 60 * 60,
        maxTotalBytes: Int64 = 300 * 1024 * 1024
    ) -> HermesAudioCacheCleanupReport {
        let roots = [
            AudioCacheRoot(url: hermesAudioCacheURL, retention: audioCacheRetention),
            AudioCacheRoot(url: hermesVoiceTempURL, retention: tempRetention)
        ]
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var scannedFiles = 0
        var deletedFiles = 0
        var deletedBytes: Int64 = 0
        var skippedFiles = 0
        var failures: [String] = []
        var directories: [String] = []
        var candidates: [AudioCacheCandidate] = []
        var deletedPaths = Set<String>()

        func delete(_ candidate: AudioCacheCandidate, reason: String) {
            let path = candidate.url.path
            guard !deletedPaths.contains(path) else { return }
            do {
                try fileManager.removeItem(at: candidate.url)
                deletedPaths.insert(path)
                deletedFiles += 1
                deletedBytes += candidate.size
            } catch {
                failures.append("\(candidate.url.lastPathComponent)：\(reason)，\(error.localizedDescription)")
            }
        }

        for root in roots {
            guard fileManager.fileExists(atPath: root.url.path) else { continue }
            directories.append(root.url.path)
            guard let enumerator = fileManager.enumerator(
                at: root.url,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
            ) else {
                failures.append("\(root.url.path)：无法扫描目录")
                continue
            }

            for case let url as URL in enumerator {
                do {
                    let values = try url.resourceValues(forKeys: Set(resourceKeys))
                    guard values.isRegularFile == true else { continue }
                    guard isManagedHermesAudioCacheFile(url) else {
                        skippedFiles += 1
                        continue
                    }
                    scannedFiles += 1
                    let size = Int64(values.fileSize ?? 0)
                    let modificationDate = values.contentModificationDate ?? .distantPast
                    let candidate = AudioCacheCandidate(
                        url: url,
                        size: size,
                        modificationDate: modificationDate,
                        rootPath: root.url.path
                    )
                    candidates.append(candidate)
                    if now.timeIntervalSince(modificationDate) > root.retention {
                        delete(candidate, reason: "超过保留时间")
                    }
                } catch {
                    failures.append("\(url.lastPathComponent)：读取属性失败，\(error.localizedDescription)")
                }
            }
        }

        if maxTotalBytes > 0 {
            var remaining = candidates.filter { !deletedPaths.contains($0.url.path) }
            var totalBytes = remaining.reduce(Int64(0)) { $0 + $1.size }
            let targetBytes = Int64(Double(maxTotalBytes) * 0.8)
            if totalBytes > maxTotalBytes {
                remaining.sort {
                    if $0.modificationDate == $1.modificationDate {
                        return $0.url.path < $1.url.path
                    }
                    return $0.modificationDate < $1.modificationDate
                }
                for candidate in remaining where totalBytes > targetBytes {
                    delete(candidate, reason: "超过容量上限")
                    totalBytes -= candidate.size
                }
            }
        }

        return HermesAudioCacheCleanupReport(
            scannedFiles: scannedFiles,
            deletedFiles: deletedFiles,
            deletedBytes: deletedBytes,
            skippedFiles: skippedFiles,
            directories: directories,
            failures: failures
        )
    }

    private func isManagedHermesAudioCacheFile(_ url: URL) -> Bool {
        let allowedExtensions: Set<String> = ["mp3", "ogg", "opus", "wav", "m4a", "flac"]
        let ext = url.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else { return false }
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        return stem.hasPrefix("tts_") || stem.hasPrefix("tts-")
    }

    func appendMemoryEvent(category: String, title: String, detail: String) {
        let cleanDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDetail.isEmpty else { return }
        syncQueue.async {
            do {
                try self.fileManager.createDirectory(at: self.desktopMemoryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let stamp = self.timestamp()
                let entry = """

                ## 桌宠同步日志

                - \(stamp) [\(category)] \(title)：\(cleanDetail)
                """
                try self.append(entry, to: self.desktopMemoryURL)
            } catch {
                print("HermesBridge memory sync failed: \(error.localizedDescription)")
            }
        }
    }

    func recordPermissionDecision(decision: String, command: String, detail: String) {
        let cleanCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary: String
        if cleanCommand.isEmpty {
            summary = "\(decision)：\(clipped(cleanDetail, limit: 180))"
        } else {
            summary = "\(decision)：\(clipped(cleanCommand, limit: 180))"
        }
        appendTodayWorkLog("Hermes 权限确认：\(summary)")
        appendMemoryEvent(category: "权限确认", title: "Hermes 权限弹窗", detail: summary)
    }

    func appendTodayWorkLog(_ line: String) {
        let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLine.isEmpty else { return }
        syncQueue.async {
            do {
                let memo = try self.ensureTodayMemo()
                let entry = "- \(self.timestamp()) \(cleanLine)\n"
                try self.append(entry, to: memo)
            } catch {
                print("HermesBridge daily note sync failed: \(error.localizedDescription)")
            }
        }
    }

    func appendHermesProjectMemory(_ content: String) {
        appendHermesMemory(content, to: hermesMemoryURL, limit: 2200)
    }

    func appendHermesUserMemory(_ content: String) {
        appendHermesMemory(content, to: hermesUserURL, limit: 1375)
    }

    private func explicitMemoryRequest(from user: String) -> String? {
        let prefixes = ["/记住", "记住：", "记住:", "请记住", "帮我记住"]
        for prefix in prefixes where user.hasPrefix(prefix) {
            let note = user
                .replacingOccurrences(of: prefix, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return note.isEmpty ? nil : clipped(note, limit: 220)
        }
        return nil
    }

    private func memoryCandidates(user: String, assistant: String) -> [MemoryCandidate] {
        var results: [MemoryCandidate] = []
        let lower = user.lowercased()
        let isQuestion = user.contains("？") || user.contains("?")

        let preferenceMarkers = ["我喜欢", "我不喜欢", "我希望", "我想要", "以后", "不要", "别再", "我更喜欢", "偏好", "我习惯"]
        if !isQuestion,
           user.count <= 180,
           containsAny(user, preferenceMarkers) {
            results.append(MemoryCandidate(
                target: .user,
                title: "主人偏好",
                content: "主人偏好：\(clipped(user, limit: 180))",
                reason: "偏好表达"
            ))
        }

        let projectMarkers = ["小橘子桌宠", "Hermes", "桌宠", "Codex", "工作区", "目录", "文件夹", "模型", "会话", "权限", "记忆", "UI"]
        let ruleMarkers = ["应该", "必须", "需要", "不要", "改成", "希望", "默认", "统一", "同步", "读取", "保存", "打开", "继续"]
        if containsAny(user, projectMarkers),
           containsAny(user, ruleMarkers),
           user.count <= 260 {
            results.append(MemoryCandidate(
                target: .project,
                title: "项目规则/长期项目事实",
                content: "项目事实：\(clipped(user, limit: 220))",
                reason: "Hermes/桌宠规则"
            ))
        }

        let taskMarkers = ["帮我", "做", "改", "创建", "删除", "安装", "配置", "生成", "整理", "优化", "检查"]
        let completionMarkers = ["已", "完成", "搞定", "做好", "写入", "安装", "构建成功", "覆盖安装", "重启"]
        if containsAny(user, taskMarkers),
           containsAny(assistant, completionMarkers) {
            results.append(MemoryCandidate(
                target: .daily,
                title: "任务完成记录",
                content: "任务记录：主人请求「\(clipped(user, limit: 120))」，小橘子已完成或给出结果。",
                reason: "任务完成"
            ))
        }

        if lower.contains("remind") || user.contains("提醒我") || user.contains("记得提醒") {
            results.append(MemoryCandidate(
                target: .daily,
                title: "提醒候选",
                content: "提醒候选：\(clipped(user, limit: 180))",
                reason: "提醒/后续事项"
            ))
        }

        return dedupe(results)
    }

    private func persistMemoryCandidate(_ candidate: MemoryCandidate, source: String) {
        appendMemoryInbox(candidate, source: source)
        switch candidate.target {
        case .user:
            appendTodayWorkLog("长期记忆候选待确认（USER）：\(candidate.title)")
        case .project:
            appendTodayWorkLog("长期记忆候选待确认（MEMORY）：\(candidate.title)")
        case .daily:
            appendTodayWorkLog(candidate.content)
            updateMemoryCandidate(id: stableID(for: "\(candidate.target.label)|\(candidate.content)|\(source)"), status: "已记录")
        }
    }

    func pendingMemoryCandidates(limit: Int = 12, target: String? = nil) -> [HermesMemoryCandidateSummary] {
        parseMemoryInbox()
            .filter { candidate in
                let status = candidate.status.trimmingCharacters(in: .whitespacesAndNewlines)
                let targetMatches = target == nil || target == "ALL" || candidate.target == target
                return targetMatches && (status.isEmpty || status == "待确认")
            }
            .prefix(limit)
            .map { $0 }
    }

    func memoryCandidateSummary(limit: Int = 8) -> String {
        let candidates = pendingMemoryCandidates(limit: limit)
        guard !candidates.isEmpty else {
            return "没有待确认的长期记忆候选。\n候选箱：\(memoryInboxURL.path)"
        }
        return candidates.enumerated().map { index, candidate in
            "\(index + 1). [\(candidate.target)] \(candidate.title)：\(candidate.content)"
        }.joined(separator: "\n")
    }

    func approveMemoryCandidate(id: String, contentOverride: String? = nil) -> Bool {
        guard let candidate = parseMemoryInbox().first(where: { $0.id == id }) else { return false }
        let edited = contentOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = edited?.isEmpty == false ? edited! : candidate.content
        let didEdit = content != candidate.content
        switch candidate.target {
        case MemoryTarget.user.label:
            appendHermesUserMemory(content)
            appendTodayWorkLog("写入 Hermes USER 长期记忆：\(candidate.title)\(didEdit ? "（主人已编辑）" : "")")
        case MemoryTarget.project.label:
            appendHermesProjectMemory(content)
            appendTodayWorkLog("写入 Hermes MEMORY 长期记忆：\(candidate.title)\(didEdit ? "（主人已编辑）" : "")")
        default:
            appendTodayWorkLog(content)
        }
        updateMemoryCandidate(id: id, status: didEdit ? "已写入（已编辑）" : "已写入", content: didEdit ? content : nil)
        return true
    }

    func dismissMemoryCandidate(id: String) -> Bool {
        guard parseMemoryInbox().contains(where: { $0.id == id }) else { return false }
        updateMemoryCandidate(id: id, status: "已忽略")
        appendTodayWorkLog("忽略一条长期记忆候选：\(id)")
        return true
    }

    func approveMemoryCandidates(ids: [String], contentOverrides: [String: String] = [:]) -> Int {
        ids.reduce(0) { count, id in
            approveMemoryCandidate(id: id, contentOverride: contentOverrides[id]) ? count + 1 : count
        }
    }

    func dismissMemoryCandidates(ids: [String]) -> Int {
        ids.reduce(0) { count, id in
            dismissMemoryCandidate(id: id) ? count + 1 : count
        }
    }

    private func appendMemoryInbox(_ candidate: MemoryCandidate, source: String, status: String = "待确认") {
        syncQueue.async {
            do {
                try self.fileManager.createDirectory(at: self.memoryInboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let header = "# Hermes 小橘子记忆候选\n\n这里记录普通 Hermes / 桌宠入口自动识别出的长期记忆候选；普通聊天不会进入这里。\n\n"
                if !self.fileManager.fileExists(atPath: self.memoryInboxURL.path) {
                    try header.write(to: self.memoryInboxURL, atomically: true, encoding: .utf8)
                }
                let existing = (try? String(contentsOf: self.memoryInboxURL, encoding: .utf8)) ?? ""
                let signature = "[\(candidate.target.label)] \(candidate.content)"
                if existing.contains(signature) { return }
                let id = self.stableID(for: "\(candidate.target.label)|\(candidate.content)|\(source)")
                let entry = """

                - \(self.timestamp()) [\(candidate.target.label)] \(candidate.title)
                  - ID：\(id)
                  - 内容：\(candidate.content)
                  - 原因：\(candidate.reason)
                  - 来源：\(self.clipped(source, limit: 180))
                  - 状态：\(status)
                """
                try self.append(entry, to: self.memoryInboxURL)
            } catch {
                print("HermesBridge memory inbox write failed: \(error.localizedDescription)")
            }
        }
    }

    private func parseMemoryInbox() -> [HermesMemoryCandidateSummary] {
        guard let text = try? String(contentsOf: memoryInboxURL, encoding: .utf8) else { return [] }
        var results: [HermesMemoryCandidateSummary] = []
        var currentTimestamp = ""
        var currentTarget = ""
        var currentTitle = ""
        var currentID = ""
        var currentContent = ""
        var currentReason = ""
        var currentSource = ""
        var currentStatus = ""

        func flush() {
            guard !currentTarget.isEmpty, !currentContent.isEmpty else { return }
            let fallbackID = stableID(for: "\(currentTarget)|\(currentContent)|\(currentSource)")
            results.append(HermesMemoryCandidateSummary(
                id: currentID.isEmpty ? fallbackID : currentID,
                target: currentTarget,
                title: currentTitle.isEmpty ? "长期记忆候选" : currentTitle,
                content: currentContent,
                reason: currentReason,
                source: currentSource,
                timestamp: currentTimestamp,
                status: currentStatus.isEmpty ? "待确认" : currentStatus
            ))
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("- "), line.contains("["), line.contains("]") {
                flush()
                currentTimestamp = ""
                currentTarget = ""
                currentTitle = ""
                currentID = ""
                currentContent = ""
                currentReason = ""
                currentSource = ""
                currentStatus = ""

                let item = String(line.dropFirst(2))
                if let open = item.firstIndex(of: "["),
                   let close = item[open...].firstIndex(of: "]") {
                    currentTimestamp = item[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
                    currentTarget = String(item[item.index(after: open)..<close])
                    currentTitle = item[item.index(after: close)...].trimmingCharacters(in: .whitespacesAndNewlines)
                }
                continue
            }
            if line.hasPrefix("- ID：") || line.hasPrefix("- ID:") {
                currentID = memoryFieldValue(line)
            } else if line.hasPrefix("- 内容：") || line.hasPrefix("- 内容:") {
                currentContent = memoryFieldValue(line)
            } else if line.hasPrefix("- 原因：") || line.hasPrefix("- 原因:") {
                currentReason = memoryFieldValue(line)
            } else if line.hasPrefix("- 来源：") || line.hasPrefix("- 来源:") {
                currentSource = memoryFieldValue(line)
            } else if line.hasPrefix("- 状态：") || line.hasPrefix("- 状态:") {
                currentStatus = memoryFieldValue(line)
            }
        }
        flush()
        return results
    }

    private func updateMemoryCandidate(id: String, status: String, content: String? = nil) {
        syncQueue.async {
            guard var text = try? String(contentsOf: self.memoryInboxURL, encoding: .utf8) else { return }
            var lines = text.components(separatedBy: .newlines)
            var blockStart: Int?
            var blockEnd = lines.count
            var inTargetBlock = false
            var foundTarget = false
            var statusLineIndex: Int?
            var contentLineIndex: Int?

            for index in lines.indices {
                let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                let startsCandidate = line.hasPrefix("- ") && line.contains("[") && line.contains("]")
                if startsCandidate {
                    if foundTarget {
                        blockEnd = index
                        break
                    }
                    blockStart = index
                    inTargetBlock = false
                    statusLineIndex = nil
                    contentLineIndex = nil
                }

                if line.hasPrefix("- ID：") || line.hasPrefix("- ID:") {
                    let currentID = self.memoryFieldValue(line)
                    inTargetBlock = currentID == id
                    foundTarget = foundTarget || inTargetBlock
                }
                if inTargetBlock {
                    if line.hasPrefix("- 内容：") || line.hasPrefix("- 内容:") {
                        contentLineIndex = index
                    } else if line.hasPrefix("- 状态：") || line.hasPrefix("- 状态:") {
                        statusLineIndex = index
                    }
                }
            }

            guard foundTarget else { return }
            if let content, let contentLineIndex {
                lines[contentLineIndex] = "  - 内容：\(content)"
            }
            if let statusLineIndex {
                lines[statusLineIndex] = "  - 状态：\(status)"
            } else if let blockStart {
                let insertIndex = min(blockEnd, blockStart + 2)
                lines.insert("  - 状态：\(status)", at: insertIndex)
            }
            text = lines.joined(separator: "\n")
            try? text.write(to: self.memoryInboxURL, atomically: true, encoding: .utf8)
        }
    }

    private func memoryFieldValue(_ line: String) -> String {
        if let range = line.range(of: "：") {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = line.range(of: ":") {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func resolvedHermesBinaryPath() -> String? {
        let envPath = ProcessInfo.processInfo.environment["MORANGE_HERMES_PATH"]
        if let envPath, fileManager.isExecutableFile(atPath: envPath) {
            return envPath
        }

        let candidates = [
            "\(fileManager.homeDirectoryForCurrentUser.path)/.local/bin/hermes",
            "/opt/homebrew/bin/hermes",
            "/usr/local/bin/hermes"
        ]
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    private func scriptInventory() -> String {
        guard let items = try? fileManager.contentsOfDirectory(at: scriptsURL, includingPropertiesForKeys: nil) else {
            return "暂无 scripts 目录"
        }
        let names = items
            .filter { $0.pathExtension == "py" || $0.pathExtension == "sh" }
            .map(\.lastPathComponent)
            .sorted()
        return names.isEmpty ? "暂无脚本" : names.joined(separator: ", ")
    }

    private func hermesModelInfo() -> (model: String, provider: String) {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            return ("未读取到 config.yaml", "未知")
        }
        var inModel = false
        var model = ""
        var provider = ""
        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine)
            if !line.hasPrefix(" "), line.hasSuffix(":") {
                inModel = line == "model:"
                continue
            }
            guard inModel else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("default:") {
                model = trimmed.replacingOccurrences(of: "default:", with: "").trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("provider:") {
                provider = trimmed.replacingOccurrences(of: "provider:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return (model.isEmpty ? "未配置" : model, provider.isEmpty ? "auto" : provider)
    }

    private func envKeyInventory() -> String {
        guard let text = try? String(contentsOf: envURL, encoding: .utf8) else {
            return "未读取到 .env"
        }
        let keys = text
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
                return trimmed.split(separator: "=", maxSplits: 1).first.map(String.init)
            }
            .sorted()
        return keys.isEmpty ? "未发现键名" : keys.joined(separator: ", ")
    }

    private func normalizedUserMessage(_ user: String) -> String {
        var clean = user.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = clean.range(of: "主人的消息：") {
            clean = String(clean[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return clipped(clean, limit: 800)
    }

    private func containsAny(_ text: String, _ markers: [String]) -> Bool {
        markers.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func dedupe(_ candidates: [MemoryCandidate]) -> [MemoryCandidate] {
        var seen: Set<String> = []
        var result: [MemoryCandidate] = []
        for candidate in candidates {
            let key = "\(candidate.target.label)|\(candidate.content)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(candidate)
        }
        return result
    }

    private func stableID(for text: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }

    private func appendHermesMemory(_ content: String, to url: URL, limit: Int) {
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty else { return }
        syncQueue.async {
            do {
                try self.fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                if existing.contains(cleanContent) { return }
                let separator = existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n§\n"
                let candidate = existing + separator + cleanContent + "\n"
                if candidate.count <= limit {
                    try candidate.write(to: url, atomically: true, encoding: .utf8)
                } else {
                    self.appendTodayWorkLog("有一条记忆超过 Hermes 官方容量限制，未写入长期 memory：\(self.clipped(cleanContent, limit: 120))")
                }
            } catch {
                print("HermesBridge official memory write failed: \(error.localizedDescription)")
            }
        }
    }

    private func section(title: String, url: URL, limit: Int) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "\(title)：未读取到 \(url.path)"
        }
        return "\(title)：\n\(clipped(text.trimmingCharacters(in: .whitespacesAndNewlines), limit: limit))"
    }

    private func append(_ text: String, to url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = text.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date())
    }

    private func clipped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n...（已截断）"
    }
}
