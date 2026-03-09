# Research Log: recording-feedback-bar

## Summary

既存の RecordingOverlayView を画面下部のバー型インジケーターに置き換え、音量レベルのリアルタイム可視化を追加する機能の設計調査。既存アーキテクチャの拡張として、最小限の変更で実現可能。

## Research Log

### Topic 1: 音量レベル計算方式

AVAudioPCMBuffer の `floatChannelData` からRMS（Root Mean Square）値を計算する。RMSは音量レベルの標準的な指標で、バッファ内のサンプル値の二乗平均平方根を取る。

計算式: `sqrt(sum(sample^2) / count)`

結果は 0.0〜1.0 の範囲に正規化し、dBスケールではなくリニアスケールで扱う（UIアニメーション向け）。

### Topic 2: 音量レベルの伝搬方式

2つの選択肢を検討:

A. AudioCapturing プロトコルに `audioLevel` プロパティを追加
   - 利点: シンプル、AudioCaptureService内で完結
   - 欠点: プロトコル変更が既存のモックに波及

B. SessionManager が音量レベルを独自に管理
   - 利点: Presentation層に近い場所でPublish
   - 欠点: SessionManagerの責務が増える

決定: 方式Aを採用。AudioCapturing に `var currentAudioLevel: Float { get }` を追加し、SessionManager がタイマーまたはバッファ処理時にポーリングして `@Published audioLevel` として公開する。ただし、より直接的なアプローチとして、AudioCaptureService のタップコールバック内でレベルを計算し、SessionManager に公開用の Published プロパティを追加する。

### Topic 3: バーUIの配置と表示方式

NSWindow をフローティングで画面下部に配置する既存パターン（OverlayWindowController）を流用。変更点:
- 位置: 画面中央上部 → 画面下部全幅
- サイズ: 300x80 → 画面幅 x 40程度
- コンテンツ: VStack → HStack（音量バー + テキスト）

### Topic 4: アニメーション方式

音量レベルに応じたバーアニメーションとして、複数の縦棒（バーグラフ）が音量に連動して上下するイコライザー風の表示を採用。SwiftUI の `withAnimation` で滑らかに更新する。更新頻度はオーディオタップのバッファサイズ（1024サンプル）に依存し、44.1kHz/1024 = 約43Hz で十分滑らか。

## Design Decisions

| 決定事項 | 選択 | 根拠 |
|---------|------|------|
| 音量計算方式 | RMS | 標準的で安定した音量指標 |
| レベル伝搬 | AudioCapturing拡張 + SessionManager Published | 既存パターンに合致 |
| バー配置 | NSWindow floating, 画面下部 | 既存OverlayWindowControllerパターンを流用 |
| アニメーション | SwiftUI + withAnimation | フレームワーク内で完結、高パフォーマンス |
| 更新頻度 | オーディオバッファ到着時（約43Hz） | 追加タイマー不要、十分滑らか |

## Risks

| リスク | 影響度 | 対策 |
|-------|-------|------|
| 音量レベル更新によるUI負荷 | 低 | SwiftUIの差分レンダリングで最小限 |
| AudioCapturingプロトコル変更 | 低 | モック更新が必要だが軽微 |
