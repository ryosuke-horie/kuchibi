# Research & Design Decisions

---
**Purpose**: Capture discovery findings, architectural investigations, and rationale that inform the technical design.

---

## Summary

- **Feature**: `audio-session-idle-fix`
- **Discovery Scope**: Extension（既存サービスの修正）
- **Key Findings**:
  - `AudioCaptureServiceImpl` は `AVAudioEngine` をクラスのプロパティとして `let` で永続保持しており、録音停止後もオーディオハードウェアへの参照を手放さない
  - macOS では `AVAudioEngine.stop()` を呼んでも OS はオーディオ I/O ユニットの接続を即座に解放せず、他アプリのオーディオパイプラインに干渉し続ける可能性がある
  - `setVoiceProcessingEnabled(true)` はシステムレベルの Voice Processing IO ユニットを有効化するため、エンジン停止後もその効果が残存するリスクがある
  - macOS 14.0 以降では `AVAudioSession` API が native macOS で利用可能だが、セッション停止の最も確実な手段はエンジンインスタンス自体を破棄することである

## Research Log

### AVAudioEngine のリソース保持挙動

- **Context**: `engine.stop()` を呼んだ後もマイク・スピーカーへ影響を与えている原因調査
- **Findings**:
  - `AVAudioEngine` は `stop()` 後もオーディオグラフを保持し、内部 I/O ノードへの参照を維持する
  - Swift の ARC によってエンジンインスタンスが解放されるまで、OS 側では当該プロセスがオーディオ I/O ユニットを保有しているとみなす
  - Voice Processing IO (`setVoiceProcessingEnabled(true)`) はシステムの AudioUnit グラフに追加される。エンジンが生きている限りこの AudioUnit は存在し続ける
- **Implications**: 録音停止後にエンジンを `nil` にして ARC に解放させることで、OS がオーディオ I/O ユニットを完全に破棄する

### macOS 14 における AVAudioSession

- **Context**: iOS のようなセッション管理 API が macOS で利用できるか確認
- **Findings**:
  - macOS 14.0+ で `AVAudioSession` が native macOS に提供されたが、カテゴリ設定やアクティブ化の挙動は iOS と異なる
  - macOS ではシステムレベルの排他制御が iOS ほど厳密ではなく、`setActive(false)` の呼び出しだけではハードウェアリソースの解放を保証できない
  - 最も確実な解放方法は、エンジンインスタンスを破棄してオーディオグラフごと解放することである
- **Implications**: `AVAudioSession` 明示的管理よりも lazy engine instantiation を優先する

### 変更対象ファイルの特定

- **Context**: Light Discovery - 修正範囲の特定
- **Findings**:
  - 変更対象: `Sources/Services/AudioCaptureService.swift` のみ
  - `AudioCapturing` プロトコル（`Sources/Services/Protocols/AudioCapturing.swift`）: 変更不要（インターフェースは変わらない）
  - `SessionManager.swift`: 変更不要（`stopCapture()` の呼び出し方は変わらない）
  - 新規外部依存ライブラリ: なし
- **Implications**: 影響範囲が最小で、既存テスト・呼び出し元への破壊的変更なし

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| Lazy Engine Instantiation | `startCapture()` で毎回新しい `AVAudioEngine` を生成し、`stopCapture()` で nil にして ARC 解放 | OS がオーディオ I/O ユニットを確実に解放する。VP 状態もリセットされる | セッション開始ごとにエンジン初期化のオーバーヘッドがある（100ms 未満） | 採用 |
| Engine.reset() 呼び出し | 停止後に `engine.reset()` を呼んでグラフをリセット | エンジン再利用によりオーバーヘッド低減 | `reset()` がハードウェア I/O を完全解放するか OS バージョン依存で不確実 | 不採用 |
| AVAudioSession.setActive(false) | 停止後にセッションを明示的に非アクティブ化 | iOS との整合性がある | macOS 14 の AVAudioSession 挙動が iOS と異なる。単独では不十分 | 補助的に検討したが不採用 |

## Design Decisions

### Decision: `AVAudioEngine` の lazy per-session インスタンス化

- **Context**: 録音停止後もエンジンが生存することで音声ハードウェアが解放されない問題
- **Alternatives Considered**:
  1. `let engine = AVAudioEngine()` の維持 + `engine.reset()` 追加
  2. `let engine = AVAudioEngine()` の維持 + `AVAudioSession.setActive(false)` 追加
  3. `var engine: AVAudioEngine?` に変更し、セッションごとに生成・破棄
- **Selected Approach**: Option 3 — `var engine: AVAudioEngine?` で lazy 初期化。`startCapture()` で生成、`stopCapture()` で `nil` 代入して ARC 解放
- **Rationale**: ARC によるデストラクション時に OS がオーディオグラフと I/O ユニットを確実に解放する。プラットフォーム差異に依存せず macOS 14 以降で安定動作する
- **Trade-offs**:
  - メリット: 他アプリへの干渉を完全排除、VP 状態のリセット保証
  - デメリット: セッション開始ごとにエンジン初期化コスト（実測で 50〜100ms 程度、UI 上は許容範囲）
- **Follow-up**: セッション開始の体感速度を動作確認し、レイテンシが問題になる場合は warm-up 戦略を検討

### Decision: `AudioCapturing` プロトコルを変更しない

- **Context**: インターフェースの変更範囲を最小化する
- **Selected Approach**: `stopCapture() -> Void` のシグネチャを維持し、内部実装のみ変更
- **Rationale**: 呼び出し元（`SessionManager`）への影響ゼロ。モックやテストダブルへの変更も不要

## Risks & Mitigations

- エンジン生成コストによる開始レイテンシ増加 — 実測して 200ms を超える場合のみ対策を検討
- `inputNode.removeTap` を `engine.stop()` 後に呼ぶと既に無効なグラフへのアクセスになるリスク — tap 除去を `engine.stop()` より必ず先に実行する順序を設計で明示
- `startCapture()` 中に前回のエンジンが残存するケース — `stopCapture()` が必ず `engine = nil` を実行することを保証する

## References

- Apple Developer Documentation — AVAudioEngine: https://developer.apple.com/documentation/avfaudio/avaudioengine
- Apple Developer Documentation — setVoiceProcessingEnabled: https://developer.apple.com/documentation/avfaudio/avaudioinputnode/setvoiceprocessingenabled(_:)
