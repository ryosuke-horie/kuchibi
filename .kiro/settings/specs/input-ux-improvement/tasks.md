# Implementation Plan

- [x] 1. OutputMode 列挙型と ClipboardServicing プロトコルの拡張
  - `OutputMode` に `autoInput` case を追加し、UserDefaults 永続化に対応する rawValue を設定する
  - `ClipboardServicing` プロトコルに直接タイピング入力用の `typeText` メソッドを追加する
  - _Requirements: 2.1_

- [x] 2. 直接タイピング入力機能の実装
- [x] 2.1 (P) ClipboardService に直接タイピング入力メソッドを実装する
  - CGEvent と `keyboardSetUnicodeString` を使用して、テキストを1文字ずつキーボードイベントとしてアクティブアプリのカーソル位置に送信する
  - virtualKey = 0 で keyDown / keyUp イベントを生成し、UTF-16 に変換した文字列をアタッチして `.cghidEventTap` にポストする
  - CGEvent の生成が nil を返した場合、即座に既存の `pasteToActiveApp`（クリップボード退避・Cmd+V・復元）にフォールバックする
  - 直接タイピング成功時はクリップボードに一切触れないことを保証する
  - _Requirements: 1.1, 1.2, 1.3, 3.1, 3.2, 3.3_

- [x] 2.2 (P) AppSettings のデフォルト値変更と SettingsView UI 拡張
  - `AppSettings` の `defaultOutputMode` を `autoInput` に変更する
  - 設定画面の出力モード Picker に「自動入力（推奨）」を先頭の選択肢として追加する
  - 既存ユーザーの保存済み設定値は維持され、新規インストール時のみ `autoInput` がデフォルトになる
  - _Requirements: 2.2, 2.3, 2.4_

- [x] 3. 出力パイプライン統合
  - OutputManager の `output(text:mode:)` メソッドの switch 分岐に `autoInput` case を追加し、`typeText` を呼び出すようにする
  - SessionManager からの呼び出しフロー（SessionManager → OutputManager → ClipboardService）が `autoInput` モードで正しく動作することを確認する
  - _Requirements: 1.1_

- [x] 4. テスト
- [x] 4.1 (P) OutputMode と AppSettings の単体テスト
  - `OutputMode.autoInput` の rawValue エンコード・デコードが正しく動作することを検証する
  - `AppSettings` のデフォルト値が `autoInput` であることを検証する
  - 既存の保存値（`clipboard` / `directInput`）が正しく復元されることを検証する
  - _Requirements: 2.1, 2.4_

- [x] 4.2 (P) OutputManager 統合テストとフォールバック検証
  - `OutputManagerImpl` が `autoInput` モード時に `typeText` を呼び出すことを検証する
  - CGEvent 生成失敗時に `pasteToActiveApp` へフォールバックすることを検証する
  - フォールバック後にクリップボード内容が復元されることを検証する
  - _Requirements: 1.1, 1.2, 3.1, 3.2, 3.3_
