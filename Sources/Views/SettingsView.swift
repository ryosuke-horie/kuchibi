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
        .frame(width: 400, height: 250)
    }
}

// MARK: - 一般タブ

private struct GeneralSettingsTab: View {
    @ObservedObject var appSettings: AppSettings
    @Binding var launchAtLogin: Bool

    var body: some View {
        Form {
            Picker("出力モード", selection: $appSettings.outputMode) {
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
            LabeledContent("モデル") {
                Text(appSettings.modelName)
                    .foregroundStyle(.secondary)
            }

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
