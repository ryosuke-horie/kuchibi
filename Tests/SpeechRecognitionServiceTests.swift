import AVFoundation
import Foundation
import Testing
@testable import Kuchibi

@Suite("SpeechRecognitionService")
struct SpeechRecognitionServiceTests {
    @Test("loadModelでアダプターが初期化される")
    func loadModel() async throws {
        let mockAdapter = MockSpeechRecognitionAdapter()
        let service = SpeechRecognitionServiceImpl(adapter: mockAdapter)

        #expect(!service.isModelLoaded)
        try await service.loadModel()
        #expect(service.isModelLoaded)
        #expect(mockAdapter.isInitialized)
    }

    @Test("loadModel失敗時にエラーをスローする")
    func loadModelFailure() async {
        let mockAdapter = MockSpeechRecognitionAdapter()
        mockAdapter.shouldThrowOnInit = true
        let service = SpeechRecognitionServiceImpl(adapter: mockAdapter)

        do {
            try await service.loadModel()
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is KuchibiError)
        }
    }

    @Test("processAudioStreamがRecognitionEventを発行する")
    func processAudioStream() async {
        let mockAdapter = MockSpeechRecognitionAdapter()
        mockAdapter.partialText = "途中"
        mockAdapter.finalText = "完了テキスト"
        let service = SpeechRecognitionServiceImpl(adapter: mockAdapter)

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
