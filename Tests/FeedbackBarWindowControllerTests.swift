import AppKit
import AVFoundation
import Foundation
import Testing
@testable import Kuchibi

/// 注: テストはメイン画面（NSScreen.main）が利用可能な環境（ローカル macOS 開発機）で実行することを前提とします。
@Suite("FeedbackBarWindowController")
struct FeedbackBarWindowControllerTests {

    @Test("初期状態でウィンドウは非表示")
    @MainActor
    func initiallyHidden() {
        let sm = makeSessionManager()
        let controller = FeedbackBarWindowController(sessionManager: sm)
        #expect(!controller.isVisible)
    }

    @Test("recording状態でウィンドウが表示される")
    @MainActor
    func showsWindowInRecordingState() async throws {
        try #require(NSScreen.main != nil, "このテストはディスプレイ（NSScreen.main）が必要です")

        let mockASR = makeHoldingASR()
        let sm = makeSessionManager(speechService: mockASR)
        let controller = FeedbackBarWindowController(sessionManager: sm)

        sm.startSession()
        try await Task.sleep(for: .milliseconds(100))

        #expect(controller.isVisible)

        mockASR.finishStream()
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test("processing状態でウィンドウが表示され続ける")
    @MainActor
    func keepsWindowInProcessingState() async throws {
        try #require(NSScreen.main != nil, "このテストはディスプレイ（NSScreen.main）が必要です")

        let mockASR = makeHoldingASR()
        let sm = makeSessionManager(speechService: mockASR)
        let controller = FeedbackBarWindowController(sessionManager: sm)

        sm.startSession()
        try await Task.sleep(for: .milliseconds(100))
        #expect(sm.state == .recording)
        #expect(controller.isVisible)

        sm.stopSession()
        try await Task.sleep(for: .milliseconds(100))
        #expect(sm.state == .processing)
        #expect(controller.isVisible)

        mockASR.finishStream()
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test("idle遷移でウィンドウが非表示になる")
    @MainActor
    func hidesWindowWhenIdle() async throws {
        try #require(NSScreen.main != nil, "このテストはディスプレイ（NSScreen.main）が必要です")

        let mockASR = makeHoldingASR()
        let sm = makeSessionManager(speechService: mockASR)
        let controller = FeedbackBarWindowController(sessionManager: sm)

        sm.startSession()
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.isVisible)

        sm.stopSession()
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.isVisible)  // まだ processing 中

        mockASR.finishStream()  // → idle
        try await Task.sleep(for: .milliseconds(100))
        #expect(!controller.isVisible)
    }

    @Test("recording→processing遷移でウィンドウが重複生成されない")
    @MainActor
    func idempotentShowDoesNotDuplicateWindow() async throws {
        try #require(NSScreen.main != nil, "このテストはディスプレイ（NSScreen.main）が必要です")

        let mockASR = makeHoldingASR()
        let sm = makeSessionManager(speechService: mockASR)
        let controller = FeedbackBarWindowController(sessionManager: sm)

        sm.startSession()
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.isVisible)

        sm.stopSession()  // show() が再呼び出しされるが guard window == nil でスキップされる
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.isVisible)

        mockASR.finishStream()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!controller.isVisible)
    }

    // MARK: - Helpers

    @MainActor
    private func makeHoldingASR() -> MockSpeechRecognitionService {
        let asr = MockSpeechRecognitionService()
        asr.isModelLoaded = true
        asr.holdStream = true
        return asr
    }

    @MainActor
    private func makeSessionManager(speechService: SpeechRecognizing? = nil) -> SessionManagerImpl {
        let asr = speechService ?? {
            let m = MockSpeechRecognitionService()
            m.isModelLoaded = true
            return m
        }()
        return SessionManagerImpl(
            audioService: MockAudioCaptureService(),
            speechService: asr,
            outputManager: MockOutputManager(),
            notificationService: MockNotificationService(),
            appSettings: AppSettings(defaults: UserDefaults(suiteName: "test.fbwc.\(UUID().uuidString)")!),
            micAuthorizationStatus: { .authorized },
            accessibilityTrusted: { true }
        )
    }
}
