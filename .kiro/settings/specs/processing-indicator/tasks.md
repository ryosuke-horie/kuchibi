# Implementation Plan

- [x] 1. ウィンドウコントローラーの処理中表示を有効にする
- [x] 1.1 `.processing` 状態でもフィードバックバーウィンドウを表示するよう購読ロジックを修正する
  - `FeedbackBarWindowController` の `$state` 購読クロージャ内の表示条件を `.recording` のみから `.recording || .processing` に変更する
  - 既存の `show()` のべき等性（`guard window == nil`）により重複ウィンドウ生成がないことを確認する
  - `.idle` 遷移時には引き続き `hide()` が呼ばれることを確認する
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 4.1, 4.2_

- [x] 2. 処理中ウェーブアニメーションコンポーネントを実装する
- [x] 2.1 5本バーが山型ウェーブで上下アニメーションする `ProcessingWaveView` を実装する
  - `@State private var animating: Bool` を持ち、`onAppear` で `true` に切り替えてアニメーションを開始する
  - バーは5本で中央を頂点とする山型高さ分布（4/10, 4/16, 4/20, 4/16, 4/10 pt）にする
  - 各バーに `.easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(index) * 0.09)` を適用してウェーブ感を演出する
  - `onDisappear` で `animating = false` にしてアニメーションを停止する
  - 外部から引数を受け取らない完全自律コンポーネントとして設計する
  - _Requirements: 2.2, 2.3, 2.4, 2.5_

- [x] 3. FeedbackBarView の状態別コンテンツ切り替えを実装する
- [x] 3.1 `.processing` 状態時に `ProcessingWaveView` と処理中ラベルを表示する分岐を追加する
  - `sessionManager.state == .processing` の条件分岐を `body` に追加する
  - 処理中ブランチでは `ProcessingWaveView` と "文字起こし中..." テキストラベルを表示する
  - テキストラベルは `.foregroundColor(.secondary)` で録音中の `partialText` と区別できる配色にする
  - 処理中ブランチでは `partialText` の表示条件を評価しない
  - `@ObservedObject` による `sessionManager.state` の変化を SwiftUI が自動検知するため追加バインディングは不要
  - _Requirements: 2.1, 3.1, 3.2, 3.3, 4.3_

- [x] 3.2 録音中の既存表示（音量バー・部分テキスト）が維持されていることを確認する
  - `.recording` 状態では従来の `AudioLevelBar` 10本と `partialText` が引き続き表示されることを確認する
  - `.idle` 状態時はウィンドウ自体が非表示になるため `FeedbackBarView` の else ブランチは録音中のみを対象とする
  - _Requirements: 2.1, 2.5_

- [x] 4. ウィンドウコントローラーの状態遷移テストを追加する
- [x] 4.1 (P) `.processing` 遷移時にウィンドウが表示され続けることを検証するユニットテストを追加する
  - `state` を `.idle → .recording → .processing` と遷移させ、各状態でウィンドウの有無を検証する
  - `.processing → .idle` 遷移後にウィンドウが非表示になることを検証する
  - 既存の `show()` べき等性テスト（重複ウィンドウ未生成）を `.recording || .processing` 条件にも適用する
  - _Requirements: 1.1, 1.2, 1.3, 4.1, 4.2_

- [ ]* 4.2 (P) FeedbackBarView の状態別レンダリングテストを追加する
  - `.processing` 状態で `ProcessingWaveView` と "文字起こし中..." ラベルが存在することをスナップショットまたは accessibility ツリーで確認する
  - `.recording` 状態で `AudioLevelBar` と `partialText` が表示され処理中ラベルが存在しないことを確認する
  - _Requirements: 2.1, 3.1, 3.2, 3.3_
