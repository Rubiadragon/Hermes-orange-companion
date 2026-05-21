import SwiftUI
import AppKit

enum AppIdentity {
    static let currentBundleIdentifier = "com.rubiadragon.morangecompanion"
    static let supportDirectoryName = "morange-companion"
    static let workspacePath: String = {
        let envPath = ProcessInfo.processInfo.environment["MORANGE_HERMES_CWD"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let envPath, !envPath.isEmpty {
            return NSString(string: envPath).expandingTildeInPath
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Hermes小橘子", isDirectory: true)
            .path
    }()
    static let stableAppPath = "/Applications/小橘子桌宠.app"
    static let launchAgentIdentifier = "com.rubiadragon.morangecompanion.autostart"
}

@main
struct MOrangeCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: MOrangeCompanionController?
    var statusItem: NSStatusItem?
    var petStatusMenuItem: NSMenuItem?
    var petVisibilityMenuItem: NSMenuItem?
    var closePetMenuItem: NSMenuItem?
    var autostartMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = MOrangeCompanionController()
        controller?.start()
        setupMenuBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.characters.forEach { $0.terminateAllSessions() }
    }

    // MARK: - Menu Bar

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "小橘子桌宠")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = 240

        menu.addItem(makeSectionHeader("小橘子"))

        let closePetItem = NSMenuItem(title: "收起桌宠", action: #selector(closePet), keyEquivalent: "")
        closePetItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "收起桌宠")
        closePetMenuItem = closePetItem
        menu.addItem(closePetItem)

        let char1Item = NSMenuItem(title: "唤回桌宠", action: #selector(toggleChar1), keyEquivalent: "")
        char1Item.state = .on
        char1Item.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "唤回桌宠")
        petVisibilityMenuItem = char1Item
        menu.addItem(char1Item)

        let quitItem = NSMenuItem(title: "退出整个应用", action: #selector(quitApp), keyEquivalent: "")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "退出整个应用")
        menu.addItem(quitItem)

        let petStatusItem = NSMenuItem(title: "状态：启动中", action: nil, keyEquivalent: "")
        petStatusItem.isEnabled = false
        petStatusMenuItem = petStatusItem
        menu.addItem(petStatusItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeSettingsMenu())
        menu.addItem(makeHermesMenu())
        menu.addItem(makeAppearanceMenu())

        menu.addItem(NSMenuItem.separator())

        let restartItem = NSMenuItem(title: "重启应用", action: #selector(restartApp), keyEquivalent: "")
        restartItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "重启小橘子")
        menu.addItem(restartItem)

        menu.delegate = self
        statusItem?.menu = menu
    }

    private func makeSettingsMenu() -> NSMenuItem {
        let root = NSMenuItem(title: "开关", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: "开关")
        let submenu = NSMenu()

        let soundItem = NSMenuItem(title: "声音", action: #selector(toggleSounds(_:)), keyEquivalent: "")
        soundItem.state = WalkerCharacter.soundsEnabled ? .on : .off
        submenu.addItem(soundItem)

        let autostartItem = NSMenuItem(title: "开机启动", action: #selector(toggleAutostart(_:)), keyEquivalent: "")
        autostartItem.state = isAutostartEnabled ? .on : .off
        autostartMenuItem = autostartItem
        submenu.addItem(autostartItem)

        root.submenu = submenu
        return root
    }

    private func makeHermesMenu() -> NSMenuItem {
        let root = NSMenuItem(title: "Hermes", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Hermes")
        let submenu = NSMenu()

        submenu.addItem(NSMenuItem(title: "重载记忆", action: #selector(reloadMemory), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "检查 Hermes 连接", action: #selector(checkHermesConnection), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "清理语音缓存", action: #selector(cleanHermesAudioCache), keyEquivalent: ""))
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(NSMenuItem(title: "打开工作区", action: #selector(openHermesWorkspace), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "打开记忆", action: #selector(openHermesMemory), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "打开素材", action: #selector(openAnimationAssets), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "显示 App", action: #selector(revealStableApp), keyEquivalent: ""))

        root.submenu = submenu
        return root
    }

    private func makeAppearanceMenu() -> NSMenuItem {
        let root = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "外观")
        let submenu = NSMenu()

        let themeItem = NSMenuItem(title: "样式", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for (i, theme) in PopoverTheme.allThemes.enumerated() {
            let item = NSMenuItem(title: theme.name, action: #selector(switchTheme(_:)), keyEquivalent: "")
            item.tag = i
            item.state = i == 0 ? .on : .off
            themeMenu.addItem(item)
        }
        themeItem.submenu = themeMenu
        submenu.addItem(themeItem)

        let displayItem = NSMenuItem(title: "显示器", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu()
        displayMenu.delegate = self
        let autoItem = NSMenuItem(title: "自动（主显示器）", action: #selector(switchDisplay(_:)), keyEquivalent: "")
        autoItem.tag = -1
        autoItem.state = .on
        displayMenu.addItem(autoItem)
        displayMenu.addItem(NSMenuItem.separator())
        for (i, screen) in NSScreen.screens.enumerated() {
            let name = screen.localizedName
            let item = NSMenuItem(title: name, action: #selector(switchDisplay(_:)), keyEquivalent: "")
            item.tag = i
            item.state = .off
            displayMenu.addItem(item)
        }
        displayItem.submenu = displayMenu
        submenu.addItem(displayItem)

        root.submenu = submenu
        return root
    }

    private func makeSectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let attributed = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        item.attributedTitle = attributed
        return item
    }

    // MARK: - Menu Actions

    @objc func switchTheme(_ sender: NSMenuItem) {
        animateMenuAction(state: .affection, phrase: "换件小衣服")
        let idx = sender.tag
        guard idx < PopoverTheme.allThemes.count else { return }
        PopoverTheme.current = PopoverTheme.allThemes[idx]

        if let themeMenu = sender.menu {
            for item in themeMenu.items {
                item.state = item.tag == idx ? .on : .off
            }
        }

        controller?.characters.forEach { char in
            let wasOpen = char.isIdleForPopover
            if wasOpen { char.popoverWindow?.orderOut(nil) }
            char.popoverWindow = nil
            char.terminalView = nil
            char.thinkingBubbleWindow = nil
            if wasOpen {
                char.createPopoverWindow()
                if let session = char.currentSession, !session.history.isEmpty {
                    char.terminalView?.replayHistory(session.history)
                }
                char.updatePopoverPosition()
                char.popoverWindow?.orderFrontRegardless()
                char.popoverWindow?.makeKey()
                if let terminal = char.terminalView {
                    char.popoverWindow?.makeFirstResponder(terminal.inputField)
                }
            }
        }
    }

    @objc func switchDisplay(_ sender: NSMenuItem) {
        animateMenuAction(state: .lifted, phrase: "搬到那边去")
        let idx = sender.tag
        controller?.pinnedScreenIndex = idx

        if let displayMenu = sender.menu {
            for item in displayMenu.items {
                item.state = item.tag == idx ? .on : .off
            }
        }
    }

    @objc func toggleChar1(_ sender: NSMenuItem) {
        guard let chars = controller?.characters, chars.count > 0 else { return }
        let char = chars[0]
        if char.window.isVisible {
            char.applyPetState(.sleepy, phrase: "我先藏一下", completion: true, autoReturnAfter: 5.0)
            char.hideByUser()
            sender.state = .off
            sender.title = "唤回桌宠"
        } else {
            char.showByUser()
            char.applyPetState(.affection, phrase: "小橘子回来啦", completion: true, autoReturnAfter: 5.5)
            sender.state = .on
            sender.title = "隐藏桌宠"
        }
    }

    @objc func closePet() {
        guard let char = controller?.characters.first else { return }
        char.terminateAllSessions()
        char.closePopover()
        char.thinkingBubbleWindow?.orderOut(nil)
        char.thinkingBubbleWindow = nil
        char.applyPetState(.sleepy, phrase: "小橘子先收起来", completion: true, autoReturnAfter: 5.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            char.hideByUser()
            self.petVisibilityMenuItem?.title = "唤回桌宠"
            self.petVisibilityMenuItem?.state = .off
            self.closePetMenuItem?.isEnabled = false
        }
    }

    @objc func toggleChar2(_ sender: NSMenuItem) {
        guard let chars = controller?.characters, chars.count > 1 else { return }
        let char = chars[1]
        if char.window.isVisible {
            char.hideByUser()
            sender.state = .off
        } else {
            char.showByUser()
            sender.state = .on
        }
    }

    @objc func toggleDebug(_ sender: NSMenuItem) {
        guard let debugWin = controller?.debugWindow else { return }
        if debugWin.isVisible {
            debugWin.orderOut(nil)
            sender.state = .off
        } else {
            debugWin.orderFrontRegardless()
            sender.state = .on
        }
    }

    @objc func toggleSounds(_ sender: NSMenuItem) {
        WalkerCharacter.soundsEnabled.toggle()
        sender.state = WalkerCharacter.soundsEnabled ? .on : .off
        animateMenuAction(state: WalkerCharacter.soundsEnabled ? .affection : .sleepy, phrase: WalkerCharacter.soundsEnabled ? "声音回来啦" : "我安静一点")
    }

    @objc func toggleAutostart(_ sender: NSMenuItem) {
        if isAutostartEnabled {
            disableAutostart()
            animateMenuAction(state: .sleepy, phrase: "开机先不叫我")
        } else {
            enableAutostart()
            animateMenuAction(state: .done, phrase: "开机我会来")
        }
        sender.state = isAutostartEnabled ? .on : .off
    }

    @objc func reloadMemory() {
        HermesBridge.shared.appendMemoryEvent(category: "Bridge", title: "重载记忆", detail: "主人从菜单栏要求重新载入 Hermes 小橘子记忆。")
        controller?.characters.forEach { char in
            char.terminateAllSessions()
            char.applyPetState(.thinking, phrase: "翻一下记忆", completion: true, autoReturnAfter: 1.4)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                char.applyPetState(.done, phrase: "记忆刷新啦", completion: true, autoReturnAfter: 2.5)
            }
        }
    }

    @objc func checkHermesConnection() {
        animateMenuAction(state: .working, phrase: "检查 Hermes")
        let snapshot = HermesBridge.shared.snapshot
        let ready = snapshot.isHermesReady && snapshot.isWorkspaceReady && snapshot.isMemoryReady && snapshot.isSoulReady && snapshot.isConfigReady
        let phrase = ready ? "Hermes 融合正常" : "Hermes 配置要看一眼"
        let detail = """
        CLI：\(snapshot.hermesBinaryPath ?? "未找到")
        工作区：\(snapshot.isWorkspaceReady ? "OK" : "缺失")
        配置：\(snapshot.isConfigReady ? "OK" : "缺失")
        灵魂档案：\(snapshot.isSoulReady ? "OK" : "缺失")
        记忆：\(snapshot.isMemoryReady ? "OK" : "缺失")
        """
        HermesBridge.shared.appendMemoryEvent(category: "Bridge", title: "检查 Hermes 连接", detail: detail)
        controller?.characters.first?.applyPetState(ready ? .done : .confused, phrase: phrase, completion: true, autoReturnAfter: 3.0)
    }

    @objc func cleanHermesAudioCache() {
        animateMenuAction(state: .working, phrase: "收拾声音纸屑")
        controller?.cleanHermesAudioCache(reason: "菜单手动清理", announce: true)
    }

    @objc func openHermesWorkspace() {
        animateMenuAction(state: .working, phrase: "打开工作区")
        NSWorkspace.shared.open(HermesBridge.shared.workspaceURL)
        HermesBridge.shared.recordPlanRequest("打开 Hermes 工作区", detail: "主人从菜单栏打开主工作区。")
    }

    @objc func openHermesMemory() {
        animateMenuAction(state: .thinking, phrase: "打开记忆本")
        NSWorkspace.shared.open(HermesBridge.shared.hermesMemoryDirectoryURL)
        HermesBridge.shared.recordPlanRequest("打开 Hermes 官方记忆", detail: "主人从菜单栏打开 ~/.hermes/memories。")
    }

    @objc func openAnimationAssets() {
        animateMenuAction(state: .puffed, phrase: "翻素材箱")
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let assets = support?
            .appendingPathComponent(AppIdentity.supportDirectoryName)
            .appendingPathComponent("MOrangeAnimations")
        if let assets {
            NSWorkspace.shared.open(assets)
        }
    }

    @objc func revealStableApp() {
        animateMenuAction(state: .held, phrase: "找到我啦")
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: AppIdentity.stableAppPath)])
    }

    @objc func restartApp() {
        animateMenuAction(state: .sleepy, phrase: "我重启一下")
        controller?.characters.forEach { $0.terminateAllSessions() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.6; /usr/bin/open '\(AppIdentity.stableAppPath)'"]
        try? process.run()
        NSApp.terminate(nil)
    }

    @objc func quitApp() {
        animateMenuAction(state: .sleepy, phrase: "小橘子下线")
        NSApp.terminate(nil)
    }

    private func animateMenuAction(state: WalkerCharacter.PetState, phrase: String) {
        controller?.characters.first?.applyPetState(state, phrase: phrase, completion: true, autoReturnAfter: 3.0)
    }

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(AppIdentity.launchAgentIdentifier).plist")
    }

    private var isAutostartEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private func enableAutostart() {
        let launchAgentsDir = launchAgentURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(AppIdentity.launchAgentIdentifier)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>\(AppIdentity.stableAppPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
        try? plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
        runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentURL.path])
    }

    private func disableAutostart() {
        runLaunchctl(["bootout", "gui/\(getuid())", launchAgentURL.path])
        try? FileManager.default.removeItem(at: launchAgentURL)
    }

    private func runLaunchctl(_ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        try? process.run()
    }

}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        autostartMenuItem?.state = isAutostartEnabled ? .on : .off

        guard let char = controller?.characters.first else {
            petStatusMenuItem?.title = "状态：未启动"
            petVisibilityMenuItem?.title = "唤回桌宠"
            petVisibilityMenuItem?.state = .off
            closePetMenuItem?.isEnabled = false
            return
        }

        let isVisible = char.window?.isVisible == true
        let busy = char.isAgentBusy ? "工作中" : "待命"
        let petState = char.petState.title.replacingOccurrences(of: "小橘子 · ", with: "")
        petStatusMenuItem?.title = "状态：\(petState) · \(busy)"
        petVisibilityMenuItem?.title = isVisible ? "隐藏桌宠" : "唤回桌宠"
        petVisibilityMenuItem?.state = isVisible ? .on : .off
        closePetMenuItem?.isEnabled = isVisible
    }
}
