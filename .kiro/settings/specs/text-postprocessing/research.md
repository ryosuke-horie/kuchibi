# Research & Design Decisions

## Summary
- Feature: `text-postprocessing`
- Discovery Scope: Simple Addition
- Key Findings:
  - 現在のパイプラインではテキスト変換が一切行われていない。SessionManager の `handleRecognitionEvent` が最適な挿入ポイント
  - Swift の正規表現（`Regex`）で日本語文字クラスの判定が可能。Unicode プロパティ `\p{Han}`, `\p{Hiragana}`, `\p{Katakana}` を使用
  - 繰り返し検出は正規表現のバックリファレンス `(.{3,})\1+` で実現可能

## Research Log

### 日本語文字間の空白除去パターン

- Context: Requirement 1 の空白正規化。Moonshine は複数行を空白で結合するため、日本語文字間に不要なスペースが挿入される
- Sources Consulted: Swift 標準ライブラリ、Unicode Character Properties
- Findings:
  - Swift の `Regex` で Unicode プロパティベースのマッチングが可能
  - 日本語文字: `\p{Han}`（漢字）, `\p{Hiragana}`, `\p{Katakana}`, 全角記号は `\p{Fullwidth_Forms}` や個別指定
  - 「日本語文字 + スペース + 日本語文字」のパターンをスペースなしに置換
  - 英数字と日本語の間のスペースは保持する必要がある
- Implications: 純粋な文字列操作のみで実現可能。外部ライブラリ不要

### 繰り返しテキスト検出

- Context: Requirement 2 の重複フレーズ除去
- Sources Consulted: 正規表現パターン
- Findings:
  - `(.{3,})\1+` パターンで 3 文字以上の連続繰り返しを検出可能
  - バックリファレンス `\1` で同一フレーズのマッチング
  - 2 文字以下は助詞の意図的な繰り返し（「はは」「のの」等）があるため除外
- Implications: 正規表現 1 つで実現可能。パフォーマンス上の懸念は認識テキストの長さ（通常数十文字）を考えると無視できる

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| SessionManager 内に直接実装 | handleRecognitionEvent でテキスト変換 | 変更箇所最小 | テストしにくい、責務混在 | 不採用 |
| TextPostprocessor を新設 | 独立コンポーネントとして抽出 | テスト容易、設定注入が自然、AudioPreprocessor と対称的 | コンポーネント数増加 | 採用 |
| OutputManager 内で処理 | 出力直前に変換 | 出力に近い | OutputManager の責務逸脱 | 不採用 |

## Design Decisions

### Decision: TextPostprocessor を SessionManager から呼び出す

- Context: テキスト後処理の配置場所
- Alternatives Considered:
  1. SessionManager 内に直接実装
  2. 独立コンポーネント TextPostprocessor
  3. OutputManager 内で処理
- Selected Approach: TextPostprocessor を新設し、SessionManager の lineCompleted ハンドリングで呼び出す
- Rationale: AudioPreprocessor と対称的な設計。テスト容易性と単一責務の原則に従う
- Trade-offs: コンポーネント増加だが、純粋関数的な設計でテストが容易
- Follow-up: なし

## Risks & Mitigations

- 正規表現が意図しないテキストを変換する可能性 — 設定でオフにできるようにする
- 英数字混在テキストでの空白除去の誤判定 — 英数字と日本語の間のスペースは明示的に保持

## References

- Swift Regex documentation — Unicode property escapes
