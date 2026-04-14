import AVFoundation
import Combine

/// 音声認識サービスのプロトコル
///
/// hot-swap 対応のため、現在のエンジン・切替中フラグ・最後の切替エラーを
/// Published として公開する。
/// 初回ロードは `loadInitialEngine(_:language:)`、以降の切替は `switchEngine(to:language:)` を使う。
///
/// 注意: 設計上は `@MainActor` 前提だが、既存テスト群（Mock 実装を非 MainActor 文脈から
/// セットアップする箇所が多い）への破壊を避けるため本 task（1.3）ではプロトコルレベルの
/// `@MainActor` 付与を見送っている。Task 5.2 で `SessionManagerImpl.state` 監視を追加する
/// タイミングで MainActor 強制へ引き上げる想定。
protocol SpeechRecognizing: ObservableObject {
    var currentEngine: SpeechEngine { get }
    var isModelLoaded: Bool { get }
    var isSwitching: Bool { get }
    var lastSwitchError: String? { get }

    func loadInitialEngine(_ engine: SpeechEngine, language: String) async throws
    func switchEngine(to engine: SpeechEngine, language: String) async throws
    func processAudioStream(_ stream: AsyncStream<AVAudioPCMBuffer>) -> AsyncStream<RecognitionEvent>
}
