# Research & Design Decisions

## Summary
- Feature: `audio-preprocessing`
- Discovery Scope: Extension
- Key Findings:
  - macOS の `setVoiceProcessingEnabled(_:)` はエンジン停止中にのみ有効化可能。有効化時にチャンネル数やフォーマットが変わる場合がある
  - AVAudioConverter のサンプルレート変換には `convert(to:error:withInputFrom:)` コールバック形式を使う必要がある。単純な `convert(to:from:)` ではサンプルレート変換は動作しない
  - Voice Processing 有効化時にエンジン構成変更通知が発生するため、`AVAudioEngineConfigurationChange` の監視が必要

## Research Log

### macOS Voice Processing API

- Context: Requirement 1 のノイズ抑制に macOS Voice Processing を使用する方針
- Sources Consulted:
  - [setVoiceProcessingEnabled Apple Docs](https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:))
  - [WWDC23 What's new in voice processing](https://developer.apple.com/videos/play/wwdc2023/10235/)
  - [WWDC19 What's New in AVAudioEngine](https://developer.apple.com/videos/play/wwdc2019/510/)
  - [Tips about AVAudioEngine](https://snakamura.github.io/log/2024/11/audio_engine.html)
  - [OpenAI Realtime Audio Notes](https://community.openai.com/t/audio-notes-for-openai-realtime-on-apple-platforms/1108404)
- Findings:
  - `AVAudioIONode.setVoiceProcessingEnabled(_:)` で入力ノードにノイズ抑制・エコーキャンセル・AGC を適用できる
  - エンジンが停止中の状態でのみ呼び出し可能（動的な切り替え不可）
  - 有効化すると input/output 両ノードに Voice Processing が適用される
  - macOS では有効化時にチャンネル数が変わる場合がある（1ch → 5ch 等）。tap のフォーマット取得タイミングに注意が必要
  - `setVoiceProcessingEnabled` の呼び出しによりエンジン構成が変更されるため、`AVAudioEngineConfigurationChange` 通知を監視してエンジンを再起動する必要がある
- Implications:
  - ノイズ抑制の切り替えにはエンジン停止→再起動が必要。セッション中の動的切り替えは不可
  - tap インストール前に Voice Processing を有効化し、その後のフォーマットで tap を設定する必要がある

### AVAudioConverter によるリサンプリング

- Context: Requirement 3 の 16kHz リサンプリングの実現方法
- Sources Consulted:
  - [TN3136: AVAudioConverter](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions)
  - [AVAudioConverter Apple Docs](https://developer.apple.com/documentation/avfaudio/avaudioconverter)
  - [Swift AVAudioEngine Airpod Convert SampleRate](https://forums.swift.org/t/swift-avaudioengine-airpod-convert-samplerate/34243)
  - [Tips about AVAudioEngine](https://snakamura.github.io/log/2024/11/audio_engine.html)
- Findings:
  - 単純な `convert(to:from:)` ではサンプルレート変換が動作しない
  - `convert(to:error:withInputFrom:)` のコールバック形式を使う必要がある
  - コールバックでは入力バッファを提供した後、`inputStatus` を `.noDataNow` に設定し `nil` を返す
  - 出力バッファに全結果が含まれない場合がある。同じ converter インスタンスを使い続ける必要がある
  - フレームキャパシティは `inputFrames * (outputSampleRate / inputSampleRate)` で計算
- Implications:
  - AudioPreprocessor 内で AVAudioConverter インスタンスを保持し、バッファごとに変換を実行する設計が必要
  - 入力フォーマットが既に 16kHz モノラルの場合はスキップして効率化

### エネルギーベース VAD

- Context: Requirement 2 の音声アクティビティ検出
- Sources Consulted: 一般的な音声処理の知識
- Findings:
  - RMS（二乗平均平方根）でバッファのエネルギーレベルを計算し、閾値と比較する方式が最もシンプル
  - 現在の `AudioCaptureServiceImpl.updateAudioLevel` が既に RMS 計算を行っている。この計算を活用可能
  - 無音区間の判定にはヒステリシスは不要（バッファ単位の判定で十分）
  - 閾値はユーザーが調整可能にする（AppSettings で管理）
- Implications:
  - VAD は前処理パイプラインの最終段（リサンプリング後）に配置
  - 閾値以下のバッファは認識エンジンに送信しない
  - 音声レベル計算は VAD と共有できる

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| AudioCaptureService 内に統合 | 全処理を AudioCaptureService に追加 | 変更箇所が少ない | 責務が肥大化、テストしにくい | 不採用 |
| AudioPreprocessor を新設 | 前処理を独立コンポーネントとして抽出 | 単一責務、テスト容易、設定注入が自然 | コンポーネント数が増える | 採用 |
| SpeechRecognitionService 内で処理 | 認識サービス内で前処理 | 認識エンジンに近い | AudioCapturing との結合が不自然 | 不採用 |

## Design Decisions

### Decision: AudioPreprocessor を AudioCaptureService と SpeechRecognitionService の間に配置

- Context: 前処理（リサンプリング、VAD）をどのレイヤーで実行するか
- Alternatives Considered:
  1. AudioCaptureService の tap 内で処理 — キャプチャと前処理が密結合
  2. 独立した AudioPreprocessor コンポーネント — AsyncStream を変換するパイプラインとして機能
  3. SpeechRecognitionService 内で処理 — 認識サービスの責務が過大
- Selected Approach: 独立した AudioPreprocessor を新設し、AudioCaptureService からの AsyncStream を受け取り、前処理済みの AsyncStream を SpeechRecognitionService に渡す
- Rationale: 単一責務の原則に従い、テスト容易性を確保。AppSettings からの設定注入も自然に行える
- Trade-offs: コンポーネントが1つ増えるが、テスト容易性と拡張性が向上する
- Follow-up: SessionManager での統合時にストリーム変換のパフォーマンスを確認

### Decision: Voice Processing はエンジン起動前に設定する

- Context: ノイズ抑制の有効化タイミング
- Alternatives Considered:
  1. セッション開始時に毎回設定 — エンジン停止→設定→再起動
  2. アプリ起動時に一度だけ設定 — 設定変更時にはエンジン再起動が必要
- Selected Approach: AudioCaptureService の `startCapture` 内で、エンジン起動前に設定値に基づいて Voice Processing を有効化
- Rationale: セッションごとに最新の設定を反映でき、エンジンはセッション終了時に停止するため自然なタイミング
- Trade-offs: 毎回のセッション開始時に Voice Processing の設定が走るが、オーバーヘッドは無視できる程度
- Follow-up: Voice Processing 有効化によるフォーマット変更の確認

### Decision: VAD はリサンプリング後に適用

- Context: VAD の適用タイミング
- Alternatives Considered:
  1. リサンプリング前に適用 — 元のサンプルレートでエネルギー計算
  2. リサンプリング後に適用 — 16kHz に統一された状態でエネルギー計算
- Selected Approach: リサンプリング後に VAD を適用
- Rationale: 16kHz に統一されたデータでエネルギー計算することで、サンプルレートに依存しない一貫した閾値設定が可能
- Trade-offs: 無音区間のリサンプリングが無駄になるが、バッファサイズが小さいため影響は軽微
- Follow-up: なし

## Risks & Mitigations

- macOS で Voice Processing 有効化時にフォーマットが予期せず変わる可能性 — 有効化後にフォーマットを再取得し、それに基づいて tap と converter を設定
- AVAudioConverter のコールバック形式の複雑さ — TN3136 のパターンに厳密に従い、ユニットテストで検証
- VAD 閾値のデフォルト値が環境に合わない可能性 — 設定画面で調整可能にし、適切なデフォルト値を検証で決定

## References

- [setVoiceProcessingEnabled Apple Docs](https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:)) — Voice Processing API リファレンス
- [TN3136: AVAudioConverter](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions) — サンプルレート変換の公式技術ノート
- [WWDC23 What's new in voice processing](https://developer.apple.com/videos/play/wwdc2023/10235/) — Voice Processing の最新機能
- [Tips about AVAudioEngine](https://snakamura.github.io/log/2024/11/audio_engine.html) — AVAudioConverter の実践的な注意点
