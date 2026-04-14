import Foundation
import Testing
@testable import Kuchibi

@Suite("ModelAvailabilityChecker")
struct ModelAvailabilityCheckerTests {
    // MARK: - Helpers

    /// 一時ディレクトリを作成し、テスト終了時に削除する scope を提供する。
    private static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelAvailabilityCheckerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - WhisperKit (常に true)

    @Test("WhisperKit: モデルファイルが存在しなくても常に true を返す")
    func whisperKitAlwaysAvailable() throws {
        let tempDir = try Self.makeTempDirectory()
        defer { Self.cleanup(tempDir) }

        let checker = ModelAvailabilityChecker(modelsDirectory: tempDir)

        for model in WhisperKitModel.allCases {
            #expect(checker.isAvailable(for: .whisperKit(model)))
        }
    }

    @Test("WhisperKit: 配置済みでも未配置でも true（FileManager 参照しない）")
    func whisperKitIgnoresFilesystem() throws {
        let tempDir = try Self.makeTempDirectory()
        defer { Self.cleanup(tempDir) }

        // 何らかのファイルを置いても置かなくても挙動は変わらない
        let dummyFile = tempDir.appendingPathComponent("anything.bin")
        try Data([0x00]).write(to: dummyFile)

        let checker = ModelAvailabilityChecker(modelsDirectory: tempDir)
        #expect(checker.isAvailable(for: .whisperKit(.base)))
        #expect(checker.isAvailable(for: .whisperKit(.largeV3Turbo)))
    }

    // MARK: - Kotoba (ファイル存在判定)

    @Test("Kotoba: expectedFileName が配置済みのとき true")
    func kotobaAvailableWhenFilePresent() throws {
        let tempDir = try Self.makeTempDirectory()
        defer { Self.cleanup(tempDir) }

        let model = KotobaWhisperBilingualModel.v1Q5
        let target = tempDir.appendingPathComponent(model.expectedFileName)
        try Data([0xDE, 0xAD, 0xBE, 0xEF]).write(to: target)

        let checker = ModelAvailabilityChecker(modelsDirectory: tempDir)
        #expect(checker.isAvailable(for: .kotobaWhisperBilingual(model)))
    }

    @Test("Kotoba: expectedFileName が未配置のとき false")
    func kotobaUnavailableWhenFileMissing() throws {
        let tempDir = try Self.makeTempDirectory()
        defer { Self.cleanup(tempDir) }

        let checker = ModelAvailabilityChecker(modelsDirectory: tempDir)
        for model in KotobaWhisperBilingualModel.allCases {
            #expect(!checker.isAvailable(for: .kotobaWhisperBilingual(model)))
        }
    }

    @Test("Kotoba: 異なる量子化ファイルは混同しない")
    func kotobaVariantIsolation() throws {
        let tempDir = try Self.makeTempDirectory()
        defer { Self.cleanup(tempDir) }

        // Q5 のみ配置
        let target = tempDir.appendingPathComponent(KotobaWhisperBilingualModel.v1Q5.expectedFileName)
        try Data([0x00]).write(to: target)

        let checker = ModelAvailabilityChecker(modelsDirectory: tempDir)
        #expect(checker.isAvailable(for: .kotobaWhisperBilingual(.v1Q5)))
        #expect(!checker.isAvailable(for: .kotobaWhisperBilingual(.v1Q8)))
    }

    // MARK: - modelPath / downloadPageURL

    @Test("modelPath: WhisperKit は nil、Kotoba は配置先 URL を返す")
    func modelPathResolution() throws {
        let tempDir = try Self.makeTempDirectory()
        defer { Self.cleanup(tempDir) }

        let checker = ModelAvailabilityChecker(modelsDirectory: tempDir)
        #expect(checker.modelPath(for: .whisperKit(.base)) == nil)

        let model = KotobaWhisperBilingualModel.v1Q5
        let path = checker.modelPath(for: .kotobaWhisperBilingual(model))
        #expect(path == tempDir.appendingPathComponent(model.expectedFileName))
    }

    @Test("downloadPageURL: WhisperKit は nil、Kotoba は HuggingFace URL")
    func downloadPageURLResolution() throws {
        let tempDir = try Self.makeTempDirectory()
        defer { Self.cleanup(tempDir) }

        let checker = ModelAvailabilityChecker(modelsDirectory: tempDir)
        #expect(checker.downloadPageURL(for: .whisperKit(.base)) == nil)

        let model = KotobaWhisperBilingualModel.v1Q5
        #expect(checker.downloadPageURL(for: .kotobaWhisperBilingual(model)) == model.downloadPageURL)
    }
}
