import AppKit
import Foundation
import ServiceManagement

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configStore = DeepSeekConfigStore()
    private let characterStore = CharacterStore()
    private let knowledgeStore = LocalKnowledgeStore()
    private let pushToTalk = GlobalPushToTalk()
    private let wakeWord = WakeWordController()
    private lazy var chatStore = ChatStore(
        deepSeek: DeepSeekClient(),
        configStore: configStore,
        persistence: ConversationPersistence(),
        characterStore: characterStore,
        knowledgeStore: knowledgeStore
    )

    private var petController: PetWindowController?
    private var chatController: ChatPanelController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try configStore.ensureTemplateExists()
        } catch {
            showError("无法创建 DeepSeek 配置文件：\(error.localizedDescription)")
        }

        guard let character = characterStore.active else {
            showError("无法加载内置角色，请重新构建 OceanPet。")
            NSApp.terminate(nil)
            return
        }

        do {
            let pet = try PetWindowController(character: character)
            let chat = ChatPanelController(store: chatStore) { [weak self] recovery in
                self?.perform(recovery)
            }
            petController = pet
            chatController = chat

            pet.onDoubleClick = { [weak self, weak pet] in
                guard let self, let frame = pet?.window.frame else { return }
                self.chatController?.toggle(near: frame)
            }
            pet.menuProvider = { [weak self] in self?.makeContextMenu() }
            pet.onMove = { [weak chat] frame in chat?.updateAnchor(petFrame: frame) }
            chat.onVisibilityChanged = { [weak pet] visible in pet?.setRoamingPaused(visible) }
            chatStore.onNeedsAPIKey = { [weak self] in self?.openAPIConfig() }
            chatStore.onVisualState = { [weak pet] state in pet?.setState(state) }
            chatStore.onVoiceSessionChanged = { [weak self] active in
                if active {
                    self?.wakeWord.suspend()
                } else {
                    self?.wakeWord.resumeAfterConversation()
                }
            }
            pushToTalk.onPress = { [weak self, weak pet] in
                guard let self, let frame = pet?.window.frame else { return }
                self.chatController?.show(near: frame)
                self.chatStore.startVoiceInput(autoStopOnSilence: false)
            }
            pushToTalk.onRelease = { [weak self] in
                self?.chatStore.stopVoiceInput()
            }
            wakeWord.onWake = { [weak self, weak pet] in
                guard let self, let pet else { return }
                pet.scene.playClickReaction()
                NSSound(named: NSSound.Name("Pop"))?.play()
                self.chatController?.show(near: pet.window.frame)
                self.chatStore.startVoiceInput(autoStopOnSilence: true)
            }
            wakeWord.onError = { [weak self] message in
                self?.chatStore.presentError(message, recovery: .dictationSettings)
            }
            wakeWord.setWakeWords(character.manifest.effectiveWakeWords)
            pet.show()
            wakeWord.startIfEnabled()
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(systemDidWake),
                name: NSWorkspace.didWakeNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(screenConfigurationChanged),
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
            if ProcessInfo.processInfo.arguments.contains("--open-chat") {
                DispatchQueue.main.async {
                    chat.toggle(near: pet.window.frame)
                }
            }
        } catch {
            showError(error.localizedDescription)
            NSApp.terminate(nil)
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "OceanPet")
        menu.autoenablesItems = false
        menu.addItem(item("打开聊天（也可双击）", action: #selector(toggleChat), key: ""))
        menu.addItem(item("打开 DeepSeek 配置文件…", action: #selector(openAPIConfigAction), key: ""))

        let wakeName = characterStore.active?.manifest.conversationName ?? "当前角色"
        let voiceWake = item("语音唤醒：喊“\(wakeName)”", action: #selector(toggleWakeWord(_:)), key: "")
        voiceWake.state = wakeWord.isEnabled ? .on : .off
        menu.addItem(voiceWake)
        let shortcut = NSMenuItem(title: "按住 ⌥Space 说话", action: nil, keyEquivalent: "")
        shortcut.isEnabled = false
        menu.addItem(shortcut)

        let roaming = item("在附近走动", action: #selector(toggleRoaming(_:)), key: "")
        roaming.state = petController?.isRoamingEnabled == true ? .on : .off
        menu.addItem(roaming)

        let login = item("开机自动启动", action: #selector(toggleLaunchAtLogin(_:)), key: "")
        switch SMAppService.mainApp.status {
        case .enabled: login.state = .on
        case .requiresApproval: login.state = .mixed
        default: login.state = .off
        }
        menu.addItem(login)

        let notesItem = NSMenuItem(title: "本地笔记", action: nil, keyEquivalent: "")
        let notesMenu = NSMenu(title: "本地笔记")
        notesMenu.addItem(item("选择 Obsidian 知识库…", action: #selector(selectKnowledgeVault), key: ""))
        if let vault = knowledgeStore.vaultURL {
            let current = NSMenuItem(title: "当前：\(vault.lastPathComponent)", action: nil, keyEquivalent: "")
            current.isEnabled = false
            notesMenu.addItem(current)
            notesMenu.addItem(item("停用本地笔记", action: #selector(clearKnowledgeVault), key: ""))
        }
        notesItem.submenu = notesMenu
        menu.addItem(notesItem)

        let charactersItem = NSMenuItem(title: "更换形象", action: nil, keyEquivalent: "")
        let charactersMenu = NSMenu(title: "更换形象")
        for character in characterStore.characters {
            let option = NSMenuItem(title: character.manifest.displayName, action: #selector(selectCharacter(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = character.id
            option.state = character.id == characterStore.active?.id ? .on : .off
            charactersMenu.addItem(option)
        }
        charactersMenu.addItem(.separator())
        charactersMenu.addItem(item("导入角色包…", action: #selector(importCharacter), key: ""))
        charactersItem.submenu = charactersMenu
        menu.addItem(charactersItem)

        menu.addItem(.separator())
        menu.addItem(item("清空聊天记录", action: #selector(clearConversation), key: ""))
        menu.addItem(item("回到屏幕右下角", action: #selector(resetPosition), key: ""))
        menu.addItem(.separator())
        menu.addItem(item("退出 OceanPet", action: #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        result.isEnabled = true
        return result
    }

    @objc private func toggleChat() {
        guard let frame = petController?.window.frame else { return }
        chatController?.toggle(near: frame)
    }

    @objc private func toggleWakeWord(_ sender: NSMenuItem) {
        wakeWord.setEnabled(!wakeWord.isEnabled)
        sender.state = wakeWord.isEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = SMAppService.mainApp.status == .enabled ? .on : .mixed
            }
        } catch {
            showError("无法修改开机启动设置：\(error.localizedDescription)")
        }
    }

    @objc private func selectKnowledgeVault() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "选择 Obsidian 知识库"
        panel.message = "选择包含 Markdown 笔记的文件夹。笔记只在本机检索。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        knowledgeStore.setVault(url)
    }

    @objc private func clearKnowledgeVault() {
        knowledgeStore.setVault(nil)
    }

    @objc private func systemDidWake() {
        petController?.reconcileAfterScreenChange()
    }

    @objc private func screenConfigurationChanged() {
        petController?.reconcileAfterScreenChange()
    }

    @objc private func openAPIConfigAction() {
        openAPIConfig()
    }

    private func openAPIConfig() {
        do {
            try configStore.ensureTemplateExists()
            guard let textEditURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.TextEdit"
            ) else {
                showError("找不到 macOS 自带的“文本编辑”。配置文件位于：\(configStore.configURL.path)")
                return
            }

            let options = NSWorkspace.OpenConfiguration()
            options.activates = true
            NSWorkspace.shared.open(
                [configStore.configURL],
                withApplicationAt: textEditURL,
                configuration: options
            ) { [weak self] _, error in
                guard let error else { return }
                DispatchQueue.main.async {
                    self?.showError("无法用“文本编辑”打开配置文件：\(error.localizedDescription)")
                }
            }
        } catch {
            showError("无法创建 DeepSeek 配置文件：\(error.localizedDescription)")
        }
    }

    private func perform(_ recovery: ChatStore.ErrorRecoveryAction) {
        switch recovery {
        case .apiConfiguration:
            openAPIConfig()
        case .dictationSettings:
            openSystemSettings("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        case .microphonePrivacy:
            openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechRecognitionPrivacy:
            openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        }
    }

    private func openSystemSettings(_ address: String) {
        guard let url = URL(string: address), NSWorkspace.shared.open(url) else {
            showError("无法打开系统设置，请手动进入“系统设置 → 键盘 → 听写”。")
            return
        }
    }

    @objc private func selectCharacter(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let character = characterStore.characters.first(where: { $0.id == id }) else { return }
        activate(character)
    }

    @objc private func importCharacter() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "选择角色包目录"
        panel.message = "目录中需要包含 pet.json 和透明 PNG 精灵图。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let character = try characterStore.importPackage(from: url)
            activate(character)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func activate(_ character: PetCharacter) {
        do {
            characterStore.select(character)
            try petController?.apply(character: character)
            wakeWord.setWakeWords(character.manifest.effectiveWakeWords)
            chatStore.characterDidChange()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func clearConversation() {
        chatStore.clear()
    }

    @objc private func toggleRoaming(_ sender: NSMenuItem) {
        guard let petController else { return }
        petController.setRoamingEnabled(!petController.isRoamingEnabled)
    }

    @objc private func resetPosition() {
        guard let window = petController?.window,
              let visible = NSScreen.main?.visibleFrame else { return }
        petController?.moveHome(to: CGPoint(
            x: visible.maxX - window.frame.width - 70,
            y: visible.minY + 54
        ))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "OceanPet"
        alert.informativeText = message
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}
