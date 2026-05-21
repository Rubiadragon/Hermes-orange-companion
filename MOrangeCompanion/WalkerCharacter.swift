import AVFoundation
import AppKit
import QuartzCore

class WalkerCharacter {
    static let characterWindowLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 20)

    enum PetState {
        case walking
        case listening
        case thinking
        case working
        case done
        case confused
        case sleepy
        case affection
        case poke
        case puffed
        case held
        case dragForward
        case dragBehind
        case lifted
        case pressed

        var title: String {
            switch self {
            case .walking: return "小橘子 · 巡逻中"
            case .listening: return "小橘子 · 听主人说"
            case .thinking: return "小橘子 · 翻记忆"
            case .working: return "小橘子 · 开工中"
            case .done: return "小橘子 · 完成啦"
            case .confused: return "小橘子 · 卡住了"
            case .sleepy: return "小橘子 · 充电中"
            case .affection: return "小橘子 · 贴贴"
            case .poke: return "小橘子 · 被戳戳"
            case .puffed: return "小橘子 · 气鼓鼓"
            case .held: return "小橘子 · 被捏住"
            case .dragForward: return "小橘子 · 被牵着走"
            case .dragBehind: return "小橘子 · 被往后拽"
            case .lifted: return "小橘子 · 被拎起"
            case .pressed: return "小橘子 · 被按住"
            }
        }

        var video: (name: String, allowsMovement: Bool) {
            switch self {
            case .walking: return ("morange-walk", true)
            case .listening: return ("morange-idle", false)
            case .thinking: return ("morange-thinking", false)
            case .working: return ("morange-working", false)
            case .done: return ("morange-done", false)
            case .confused: return ("morange-confused", false)
            case .sleepy: return ("morange-sleepy", false)
            case .affection: return ("morange-affection", false)
            case .poke: return ("morange-poke", false)
            case .puffed: return ("morange-puffed", false)
            case .held: return ("morange-held", false)
            case .dragForward: return ("morange-drag-forward", false)
            case .dragBehind: return ("morange-drag-behind", false)
            case .lifted: return ("morange-lifted", false)
            case .pressed: return ("morange-pressed", false)
            }
        }

        var isInteractive: Bool {
            switch self {
            case .affection, .poke, .puffed, .held, .dragForward, .dragBehind, .lifted, .pressed:
                return true
            default:
                return false
            }
        }

        var microMotionKey: String {
            switch self {
            case .walking: return "walkDrift"
            case .listening: return "listenNod"
            case .thinking: return "thinkingSway"
            case .working: return "workingPulse"
            case .done: return "doneHop"
            case .confused: return "confusedShake"
            case .sleepy: return "sleepBreath"
            case .affection: return "affectionLean"
            case .poke: return "pokeRecoil"
            case .puffed: return "puffedBounce"
            case .held: return "heldCompress"
            case .dragForward: return "dragForwardLean"
            case .dragBehind: return "dragBehindTug"
            case .lifted: return "liftedFloat"
            case .pressed: return "pressedSquash"
            }
        }
    }

    static var animationSearchDirectories: [URL] {
        var directories: [URL] = []
        let fileManager = FileManager.default

        if let envPath = ProcessInfo.processInfo.environment["MORANGE_ASSETS_DIR"],
           !envPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            directories.append(URL(fileURLWithPath: envPath).appendingPathComponent("MOrangeAnimations"))
            directories.append(URL(fileURLWithPath: envPath))
        }

        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let morangeRoot = appSupport.appendingPathComponent(AppIdentity.supportDirectoryName)
            directories.append(morangeRoot.appendingPathComponent("MOrangeAnimations"))
            directories.append(morangeRoot)
        }

        directories.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("MOrangeAnimations"))
        directories.append(URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("MOrangeCompanion"))
        directories.append(URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("MOrangeCompanion").appendingPathComponent("MOrangeAnimations"))
        directories.append(URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("MOrangeAnimations"))
        return directories
    }
    let defaultVideoName: String
    var currentVideoName: String
    var window: NSWindow!
    var playerLayer: AVPlayerLayer!
    var queuePlayer: AVQueuePlayer!
    var looper: AVPlayerLooper?

    let videoWidth: CGFloat = 1080
    let videoHeight: CGFloat = 1920
    let baseDisplayHeight: CGFloat = 208
    var animationScaleMap: [String: CGFloat] = [:]
    var currentAnimationScale: CGFloat = 1.0
    var displayHeight: CGFloat { baseDisplayHeight * currentAnimationScale }
    var displayWidth: CGFloat { displayHeight * (videoWidth / videoHeight) }

    // Walk timing (per-character, from frame analysis)
    let videoDuration: CFTimeInterval = 10.0
    var accelStart: CFTimeInterval = 3.0
    var fullSpeedStart: CFTimeInterval = 3.75
    var decelStart: CFTimeInterval = 7.5
    var walkStop: CFTimeInterval = 8.25
    var walkAmountRange: ClosedRange<CGFloat> = 0.25...0.5
    var yOffset: CGFloat = 0
    var flipXOffset: CGFloat = 0
    var characterColor: NSColor = .gray

    // Walk state
    var playCount = 0
    var walkStartTime: CFTimeInterval = 0
    var positionProgress: CGFloat = 0.0
    var isWalking = false
    var isPaused = true
    var pauseEndTime: CFTimeInterval = 0
    var goingRight = true
    var walkStartPos: CGFloat = 0.0
    var walkEndPos: CGFloat = 0.0
    var currentTravelDistance: CGFloat = 500.0
    // Walk endpoints stored in pixels for consistent speed across screen switches
    var walkStartPixel: CGFloat = 0.0
    var walkEndPixel: CGFloat = 0.0
    private var lastDockX: CGFloat?
    private var lastDockWidth: CGFloat?
    private var lastDockTopY: CGFloat?
    var minimumPauseRange: ClosedRange<Double> = 5.0...12.0
    var restartWalkImmediately = false
    var animationKeywordMap: [(keywords: [String], videoName: String, allowsMovement: Bool)] = []
    var animationTagItems: [(title: String, videoName: String, allowsMovement: Bool)] = []
    var formPairMap: [String: (videoName: String, allowsMovement: Bool)] = [:]
    var currentAnimationAllowsMovement = true
    var manualWindowOrigin: NSPoint?
    var isUserHidden = false
    var isDraggingManually = false
    private enum DragMood {
        case held
        case leadForward
        case pulledBehind
        case lifted
        case pressedDown
    }
    private var dragMood: DragMood?
    private var dragGrabPoint: NSPoint = .zero
    private var lastDragMoodUpdate: CFTimeInterval = 0

    // Onboarding
    var isOnboarding = false

    // Popover state
    var isIdleForPopover = false
    var popoverWindow: NSWindow?
    var terminalView: TerminalView?
    var agentSession: (any AgentSession)?
    var codexSession: (any AgentSession)?
    private var activeChatProvider: AgentProvider = .hermes
    private var providerBubbleButtons: [AgentProvider: NSButton] = [:]
    private var utilityStripView: NSView?
    private var utilityStripProvider: AgentProvider?
    private var utilityStripSignature = ""
    private var popoverFollowsCharacter = false
    private var hermesSidebarView: NSView?
    private var hermesThreadButtons: [NSButton] = []
    private var selectedHermesThreadID: String?
    private var selectedHermesThreadTitle: String?
    private var codexSidebarView: NSView?
    private var codexThreadButtons: [NSButton] = []
    private var selectedCodexThreadID: String?
    private var selectedCodexThreadTitle: String?
    var chatTitleLabel: NSTextField?
    var animationTagButtons: [NSButton] = []
    var clickOutsideMonitor: Any?
    var escapeKeyMonitor: Any?
    var actionMenuWindows: [NSWindow] = []
    var actionMenuMonitor: Any?
    var currentStreamingText = ""
    weak var controller: MOrangeCompanionController?
    var themeOverride: PopoverTheme?
    var isAgentBusy: Bool {
        (agentSession?.isBusy ?? false) || (codexSession?.isBusy ?? false)
    }
    var thinkingBubbleWindow: NSWindow?
    private var permissionWindow: NSWindow?
    private weak var pendingPermissionSession: HermesSession?
    private var pendingPermissionRequestID: String?
    private var gatewayInputWindow: NSWindow?
    private weak var pendingGatewayInputSession: HermesSession?
    private var pendingGatewayInputRequest: HermesGatewayInputRequest?
    private var gatewayInputField: NSTextField?
    private var memoryInboxWindow: NSWindow?
    private var memoryInboxFilter = "ALL"
    private var memoryCandidateEditors: [String: NSTextField] = [:]
    var petState: PetState = .walking
    private var stateToken = 0
    private var lastPetStateAppliedAt: CFTimeInterval = 0
    private var lastVoiceAnimationMode = ""
    private var lastInteractionTime: CFTimeInterval = CACurrentMediaTime()
    private var interactionHoldUntil: CFTimeInterval = 0
    private var nextAmbientStateAt: CFTimeInterval = CACurrentMediaTime() + Double.random(in: 7...16)

    var session: (any AgentSession)? {
        get { currentSession }
        set { setSession(newValue, for: activeChatProvider) }
    }

    var currentSession: (any AgentSession)? {
        session(for: activeChatProvider)
    }

    private func session(for provider: AgentProvider) -> (any AgentSession)? {
        switch provider {
        case .codex:
            return codexSession
        default:
            return agentSession
        }
    }

    private func setSession(_ session: (any AgentSession)?, for provider: AgentProvider) {
        switch provider {
        case .codex:
            codexSession = session
        default:
            agentSession = session
        }
    }

    init(videoName: String) {
        self.defaultVideoName = videoName
        self.currentVideoName = videoName
    }

    // MARK: - Setup

    private func videoURL(for videoName: String) -> URL? {
        if let bundled = Bundle.main.url(forResource: videoName, withExtension: "mov") {
            return bundled
        }
        for directory in Self.animationSearchDirectories {
            let external = directory.appendingPathComponent("\(videoName).mov")
            if FileManager.default.fileExists(atPath: external.path) {
                return external
            }
        }
        return nil
    }

    private func scale(for videoName: String) -> CGFloat {
        animationScaleMap[videoName] ?? 1.0
    }

    private func applyDisplaySizing(preserveBottom: Bool = true) {
        guard let window, let hostView = window.contentView else { return }

        let oldFrame = window.frame
        let oldMidX = oldFrame.midX
        let newSize = NSSize(width: displayWidth, height: displayHeight)
        let newOrigin: NSPoint
        if let manualWindowOrigin {
            newOrigin = manualWindowOrigin
        } else {
            let newX = oldMidX - newSize.width / 2
            let newY = preserveBottom ? oldFrame.minY : oldFrame.minY - (newSize.height - oldFrame.height) / 2
            newOrigin = NSPoint(x: newX, y: newY)
        }

        playerLayer.frame = CGRect(origin: .zero, size: newSize)
        hostView.frame = CGRect(origin: .zero, size: newSize)
        hostView.layer?.frame = CGRect(origin: .zero, size: newSize)
        window.setFrame(CGRect(origin: newOrigin, size: newSize), display: true)
        if manualWindowOrigin != nil {
            manualWindowOrigin = newOrigin
        }
    }

    func setup() {
        guard let videoURL = videoURL(for: currentVideoName) else {
            print("Video \(currentVideoName) not found")
            return
        }

        currentAnimationScale = scale(for: currentVideoName)

        let asset = AVURLAsset(url: videoURL)
        queuePlayer = AVQueuePlayer()
        looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(asset: asset))

        playerLayer = AVPlayerLayer(player: queuePlayer)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.frame = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)

        let screen = controller?.activeScreen ?? NSScreen.main ?? NSScreen.screens.first!
        let dockTopY = screen.visibleFrame.origin.y
        let bottomPadding = displayHeight * 0.15
        let y = dockTopY - bottomPadding + yOffset

        let contentRect = CGRect(x: 0, y: y, width: displayWidth, height: displayHeight)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = Self.characterWindowLevel
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let hostView = CharacterContentView(frame: CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight))
        hostView.character = self
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = NSColor.clear.cgColor
        hostView.layer?.addSublayer(playerLayer)

        window.contentView = hostView
        isUserHidden = false
        window.orderFrontRegardless()
        queuePlayer.play()
    }

    func hideByUser() {
        isUserHidden = true
        window?.orderOut(nil)
        queuePlayer?.pause()
    }

    func showByUser() {
        isUserHidden = false
        repairVisibilityIfNeeded()
        window?.orderFrontRegardless()
        queuePlayer?.play()
    }

    func switchAnimation(to videoName: String, allowsMovement: Bool, preserveCurrentPosition: Bool = false) {
        if videoName == currentVideoName && allowsMovement == currentAnimationAllowsMovement { return }
        guard let videoURL = videoURL(for: videoName) else {
            print("Video \(videoName) not found")
            return
        }

        currentVideoName = videoName
        currentAnimationScale = scale(for: videoName)
        currentAnimationAllowsMovement = allowsMovement
        let asset = AVURLAsset(url: videoURL)
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.12
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        playerLayer.add(transition, forKey: "morangeStateVideoFade")
        let previousPlayer = queuePlayer
        looper?.disableLooping()
        let nextPlayer = AVQueuePlayer()
        looper = AVPlayerLooper(player: nextPlayer, templateItem: AVPlayerItem(asset: asset))
        queuePlayer = nextPlayer
        playerLayer.player = nextPlayer
        previousPlayer?.pause()
        previousPlayer?.removeAllItems()
        applyDisplaySizing()
        if preserveCurrentPosition {
            synchronizeProgressWithCurrentWindowOrigin()
        }
        queuePlayer.seek(to: .zero)
        if allowsMovement {
            isWalking = false
            isPaused = true
            pauseEndTime = CACurrentMediaTime()
            queuePlayer.play()
        } else {
            isWalking = false
            isPaused = false
            goingRight = true
            updateFlip()
            queuePlayer.play()
        }
        updateAnimationTagSelection()
    }

    func applyAnimationTrigger(for message: String) {
        let normalized = message.lowercased()
        for entry in animationKeywordMap {
            if entry.keywords.contains(where: { normalized.contains($0.lowercased()) }) {
                switchAnimation(to: entry.videoName, allowsMovement: entry.allowsMovement)
                return
            }
        }
    }

    func applyStateForOutgoingMessage(_ message: String) {
        let normalized = message.lowercased()
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            applyPetState(.working, phrase: "执行 Hermes 指令", completion: false)
        } else if activeChatProvider == .codex {
            applyPetState(.working, phrase: "Codex 开工啦", completion: false)
        } else if containsAny(normalized, ["飞起来", "飞一下", "上拎", "拎起来", "向上抓", "抓起来"]) {
            applyNamedInteraction(.lifted)
        } else if containsAny(normalized, ["拽尾巴", "尾巴", "身后拖", "往后拽", "反向拖"]) {
            applyNamedInteraction(.dragBehind)
        } else if containsAny(normalized, ["向前拽", "往前拽", "牵着走", "向前拖", "顺着走"]) {
            applyNamedInteraction(.dragForward)
        } else if containsAny(normalized, ["下压", "按下去", "按住", "往下按", "压扁"]) {
            applyNamedInteraction(.pressed)
        } else if containsAny(normalized, ["戳", "戳戳", "点点"]) {
            applyNamedInteraction(.poke)
        } else if containsAny(normalized, ["气鼓鼓", "鼓起来", "充气", "捏", "揉", "捧"]) {
            applyPetState(.puffed, phrase: Self.puffedPhrases.randomElement() ?? "小橘子鼓起来啦", completion: false, autoReturnAfter: 6.0)
        } else if containsAny(normalized, ["贴贴", "抱抱", "摸摸", "陪我", "撒娇"]) {
            applyPetState(.affection, phrase: Self.affectionPhrases.randomElement() ?? "小橘子在这", completion: false, autoReturnAfter: 6.0)
        } else if containsAny(normalized, ["代码", "脚本", "文件", "目录", "运行", "构建", "测试", "生成", "下载", "安装", "修复", "分析", "project", "script", "run", "build", "test"]) {
            applyPetState(.working, phrase: "小橘子开工啦", completion: false)
        } else {
            applyPetState(.thinking, phrase: "我翻翻记忆", completion: false)
        }
    }

    private func applyNamedInteraction(_ state: PetState) {
        let phrase: String
        switch state {
        case .poke:
            phrase = Self.pokedPhrases.randomElement() ?? "戳到小橘子啦"
        case .puffed:
            phrase = Self.puffedPhrases.randomElement() ?? "小橘子鼓起来啦"
        case .affection:
            phrase = Self.affectionPhrases.randomElement() ?? "小橘子贴过来"
        case .lifted:
            phrase = "飞起来啦"
        case .dragBehind:
            phrase = "哎哎，别拽尾巴"
        case .dragForward:
            phrase = "好，向前走"
        case .pressed:
            phrase = "噗，被按住啦"
        case .held:
            phrase = "被主人捏住啦"
        default:
            phrase = state.title
        }
        applyPetState(state, phrase: phrase, completion: true, autoReturnAfter: 6.0)
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0.lowercased()) }
    }

    func applyPetState(_ state: PetState, phrase: String? = nil, completion: Bool = false, autoReturnAfter: Double? = nil) {
        let now = CACurrentMediaTime()
        if state == petState,
           phrase == nil,
           !completion,
           now - lastPetStateAppliedAt < 0.35 {
            return
        }
        lastPetStateAppliedAt = now
        petState = state
        if state != .sleepy {
            lastInteractionTime = CACurrentMediaTime()
        }
        if state.isInteractive {
            interactionHoldUntil = max(interactionHoldUntil, CACurrentMediaTime() + (autoReturnAfter ?? 6.0))
        }
        if state != .sleepy {
            nextAmbientStateAt = CACurrentMediaTime() + Double.random(in: 7...18)
        }
        stateToken += 1
        let token = stateToken
        let target = state.video
        switchAnimation(to: target.name, allowsMovement: target.allowsMovement, preserveCurrentPosition: true)
        updateChatUI()
        playMicroAnimation(for: state)

        if state == .confused {
            playConfusedSound()
        }

        if let phrase {
            currentPhrase = phrase
            showingCompletion = completion
            completionBubbleExpiry = CACurrentMediaTime() + (completion ? 3.0 : 2.0)
            phraseAnimating = false
            if !isIdleForPopover {
                showBubble(text: phrase, isCompletion: completion)
            }
        }

        if let autoReturnAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + autoReturnAfter) { [weak self] in
                guard let self = self, self.stateToken == token, !self.isAgentBusy else { return }
                guard !self.isDraggingManually else { return }
                if self.isIdleForPopover {
                    self.applyPetState(.listening)
                } else if CACurrentMediaTime() >= self.interactionHoldUntil {
                    self.applyRandomAmbientState()
                }
            }
        }
    }

    private func applyRandomAmbientState() {
        guard !isDraggingManually, !isAgentBusy, !isIdleForPopover else { return }
        guard CACurrentMediaTime() >= interactionHoldUntil else { return }

        let candidates: [PetState] = [.walking, .listening, .thinking, .sleepy, .affection, .puffed]
        let next = candidates.filter { $0 != petState }.randomElement() ?? .thinking
        let phrase: String?
        switch next {
        case .listening:
            phrase = ["我在这", "听主人说", "小橘子待命"].randomElement()
        case .thinking:
            phrase = ["翻翻记忆", "想一点小事", "我整理一下"].randomElement()
        case .sleepy:
            phrase = ["小橘子充会电", "困困一下", "眯一小会"].randomElement()
        case .affection:
            phrase = Self.affectionPhrases.randomElement()
        case .puffed:
            phrase = Self.puffedPhrases.randomElement()
        default:
            phrase = nil
        }
        applyPetState(next, phrase: phrase, completion: false, autoReturnAfter: next.isInteractive ? 5.5 : nil)
        nextAmbientStateAt = CACurrentMediaTime() + Double.random(in: 6...18)
    }

    private func maybeApplyAmbientState(now: CFTimeInterval) {
        guard now >= nextAmbientStateAt else { return }
        applyRandomAmbientState()
    }

    func cycleAnimationForward() {
        var animationSequence: [(videoName: String, allowsMovement: Bool)] = [
            (defaultVideoName, true)
        ]
        for entry in animationKeywordMap {
            if !animationSequence.contains(where: { $0.videoName == entry.videoName }) {
                animationSequence.append((entry.videoName, entry.allowsMovement))
            }
        }

        guard !animationSequence.isEmpty else { return }
        let currentIndex = animationSequence.firstIndex {
            $0.videoName == currentVideoName && $0.allowsMovement == currentAnimationAllowsMovement
        } ?? -1
        let nextIndex = (currentIndex + 1) % animationSequence.count
        let nextAnimation = animationSequence[nextIndex]
        switchAnimation(to: nextAnimation.videoName, allowsMovement: nextAnimation.allowsMovement)
    }

    func toggleFormForCurrentAnimation() {
        guard let pair = formPairMap[currentVideoName] else { return }
        closeActionMenu()
        switchAnimation(to: pair.videoName, allowsMovement: pair.allowsMovement, preserveCurrentPosition: true)
    }

    // MARK: - Click Handling & Popover

    func handleClick() {
        if isOnboarding {
            openOnboardingPopover()
            return
        }
        if isIdleForPopover {
            closePopover()
        } else {
            applyPokeInteraction(openChat: true)
            openPopover()
        }
    }

    func toggleActionMenu() {
        if isOnboarding {
            openOnboardingPopover()
            return
        }
        if !actionMenuWindows.isEmpty {
            closeActionMenu()
            return
        }
        if isIdleForPopover {
            closePopover()
        }
        applyPetState(.puffed, phrase: Self.puffedPhrases.randomElement() ?? "小橘子鼓起来啦", completion: true, autoReturnAfter: 6.0)
        openActionMenu()
    }

    func applyPokeInteraction(openChat: Bool = false) {
        let phrase = openChat ? "噗一下，主人叫我？" : (Self.pokedPhrases.randomElement() ?? "戳到小橘子啦")
        applyPetState(.poke, phrase: phrase, completion: true, autoReturnAfter: openChat ? 5.5 : 6.0)
    }

    func playInflatablePress() {
        playInflatableBounce(strength: 0.72)
    }

    private func playMicroAnimation(for state: PetState) {
        guard let layer = window?.contentView?.layer else { return }
        layer.removeAnimation(forKey: "morangeMicroMotion")

        switch state {
        case .walking:
            playFloatMotion(on: layer, y: [0, 1.5, 0], duration: 1.8, repeatCount: 1, key: state.microMotionKey)
        case .listening:
            playScaleMotion(on: layer, values: [(1, 1), (1.02, 0.99), (1, 1)], duration: 0.42, key: state.microMotionKey)
        case .thinking:
            playRotateMotion(on: layer, degrees: [0, -2.8, 2.2, -1.2, 0], duration: 0.74, key: state.microMotionKey)
        case .working:
            playScaleMotion(on: layer, values: [(1, 1), (1.035, 1.035), (1, 1)], duration: 0.52, key: state.microMotionKey)
        case .done:
            playFloatMotion(on: layer, y: [0, 12, -3, 0], duration: 0.46, repeatCount: 1, key: state.microMotionKey)
        case .confused:
            playTranslateMotion(on: layer, x: [0, -7, 6, -5, 4, 0], duration: 0.42, key: state.microMotionKey)
        case .sleepy:
            playScaleMotion(on: layer, values: [(1, 1), (1.018, 0.985), (1, 1)], duration: 1.65, key: state.microMotionKey)
        case .affection:
            playRotateMotion(on: layer, degrees: [0, 3.6, -1.8, 1.2, 0], duration: 0.62, key: state.microMotionKey)
        case .poke:
            playTranslateMotion(on: layer, x: [0, -5, 6, -3, 0], duration: 0.28, key: state.microMotionKey)
        case .puffed:
            playInflatableBounce(strength: 1.0)
        case .held:
            playScaleMotion(on: layer, values: [(1, 1), (1.08, 0.92), (1.02, 0.98), (1, 1)], duration: 0.38, key: state.microMotionKey)
        case .dragForward:
            playRotateMotion(on: layer, degrees: [0, goingRight ? 5 : -5, goingRight ? 2 : -2], duration: 0.42, key: state.microMotionKey)
        case .dragBehind:
            playRotateMotion(on: layer, degrees: [0, goingRight ? -6 : 6, goingRight ? -2 : 2], duration: 0.42, key: state.microMotionKey)
        case .lifted:
            playFloatMotion(on: layer, y: [0, 15, 8, 12], duration: 0.48, repeatCount: 1, key: state.microMotionKey)
        case .pressed:
            playScaleMotion(on: layer, values: [(1, 1), (1.14, 0.82), (1.06, 0.91), (1, 1)], duration: 0.42, key: state.microMotionKey)
        }
    }

    private func playScaleMotion(on layer: CALayer, values: [(CGFloat, CGFloat)], duration: CFTimeInterval, key: String) {
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = values.map { CATransform3DMakeScale($0.0, $0.1, 1) }
        animation.duration = duration
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: max(values.count - 1, 1))
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: "morangeMicroMotion")
    }

    private func playRotateMotion(on layer: CALayer, degrees: [CGFloat], duration: CFTimeInterval, key: String) {
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = degrees.map { $0 * .pi / 180 }
        animation.duration = duration
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: max(degrees.count - 1, 1))
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: "morangeMicroMotion")
    }

    private func playTranslateMotion(on layer: CALayer, x: [CGFloat], duration: CFTimeInterval, key: String) {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = x
        animation.duration = duration
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: max(x.count - 1, 1))
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: "morangeMicroMotion")
    }

    private func playFloatMotion(on layer: CALayer, y: [CGFloat], duration: CFTimeInterval, repeatCount: Float, key: String) {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animation.values = y
        animation.duration = duration
        animation.repeatCount = repeatCount
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: max(y.count - 1, 1))
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: "morangeMicroMotion")
    }

    private func playInflatableBounce(strength: CGFloat) {
        guard let layer = window?.contentView?.layer else { return }
        let x1 = 1.0 + 0.12 * strength
        let y1 = max(0.86, 1.0 - 0.08 * strength)
        let x2 = max(0.90, 1.0 - 0.05 * strength)
        let y2 = 1.0 + 0.10 * strength
        let x3 = 1.0 + 0.04 * strength
        let y3 = max(0.92, 1.0 - 0.03 * strength)

        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [
            CATransform3DIdentity,
            CATransform3DMakeScale(x1, y1, 1),
            CATransform3DMakeScale(x2, y2, 1),
            CATransform3DMakeScale(x3, y3, 1),
            CATransform3DIdentity
        ]
        animation.keyTimes = [0, 0.22, 0.52, 0.78, 1]
        animation.duration = 0.46
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        layer.add(animation, forKey: "morangeInflatableBounce")
    }

    private func openActionMenu() {
        closeActionMenu()
        guard let window else { return }

        // Keep the pet alive while the action petals are open: stop travel, not animation.
        isWalking = false
        isPaused = false
        queuePlayer.play()

        let actionItems = flowerMenuItems()
        let origin = NSPoint(x: window.frame.midX, y: window.frame.midY + 8)
        let columns = actionMenuLayout(items: actionItems, origin: origin, screenFrame: window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)

        for (index, layout) in columns.enumerated() {
            let item = layout.item
            let startFrame = NSRect(x: origin.x - layout.size.width / 2, y: origin.y - layout.size.height / 2, width: layout.size.width, height: layout.size.height)
            let finalFrame = NSRect(x: layout.center.x - layout.size.width / 2, y: layout.center.y - layout.size.height / 2, width: layout.size.width, height: layout.size.height)

            let petal = makeActionPetalWindow(item: item, frame: startFrame, index: index)
            actionMenuWindows.append(petal)
            petal.alphaValue = 0
            petal.orderFrontRegardless()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.028 * Double(index)) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    petal.animator().setFrame(finalFrame, display: true)
                    petal.animator().alphaValue = 1
                }
            }
        }

        actionMenuMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeActionMenu()
        }
    }

    private struct ActionMenuLayout {
        let item: FlowerMenuItem
        let center: NSPoint
        let size: NSSize
    }

    private struct FlowerMenuItem {
        let title: String
        let icon: String
        let videoName: String?
        let allowsMovement: Bool
        let isChat: Bool
        let isDanger: Bool
        let command: String?
    }

    private func flowerMenuItems() -> [FlowerMenuItem] {
        var items = [
            FlowerMenuItem(title: "聊天", icon: "💬", videoName: nil, allowsMovement: false, isChat: true, isDanger: false, command: "__chat__"),
            FlowerMenuItem(title: "戳戳", icon: "✦", videoName: nil, allowsMovement: false, isChat: false, isDanger: false, command: "__poke__"),
            FlowerMenuItem(title: "气鼓鼓", icon: "😤", videoName: nil, allowsMovement: false, isChat: false, isDanger: false, command: "__puffed__"),
            FlowerMenuItem(title: "贴贴", icon: "♡", videoName: nil, allowsMovement: false, isChat: false, isDanger: false, command: "__affection__"),
            FlowerMenuItem(title: "飞起", icon: "↟", videoName: nil, allowsMovement: false, isChat: false, isDanger: false, command: "__lifted__"),
            FlowerMenuItem(title: "拽尾", icon: "⌁", videoName: nil, allowsMovement: false, isChat: false, isDanger: false, command: "__dragBehind__"),
            FlowerMenuItem(title: "前拽", icon: "➜", videoName: nil, allowsMovement: false, isChat: false, isDanger: false, command: "__dragForward__"),
            FlowerMenuItem(title: "下压", icon: "⬇", videoName: nil, allowsMovement: false, isChat: false, isDanger: false, command: "__pressed__"),
            FlowerMenuItem(title: "关闭", icon: "⏻", videoName: nil, allowsMovement: false, isChat: false, isDanger: true, command: "__quit__")
        ]
        for tag in animationTagItems.prefix(8) {
            items.append(FlowerMenuItem(title: tag.title, icon: stateMenuIcon(for: tag.title), videoName: tag.videoName, allowsMovement: tag.allowsMovement, isChat: false, isDanger: false, command: nil))
        }
        return items
    }

    private func stateMenuIcon(for title: String) -> String {
        switch title {
        case "走路": return "👣"
        case "待机": return "☕"
        case "思考": return "💭"
        case "工作": return "🛠"
        case "完成": return "✓"
        case "困惑": return "?"
        case "困困": return "💤"
        case "开心": return "😊"
        default: return "✦"
        }
    }

    private func actionMenuLayout(items: [FlowerMenuItem], origin: NSPoint, screenFrame: NSRect?) -> [ActionMenuLayout] {
        let primary = items.filter { $0.command != nil }
        let states = items.filter { $0.command == nil }
        let rowSpacing: CGFloat = 48
        let itemSize = NSSize(width: 104, height: 38)
        let chatSize = NSSize(width: 112, height: 38)
        let largestWidth = max(itemSize.width, chatSize.width)
        let visible = screenFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let minX = visible.minX + largestWidth / 2 + 12
        let maxX = visible.maxX - largestWidth / 2 - 12
        let leftX = clamp(origin.x - 220, minX, maxX)
        let rightX = clamp(origin.x + 220, minX, maxX)

        func makeColumn(_ columnItems: [FlowerMenuItem], x: CGFloat) -> [ActionMenuLayout] {
            let totalHeight = rowSpacing * CGFloat(max(columnItems.count - 1, 0))
            let minTopY = visible.minY + itemSize.height / 2 + totalHeight + 12
            let maxTopY = visible.maxY - itemSize.height / 2 - 12
            let topY = clamp(origin.y + totalHeight / 2, minTopY, maxTopY)
            return columnItems.enumerated().map { index, item in
                ActionMenuLayout(
                    item: item,
                    center: NSPoint(x: x, y: topY - CGFloat(index) * rowSpacing),
                    size: item.isChat ? chatSize : itemSize
                )
            }
        }

        return makeColumn(primary, x: leftX) + makeColumn(states, x: rightX)
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    private func makeActionPetalWindow(item: FlowerMenuItem, frame: NSRect, index: Int) -> NSWindow {
        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 24)
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let button = NSButton(frame: NSRect(origin: .zero, size: frame.size))
        button.title = "\(item.icon)  \(item.title)"
        button.isBordered = false
        button.font = .systemFont(ofSize: 13, weight: .heavy)
        button.contentTintColor = item.isDanger ? NSColor(red: 0.68, green: 0.12, blue: 0.12, alpha: 1) : (item.isChat ? NSColor(red: 0.62, green: 0.21, blue: 0.13, alpha: 1) : petalTextColor(index: index))
        button.identifier = NSUserInterfaceItemIdentifier(item.command ?? "\(item.videoName ?? "")|\(item.allowsMovement ? "1" : "0")")
        button.target = self
        button.action = #selector(selectActionPetal(_:))
        button.wantsLayer = true
        button.layer?.masksToBounds = false
        button.layer?.cornerRadius = frame.height / 2
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.shadowColor = petalShadowColor(index: index, isChat: item.isChat).cgColor
        button.layer?.shadowOpacity = 1
        button.layer?.shadowRadius = 12
        button.layer?.shadowOffset = CGSize(width: 0, height: -5)

        let base = item.isDanger ? NSColor(red: 1.0, green: 0.78, blue: 0.72, alpha: 0.56) : (item.isChat ? NSColor(red: 1.0, green: 0.76, blue: 0.68, alpha: 0.48) : petalColor(index: index))
        let gradient = CAGradientLayer()
        gradient.frame = button.bounds
        gradient.cornerRadius = frame.height / 2
        gradient.colors = [
            NSColor.white.withAlphaComponent(0.62).cgColor,
            base.blended(withFraction: 0.42, of: .white)?.withAlphaComponent(0.46).cgColor ?? base.withAlphaComponent(0.46).cgColor,
            base.withAlphaComponent(0.34).cgColor
        ]
        gradient.locations = [0, 0.45, 1]
        gradient.startPoint = CGPoint(x: 0.25, y: 1)
        gradient.endPoint = CGPoint(x: 0.85, y: 0)
        button.layer?.insertSublayer(gradient, at: 0)

        let acrylicWash = CALayer()
        acrylicWash.frame = button.bounds.insetBy(dx: 2.5, dy: 2.5)
        acrylicWash.cornerRadius = max(0, frame.height / 2 - 2.5)
        acrylicWash.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        button.layer?.addSublayer(acrylicWash)

        let rim = CAShapeLayer()
        rim.frame = button.bounds
        rim.path = CGPath(roundedRect: button.bounds.insetBy(dx: 1.2, dy: 1.2), cornerWidth: frame.height / 2, cornerHeight: frame.height / 2, transform: nil)
        rim.fillColor = NSColor.clear.cgColor
        rim.strokeColor = NSColor.white.withAlphaComponent(0.92).cgColor
        rim.lineWidth = 1.8
        button.layer?.addSublayer(rim)

        let highlight = CAShapeLayer()
        highlight.frame = button.bounds
        highlight.path = CGPath(roundedRect: NSRect(x: 8, y: frame.height * 0.54, width: frame.width - 16, height: frame.height * 0.32), cornerWidth: frame.height * 0.16, cornerHeight: frame.height * 0.16, transform: nil)
        highlight.fillColor = NSColor.white.withAlphaComponent(0.34).cgColor
        button.layer?.addSublayer(highlight)

        if let cell = button.cell as? NSButtonCell {
            cell.wraps = false
            cell.lineBreakMode = .byTruncatingTail
            cell.alignment = .center
        }
        win.contentView = button
        return win
    }

    private func petalColor(index: Int) -> NSColor {
        let colors: [NSColor] = [
            NSColor(red: 0.70, green: 0.86, blue: 1.00, alpha: 0.48),
            NSColor(red: 1.00, green: 0.87, blue: 0.56, alpha: 0.48),
            NSColor(red: 0.84, green: 0.95, blue: 0.68, alpha: 0.48),
            NSColor(red: 1.00, green: 0.76, blue: 0.88, alpha: 0.48),
            NSColor(red: 0.82, green: 0.76, blue: 1.00, alpha: 0.48),
            NSColor(red: 0.65, green: 0.94, blue: 0.88, alpha: 0.48)
        ]
        return colors[index % colors.count]
    }

    private func petalTextColor(index: Int) -> NSColor {
        let colors: [NSColor] = [
            NSColor(red: 0.08, green: 0.36, blue: 0.52, alpha: 1),
            NSColor(red: 0.52, green: 0.31, blue: 0.04, alpha: 1),
            NSColor(red: 0.25, green: 0.43, blue: 0.13, alpha: 1),
            NSColor(red: 0.65, green: 0.18, blue: 0.43, alpha: 1),
            NSColor(red: 0.33, green: 0.25, blue: 0.62, alpha: 1),
            NSColor(red: 0.06, green: 0.42, blue: 0.38, alpha: 1)
        ]
        return colors[index % colors.count]
    }

    private func petalShadowColor(index: Int, isChat: Bool) -> NSColor {
        if isChat { return NSColor(red: 1.0, green: 0.42, blue: 0.26, alpha: 0.28) }
        return petalColor(index: index).withAlphaComponent(0.42)
    }

    @objc private func selectActionPetal(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        closeActionMenu()
        if raw == "__chat__" {
            openChatProviderChooser()
            return
        } else if raw == "__poke__" {
            applyPokeInteraction()
            return
        } else if raw == "__puffed__" {
            applyPetState(.puffed, phrase: Self.puffedPhrases.randomElement() ?? "小橘子鼓起来啦", completion: true, autoReturnAfter: 6.0)
            return
        } else if raw == "__affection__" {
            applyNamedInteraction(.affection)
            return
        } else if raw == "__lifted__" {
            applyNamedInteraction(.lifted)
            return
        } else if raw == "__dragBehind__" {
            applyNamedInteraction(.dragBehind)
            return
        } else if raw == "__dragForward__" {
            applyNamedInteraction(.dragForward)
            return
        } else if raw == "__pressed__" {
            applyNamedInteraction(.pressed)
            return
        } else if raw == "__quit__" {
            applyPetState(.sleepy, phrase: "小橘子下线啦", completion: true, autoReturnAfter: 2.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                NSApp.terminate(nil)
            }
            return
        }
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard let videoName = parts.first, !videoName.isEmpty else { return }
        let allowsMovement = parts.dropFirst().first == "1"
        switchAnimation(to: videoName, allowsMovement: allowsMovement)
    }

    private func closeActionMenu() {
        if let monitor = actionMenuMonitor {
            NSEvent.removeMonitor(monitor)
            actionMenuMonitor = nil
        }
        let windows = actionMenuWindows
        actionMenuWindows = []
        for (index, win) in windows.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.012 * Double(index)) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.11
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    win.animator().alphaValue = 0
                } completionHandler: {
                    win.orderOut(nil)
                }
            }
        }
    }

    private func openChatProviderChooser() {
        closeActionMenu()
        guard let window else { return }

        isWalking = false
        isPaused = false
        queuePlayer.play()
        applyPetState(.listening, phrase: "选聊天入口", completion: false)

        let providers: [(AgentProvider, String, String)] = [
            (.hermes, "Hermes", "小橘子本体"),
            (.codex, "Codex", "本机代码工作")
        ]
        let size = NSSize(width: 138, height: 46)
        let gap: CGFloat = 12
        let totalWidth = size.width * 2 + gap
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let baseX = clamp(window.frame.midX - totalWidth / 2, visible.minX + 12, visible.maxX - totalWidth - 12)
        let y = clamp(window.frame.maxY + 10, visible.minY + 12, visible.maxY - size.height - 12)

        for (index, providerInfo) in providers.enumerated() {
            let frame = NSRect(x: baseX + CGFloat(index) * (size.width + gap), y: y, width: size.width, height: size.height)
            let bubble = makeChatProviderChoiceWindow(provider: providerInfo.0, title: providerInfo.1, subtitle: providerInfo.2, frame: frame)
            actionMenuWindows.append(bubble)
            bubble.alphaValue = 0
            bubble.orderFrontRegardless()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04 * Double(index)) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    bubble.animator().alphaValue = 1
                }
            }
        }

        actionMenuMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeActionMenu()
        }
    }

    private func makeChatProviderChoiceWindow(provider: AgentProvider, title: String, subtitle: String, frame: NSRect) -> NSWindow {
        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 26)
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let button = NSButton(frame: NSRect(origin: .zero, size: frame.size))
        button.identifier = NSUserInterfaceItemIdentifier(provider.rawValue)
        button.isBordered = false
        button.title = ""
        button.target = self
        button.action = #selector(selectChatProviderChoice(_:))
        button.wantsLayer = true
        button.layer?.cornerRadius = frame.height / 2
        button.layer?.cornerCurve = .continuous
        button.layer?.borderWidth = 1.4
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.88).cgColor
        button.layer?.backgroundColor = (provider == .codex
            ? NSColor(red: 0.90, green: 0.95, blue: 1.0, alpha: 0.76)
            : NSColor(red: 1.0, green: 0.82, blue: 0.58, alpha: 0.78)
        ).cgColor
        button.layer?.shadowColor = NSColor(red: 0.45, green: 0.26, blue: 0.10, alpha: 0.20).cgColor
        button.layer?.shadowOpacity = 1
        button.layer?.shadowRadius = 11
        button.layer?.shadowOffset = CGSize(width: 0, height: -4)

        let textColor = provider == .codex
            ? NSColor(red: 0.16, green: 0.28, blue: 0.42, alpha: 1)
            : NSColor(red: 0.55, green: 0.23, blue: 0.10, alpha: 1)
        button.addSubview(makeLabel(title, frame: NSRect(x: 0, y: 22, width: frame.width, height: 16), fontSize: 13, weight: .heavy, color: textColor, alignment: .center))
        button.addSubview(makeLabel(subtitle, frame: NSRect(x: 0, y: 9, width: frame.width, height: 12), fontSize: 10, weight: .semibold, color: textColor.withAlphaComponent(0.72), alignment: .center))
        win.contentView = button
        return win
    }

    @objc private func selectChatProviderChoice(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let provider = AgentProvider(rawValue: raw) else { return }
        closeActionMenu()
        openPopover(provider: provider)
    }

    func beginManualDrag(grabPoint: NSPoint = .zero) {
        closeActionMenu()
        isDraggingManually = true
        dragMood = nil
        dragGrabPoint = grabPoint
        lastDragMoodUpdate = 0
        manualWindowOrigin = window?.frame.origin
        isWalking = false
        isPaused = false
        queuePlayer.play()
        applyDragMood(.held, force: true)
    }

    func updateManualDragOrigin(_ origin: NSPoint, pointer: NSPoint? = nil, delta: CGVector = .zero) {
        manualWindowOrigin = origin
        window.setFrameOrigin(origin)
        updateDragMood(pointer: pointer, delta: delta)
        updatePopoverPosition()
        updateThinkingBubble()
    }

    func endManualDrag() {
        isDraggingManually = false
        dragMood = nil
        applyPetState(.puffed, phrase: "放好啦，噗", completion: true, autoReturnAfter: 6.0)
    }

    private func updateDragMood(pointer: NSPoint?, delta: CGVector) {
        guard let window else { return }
        let now = CACurrentMediaTime()
        guard now - lastDragMoodUpdate > 0.55 else { return }

        let screen = controller?.activeScreen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let frame = window.frame
        let highLine = visible.minY + visible.height * 0.66
        let lowLine = visible.minY + visible.height * 0.22

        let nextMood: DragMood
        if frame.midY > highLine || delta.dy > 90 {
            nextMood = .lifted
        } else if frame.midY < lowLine || delta.dy < -90 {
            nextMood = .pressedDown
        } else {
            let horizontal = abs(delta.dx) >= abs(delta.dy)
            let movingWithFacing = goingRight ? delta.dx > 12 : delta.dx < -12
            let grabbedFront = goingRight ? dragGrabPoint.x > displayWidth * 0.52 : dragGrabPoint.x < displayWidth * 0.48
            if horizontal && movingWithFacing && grabbedFront {
                nextMood = .leadForward
            } else if horizontal && !movingWithFacing && abs(delta.dx) > 12 {
                nextMood = .pulledBehind
            } else {
                nextMood = .held
            }
        }

        applyDragMood(nextMood)
    }

    private func applyDragMood(_ mood: DragMood, force: Bool = false) {
        guard force || dragMood != mood else { return }
        dragMood = mood
        lastDragMoodUpdate = CACurrentMediaTime()

        let phrase: String
        switch mood {
        case .held:
            phrase = "被主人捏住啦"
            applyPetState(.held, phrase: phrase, completion: false)
            return
        case .leadForward:
            phrase = "好，往前走"
            applyPetState(.dragForward, phrase: phrase, completion: false)
            return
        case .pulledBehind:
            phrase = "哎哎，尾巴方向"
            applyPetState(.dragBehind, phrase: phrase, completion: false)
            return
        case .lifted:
            phrase = "被拎起来啦"
            applyPetState(.lifted, phrase: phrase, completion: false)
            return
        case .pressedDown:
            phrase = "噗，按回下面"
            applyPetState(.pressed, phrase: phrase, completion: false)
            return
        }
    }

    private func openOnboardingPopover() {
        showingCompletion = false
        hideBubble()

        isIdleForPopover = true
        // Opening chat should not freeze the pet. Pause movement only; keep the loop playing.
        isWalking = false
        isPaused = false
        queuePlayer.play()

        if popoverWindow == nil {
            createPopoverWindow()
        }

        // Show static welcome message instead of Claude terminal
        terminalView?.inputField.isEditable = false
        terminalView?.inputField.placeholderString = ""
        let welcome = """
        你好，我是小橘子。

        我会在桌面上陪着你。点击我可以打开聊天窗口，默认把消息交给本机 Hermes。

        聊天窗口上方有 Hermes 和 Codex 两个气泡：Hermes 是小橘子本体，Codex 是额外的代码工作入口。

        点窗口外面可以先收起，之后再点我就能继续聊天。
        """
        terminalView?.appendStreamingText(welcome)
        terminalView?.endStreaming()

        updatePopoverPosition(anchorToCharacter: true)
        popoverFollowsCharacter = false
        popoverWindow?.orderFrontRegardless()

        // Set up click-outside to dismiss and complete onboarding
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.closeOnboarding()
        }
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.closeOnboarding(); return nil }
            return event
        }
    }

    private func closeOnboarding() {
        if let monitor = clickOutsideMonitor { NSEvent.removeMonitor(monitor); clickOutsideMonitor = nil }
        if let monitor = escapeKeyMonitor { NSEvent.removeMonitor(monitor); escapeKeyMonitor = nil }
        popoverWindow?.orderOut(nil)
        popoverWindow = nil
        terminalView = nil
        isIdleForPopover = false
        isOnboarding = false
        isPaused = true
        pauseEndTime = CACurrentMediaTime() + Double.random(in: 1.0...3.0)
        queuePlayer.seek(to: .zero)
        controller?.completeOnboarding()
    }

    func openPopover(provider: AgentProvider = .hermes) {
        closeActionMenu()
        activeChatProvider = provider
        // Close any other open popover
        if let siblings = controller?.characters {
            for sibling in siblings where sibling !== self && sibling.isIdleForPopover {
                sibling.closePopover()
            }
        }

        isIdleForPopover = true
        isWalking = false
        isPaused = false
        queuePlayer.play()
        applyPetState(.listening, phrase: "我在听", completion: false)

        // Always clear any bubble (thinking or completion) when popover opens
        showingCompletion = false
        hideBubble()

        if activeChatProvider == .codex {
            ensureCodexSession()
        } else if activeChatProvider == .hermes {
            ensureHermesSession()
        } else {
            ensureSession()
        }

        if popoverWindow == nil {
            createPopoverWindow()
        }

        if let terminal = terminalView, let session = currentSession, !session.history.isEmpty {
            terminal.replayHistory(session.history)
        }
        updateChatUI()

        updatePopoverPosition(anchorToCharacter: true)
        popoverFollowsCharacter = false
        if popoverWindow?.isMiniaturized == true {
            popoverWindow?.deminiaturize(nil)
        }
        popoverWindow?.orderFrontRegardless()
        popoverWindow?.makeKey()

        if let terminal = terminalView {
            popoverWindow?.makeFirstResponder(terminal.inputField)
        }

        // Remove old monitors before adding new ones. The chat window now
        // behaves like a normal macOS window, so clicking elsewhere should not
        // auto-close it; the red close button, Esc, or the pet menu can close it.
        removeEventMonitors()

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.closePopover()
                return nil
            }
            return event
        }
    }

    func closePopover() {
        guard isIdleForPopover else { return }

        popoverWindow?.orderOut(nil)
        removeEventMonitors()

        isIdleForPopover = false

        // If still waiting for a response, show thinking bubble immediately
        // If completion came while popover was open, show completion bubble
        if showingCompletion {
            // Reset expiry so user gets the full 3s from now
            completionBubbleExpiry = CACurrentMediaTime() + 3.0
            showBubble(text: currentPhrase, isCompletion: true)
        } else if isAgentBusy {
            // Force a fresh phrase pick and show immediately
            currentPhrase = ""
            lastPhraseUpdate = 0
            updateThinkingPhrase()
            showBubble(text: currentPhrase, isCompletion: false)
        }

        let delay = Double.random(in: 2.0...5.0)
        isWalking = false
        isPaused = true
        pauseEndTime = CACurrentMediaTime() + delay
    }

    private func removeEventMonitors() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
        if let monitor = actionMenuMonitor {
            NSEvent.removeMonitor(monitor)
            actionMenuMonitor = nil
        }
    }

    var resolvedTheme: PopoverTheme {
        (themeOverride ?? PopoverTheme.current).withCharacterColor(characterColor).withCustomFont()
    }

    func createPopoverWindow() {
        let visibleFrame = (controller?.activeScreen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let popoverWidth: CGFloat = min(1040, max(820, visibleFrame.width - 80))
        let popoverHeight: CGFloat = min(780, max(680, visibleFrame.height - 80))
        let mintWash = NSColor(red: 1.0, green: 0.965, blue: 0.90, alpha: 0.30)
        let border = NSColor(red: 0.95, green: 0.67, blue: 0.36, alpha: 0.32)

        let win = KeyableWindow(
            contentRect: CGRect(x: 0, y: 0, width: popoverWidth, height: popoverHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "小橘子 Hermes"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.toolbarStyle = .unifiedCompact
        win.minSize = NSSize(width: 720, height: 560)
        win.maxSize = NSSize(width: visibleFrame.width - 24, height: visibleFrame.height - 24)
        win.onCloseRequest = { [weak self] in
            self?.closePopover()
        }
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 10)
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.appearance = NSAppearance(named: .aqua)
        win.isMovableByWindowBackground = true

        let root = DraggablePopoverRootView(frame: NSRect(x: 0, y: 0, width: popoverWidth, height: popoverHeight))
        root.onManualDragBegan = { [weak self] in
            self?.popoverFollowsCharacter = false
        }
        root.onManualDragEnded = { [weak self] in
            self?.clampPopoverToVisibleFrame()
        }
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.layer?.shadowColor = NSColor(red: 0.20, green: 0.32, blue: 0.24, alpha: 0.18).cgColor
        root.layer?.shadowOpacity = 1
        root.layer?.shadowRadius = 18
        root.layer?.shadowOffset = CGSize(width: 0, height: -6)
        root.layer?.shadowPath = CGPath(
            roundedRect: root.bounds,
            cornerWidth: 42,
            cornerHeight: 42,
            transform: nil
        )
        root.autoresizingMask = [.width, .height]

        let container = NSView(frame: root.bounds)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.cornerRadius = 42
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1.2
        container.layer?.borderColor = border.withAlphaComponent(0.62).cgColor
        container.autoresizingMask = [.width, .height]
        root.addSubview(container)

        container.layer?.backgroundColor = mintWash.cgColor
        addJournalBackground(to: container)

        if let watermark = makeMOrangeWatermark(frame: NSRect(x: popoverWidth - 260, y: 50, width: 220, height: 220)) {
            container.addSubview(watermark)
        }

        let title = makeLabel("小橘子 · 在线", frame: NSRect(x: 92, y: popoverHeight - 42, width: popoverWidth - 120, height: 22), fontSize: 15, weight: .heavy, color: resolvedTheme.textPrimary)
        title.autoresizingMask = NSView.AutoresizingMask([.width, .minYMargin])
        container.addSubview(title)
        chatTitleLabel = title

        let utilityStrip = makeUtilityStrip(frame: NSRect(x: 18, y: popoverHeight - 234, width: popoverWidth - 36, height: 184))
        container.addSubview(utilityStrip)
        utilityStripView = utilityStrip
        utilityStripProvider = activeChatProvider
        utilityStripSignature = currentUtilityStripSignature()

        let sidebarWidth: CGFloat = 232
        let hermesSidebar = makeHermesSidebar(frame: NSRect(x: 18, y: 18, width: sidebarWidth, height: popoverHeight - 260))
        container.addSubview(hermesSidebar)
        hermesSidebarView = hermesSidebar

        let sidebar = makeCodexSidebar(frame: NSRect(x: 18, y: 18, width: sidebarWidth, height: popoverHeight - 260))
        container.addSubview(sidebar)
        codexSidebarView = sidebar

        let terminal = TerminalView(frame: NSRect(x: 18, y: 18, width: popoverWidth - 36, height: popoverHeight - 260))
        terminal.characterColor = characterColor
        terminal.themeOverride = themeOverride
        terminal.autoresizingMask = [.width, .height]
        terminal.onSendMessageWithAttachments = { [weak self] message, attachments in
            guard let self = self else { return }
            self.applyStateForOutgoingMessage(message)
            self.ensureSession()
            self.currentSession?.send(message: message, attachments: attachments)
        }
        terminal.onShowCapabilities = { [weak self] in
            self?.showAgentCapabilities()
        }
        terminal.onVoiceRecordToggle = { [weak self] in
            self?.toggleHermesVoiceRecording()
        }
        terminal.onVoiceTTSToggle = { [weak self] in
            self?.toggleHermesVoiceTTS()
        }
        terminal.suggestionProvider = { [weak self] text in
            self?.inputSuggestions(for: text) ?? []
        }
        container.addSubview(terminal)

        win.hasShadow = false
        win.contentView = root
        popoverWindow = win
        terminalView = terminal
        updateChatUI()
        updateAnimationTagSelection()
    }

    private func makeProviderBubbleStrip(frame: NSRect) -> NSView {
        providerBubbleButtons.removeAll()

        let strip = NSView(frame: frame)
        strip.wantsLayer = true
        strip.layer?.backgroundColor = NSColor.clear.cgColor

        let providers: [(AgentProvider, String, String)] = [
            (.hermes, "Hermes", "小橘子本体"),
            (.codex, "Codex", "代码工作")
        ]

        let gap: CGFloat = 10
        let bubbleW: CGFloat = 150
        for (idx, item) in providers.enumerated() {
            let x = CGFloat(idx) * (bubbleW + gap)
            let button = NSButton(frame: NSRect(x: x, y: 0, width: bubbleW, height: frame.height))
            button.identifier = NSUserInterfaceItemIdentifier(item.0.rawValue)
            button.isBordered = false
            button.title = ""
            button.wantsLayer = true
            button.target = self
            button.action = #selector(switchChatProviderFromBubble(_:))

            let name = makeLabel(item.1, frame: NSRect(x: 14, y: 15, width: bubbleW - 28, height: 15), fontSize: 12, weight: .heavy, color: resolvedTheme.textPrimary)
            let subtitle = makeLabel(item.2, frame: NSRect(x: 14, y: 4, width: bubbleW - 28, height: 12), fontSize: 9, weight: .semibold, color: resolvedTheme.textDim)
            button.addSubview(name)
            button.addSubview(subtitle)
            strip.addSubview(button)
            providerBubbleButtons[item.0] = button
        }

        let hint = makeLabel("聊天入口", frame: NSRect(x: bubbleW * 2 + gap * 2 + 4, y: 10, width: frame.width - bubbleW * 2 - gap * 2 - 4, height: 14), fontSize: 10, weight: .semibold, color: resolvedTheme.textDim)
        strip.addSubview(hint)

        updateProviderBubbleSelection()
        return strip
    }

    private func makeUtilityStrip(frame: NSRect) -> NSView {
        let t = resolvedTheme
        let strip = NSView(frame: frame)
        strip.wantsLayer = true
        strip.layer?.backgroundColor = NSColor(red: 1.0, green: 0.95, blue: 0.86, alpha: 0.26).cgColor
        strip.layer?.cornerRadius = 18
        strip.layer?.borderWidth = 1
        strip.layer?.borderColor = NSColor(red: 0.96, green: 0.66, blue: 0.34, alpha: 0.28).cgColor

        let groups: [(title: String, items: [(String, String)])]
        if activeChatProvider == .codex {
            let config = CodexConfig.shared.snapshot
            groups = [
                ("Codex", [
                    ("状态", "__codex_status__"),
                    ("配置", "__open_codex_config__"),
                    ("图片", "__attach_image__"),
                    ("新会话", "__codex_new_session__")
                ]),
                ("模型 \(shortModelName(config.model))", [
                    ("5.5", "__codex_model:gpt-5.5"),
                    ("5.4", "__codex_model:gpt-5.4"),
                    ("Mini", "__codex_model:gpt-5.4-mini"),
                    ("Spark", "__codex_model:gpt-5.3-codex-spark")
                ]),
                ("智能 \(config.reasoningEffort)", [
                    ("Low", "__codex_effort:low"),
                    ("Med", "__codex_effort:medium"),
                    ("High", "__codex_effort:high"),
                    ("XHigh", "__codex_effort:xhigh")
                ]),
                ("工作", [
                    ("检查", "请检查当前 Hermes 小橘子工作区的状态，列出最近改动、风险和下一步。"),
                    ("改代码", "请进入代码工作模式：先理解当前任务，再修改文件，最后运行必要验证。"),
                    ("总结", "请总结当前工作区最近完成了什么、还差什么、建议下一步做什么。"),
                    ("能力", "__capabilities__")
                ])
            ]
        } else {
            let runtimeModel = currentHermesRuntimeModel()
            let modelItems = hermesModelUtilityItems()
            groups = [
                ("Hermes", [
                    ("自检", "__self_check__"),
                    ("TUI", "__open_hermes_tui__"),
                    ("候选", "__memory_inbox__"),
                    ("记忆", "__open_memory__")
                ]),
                (hermesProviderTitle(runtimeModel.provider), modelItems),
                ("能力", [
                    ("图像", "__hermes_image_generate__"),
                    ("视频", "__hermes_video_generate__"),
                    ("语音", "__hermes_tts_prompt__"),
                    ("工具", "__hermes_tool_report__")
                ]),
                ("工作", [
                    ("备忘录", "__open_memo__"),
                    ("工作区", "__open_workspace__"),
                    ("主人计划", "__owner_plan__"),
                    ("同步计划", "__sync_plan__")
                ]),
                ("创作", [
                    ("带我学习", "请像小橘子老师一样带我学习：先问我想学什么，然后按 15 分钟一节课拆成目标、讲解、练习、回顾。"),
                    ("拆解任务", "请把我接下来要做的事拆成可执行步骤，并标出第一步、阻塞点和验收标准。"),
                    ("语音", "请使用 Hermes 的 TTS 能力，把下面这段话转成适合小橘子语气的语音："),
                    ("能力", "__capabilities__")
                ])
            ]
        }

        let outerGap: CGFloat = 8
        let groupGap: CGFloat = 8
        let groupW = (frame.width - outerGap * 2 - groupGap * CGFloat(groups.count - 1)) / CGFloat(groups.count)
        for (groupIndex, group) in groups.enumerated() {
            let x = outerGap + CGFloat(groupIndex) * (groupW + groupGap)
            let panel = makePill(
                frame: NSRect(x: x, y: outerGap, width: groupW, height: frame.height - outerGap * 2),
                fill: NSColor.white.withAlphaComponent(0.22),
                border: NSColor(red: 0.96, green: 0.70, blue: 0.42, alpha: 0.24),
                radius: 14
            )
            panel.addSubview(makeLabel(group.title, frame: NSRect(x: 10, y: panel.frame.height - 24, width: groupW - 20, height: 16), fontSize: 11, weight: .heavy, color: t.textPrimary))

            let buttonGap: CGFloat = 6
            let buttonW = (groupW - 24 - buttonGap) / 2
            let buttonH: CGFloat = 30
            for (idx, item) in group.items.enumerated() {
                let col = idx % 2
                let row = idx / 2
                let bx = 10 + CGFloat(col) * (buttonW + buttonGap)
                let by = panel.frame.height - 62 - CGFloat(row) * (buttonH + 7)
                let button = makeUtilityButton(title: item.0, payload: item.1, frame: NSRect(x: bx, y: by, width: buttonW, height: buttonH), theme: t)
                panel.addSubview(button)
            }
            strip.addSubview(panel)
        }
        return strip
    }

    private func shortModelName(_ model: String) -> String {
        model
            .replacingOccurrences(of: "gpt-", with: "")
            .replacingOccurrences(of: "codex-", with: "")
    }

    private func shortHermesModelName(_ model: String) -> String {
        let lower = model.lowercased()
        if lower == "grok-4.3" { return "Grok 4.3" }
        if lower == "grok-4" { return "Grok 4" }
        if lower.contains("grok-4-1") && lower.contains("reasoning") { return "Grok 4.1R" }
        if lower.contains("grok-4-1") { return "Grok 4.1" }
        if lower.contains("grok-4.20") && lower.contains("multi-agent") { return "4.20 MA" }
        if lower.contains("grok-4.20") && lower.contains("non-reasoning") { return "4.20 NR" }
        if lower.contains("grok-4.20") && lower.contains("reasoning") { return "4.20 R" }
        if lower.hasPrefix("grok-") {
            return model.replacingOccurrences(of: "grok-", with: "Grok ")
        }
        return model
    }

    private func hermesProviderTitle(_ provider: String) -> String {
        let clean = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased() == "xai" { return "XAI" }
        if clean.isEmpty { return "模型" }
        return clean.uppercased()
    }

    private func currentHermesRuntimeModel() -> HermesRuntimeModel {
        if let live = (agentSession as? HermesSession)?.currentEffectiveModel {
            return live
        }
        let threadID = selectedHermesThreadID ?? HermesSession.desktopSessionID
        if let stored = HermesSession.effectiveModel(for: threadID) {
            return stored
        }
        if let threadID,
           let thread = HermesConversationStore.shared.thread(id: threadID),
           !thread.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return HermesRuntimeModel(
                provider: inferredHermesProvider(model: thread.model, hint: thread.provider),
                model: thread.model
            )
        }
        if let stored = HermesSession.effectiveModel(for: nil) {
            return stored
        }
        let config = HermesConfig.shared.snapshot
        return HermesRuntimeModel(
            provider: inferredHermesProvider(model: config.model, hint: config.provider),
            model: config.model
        )
    }

    private func inferredHermesProvider(model: String, hint: String) -> String {
        let clean = hint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        if clean == "x.ai" || clean == "xai" { return "xai" }
        if clean.contains("deepseek") { return "deepseek" }
        if clean.contains("anthropic") || clean.contains("claude") { return "anthropic" }
        if clean.contains("openai") { return "openai" }
        if clean.contains("google") || clean.contains("gemini") { return "google" }
        if !clean.isEmpty { return clean }

        let lower = model.lowercased()
        if lower.contains("grok") { return "xai" }
        if lower.contains("deepseek") { return "deepseek" }
        if lower.contains("claude") { return "anthropic" }
        if lower.contains("gemini") { return "google" }
        if lower.hasPrefix("gpt") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") {
            return "openai"
        }
        return HermesConfig.shared.snapshot.provider
    }

    private func hermesModelUtilityItems() -> [(String, String)] {
        let runtimeModel = currentHermesRuntimeModel()
        let config = HermesConfig.shared.snapshot
        let options = HermesCatalog.shared.quickModelOptions(limit: 4)
        if options.isEmpty {
            return [(shortHermesModelName(runtimeModel.model), "__hermes_model:\(runtimeModel.provider)|\(runtimeModel.model)|\(config.baseURL)")]
        }
        var items = options.map { option in
            let label = clipped(shortHermesModelName(option.id), limit: 10)
            return (label, option.payload)
        }
        let hasCurrent = options.contains { option in
            option.provider == runtimeModel.provider && option.id == runtimeModel.model
        }
        if !hasCurrent {
            let current = (
                clipped(shortHermesModelName(runtimeModel.model), limit: 10),
                "__hermes_model:\(runtimeModel.provider)|\(runtimeModel.model)|\(config.baseURL)"
            )
            items.insert(current, at: 0)
        }
        return Array(items.prefix(4))
    }

    private func makeUtilityButton(title: String, payload: String, frame: NSRect, theme t: PopoverTheme) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = title
        button.identifier = NSUserInterfaceItemIdentifier(payload)
        button.target = self
        button.action = #selector(runQuickAction(_:))
        button.isBordered = false
        button.font = .systemFont(ofSize: frame.width < 56 ? 9.0 : 10.5, weight: .semibold)
        let selected = isSelectedUtilitySetting(payload)
        button.contentTintColor = selected ? .white : t.textPrimary
        button.wantsLayer = true
        button.layer?.backgroundColor = selected
            ? NSColor(red: 0.95, green: 0.48, blue: 0.18, alpha: 0.82).cgColor
            : NSColor.white.withAlphaComponent(0.44).cgColor
        button.layer?.cornerRadius = 10
        button.layer?.borderWidth = 1
        button.layer?.borderColor = selected
            ? NSColor(red: 0.95, green: 0.48, blue: 0.18, alpha: 0.86).cgColor
            : NSColor(red: 0.95, green: 0.69, blue: 0.40, alpha: 0.20).cgColor
        return button
    }

    private func makeHermesSidebar(frame: NSRect) -> NSView {
        let sidebar = NSView(frame: frame)
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.30).cgColor
        sidebar.layer?.cornerRadius = 18
        sidebar.layer?.borderWidth = 1
        sidebar.layer?.borderColor = NSColor(red: 0.96, green: 0.70, blue: 0.42, alpha: 0.32).cgColor
        return sidebar
    }

    private func refreshHermesSidebar() {
        guard let sidebar = hermesSidebarView else { return }
        sidebar.subviews.forEach { $0.removeFromSuperview() }
        hermesThreadButtons.removeAll()

        let t = resolvedTheme
        sidebar.addSubview(makeLabel(hermesCurrentModelLine(), frame: NSRect(x: 12, y: sidebar.frame.height - 30, width: sidebar.frame.width - 24, height: 16), fontSize: 10, weight: .bold, color: t.accentColor))
        sidebar.addSubview(makeLabel("Hermes 对话", frame: NSRect(x: 12, y: sidebar.frame.height - 52, width: 104, height: 16), fontSize: 12, weight: .heavy, color: t.textPrimary))

        let refresh = makeSmallSidebarButton(title: "刷新", frame: NSRect(x: sidebar.frame.width - 128, y: sidebar.frame.height - 55, width: 36, height: 22), identifier: "__hermes_refresh__")
        let new = makeSmallSidebarButton(title: "新建", frame: NSRect(x: sidebar.frame.width - 88, y: sidebar.frame.height - 55, width: 36, height: 22), identifier: "__hermes_new_session__")
        let delete = makeSmallSidebarButton(title: "删除", frame: NSRect(x: sidebar.frame.width - 48, y: sidebar.frame.height - 55, width: 36, height: 22), identifier: "__hermes_delete__")
        sidebar.addSubview(refresh)
        sidebar.addSubview(new)
        sidebar.addSubview(delete)

        let buttonH: CGFloat = 48
        let gap: CGFloat = 8
        let maxThreadCount = max(5, Int((sidebar.frame.height - 116) / (buttonH + gap)))
        let threads = HermesConversationStore.shared.recentThreads(limit: maxThreadCount)
        if threads.isEmpty {
            sidebar.addSubview(makeLabel("还没有 Hermes 对话", frame: NSRect(x: 14, y: sidebar.frame.height - 88, width: sidebar.frame.width - 28, height: 16), fontSize: 10, weight: .medium, color: t.textDim))
            return
        }

        for (idx, thread) in threads.enumerated() {
            let y = sidebar.frame.height - 106 - CGFloat(idx) * (buttonH + gap)
            guard y >= 12 else { break }
            let button = makeHermesThreadButton(thread: thread, frame: NSRect(x: 10, y: y, width: sidebar.frame.width - 20, height: buttonH))
            sidebar.addSubview(button)
            hermesThreadButtons.append(button)
        }
    }

    private func makeHermesThreadButton(thread: HermesThreadSummary, frame: NSRect) -> NSButton {
        let selected = thread.id == selectedHermesThreadID || thread.id == HermesSession.desktopSessionID
        let button = NSButton(frame: frame)
        button.title = ""
        button.identifier = NSUserInterfaceItemIdentifier(thread.id)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.layer?.backgroundColor = selected
            ? NSColor(red: 1.0, green: 0.84, blue: 0.58, alpha: 0.72).cgColor
            : NSColor.white.withAlphaComponent(0.34).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = selected
            ? NSColor(red: 0.95, green: 0.48, blue: 0.18, alpha: 0.70).cgColor
            : NSColor.white.withAlphaComponent(0.38).cgColor
        button.target = self
        button.action = #selector(selectHermesThreadFromSidebar(_:))

        let title = clipped(thread.title, limit: 22)
        let runtimeModel = currentHermesRuntimeModel()
        let model = selected
            ? shortHermesModelName(runtimeModel.model)
            : (thread.model.isEmpty ? shortHermesModelName(runtimeModel.model) : shortHermesModelName(thread.model))
        let threadProvider = inferredHermesProvider(model: thread.model.isEmpty ? runtimeModel.model : thread.model, hint: thread.provider)
        let provider = selected ? hermesProviderTitle(runtimeModel.provider) : hermesProviderTitle(threadProvider)
        let metaPrefix = selected ? "当前模型 \(provider) / \(model)" : "\(provider) / \(model)"
        let meta = "\(metaPrefix) · \(hermesThreadTime(thread.updatedAt))"
        button.addSubview(makeLabel(title, frame: NSRect(x: 10, y: 25, width: frame.width - 20, height: 14), fontSize: 10.5, weight: .heavy, color: NSColor(red: 0.30, green: 0.21, blue: 0.13, alpha: 1)))
        button.addSubview(makeLabel(meta, frame: NSRect(x: 10, y: 9, width: frame.width - 20, height: 13), fontSize: 8.5, weight: .medium, color: NSColor(red: 0.48, green: 0.35, blue: 0.22, alpha: 0.86)))
        return button
    }

    private func hermesCurrentModelLine() -> String {
        let runtimeModel = currentHermesRuntimeModel()
        return "当前模型：\(hermesProviderTitle(runtimeModel.provider)) / \(shortHermesModelName(runtimeModel.model))"
    }

    private func hermesThreadTime(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "未知" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private func makeCodexSidebar(frame: NSRect) -> NSView {
        let sidebar = NSView(frame: frame)
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.30).cgColor
        sidebar.layer?.cornerRadius = 18
        sidebar.layer?.borderWidth = 1
        sidebar.layer?.borderColor = NSColor(red: 0.65, green: 0.74, blue: 0.86, alpha: 0.30).cgColor
        return sidebar
    }

    private func refreshCodexSidebar() {
        guard let sidebar = codexSidebarView else { return }
        sidebar.subviews.forEach { $0.removeFromSuperview() }
        codexThreadButtons.removeAll()

        let t = resolvedTheme
        sidebar.addSubview(makeLabel(codexCurrentModelLine(), frame: NSRect(x: 12, y: sidebar.frame.height - 30, width: sidebar.frame.width - 24, height: 16), fontSize: 10, weight: .bold, color: NSColor(red: 0.30, green: 0.48, blue: 0.72, alpha: 1)))
        sidebar.addSubview(makeLabel("Codex 对话", frame: NSRect(x: 12, y: sidebar.frame.height - 52, width: 100, height: 16), fontSize: 12, weight: .heavy, color: t.textPrimary))

        let refresh = makeSmallSidebarButton(title: "刷新", frame: NSRect(x: sidebar.frame.width - 128, y: sidebar.frame.height - 55, width: 36, height: 22), identifier: "__codex_refresh__")
        let new = makeSmallSidebarButton(title: "新建", frame: NSRect(x: sidebar.frame.width - 88, y: sidebar.frame.height - 55, width: 36, height: 22), identifier: "__codex_new_session__")
        let archive = makeSmallSidebarButton(title: "归档", frame: NSRect(x: sidebar.frame.width - 48, y: sidebar.frame.height - 55, width: 36, height: 22), identifier: "__codex_archive__")
        sidebar.addSubview(refresh)
        sidebar.addSubview(new)
        sidebar.addSubview(archive)

        let buttonH: CGFloat = 48
        let gap: CGFloat = 8
        let maxThreadCount = max(5, Int((sidebar.frame.height - 116) / (buttonH + gap)))
        let threads = CodexConversationStore.shared.recentThreads(limit: maxThreadCount)
        if threads.isEmpty {
            sidebar.addSubview(makeLabel("还没有 Codex 对话", frame: NSRect(x: 14, y: sidebar.frame.height - 88, width: sidebar.frame.width - 28, height: 16), fontSize: 10, weight: .medium, color: t.textDim))
            return
        }

        for (idx, thread) in threads.enumerated() {
            let y = sidebar.frame.height - 106 - CGFloat(idx) * (buttonH + gap)
            guard y >= 12 else { break }
            let button = makeCodexThreadButton(thread: thread, frame: NSRect(x: 10, y: y, width: sidebar.frame.width - 20, height: buttonH))
            sidebar.addSubview(button)
            codexThreadButtons.append(button)
        }
    }

    private func makeSmallSidebarButton(title: String, frame: NSRect, identifier: String) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = title
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.isBordered = false
        button.font = .systemFont(ofSize: 9, weight: .bold)
        button.contentTintColor = NSColor(red: 0.26, green: 0.36, blue: 0.48, alpha: 1)
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.42).cgColor
        button.layer?.cornerRadius = 8
        button.target = self
        button.action = #selector(runQuickAction(_:))
        return button
    }

    private func makeCodexThreadButton(thread: CodexThreadSummary, frame: NSRect) -> NSButton {
        let selected = thread.id == selectedCodexThreadID
        let button = NSButton(frame: frame)
        button.title = ""
        button.identifier = NSUserInterfaceItemIdentifier(thread.id)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.layer?.backgroundColor = selected
            ? NSColor(red: 0.78, green: 0.88, blue: 1.0, alpha: 0.72).cgColor
            : NSColor.white.withAlphaComponent(0.34).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = selected
            ? NSColor(red: 0.38, green: 0.55, blue: 0.78, alpha: 0.70).cgColor
            : NSColor.white.withAlphaComponent(0.38).cgColor
        button.target = self
        button.action = #selector(selectCodexThreadFromSidebar(_:))

        let title = clipped(thread.title, limit: 22)
        let config = CodexConfig.shared.snapshot
        let model = selected ? shortModelName(config.model) : shortModelName(thread.model)
        let effort = selected ? config.reasoningEffort : (thread.reasoningEffort.isEmpty ? "auto" : thread.reasoningEffort)
        let metaPrefix = selected ? "当前模型 \(model) / \(effort)" : "\(model.isEmpty ? "model" : model) / \(effort)"
        let meta = "\(metaPrefix) · \(codexThreadTime(thread.updatedAtMS))"
        button.addSubview(makeLabel(title, frame: NSRect(x: 10, y: 25, width: frame.width - 20, height: 14), fontSize: 10.5, weight: .heavy, color: NSColor(red: 0.17, green: 0.25, blue: 0.34, alpha: 1)))
        button.addSubview(makeLabel(meta, frame: NSRect(x: 10, y: 9, width: frame.width - 20, height: 13), fontSize: 8.5, weight: .medium, color: NSColor(red: 0.33, green: 0.42, blue: 0.52, alpha: 0.86)))
        return button
    }

    private func codexCurrentModelLine() -> String {
        let config = CodexConfig.shared.snapshot
        return "当前模型：\(shortModelName(config.model)) / \(config.reasoningEffort)"
    }

    private func codexThreadTime(_ milliseconds: Int64) -> String {
        guard milliseconds > 0 else { return "未知" }
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func clipped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "..."
    }

    private func isSelectedUtilitySetting(_ payload: String) -> Bool {
        if activeChatProvider == .codex {
            let config = CodexConfig.shared.snapshot
            if payload.hasPrefix("__codex_model:") {
                return payload.replacingOccurrences(of: "__codex_model:", with: "") == config.model
            }
            if payload.hasPrefix("__codex_effort:") {
                return payload.replacingOccurrences(of: "__codex_effort:", with: "") == config.reasoningEffort
            }
        }

        if activeChatProvider == .hermes {
            let runtimeModel = currentHermesRuntimeModel()
            if payload.hasPrefix("__hermes_model:") {
                let parts = payload
                    .replacingOccurrences(of: "__hermes_model:", with: "")
                    .components(separatedBy: "|")
                return parts.count >= 2 && parts[0] == runtimeModel.provider && parts[1] == runtimeModel.model
            }
        }

        return false
    }

    private func addJournalBackground(to container: NSView) {
        guard let layer = container.layer else { return }

        let paper = CAGradientLayer()
        paper.frame = container.bounds
        paper.colors = [
            NSColor(red: 1.0, green: 0.975, blue: 0.925, alpha: 0.98).cgColor,
            NSColor(red: 1.0, green: 0.915, blue: 0.78, alpha: 0.92).cgColor,
            NSColor(red: 1.0, green: 0.965, blue: 0.88, alpha: 0.94).cgColor
        ]
        paper.locations = [0, 0.58, 1]
        paper.startPoint = CGPoint(x: 0, y: 1)
        paper.endPoint = CGPoint(x: 1, y: 0)
        layer.insertSublayer(paper, at: 0)

        let glow = CAGradientLayer()
        glow.frame = CGRect(x: container.bounds.width * 0.08, y: container.bounds.height * 0.10, width: container.bounds.width * 0.76, height: container.bounds.height * 0.82)
        glow.type = .radial
        glow.colors = [
            NSColor(red: 1.0, green: 0.72, blue: 0.38, alpha: 0.16).cgColor,
            NSColor(red: 1.0, green: 0.96, blue: 0.84, alpha: 0.03).cgColor,
            NSColor.clear.cgColor
        ]
        glow.locations = [0, 0.62, 1]
        layer.addSublayer(glow)
    }

    private func makeMOrangeWatermark(frame: NSRect) -> NSImageView? {
        let workspaceAssets = URL(fileURLWithPath: AppIdentity.workspacePath, isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("morange-desktop-assets", isDirectory: true)
        let supportAssets = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(AppIdentity.supportDirectoryName, isDirectory: true)
            .appendingPathComponent("MOrangeAnimations", isDirectory: true)
        var candidates: [String] = []
        if let supportPath = supportAssets?.appendingPathComponent("morange-chat-watermark.png").path {
            candidates.append(supportPath)
        }
        candidates.append(workspaceAssets.appendingPathComponent("chat-background/morange-chat-watermark.png").path)
        candidates.append(workspaceAssets.appendingPathComponent("source/morange-chibi-reference.jpg").path)
        candidates.append(workspaceAssets.appendingPathComponent("interaction-previews/morange-affection-source.jpg").path)
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let image = NSImage(contentsOfFile: path) else { return nil }
        let imageView = NSImageView(frame: frame)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.alphaValue = 0.12
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        imageView.layer?.cornerRadius = 0
        imageView.layer?.masksToBounds = false
        return imageView
    }

    private func makePill(frame: NSRect, fill: NSColor, border: NSColor, radius: CGFloat) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = fill.cgColor
        view.layer?.cornerRadius = radius
        view.layer?.borderWidth = 1
        view.layer?.borderColor = border.cgColor
        view.layer?.masksToBounds = true
        return view
    }

    private func makeLabel(_ text: String, frame: NSRect, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment = .left) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = .systemFont(ofSize: fontSize, weight: weight)
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        label.backgroundColor = .clear
        return label
    }

    private func makeCircleLabel(_ text: String, frame: NSRect, fill: NSColor, textColor: NSColor, fontSize: CGFloat) -> NSTextField {
        let label = makeLabel(text, frame: frame, fontSize: fontSize, weight: .bold, color: textColor, alignment: .center)
        label.wantsLayer = true
        label.layer?.backgroundColor = fill.cgColor
        label.layer?.cornerRadius = frame.height / 2
        label.layer?.masksToBounds = true
        return label
    }

    private func makeTopIconButton(_ title: String, frame: NSRect) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = title
        button.isBordered = false
        button.font = .systemFont(ofSize: title == "⚙" ? 17 : 22, weight: .medium)
        button.contentTintColor = NSColor(red: 0.48, green: 0.36, blue: 0.26, alpha: 1)
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        return button
    }

    private func makeSectionCard(frame: NSRect, title: String, icon: String, text: NSColor, border: NSColor, cardBg: NSColor) -> NSView {
        let card = makePill(frame: frame, fill: cardBg, border: border, radius: 12)
        card.addSubview(makeLabel("\(icon)  \(title)", frame: NSRect(x: 14, y: frame.height - 28, width: frame.width - 28, height: 18), fontSize: 13, weight: .heavy, color: text))
        return card
    }

    private func buildConnectionCard(in parent: NSView, frame: NSRect, text: NSColor, dim: NSColor, accent: NSColor, border: NSColor, cardBg: NSColor) {
        let card = makeSectionCard(frame: frame, title: "连接状态", icon: "🌿", text: text, border: border, cardBg: cardBg)
        let leftCat = makeCircleLabel("🍊", frame: NSRect(x: 52, y: 50, width: 36, height: 36), fill: NSColor(red: 1.0, green: 0.91, blue: 0.75, alpha: 1), textColor: accent, fontSize: 21)
        let laptop = makeLabel("⌨", frame: NSRect(x: 90, y: 50, width: 34, height: 30), fontSize: 23, weight: .regular, color: text, alignment: .center)
        let check1 = makeCircleLabel("✓", frame: NSRect(x: 124, y: 44, width: 22, height: 22), fill: NSColor(red: 0.48, green: 0.72, blue: 0.37, alpha: 1), textColor: .white, fontSize: 15)
        let line = makeLabel("− − − 〰︎ ♥ − − −", frame: NSRect(x: 150, y: 58, width: 116, height: 20), fontSize: 15, weight: .semibold, color: NSColor(red: 0.82, green: 0.67, blue: 0.38, alpha: 0.75), alignment: .center)
        let heart = makeCircleLabel("💗", frame: NSRect(x: frame.width - 82, y: 48, width: 46, height: 46), fill: NSColor(red: 1.0, green: 0.90, blue: 0.80, alpha: 0.82), textColor: accent, fontSize: 23)
        let check2 = makeCircleLabel("✓", frame: NSRect(x: frame.width - 44, y: 44, width: 22, height: 22), fill: NSColor(red: 0.48, green: 0.72, blue: 0.37, alpha: 1), textColor: .white, fontSize: 15)
        card.addSubview(leftCat)
        card.addSubview(laptop)
        card.addSubview(check1)
        card.addSubview(line)
        card.addSubview(heart)
        card.addSubview(check2)
        card.addSubview(makeLabel("代码助手已连接", frame: NSRect(x: 46, y: 22, width: 120, height: 16), fontSize: 12, weight: .bold, color: NSColor(red: 0.55, green: 0.42, blue: 0.18, alpha: 1), alignment: .center))
        card.addSubview(makeLabel("智能编程协助在线", frame: NSRect(x: 46, y: 7, width: 120, height: 14), fontSize: 10, weight: .regular, color: dim, alignment: .center))
        card.addSubview(makeLabel("小橘子待命", frame: NSRect(x: frame.width - 146, y: 22, width: 120, height: 16), fontSize: 12, weight: .bold, color: NSColor(red: 0.55, green: 0.42, blue: 0.18, alpha: 1), alignment: .center))
        card.addSubview(makeLabel("陪伴工作都在线", frame: NSRect(x: frame.width - 146, y: 7, width: 120, height: 14), fontSize: 10, weight: .regular, color: dim, alignment: .center))
        parent.addSubview(card)
    }

    private func buildQuickActionsCard(in parent: NSView, frame: NSRect, text: NSColor, dim: NSColor, accent: NSColor, border: NSColor, cardBg: NSColor) {
        let card = makeSectionCard(frame: frame, title: "快捷操作", icon: "🛠", text: text, border: border, cardBg: cardBg)
        let buttonW = (frame.width - 38) / 4
        let items: [(String, String, String, String)] = [
            ("</>", "代码问答", "解决编程问题", "帮我分析这个编程问题："),
            ("🐞", "调试助手", "找 Bug & 优化", "请帮我调试和优化这段代码："),
            ("📒", "解释代码", "逐行解释逻辑", "请帮我解释这段代码的逻辑："),
            ("💗", "情绪树洞", "说说心里话", "我想吐槽/聊聊今天的心情：")
        ]
        for (idx, item) in items.enumerated() {
            let x = 10 + CGFloat(idx) * (buttonW + 6)
            let button = makeQuickActionButton(icon: item.0, title: item.1, subtitle: item.2, prompt: item.3, frame: NSRect(x: x, y: 14, width: buttonW, height: 68), accent: accent, text: text, dim: dim, border: border)
            card.addSubview(button)
        }
        parent.addSubview(card)
    }

    private func makeQuickActionButton(icon: String, title: String, subtitle: String, prompt: String, frame: NSRect, accent: NSColor, text: NSColor, dim: NSColor, border: NSColor) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = ""
        button.isBordered = false
        button.identifier = NSUserInterfaceItemIdentifier(prompt)
        button.target = self
        button.action = #selector(runQuickAction(_:))
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.32).cgColor
        button.layer?.cornerRadius = min(frame.height / 2, 18)
        button.layer?.borderWidth = 1
        button.layer?.borderColor = border.withAlphaComponent(0.40).cgColor
        button.addSubview(makeLabel(icon, frame: NSRect(x: 0, y: 37, width: frame.width, height: 22), fontSize: 21, weight: .bold, color: accent, alignment: .center))
        button.addSubview(makeLabel(title, frame: NSRect(x: 4, y: 22, width: frame.width - 8, height: 15), fontSize: 11, weight: .bold, color: text, alignment: .center))
        button.addSubview(makeLabel(subtitle, frame: NSRect(x: 4, y: 8, width: frame.width - 8, height: 14), fontSize: 9, weight: .regular, color: dim, alignment: .center))
        return button
    }

    private func buildCompanionCard(in parent: NSView, frame: NSRect, text: NSColor, dim: NSColor, accent: NSColor, border: NSColor, cardBg: NSColor) {
        let card = makeSectionCard(frame: frame, title: "今日陪伴", icon: "🌱", text: text, border: border, cardBg: cardBg)
        let stat1 = makePill(frame: NSRect(x: 14, y: 48, width: 128, height: 28), fill: NSColor(red: 1.0, green: 0.96, blue: 0.84, alpha: 0.70), border: border.withAlphaComponent(0.45), radius: 9)
        stat1.addSubview(makeLabel("陪伴时长", frame: NSRect(x: 12, y: 7, width: 60, height: 14), fontSize: 10, weight: .semibold, color: dim))
        stat1.addSubview(makeLabel("2h 35m", frame: NSRect(x: 76, y: 7, width: 48, height: 14), fontSize: 11, weight: .bold, color: text, alignment: .right))
        let stat2 = makePill(frame: NSRect(x: 14, y: 14, width: 128, height: 28), fill: NSColor(red: 1.0, green: 0.96, blue: 0.84, alpha: 0.70), border: border.withAlphaComponent(0.45), radius: 9)
        stat2.addSubview(makeLabel("互动次数", frame: NSRect(x: 12, y: 7, width: 60, height: 14), fontSize: 10, weight: .semibold, color: dim))
        stat2.addSubview(makeLabel("24 次", frame: NSRect(x: 82, y: 7, width: 40, height: 14), fontSize: 11, weight: .bold, color: text, alignment: .right))
        let speech = makePill(frame: NSRect(x: 154, y: 20, width: frame.width - 222, height: 48), fill: NSColor(red: 1.0, green: 0.925, blue: 0.84, alpha: 0.70), border: border.withAlphaComponent(0.42), radius: 10)
        speech.addSubview(makeLabel("你今天已经很棒啦，\n记得喝水休息哦～", frame: NSRect(x: 12, y: 9, width: speech.frame.width - 24, height: 32), fontSize: 12, weight: .medium, color: text))
        card.addSubview(stat1)
        card.addSubview(stat2)
        card.addSubview(speech)
        card.addSubview(makeCircleLabel("🍊", frame: NSRect(x: frame.width - 56, y: 16, width: 42, height: 42), fill: NSColor(red: 1.0, green: 0.91, blue: 0.75, alpha: 1), textColor: accent, fontSize: 25))
        parent.addSubview(card)
    }

    private func buildTopicsCard(in parent: NSView, frame: NSRect, text: NSColor, dim: NSColor, accent: NSColor, border: NSColor, cardBg: NSColor) {
        let card = makeSectionCard(frame: frame, title: "最近话题", icon: "🗂", text: text, border: border, cardBg: cardBg)
        card.addSubview(makeLabel("🗑  清空记录", frame: NSRect(x: frame.width - 86, y: frame.height - 28, width: 72, height: 16), fontSize: 10, weight: .medium, color: dim, alignment: .right))
        let topics = ["# 动画与放松", "# Deepseek", "# 今天的心情", "•••"]
        var x: CGFloat = 14
        for topic in topics {
            let w: CGFloat = topic == "•••" ? 48 : (topic.count > 10 ? 98 : 86)
            let chip = makePill(frame: NSRect(x: x, y: 18, width: w, height: 30), fill: NSColor(red: 1.0, green: 0.94, blue: 0.86, alpha: 0.82), border: border.withAlphaComponent(0.52), radius: 15)
            chip.addSubview(makeLabel(topic, frame: NSRect(x: 0, y: 7, width: w, height: 16), fontSize: 11, weight: .medium, color: text, alignment: .center))
            card.addSubview(chip)
            x += w + 8
        }
        parent.addSubview(card)
    }

    @objc private func closePopoverFromButton() {
        closePopover()
    }

    @objc private func runQuickAction(_ sender: NSButton) {
        guard let prompt = sender.identifier?.rawValue else { return }
        if prompt == "__capabilities__" {
            showAgentCapabilities()
            return
        }
        if prompt == "__attach_image__" {
            terminalView?.requestImageAttachmentPicker()
            applyPetState(.listening, phrase: "把图片递给我吧", completion: true, autoReturnAfter: 3.0)
            return
        }
        if prompt == "__attach_file__" {
            terminalView?.requestFileAttachmentPicker()
            applyPetState(.listening, phrase: "文件路径我来接", completion: true, autoReturnAfter: 3.0)
            return
        }
        if prompt == "__hermes_image_generate__" {
            activateChatProvider(.hermes, announce: false)
            terminalView?.insertDraft(hermesImageGeneratePrompt())
            terminalView?.appendToolUse(toolName: "Hermes 图像创作意图", summary: hermesMediaStatusLine(kind: "image"))
            applyPetState(.thinking, phrase: "画什么，主人说", completion: true, autoReturnAfter: 4.0)
            return
        }
        if prompt == "__hermes_video_generate__" {
            activateChatProvider(.hermes, announce: false)
            terminalView?.insertDraft(hermesVideoGeneratePrompt())
            terminalView?.appendToolUse(toolName: "Hermes 视频创作意图", summary: hermesMediaStatusLine(kind: "video"))
            applyPetState(.working, phrase: "镜头我准备好啦", completion: true, autoReturnAfter: 4.0)
            return
        }
        if prompt == "__hermes_tts_prompt__" {
            activateChatProvider(.hermes, announce: false)
            terminalView?.insertDraft(hermesTTSPrompt())
            terminalView?.appendToolUse(toolName: "Hermes 语音创作意图", summary: hermesMediaStatusLine(kind: "tts"))
            applyPetState(.listening, phrase: "要我念哪段？", completion: true, autoReturnAfter: 4.0)
            return
        }
        if prompt == "__hermes_tool_report__" {
            terminalView?.appendToolResult(summary: hermesOfficialToolReport(), isError: false)
            applyPetState(.thinking, phrase: "工具表翻出来啦", completion: true, autoReturnAfter: 4.0)
            return
        }
        if prompt == "__self_check__" {
            let report = HermesBridge.shared.selfCheckReport(sessionID: HermesSession.desktopSessionID)
            terminalView?.appendToolResult(summary: "Hermes 自检完成\n\(report)", isError: false)
            applyPetState(.done, phrase: "自检完成", completion: true, autoReturnAfter: 4.0)
            return
        }
        if prompt == "__open_hermes_tui__" {
            openHermesTUI()
            return
        }
        if prompt == "__open_memory__" {
            NSWorkspace.shared.open(HermesBridge.shared.hermesMemoryDirectoryURL)
            HermesBridge.shared.recordPlanRequest("打开 Hermes 官方记忆", detail: "主人从聊天面板打开 ~/.hermes/memories。")
            terminalView?.appendToolResult(summary: "已打开 Hermes 官方记忆", isError: false)
            applyPetState(.thinking, phrase: "翻记忆本", completion: true, autoReturnAfter: 3.0)
            return
        }
        if prompt == "__memory_inbox__" {
            showMemoryInbox()
            return
        }
        if prompt == "__open_workspace__" {
            NSWorkspace.shared.open(HermesBridge.shared.workspaceURL)
            HermesBridge.shared.recordPlanRequest("打开 Hermes 工作区", detail: "主人从聊天面板打开主工作区。")
            terminalView?.appendToolResult(summary: "已打开 Hermes 工作区", isError: false)
            applyPetState(.working, phrase: "打开工作区", completion: true, autoReturnAfter: 3.0)
            return
        }
        if prompt == "__hermes_refresh__" {
            selectedHermesThreadID = (agentSession as? HermesSession)?.currentSessionID ?? HermesSession.desktopSessionID ?? selectedHermesThreadID
            refreshHermesSidebar()
            terminalView?.appendToolResult(summary: "Hermes 对话列表已刷新", isError: false)
            applyPetState(.done, phrase: "Hermes 列表刷新", completion: true, autoReturnAfter: 2.5)
            return
        }
        if prompt == "__hermes_new_session__" {
            agentSession?.terminate()
            agentSession = nil
            HermesSession.setDesktopSessionID(nil)
            selectedHermesThreadID = nil
            selectedHermesThreadTitle = nil
            if activeChatProvider == .hermes {
                terminalView?.clearTranscript()
            }
            refreshHermesSidebar()
            terminalView?.appendToolResult(summary: "Hermes 新会话已准备好", isError: false)
            applyPetState(.done, phrase: "Hermes 换新会话", completion: true, autoReturnAfter: 3.0)
            return
        }
        if prompt == "__hermes_delete__" {
            deleteSelectedHermesThread()
            return
        }
        if prompt == "__open_hermes_model__" {
            openHermesModelGuide()
            return
        }
        if prompt.hasPrefix("__hermes_model:") {
            updateHermesConfig(fromPayload: prompt)
            return
        }
        if prompt == "__codex_status__" {
            terminalView?.appendToolResult(summary: codexStatusReport(), isError: false)
            applyPetState(.done, phrase: "Codex 状态读到啦", completion: true, autoReturnAfter: 3.0)
            return
        }
        if prompt == "__codex_refresh__" {
            selectedCodexThreadID = (codexSession as? CodexSession)?.currentThreadID ?? selectedCodexThreadID
            refreshCodexSidebar()
            terminalView?.appendToolResult(summary: "Codex 对话列表已刷新", isError: false)
            applyPetState(.done, phrase: "列表刷新啦", completion: true, autoReturnAfter: 2.5)
            return
        }
        if prompt == "__codex_archive__" {
            archiveSelectedCodexThread()
            return
        }
        if prompt == "__open_codex_config__" {
            NSWorkspace.shared.open(CodexConfig.shared.configURL)
            terminalView?.appendToolResult(summary: "已打开 Codex 本体配置：\(CodexConfig.shared.configURL.path)", isError: false)
            applyPetState(.working, phrase: "打开 Codex 配置", completion: true, autoReturnAfter: 3.0)
            return
        }
        if prompt == "__codex_new_session__" {
            codexSession?.terminate()
            codexSession = nil
            selectedCodexThreadID = nil
            selectedCodexThreadTitle = nil
            if activeChatProvider == .codex {
                terminalView?.clearTranscript()
            }
            refreshCodexSidebar()
            terminalView?.appendToolResult(summary: "Codex 新会话已准备好", isError: false)
            applyPetState(.done, phrase: "Codex 换新会话", completion: true, autoReturnAfter: 3.0)
            return
        }
        if prompt.hasPrefix("__codex_model:") {
            updateCodexConfig(model: prompt.replacingOccurrences(of: "__codex_model:", with: ""), reasoningEffort: nil)
            return
        }
        if prompt.hasPrefix("__codex_effort:") {
            updateCodexConfig(model: nil, reasoningEffort: prompt.replacingOccurrences(of: "__codex_effort:", with: ""))
            return
        }
        if prompt == "__open_memo__" {
            openTodayMemo()
            return
        }
        if prompt == "__morange_plan__" {
            activateChatProvider(.hermes, announce: false)
            HermesBridge.shared.recordPlanRequest("请求小橘子计划", detail: "主人要求整理桌宠/Hermes 小橘子自身计划。")
            terminalView?.submitProgrammaticMessage(morangePlanPrompt())
            return
        }
        if prompt == "__owner_plan__" {
            activateChatProvider(.hermes, announce: false)
            HermesBridge.shared.recordPlanRequest("请求主人计划", detail: "小橘子读取当天备忘录并整理主人今日计划。")
            terminalView?.submitProgrammaticMessage(ownerPlanPrompt())
            return
        }
        if prompt == "__sync_plan__" {
            activateChatProvider(.hermes, announce: false)
            HermesBridge.shared.recordPlanRequest("请求同步计划", detail: "小橘子把主人计划和小橘子计划合并为当天联合计划。")
            terminalView?.submitProgrammaticMessage(syncPlanPrompt())
            return
        }
        if prompt == "__copy_chat__" {
            terminalView?.copyTranscriptToPasteboard()
            terminalView?.appendToolResult(summary: "对话已复制", isError: false)
            applyPetState(.done, phrase: "复制好啦", completion: true, autoReturnAfter: 3.0)
            return
        }
        if prompt == "__clear_chat__" {
            terminalView?.clearTranscript()
            terminalView?.appendToolResult(summary: "对话已清空", isError: false)
            applyPetState(.sleepy, phrase: "擦干净啦", completion: true, autoReturnAfter: 3.0)
            return
        }
        if prompt.hasPrefix("/记住") {
            terminalView?.insertDraft(prompt)
            applyPetState(.listening, phrase: "主人要我记什么？", completion: true, autoReturnAfter: 3.0)
            return
        }
        if prompt.hasPrefix("/") {
            activateChatProvider(.hermes, announce: false)
        } else {
            ensureSession()
        }
        terminalView?.submitProgrammaticMessage(prompt)
    }

    private func inputSuggestions(for text: String) -> [InputSuggestion] {
        switch activeChatProvider {
        case .hermes:
            return HermesCatalog.shared.suggestions(for: text)
        case .codex:
            return codexInputSuggestions(for: text)
        default:
            return []
        }
    }

    private func showAgentCapabilities() {
        let summary: String
        if activeChatProvider == .codex {
            summary = [
                "Codex 多模态入口",
                "图片：点输入框左侧图片按钮，桌宠会用 `codex exec --image` 传给 Codex。",
                "文件：点文件按钮选择本地文件，桌宠会把路径写进请求，Codex 可按路径读取。",
                "本体同步：模型、智能程度、会话列表和归档仍同步本机 Codex。",
                "扩展：Codex 本体还支持 MCP、插件、web search、子代理；需要完整 TUI 时仍可打开 Codex 本体。"
            ].joined(separator: "\n")
        } else {
            let mediaLines = HermesCatalog.shared.mediaCapabilityLines()
            summary = [
                "Hermes 多模态入口",
                "图片输入：点输入框左侧图片按钮，桌宠会用官方 `image.attach` / `hermes chat --image` 传给 Hermes。",
                "文件：点文件按钮选择本地文件，桌宠会把路径交给 Hermes 的 file/terminal 工具读取。",
                "联网/网页：Hermes CLI 已启用 web/browser 工具集，可以直接让她搜索、打开网页、提取内容。",
                "电脑操作：Hermes CLI 已启用 computer_use，需要确认时会弹出小橘子的确认框。",
                "可用媒体/语音能力会交给 Hermes 自行调度："
            ].joined(separator: "\n")
            + "\n"
            + mediaLines.map { "- \($0)" }.joined(separator: "\n")
        }
        terminalView?.appendToolResult(summary: summary, isError: false)
        applyPetState(.thinking, phrase: "能力表翻出来啦", completion: true, autoReturnAfter: 4.0)
    }

    private func codexInputSuggestions(for text: String) -> [InputSuggestion] {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("/") else { return [] }
        let commands = [
            InputSuggestion(title: "/status", subtitle: "Codex 状态和本体配置", replacement: "请检查 Codex 本体状态、当前模型、智能程度和工作区。"),
            InputSuggestion(title: "/workspace", subtitle: "打开 Hermes 小橘子工作区", replacement: "请检查当前 Hermes 小橘子工作区并说明最近改动。"),
            InputSuggestion(title: "/image", subtitle: "附加图片并交给 Codex 视觉输入", replacement: "请分析我附加的图片。"),
            InputSuggestion(title: "/file", subtitle: "附加本地文件路径并让 Codex 读取", replacement: "请读取我附加的文件路径并总结重点。"),
            InputSuggestion(title: "/summary", subtitle: "总结当前工作", replacement: "请总结当前工作区最近完成了什么、还差什么、建议下一步做什么。"),
            InputSuggestion(title: "/web", subtitle: "需要 Codex 本体联网时的提示", replacement: "请判断这件事是否需要联网搜索；如果当前桌宠 exec 通道不支持，请告诉我切到 Codex 本体的方式。")
        ]
        let needle = raw.dropFirst().lowercased()
        return commands.filter { suggestion in
            suggestion.title.dropFirst().lowercased().hasPrefix(needle)
        }
    }

    private func hermesImageGeneratePrompt() -> String {
        "我想让小橘子帮我做一张图片。需求："
    }

    private func hermesVideoGeneratePrompt() -> String {
        "我想让小橘子帮我做一段视频。需求："
    }

    private func hermesTTSPrompt() -> String {
        "我想让小橘子帮我把下面这段文字做成语音文件："
    }

    private func hermesMediaStatusLine(kind: String) -> String {
        let config = HermesConfig.shared.snapshot
        switch kind {
        case "image":
            return "已把图像创作需求交给 Hermes；Hermes 会按上下文自行决定是否调用 image_generate。当前 image_gen provider=\(config.imageGenProvider.isEmpty ? "未配置" : config.imageGenProvider)，model=\(config.imageGenModel.isEmpty ? "默认" : config.imageGenModel)"
        case "video":
            return "已把视频创作需求交给 Hermes；Hermes 会按上下文自行决定是否调用 video_generate。当前 video_gen provider=\(config.videoGenProvider.isEmpty ? "未配置" : config.videoGenProvider)，model=\(config.videoGenModel.isEmpty ? "默认" : config.videoGenModel)"
        case "tts":
            return "已把语音创作需求交给 Hermes；Hermes 会按上下文自行决定是否调用 text_to_speech。当前 tts provider=\(config.ttsProvider.isEmpty ? "未配置" : config.ttsProvider)，voice=\(config.ttsVoice.isEmpty ? "默认" : config.ttsVoice)"
        default:
            return "Hermes 官方工具"
        }
    }

    private func hermesOfficialToolReport() -> String {
        let tools = HermesCatalog.shared.registeredTools()
        let grouped = Dictionary(grouping: tools, by: \.toolset)
        let mediaLines = HermesCatalog.shared.mediaCapabilityLines()
        var lines: [String] = [
            "Hermes 官方工具对齐",
            "来源：~/.hermes/hermes-agent/tools/* 的 registry.register，不是小橘子手写假按钮。",
            "",
            "媒体/语音："
        ]
        lines.append(contentsOf: mediaLines.map { "- \($0)" })
        lines.append("")
        lines.append("工具集：\(grouped.keys.sorted().count) 组，\(tools.count) 个工具")
        for key in grouped.keys.sorted() {
            let names = (grouped[key] ?? []).map(\.name).sorted()
            let preview = names.prefix(12).joined(separator: ", ")
            let suffix = names.count > 12 ? " ..." : ""
            lines.append("- \(key): \(preview)\(suffix)")
        }
        lines.append("")
        lines.append("说明：聊天区按钮只表达主人意图，不直接强制调用具体工具；Hermes 会根据上下文、模型和工具策略自动决定是否使用这些工具，并通过工具事件回显。")
        return lines.joined(separator: "\n")
    }

    @objc private func selectHermesThreadFromSidebar(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let thread = HermesConversationStore.shared.thread(id: id) else { return }
        loadHermesThread(thread, announce: true)
    }

    private func deleteSelectedHermesThread() {
        guard let id = selectedHermesThreadID ?? HermesSession.desktopSessionID else {
            terminalView?.appendToolResult(summary: "请先选中一个 Hermes 对话，再点删除。", isError: true)
            applyPetState(.confused, phrase: "先选一个对话", completion: true, autoReturnAfter: 3.5)
            return
        }

        let title = selectedHermesThreadTitle ?? HermesConversationStore.shared.thread(id: id)?.title ?? "当前对话"
        guard HermesConversationStore.shared.deleteThread(id: id) else {
            terminalView?.appendToolResult(summary: "删除失败：没有找到这个 Hermes 对话。", isError: true)
            applyPetState(.confused, phrase: "删除没成功", completion: true, autoReturnAfter: 4.0)
            return
        }

        if HermesSession.desktopSessionID == id {
            agentSession?.terminate()
            agentSession = nil
            HermesSession.setDesktopSessionID(nil)
        }
        selectedHermesThreadID = nil
        selectedHermesThreadTitle = nil
        terminalView?.clearTranscript()
        refreshHermesSidebar()
        terminalView?.appendToolResult(summary: "已删除 Hermes 对话：\(title)", isError: false)
        applyPetState(.done, phrase: "Hermes 对话收掉啦", completion: true, autoReturnAfter: 3.0)
    }

    private func updateHermesConfig(fromPayload payload: String) {
        let parts = payload
            .replacingOccurrences(of: "__hermes_model:", with: "")
            .components(separatedBy: "|")
        guard parts.count >= 2 else { return }

        do {
            try HermesConfig.shared.update(
                provider: parts[0],
                model: parts[1],
                baseURL: parts.count >= 3 ? parts[2] : nil
            )
            let runtimeModel = HermesRuntimeModel(provider: parts[0], model: parts[1])
            HermesSession.setEffectiveModel(runtimeModel, for: selectedHermesThreadID ?? HermesSession.desktopSessionID)
            HermesSession.setEffectiveModel(runtimeModel, for: nil)
            agentSession?.terminate()
            agentSession = nil
            rebuildUtilityStripIfNeeded(force: true)
            updateChatUI()
            let config = HermesConfig.shared.snapshot
            terminalView?.appendToolResult(summary: "Hermes 模型配置已同步：\(config.provider) / \(config.model)。下一条 Hermes 消息会按这个本体配置开启或续聊。", isError: false)
            applyPetState(.done, phrase: "Hermes 模型同步", completion: true, autoReturnAfter: 3.0)
        } catch {
            terminalView?.appendToolResult(summary: "Hermes 配置写入失败：\(error.localizedDescription)", isError: true)
            applyPetState(.confused, phrase: "模型没写进去", completion: true, autoReturnAfter: 4.0)
        }
    }

    @objc private func selectCodexThreadFromSidebar(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let thread = CodexConversationStore.shared.thread(id: id) else { return }
        loadCodexThread(thread, announce: true)
    }

    private func archiveSelectedCodexThread() {
        guard let id = selectedCodexThreadID ?? (codexSession as? CodexSession)?.currentThreadID else {
            terminalView?.appendToolResult(summary: "请先选中一个 Codex 对话，再点归档。", isError: true)
            applyPetState(.confused, phrase: "先选一个对话", completion: true, autoReturnAfter: 3.5)
            return
        }

        let title = selectedCodexThreadTitle ?? CodexConversationStore.shared.thread(id: id)?.title ?? "当前对话"
        guard CodexConversationStore.shared.archiveThread(id: id) else {
            terminalView?.appendToolResult(summary: "归档失败：没有找到这个 Codex 对话。", isError: true)
            applyPetState(.confused, phrase: "归档没成功", completion: true, autoReturnAfter: 4.0)
            return
        }

        if (codexSession as? CodexSession)?.currentThreadID == id {
            codexSession?.terminate()
            codexSession = nil
        }
        selectedCodexThreadID = nil
        selectedCodexThreadTitle = nil
        terminalView?.clearTranscript()
        refreshCodexSidebar()
        terminalView?.appendToolResult(summary: "已归档 Codex 对话：\(title)", isError: false)
        applyPetState(.done, phrase: "对话收好啦", completion: true, autoReturnAfter: 3.0)
    }

    private func codexStatusReport() -> String {
        let config = CodexConfig.shared.snapshot
        let binary = ShellEnvironment.findBinarySync(name: "codex", fallbackPaths: [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".npm-global/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]) ?? "未找到"
        return """
        Codex 本体状态
        CLI：\(binary)
        配置：\(config.configURL.path)
        模型：\(config.model)
        智能程度：\(config.reasoningEffort)
        工作区：\(HermesBridge.shared.workspaceURL.path)
        同步方式：桌宠直接读写 ~/.codex/config.toml；本机 Codex 改配置后，重新打开/切回 Codex 区会读取新值。
        """
    }

    private func updateCodexConfig(model: String?, reasoningEffort: String?) {
        do {
            try CodexConfig.shared.update(model: model, reasoningEffort: reasoningEffort)
            codexSession?.terminate()
            codexSession = nil
            rebuildUtilityStripIfNeeded(force: true)
            updateChatUI()
            let config = CodexConfig.shared.snapshot
            terminalView?.appendToolResult(summary: "Codex 配置已同步：\(config.model) / \(config.reasoningEffort)。下一条消息会按本体配置开启新会话。", isError: false)
            applyPetState(.done, phrase: "Codex 配置同步", completion: true, autoReturnAfter: 3.0)
        } catch {
            terminalView?.appendToolResult(summary: "Codex 配置写入失败：\(error.localizedDescription)", isError: true)
            applyPetState(.confused, phrase: "配置没写进去", completion: true, autoReturnAfter: 4.0)
        }
    }

    @discardableResult
    private func ensureTodayMemo() throws -> URL {
        try HermesBridge.shared.ensureTodayMemo()
    }

    private func readTodayMemo() -> (url: URL, text: String) {
        HermesBridge.shared.readTodayMemo()
    }

    private func morangePlanPrompt() -> String {
        """
        请为“小橘子桌宠”制定今天的小橘子计划。

        要求：
        - 只关注小橘子自身：UI、交互、记忆、素材、稳定性、Hermes 连接。
        - 分成「今天必须」「可以继续」「以后再说」三组。
        - 每项写清楚验收标准。
        - 最后给出你建议现在先做的一步。
        """
    }

    private func ownerPlanPrompt() -> String {
        let memo = readTodayMemo()
        return """
        请读取并整理“主人的今日计划”。下面是主人的备忘录内容：

        文件路径：\(memo.url.path)

        ```markdown
        \(memo.text)
        ```

        请输出：
        1. 主人今天真正要做的事。
        2. 优先级和建议顺序。
        3. 哪些可以交给小橘子协助。
        4. 如果备忘录里计划不清楚，请给出需要主人补充的问题。

        小橘子被允许根据主人确认后的内容更新这个备忘录文件。
        """
    }

    private func syncPlanPrompt() -> String {
        let memo = readTodayMemo()
        return """
        请把“小橘子的计划”和“主人的计划”同步成一份今天可执行的联合计划。

        主人备忘录路径：\(memo.url.path)

        当前备忘录内容：

        ```markdown
        \(memo.text)
        ```

        要求：
        - 分成「主人做」「小橘子做」「一起确认」三组。
        - 如果需要修改备忘录，请先给出修改后的 markdown 草稿，并说明会改哪些部分。
        - 小橘子有权限在主人确认后更新这份备忘录。
        """
    }

    private func openTodayMemo() {
        do {
            let memoURL = try ensureTodayMemo()
            NSWorkspace.shared.open(memoURL)
            HermesBridge.shared.recordPlanRequest("打开今日备忘录", detail: memoURL.path)
            terminalView?.appendToolResult(summary: "已打开今日备忘录", isError: false)
            applyPetState(.done, phrase: "备忘录打开啦", completion: true, autoReturnAfter: 3.0)
        } catch {
            terminalView?.appendToolResult(summary: "备忘录打开失败：\(error.localizedDescription)", isError: true)
            applyPetState(.confused, phrase: "备忘录卡住了", completion: true, autoReturnAfter: 4.0)
        }
    }

    private func openHermesTUI() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binary = ShellEnvironment.findBinarySync(name: "hermes", fallbackPaths: [
            home.appendingPathComponent(".local/bin/hermes").path,
            "/opt/homebrew/bin/hermes",
            "/usr/local/bin/hermes"
        ]) ?? "hermes"

        var command = "cd \(shellQuote(HermesBridge.shared.workspaceURL.path)); \(shellQuote(binary)) chat --tui --source morange_desktop"
        if let sessionID = HermesSession.desktopSessionID,
           !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            command += " --resume \(shellQuote(sessionID))"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"\(appleScriptString(command))\""
        ]

        do {
            try process.run()
            HermesBridge.shared.recordPlanRequest("打开 Hermes 原生 TUI", detail: command)
            terminalView?.appendToolResult(summary: "已打开 Hermes 原生 TUI。它会尽量接上当前桌宠 Hermes session。", isError: false)
            applyPetState(.working, phrase: "原生 TUI 打开", completion: true, autoReturnAfter: 3.0)
        } catch {
            terminalView?.appendToolResult(summary: "Hermes TUI 打开失败：\(error.localizedDescription)", isError: true)
            applyPetState(.confused, phrase: "TUI 没打开", completion: true, autoReturnAfter: 4.0)
        }
    }

    private func openHermesModelGuide() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binary = ShellEnvironment.findBinarySync(name: "hermes", fallbackPaths: [
            home.appendingPathComponent(".local/bin/hermes").path,
            "/opt/homebrew/bin/hermes",
            "/usr/local/bin/hermes"
        ]) ?? "hermes"

        let command = "cd \(shellQuote(HermesBridge.shared.workspaceURL.path)); \(shellQuote(binary)) model"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"\(appleScriptString(command))\""
        ]

        do {
            try process.run()
            HermesBridge.shared.recordPlanRequest("打开 Hermes 模型向导", detail: command)
            terminalView?.appendToolResult(summary: "已打开 Hermes 模型向导。顶部的 Grok 按钮也会直接写入 ~/.hermes/config.yaml。", isError: false)
            applyPetState(.working, phrase: "模型向导打开", completion: true, autoReturnAfter: 3.0)
        } catch {
            terminalView?.appendToolResult(summary: "Hermes 模型向导打开失败：\(error.localizedDescription)", isError: true)
            applyPetState(.confused, phrase: "模型向导没开", completion: true, autoReturnAfter: 4.0)
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func activeHermesSessionForVoice() -> HermesSession? {
        guard activeChatProvider == .hermes else {
            terminalView?.appendToolResult(summary: "语音模式先接在 Hermes 入口。切回 Hermes 后小橘子就能听主人说话。", isError: true)
            applyPetState(.confused, phrase: "先切回 Hermes", completion: true, autoReturnAfter: 4.0)
            return nil
        }
        ensureSession()
        guard let hermesSession = currentSession as? HermesSession else {
            terminalView?.appendToolResult(summary: "Hermes 会话还没准备好。", isError: true)
            applyPetState(.confused, phrase: "Hermes 还没接上", completion: true, autoReturnAfter: 4.0)
            return nil
        }
        return hermesSession
    }

    private func toggleHermesVoiceRecording() {
        guard let hermesSession = activeHermesSessionForVoice() else { return }
        terminalView?.appendToolUse(toolName: "Hermes 语音输入", summary: "调用官方 voice.record")
        applyPetState(.listening, phrase: "我在听主人说", completion: false, autoReturnAfter: 10.0)
        hermesSession.toggleVoiceRecording()
    }

    private func toggleHermesVoiceTTS() {
        guard let hermesSession = activeHermesSessionForVoice() else { return }
        terminalView?.appendToolUse(toolName: "Hermes 回复朗读", summary: "调用官方 voice.toggle tts")
        applyPetState(.listening, phrase: "要我读出来吗", completion: false, autoReturnAfter: 4.0)
        hermesSession.toggleVoiceTTS()
    }

    private func wireSession(_ session: any AgentSession, provider: AgentProvider) {
        let providerName = provider.displayName
        session.onText = { [weak self] text in
            guard let self = self else { return }
            self.currentStreamingText += text
            guard self.activeChatProvider == provider else { return }
            self.terminalView?.appendStreamingText(text)
        }

        session.onTurnComplete = { [weak self] in
            guard let self = self else { return }
            if self.activeChatProvider == provider {
                self.terminalView?.endStreaming()
            }
            if provider == .codex {
                if let threadID = (session as? CodexSession)?.currentThreadID {
                    let thread = CodexConversationStore.shared.syncForDesktop(threadID: threadID)
                    self.selectedCodexThreadID = threadID
                    self.selectedCodexThreadTitle = thread?.title ?? CodexConversationStore.shared.thread(id: threadID)?.title ?? self.selectedCodexThreadTitle
                }
                self.refreshCodexSidebar()
                self.chatTitleLabel?.stringValue = self.chatTitleText()
            } else if provider == .hermes {
                if let sessionID = (session as? HermesSession)?.currentSessionID ?? HermesSession.desktopSessionID {
                    let thread = HermesConversationStore.shared.thread(id: sessionID)
                    self.selectedHermesThreadID = sessionID
                    self.selectedHermesThreadTitle = thread?.title ?? self.selectedHermesThreadTitle
                }
                self.refreshHermesSidebar()
                self.rebuildUtilityStripIfNeeded()
                self.chatTitleLabel?.stringValue = self.chatTitleText()
            }
            self.playCompletionSound()
            let phrase = provider == .codex ? "Codex 做完啦" : (Self.completionPhrases.randomElement() ?? "给主人整理好了")
            self.applyPetState(.done, phrase: phrase, completion: true, autoReturnAfter: 5.0)
        }

        session.onError = { [weak self] text in
            guard let self = self else { return }
            if self.activeChatProvider == provider {
                self.terminalView?.appendError(text)
            }
            self.applyPetState(.confused, phrase: "这里卡住了", completion: true, autoReturnAfter: 6.0)
        }

        session.onToolUse = { [weak self] toolName, input in
            guard let self = self else { return }
            let summary = self.formatToolInput(input)
            if self.activeChatProvider == provider {
                self.terminalView?.appendToolUse(toolName: toolName, summary: summary)
            }
            if toolName.hasPrefix("Hermes 语音") || toolName.hasPrefix("Hermes 回复朗读") {
                return
            }
            let presentation = self.presentationForHermesMirror(toolName: toolName, input: input, provider: provider)
            self.applyPetState(presentation.state, phrase: presentation.phrase, completion: false, autoReturnAfter: presentation.hold)
        }

        session.onToolResult = { [weak self] summary, isError in
            guard let self = self else { return }
            if self.activeChatProvider == provider {
                self.terminalView?.appendToolResult(summary: summary, isError: isError)
            }
            self.applyPetState(isError ? .confused : .working, phrase: isError ? "这里不太对" : "收到结果啦", completion: isError)
        }

        session.onProcessExit = { [weak self] in
            guard let self = self else { return }
            if self.activeChatProvider == provider {
                self.terminalView?.endStreaming()
                self.terminalView?.appendError("\(providerName) session ended.")
            }
            self.applyPetState(.confused, phrase: "连接断了一下", completion: true, autoReturnAfter: 6.0)
        }

        if let hermesSession = session as? HermesSession {
            hermesSession.onModelChanged = { [weak self] _ in
                guard let self = self else { return }
                guard self.activeChatProvider == .hermes else { return }
                self.refreshHermesSidebar()
                self.rebuildUtilityStripIfNeeded(force: true)
                self.chatTitleLabel?.stringValue = self.chatTitleText()
            }

            hermesSession.onPermissionRequest = { [weak self, weak hermesSession] request in
                guard let self = self, let hermesSession = hermesSession else { return }
                if self.activeChatProvider == .hermes {
                    self.terminalView?.appendToolUse(
                        toolName: "Hermes 等待主人确认",
                        summary: request.command.isEmpty ? request.detail : request.command
                    )
                }
                self.showHermesPermissionRequest(request, session: hermesSession)
                self.applyPetState(.listening, phrase: "等主人拍板", completion: false, autoReturnAfter: 12.0)
            }

            hermesSession.onGatewayInputRequest = { [weak self, weak hermesSession] request in
                guard let self = self, let hermesSession = hermesSession else { return }
                if self.activeChatProvider == .hermes {
                    self.terminalView?.appendToolUse(
                        toolName: request.title,
                        summary: request.envVar.isEmpty ? request.prompt : "\(request.envVar)：\(request.prompt)"
                    )
                }
                self.showHermesGatewayInputRequest(request, session: hermesSession)
                self.applyPetState(.listening, phrase: "等主人输入", completion: false, autoReturnAfter: 18.0)
            }

            hermesSession.onVoiceStatus = { [weak self] status in
                guard let self = self else { return }
                if self.activeChatProvider == .hermes {
                    self.terminalView?.setVoiceStatus(status)
                }
                let mode: String
                if status.recording {
                    mode = "recording"
                } else if status.processing {
                    mode = "processing"
                } else if status.speaking {
                    mode = "speaking"
                } else {
                    mode = "idle"
                }
                guard mode != self.lastVoiceAnimationMode else { return }
                self.lastVoiceAnimationMode = mode
                switch mode {
                case "recording":
                    self.applyPetState(.listening, phrase: "我在听主人说", completion: false, autoReturnAfter: 10.0)
                case "processing":
                    self.applyPetState(.thinking, phrase: "我在听写", completion: false, autoReturnAfter: 8.0)
                case "speaking":
                    self.applyPetState(.affection, phrase: "我念给主人听", completion: false, autoReturnAfter: 6.0)
                default:
                    break
                }
            }

            hermesSession.onVoiceTranscript = { [weak self] text in
                guard let self = self else { return }
                if self.activeChatProvider == .hermes {
                    self.terminalView?.appendVoiceTranscript(text)
                    self.terminalView?.appendToolUse(toolName: "Hermes 语音转写", summary: text)
                }
                self.applyPetState(.thinking, phrase: "听懂啦，我想想", completion: false, autoReturnAfter: 6.0)
            }
        }
    }

    private func presentationForHermesMirror(toolName: String, input: [String: Any], provider: AgentProvider) -> (state: PetState, phrase: String, hold: Double?) {
        guard provider == .hermes else {
            return (.working, "我去工作区看一眼", nil)
        }

        if toolName.contains("等待主人确认") {
            return (.listening, "等主人拍板", 12.0)
        }
        if toolName.contains("权限已处理") {
            return (.working, "按主人说的做", 5.0)
        }
        if toolName.contains("执行命令") {
            return (.working, "我在跑命令", nil)
        }
        if toolName.contains("读取文件") {
            return (.thinking, "我在读文件", nil)
        }
        if toolName.contains("修改文件") {
            return (.working, "我在改文件", nil)
        }
        if toolName.contains("搜索内容") {
            return (.thinking, "我在找线索", nil)
        }
        if toolName.contains("读取记忆") {
            return (.thinking, "翻记忆本", nil)
        }
        if toolName.contains("写入记忆") {
            return (.working, "写进记忆本", nil)
        }
        if toolName.contains("压缩上下文") {
            return (.thinking, "整理长上下文", nil)
        }
        if toolName.contains("警告") || toolName.contains("失败") {
            return (.confused, "这里要小心", 7.0)
        }
        if let tool = input["工具"] as? String, !tool.isEmpty {
            if tool.localizedCaseInsensitiveContains("image_generate") {
                return (.working, "我在画图", nil)
            }
            if tool.localizedCaseInsensitiveContains("video_generate") {
                return (.working, "我在生成视频", nil)
            }
            if tool.localizedCaseInsensitiveContains("text_to_speech") || tool.localizedCaseInsensitiveContains("tts") {
                return (.listening, "我在准备语音", nil)
            }
            if tool.localizedCaseInsensitiveContains("computer") {
                return (.working, "我在操作电脑", nil)
            }
            if tool.localizedCaseInsensitiveContains("browser") || tool.localizedCaseInsensitiveContains("web") {
                return (.thinking, "我在网上找", nil)
            }
            if tool.localizedCaseInsensitiveContains("read") {
                return (.thinking, "工具在读东西", nil)
            }
            if tool.localizedCaseInsensitiveContains("write") || tool.localizedCaseInsensitiveContains("patch") {
                return (.working, "工具在改东西", nil)
            }
            if tool.localizedCaseInsensitiveContains("exec") || tool.localizedCaseInsensitiveContains("terminal") {
                return (.working, "工具在跑命令", nil)
            }
        }
        return (.working, "我去工作区看一眼", nil)
    }

    private func showMemoryInbox() {
        memoryInboxWindow?.orderOut(nil)
        memoryCandidateEditors = [:]

        let candidates = HermesBridge.shared.pendingMemoryCandidates(limit: 5, target: memoryInboxFilter)
        let w: CGFloat = 700
        let h: CGFloat = candidates.isEmpty ? 280 : 216 + CGFloat(candidates.count) * 92
        let anchor = popoverWindow?.frame ?? window.frame
        let screen = (popoverWindow?.screen ?? window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let x = min(max(anchor.midX - w / 2, screen.minX + 16), screen.maxX - w - 16)
        let y = min(max(anchor.maxY - h - 24, screen.minY + 16), screen.maxY - h - 16)

        let win = NSWindow(contentRect: NSRect(x: x, y: y, width: w, height: h), styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 30)
        win.collectionBehavior = [.canJoinAllSpaces, .transient]

        let root = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(red: 1.0, green: 0.94, blue: 0.84, alpha: 0.98).cgColor
        root.layer?.cornerRadius = 26
        root.layer?.cornerCurve = .continuous
        root.layer?.borderWidth = 1.2
        root.layer?.borderColor = NSColor(red: 0.95, green: 0.55, blue: 0.22, alpha: 0.48).cgColor

        root.addSubview(makeLabel("小橘子 · 记忆候选箱", frame: NSRect(x: 26, y: h - 48, width: w - 180, height: 24), fontSize: 17, weight: .heavy, color: NSColor(red: 0.22, green: 0.15, blue: 0.09, alpha: 1)))
        root.addSubview(makeLabel("自动识别的长期记忆先放这里，主人点写入后才进入 Hermes 官方 memory。", frame: NSRect(x: 28, y: h - 76, width: w - 56, height: 18), fontSize: 11.5, weight: .medium, color: NSColor(red: 0.45, green: 0.32, blue: 0.20, alpha: 0.86)))

        let close = makeMemoryInboxButton(title: "关闭", identifier: "__memory_close__", frame: NSRect(x: w - 84, y: h - 48, width: 58, height: 28), fill: NSColor.white.withAlphaComponent(0.62), text: NSColor(red: 0.38, green: 0.25, blue: 0.16, alpha: 1))
        root.addSubview(close)

        let filters = [("全部", "ALL"), ("USER", "USER"), ("MEMORY", "MEMORY"), ("DAILY", "DAILY")]
        for (idx, filter) in filters.enumerated() {
            let selected = memoryInboxFilter == filter.1
            root.addSubview(makeMemoryInboxButton(
                title: filter.0,
                identifier: "__memory_filter:\(filter.1)",
                frame: NSRect(x: 28 + CGFloat(idx) * 76, y: h - 112, width: 68, height: 26),
                fill: selected ? NSColor(red: 1.0, green: 0.58, blue: 0.28, alpha: 0.96) : NSColor.white.withAlphaComponent(0.54),
                text: selected ? .white : NSColor(red: 0.38, green: 0.25, blue: 0.16, alpha: 1)
            ))
        }

        if candidates.isEmpty {
            let empty = makeLabel("这个筛选下还没有待确认候选。小橘子会继续观察明确偏好、项目规则和长期事实。", frame: NSRect(x: 30, y: 120, width: w - 60, height: 42), fontSize: 13, weight: .semibold, color: NSColor(red: 0.38, green: 0.27, blue: 0.18, alpha: 0.88), alignment: .center)
            empty.lineBreakMode = .byWordWrapping
            root.addSubview(empty)
        } else {
            for (idx, candidate) in candidates.enumerated() {
                let top = h - 140 - CGFloat(idx) * 92
                let row = makePill(frame: NSRect(x: 24, y: top - 78, width: w - 48, height: 82), fill: NSColor.white.withAlphaComponent(0.48), border: NSColor(red: 0.95, green: 0.66, blue: 0.34, alpha: 0.38), radius: 15)
                let title = makeLabel("[\(candidate.target)] \(candidate.title) · \(candidate.reason)", frame: NSRect(x: 14, y: 57, width: row.frame.width - 178, height: 15), fontSize: 10.5, weight: .heavy, color: NSColor(red: 0.34, green: 0.22, blue: 0.13, alpha: 1))
                let content = makeMemoryCandidateEditor(candidate.content, frame: NSRect(x: 14, y: 13, width: row.frame.width - 178, height: 40))
                memoryCandidateEditors[candidate.id] = content
                row.addSubview(title)
                row.addSubview(content)
                row.addSubview(makeMemoryInboxButton(title: "写入", identifier: "__memory_accept:\(candidate.id)", frame: NSRect(x: row.frame.width - 150, y: 43, width: 62, height: 24), fill: NSColor(red: 1.0, green: 0.58, blue: 0.28, alpha: 0.94), text: .white))
                row.addSubview(makeMemoryInboxButton(title: "忽略", identifier: "__memory_ignore:\(candidate.id)", frame: NSRect(x: row.frame.width - 78, y: 43, width: 52, height: 24), fill: NSColor(red: 0.98, green: 0.82, blue: 0.78, alpha: 0.82), text: NSColor(red: 0.58, green: 0.18, blue: 0.13, alpha: 1)))
                root.addSubview(row)
            }
        }

        root.addSubview(makeMemoryInboxButton(title: "打开候选箱 .md", identifier: "__memory_open_inbox__", frame: NSRect(x: 26, y: 26, width: 124, height: 30), fill: NSColor.white.withAlphaComponent(0.58), text: NSColor(red: 0.38, green: 0.25, blue: 0.16, alpha: 1)))
        root.addSubview(makeMemoryInboxButton(title: "打开 Hermes 记忆", identifier: "__memory_open_official__", frame: NSRect(x: 158, y: 26, width: 124, height: 30), fill: NSColor.white.withAlphaComponent(0.58), text: NSColor(red: 0.38, green: 0.25, blue: 0.16, alpha: 1)))
        if !candidates.isEmpty {
            root.addSubview(makeMemoryInboxButton(title: "全部写入", identifier: "__memory_accept_all__", frame: NSRect(x: w - 194, y: 26, width: 78, height: 30), fill: NSColor(red: 1.0, green: 0.58, blue: 0.28, alpha: 0.94), text: .white))
            root.addSubview(makeMemoryInboxButton(title: "全部忽略", identifier: "__memory_ignore_all__", frame: NSRect(x: w - 108, y: 26, width: 78, height: 30), fill: NSColor(red: 0.98, green: 0.82, blue: 0.78, alpha: 0.82), text: NSColor(red: 0.58, green: 0.18, blue: 0.13, alpha: 1)))
        }

        win.contentView = root
        memoryInboxWindow = win
        win.orderFrontRegardless()
        terminalView?.appendToolResult(summary: HermesBridge.shared.memoryCandidateSummary(), isError: false)
        applyPetState(.thinking, phrase: "翻候选记忆", completion: true, autoReturnAfter: 4.0)
    }

    private func makeMemoryCandidateEditor(_ text: String, frame: NSRect) -> NSTextField {
        let field = NSTextField(frame: frame)
        field.stringValue = text
        field.font = .systemFont(ofSize: 10.5, weight: .regular)
        field.textColor = NSColor(red: 0.40, green: 0.30, blue: 0.22, alpha: 0.94)
        field.backgroundColor = NSColor.white.withAlphaComponent(0.62)
        field.isBordered = false
        field.isEditable = true
        field.isSelectable = true
        field.focusRingType = .none
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.wantsLayer = true
        field.layer?.cornerRadius = 9
        field.layer?.cornerCurve = .continuous
        return field
    }

    private func makeMemoryInboxButton(title: String, identifier: String, frame: NSRect, fill: NSColor, text: NSColor) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = title
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.target = self
        button.action = #selector(handleMemoryInboxButton(_:))
        button.isBordered = false
        button.font = .systemFont(ofSize: 11, weight: .bold)
        button.contentTintColor = text
        button.wantsLayer = true
        button.layer?.backgroundColor = fill.cgColor
        button.layer?.cornerRadius = min(frame.height / 2, 12)
        button.layer?.cornerCurve = .continuous
        return button
    }

    @objc private func handleMemoryInboxButton(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        if raw == "__memory_close__" {
            memoryInboxWindow?.orderOut(nil)
            memoryInboxWindow = nil
            return
        }
        if raw == "__memory_open_inbox__" {
            NSWorkspace.shared.open(HermesBridge.shared.memoryInboxURL)
            return
        }
        if raw == "__memory_open_official__" {
            NSWorkspace.shared.open(HermesBridge.shared.hermesMemoryDirectoryURL)
            return
        }
        if raw.hasPrefix("__memory_filter:") {
            memoryInboxFilter = raw.replacingOccurrences(of: "__memory_filter:", with: "")
            showMemoryInbox()
            return
        }
        if raw == "__memory_accept_all__" {
            let ids = memoryCandidateEditors.keys.sorted()
            let edits = memoryCandidateEditors.reduce(into: [String: String]()) { result, item in
                result[item.key] = item.value.stringValue
            }
            let count = HermesBridge.shared.approveMemoryCandidates(ids: ids, contentOverrides: edits)
            terminalView?.appendToolResult(summary: "已写入 \(count) 条 Hermes 长期记忆", isError: false)
            applyPetState(.working, phrase: "批量记好了", completion: true, autoReturnAfter: 3.0)
            showMemoryInbox()
            return
        }
        if raw == "__memory_ignore_all__" {
            let ids = memoryCandidateEditors.keys.sorted()
            let count = HermesBridge.shared.dismissMemoryCandidates(ids: ids)
            terminalView?.appendToolResult(summary: "已忽略 \(count) 条记忆候选", isError: false)
            applyPetState(.done, phrase: "先放过这些", completion: true, autoReturnAfter: 3.0)
            showMemoryInbox()
            return
        }
        if raw.hasPrefix("__memory_accept:") {
            let id = raw.replacingOccurrences(of: "__memory_accept:", with: "")
            let edited = memoryCandidateEditors[id]?.stringValue
            if HermesBridge.shared.approveMemoryCandidate(id: id, contentOverride: edited) {
                terminalView?.appendToolResult(summary: "已写入一条 Hermes 长期记忆", isError: false)
                applyPetState(.working, phrase: "写进记忆本", completion: true, autoReturnAfter: 3.0)
                showMemoryInbox()
            }
            return
        }
        if raw.hasPrefix("__memory_ignore:") {
            let id = raw.replacingOccurrences(of: "__memory_ignore:", with: "")
            if HermesBridge.shared.dismissMemoryCandidate(id: id) {
                terminalView?.appendToolResult(summary: "已忽略一条记忆候选", isError: false)
                applyPetState(.done, phrase: "这条先不记", completion: true, autoReturnAfter: 3.0)
                showMemoryInbox()
            }
        }
    }

    private func showHermesPermissionRequest(_ request: HermesPermissionRequest, session: HermesSession) {
        pendingPermissionSession = session
        pendingPermissionRequestID = request.id
        permissionWindow?.orderOut(nil)

        let w: CGFloat = 520
        let h: CGFloat = 260
        let anchor = popoverWindow?.frame ?? window.frame
        let screen = (popoverWindow?.screen ?? window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let x = min(max(anchor.midX - w / 2, screen.minX + 16), screen.maxX - w - 16)
        let y = min(max(anchor.maxY - h - 24, screen.minY + 16), screen.maxY - h - 16)

        let win = NSWindow(contentRect: NSRect(x: x, y: y, width: w, height: h), styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 32)
        win.collectionBehavior = [.canJoinAllSpaces, .transient]

        let root = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(red: 1.0, green: 0.93, blue: 0.82, alpha: 0.97).cgColor
        root.layer?.cornerRadius = 28
        root.layer?.cornerCurve = .continuous
        root.layer?.borderWidth = 1.4
        root.layer?.borderColor = NSColor(red: 0.95, green: 0.52, blue: 0.20, alpha: 0.50).cgColor

        let title = makeLabel("小橘子 · 等主人确认", frame: NSRect(x: 26, y: h - 48, width: w - 52, height: 24), fontSize: 17, weight: .heavy, color: NSColor(red: 0.22, green: 0.15, blue: 0.09, alpha: 1))
        root.addSubview(title)

        let detail = makeLabel(request.detail, frame: NSRect(x: 28, y: h - 92, width: w - 56, height: 38), fontSize: 12.5, weight: .medium, color: NSColor(red: 0.42, green: 0.31, blue: 0.22, alpha: 0.95))
        root.addSubview(detail)

        let commandText = request.command.isEmpty ? request.rawText : request.command
        let commandBox = makePill(frame: NSRect(x: 26, y: 82, width: w - 52, height: 78), fill: NSColor.white.withAlphaComponent(0.50), border: NSColor(red: 0.93, green: 0.66, blue: 0.36, alpha: 0.45), radius: 14)
        let command = makeLabel(commandText, frame: NSRect(x: 14, y: 11, width: commandBox.frame.width - 28, height: 56), fontSize: 11.5, weight: .regular, color: NSColor(red: 0.26, green: 0.20, blue: 0.16, alpha: 0.95))
        commandBox.addSubview(command)
        root.addSubview(commandBox)

        let choices: [(HermesPermissionDecision, String)] = request.allowPermanent
            ? [(.allowOnce, "只允许这次"), (.allowSession, "允许"), (.allowAlways, "记住选择"), (.deny, "拒绝")]
            : [(.allowOnce, "只允许这次"), (.allowSession, "允许"), (.deny, "拒绝")]
        let gap: CGFloat = 10
        let buttonW = (w - 52 - gap * CGFloat(choices.count - 1)) / CGFloat(choices.count)
        for (idx, item) in choices.enumerated() {
            let bx = 26 + CGFloat(idx) * (buttonW + gap)
            let button = NSButton(frame: NSRect(x: bx, y: 26, width: buttonW, height: 38))
            button.title = item.1
            button.identifier = NSUserInterfaceItemIdentifier(item.0.rawValue)
            button.target = self
            button.action = #selector(handleHermesPermissionButton(_:))
            button.isBordered = false
            button.font = .systemFont(ofSize: 12.5, weight: .bold)
            button.wantsLayer = true
            button.layer?.cornerRadius = 13
            button.layer?.cornerCurve = .continuous
            let isDeny = item.0 == .deny
            button.layer?.backgroundColor = isDeny
                ? NSColor(red: 0.98, green: 0.82, blue: 0.78, alpha: 0.90).cgColor
                : NSColor(red: 1.0, green: 0.58, blue: 0.28, alpha: 0.92).cgColor
            button.contentTintColor = isDeny
                ? NSColor(red: 0.55, green: 0.16, blue: 0.13, alpha: 1)
                : .white
            root.addSubview(button)
        }

        win.contentView = root
        permissionWindow = win
        win.orderFrontRegardless()
    }

    @objc private func handleHermesPermissionButton(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let decision = HermesPermissionDecision(rawValue: raw) else { return }
        pendingPermissionSession?.respondToPermission(decision)
        let isDeny = decision == .deny
        terminalView?.appendToolResult(summary: "权限选择：\(decision.title)", isError: isDeny)
        permissionWindow?.orderOut(nil)
        permissionWindow = nil
        pendingPermissionSession = nil
        pendingPermissionRequestID = nil
        applyPetState(isDeny ? .confused : .working, phrase: isDeny ? "那我先停手" : "按主人说的做", completion: true, autoReturnAfter: 4.0)
    }

    private func showHermesGatewayInputRequest(_ request: HermesGatewayInputRequest, session: HermesSession) {
        pendingGatewayInputSession = session
        pendingGatewayInputRequest = request
        gatewayInputWindow?.orderOut(nil)
        gatewayInputField = nil

        let hasChoices = request.kind == .clarify && !request.choices.isEmpty
        let choiceRows = min(request.choices.count, 4)
        let w: CGFloat = 540
        let h: CGFloat = hasChoices ? 250 + CGFloat(choiceRows) * 36 : 272
        let anchor = popoverWindow?.frame ?? window.frame
        let screen = (popoverWindow?.screen ?? window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let x = min(max(anchor.midX - w / 2, screen.minX + 16), screen.maxX - w - 16)
        let y = min(max(anchor.maxY - h - 24, screen.minY + 16), screen.maxY - h - 16)

        let win = NSWindow(contentRect: NSRect(x: x, y: y, width: w, height: h), styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 33)
        win.collectionBehavior = [.canJoinAllSpaces, .transient]

        let root = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(red: 1.0, green: 0.94, blue: 0.84, alpha: 0.98).cgColor
        root.layer?.cornerRadius = 28
        root.layer?.cornerCurve = .continuous
        root.layer?.borderWidth = 1.4
        root.layer?.borderColor = NSColor(red: 0.95, green: 0.52, blue: 0.20, alpha: 0.50).cgColor

        root.addSubview(makeLabel(request.title, frame: NSRect(x: 26, y: h - 48, width: w - 52, height: 24), fontSize: 17, weight: .heavy, color: NSColor(red: 0.22, green: 0.15, blue: 0.09, alpha: 1)))

        let subtitle: String
        switch request.kind {
        case .clarify:
            subtitle = "Hermes 想先问清楚再继续。"
        case .sudo:
            subtitle = "密码只通过官方 sudo.respond 发回 Hermes，不写入记忆或日志。"
        case .secret:
            subtitle = request.envVar.isEmpty ? "Secret 只通过官方 secret.respond 发回 Hermes。" : "变量：\(request.envVar)"
        }
        root.addSubview(makeLabel(subtitle, frame: NSRect(x: 28, y: h - 75, width: w - 56, height: 18), fontSize: 11.5, weight: .medium, color: NSColor(red: 0.45, green: 0.32, blue: 0.20, alpha: 0.88)))

        let promptBox = makePill(frame: NSRect(x: 26, y: h - 144, width: w - 52, height: 58), fill: NSColor.white.withAlphaComponent(0.52), border: NSColor(red: 0.93, green: 0.66, blue: 0.36, alpha: 0.45), radius: 14)
        let prompt = makeLabel(request.prompt, frame: NSRect(x: 14, y: 10, width: promptBox.frame.width - 28, height: 38), fontSize: 12, weight: .regular, color: NSColor(red: 0.30, green: 0.22, blue: 0.15, alpha: 0.95))
        promptBox.addSubview(prompt)
        root.addSubview(promptBox)

        var controlsY = h - 186
        if hasChoices {
            for (idx, choice) in request.choices.prefix(4).enumerated() {
                let button = makeGatewayInputButton(
                    title: choice,
                    identifier: "__gateway_choice:\(idx)",
                    frame: NSRect(x: 26, y: controlsY - CGFloat(idx) * 36, width: w - 52, height: 28),
                    fill: NSColor.white.withAlphaComponent(0.64),
                    text: NSColor(red: 0.34, green: 0.22, blue: 0.13, alpha: 1)
                )
                button.alignment = .left
                root.addSubview(button)
            }
            controlsY -= CGFloat(choiceRows) * 36 + 4
        }

        let fieldFrame = NSRect(x: 26, y: 74, width: w - 52, height: 38)
        let field: NSTextField
        if request.kind == .sudo || request.kind == .secret {
            field = NSSecureTextField(frame: fieldFrame)
        } else {
            field = NSTextField(frame: fieldFrame)
        }
        field.placeholderString = hasChoices ? "也可以自己输入答案..." : "输入后交给 Hermes..."
        field.font = .systemFont(ofSize: 13, weight: .regular)
        field.isBordered = false
        field.focusRingType = .none
        field.backgroundColor = NSColor.white.withAlphaComponent(0.70)
        field.wantsLayer = true
        field.layer?.cornerRadius = 12
        field.layer?.cornerCurve = .continuous
        gatewayInputField = field
        root.addSubview(field)

        root.addSubview(makeGatewayInputButton(title: "取消", identifier: "__gateway_cancel__", frame: NSRect(x: 26, y: 26, width: 92, height: 34), fill: NSColor(red: 0.98, green: 0.82, blue: 0.78, alpha: 0.90), text: NSColor(red: 0.55, green: 0.16, blue: 0.13, alpha: 1)))
        root.addSubview(makeGatewayInputButton(title: "提交给 Hermes", identifier: "__gateway_submit__", frame: NSRect(x: w - 154, y: 26, width: 128, height: 34), fill: NSColor(red: 1.0, green: 0.58, blue: 0.28, alpha: 0.94), text: .white))

        win.contentView = root
        gatewayInputWindow = win
        win.orderFrontRegardless()
        win.makeFirstResponder(field)
    }

    private func makeGatewayInputButton(title: String, identifier: String, frame: NSRect, fill: NSColor, text: NSColor) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = title
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.target = self
        button.action = #selector(handleHermesGatewayInputButton(_:))
        button.isBordered = false
        button.font = .systemFont(ofSize: 12.5, weight: .bold)
        button.contentTintColor = text
        button.wantsLayer = true
        button.layer?.backgroundColor = fill.cgColor
        button.layer?.cornerRadius = min(frame.height / 2, 13)
        button.layer?.cornerCurve = .continuous
        return button
    }

    @objc private func handleHermesGatewayInputButton(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let request = pendingGatewayInputRequest else { return }
        let value: String
        if raw.hasPrefix("__gateway_choice:") {
            let idxText = raw.replacingOccurrences(of: "__gateway_choice:", with: "")
            let index = Int(idxText) ?? -1
            guard request.choices.indices.contains(index) else { return }
            value = request.choices[index]
        } else if raw == "__gateway_cancel__" {
            value = ""
        } else {
            value = gatewayInputField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        pendingGatewayInputSession?.respondToGatewayInput(request, value: value)
        terminalView?.appendToolResult(summary: raw == "__gateway_cancel__" ? "已取消 Hermes 输入" : "已提交 Hermes 输入", isError: raw == "__gateway_cancel__")
        gatewayInputWindow?.orderOut(nil)
        gatewayInputWindow = nil
        pendingGatewayInputSession = nil
        pendingGatewayInputRequest = nil
        gatewayInputField = nil
        applyPetState(raw == "__gateway_cancel__" ? .confused : .working, phrase: raw == "__gateway_cancel__" ? "先不填啦" : "交给 Hermes", completion: true, autoReturnAfter: 4.0)
    }

    private func ensureSession(provider explicitProvider: AgentProvider? = nil) {
        let provider = explicitProvider ?? activeChatProvider
        if session(for: provider) == nil {
            let newSession = provider.createSession()
            setSession(newSession, for: provider)
            wireSession(newSession, provider: provider)
            newSession.start()
        }
    }

    private func ensureCodexSession() {
        if codexSession != nil { return }
        if let latest = CodexConversationStore.shared.recentThreads(limit: 1).first {
            loadCodexThread(latest, announce: false)
            return
        }
        ensureSession(provider: .codex)
    }

    private func ensureHermesSession() {
        if agentSession != nil { return }
        if let currentID = HermesSession.desktopSessionID,
           let currentThread = HermesConversationStore.shared.thread(id: currentID) {
            loadHermesThread(currentThread, announce: false)
            return
        }
        selectedHermesThreadID = nil
        selectedHermesThreadTitle = nil
        ensureSession(provider: .hermes)
    }

    private func loadHermesThread(_ thread: HermesThreadSummary, announce: Bool) {
        activeChatProvider = .hermes
        let messages = HermesConversationStore.shared.loadMessages(for: thread)

        agentSession?.terminate()
        let newSession = HermesSession()
        newSession.attach(sessionID: thread.id, history: messages)
        agentSession = newSession
        selectedHermesThreadID = thread.id
        selectedHermesThreadTitle = thread.title
        wireSession(newSession, provider: .hermes)
        newSession.start()

        terminalView?.replayHistory(messages)
        updateChatUI()
        refreshHermesSidebar()
        if announce {
            terminalView?.appendToolResult(summary: "已切换到 Hermes 对话：\(thread.title)", isError: false)
            applyPetState(.listening, phrase: "Hermes 对话切好啦", completion: true, autoReturnAfter: 3.0)
        }
    }

    private func loadCodexThread(_ thread: CodexThreadSummary, announce: Bool) {
        activeChatProvider = .codex
        let messages = CodexConversationStore.shared.loadMessages(for: thread)

        codexSession?.terminate()
        let newSession = CodexSession()
        newSession.attach(threadID: thread.id, history: messages)
        codexSession = newSession
        selectedCodexThreadID = thread.id
        selectedCodexThreadTitle = thread.title
        wireSession(newSession, provider: .codex)
        newSession.start()

        terminalView?.replayHistory(messages)
        updateChatUI()
        refreshCodexSidebar()
        if announce {
            terminalView?.appendToolResult(summary: "已切换到 Codex 对话：\(thread.title)", isError: false)
            applyPetState(.listening, phrase: "对话切好啦", completion: true, autoReturnAfter: 3.0)
        }
    }

    private func makeAnimationTagButton(title: String, videoName: String, allowsMovement: Bool, width: CGFloat) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: width, height: 32))
        button.title = title
        button.identifier = NSUserInterfaceItemIdentifier(videoName)
        button.tag = allowsMovement ? 1 : 0
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 16
        if let cell = button.cell as? NSButtonCell {
            cell.wraps = false
            cell.lineBreakMode = .byClipping
        }
        button.target = self
        button.action = #selector(switchAnimationFromTag(_:))
        return button
    }

    @objc private func switchAnimationFromTag(_ sender: NSButton) {
        guard let videoName = sender.identifier?.rawValue else { return }
        switchAnimation(to: videoName, allowsMovement: sender.tag == 1)
    }

    @objc private func switchChatProviderFromBubble(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let provider = AgentProvider(rawValue: raw) else { return }
        activateChatProvider(provider, announce: true)
    }

    private func activateChatProvider(_ provider: AgentProvider, announce: Bool) {
        activeChatProvider = provider
        if provider == .codex {
            ensureCodexSession()
        } else if provider == .hermes {
            ensureHermesSession()
        } else {
            ensureSession()
        }
        let phrase = provider == .codex ? "Codex 入口打开" : "Hermes 接回来啦"
        applyPetState(.listening, phrase: phrase, completion: true, autoReturnAfter: 3.0)

        if announce, let terminal = terminalView, currentSession?.history.isEmpty ?? true {
            let summary = provider == .codex
                ? "Codex 工作入口已接到小橘子桌宠"
                : "Hermes 小橘子本体已接回聊天"
            terminal.appendToolResult(summary: summary, isError: false)
        }
    }

    private func updateProviderBubbleSelection() {
        for (provider, button) in providerBubbleButtons {
            let selected = provider == activeChatProvider
            button.layer?.cornerRadius = button.frame.height / 2
            button.layer?.cornerCurve = .continuous
            button.layer?.borderWidth = selected ? 1.4 : 1
            button.layer?.borderColor = selected
                ? NSColor(red: 0.95, green: 0.48, blue: 0.18, alpha: 0.76).cgColor
                : NSColor(red: 0.96, green: 0.70, blue: 0.42, alpha: 0.26).cgColor
            button.layer?.backgroundColor = selected
                ? NSColor(red: 1.0, green: 0.82, blue: 0.58, alpha: 0.72).cgColor
                : NSColor.white.withAlphaComponent(0.32).cgColor
            button.alphaValue = selected ? 1.0 : 0.82
        }
    }

    private func chatTitleText() -> String {
        if activeChatProvider == .codex {
            let config = CodexConfig.shared.snapshot
            let threadTitle = selectedCodexThreadTitle.map { " · \(clipped($0, limit: 18))" } ?? ""
            return "\(petState.title) · Codex\(threadTitle) · \(shortModelName(config.model)) / \(config.reasoningEffort)"
        }
        let runtimeModel = currentHermesRuntimeModel()
        let threadTitle = selectedHermesThreadTitle.map { " · \(clipped($0, limit: 18))" } ?? ""
        return "\(petState.title) · Hermes\(threadTitle) · \(hermesProviderTitle(runtimeModel.provider)) / \(shortHermesModelName(runtimeModel.model))"
    }

    private func updateChatUI() {
        chatTitleLabel?.stringValue = chatTitleText()
        terminalView?.updatePlaceholder(activeChatProvider.inputPlaceholder)
        rebuildUtilityStripIfNeeded()
        layoutChatContent()
        updateProviderBubbleSelection()
        if activeChatProvider == .codex {
            refreshCodexSidebar()
        } else if activeChatProvider == .hermes {
            refreshHermesSidebar()
        }

        if let terminal = terminalView {
            terminal.applyTheme()
            popoverWindow?.makeFirstResponder(terminal.inputField)
        }
    }

    private func layoutChatContent() {
        guard let terminal = terminalView,
              let container = terminal.superview else { return }
        let bottom: CGFloat = 18
        let height = container.bounds.height - 260
        let fullWidth = container.bounds.width - 36
        let sidebarWidth: CGFloat = 232
        let terminalX = 18 + sidebarWidth + 12

        if activeChatProvider == .codex {
            hermesSidebarView?.isHidden = true
            codexSidebarView?.isHidden = false
            codexSidebarView?.frame = NSRect(x: 18, y: bottom, width: sidebarWidth, height: height)
            terminal.frame = NSRect(x: terminalX, y: bottom, width: container.bounds.width - terminalX - 18, height: height)
        } else if activeChatProvider == .hermes {
            codexSidebarView?.isHidden = true
            hermesSidebarView?.isHidden = false
            hermesSidebarView?.frame = NSRect(x: 18, y: bottom, width: sidebarWidth, height: height)
            terminal.frame = NSRect(x: terminalX, y: bottom, width: container.bounds.width - terminalX - 18, height: height)
        } else {
            codexSidebarView?.isHidden = true
            hermesSidebarView?.isHidden = true
            terminal.frame = NSRect(x: 18, y: bottom, width: fullWidth, height: height)
        }
    }

    private func rebuildUtilityStripIfNeeded(force: Bool = false) {
        guard let currentStrip = utilityStripView,
              let container = currentStrip.superview else { return }
        let signature = currentUtilityStripSignature()
        guard force || utilityStripProvider != activeChatProvider || utilityStripSignature != signature else { return }
        let frame = currentStrip.frame
        currentStrip.removeFromSuperview()
        let newStrip = makeUtilityStrip(frame: frame)
        container.addSubview(newStrip, positioned: .above, relativeTo: nil)
        utilityStripView = newStrip
        utilityStripProvider = activeChatProvider
        utilityStripSignature = signature
    }

    private func currentUtilityStripSignature() -> String {
        if activeChatProvider == .codex {
            let config = CodexConfig.shared.snapshot
            return "codex|\(config.model)|\(config.reasoningEffort)"
        }
        let runtimeModel = currentHermesRuntimeModel()
        return "hermes|\(runtimeModel.provider)|\(runtimeModel.model)|\(HermesCatalog.shared.syncSignature())"
    }

    private func updateAnimationTagSelection() {
        let t = resolvedTheme
        for button in animationTagButtons {
            let isSelected = button.identifier?.rawValue == currentVideoName && (button.tag == 1) == currentAnimationAllowsMovement
            button.contentTintColor = isSelected ? .white : t.textPrimary
            button.layer?.backgroundColor = isSelected ? t.accentColor.cgColor : NSColor.white.withAlphaComponent(0.62).cgColor
            button.layer?.borderColor = isSelected ? t.accentColor.cgColor : t.separatorColor.withAlphaComponent(0.35).cgColor
            button.layer?.borderWidth = 1
            button.alphaValue = isSelected ? 1.0 : 0.96
        }
    }

    func terminateAllSessions() {
        agentSession?.terminate()
        codexSession?.terminate()
        agentSession = nil
        codexSession = nil
        permissionWindow?.orderOut(nil)
        permissionWindow = nil
        gatewayInputWindow?.orderOut(nil)
        gatewayInputWindow = nil
        memoryInboxWindow?.orderOut(nil)
        memoryInboxWindow = nil
        pendingPermissionSession = nil
        pendingPermissionRequestID = nil
        pendingGatewayInputSession = nil
        pendingGatewayInputRequest = nil
        gatewayInputField = nil
    }

    private func formatToolInput(_ input: [String: Any]) -> String {
        if let cmd = input["command"] as? String { return cmd }
        if let cmd = input["命令"] as? String { return cmd }
        if let path = input["file_path"] as? String { return path }
        if let path = input["路径"] as? String { return path }
        if let pattern = input["pattern"] as? String { return pattern }
        if let clue = input["线索"] as? String { return clue }
        if let status = input["状态"] as? String { return status }
        if let detail = input["说明"] as? String { return detail }
        return input.keys.sorted().prefix(3).joined(separator: ", ")
    }

    func updatePopoverPosition(anchorToCharacter: Bool = false) {
        guard let popover = popoverWindow, isIdleForPopover else { return }
        guard let screen = controller?.activeScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        guard anchorToCharacter || popoverFollowsCharacter else {
            clampPopoverToVisibleFrame()
            return
        }

        let charFrame = window.frame
        let popoverSize = popover.frame.size
        var x = charFrame.midX - popoverSize.width / 2
        let y = charFrame.maxY - 15

        let screenFrame = screen.visibleFrame
        x = max(screenFrame.minX + 4, min(x, screenFrame.maxX - popoverSize.width - 4))
        let clampedY = min(y, screenFrame.maxY - popoverSize.height - 4)

        popover.setFrameOrigin(NSPoint(x: x, y: clampedY))
    }

    private func clampPopoverToVisibleFrame() {
        guard let popover = popoverWindow else { return }
        let screen = popover.screen ?? controller?.activeScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let frame = popover.frame
        let x = max(visibleFrame.minX + 4, min(frame.origin.x, visibleFrame.maxX - frame.width - 4))
        let y = max(visibleFrame.minY + 4, min(frame.origin.y, visibleFrame.maxY - frame.height - 4))
        if x != frame.origin.x || y != frame.origin.y {
            popover.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    // MARK: - Thinking Bubble

    private static let thinkingPhrases = [
        "小橘子翻翻记忆...", "我去工作区看一眼", "主人稍等...",
        "我在整理线索", "小橘子开工啦", "让我确认下",
        "在等那边回信", "我把东西捋顺", "马上给主人"
    ]

    private static let completionPhrases = [
        "给主人整理好了", "好啦，收工", "小橘子搞定", "放到主人手边了", "完成啦"
    ]

    private static let puffedPhrases = [
        "小橘子鼓起来啦", "噗一下", "气鼓鼓待命", "软乎乎上线"
    ]

    private static let pokedPhrases = [
        "戳到小橘子啦", "噗，收到", "主人在点名？", "别戳漏气啦"
    ]

    private static let affectionPhrases = [
        "小橘子贴过来", "我在这呢", "给主人贴贴", "靠近一点"
    ]

    private var lastPhraseUpdate: CFTimeInterval = 0
    var currentPhrase = ""
    var completionBubbleExpiry: CFTimeInterval = 0
    var showingCompletion = false

    private static let bubbleH: CGFloat = 26
    private var phraseAnimating = false

    func updateThinkingBubble() {
        let now = CACurrentMediaTime()

        if showingCompletion {
            if now >= completionBubbleExpiry {
                showingCompletion = false
                hideBubble()
                return
            }
            if isIdleForPopover {
                completionBubbleExpiry += 1.0 / 60.0
                hideBubble()
            } else {
                showBubble(text: currentPhrase, isCompletion: true)
            }
            return
        }

        if isAgentBusy && !isIdleForPopover {
            let oldPhrase = currentPhrase
            updateThinkingPhrase()
            if currentPhrase != oldPhrase && !oldPhrase.isEmpty && !phraseAnimating {
                animatePhraseChange(to: currentPhrase, isCompletion: false)
            } else if !phraseAnimating {
                showBubble(text: currentPhrase, isCompletion: false)
            }
        } else if !showingCompletion {
            hideBubble()
        }
    }

    private func hideBubble() {
        if thinkingBubbleWindow?.isVisible ?? false {
            thinkingBubbleWindow?.orderOut(nil)
        }
    }

    private func animatePhraseChange(to newText: String, isCompletion: Bool) {
        guard let win = thinkingBubbleWindow, win.isVisible,
              let label = win.contentView?.viewWithTag(100) as? NSTextField else {
            showBubble(text: newText, isCompletion: isCompletion)
            return
        }
        phraseAnimating = true

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            label.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.showBubble(text: newText, isCompletion: isCompletion)
            label.alphaValue = 0.0
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                ctx.allowsImplicitAnimation = true
                label.animator().alphaValue = 1.0
            }, completionHandler: {
                self?.phraseAnimating = false
            })
        })
    }

    func showBubble(text: String, isCompletion: Bool) {
        let t = resolvedTheme
        if thinkingBubbleWindow == nil {
            createThinkingBubble()
        }

        let h = Self.bubbleH
        let padding: CGFloat = 16
        let font = t.bubbleFont
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let bubbleW = max(ceil(textSize.width) + padding * 2, 48)

        let charFrame = window.frame
        let x = charFrame.midX - bubbleW / 2
        let y = charFrame.origin.y + charFrame.height * 0.88
        thinkingBubbleWindow?.setFrame(CGRect(x: x, y: y, width: bubbleW, height: h), display: false)

        let borderColor = isCompletion ? t.bubbleCompletionBorder.cgColor : t.bubbleBorder.cgColor
        let textColor = isCompletion ? t.bubbleCompletionText : t.bubbleText

        if let container = thinkingBubbleWindow?.contentView {
            container.frame = NSRect(x: 0, y: 0, width: bubbleW, height: h)
            container.layer?.backgroundColor = t.bubbleBg.cgColor
            container.layer?.cornerRadius = t.bubbleCornerRadius
            container.layer?.borderColor = borderColor
            if let label = container.viewWithTag(100) as? NSTextField {
                label.font = font
                let lineH = ceil(textSize.height)
                let labelY = round((h - lineH) / 2) - 1
                label.frame = NSRect(x: 0, y: labelY, width: bubbleW, height: lineH + 2)
                label.stringValue = text
                label.textColor = textColor
            }
        }

        if !(thinkingBubbleWindow?.isVisible ?? false) {
            thinkingBubbleWindow?.alphaValue = 1.0
            thinkingBubbleWindow?.orderFrontRegardless()
            animateBubblePop(isCompletion: isCompletion)
        }
    }

    private func animateBubblePop(isCompletion: Bool) {
        guard let layer = thinkingBubbleWindow?.contentView?.layer else { return }
        let scale = CAKeyframeAnimation(keyPath: "transform")
        let peak: CGFloat = isCompletion ? 1.08 : 1.04
        scale.values = [
            CATransform3DMakeScale(0.88, 0.88, 1),
            CATransform3DMakeScale(peak, peak, 1),
            CATransform3DIdentity
        ]
        scale.duration = 0.22
        scale.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        layer.add(scale, forKey: "morangeBubblePop")
    }

    private func updateThinkingPhrase() {
        let now = CACurrentMediaTime()
        if currentPhrase.isEmpty || now - lastPhraseUpdate > Double.random(in: 3.0...5.0) {
            var next = Self.thinkingPhrases.randomElement() ?? "..."
            while next == currentPhrase && Self.thinkingPhrases.count > 1 {
                next = Self.thinkingPhrases.randomElement() ?? "..."
            }
            currentPhrase = next
            lastPhraseUpdate = now
        }
    }

    func showCompletionBubble() {
        currentPhrase = Self.completionPhrases.randomElement() ?? "done!"
        showingCompletion = true
        completionBubbleExpiry = CACurrentMediaTime() + 3.0
        lastPhraseUpdate = 0
        phraseAnimating = false
        if !isIdleForPopover {
            showBubble(text: currentPhrase, isCompletion: true)
        }
    }

    private func createThinkingBubble() {
        let t = resolvedTheme
        let w: CGFloat = 80
        let h = Self.bubbleH
        let win = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: w, height: h),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 5)
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        container.wantsLayer = true
        container.layer?.backgroundColor = t.bubbleBg.cgColor
        container.layer?.cornerRadius = t.bubbleCornerRadius
        container.layer?.borderWidth = 1
        container.layer?.borderColor = t.bubbleBorder.cgColor

        let font = t.bubbleFont
        let lineH = ceil(("Xg" as NSString).size(withAttributes: [.font: font]).height)
        let labelY = round((h - lineH) / 2) - 1

        let label = NSTextField(labelWithString: "")
        label.font = font
        label.textColor = t.bubbleText
        label.alignment = .center
        label.drawsBackground = false
        label.isBordered = false
        label.isEditable = false
        label.frame = NSRect(x: 0, y: labelY, width: w, height: lineH + 2)
        label.tag = 100
        container.addSubview(label)

        win.contentView = container
        thinkingBubbleWindow = win
    }

    // MARK: - Completion Sound

    static var soundsEnabled = true

    private static let completionSounds: [(name: String, ext: String)] = [
        ("morange-done", "m4a"), ("morange-soft", "m4a")
    ]
    private static var lastSoundIndex: Int = -1

    func playCompletionSound() {
        guard Self.soundsEnabled else { return }
        var idx: Int
        repeat {
            idx = Int.random(in: 0..<Self.completionSounds.count)
        } while idx == Self.lastSoundIndex && Self.completionSounds.count > 1
        Self.lastSoundIndex = idx

        let s = Self.completionSounds[idx]
        if let url = Bundle.main.url(forResource: s.name, withExtension: s.ext, subdirectory: "Sounds"),
           let sound = NSSound(contentsOf: url, byReference: true) {
            sound.play()
        }
    }

    func playConfusedSound() {
        guard Self.soundsEnabled else { return }
        if let url = Bundle.main.url(forResource: "morange-confused", withExtension: "m4a", subdirectory: "Sounds"),
           let sound = NSSound(contentsOf: url, byReference: true) {
            sound.play()
        }
    }

    // MARK: - Walking

    func startWalk() {
        isPaused = false
        isWalking = true
        playCount = 0
        walkStartTime = CACurrentMediaTime()

        if positionProgress > 0.85 {
            goingRight = false
        } else if positionProgress < 0.15 {
            goingRight = true
        } else {
            goingRight = Bool.random()
        }

        walkStartPos = positionProgress
        // Walk a fixed pixel distance (~200-325px) regardless of screen width.
        let referenceWidth: CGFloat = 500.0
        let walkPixels = CGFloat.random(in: walkAmountRange) * referenceWidth
        let walkAmount = currentTravelDistance > 0 ? walkPixels / currentTravelDistance : 0.3
        if goingRight {
            walkEndPos = min(walkStartPos + walkAmount, 1.0)
        } else {
            walkEndPos = max(walkStartPos - walkAmount, 0.0)
        }
        // Store pixel positions so walk speed stays consistent if screen changes mid-walk
        walkStartPixel = walkStartPos * currentTravelDistance
        walkEndPixel = walkEndPos * currentTravelDistance

        let minSeparation: CGFloat = 0.12
        if let siblings = controller?.characters {
            for sibling in siblings where sibling !== self {
                let sibPos = sibling.positionProgress
                if abs(walkEndPos - sibPos) < minSeparation {
                    if goingRight {
                        walkEndPos = max(walkStartPos, sibPos - minSeparation)
                    } else {
                        walkEndPos = min(walkStartPos, sibPos + minSeparation)
                    }
                }
            }
        }

        updateFlip()
        queuePlayer.seek(to: .zero)
        queuePlayer.play()
    }

    func enterPause() {
        isWalking = false
        isPaused = true
        queuePlayer.play()
        if restartWalkImmediately {
            pauseEndTime = CACurrentMediaTime() + 0.05
        } else {
            let delay = Double.random(in: minimumPauseRange)
            pauseEndTime = CACurrentMediaTime() + delay
        }
    }

    func updateFlip() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if goingRight {
            playerLayer.transform = CATransform3DIdentity
        } else {
            playerLayer.transform = CATransform3DMakeScale(-1, 1, 1)
        }
        playerLayer.frame = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
        CATransaction.commit()
    }

    var currentFlipCompensation: CGFloat {
        goingRight ? 0 : flipXOffset
    }

    private func synchronizeProgressWithCurrentWindowOrigin() {
        guard
            let lastDockX,
            let lastDockWidth,
            window != nil
        else { return }

        let travelDistance = max(lastDockWidth - displayWidth, 0)
        guard travelDistance > 0 else { return }

        let originX = window.frame.origin.x - currentFlipCompensation
        positionProgress = min(max((originX - lastDockX) / travelDistance, 0), 1)
        let pixelPosition = positionProgress * travelDistance
        walkStartPixel = pixelPosition
        walkEndPixel = pixelPosition
        walkStartPos = positionProgress
        walkEndPos = positionProgress
    }

    func movementPosition(at videoTime: CFTimeInterval) -> CGFloat {
        let dIn = fullSpeedStart - accelStart
        let dLin = decelStart - fullSpeedStart
        let dOut = walkStop - decelStart
        let v = 1.0 / (dIn / 2.0 + dLin + dOut / 2.0)

        if videoTime <= accelStart {
            return 0.0
        } else if videoTime <= fullSpeedStart {
            let t = videoTime - accelStart
            return CGFloat(v * t * t / (2.0 * dIn))
        } else if videoTime <= decelStart {
            let easeInDist = v * dIn / 2.0
            let t = videoTime - fullSpeedStart
            return CGFloat(easeInDist + v * t)
        } else if videoTime <= walkStop {
            let easeInDist = v * dIn / 2.0
            let linearDist = v * dLin
            let t = videoTime - decelStart
            return CGFloat(easeInDist + linearDist + v * (t - t * t / (2.0 * dOut)))
        } else {
            return 1.0
        }
    }

    // MARK: - Frame Update

    func update(dockX: CGFloat, dockWidth: CGFloat, dockTopY: CGFloat) {
        lastDockX = dockX
        lastDockWidth = dockWidth
        lastDockTopY = dockTopY
        currentTravelDistance = max(dockWidth - displayWidth, 0)
        repairVisibilityIfNeeded()
        let now = CACurrentMediaTime()
        if isDraggingManually, let origin = manualWindowOrigin {
            window.setFrameOrigin(origin)
            updatePopoverPosition()
            updateThinkingBubble()
            return
        }
        maybeApplyAmbientState(now: now)
        if let origin = manualWindowOrigin {
            window.setFrameOrigin(origin)
            updatePopoverPosition()
            updateThinkingBubble()
            return
        }
        if !currentAnimationAllowsMovement {
            if queuePlayer.timeControlStatus != .playing {
                queuePlayer.play()
            }
            if CACurrentMediaTime() < interactionHoldUntil {
                updateThinkingBubble()
                return
            }
            let travelDistance = currentTravelDistance
            let x = dockX + travelDistance * positionProgress + currentFlipCompensation
            let bottomPadding = displayHeight * 0.15
            let y = dockTopY - bottomPadding + yOffset
            window.setFrameOrigin(NSPoint(x: x, y: y))
            if isIdleForPopover {
                updatePopoverPosition()
                updateThinkingBubble()
            }
            return
        }
        if isIdleForPopover {
            if queuePlayer.timeControlStatus != .playing {
                queuePlayer.play()
            }
            let travelDistance = currentTravelDistance
            let x = dockX + travelDistance * positionProgress + currentFlipCompensation
            let bottomPadding = displayHeight * 0.15
            let y = dockTopY - bottomPadding + yOffset
            window.setFrameOrigin(NSPoint(x: x, y: y))
            updatePopoverPosition()
            updateThinkingBubble()
            return
        }

        if !isAgentBusy && !isIdleForPopover && petState != .sleepy && now - lastInteractionTime > 120 {
            applyPetState(.sleepy, phrase: "小橘子充会电", completion: false)
        }

        if isPaused {
            if now >= pauseEndTime {
                startWalk()
            } else {
                if queuePlayer.timeControlStatus != .playing {
                    queuePlayer.play()
                }
                let travelDistance = max(dockWidth - displayWidth, 0)
                let x = dockX + travelDistance * positionProgress + currentFlipCompensation
                let bottomPadding = displayHeight * 0.15
                let y = dockTopY - bottomPadding + yOffset
                window.setFrameOrigin(NSPoint(x: x, y: y))
                return
            }
        }

        if isWalking {
            let elapsed = now - walkStartTime
            let videoTime = min(elapsed, videoDuration)
            let travelDistance = currentTravelDistance

            // Interpolate in pixel space for consistent speed across screen changes
            let walkNorm = elapsed >= videoDuration ? 1.0 : movementPosition(at: videoTime)
            let currentPixel = walkStartPixel + (walkEndPixel - walkStartPixel) * walkNorm

            // Convert pixel position back to progress for the current screen
            if travelDistance > 0 {
                positionProgress = min(max(currentPixel / travelDistance, 0), 1)
            }

            if elapsed >= videoDuration {
                walkEndPos = positionProgress
                enterPause()
                return
            }

            let x = dockX + travelDistance * positionProgress + currentFlipCompensation
            let bottomPadding = displayHeight * 0.15
            let y = dockTopY - bottomPadding + yOffset
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        updateThinkingBubble()
    }

    func repairVisibilityIfNeeded() {
        guard !isUserHidden, let window else { return }

        window.alphaValue = 1
        window.level = Self.characterWindowLevel
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView?.isHidden = false
        window.contentView?.alphaValue = 1

        if playerLayer.superlayer !== window.contentView?.layer {
            playerLayer.removeFromSuperlayer()
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.addSublayer(playerLayer)
        }
        playerLayer.zPosition = 1
        playerLayer.isHidden = false
        playerLayer.opacity = 1
        let playerItemFailed = queuePlayer?.currentItem?.status == .failed
        let playerQueueEmpty = queuePlayer?.items().isEmpty ?? true
        if queuePlayer == nil || queuePlayer.currentItem == nil || playerItemFailed || playerQueueEmpty || playerLayer.player == nil {
            rebuildCurrentAnimationPlayer()
        } else if playerLayer.player !== queuePlayer {
            playerLayer.player = queuePlayer
        }
        if queuePlayer.timeControlStatus != .playing {
            queuePlayer.play()
        }
        if playerLayer.bounds.size.width <= 1 || playerLayer.bounds.size.height <= 1 {
            playerLayer.frame = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
        }
        if let hostLayer = window.contentView?.layer {
            hostLayer.isHidden = false
            hostLayer.opacity = 1
            hostLayer.speed = 1
            hostLayer.frame = CGRect(origin: .zero, size: window.frame.size)
        }

        let screen = window.screen ?? controller?.activeScreen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var frame = window.frame
        if frame.width <= 20 || frame.height <= 20 || !frame.origin.x.isFinite || !frame.origin.y.isFinite {
            frame.size = NSSize(width: displayWidth, height: displayHeight)
        }

        let visibleIntersection = frame.intersection(visible)
        let mostlyOffscreen = visibleIntersection.isNull
            || visibleIntersection.width < min(44, frame.width * 0.25)
            || visibleIntersection.height < min(44, frame.height * 0.25)
        if mostlyOffscreen {
            let x = min(max(frame.origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
            let y = min(max(frame.origin.y, visible.minY + 8), visible.maxY - frame.height - 8)
            let repairedOrigin = NSPoint(x: x, y: y)
            window.setFrame(CGRect(origin: repairedOrigin, size: frame.size), display: true)
            manualWindowOrigin = nil
            synchronizeProgressWithCurrentWindowOrigin()
        }

        if !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    private func rebuildCurrentAnimationPlayer() {
        guard let videoURL = videoURL(for: currentVideoName) else { return }
        let asset = AVURLAsset(url: videoURL)
        let previousPlayer = queuePlayer
        looper?.disableLooping()
        let nextPlayer = AVQueuePlayer()
        looper = AVPlayerLooper(player: nextPlayer, templateItem: AVPlayerItem(asset: asset))
        queuePlayer = nextPlayer
        playerLayer.player = nextPlayer
        previousPlayer?.pause()
        previousPlayer?.removeAllItems()
        updateFlip()
        if !isUserHidden {
            queuePlayer.play()
        }
    }
}
