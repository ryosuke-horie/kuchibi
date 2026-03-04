import Foundation
import os

/// セッション単位のメトリクス
struct SessionMetrics {
    let startTime: Date
    let duration: TimeInterval
    let completedLineCount: Int
    let totalCharacterCount: Int
    let error: KuchibiError?
}

/// セッションメトリクスの収集とログ出力
final class SessionMonitoringServiceImpl: SessionMonitoring {
    private static let logger = Logger(subsystem: "com.kuchibi.app", category: "Monitoring")

    private var startTime: Date?
    private var lineCount: Int = 0
    private var charCount: Int = 0
    private(set) var currentMetrics: SessionMetrics?

    func sessionStarted() {
        startTime = Date()
        lineCount = 0
        charCount = 0
        currentMetrics = SessionMetrics(
            startTime: startTime!,
            duration: 0,
            completedLineCount: 0,
            totalCharacterCount: 0,
            error: nil
        )
    }

    func textCompleted(text: String) {
        lineCount += 1
        charCount += text.count
        updateMetrics()
    }

    func sessionEnded() {
        let duration = calculateDuration()
        currentMetrics = SessionMetrics(
            startTime: startTime ?? Date(),
            duration: duration,
            completedLineCount: lineCount,
            totalCharacterCount: charCount,
            error: nil
        )
        Self.logger.info("セッション完了: 継続時間=\(String(format: "%.1f", duration))s, 行数=\(self.lineCount), 文字数=\(self.charCount)")
    }

    func sessionFailed(error: KuchibiError) {
        let duration = calculateDuration()
        currentMetrics = SessionMetrics(
            startTime: startTime ?? Date(),
            duration: duration,
            completedLineCount: lineCount,
            totalCharacterCount: charCount,
            error: error
        )
        Self.logger.error("セッションエラー: 種別=\(String(describing: error)), 継続時間=\(String(format: "%.1f", duration))s")
    }

    // MARK: - Private

    private func calculateDuration() -> TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    private func updateMetrics() {
        currentMetrics = SessionMetrics(
            startTime: startTime ?? Date(),
            duration: calculateDuration(),
            completedLineCount: lineCount,
            totalCharacterCount: charCount,
            error: nil
        )
    }
}
