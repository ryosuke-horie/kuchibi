# Research & Design Decisions

---
- Feature: `punctuation-postprocessing`
- Discovery Scope: Simple Addition（既存サービスへの処理ステップ追加）
- Key Findings:
  - `TextPostprocessorImpl.process(_:)` が唯一の後処理エントリポイントであり、ここに句点付与ステップを追加するだけで要件を満たせる
  - プロトコル `TextPostprocessing` のシグネチャ変更は不要
  - `textPostprocessingEnabled` フラグが false の場合、`SessionManager` が `process` を呼ばないため、自動的に句点付与もスキップされる

---

## Research Log

### TextPostprocessor の既存パイプライン確認

- Context: 句点付与をどのステップに挿入すべきか判断するために既存実装を確認
- Findings:
  - ステップ1: 先頭・末尾空白除去
  - ステップ2: 連続スペース正規化
  - ステップ2.5: 日本語フィラー除去（えーと、うーん 等）
  - ステップ3: 日本語文字間スペース除去
  - ステップ4: 3文字以上繰り返しフレーズ集約
- Implications: 句点付与はフィラー除去・スペース正規化後の最終ステップ（ステップ5）として追加する

### SessionManager の後処理呼び出し確認

- Context: `textPostprocessingEnabled` と句点付与の連動方法を確認
- Findings:
  - `SessionManager.handleRecognitionEvent()` で `textPostprocessingEnabled` が true のときのみ `textPostprocessor.process()` を呼ぶ
  - false のときは raw テキストをそのまま使用
- Implications: `process` メソッド内に句点付与を追加すれば、`textPostprocessingEnabled` フラグとの連動は自動的に実現される（要件 3.3 を満たす）

### 読点の扱い

- Context: WhisperKit が生成する読点（、）をどう扱うべきか確認
- Findings:
  - 現在の TextPostprocessor は読点を操作していない
  - 読点追加ロジックを実装しないことで要件 2.1〜2.3 をすべて満たせる
- Implications: 読点に関しては新規コードを追加しないことが正しい設計

---

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| 既存 process() への追加 | TextPostprocessorImpl.process() の末尾にステップ5を追加 | 変更箇所最小、プロトコル変更不要 | なし | 採用 |
| 別メソッド化 | appendPeriod() を独立メソッドとして追加 | 単体テストしやすい | 呼び出し側の変更が必要 | 不採用（過剰設計） |

---

## Design Decisions

### Decision: 句点付与を process() の最終ステップとして実装

- Context: 要件 1.4 および 3.1 で「既存後処理の後に実行」が明記されている
- Alternatives Considered:
  1. process() 末尾にインライン追加 — シンプルで変更最小
  2. 独立した後処理ステップとして分離 — テスト容易性は高いが複雑化
- Selected Approach: process() 末尾にステップ5としてインライン追加
- Rationale: プロトコルシグネチャを変更せず、SessionManager 側の変更もゼロで要件を満たせる
- Trade-offs: ロジックが process() に集約されるが、1行の追加であり可読性は損なわれない
- Follow-up: 単体テストで境界値（空文字、既存句点、感嘆符・疑問符）を網羅すること

---

## Risks & Mitigations

- WhisperKit が既に句点を付与している場合の二重付与 — 末尾文字チェック（。！!？?）により防止済み
- 英数字・記号のみのテキストへの誤付与 — 末尾チェックは文字種に依存しないため影響なし（許容範囲）

---

## References

- TextPostprocessor.swift — Sources/Services/TextPostprocessor.swift
- TextPostprocessing protocol — Sources/Services/Protocols/TextPostprocessing.swift
- SessionManager 後処理呼び出し — Sources/Services/SessionManager.swift:212-214
