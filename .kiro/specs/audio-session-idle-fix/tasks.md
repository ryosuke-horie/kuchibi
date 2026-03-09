# Implementation Plan

- [x] 1. AudioCaptureServiceImpl のエンジンライフサイクルをセッション単位に変更する

- [x] 1.1 エンジンプロパティをオプショナルに変更し startCapture 呼び出し時にのみ生成する
  - `private let engine = AVAudioEngine()` を `private var engine: AVAudioEngine?` に変更する
  - `startCapture()` の冒頭に `engine == nil` のガード（または既存エンジンがあれば即 return）を追加し、二重起動を防ぐ
  - 毎回新しい `AVAudioEngine` を生成してから Voice Processing 設定・tap 設置・エンジン起動を行う
  - エンジン起動（`engine.start()`）が失敗した場合は `engine = nil` にしてリソースをリークしない
  - _Requirements: 1.3, 2.1, 2.2, 2.3, 4.1, 4.2_

- [x] 1.2 stopCapture で tap 除去 → エンジン停止 → nil 化の順序を保証する
  - `inputNode.removeTap(onBus: 0)` を `engine.stop()` より前に実行する
  - `engine.stop()` の後に `engine = nil` を代入し ARC によるオーディオリソース解放を確実にする
  - `engine` が nil の場合でも `stopCapture()` が安全に noop となるよう optional chaining を使う
  - 停止完了時に `"オーディオハードウェアを解放"` のログを追加する
  - _Requirements: 1.1, 1.2, 1.4, 3.1, 3.2, 3.3, 4.3_

- [x] 2. ライフサイクル変更の動作をテストで検証する

- [x] 2.1 startCapture / stopCapture の正常サイクルを検証する
  - `startCapture()` 後にエンジンが存在し `isCapturing == true` であることを確認する
  - `stopCapture()` 後にエンジンが解放されて `isCapturing == false` であることを確認する
  - `startCapture()` → `stopCapture()` を複数回繰り返しても正常に動作することを確認する
  - _Requirements: 1.3, 2.1, 2.2, 4.1, 4.2_

- [x] 2.2 エラーケースと nil ガードを検証する
  - エンジンが nil の状態で `stopCapture()` を呼び出してもクラッシュしないことを確認する
  - `startCapture()` 失敗時にエンジンが nil に戻ってリソースをリークしないことを確認する
  - _Requirements: 1.4, 2.3, 3.3_
