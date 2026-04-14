import Foundation

/// マイク権限とアクセシビリティ権限の状態を観測するプロトコル。
///
/// 起動時および `NSApplication.didBecomeActiveNotification` 発火時に `refresh()` を呼ぶことで、
/// 設定 UI 上で最新の権限状態を Published 値として参照できるようにする。
@MainActor
protocol PermissionStateObserving: ObservableObject {
    /// マイク権限が付与されているか
    var microphoneGranted: Bool { get }

    /// アクセシビリティ権限（AXIsProcessTrusted）が付与されているか
    var accessibilityTrusted: Bool { get }

    /// 権限状態を再取得し、Published 値を更新する
    func refresh()
}
