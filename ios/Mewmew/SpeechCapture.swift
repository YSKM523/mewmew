import AVFoundation
import Combine
import Speech

@MainActor
protocol SpeechCapturing: ObservableObject {
    var transcript: String { get }
    var isRecording: Bool { get }
    var errorMessage: String? { get }

    func requestPermissions() async -> Bool
    func start()
    func stop()
}

@MainActor
final class SpeechCapture: ObservableObject, SpeechCapturing {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledInputTap = false

    init(locale: Locale = .current) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    func requestPermissions() async -> Bool {
        let speechStatus = await requestSpeechRecognitionPermission()
        let microphoneAllowed = await requestMicrophonePermission()

        guard speechStatus == .authorized else {
            errorMessage = "请在系统设置中允许语音识别。"
            return false
        }
        guard microphoneAllowed else {
            errorMessage = "请在系统设置中允许使用麦克风。"
            return false
        }

        errorMessage = nil
        return true
    }

    func start() {
        guard !isRecording else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "语音识别暂时不可用，请稍后再试。"
            return
        }

        resetRecognitionSession()
        transcript = ""
        errorMessage = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setActive(true, options: [])

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                throw SpeechCaptureError.audioInputUnavailable
            }

            inputNode.installTap(
                onBus: 0,
                bufferSize: 1_024,
                format: recordingFormat
            ) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            hasInstalledInputTap = true

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            recognitionTask = speechRecognizer.recognitionTask(with: request) {
                [weak self] result,
                error in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if let result {
                        transcript = result.bestTranscription.formattedString
                        if result.isFinal {
                            finishAudioCapture()
                        }
                    }

                    if let error, isRecording {
                        errorMessage = error.localizedDescription
                        finishAudioCapture()
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            finishAudioCapture()
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        stopAudioEngine()
        recognitionRequest?.endAudio()
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func finishAudioCapture() {
        isRecording = false
        stopAudioEngine()
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledInputTap = false
        }
    }

    private func resetRecognitionSession() {
        stopAudioEngine()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }

    private func requestSpeechRecognitionPermission()
        async -> SFSpeechRecognizerAuthorizationStatus
    {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}

private enum SpeechCaptureError: LocalizedError {
    case audioInputUnavailable

    var errorDescription: String? {
        "没有可用的麦克风输入。"
    }
}
