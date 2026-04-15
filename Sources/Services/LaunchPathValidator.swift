import Foundation
import os

/// アプリの起動場所を検査する実装。
///
/// 唯一の承認された起動場所は `/Applications/Kuchibi.app`。
/// それ以外（DerivedData などのビルド成果物）から起動された場合、
/// `isApproved == false` を返し、UI 側で警告バナーを表示する想定。
final class LaunchPathValidator: LaunchPathValidating {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "LaunchPathValidator")

    /// 唯一の承認された起動場所
    static let approvedPath = "/Applications/Kuchibi.app"

    private let bundlePath: String

    /// テスト容易性のため、現在のバンドルパスを DI 可能にする。
    /// - Parameter currentBundlePath: 起動中のアプリの bundlePath。
    ///   デフォルトは `Bundle.main.bundlePath`。
    init(currentBundlePath: String = Bundle.main.bundlePath) {
        self.bundlePath = currentBundlePath
        if currentBundlePath != Self.approvedPath {
            Self.logger.warning(
                "承認外パスから起動: \(currentBundlePath, privacy: .public) (期待: \(Self.approvedPath, privacy: .public))"
            )
        }
    }

    var isApproved: Bool {
        bundlePath == Self.approvedPath
    }

    var currentPath: String {
        bundlePath
    }
}
