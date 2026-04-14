import Foundation

/// 各 `SpeechEngine` のモデルファイル配置状況を判定するプロトコル。
///
/// - WhisperKit 系は WhisperKit 自身がモデル DL を管理するため常に `true` を返す想定。
/// - Kotoba-Whisper Bilingual のようにユーザー手動配置が必要なエンジンは、
///   `~/Library/Application Support/Kuchibi/models/` 配下のファイル存在を確認する。
protocol ModelAvailabilityChecking {
    /// 指定エンジンのモデルファイルが利用可能か
    func isAvailable(for engine: SpeechEngine) -> Bool

    /// 指定エンジンのモデルファイル URL（ロード時に使用）。
    /// WhisperKit のように URL 指定を必要としないエンジンでは `nil` を返す。
    func modelPath(for engine: SpeechEngine) -> URL?

    /// 指定エンジンのモデル配布ページ URL（未配置時に UI から開くためのガイド）。
    /// 配布ページが存在しない（WhisperKit など）エンジンでは `nil` を返す。
    func downloadPageURL(for engine: SpeechEngine) -> URL?
}
