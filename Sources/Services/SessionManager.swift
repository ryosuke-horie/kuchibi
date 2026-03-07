import AppKit
import AudioToolbox
import AVFoundation
import os

private enum SystemSound {
    static let sessionStart: SystemSoundID = 1057  // Tink 相当
    static let sessionEnd: SystemSoundID = SystemSoundID(kSystemSoundID_UserPreferredAlert)
}

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
    private let monitoring: SessionMonitoring
    private let micAuthorizationStatus: () -> AVAuthorizationStatus
    private let accessibilityTrusted: () -> Bool

    private var recordingTask: Task<Void, Never>?
    private var accumulatedLines: [String] = []

    init(
        audioService: AudioCapturing,
        speechService: SpeechRecognizing,
        outputManager: OutputManaging,
        notificationService: NotificationServicing,
        appSettings: AppSettings,
        preprocessor: AudioPreprocessing = AudioPreprocessorImpl(),
        textPostprocessor: TextPostprocessing = TextPostprocessorImpl(),
        monitoring: SessionMonitoring = SessionMonitoringServiceImpl(),
        micAuthorizationStatus: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
        accessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.audioService = audioService
        self.speechService = speechService
        self.outputManager = outputManager
        self.notificationService = notificationService
        self.appSettings = appSettings
        self.preprocessor = preprocessor
        self.textPostprocessor = textPostprocessor
        self.monitoring = monitoring
        self.micAuthorizationStatus = micAuthorizationStatus
        self.accessibilityTrusted = accessibilityTrusted
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

        // マイク権限チェック
        let authStatus = micAuthorizationStatus()
        switch authStatus {
        case .denied:
            Self.logger.warning("マイク権限が拒否されています")
            Task {
                await notificationService.sendErrorNotification(error: .microphonePermissionDenied)
            }
            return
        case .restricted:
            Self.logger.warning("マイク権限が制限されています（管理者ポリシーによる制限）")
            Task {
                await notificationService.sendErrorNotification(error: .microphonePermissionDenied)
            }
            return
        case .notDetermined:
            Self.logger.info("マイク権限が未決定のため権限リクエストを行います")
            state = .processing  // 二重呼び出し防止
            Task {
                let granted = await audioService.requestMicrophonePermission()
                state = .idle
                if granted {
                    Self.logger.info("マイク権限が許可されました。セッションを開始します")
                    startSession()
                } else {
                    Self.logger.warning("マイク権限が拒否されました")
                    await notificationService.sendErrorNotification(error: .microphonePermissionDenied)
                }
            }
            return
        case .authorized:
            break
        @unknown default:
            Self.logger.warning("未知のマイク権限ステータス (\(authStatus.rawValue))。安全のため処理を中断します")
            Task {
                await notificationService.sendErrorNotification(error: .microphonePermissionDenied)
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
        if appSettings.sessionSoundEnabled {
            AudioServicesPlaySystemSound(SystemSound.sessionStart)
        }
        partialText = ""
        accumulatedLines = []
        if appSettings.monitoringEnabled {
            monitoring.sessionStarted()
        }
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
                await finishSession()
            }
        }
    }

    func stopSession() {
        guard state == .recording else {
            Self.logger.warning("セッション停止が無視された: 現在の状態=\(String(describing: self.state))")
            return
        }

        state = .processing
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
        case .lineCompleted(let final_):
            if appSettings.monitoringEnabled {
                monitoring.textCompleted(text: final_)
            }
            let outputText = appSettings.textPostprocessingEnabled
                ? textPostprocessor.process(final_)
                : final_
            accumulatedLines.append(outputText)
            partialText = ""
        }
    }

    private func finishSession(error: KuchibiError? = nil) async {
        if audioService.isCapturing {
            audioService.stopCapture()
        }
        if !accumulatedLines.isEmpty {
            let joinedText = accumulatedLines.joined(separator: "\n")
            let mode = appSettings.outputMode
            await outputManager.output(text: joinedText, mode: mode)
            accumulatedLines = []
        }
        if appSettings.monitoringEnabled {
            if let error {
                monitoring.sessionFailed(error: error)
            } else {
                monitoring.sessionEnded()
            }
        }
        if error == nil && appSettings.sessionSoundEnabled {
            AudioServicesPlaySystemSound(SystemSound.sessionEnd)
        }
        state = .idle
        audioLevel = 0.0
        recordingTask = nil
        Self.logger.info("セッションを完了")
    }
}
