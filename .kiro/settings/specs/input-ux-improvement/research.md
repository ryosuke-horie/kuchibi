# Research & Design Decisions

## Summary
- Feature: `input-ux-improvement`
- Discovery Scope: Extension
- Key Findings:
  - CGEvent の `keyboardSetUnicodeString` API により、仮想キーコード不要で任意の Unicode 文字（日本語含む）を直接入力可能
  - 既存の `OutputMode` enum と `ClipboardService` を拡張する形で実装可能。プロトコル変更は最小限
  - フォールバックは既存の `pasteToActiveApp` をそのまま再利用可能

## Research Log

### CGEvent による Unicode テキスト直接入力
- Context: `autoInput` モードでクリップボードを使わずにテキストを入力する方法の調査
- Sources Consulted:
  - [Apple Developer Documentation - keyboardSetUnicodeString](https://developer.apple.com/documentation/coregraphics/cgevent/1456028-keyboardsetunicodestring)
  - [Swift keyboard keycodes reference](https://gist.github.com/swillits/df648e87016772c7f7e5dbed2b345066)
- Findings:
  - `CGEvent(keyboardEventSource:virtualKey:keyDown:)` で仮想キーイベントを生成し、`keyboardSetUnicodeString(stringLength:unicodeString:)` で Unicode 文字列をアタッチする
  - virtualKey は 0 を指定し、実際の文字は Unicode 文字列で指定する方式が Unicode 入力に適している
  - keyDown と keyUp の両方をポストする必要がある
  - 日本語・絵文字等の非 ASCII 文字も UTF-16 に変換して設定可能
  - `.cghidEventTap` にポストすることでアクティブアプリに入力される
  - アクセシビリティ権限（既に取得済み）が必要
- Implications:
  - 1文字ずつイベントを送信するため長文では遅延が発生する可能性がある
  - 文字単位での失敗検出は困難（CGEvent の post は戻り値なし）
  - イベント生成自体の失敗（nil 返却）でフォールバックを判定する

### フォールバック戦略
- Context: 直接入力が失敗した場合のリカバリ方法
- Findings:
  - CGEvent の生成が nil を返す場合 = アクセシビリティ権限がない、またはシステムリソース不足
  - 既存の `pasteToActiveApp` メソッドがクリップボード退避・復元を含む完全な実装を持つ
  - フォールバック時はこのメソッドをそのまま呼び出せる
- Implications: 新規コードは最小限で済む

## Design Decisions

### Decision: テキスト入力方式
- Context: Unicode テキストをアクティブアプリに直接入力する方法の選定
- Alternatives Considered:
  1. CGEvent + keyboardSetUnicodeString（1文字ずつ送信）
  2. NSAppleScript による keystroke コマンド
  3. Accessibility API (AXUIElementSetAttributeValue) によるテキスト設定
- Selected Approach: CGEvent + keyboardSetUnicodeString
- Rationale: 既存コードが CGEvent を使用しており一貫性がある。アクセシビリティ権限は既に取得済み。AppleScript は起動オーバーヘッドが大きく、Accessibility API はフォーカス中の要素の特定が複雑
- Trade-offs: 長文入力時に1文字ずつの送信で遅延が生じる可能性があるが、音声認識結果は通常短文のため許容範囲
- Follow-up: 長文入力時のパフォーマンスを実機テストで確認

### Decision: OutputMode の命名
- Context: 新モードの内部名称
- Selected Approach: `autoInput` — 自動判定で入力方式を選択する意味を明示
- Rationale: `clipboard` / `directInput` と区別しやすく、フォールバック動作を含意する名称

## Risks & Mitigations
- 長文テキストの入力遅延 — 文字間の sleep を最小限にし、必要に応じてバッチ送信を検討
- 一部アプリケーションが CGEvent を受け付けない可能性 — フォールバック機構で対応
- 既存ユーザーの設定値が `clipboard` のまま変わらない — デフォルト変更は新規インストール時のみ、既存設定は維持

## References
- [Apple CGEvent keyboardSetUnicodeString](https://developer.apple.com/documentation/coregraphics/cgevent/1456028-keyboardsetunicodestring) — Unicode 文字列付きキーイベント生成 API
- [Swift keyboard keycodes](https://gist.github.com/swillits/df648e87016772c7f7e5dbed2b345066) — macOS キーコードリファレンス
