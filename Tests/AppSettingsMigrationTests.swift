import Foundation
import Testing
@testable import Kuchibi

/// `AppSettings` の `setting.modelName` (旧キー) → `setting.speechEngine` (新キー) migration テスト群。
///
/// Req 1.3「選択の永続化とデフォルト」の acceptance criteria 3 に対応する 4 ケース:
/// (a) 旧キーのみ → 変換、(b) 新キーのみ → 保持、(c) 両方 → 新キー採用、(d) どちらも無し → デフォルト。
@Suite("AppSettingsMigration")
struct AppSettingsMigrationTests {
    /// 各テストごとに UUID で suite を分離し、UserDefaults の状態が他テストに漏れないようにする。
    private func freshDefaults() -> UserDefaults {
        let suiteName = "com.kuchibi.test.AppSettingsMigration." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func encodeEngine(_ engine: SpeechEngine) -> String {
        let data = try! JSONEncoder().encode(engine)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - (a) 旧キーのみ存在 → SpeechEngine.whisperKit へ migration

    @Test("旧キー modelName=small のみ → SpeechEngine.whisperKit(.small) へ migration し旧キーは削除")
    @MainActor
    func migrateFromLegacyModelNameOnly_small() {
        let defaults = freshDefaults()
        defaults.set("small", forKey: "setting.modelName")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.speechEngine == .whisperKit(.small))
        // 旧キーは削除されている
        #expect(defaults.string(forKey: "setting.modelName") == nil)
        // 新キーが書き込まれている
        #expect(defaults.string(forKey: "setting.speechEngine") != nil)
    }

    @Test("旧キー modelName=large-v3 → 後継 .largeV3Turbo に集約 migration")
    @MainActor
    func migrateLargeV3MapsToTurbo() {
        let defaults = freshDefaults()
        defaults.set("large-v3", forKey: "setting.modelName")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.speechEngine == .whisperKit(.largeV3Turbo))
        #expect(defaults.string(forKey: "setting.modelName") == nil)
    }

    // MARK: - (b) 新キーのみ存在 → そのまま保持

    @Test("新キー setting.speechEngine のみ存在 → そのまま保持")
    @MainActor
    func newKeyOnlyPersists() {
        let defaults = freshDefaults()
        let engine: SpeechEngine = .whisperKit(.medium)
        defaults.set(encodeEngine(engine), forKey: "setting.speechEngine")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.speechEngine == .whisperKit(.medium))
    }

    // MARK: - (c) 新旧両方存在 → 新キー採用、旧キーは触らない

    @Test("新旧両方存在 → 新キーを採用し、旧キーは migration を発火させない")
    @MainActor
    func bothKeysNewWins() {
        let defaults = freshDefaults()
        defaults.set("tiny", forKey: "setting.modelName")
        let engine: SpeechEngine = .whisperKit(.base)
        defaults.set(encodeEngine(engine), forKey: "setting.speechEngine")

        let settings = AppSettings(defaults: defaults)

        // 新キー優先
        #expect(settings.speechEngine == .whisperKit(.base))
        // migration 経路を通っていないので旧キーは保持されたまま（design の Migration Strategy フローチャート通り）
        #expect(defaults.string(forKey: "setting.modelName") == "tiny")
    }

    // MARK: - (d) どちらも無し → デフォルト（largeV3Turbo）

    @Test("どちらのキーも無し → デフォルト SpeechEngine.whisperKit(.largeV3Turbo)")
    @MainActor
    func noKeysFallsBackToDefault() {
        let defaults = freshDefaults()

        let settings = AppSettings(defaults: defaults)

        #expect(settings.speechEngine == .whisperKit(.largeV3Turbo))
        #expect(settings.speechEngine == AppSettings.defaultSpeechEngine)
    }

    // MARK: - 補助テスト（migration ヘルパーの単体検証）

    @Test("WhisperKitModel(fromLegacy:) は既知の旧 rawValue を全て解決する")
    func legacyMappingCoversKnownValues() {
        #expect(WhisperKitModel(fromLegacy: "tiny") == .tiny)
        #expect(WhisperKitModel(fromLegacy: "base") == .base)
        #expect(WhisperKitModel(fromLegacy: "small") == .small)
        #expect(WhisperKitModel(fromLegacy: "medium") == .medium)
        #expect(WhisperKitModel(fromLegacy: "large-v2") == .largeV3Turbo)
        #expect(WhisperKitModel(fromLegacy: "large-v3") == .largeV3Turbo)
        #expect(WhisperKitModel(fromLegacy: "unknown-model") == nil)
    }

    // MARK: - 永続化と再ロードのラウンドトリップ

    @Test("speechEngine への代入が UserDefaults に JSON として永続化され再ロード時に復元される")
    @MainActor
    func writeRoundTripsThroughUserDefaults() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.speechEngine = .kotobaWhisperBilingual(.v1Q5)

        // 新キーに JSON が書き込まれている
        let json = defaults.string(forKey: "setting.speechEngine")
        #expect(json != nil)

        // 同じ defaults で別 instance を作ると同じ値が復元される
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.speechEngine == .kotobaWhisperBilingual(.v1Q5))
    }

    @Test("resetToDefaults で speechEngine がデフォルトに戻り、setting.speechEngine キーも削除される")
    @MainActor
    func resetClearsSpeechEngineKey() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.speechEngine = .whisperKit(.tiny)
        #expect(defaults.string(forKey: "setting.speechEngine") != nil)

        settings.resetToDefaults()

        #expect(settings.speechEngine == AppSettings.defaultSpeechEngine)
        #expect(defaults.object(forKey: "setting.speechEngine") == nil)
    }
}
