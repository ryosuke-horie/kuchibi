import ApplicationServices
import os
import SettingsAccess
import SwiftUI

/// アプリ全体のコントローラーを保持するコーディネーター
/// SwiftUI の App struct 再生成に影響されないよう @StateObject で管理する
@MainActor
final class AppCoordinator: ObservableObject {
    let sessionManager: SessionManagerImpl
    let appSettings: AppSettings
    private let hotKeyController: HotKeyControllerImpl
    private let escapeKeyMonitor: EscapeKeyMonitorImpl
    private let feedbackBarController: FeedbackBarWindowController

    init() {
        let settings = AppSettings()
        self.appSettings = settings

        // サービス構築
        let audioService = AudioCaptureServiceImpl()
        // Task 2.1: `settings.speechEngine` を起動時の初期エンジンとして採用する。
        // 旧 `setting.modelName` からの migration は `AppSettings.init` 内で実施済み。
        let initialEngine: SpeechEngine = settings.speechEngine
        let clipboardService = ClipboardServiceImpl()
        let outputManager = OutputManagerImpl(clipboardService: clipboardService)
        let notificationService = NotificationServiceImpl()

        // Task 5.1: adapter factory で engine kind ごとに実装を切り替える。
        // Task 5.3: AppSettings / NotificationService を渡して rollback + 通知を有効化。
        // sessionStateProvider は SessionManager 生成後に参照するため、box 経由の遅延評価で解決する。
        let sessionManagerBox = SessionManagerBox()
        let speechService = SpeechRecognitionServiceImpl(
            adapterFactory: { engine in
                switch engine.kind {
                case .whisperKit:
                    return WhisperKitAdapter()
                case .kotobaWhisperBilingual:
                    return WhisperCppAdapter()
                }
            },
            initialEngine: initialEngine,
            appSettings: settings,
            notificationService: notificationService,
            sessionStateProvider: { [sessionManagerBox] in
                sessionManagerBox.manager?.state ?? .idle
            }
        )

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
                Logger(subsystem: "com.kuchibi.app", category: "App")
                    .warning("アクセシビリティ権限が未付与: システム設定で許可が必要です")
            }
        }

        // モデルの非同期読み込み（Task 2.1: `settings.speechEngine` を採用）
        Task {
            do {
                try await speechService.loadInitialEngine(settings.speechEngine, language: "ja")
            } catch {
                await notificationService.sendErrorNotification(error: error as? KuchibiError ?? .modelLoadFailed(underlying: error))
            }
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
            SettingsView(appSettings: coordinator.appSettings)
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
