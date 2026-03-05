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
        #expect(settings.model == AppSettings.defaultModel)
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
        settings.model = .small
        settings.updateInterval = 1.0
        settings.bufferSize = 2048

        #expect(defaults.string(forKey: "setting.outputMode") == "directInput")
        #expect(defaults.double(forKey: "setting.silenceTimeout") == 60)
        #expect(defaults.string(forKey: "setting.modelName") == "small")
        #expect(defaults.double(forKey: "setting.updateInterval") == 1.0)
        #expect(defaults.integer(forKey: "setting.bufferSize") == 2048)
    }

    @Test("デフォルトの出力モードがautoInputである")
    @MainActor
    func defaultOutputModeIsAutoInput() {
        #expect(AppSettings.defaultOutputMode == .autoInput)

        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.outputMode == .autoInput)
    }

    @Test("保存済みの値がinitで復元される")
    @MainActor
    func restoresFromUserDefaults() {
        let defaults = createCleanDefaults()

        // 値を事前に保存
        defaults.set("directInput", forKey: "setting.outputMode")
        defaults.set(45.0, forKey: "setting.silenceTimeout")
        defaults.set("small", forKey: "setting.modelName")
        defaults.set(0.8, forKey: "setting.updateInterval")
        defaults.set(512, forKey: "setting.bufferSize")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.outputMode == .directInput)
        #expect(settings.silenceTimeout == 45.0)
        #expect(settings.model == .small)
        #expect(settings.updateInterval == 0.8)
        #expect(settings.bufferSize == 512)
    }

    @Test("既存の保存値clipboardが正しく復元される")
    @MainActor
    func restoresClipboardMode() {
        let defaults = createCleanDefaults()
        defaults.set("clipboard", forKey: "setting.outputMode")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.outputMode == .clipboard)
    }

    @Test("既存の保存値autoInputが正しく復元される")
    @MainActor
    func restoresAutoInputMode() {
        let defaults = createCleanDefaults()
        defaults.set("autoInput", forKey: "setting.outputMode")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.outputMode == .autoInput)
    }

    @Test("resetToDefaultsで全プロパティがデフォルト値に戻る")
    @MainActor
    func resetToDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        // デフォルトから変更
        settings.outputMode = .directInput
        settings.silenceTimeout = 60
        settings.model = .small
        settings.updateInterval = 1.0
        settings.bufferSize = 2048

        // リセット
        settings.resetToDefaults()

        #expect(settings.outputMode == AppSettings.defaultOutputMode)
        #expect(settings.silenceTimeout == AppSettings.defaultSilenceTimeout)
        #expect(settings.model == AppSettings.defaultModel)
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

    @Test("無効なモデル名がUserDefaultsに保存されている場合デフォルトにフォールバックする")
    @MainActor
    func fallbacksOnInvalidModelName() {
        let defaults = createCleanDefaults()
        defaults.set("moonshine-small-ja", forKey: "setting.modelName")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.model == AppSettings.defaultModel)
    }

    @Test("ハイフン付きモデル名が正しく復元される")
    @MainActor
    func restoresHyphenatedModelName() {
        let defaults = createCleanDefaults()
        defaults.set("large-v2", forKey: "setting.modelName")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.model == .largeV2)
    }

    // MARK: - 前処理設定テスト

    @Test("前処理設定のデフォルト値で初期化される")
    @MainActor
    func preprocessingInitWithDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        #expect(settings.noiseSuppressionEnabled == AppSettings.defaultNoiseSuppressionEnabled)
        #expect(settings.vadEnabled == AppSettings.defaultVadEnabled)
        #expect(settings.vadThreshold == AppSettings.defaultVadThreshold)
    }

    @Test("前処理設定がUserDefaultsに永続化される")
    @MainActor
    func preprocessingPersistsToUserDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.noiseSuppressionEnabled = false
        settings.vadEnabled = false
        settings.vadThreshold = 0.05

        #expect(defaults.bool(forKey: "setting.noiseSuppressionEnabled") == false)
        #expect(defaults.bool(forKey: "setting.vadEnabled") == false)
        #expect(defaults.float(forKey: "setting.vadThreshold") == 0.05)
    }

    @Test("前処理設定がinitで復元される")
    @MainActor
    func preprocessingRestoresFromUserDefaults() {
        let defaults = createCleanDefaults()

        defaults.set(false, forKey: "setting.noiseSuppressionEnabled")
        defaults.set(false, forKey: "setting.vadEnabled")
        defaults.set(Float(0.08), forKey: "setting.vadThreshold")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.noiseSuppressionEnabled == false)
        #expect(settings.vadEnabled == false)
        #expect(settings.vadThreshold == 0.08)
    }

    @Test("resetToDefaultsで前処理設定もデフォルト値に戻る")
    @MainActor
    func preprocessingResetToDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.noiseSuppressionEnabled = false
        settings.vadEnabled = false
        settings.vadThreshold = 0.05

        settings.resetToDefaults()

        #expect(settings.noiseSuppressionEnabled == AppSettings.defaultNoiseSuppressionEnabled)
        #expect(settings.vadEnabled == AppSettings.defaultVadEnabled)
        #expect(settings.vadThreshold == AppSettings.defaultVadThreshold)
    }

    @Test("vadThresholdの範囲外の値は拒否される")
    @MainActor
    func rejectsInvalidVadThreshold() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.vadThreshold = -0.1
        #expect(settings.vadThreshold == AppSettings.defaultVadThreshold)

        settings.vadThreshold = 1.5
        #expect(settings.vadThreshold == AppSettings.defaultVadThreshold)
    }

    // MARK: - テキスト後処理設定テスト

    @Test("テキスト後処理設定のデフォルト値で初期化される")
    @MainActor
    func textPostprocessingInitWithDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        #expect(settings.textPostprocessingEnabled == AppSettings.defaultTextPostprocessingEnabled)
    }

    @Test("テキスト後処理設定がUserDefaultsに永続化される")
    @MainActor
    func textPostprocessingPersistsToUserDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.textPostprocessingEnabled = false

        #expect(defaults.bool(forKey: "setting.textPostprocessingEnabled") == false)
    }

    @Test("テキスト後処理設定がinitで復元される")
    @MainActor
    func textPostprocessingRestoresFromUserDefaults() {
        let defaults = createCleanDefaults()
        defaults.set(false, forKey: "setting.textPostprocessingEnabled")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.textPostprocessingEnabled == false)
    }

    @Test("resetToDefaultsでテキスト後処理設定もデフォルト値に戻る")
    @MainActor
    func textPostprocessingResetToDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.textPostprocessingEnabled = false
        settings.resetToDefaults()

        #expect(settings.textPostprocessingEnabled == AppSettings.defaultTextPostprocessingEnabled)
    }

    // MARK: - モニタリング設定テスト

    @Test("モニタリング設定のデフォルト値で初期化される")
    @MainActor
    func monitoringInitWithDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        #expect(settings.monitoringEnabled == AppSettings.defaultMonitoringEnabled)
    }

    @Test("モニタリング設定がUserDefaultsに永続化される")
    @MainActor
    func monitoringPersistsToUserDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.monitoringEnabled = false

        #expect(defaults.bool(forKey: "setting.monitoringEnabled") == false)
    }

    @Test("モニタリング設定がinitで復元される")
    @MainActor
    func monitoringRestoresFromUserDefaults() {
        let defaults = createCleanDefaults()
        defaults.set(false, forKey: "setting.monitoringEnabled")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.monitoringEnabled == false)
    }

    @Test("resetToDefaultsでモニタリング設定もデフォルト値に戻る")
    @MainActor
    func monitoringResetToDefaults() {
        let defaults = createCleanDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.monitoringEnabled = false
        settings.resetToDefaults()

        #expect(settings.monitoringEnabled == AppSettings.defaultMonitoringEnabled)
    }
}
