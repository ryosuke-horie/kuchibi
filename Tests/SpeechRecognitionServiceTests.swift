import AVFoundation
import Foundation
import Testing
@testable import Kuchibi

@Suite("SpeechRecognitionService")
struct SpeechRecognitionServiceTests {
    @Test("loadInitialEngineでアダプターが初期化される")
    @MainActor
    func loadInitialEngine() async throws {
        let mockAdapter = MockSpeechRecognitionAdapter()
        let service = SpeechRecognitionServiceImpl(
            adapter: mockAdapter,
            initialEngine: .whisperKit(.base)
        )

        #expect(!service.isModelLoaded)
        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")
        #expect(service.isModelLoaded)
        #expect(mockAdapter.isInitialized)
        #expect(service.currentEngine == .whisperKit(.base))
    }

    @Test("loadInitialEngineで指定されたエンジンと言語がアダプターに渡される")
    @MainActor
    func loadInitialEnginePassesArguments() async throws {
        let mockAdapter = MockSpeechRecognitionAdapter()
        let service = SpeechRecognitionServiceImpl(
            adapter: mockAdapter,
            initialEngine: .whisperKit(.base)
        )

        try await service.loadInitialEngine(.whisperKit(.largeV3Turbo), language: "en")
        #expect(mockAdapter.initializedEngine == .whisperKit(.largeV3Turbo))
        #expect(mockAdapter.initializedLanguage == "en")
    }

    @Test("loadInitialEngine失敗時にエラーをスローする")
    @MainActor
    func loadInitialEngineFailure() async {
        let mockAdapter = MockSpeechRecognitionAdapter()
        mockAdapter.shouldThrowOnInit = true
        let service = SpeechRecognitionServiceImpl(
            adapter: mockAdapter,
            initialEngine: .whisperKit(.base)
        )

        do {
            try await service.loadInitialEngine(.whisperKit(.base), language: "ja")
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is KuchibiError)
        }
    }

    @Test("switchEngineでcurrentEngineが更新される（最小スタブ）")
    @MainActor
    func switchEngineUpdatesCurrentEngine() async throws {
        let mockAdapter = MockSpeechRecognitionAdapter()
        let service = SpeechRecognitionServiceImpl(
            adapter: mockAdapter,
            initialEngine: .whisperKit(.base)
        )

        try await service.loadInitialEngine(.whisperKit(.base), language: "ja")
        try await service.switchEngine(to: .whisperKit(.small), language: "ja")

        #expect(service.currentEngine == .whisperKit(.small))
        #expect(service.isModelLoaded)
        #expect(!service.isSwitching)
    }

    @Test("processAudioStreamがRecognitionEventを発行する")
    @MainActor
    func processAudioStream() async {
        let mockAdapter = MockSpeechRecognitionAdapter()
        mockAdapter.partialText = "途中"
        mockAdapter.finalText = "完了テキスト"
        let service = SpeechRecognitionServiceImpl(
            adapter: mockAdapter,
            initialEngine: .whisperKit(.base)
        )

        // ストリームを作成してすぐ終了
        let audioStream = AsyncStream<AVAudioPCMBuffer> { continuation in
            continuation.finish()
        }

        let eventStream = service.processAudioStream(audioStream)
        var events: [RecognitionEvent] = []
        for await event in eventStream {
            events.append(event)
        }

        // 少なくともlineCompletedが発行される
        let hasCompleted = events.contains { event in
            if case .lineCompleted = event.kind { return true }
            return false
        }
        #expect(hasCompleted)
    }
}
