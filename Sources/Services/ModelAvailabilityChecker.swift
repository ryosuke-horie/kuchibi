import Foundation
import os

/// 各 `SpeechEngine` のモデルファイル配置状況を判定する実装。
///
/// - WhisperKit 系は WhisperKit 自身がモデル DL を管理するため常に `true` を返す。
/// - Kotoba-Whisper Bilingual のようなユーザー手動配置型は
///   `~/Library/Application Support/Kuchibi/models/<expectedFileName>` の存在を確認する。
final class ModelAvailabilityChecker: ModelAvailabilityChecking {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "ModelAvailabilityChecker")

    private let fileManager: FileManager
    private let modelsDirectory: URL

    /// テスト容易性のため `FileManager` と モデル配置ディレクトリを DI 可能にする。
    /// - Parameters:
    ///   - fileManager: ファイル存在確認に使用する `FileManager`。デフォルトは `.default`。
    ///   - modelsDirectory: モデル配置ディレクトリ URL。
    ///     `nil` の場合、`fileManager` から
    ///     `~/Library/Application Support/Kuchibi/models/` を解決する。
    init(fileManager: FileManager = .default, modelsDirectory: URL? = nil) {
        self.fileManager = fileManager
        if let modelsDirectory {
            self.modelsDirectory = modelsDirectory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.modelsDirectory = appSupport.appendingPathComponent("Kuchibi/models", isDirectory: true)
        }
    }

    func isAvailable(for engine: SpeechEngine) -> Bool {
        switch engine {
        case .whisperKit:
            return true
        case .kotobaWhisperBilingual(let model):
            let path = modelsDirectory.appendingPathComponent(model.expectedFileName)
            let exists = fileManager.fileExists(atPath: path.path)
            if !exists {
                Self.logger.debug("Kotoba モデル未配置: \(path.path, privacy: .public)")
            }
            return exists
        }
    }

    func modelPath(for engine: SpeechEngine) -> URL? {
        switch engine {
        case .whisperKit:
            // WhisperKit は自前で DL 管理を行うため URL 指定不要
            return nil
        case .kotobaWhisperBilingual(let model):
            return modelsDirectory.appendingPathComponent(model.expectedFileName)
        }
    }

    func downloadPageURL(for engine: SpeechEngine) -> URL? {
        switch engine {
        case .whisperKit:
            // WhisperKit は HF からの自動 DL のため、ユーザー向け配布ページは存在しない
            return nil
        case .kotobaWhisperBilingual(let model):
            return model.downloadPageURL
        }
    }
}
