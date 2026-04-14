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
        let whisperAdapter = WhisperKitAdapter()
        // Task 2.1 で `settings.speechEngine` を参照するよう差し替える。
        // 本 task（1.3）ではビルドを通すため WhisperKit .base をハードコードする。
        let initialEngine: SpeechEngine = .whisperKit(.base)
        let speechService = SpeechRecognitionServiceImpl(
            adapter: whisperAdapter,
            initialEngine: initialEngine
        )
        let clipboardService = ClipboardServiceImpl()
        let outputManager = OutputManagerImpl(clipboardService: clipboardService)
        let notificationService = NotificationServiceImpl()

        let sm = SessionManagerImpl(
            audioService: audioService,
            speechService: speechService,
            outputManager: outputManager,
            notificationService: notificationService,
            appSettings: settings
        )
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

        // モデルの非同期読み込み
        // Task 2.1 で `settings.speechEngine` を参照するよう差し替える予定。
        Task {
            do {
                try await speechService.loadInitialEngine(initialEngine, language: "ja")
            } catch {
                await notificationService.sendErrorNotification(error: error as? KuchibiError ?? .modelLoadFailed(underlying: error))
            }
        }
    }
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
