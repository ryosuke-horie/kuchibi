import AppKit
import AVFoundation
import ApplicationServices
import Combine
import Foundation
import os

/// マイク権限とアクセシビリティ権限の状態を観測する実装。
///
/// 起動時に `refresh()` を実行し、`NSApplication.didBecomeActiveNotification` を購読して
/// アプリがアクティブに戻るたびに状態を再取得する。
@MainActor
final class PermissionStateObserver: ObservableObject, PermissionStateObserving {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "PermissionStateObserver")

    @Published private(set) var microphoneGranted: Bool = false
    @Published private(set) var accessibilityTrusted: Bool = false

    private let fetchMicrophoneStatus: @MainActor () -> Bool
    private let fetchAccessibilityTrusted: @MainActor () -> Bool
    private var didBecomeActiveObservation: NSObjectProtocol?

    /// テスト容易性のため、2 つの権限取得処理をクロージャで DI 可能にする。
    /// - Parameters:
    ///   - fetchMicrophoneStatus: マイク権限取得クロージャ。
    ///     デフォルトは `AVCaptureDevice.authorizationStatus(for: .audio) == .authorized`。
    ///   - fetchAccessibilityTrusted: アクセシビリティ権限取得クロージャ。
    ///     デフォルトは `AXIsProcessTrusted()`。
    init(
        fetchMicrophoneStatus: @escaping @MainActor () -> Bool = {
            AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        },
        fetchAccessibilityTrusted: @escaping @MainActor () -> Bool = {
            AXIsProcessTrusted()
        }
    ) {
        self.fetchMicrophoneStatus = fetchMicrophoneStatus
        self.fetchAccessibilityTrusted = fetchAccessibilityTrusted
        refresh()
        subscribeToDidBecomeActive()
    }

    deinit {
        if let token = didBecomeActiveObservation {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func refresh() {
        let mic = fetchMicrophoneStatus()
        let ax = fetchAccessibilityTrusted()
        if mic != microphoneGranted {
            Self.logger.info("マイク権限の状態変化: \(mic, privacy: .public)")
            microphoneGranted = mic
        }
        if ax != accessibilityTrusted {
            Self.logger.info("アクセシビリティ権限の状態変化: \(ax, privacy: .public)")
            accessibilityTrusted = ax
        }
    }

    // MARK: - Private

    private func subscribeToDidBecomeActive() {
        didBecomeActiveObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // forName / queue: .main で発火する Notification ハンドラは
            // MainActor コンテキストで実行されるため、明示的に MainActor へ hop する。
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }
}
