# Research & Design Decisions

---
**Purpose**: Capture discovery findings, architectural investigations, and rationale that inform the technical design.

---

## Summary
- **Feature**: `voice-input-escape`
- **Discovery Scope**: Extension（既存セッション管理への機能追加）
- **Key Findings**:
  - ESC キーのグローバル監視には `NSEvent.addGlobalMonitorForEvents` が適切。HotKey ライブラリで裸の ESC キーを登録すると全アプリの ESC 操作を奪ってしまう
  - `SessionManagerImpl` に `cancelSession()` メソッドを追加するのが最小変更。既存の `finishSession()` とは別パスとしてテキスト出力を完全スキップする
  - FeedbackBar は `sessionManager.$state` の Combine パイプラインに反応して自動的に非表示になるため、追加の UI 変更は不要

## Research Log

### ESC キー検出方法の選定

- **Context**: ESC キーをグローバルに検出する手段を選定する必要がある
- **Sources Consulted**: macOS NSEvent documentation, HotKey library source
- **Findings**:
  - `HotKey(key: .escape, modifiers: [])` で ESC 単体を登録可能だが、Carbon の `RegisterEventHotKey` はシステム全体で ESC を奪う。個人用ツールでも他のアプリの ESC 操作（例: テキスト編集のキャンセル）を妨害するリスクがある
  - `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` はイベントを「横取り」せず監視のみ行う。ターゲットアプリにもイベントが届く。macOS 個人ツールで広く採用されているパターン
  - keyCode `53` が ESC キーに対応（Carbon 定数 `kVK_Escape` と同値）
- **Implications**: `NSEvent.addGlobalMonitorForEvents` を採用し、既存の HotKey パターンとは分離した `EscapeKeyMonitor` クラスを新設する

### 既存 SessionManager の cancelSession 設計

- **Context**: `finishSession()` は `accumulatedLines` を出力してから state を `.idle` に戻す。キャンセル時はこのパスを通らない専用メソッドが必要
- **Findings**:
  - `recordingTask` は `Task<Void, Never>` として保持されており `cancel()` で協調的にキャンセル可能
  - `audioService.stopCapture()` は既に `finishSession()` で呼ばれているため同様に利用できる
  - `accumulatedLines` と `partialText` をクリアすれば出力は発生しない
- **Implications**: `cancelSession()` は `finishSession()` のパラメータ化ではなく独立メソッドとして実装し、意図の明確さとテスタビリティを優先する

### キャンセル時システムサウンド

- **Context**: 通常終了と区別できるキャンセル専用フィードバック音が必要（要件 4.1）
- **Findings**:
  - 既存: `sessionStart` = 1057 (Tink), `sessionEnd` = `kSystemSoundID_UserPreferredAlert`
  - macOS システムサウンド ID 1073 (Basso) が「キャンセル/エラー」の意味合いで一般的に用いられる
  - `sessionSoundEnabled` 設定フラグを既存通り尊重する（要件 4.2）
- **Implications**: `SystemSound.sessionCancel = 1073` を追加し、既存の Sound 列挙に合わせる

### FeedbackBar への影響

- **Context**: キャンセル後に FeedbackBar を非表示にする必要がある（要件 4.3）
- **Findings**:
  - `FeedbackBarWindowController` は `sessionManager.$state` を Combine で購読し、`.recording` または `.processing` 以外は自動的に `hide()` を呼ぶ
  - `cancelSession()` が `state = .idle` に設定するだけで FeedbackBar は自動非表示になる
- **Implications**: FeedbackBar への追加実装は不要。既存の reactive パターンで要件を満たす

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| HotKey ライブラリで ESC 登録 | `HotKey(key: .escape, modifiers: [])` | 既存パターンと統一 | システム全体の ESC を奪う、他アプリ干渉 | 不採用 |
| NSEvent グローバルモニター | `addGlobalMonitorForEvents(matching: .keyDown)` | 非奪取・監視のみ、状態条件付きキャンセルと相性良い | アクセシビリティ権限不要（グローバルモニターは権限なしで動作） | 採用 |
| Local NSEvent モニター | アプリウィンドウがフォーカス時のみ | 影響範囲が小さい | バックグラウンドアプリのため常に非フォーカス。機能しない | 不採用 |

## Design Decisions

### Decision: EscapeKeyMonitor を独立コンポーネントとして新設

- **Context**: ESC 検出ロジックをどこに配置するか
- **Alternatives Considered**:
  1. `HotKeyControllerImpl` を拡張して ESC も担当させる
  2. `KuchibiApp` に直接 `NSEvent.addGlobalMonitorForEvents` を書く
  3. `EscapeKeyMonitorImpl` として独立コンポーネント新設
- **Selected Approach**: Option 3。`EscapeKeyMonitoring` プロトコルを定義し `EscapeKeyMonitorImpl` を実装
- **Rationale**: 単一責任原則。HotKey のトグル責務と ESC のキャンセル責務を分離することでテスタビリティと可読性が向上する。Mock を用いた `SessionManagerImpl` のテストが独立して行える
- **Trade-offs**: ファイルが 2 つ増える（プロトコル + 実装）。ただし小規模で許容範囲内
- **Follow-up**: `EscapeKeyMonitorImpl` の `startMonitoring` を `KuchibiApp.init()` で呼び出す統合確認

### Decision: cancelSession は processing 状態でも受け付ける

- **Context**: 要件 1.2 で `.processing` 状態中の ESC も対象
- **Alternatives Considered**:
  1. `.recording` のみキャンセル受け付け、`.processing` は無視
  2. `.recording` も `.processing` も両方キャンセル
- **Selected Approach**: Option 2
- **Rationale**: ユーザー視点では音声録音開始から認識完了まで「セッション中」であり、どの段階でも取り消せることが自然なUX
- **Trade-offs**: `.processing` 中に `recordingTask` は既に完了している可能性があるため、`cancel()` は no-op になる場合があるが問題ない

## Risks & Mitigations

- グローバルイベントモニターが他のアプリの ESC を「奪わない」前提で設計。`addGlobalMonitorForEvents` は奪取しないが、将来ローカルモニター追加時には注意が必要
- `recordingTask.cancel()` は協調的キャンセルのため、タスク内で `Task.isCancelled` を確認しない処理は継続する可能性がある。ただし `audioService.stopCapture()` で入力を止めるため実質的な問題はない
- `NSEvent.addGlobalMonitorForEvents` はメインスレッド以外から呼ばれる可能性がある。コールバック内で `Task { @MainActor in ... }` による actor isolation が必要

## References
- [NSEvent.addGlobalMonitorForEvents(matching:handler:)](https://developer.apple.com/documentation/appkit/nsevent/1535472-addglobalmonitorforevents) — グローバルイベントモニター公式ドキュメント
- [HotKey library](https://github.com/soffes/HotKey) — 既存ホットキー管理ライブラリ
