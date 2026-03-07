# Implementation Plan

- [x] 1. SessionManager の音再生 API を AudioServicesPlaySystemSound に置き換える
- [x] 1.1 AudioToolbox import・SystemSound 定数・セッション開始音を置き換える
  - `import AudioToolbox` を SessionManager.swift に追加する
  - `SystemSound` プライベート enum を定義し、セッション開始音 (1057/Tink相当)・完了音 (1054/Pop相当)・フォールバック (`kSystemSoundID_UserPreferredAlert`) の定数を持たせる
  - `startSession()` 内の `NSSound(named: "Tink")` ブロックを `AudioServicesPlaySystemSound(SystemSound.sessionStart)` に置き換える
  - `sessionSoundEnabled` による ON/OFF 条件は維持する
  - _Requirements: 1.4, 3.2_

- [x] 1.2 セッション完了音を置き換える
  - `finishSession()` 内の `NSSound(named: "Pop")` ブロックを `AudioServicesPlaySystemSound(SystemSound.sessionEnd)` に置き換える
  - 完了音の呼び出し位置は `await outputManager.output(...)` の後（出力完了後）であることを維持する
  - `sessionSoundEnabled` による ON/OFF 制御は変更しない
  - `NSSound` を使用するコードがなくなった場合は不要な参照を整理する
  - _Requirements: 1.1, 1.2, 1.3, 1.5, 3.1, 3.2, 3.3_

- [x] 2. SessionManager のフォールバック時アクセシビリティ権限プロンプトを追加する
- [x] 2.1 権限不足でフォールバックした際にシステムダイアログを表示する
  - `finishSession()` 内で `accessibilityTrusted()` が false の場合、`AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)` を呼んでシステムダイアログを表示する
  - ダイアログ表示は clipboard フォールバック処理・エラー通知の送信と同じブロック内で行う
  - `AXIsProcessTrustedWithOptions` の呼び出しは `@discardableResult` として扱い、SessionState を変更しない
  - `AXIsProcessTrusted()` による権限確認は既存実装のまま維持する
  - _Requirements: 2.2, 2.3, 2.4, 2.5_

- [x] 3. (P) KuchibiApp 起動時にアクセシビリティ権限チェックを追加する
  - `KuchibiApp.init()` 内で、モデルロード用の既存 Task とは別の非同期 Task を起動する
  - Task 内で `Task.sleep(for: .seconds(1))` により 1 秒待機してから `AXIsProcessTrusted()` を確認する
  - 権限が未取得の場合のみ `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)` を呼んでシステムダイアログを表示する
  - 権限取得済みの場合はダイアログを表示しない
  - タスク 1（SessionManager.swift）とは異なるファイル（KuchibiApp.swift）の変更であるため並行実施可能
  - _Requirements: 2.1_

- [ ] 4. テストを追加・更新する
- [ ] 4.1 音再生設定の制御に関するテストを追加する
  - `SessionManagerTests` に `sessionSoundEnabled=false` のとき完了音が呼ばれないことを検証するテストを追加する
  - 既存のセッション開始・停止テストが引き続きパスすることを確認する
  - _Requirements: 1.5, 3.1, 3.3_

- [ ]* 4.2 アクセシビリティ権限フォールバックのテストを追加する
  - `accessibilityTrusted` クロージャをモックで `false` に差し替えた状態で `finishSession()` を呼び、clipboard フォールバックが発生することを検証する
  - `AXIsProcessTrustedWithOptions` の呼び出しをモック化して確認する（モック差し替えが困難な場合は統合テストとして実機確認で代替）
  - _Requirements: 2.2, 2.3, 2.4_
