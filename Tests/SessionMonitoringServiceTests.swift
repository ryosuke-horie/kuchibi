import Foundation
import Testing
@testable import Kuchibi

@Suite("SessionMonitoringService")
struct SessionMonitoringServiceTests {

    @Test("sessionStarted で開始時刻が記録される")
    func sessionStartedRecordsTime() {
        let service = SessionMonitoringServiceImpl()
        let before = Date()
        service.sessionStarted()
        let after = Date()

        let metrics = service.currentMetrics
        #expect(metrics != nil)
        #expect(metrics!.startTime >= before)
        #expect(metrics!.startTime <= after)
    }

    @Test("textCompleted で行数と文字数が累計される")
    func textCompletedAccumulatesMetrics() {
        let service = SessionMonitoringServiceImpl()
        service.sessionStarted()

        service.textCompleted(text: "こんにちは")
        service.textCompleted(text: "テスト")

        let metrics = service.currentMetrics
        #expect(metrics!.completedLineCount == 2)
        #expect(metrics!.totalCharacterCount == 8) // 5 + 3
    }

    @Test("sessionEnded で継続時間が算出される")
    func sessionEndedCalculatesDuration() async throws {
        let service = SessionMonitoringServiceImpl()
        service.sessionStarted()
        try await Task.sleep(for: .milliseconds(50))
        service.sessionEnded()

        let metrics = service.currentMetrics
        #expect(metrics!.duration >= 0.04)
    }

    @Test("sessionFailed でエラー種別が記録される")
    func sessionFailedRecordsError() {
        let service = SessionMonitoringServiceImpl()
        service.sessionStarted()
        service.sessionFailed(error: .microphoneUnavailable)

        let metrics = service.currentMetrics
        #expect(metrics!.error != nil)
        if case .microphoneUnavailable = metrics!.error {} else {
            Issue.record("microphoneUnavailable を期待")
        }
    }

    @Test("sessionStarted で前回のメトリクスがリセットされる")
    func sessionStartedResetsMetrics() {
        let service = SessionMonitoringServiceImpl()
        service.sessionStarted()
        service.textCompleted(text: "テスト")
        service.sessionEnded()

        // 新しいセッション
        service.sessionStarted()
        let metrics = service.currentMetrics
        #expect(metrics!.completedLineCount == 0)
        #expect(metrics!.totalCharacterCount == 0)
    }

    @Test("空テキストの textCompleted でも行数はカウントされる")
    func textCompletedWithEmptyString() {
        let service = SessionMonitoringServiceImpl()
        service.sessionStarted()
        service.textCompleted(text: "")

        let metrics = service.currentMetrics
        #expect(metrics!.completedLineCount == 1)
        #expect(metrics!.totalCharacterCount == 0)
    }
}
