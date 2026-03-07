# Research & Design Decisions

---
**Purpose**: 文字起こし処理中インジケーターの設計に関するディスカバリー記録。

---

## Summary

- **Feature**: `processing-indicator`
- **Discovery Scope**: Extension（既存 FeedbackBar システムへの機能追加）
- **Key Findings**:
  - `SessionManagerImpl` は `@Published var state: SessionState` を持ち、`FeedbackBarWindowController` が Combine の `$state` で購読済み
  - `FeedbackBarView` は `@ObservedObject var sessionManager: SessionManagerImpl` を直接参照するため、追加の状態バインディングなしに `sessionManager.state` へアクセス可能
  - 新しい外部ライブラリは不要。SwiftUI の組み込みアニメーション API（`.animation(_:value:)`, `repeatForever`, `easeInOut`）で要件を満たせる

## Research Log

### FeedbackBarWindowController の状態購読パターン

- **Context**: `.processing` 中もウィンドウを表示し続けるために、購読ロジックの変更が必要
- **Sources Consulted**: `Sources/Views/FeedbackBarView.swift`（コードベース内）
- **Findings**:
  - 現在の条件: `state == .recording` のみ `show()` を呼ぶ
  - `state == .recording || state == .processing` に変更するだけで対応可能
  - `show()` は `guard window == nil` でべき等性が担保されている（重複表示なし）
- **Implications**: 変更はほぼ1行。既存の hide/show ロジックに影響なし

### SwiftUI アニメーション選択

- **Context**: 処理中を表すアニメーションとして何が適切か
- **Sources Consulted**: Apple Developer Documentation（SwiftUI Animation）
- **Findings**:
  - `withAnimation(.repeatForever)` はビューが画面外にある場合にも継続実行される
  - `.animation(_:value:)` + `@State` での toggle アプローチは `onAppear`/`onDisappear` でライフサイクル管理しやすい
  - stagger delay（各バーに異なる `.delay()`）でウェーブ感を演出できる
- **Implications**: `@State private var animating: Bool` を `onAppear` で `true` にセットする実装が最もシンプルで SwiftUI のライフサイクルと整合する

### 状態遷移時のウィンドウ再生成問題

- **Context**: `.recording` → `.processing` 遷移時にウィンドウを閉じずに表示を切り替えられるか
- **Findings**:
  - `FeedbackBarWindowController.show()` は `guard window == nil` のため、既にウィンドウが存在する場合は何もしない
  - `FeedbackBarView` は `@ObservedObject` により `sessionManager.state` の変化を SwiftUI が自動で検知して再レンダリングする
  - `recording` → `processing` 遷移時に `sink` が `show()` を再呼び出ししても `guard` でスキップされる
- **Implications**: ウィンドウ再生成なしに表示内容の切り替えが自動的に実現できる（要件 4.3 を自然に満たす）

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| SwiftUI @State toggle | `animating: Bool` を onAppear で切り替え | シンプル、ライフサイクル管理しやすい | なし | 採用 |
| Timer ベース | `Timer.publish` で phase 更新 | 細かい制御が可能 | 複雑、ライフサイクル管理が必要 | 不採用 |
| CAAnimation | CoreAnimation ベース | 高パフォーマンス | SwiftUI との統合が複雑 | 不採用 |

## Design Decisions

### Decision: `ProcessingWaveView` を独立コンポーネントとして分離

- **Context**: `FeedbackBarView` に処理中アニメーションロジックをインラインで書くか、別コンポーネントにするか
- **Alternatives Considered**:
  1. インライン実装 — `FeedbackBarView` 内に直接 `@State` と条件分岐を記述
  2. 独立コンポーネント — `ProcessingWaveView` として分離
- **Selected Approach**: `ProcessingWaveView` として独立コンポーネントに分離
- **Rationale**: アニメーション状態（`@State var animating`）のスコープを処理中表示ビューに閉じ込めることで、`FeedbackBarView` の責務を状態切り替えのみに限定できる
- **Trade-offs**: ファイル内に小コンポーネントが増えるが、将来の変更が局所化される
- **Follow-up**: デザイン変更時は `ProcessingWaveView` のみを変更すれば良い

## Risks & Mitigations

- アニメーションが `.processing` 終了後も継続するリスク — `onDisappear { animating = false }` で明示的に停止
- `show()` の重複呼び出し — `guard window == nil` によって自然に防止されている

## References

- Apple SwiftUI Documentation: Animation API
- `Sources/Views/FeedbackBarView.swift` — 既存の `AudioLevelBar` アニメーションパターン
