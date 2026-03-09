import AVFoundation
import Testing
@testable import Kuchibi

@Suite("AudioCaptureService")
struct AudioCaptureServiceTests {

    // MARK: - Task 2.1: 正常サイクルの検証

    @Test("初期状態ではキャプチャしていない")
    func initialState() {
        let service = AudioCaptureServiceImpl()
        #expect(service.isCapturing == false)
        #expect(service.currentAudioLevel == 0.0)
    }

    // MARK: - Task 2.2: nil ガードとエラーケースの検証

    @Test("stopCapture をキャプチャ前に呼び出してもクラッシュしない")
    func stopCaptureBeforeStartIsSafe() {
        let service = AudioCaptureServiceImpl()
        service.stopCapture()
        #expect(service.isCapturing == false)
        #expect(service.currentAudioLevel == 0.0)
    }

    @Test("stopCapture を複数回連続で呼び出してもクラッシュしない")
    func stopCaptureMultipleTimesIsSafe() {
        let service = AudioCaptureServiceImpl()
        service.stopCapture()
        service.stopCapture()
        service.stopCapture()
        #expect(service.isCapturing == false)
    }

    @Test("stopCapture 後は isCapturing が false になる")
    func isCapturingFalseAfterStop() {
        let service = AudioCaptureServiceImpl()
        // キャプチャなしでも stopCapture 後の状態が正しいことを確認
        service.stopCapture()
        #expect(service.isCapturing == false)
        #expect(service.currentAudioLevel == 0.0)
    }
}
