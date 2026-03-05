import Testing
@testable import Kuchibi

@Suite("WhisperModel")
struct WhisperModelTests {
    @Test("rawValueがWhisperKitのモデル名と一致する")
    func rawValues() {
        #expect(WhisperModel.tiny.rawValue == "tiny")
        #expect(WhisperModel.base.rawValue == "base")
        #expect(WhisperModel.small.rawValue == "small")
        #expect(WhisperModel.medium.rawValue == "medium")
        #expect(WhisperModel.largeV2.rawValue == "large-v2")
        #expect(WhisperModel.largeV3.rawValue == "large-v3")
    }

    @Test("全ケース数が期待通り")
    func caseCount() {
        #expect(WhisperModel.allCases.count == 6)
    }

    @Test("defaultModelが有効なWhisperModelである")
    @MainActor
    func defaultModelIsValid() {
        #expect(WhisperModel.allCases.contains(AppSettings.defaultModel))
    }

    @Test("displayNameが各モデルで定義されている")
    func displayNames() {
        for model in WhisperModel.allCases {
            #expect(!model.displayName.isEmpty)
        }
    }

    @Test("無効なrawValueからの初期化はnilを返す")
    func invalidRawValue() {
        #expect(WhisperModel(rawValue: "invalid-model") == nil)
        #expect(WhisperModel(rawValue: "moonshine-small-ja") == nil)
        #expect(WhisperModel(rawValue: "") == nil)
    }
}
