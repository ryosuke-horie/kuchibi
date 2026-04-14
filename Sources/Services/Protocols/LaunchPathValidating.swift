import Foundation

/// アプリの起動場所を検査するプロトコル。
///
/// `/Applications/Kuchibi.app` を唯一の承認された起動場所として定義し、
/// それ以外（DerivedData などのビルド成果物）から起動された場合に UI で警告を出すための判定を提供する。
protocol LaunchPathValidating {
    /// 現在の起動場所が承認されたパスと一致するか
    var isApproved: Bool { get }

    /// 現在のバンドルパス（診断・UI 表示用）
    var currentPath: String { get }
}
