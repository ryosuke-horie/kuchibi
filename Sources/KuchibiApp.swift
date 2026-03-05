import os
import SettingsAccess
import SwiftUI

@main
struct KuchibiApp: App {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var sessionManager: SessionManagerImpl
    private let hotKeyController: HotKeyControllerImpl
    private let feedbackBarController: FeedbackBarWindowController

    init() {
        let settings = AppSettings()
        _appSettings = StateObject(wrappedValue: settings)

        // サービス構築
        let audioService = AudioCaptureServiceImpl()
        let whisperAdapter = WhisperKitAdapter()
        let speechService = SpeechRecognitionServiceImpl(adapter: whisperAdapter)
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
        _sessionManager = StateObject(wrappedValue: sm)

        hotKeyController = HotKeyControllerImpl(onToggle: {
            Task { @MainActor in
                sm.toggleSession()
            }
        })

        feedbackBarController = FeedbackBarWindowController(sessionManager: sm)

        // ホットキー登録
        hotKeyController.register()

        // モデルの非同期読み込み
        Task {
            do {
                try await speechService.loadModel(modelName: settings.modelName)
            } catch {
                await notificationService.sendErrorNotification(error: error as? KuchibiError ?? .modelLoadFailed(underlying: error))
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("Kuchibi", systemImage: menuBarIcon) {
            MenuBarView(sessionManager: sessionManager)
        }

        Settings {
            SettingsView(appSettings: appSettings)
        }
    }

    private var menuBarIcon: String {
        switch sessionManager.state {
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
