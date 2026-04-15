import Foundation
@testable import Kuchibi

/// `ModelAvailabilityChecking` のテスト用モック。
///
/// `availabilityOverride` / `pathOverride` / `downloadURLOverride` を任意で差し替え可能。
/// 何も設定しない場合は WhisperKit は常に利用可能、Kotoba は常に利用不可と返す。
final class MockModelAvailabilityChecker: ModelAvailabilityChecking {
    /// `engine` ごとの `isAvailable` の返却値を上書きする。
    var availabilityOverride: [SpeechEngine: Bool] = [:]

    /// `engine` ごとの `modelPath` の返却値を上書きする。
    var pathOverride: [SpeechEngine: URL?] = [:]

    /// `engine` ごとの `downloadPageURL` の返却値を上書きする。
    var downloadURLOverride: [SpeechEngine: URL?] = [:]

    private(set) var isAvailableCallCount = 0
    private(set) var modelPathCallCount = 0
    private(set) var downloadPageURLCallCount = 0

    func isAvailable(for engine: SpeechEngine) -> Bool {
        isAvailableCallCount += 1
        if let override = availabilityOverride[engine] {
            return override
        }
        switch engine {
        case .whisperKit: return true
        case .kotobaWhisperBilingual: return false
        }
    }

    func modelPath(for engine: SpeechEngine) -> URL? {
        modelPathCallCount += 1
        if let override = pathOverride[engine] {
            return override
        }
        return nil
    }

    func downloadPageURL(for engine: SpeechEngine) -> URL? {
        downloadPageURLCallCount += 1
        if let override = downloadURLOverride[engine] {
            return override
        }
        switch engine {
        case .whisperKit: return nil
        case .kotobaWhisperBilingual(let model): return model.downloadPageURL
        }
    }
}
