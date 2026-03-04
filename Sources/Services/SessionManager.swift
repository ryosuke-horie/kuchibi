import AVFoundation
import os

/// 音声入力セッションのライフサイクル管理
@MainActor
final class SessionManagerImpl: ObservableObject {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "SessionManager")

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var partialText: String = ""
    @Published private(set) var audioLevel: Float = 0.0

    private let audioService: AudioCapturing
    private let speechService: SpeechRecognizing
    private let outputManager: OutputManaging
    private let notificationService: NotificationServicing
    private let appSettings: AppSettings
    private let preprocessor: AudioPreprocessing
    private let textPostprocessor: TextPostprocessing

    private var recordingTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(
        audioService: AudioCapturing,
        speechService: SpeechRecognizing,
        outputManager: OutputManaging,
        notificationService: NotificationServicing,
        appSettings: AppSettings,
        preprocessor: AudioPreprocessing = AudioPreprocessorImpl(),
        textPostprocessor: TextPostprocessing = TextPostprocessorImpl()
    ) {
        self.audioService = audioService
        self.speechService = speechService
        self.outputManager = outputManager
        self.notificationService = notificationService
        self.appSettings = appSettings
        self.preprocessor = preprocessor
        self.textPostprocessor = textPostprocessor
    }

    func startSession() {
        guard state == .idle else {
            Self.logger.warning("セッション開始が無視された: 現在の状態=\(String(describing: self.state))")
            return
        }

        guard speechService.isModelLoaded else {
            Self.logger.error("モデルが未読み込みのためセッション開始を拒否")
            Task {
                await notificationService.sendErrorNotification(
                    error: .modelLoadFailed(underlying: NSError(
                        domain: "com.kuchibi.app", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "モデルがまだ読み込まれていません"])))
            }
            return
        }

        let audioStream: AsyncStream<AVAudioPCMBuffer>
        do {
            audioStream = try audioService.startCapture(
                noiseSuppressionEnabled: appSettings.noiseSuppressionEnabled
            )
        } catch {
            Self.logger.error("音声キャプチャの開始に失敗: \(error.localizedDescription)")
            Task {
                await notificationService.sendErrorNotification(error: .microphoneUnavailable)
            }
            return
        }

        state = .recording
        partialText = ""
        Self.logger.info("セッションを開始")

        let processedStream = preprocessor.process(
            audioStream,
            vadEnabled: appSettings.vadEnabled,
            vadThreshold: appSettings.vadThreshold
        )
        let eventStream = speechService.processAudioStream(processedStream)

        recordingTask = Task {
            for await event in eventStream {
                await handleRecognitionEvent(event)
            }
            // イベントストリームが完了してもまだidleでなければ終了処理
            if state != .idle {
                finishSession()
            }
        }

        startSilenceTimeout()
    }

    func stopSession() {
        guard state == .recording else {
            Self.logger.warning("セッション停止が無視された: 現在の状態=\(String(describing: self.state))")
            return
        }

        state = .processing
        timeoutTask?.cancel()
        audioService.stopCapture()
        Self.logger.info("セッションを停止、認識処理中...")
    }

    func toggleSession() {
        switch state {
        case .idle:
            startSession()
        case .recording:
            stopSession()
        case .processing:
            break
        }
    }

    // MARK: - Private

    private func handleRecognitionEvent(_ event: RecognitionEvent) async {
        switch event.kind {
        case .lineStarted:
            audioLevel = audioService.currentAudioLevel
            Self.logger.debug("行の認識を開始")
        case .textChanged(let partial):
            partialText = partial
            audioLevel = audioService.currentAudioLevel
            startSilenceTimeout()
        case .lineCompleted(let final_):
            let outputText = appSettings.textPostprocessingEnabled
                ? textPostprocessor.process(final_)
                : final_
            let mode = appSettings.outputMode
            await outputManager.output(text: outputText, mode: mode)
            partialText = ""
            startSilenceTimeout()
        }
    }

    private func finishSession() {
        if audioService.isCapturing {
            audioService.stopCapture()
        }
        state = .idle
        audioLevel = 0.0
        recordingTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        Self.logger.info("セッションを完了")
    }

    private func startSilenceTimeout() {
        timeoutTask?.cancel()
        let timeout = appSettings.silenceTimeout
        timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, state == .recording else { return }
            Self.logger.info("無音タイムアウト")
            audioService.stopCapture()
            await notificationService.sendErrorNotification(error: .silenceTimeout)
            finishSession()
        }
    }
}
