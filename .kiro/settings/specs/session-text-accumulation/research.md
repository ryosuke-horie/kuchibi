# Research & Design Decisions

## Summary
- Feature: `session-text-accumulation`
- Discovery Scope: Extension
- Key Findings:
  - SessionManager は `.lineCompleted` ごとに即座に `outputManager.output()` を呼んでおり、テキスト蓄積の仕組みがない
  - `finishSession()` にはテキスト出力ロジックが存在しない。蓄積テキストのフラッシュ処理を追加する必要がある
  - 無音タイムアウトパスでは `finishSession(error:)` を呼ぶが、出力処理は含まれていない

## Research Log

### SessionManager の出力フロー分析
- Context: 現在の `.lineCompleted` 処理がどのようにテキストを出力しているか
- Sources Consulted: `Sources/Services/SessionManager.swift` (127-148行目)
- Findings:
  - `.lineCompleted` ハンドラ内で `textPostprocessor.process()` → `outputManager.output()` を即座に実行
  - `partialText` をクリアし、無音タイマーをリセット
  - 複数の `.lineCompleted` が1セッション内で発生すると、各回でクリップボードが上書きされる
- Implications: `.lineCompleted` ハンドラから `outputManager` 呼び出しを除去し、バッファ追加に置換する

### セッション終了パスの網羅分析
- Context: セッション終了時にテキストをフラッシュする箇所の特定
- Sources Consulted: `Sources/Services/SessionManager.swift` (89-96, 150-180行目)
- Findings:
  - 正常終了: `stopSession()` → audio停止 → eventStream完了 → `recordingTask` ループ脱出 → `finishSession()`
  - 無音タイムアウト: `startSilenceTimeout()` → `audioService.stopCapture()` → `finishSession(error: .silenceTimeout)`
  - 無音タイムアウトでは `audioService.stopCapture()` の後に直接 `finishSession()` が呼ばれる。ただし、`stopCapture()` により eventStream が終了するため、`recordingTask` 側の `finishSession()` も実行される可能性がある
  - `@MainActor` により同時実行はないが、`state != .idle` ガードで二重実行は防止されている
- Implications:
  - 蓄積テキストのフラッシュは `finishSession()` 内、または `recordingTask` ループ脱出後の `finishSession()` 呼び出し前に配置する
  - 無音タイムアウトパスでは、タイムアウト時点までに蓄積されたテキストが出力される必要がある（要件 2.3）
  - `finishSession()` 内でフラッシュするのが最もシンプルで、すべての終了パスをカバーできる

### テキスト後処理との統合ポイント
- Context: 後処理をどのタイミングで適用するか
- Sources Consulted: `Sources/Services/TextPostprocessor.swift`, requirements.md 要件 3
- Findings:
  - 現在は `.lineCompleted` ハンドラ内で行単位に後処理を適用
  - 後処理の内容: 空白トリム、スペース正規化、日本語文字間スペース除去、繰り返しフレーズ除去
  - これらの処理は行単位での適用が意味的に正しい（結合後に適用すると行間の空白が正規化対象になる問題がある）
- Implications: 後処理は従来通り行単位で適用し、後処理済みテキストをバッファに追加する方式が適切

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| A: SessionManager 内バッファ | `[String]` 配列プロパティを追加し、`finishSession()` でフラッシュ | 最小変更、単一責務の延長 | SessionManager の責務がやや増える | 推奨: 既存の状態管理フローに自然に統合 |
| B: TextAccumulator 専用クラス | テキスト蓄積を別コンポーネントに分離 | 責務分離 | オーバーエンジニアリング、依存注入が増える | 不採用: 配列操作1つに対して過剰 |

## Design Decisions

### Decision: バッファの配置場所
- Context: 蓄積テキストをどこに保持するか
- Alternatives Considered:
  1. SessionManager 内の `private var accumulatedLines: [String]`
  2. 別途 TextAccumulator クラスを導入
- Selected Approach: SessionManager 内のプライベート配列プロパティ
- Rationale: セッションライフサイクルと密結合しており、分離する意味が薄い。配列への append と join のみの操作で、専用クラスは過剰
- Trade-offs: SessionManager のプロパティが1つ増えるが、既存の `partialText` と同じレイヤーの状態管理
- Follow-up: テスト時に蓄積テキストの内容を検証するため、出力結果を MockOutputManager 経由で確認する

### Decision: テキスト結合方式
- Context: 蓄積した行をどのように結合して出力するか
- Alternatives Considered:
  1. 改行 (`\n`) で結合
  2. 空文字列で結合（行末の処理に依存）
- Selected Approach: 改行 (`\n`) で結合
- Rationale: 各行は独立した発話セグメントであり、改行区切りが最も自然
- Trade-offs: なし
- Follow-up: なし

### Decision: フラッシュのタイミング
- Context: 蓄積テキストをいつ出力するか
- Alternatives Considered:
  1. `finishSession()` 内でフラッシュ
  2. `recordingTask` ループ脱出直後、`finishSession()` 呼び出し前にフラッシュ
- Selected Approach: `finishSession()` 内でフラッシュ（`state = .idle` 設定の前）
- Rationale: すべての終了パス（正常終了・無音タイムアウト）を1箇所でカバーでき、フラッシュ漏れのリスクがない
- Trade-offs: `finishSession()` が async になる必要がある（`outputManager.output()` が async のため）
- Follow-up: `finishSession()` の呼び出し箇所すべてで `await` が必要

## Risks & Mitigations
- `finishSession()` の async 化: 現在の呼び出し箇所（`recordingTask` クロージャ、`startSilenceTimeout` クロージャ）はすでに async コンテキスト内にあるため、`await` 追加のみで対応可能
- 二重フラッシュ: `@MainActor` + `state != .idle` ガードにより、`finishSession()` が2回実行されることはない
- メモリ: 1セッション中の蓄積テキスト量は数十行程度が上限であり、メモリ上の問題はない

## References
- `Sources/Services/SessionManager.swift` — 変更対象の中心ファイル
- `Sources/Services/TextPostprocessor.swift` — 行単位の後処理パイプライン
- `Sources/Services/OutputManager.swift` — 出力インターフェース
- `Tests/SessionManagerTests.swift` — 既存テストスイート
