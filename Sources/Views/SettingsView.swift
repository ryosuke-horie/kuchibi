import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appSettings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabView {
            GeneralSettingsTab(appSettings: appSettings, launchAtLogin: $launchAtLogin)
                .tabItem { Label("一般", systemImage: "gear") }

            RecognitionSettingsTab(appSettings: appSettings)
                .tabItem { Label("音声認識", systemImage: "waveform") }
        }
        .frame(width: 400, height: 420)
    }
}

// MARK: - 一般タブ

private struct GeneralSettingsTab: View {
    @ObservedObject var appSettings: AppSettings
    @Binding var launchAtLogin: Bool

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

    var body: some View {
        Form {
            Picker("モデル", selection: $appSettings.model) {
                ForEach(WhisperModel.allCases) { model in
                    Text("\(model.displayName) — \(model.sizeDescription)")
                        .tag(model)
                }
            }

            Text("モデル変更はアプリ再起動後に反映されます")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("無音タイムアウト") {
                HStack {
                    TextField(
                        "秒",
                        value: $appSettings.silenceTimeout,
                        format: .number
                    )
                    .frame(width: 60)
                    Text("秒")
                }
            }

            Divider()

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
}
