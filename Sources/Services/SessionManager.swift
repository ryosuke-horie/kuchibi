import AVFoundation
import os

/// 音声入力セッションのライフサイクル管理
@MainActor
final class SessionManagerImpl: ObservableObject {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "SessionManager")
    private static let silenceTimeoutSeconds: TimeInterval = 30

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var partialText: String = ""
    @Published var outputMode: OutputMode = .clipboard {
        didSet { UserDefaults.standard.set(outputMode.rawValue, forKey: "outputMode") }
    }

    private let audioService: AudioCapturing
    private let speechService: SpeechRecognizing
    private let outputManager: OutputManaging
    private let notificationService: NotificationServicing

    private var recordingTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(
        audioService: AudioCapturing,
        speechService: SpeechRecognizing,
        outputManager: OutputManaging,
        notificationService: NotificationServicing
    ) {
        self.audioService = audioService
        self.speechService = speechService
        self.outputManager = outputManager
        self.notificationService = notificationService

        // UserDefaultsから出力モードを復元
        if let saved = UserDefaults.standard.string(forKey: "outputMode"),
           let mode = OutputMode(rawValue: saved) {
            self.outputMode = mode
        }
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
            audioStream = try audioService.startCapture()
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

        let eventStream = speechService.processAudioStream(audioStream)

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
            Self.logger.debug("行の認識を開始")
        case .textChanged(let partial):
            partialText = partial
            startSilenceTimeout()
        case .lineCompleted(let final_):
            let mode = outputMode
            await outputManager.output(text: final_, mode: mode)
            finishSession()
        }
    }

    private func finishSession() {
        state = .idle
        recordingTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        Self.logger.info("セッションを完了")
    }

    private func startSilenceTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task {
            try? await Task.sleep(for: .seconds(Self.silenceTimeoutSeconds))
            guard !Task.isCancelled, state == .recording else { return }
            Self.logger.info("無音タイムアウト")
            audioService.stopCapture()
            await notificationService.sendErrorNotification(error: .silenceTimeout)
            finishSession()
        }
    }
}
