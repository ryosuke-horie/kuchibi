import ApplicationServices
import Combine
import os
import SettingsAccess
import SwiftUI

/// アプリ全体のコントローラーを保持するコーディネーター
/// SwiftUI の App struct 再生成に影響されないよう @StateObject で管理する
@MainActor
final class AppCoordinator: ObservableObject {
    let sessionManager: SessionManagerImpl
    let appSettings: AppSettings
    let speechService: SpeechRecognitionServiceImpl

    /// モデルファイル配置状況のチェッカー。
    /// `SettingsView` でモデル未配置時の DL ガイド表示に参照される想定。
    @Published private(set) var modelAvailability: ModelAvailabilityChecker

    /// 起動経路（バンドルパス）の検査結果保持。
    /// `/Applications/Kuchibi.app` 以外から起動されていないかを UI に公開する。
    @Published private(set) var launchPathValidator: LaunchPathValidator

    /// マイク・アクセシビリティ権限の観測状態。
    /// `NSApplication.didBecomeActiveNotification` 購読で自動更新される。
    @Published private(set) var permissionObserver: PermissionStateObserver

    let notificationService: NotificationServicing
    private let hotKeyController: HotKeyControllerImpl
    private let escapeKeyMonitor: EscapeKeyMonitorImpl
    private let feedbackBarController: FeedbackBarWindowController
    private let engineSwitchCoordinator: EngineSwitchCoordinator

    init() {
        let logger = Logger(subsystem: "com.kuchibi.app", category: "AppCoordinator")

        let settings = AppSettings()
        self.appSettings = settings

        // 新コンポーネント DI（Req 5.1, 6.1, 6.4）
        let modelAvailability = ModelAvailabilityChecker()
        let launchPathValidator = LaunchPathValidator()
        let permissionObserver = PermissionStateObserver()
        self.modelAvailability = modelAvailability
        self.launchPathValidator = launchPathValidator
        self.permissionObserver = permissionObserver

        // 起動経路の検査結果を info ログに出す（Req 5.1）
        logger.info("Launch path approved: \(launchPathValidator.isApproved, privacy: .public) (path: \(launchPathValidator.currentPath, privacy: .public))")

        // サービス構築
        let audioService = AudioCaptureServiceImpl()
        // Task 2.1: `settings.speechEngine` を起動時の初期エンジンとして採用する。
        // 旧 `setting.modelName` からの migration は `AppSettings.init` 内で実施済み。
        let initialEngine: SpeechEngine = settings.speechEngine
        let clipboardService = ClipboardServiceImpl()
        let outputManager = OutputManagerImpl(clipboardService: clipboardService)
        let notificationService = NotificationServiceImpl()
        self.notificationService = notificationService

        // Task 5.1: adapter factory で engine kind ごとに実装を切り替える。
        // Task 5.3: AppSettings / NotificationService を渡して rollback + 通知を有効化。
        // sessionStateProvider は SessionManager 生成後に参照するため、box 経由の遅延評価で解決する。
        let sessionManagerBox = SessionManagerBox()
        let speechService = SpeechRecognitionServiceImpl(
            adapterFactory: { [notificationService] engine in
                switch engine.kind {
                case .whisperKit:
                    return WhisperKitAdapter(notificationService: notificationService)
                case .kotobaWhisperBilingual:
                    return WhisperCppAdapter(notificationService: notificationService)
                }
            },
            initialEngine: initialEngine,
            appSettings: settings,
            notificationService: notificationService,
            sessionStateProvider: { [sessionManagerBox] in
                sessionManagerBox.manager?.state ?? .idle
            }
        )
        self.speechService = speechService

        let sm = SessionManagerImpl(
            audioService: audioService,
            speechService: speechService,
            outputManager: outputManager,
            notificationService: notificationService,
            appSettings: settings
        )
        sessionManagerBox.manager = sm
        self.sessionManager = sm

        hotKeyController = HotKeyControllerImpl(onToggle: {
            Task { @MainActor in
                sm.toggleSession()
            }
        })

        escapeKeyMonitor = EscapeKeyMonitorImpl()

        feedbackBarController = FeedbackBarWindowController(sessionManager: sm)

        // Task 6.1: deferred switchEngine 配線
        // `AppSettings.$speechEngine` と `SessionManagerImpl.$state` を合成し、
        // idle の瞬間に最新要求を `SpeechRecognitionServiceImpl.switchEngine` に渡す。
        let engineRequestPublisher = settings.$speechEngine
            .dropFirst()  // 初期値は起動時ロードで処理済みなので無視
            .eraseToAnyPublisher()
        let engineSwitchCoordinator = EngineSwitchCoordinator(
            engineRequestPublisher: engineRequestPublisher,
            sessionStatePublisher: sm.statePublisher,
            sessionStateProvider: { [weak sm] in sm?.state ?? .idle },
            switcher: speechService,
            modelAvailability: modelAvailability,
            language: "ja"
        )
        self.engineSwitchCoordinator = engineSwitchCoordinator
        engineSwitchCoordinator.start()

        // ホットキー登録
        hotKeyController.register()

        // ESCキー監視開始
        escapeKeyMonitor.startMonitoring {
            Task { @MainActor in
                sm.cancelSession()
            }
        }

        // アクセシビリティ権限の確認・プロンプト
        if settings.outputMode != .clipboard {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            if !trusted {
                logger.warning("アクセシビリティ権限が未付与: システム設定で許可が必要です")
            }
        }

        // モデル初期ロード（Req 6.4）
        // モデル未配置時は `loadInitialEngine` をスキップし、SettingsView で DL ガイドが出る状態のまま待機する。
        Task { [weak self] in
            await self?.performInitialLoad()
        }
    }

