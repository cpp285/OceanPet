import AVFoundation
import Foundation
import Speech

@MainActor
public final class SpeechInputController {
    public enum SpeechError: LocalizedError {
        case speechPermissionDenied
        case microphonePermissionDenied
        case recognizerUnavailable
        case onDeviceRecognitionUnavailable
        case audioStartFailed(String)

        public var errorDescription: String? {
            switch self {
            case .speechPermissionDenied: return "需要在系统设置中允许 OceanPet 使用语音识别。"
            case .microphonePermissionDenied: return "需要在系统设置中允许 OceanPet 使用麦克风。"
            case .recognizerUnavailable: return "中文语音识别暂时不可用。"
            case .onDeviceRecognitionUnavailable: return "这台 Mac 暂不支持离线中文语音唤醒。"
            case .audioStartFailed(let message): return "无法开始录音：\(message)"
            }
        }
    }

    public private(set) var isListening = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private var completionDelivered = false
    private var onTranscript: ((String) -> Void)?
    private var onFinished: ((String) -> Void)?
    private var onError: ((String) -> Void)?
    private var autoStopOnSilence = false
    private var heardSpeech = false
    private var startedAt: TimeInterval = 0
    private var lastLoudAt: TimeInterval = 0
    private var hasAudioTap = false

    public func start(
        requiresOnDevice: Bool = false,
        autoStopOnSilence: Bool = false,
        onTranscript: @escaping (String) -> Void,
        onFinished: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) async throws {
        cancel()
        try await ensurePermissions()
        guard let recognizer, recognizer.isAvailable else { throw SpeechError.recognizerUnavailable }
        if requiresOnDevice, !recognizer.supportsOnDeviceRecognition {
            throw SpeechError.onDeviceRecognitionUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if requiresOnDevice {
            request.requiresOnDeviceRecognition = true
        }

        self.onTranscript = onTranscript
        self.onFinished = onFinished
        self.onError = onError
        self.autoStopOnSilence = autoStopOnSilence
        latestTranscript = ""
        completionDelivered = false
        heardSpeech = false
        startedAt = ProcessInfo.processInfo.systemUptime
        lastLoudAt = startedAt
        recognitionRequest = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        if hasAudioTap {
            input.removeTap(onBus: 0)
            hasAudioTap = false
        }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard autoStopOnSilence else { return }
            let rms = Self.rms(buffer)
            Task { @MainActor [weak self] in self?.observeAudioLevel(rms) }
        }
        hasAudioTap = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.latestTranscript = result.bestTranscription.formattedString
                    self.onTranscript?(self.latestTranscript)
                    if result.isFinal { self.deliverCompletion() }
                }
                if let error, !self.completionDelivered, self.isListening {
                    self.fail(Self.userFacingMessage(for: error))
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            teardownAudio()
            throw SpeechError.audioStartFailed(error.localizedDescription)
        }
    }

    public func stop() {
        guard isListening else { return }
        audioEngine.stop()
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }
        recognitionRequest?.endAudio()
        isListening = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.deliverCompletion()
        }
    }

    public func cancel() {
        completionDelivered = true
        teardownAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        onTranscript = nil
        onFinished = nil
        onError = nil
        latestTranscript = ""
    }

    private func observeAudioLevel(_ rms: Float) {
        guard isListening, autoStopOnSilence else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if rms > 0.018 {
            heardSpeech = true
            lastLoudAt = now
        } else if heardSpeech, now - lastLoudAt > 1.2 {
            stop()
        } else if !heardSpeech, now - startedAt > 5.0 {
            stop()
        }
    }

    private func deliverCompletion() {
        guard !completionDelivered else { return }
        completionDelivered = true
        let transcript = latestTranscript
        teardownAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        let completion = onFinished
        onTranscript = nil
        onFinished = nil
        onError = nil
        completion?(transcript)
    }

    private func fail(_ message: String) {
        guard !completionDelivered else { return }
        completionDelivered = true
        teardownAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        let handler = onError
        onTranscript = nil
        onFinished = nil
        onError = nil
        handler?(message)
    }

    private func teardownAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }
        isListening = false
    }

    private func ensurePermissions() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { throw SpeechError.speechPermissionDenied }
        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneAllowed else { throw SpeechError.microphonePermissionDenied }
    }

    private nonisolated static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let samples = channels[0]
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            let value = samples[index]
            sum += value * value
        }
        return sqrt(sum / Float(buffer.frameLength))
    }

    private nonisolated static func userFacingMessage(for error: Error) -> String {
        let message = error.localizedDescription
        let normalized = message.lowercased()
        if normalized.contains("siri and dictation") || normalized.contains("dictation are disabled") {
            return "请先在“系统设置 → 键盘 → 听写”中打开听写。"
        }
        if normalized.contains("not authorized") || normalized.contains("permission") {
            return "语音识别没有获得系统权限，请在系统设置中允许 OceanPet 使用语音识别。"
        }
        return "语音识别失败：\(message)"
    }
}
