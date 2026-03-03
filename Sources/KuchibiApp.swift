import ServiceManagement
import SwiftUI

@main
struct KuchibiApp: App {
    @StateObject private var sessionManager: SessionManagerImpl
    private let hotKeyController: HotKeyControllerImpl
    private let overlayController: OverlayWindowController

    init() {
        // サービス構築
        let audioService = AudioCaptureServiceImpl()
        let moonshineAdapter = MoonshineAdapterImpl()
        let speechService = SpeechRecognitionServiceImpl(adapter: moonshineAdapter)
        let clipboardService = ClipboardServiceImpl()
        let outputManager = OutputManagerImpl(clipboardService: clipboardService)
        let notificationService = NotificationServiceImpl()

        let sm = SessionManagerImpl(
            audioService: audioService,
            speechService: speechService,
            outputManager: outputManager,
            notificationService: notificationService
        )
        _sessionManager = StateObject(wrappedValue: sm)

        hotKeyController = HotKeyControllerImpl(onToggle: { [weak sm] in
            Task { @MainActor in
                sm?.toggleSession()
            }
        })

        overlayController = OverlayWindowController(sessionManager: sm)

        // ホットキー登録
        hotKeyController.register()

        // モデルの非同期読み込み
        Task {
            do {
                try await speechService.loadModel()
            } catch {
                await notificationService.sendErrorNotification(error: error as? KuchibiError ?? .modelLoadFailed(underlying: error))
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("Kuchibi", systemImage: menuBarIcon) {
            MenuBarView(sessionManager: sessionManager)
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
    @State private var launchAtLogin = false

    var body: some View {
        VStack {
            Text(statusText)
                .font(.headline)

            Divider()

            Picker("出力モード", selection: $sessionManager.outputMode) {
                Text("クリップボード").tag(OutputMode.clipboard)
                Text("直接入力").tag(OutputMode.directInput)
            }

            Divider()

            Toggle("ログイン時に起動", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }

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

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !enabled
        }
    }
}
