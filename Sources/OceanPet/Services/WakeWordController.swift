import Foundation

@MainActor
public final class WakeWordController {
    public var onWake: (() -> Void)?
    public var onError: ((String) -> Void)?

    public private(set) var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "oceanpet.wake-word-enabled") }
    }

    private let speech = SpeechInputController()
    private var isSuspended = false
    private var restartTask: Task<Void, Never>?
    private var wakeWords: [String] = []

    public init() {
        isEnabled = UserDefaults.standard.bool(forKey: "oceanpet.wake-word-enabled")
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startListening()
        } else {
            stopListening()
        }
    }

    public func startIfEnabled() {
        guard isEnabled else { return }
        startListening()
    }

    public func setWakeWords(_ words: [String]) {
        wakeWords = words.compactMap { word in
            let normalized = Self.normalize(word)
            return normalized.isEmpty ? nil : normalized
        }
        guard isEnabled, !isSuspended, speech.isListening else { return }
        stopListening()
        startListening()
    }

    public func suspend() {
        isSuspended = true
        stopListening()
    }

    public func resumeAfterConversation() {
        isSuspended = false
        scheduleRestart(after: 1.5)
    }

    private func startListening() {
        guard isEnabled, !isSuspended, !speech.isListening else { return }
        restartTask?.cancel()
        Task {
            do {
                try await speech.start(
                    requiresOnDevice: true,
                    onTranscript: { [weak self] transcript in
                        self?.inspect(transcript)
                    },
                    onFinished: { [weak self] _ in
                        self?.scheduleRestart(after: 0.8)
                    },
                    onError: { [weak self] message in
                        self?.onError?(message)
                        self?.scheduleRestart(after: 5)
                    }
                )
            } catch {
                onError?(error.localizedDescription)
                if let speechError = error as? SpeechInputController.SpeechError {
                    switch speechError {
                    case .speechPermissionDenied, .microphonePermissionDenied, .onDeviceRecognitionUnavailable:
                        isEnabled = false
                    default:
                        scheduleRestart(after: 5)
                    }
                } else {
                    scheduleRestart(after: 5)
                }
            }
        }
    }

    private func inspect(_ transcript: String) {
        let normalized = Self.normalize(transcript)
        guard wakeWords.contains(where: normalized.contains) else { return }
        speech.cancel()
        isSuspended = true
        onWake?()
    }

    private nonisolated static func normalize(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    private func stopListening() {
        restartTask?.cancel()
        restartTask = nil
        speech.cancel()
    }

    private func scheduleRestart(after delay: TimeInterval) {
        guard isEnabled, !isSuspended else { return }
        restartTask?.cancel()
        restartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.startListening()
        }
    }
}
