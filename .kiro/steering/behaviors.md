# Behavioral Contracts

spec で確立された振る舞い契約と不変条件。新機能実装・リファクタ時にこれらを破ると UX が退行する。spec は凍結スナップショット、本ファイルは**現在有効な契約の集約**。

由来 spec は `(spec: name)` として記載する。

---

## セッション状態機械

- `idle → recording` への遷移はホットキー（Cmd+Shift+Space）1 回目でのみ発生し、遷移時に `accumulatedLines` を空に初期化する (spec: hotkey-toggle-session, session-text-accumulation)
- `recording` 中の自動停止（無音タイムアウト等）は行わない。遷移の引き金はホットキー 2 回目（正常終了）または ESC（キャンセル）のみ (spec: hotkey-toggle-session, voice-input-escape)
- `recording → processing → idle` の正常経路では、`accumulatedLines` を後処理→結合して `OutputManager` に一括出力する。蓄積が空なら `OutputManager` を呼ばない (spec: session-text-accumulation)
- `cancelSession()`（ESC 経由）は `accumulatedLines` と `partialText` を破棄し、`OutputManager` を一切呼ばずに `idle` へ戻す。`audioLevel` は 0.0 にリセット (spec: voice-input-escape)
- `idle` 状態での ESC キーは無視（副作用なし） (spec: voice-input-escape)
- セッション終了・キャンセル時は `AudioCaptureService.stopCapture()` を必ず呼び、マイクのタップ除去とエンジン停止を実行する。idle 時に他アプリのオーディオ入力を妨害しないこと (spec: audio-session-idle-fix)

## テキスト処理パイプライン

- 後処理の順序は固定: (1) 空白正規化 → (2) フィラー除去 → (3) 繰り返し集約 → (4) 句点付与。句点付与は必ず最終ステップ (spec: text-postprocessing, filler-removal, punctuation-postprocessing)
- `textPostprocessingEnabled=false` のときは全ステップをスキップし、WhisperKit の出力を素通しする (spec: text-postprocessing)
- 読点（、）は後処理で追加も削除もしない。WhisperKit の出力をそのまま保持 (spec: punctuation-postprocessing)
- 既に `。！!？?` で終わるテキストには句点を付与しない (spec: punctuation-postprocessing)

## 認識イベントの意味論

- `RecognitionEvent.lineCompleted(final:)` は確定テキスト。受信時に後処理を適用して `accumulatedLines` へ追加する。`recording` 中は `OutputManager` に直接渡さない (spec: session-text-accumulation)
- `RecognitionEvent.textChanged(partial:)` は途中結果。`partialText` の UI 表示更新用のみ、蓄積対象ではない (spec: session-text-accumulation, recording-feedback-bar)
- `RecognitionEvent.lineStarted` は認識行の開始合図で、`audioLevel` 更新の起点として扱う (spec: recording-feedback-bar)

## UI フィードバックの表示契約

- `FeedbackBar` は `recording` と `processing` の両状態で連続表示し、状態遷移時にウィンドウを close/open せず内容差し替えのみで切り替える。非表示は `idle` への遷移時のみ (spec: recording-feedback-bar, processing-indicator)
- `recording` 中は音量バー（AudioLevelBar × 10）+ `partialText`、`processing` 中は `ProcessingWaveView` + 「文字起こし中...」ラベルを表示。`processing` 中は `partialText` を表示しない (spec: processing-indicator, recording-feedback-bar)
- `FeedbackBar` は `.floating` レベル・`ignoresMouseEvents=true`・`canJoinAllSpaces` を維持し、フォーカスを奪わない (spec: recording-feedback-bar)
- ESC キャンセル時は `FeedbackBar` を同期的に非表示化する（遅延表示の残留を避ける） (spec: voice-input-escape)

## 音響フィードバック

- 開始音・完了音・キャンセル音は互いに区別可能な異なる SystemSound を使用（`1057`/`kSystemSoundID_UserPreferredAlert`/`1073`）(spec: session-start-sound, completion-sound-accessibility, voice-input-escape)
- 完了音は `OutputManager` への出力完了後に鳴らす（出力前に鳴らさない）(spec: completion-sound-accessibility)
- `sessionSoundEnabled=false` のとき、開始音・完了音・キャンセル音すべてを抑止する一括制御 (spec: session-start-sound, completion-sound-accessibility)
- サウンド再生は録音・出力処理をブロックしない非同期実行 (spec: session-start-sound)

## 音声前処理の前提

- `SpeechRecognitionAdapting` に渡す音声は常に 16kHz モノラル。これ以外のフォーマットは `AudioPreprocessing` でリサンプル済みの状態で渡す (spec: audio-preprocessing)
- ノイズ抑制（`noiseSuppressionEnabled`）と VAD（`vadEnabled`）は設定で個別に有効/無効化できる。無効時は生データ素通し (spec: audio-preprocessing)
- VAD が無音判定（RMS < `vadThreshold`）したバッファは認識エンジンに送らない (spec: audio-preprocessing)

## 権限と起動順序

- `AXIsProcessTrusted` のチェックは `outputMode ∈ {directInput, autoInput}` のときにのみ行う。`clipboard` モードでは権限不要 (spec: macos-voice-input-client, completion-sound-accessibility)
- 権限未取得時は `AXIsProcessTrustedWithOptions` でダイアログを表示し、拒否時は `NotificationService` でユーザーに通知する (spec: completion-sound-accessibility)
- ESC キーのグローバル監視はアプリ起動中常時維持する（セッション外でも監視は続くが、`idle` 時は何もしない）(spec: voice-input-escape)
- アプリは `MenuBarExtra` + `LSUIElement` でメニューバー常駐とし、Dock にウィンドウを表示しない (spec: macos-voice-input-client)
- WhisperKit モデルのロードは起動直後に `Task` で非同期実行し、UI をブロックしない (spec: macos-voice-input-client)

## デフォルト値の根拠

- `outputMode=autoInput`: セッション終了後にアクティブアプリへ即時貼り付けできる、最も摩擦の少ない経路 (spec: macos-voice-input-client)
- `model=.base`: tiny より日本語精度が大幅に高く、small ほどの処理コストを要求しないバランス点。精度重視時は設定から large-v3 まで昇格可能 (spec: whisperkit-migration)
- `updateInterval=0.5s`: 途中結果の滑らかさと CPU 負荷のバランス (spec: whisperkit-migration)
- `sessionSoundEnabled=true` / `textPostprocessingEnabled=true` / `monitoringEnabled=true`: 個人用アプリとして品質・可観測性を既定で有効化 (spec: completion-sound-accessibility, text-postprocessing, recognition-monitoring)

---
_実装変更時はここの契約を破っていないか必ず確認すること。契約そのものを変更する場合は、由来 spec の延長として新規 spec を作成する_
