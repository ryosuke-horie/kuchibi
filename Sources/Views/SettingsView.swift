import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var speechService: SpeechRecognitionServiceImpl
    @ObservedObject var permissionObserver: PermissionStateObserver
    let launchPathValidator: LaunchPathValidating
    let modelAvailability: ModelAvailabilityChecking

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabView {
            GeneralSettingsTab(appSettings: appSettings, launchAtLogin: $launchAtLogin)
                .tabItem { Label("一般", systemImage: "gear") }

            RecognitionSettingsTab(
                appSettings: appSettings,
                speechService: speechService,
                permissionObserver: permissionObserver,
                launchPathValidator: launchPathValidator,
                modelAvailability: modelAvailability
            )
            .tabItem { Label("音声認識", systemImage: "waveform") }
        }
        .frame(width: 460, height: 620)
    }
}

// MARK: - 一般タブ

private struct GeneralSettingsTab: View {
    @ObservedObject var appSettings: AppSettings
    @Binding var launchAtLogin: Bool
    @State private var diagResult: String?

    var body: some View {
        Form {
            Picker("出力モード", selection: $appSettings.outputMode) {
                Text("自動入力（推奨）").tag(OutputMode.autoInput)
                Text("クリップボード").tag(OutputMode.clipboard)
                Text("直接入力").tag(OutputMode.directInput)
            }

            Toggle("ログイン時に起動", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }

            Divider()

            Section("入力診断") {
                Button("診断を実行") {
                    Task {
                        let service = ClipboardServiceImpl()
                        diagResult = await service.runDiagnostics()
                    }
                }
                Text("結果は ~/Desktop/kuchibi-diag.txt に保存されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
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

// MARK: - 音声認識タブ

private struct RecognitionSettingsTab: View {
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var speechService: SpeechRecognitionServiceImpl
    @ObservedObject var permissionObserver: PermissionStateObserver
    let launchPathValidator: LaunchPathValidating
    let modelAvailability: ModelAvailabilityChecking

    /// モデル配置チェックの再評価用トークン。
    /// `ModelAvailabilityChecker` は `ObservableObject` ではないため、
    /// 「配置を確認」ボタン押下で View を再評価させるためのローカル State。
    @State private var availabilityRefreshToken = 0

    var body: some View {
        Form {
            if !launchPathValidator.isApproved {
                launchPathWarningBanner
            }

            engineModelPickerSection

            kotobaDownloadGuideBannerIfNeeded

            permissionStatusSection

            Section("前処理") {
                Toggle("ノイズ抑制", isOn: $appSettings.noiseSuppressionEnabled)

                Toggle("音声アクティビティ検出 (VAD)", isOn: $appSettings.vadEnabled)

                LabeledContent("VAD 感度") {
                    HStack {
                        Slider(value: $appSettings.vadThreshold, in: 0.0...1.0, step: 0.001)
                        Text(String(format: "%.3f", appSettings.vadThreshold))
                            .monospacedDigit()
                            .frame(width: 45)
                    }
                }
                .disabled(!appSettings.vadEnabled)
            }

            Section("後処理") {
                Toggle("テキスト後処理", isOn: $appSettings.textPostprocessingEnabled)
            }

            Section("フィードバック") {
                Toggle("セッションサウンド", isOn: $appSettings.sessionSoundEnabled)
            }

            Section("モニタリング") {
                Toggle("セッションモニタリング", isOn: $appSettings.monitoringEnabled)
            }

            Divider()

            HStack {
                Spacer()
                Button("デフォルトに戻す") {
                    appSettings.resetToDefaults()
                }
            }
        }
        .padding()
    }

    // MARK: エンジン/モデル Picker セクション (Task 7.1)

    /// Picker 用の選択状態（エンジン種別）
    /// `appSettings.speechEngine.kind` と同期している computed binding。
    private var engineKindBinding: Binding<SpeechEngineKind> {
        Binding(
            get: { appSettings.speechEngine.kind },
            set: { newKind in
                // 既に同じ kind なら何もしない（モデル選択を壊さない）
                guard newKind != appSettings.speechEngine.kind else { return }
                switch newKind {
                case .whisperKit:
                    appSettings.speechEngine = .whisperKit(.largeV3Turbo)
                case .kotobaWhisperBilingual:
                    appSettings.speechEngine = .kotobaWhisperBilingual(.v1Q5)
                }
            }
        )
    }

    private var whisperKitModelBinding: Binding<WhisperKitModel> {
        Binding(
            get: {
                if case .whisperKit(let model) = appSettings.speechEngine { return model }
                return .largeV3Turbo
            },
            set: { newModel in
                appSettings.speechEngine = .whisperKit(newModel)
            }
        )
    }

    private var kotobaModelBinding: Binding<KotobaWhisperBilingualModel> {
        Binding(
            get: {
                if case .kotobaWhisperBilingual(let model) = appSettings.speechEngine { return model }
                return .v1Q5
            },
            set: { newModel in
                appSettings.speechEngine = .kotobaWhisperBilingual(newModel)
            }
        )
    }

    @ViewBuilder
    private var engineModelPickerSection: some View {
        Section("音声認識エンジン") {
            Picker("エンジン", selection: engineKindBinding) {
                ForEach(SpeechEngineKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            switch appSettings.speechEngine {
            case .whisperKit:
                Picker("モデル", selection: whisperKitModelBinding) {
                    ForEach(WhisperKitModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
            case .kotobaWhisperBilingual:
                Picker("モデル", selection: kotobaModelBinding) {
                    ForEach(KotobaWhisperBilingualModel.allCases) { model in
                        let available = isKotobaAvailable(model)
                        Text(model.displayName + (available ? "" : " (未配置)"))
                            .tag(model)
                    }
                }
            }

            // 現在状態表示 (Req 3.1, 3.2)
            LabeledContent("現在") {
                HStack(spacing: 6) {
                    if speechService.isSwitching {
                        ProgressView()
                            .controlSize(.small)
                        Text("切替中…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(speechService.currentEngine.engineDisplayName)
                            + Text(" / ")
                            + Text(speechService.currentEngine.modelDisplayName)
                    }
                }
                .font(.caption)
            }

            if let err = speechService.lastSwitchError {
                Text("切替エラー: \(err)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: Kotoba DL ガイド (Task 7.2)

    /// 現在選択中の engine で、Kotoba 系かつ未配置の場合にバナーを出す。
    @ViewBuilder
    private var kotobaDownloadGuideBannerIfNeeded: some View {
        if case .kotobaWhisperBilingual(let model) = appSettings.speechEngine,
           !isKotobaAvailable(model) {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("モデル未配置: \(model.expectedFileName)", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline.bold())

                    Text("配置先: ~/Library/Application Support/Kuchibi/models/")
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("HuggingFace で開く") {
                            if let url = modelAvailability.downloadPageURL(
                                for: .kotobaWhisperBilingual(model)
                            ) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Button("配置を確認") {
                            // ModelAvailabilityChecker は非 ObservableObject のため、
                            // View 側の state をインクリメントして body を再評価させる。
                            availabilityRefreshToken &+= 1
                            // 配置完了により利用可能になった場合、現在選択中の engine を
                            // speechService へ反映させる（EngineSwitchCoordinator は
                            // 未配置時に switchEngine を skip しているため、ここで再試行）。
                            let engine = appSettings.speechEngine
                            if modelAvailability.isAvailable(for: engine),
                               speechService.currentEngine != engine {
                                Task {
                                    try? await speechService.switchEngine(to: engine, language: "ja")
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// `availabilityRefreshToken` を参照することで、
    /// refresh ボタン押下時に body が再評価されるようにする。
    private func isKotobaAvailable(_ model: KotobaWhisperBilingualModel) -> Bool {
        _ = availabilityRefreshToken  // 依存性を body に伝播
        return modelAvailability.isAvailable(for: .kotobaWhisperBilingual(model))
    }

    // MARK: 起動経路警告バナー (Task 7.3)

    @ViewBuilder
    private var launchPathWarningBanner: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("承認されていない場所から起動しています")
                        .foregroundStyle(.red)
                        .bold()
                }
                DisclosureGroup("詳細") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("現在のパス:")
                            .font(.caption)
                        Text(launchPathValidator.currentPath)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Text("推奨: `make run` で /Applications/Kuchibi.app に再インストールしてください")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: 権限状態セクション (Task 7.4)

    @ViewBuilder
    private var permissionStatusSection: some View {
        Section("権限") {
            HStack {
                Image(
                    systemName: permissionObserver.microphoneGranted
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill"
                )
                .foregroundStyle(permissionObserver.microphoneGranted ? .green : .red)
                Text("マイク")
                Spacer()
                if !permissionObserver.microphoneGranted {
                    Button("システム設定を開く") {
                        if let url = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            HStack {
                Image(
                    systemName: permissionObserver.accessibilityTrusted
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill"
                )
                .foregroundStyle(permissionObserver.accessibilityTrusted ? .green : .red)
                Text("アクセシビリティ")
                Spacer()
                if !permissionObserver.accessibilityTrusted {
                    Button("権限を要求") {
                        let options = [
                            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true
                        ] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                    }
                }
            }
        }
    }
}