    /// 起動時のエンジン初期ロード。
    /// - 選択エンジンのモデルが未配置なら読み込みをスキップする（SettingsView で DL ガイドを提示）。
    /// - 読み込み成功時は `speechService.isModelLoaded == true` となりセッション開始が許可される。
    /// - 読み込み失敗時は `NotificationService` でエラー通知を送る。
    private func performInitialLoad() async {
        let logger = Logger(subsystem: "com.kuchibi.app", category: "AppCoordinator")
        let engine = appSettings.speechEngine

        guard modelAvailability.isAvailable(for: engine) else {
            logger.warning(
                "Model not available for \(engine.modelIdentifier, privacy: .public); skipping initial load. SettingsView should guide the user to place model files."
            )
            return
        }

        do {
            try await speechService.loadInitialEngine(engine, language: "ja")
        } catch {
            logger.error("Initial engine load failed: \(error.localizedDescription, privacy: .public)")
            let wrapped = (error as? KuchibiError) ?? .modelLoadFailed(underlying: error)
            await notificationService.sendErrorNotification(error: wrapped)
        }
    }
}

/// `SpeechRecognitionServiceImpl` の `sessionStateProvider` が
/// `SessionManagerImpl` を遅延参照するための holder。
/// init 内では sm 生成前に closure を渡すため、box 経由で後から注入する。
@MainActor
private final class SessionManagerBox {
    weak var manager: SessionManagerImpl?
}

@main
struct KuchibiApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("Kuchibi", systemImage: menuBarIcon) {
            MenuBarView(sessionManager: coordinator.sessionManager)
        }

        Settings {
            SettingsView(
                appSettings: coordinator.appSettings,
                speechService: coordinator.speechService,
                permissionObserver: coordinator.permissionObserver,
                launchPathValidator: coordinator.launchPathValidator,
                modelAvailability: coordinator.modelAvailability
            )
        }
    }

    private var menuBarIcon: String {
        switch coordinator.sessionManager.state {
        case .idle: "mic"
        case .recording: "mic.fill"
        case .processing: "mic.badge.ellipsis"
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var sessionManager: SessionManagerImpl

    var body: some View {
        VStack {
            Text(statusText)
                .font(.headline)

            Divider()

            SettingsLink(
                label: { Text("設定...") },
                preAction: { NSApp.activate(ignoringOtherApps: true) },
                postAction: { }
            )

            Divider()

            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var statusText: String {
        switch sessionManager.state {
        case .idle: "待機中"
        case .recording: "録音中..."
        case .processing: "認識処理中..."
        }
    }
}
