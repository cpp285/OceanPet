import Foundation

@MainActor
public final class ChatStore: ObservableObject {
    public enum ErrorRecoveryAction {
        case apiConfiguration
        case dictationSettings
        case microphonePrivacy
        case speechRecognitionPrivacy

        public var buttonTitle: String {
            switch self {
            case .apiConfiguration: return "打开配置"
            case .dictationSettings, .microphonePrivacy, .speechRecognitionPrivacy: return "打开设置"
            }
        }
    }

    @Published public var input = ""
    @Published public private(set) var messages: [ChatMessage]
    @Published public private(set) var isSending = false
    @Published public private(set) var isListening = false
    @Published public private(set) var voiceStatus: String?
    @Published public private(set) var errorText: String?
    @Published public private(set) var errorRecoveryAction: ErrorRecoveryAction?
    @Published public private(set) var characterName: String

    public var onNeedsAPIKey: (() -> Void)?
    public var onVisualState: ((PetVisualState) -> Void)?
    public var onVoiceSessionChanged: ((Bool) -> Void)?

    private let deepSeek: DeepSeekClient
    private let configStore: DeepSeekConfigStore
    private let persistence: ConversationPersistence
    private let characterStore: CharacterStore
    private let knowledgeStore: LocalKnowledgeStore
    private let speechInput = SpeechInputController()
    private var voiceRequestID: UUID?

    public init(
        deepSeek: DeepSeekClient,
        configStore: DeepSeekConfigStore,
        persistence: ConversationPersistence,
        characterStore: CharacterStore,
        knowledgeStore: LocalKnowledgeStore
    ) {
        self.deepSeek = deepSeek
        self.configStore = configStore
        self.persistence = persistence
        self.characterStore = characterStore
        self.knowledgeStore = knowledgeStore
        characterName = characterStore.active?.manifest.conversationName ?? "桌宠"
        let stored = persistence.load()
        if stored.isEmpty, let greeting = characterStore.active?.manifest.persona.greeting {
            messages = [ChatMessage(role: .assistant, content: greeting)]
        } else {
            messages = stored
        }
    }

    public func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        let configuration: DeepSeekConfiguration
        do {
            configuration = try configStore.load()
        } catch {
            presentError(error.localizedDescription, recovery: .apiConfiguration)
            onNeedsAPIKey?()
            return
        }
        guard !configuration.apiKey.isEmpty else {
            presentError(
                "请在 config.json 的 deepseek.apiKey 中粘贴 Key，保存后直接重试。",
                recovery: .apiConfiguration
            )
            onNeedsAPIKey?()
            return
        }
        guard let character = characterStore.active else { return }

        input = ""
        clearError()
        messages.append(ChatMessage(role: .user, content: text))
        persistence.save(messages)
        isSending = true
        onVisualState?(.confused)

        Task {
            do {
                let notes = await knowledgeStore.search(query: text)
                let knowledgePrompt = notes.isEmpty ? "" : """

                用户启用了本地笔记参考。请只在确实相关时自然使用下面的内容，并说明笔记标题；如果内容不足，不要编造。
                \(notes)
                """
                let result = try await deepSeek.reply(
                    configuration: configuration,
                    systemPrompt: character.manifest.persona.systemPrompt + knowledgePrompt,
                    history: messages
                )
                messages.append(ChatMessage(role: .assistant, content: result.reply))
                persistence.save(messages)
                onVisualState?(PetVisualState(apiValue: result.emotion))
                scheduleIdleReset()
            } catch {
                presentError(error.localizedDescription)
                onVisualState?(.confused)
            }
            isSending = false
        }
    }

    public func clear() {
        persistence.clear()
        if let greeting = characterStore.active?.manifest.persona.greeting {
            messages = [ChatMessage(role: .assistant, content: greeting)]
        } else {
            messages = []
        }
        clearError()
        onVisualState?(.idle)
    }

    public func characterDidChange() {
        characterName = characterStore.active?.manifest.conversationName ?? "桌宠"
        clear()
    }

    public func toggleVoiceInput() {
        if isListening {
            stopVoiceInput()
        } else {
            startVoiceInput(autoStopOnSilence: false)
        }
    }

    public func startVoiceInput(autoStopOnSilence: Bool) {
        guard !isSending, !isListening else { return }
        let prefix = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        voiceRequestID = requestID
        isListening = true
        voiceStatus = "正在听你说…"
        clearError()
        onVoiceSessionChanged?(true)

        Task {
            do {
                try await speechInput.start(
                    autoStopOnSilence: autoStopOnSilence,
                    onTranscript: { [weak self] transcript in
                        guard let self, voiceRequestID == requestID else { return }
                        input = prefix.isEmpty ? transcript : "\(prefix) \(transcript)"
                    },
                    onFinished: { [weak self] transcript in
                        guard let self, voiceRequestID == requestID else { return }
                        voiceRequestID = nil
                        isListening = false
                        voiceStatus = nil
                        onVoiceSessionChanged?(false)
                        let combined = prefix.isEmpty ? transcript : "\(prefix) \(transcript)"
                        input = combined.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !input.isEmpty { send() }
                    },
                    onError: { [weak self] message in
                        guard let self, voiceRequestID == requestID else { return }
                        voiceRequestID = nil
                        isListening = false
                        voiceStatus = nil
                        presentError(message, recovery: .dictationSettings)
                        onVoiceSessionChanged?(false)
                    }
                )
                guard voiceRequestID == requestID else {
                    speechInput.cancel()
                    return
                }
            } catch {
                guard voiceRequestID == requestID else { return }
                voiceRequestID = nil
                isListening = false
                voiceStatus = nil
                presentError(error.localizedDescription, recovery: recoveryAction(for: error))
                onVoiceSessionChanged?(false)
            }
        }
    }

    public func stopVoiceInput() {
        guard isListening else { return }
        guard speechInput.isListening else {
            voiceRequestID = nil
            isListening = false
            voiceStatus = nil
            onVoiceSessionChanged?(false)
            return
        }
        voiceStatus = "正在整理语音…"
        speechInput.stop()
    }

    private func scheduleIdleReset() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard self?.isSending == false else { return }
            self?.onVisualState?(.idle)
        }
    }

    public func presentError(_ message: String, recovery: ErrorRecoveryAction? = nil) {
        errorText = message
        errorRecoveryAction = recovery
    }

    private func clearError() {
        errorText = nil
        errorRecoveryAction = nil
    }

    private func recoveryAction(for error: Error) -> ErrorRecoveryAction? {
        guard let speechError = error as? SpeechInputController.SpeechError else {
            return .dictationSettings
        }
        switch speechError {
        case .speechPermissionDenied: return .speechRecognitionPrivacy
        case .microphonePermissionDenied: return .microphonePrivacy
        case .recognizerUnavailable, .onDeviceRecognitionUnavailable, .audioStartFailed: return .dictationSettings
        }
    }
}
