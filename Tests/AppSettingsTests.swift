import Foundation
import Testing
@testable import Kuchibi

@Suite("AppSettings")
struct AppSettingsTests {
    // テストごとにUserDefaultsをクリーンアップするため専用suiteを使用
    private static let testSuiteName = "com.kuchibi.test.AppSettings"

    private func createCleanDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.testSuiteName)!
        defaults.removePersistentDomain(forName: Self.testSuiteName)
        return defaults
    }

    @Test("デフォルト値で初期化される")
    @MainActor
    func initWithDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        #expect(settings.outputMode == AppSettings.defaultOutputMode)
        #expect(settings.silenceTimeout == AppSettings.defaultSilenceTimeout)
        #expect(settings.modelName == AppSettings.defaultModelName)
        #expect(settings.updateInterval == AppSettings.defaultUpdateInterval)
        #expect(settings.bufferSize == AppSettings.defaultBufferSize)
    }

    @Test("プロパティ変更がUserDefaultsに永続化される")
    @MainActor
    func persistsToUserDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.outputMode = .directInput
        settings.silenceTimeout = 60
        settings.modelName = "moonshine-small-ja"
        settings.updateInterval = 1.0
        settings.bufferSize = 2048

        #expect(defaults.string(forKey: "setting.outputMode") == "directInput")
        #expect(defaults.double(forKey: "setting.silenceTimeout") == 60)
        #expect(defaults.string(forKey: "setting.modelName") == "moonshine-small-ja")
        #expect(defaults.double(forKey: "setting.updateInterval") == 1.0)
        #expect(defaults.integer(forKey: "setting.bufferSize") == 2048)
    }

    @Test("保存済みの値がinitで復元される")
    @MainActor
    func restoresFromUserDefaults() {
        let defaults = createCleanDefaults()

        // 値を事前に保存
        defaults.set("directInput", forKey: "setting.outputMode")
        defaults.set(45.0, forKey: "setting.silenceTimeout")
        defaults.set("moonshine-small-ja", forKey: "setting.modelName")
        defaults.set(0.8, forKey: "setting.updateInterval")
        defaults.set(512, forKey: "setting.bufferSize")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.outputMode == .directInput)
        #expect(settings.silenceTimeout == 45.0)
        #expect(settings.modelName == "moonshine-small-ja")
        #expect(settings.updateInterval == 0.8)
        #expect(settings.bufferSize == 512)
    }

    @Test("resetToDefaultsで全プロパティがデフォルト値に戻る")
    @MainActor
    func resetToDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        // デフォルトから変更
        settings.outputMode = .directInput
        settings.silenceTimeout = 60
        settings.modelName = "moonshine-small-ja"
        settings.updateInterval = 1.0
        settings.bufferSize = 2048

        // リセット
        settings.resetToDefaults()

        #expect(settings.outputMode == AppSettings.defaultOutputMode)
        #expect(settings.silenceTimeout == AppSettings.defaultSilenceTimeout)
        #expect(settings.modelName == AppSettings.defaultModelName)
        #expect(settings.updateInterval == AppSettings.defaultUpdateInterval)
        #expect(settings.bufferSize == AppSettings.defaultBufferSize)
    }

    @Test("resetToDefaults後にUserDefaultsもクリアされる")
    @MainActor
    func resetClearsUserDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.outputMode = .directInput
        settings.silenceTimeout = 60

        settings.resetToDefaults()

        // UserDefaultsからも削除されている
        #expect(defaults.object(forKey: "setting.outputMode") == nil)
        #expect(defaults.object(forKey: "setting.silenceTimeout") == nil)
        #expect(defaults.object(forKey: "setting.modelName") == nil)
        #expect(defaults.object(forKey: "setting.updateInterval") == nil)
        #expect(defaults.object(forKey: "setting.bufferSize") == nil)
    }

    @Test("不正な負数のsilenceTimeoutは拒否される")
    @MainActor
    func rejectsNegativeSilenceTimeout() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.silenceTimeout = -5
        #expect(settings.silenceTimeout == AppSettings.defaultSilenceTimeout)
    }

    @Test("不正な負数のupdateIntervalは拒否される")
    @MainActor
    func rejectsNegativeUpdateInterval() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.updateInterval = -1
        #expect(settings.updateInterval == AppSettings.defaultUpdateInterval)
    }

    @Test("不正なゼロ以下のbufferSizeは拒否される")
    @MainActor
    func rejectsInvalidBufferSize() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.bufferSize = 0
        #expect(settings.bufferSize == AppSettings.defaultBufferSize)
    }
}
