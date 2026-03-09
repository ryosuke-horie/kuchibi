# Design Document: filler-removal

## Overview

Purpose: 音声認識結果から日本語フィラー（言い淀み・つなぎ言葉）を自動除去し、出力テキストの可読性を向上させる。

Users: kuchibi ユーザーが音声入力した結果からフィラーが除去され、クリーンなテキストが出力される。

Impact: 既存の `TextPostprocessorImpl` に新しい処理ステップを1つ追加する。プロトコルやインターフェースの変更は不要。

### Goals
- 日本語フィラーの自動除去による出力品質向上
- 既存の後処理パイプラインへのシームレスな統合

### Non-Goals
- フィラーパターンのユーザーカスタマイズ
- 英語フィラーへの対応
- フィラー除去の個別オン/オフ切り替え（既存の `textPostprocessingEnabled` で一括制御）

## Architecture

### Existing Architecture Analysis

現在の `TextPostprocessorImpl.process()` は4段階のパイプライン:
```
入力 → 1.空白トリム → 2.連続スペース正規化 → 3.日本語文字間スペース除去 → 4.繰り返し集約 → 出力
```

- `TextPostprocessing` プロトコル: `process(_ text: String) -> String` のみ
- `SessionManager` が `appSettings.textPostprocessingEnabled` で有効/無効を制御
- プロトコル変更は不要。実装の内部処理にステップを追加するのみ

### Architecture Pattern & Boundary Map

変更後のパイプライン:
```
入力 → 1.空白トリム → 2.連続スペース正規化 → 2.5.フィラー除去 → 3.日本語文字間スペース除去 → 4.繰り返し集約 → 出力
```

- 新ステップ 2.5 を Step 2 と Step 3 の間に挿入
- 理由: スペース正規化後の安定状態でパターンマッチし、除去後の余分なスペースは Step 3 以降で処理

### Technology Stack

変更なし。既存の Swift Regex をそのまま使用。

## Requirements Traceability

| Requirement | Summary | Components | Changes |
|-------------|---------|------------|---------|
| 1.1 | フィラー除去の実行 | TextPostprocessorImpl | 新ステップ追加 |
| 1.2 | 文頭フィラー除去 | TextPostprocessorImpl | 正規表現パターン |
| 1.3 | 文中フィラー除去 | TextPostprocessorImpl | 正規表現パターン |
| 1.4 | フィラーのみテキスト | TextPostprocessorImpl | 空文字列返却 |
| 1.5 | 誤除去防止 | TextPostprocessorImpl | 単語境界マッチ |
| 2.1 | 既存パイプライン統合 | TextPostprocessorImpl | ステップ挿入 |
| 2.2 | 無効時スキップ | SessionManager | 変更なし（既存動作） |

## Components and Interfaces

| Component | Domain/Layer | Intent | Req Coverage | Changes |
|-----------|-------------|--------|--------------|---------|
| TextPostprocessorImpl | Services | フィラー除去ステップ追加 | 1.1-1.5, 2.1 | 実装変更のみ |

### Services

#### TextPostprocessorImpl

| Field | Detail |
|-------|--------|
| Intent | 既存パイプラインにフィラー除去ステップを追加 |
| Requirements | 1.1, 1.2, 1.3, 1.4, 1.5, 2.1 |

対象フィラーパターン:
- 長音系: 「あー」「えー」「うー」「んー」（長音記号の連続バリエーション含む）
- 複合系: 「えーと」「えっと」
- 短縮系: 「あ、」「ま、」
- 副詞的: 「まあ」「なんか」「あの」「その」（単独出現時のみ）

マッチ条件:
- フィラーが文頭・文末にある場合、または前後にスペースがある場合に除去
- 他の語の一部として出現する場合（例: 「まあまあ」「あのね」）は保持
- 除去後に残る余分なスペースは後続の日本語文字間スペース除去ステップで処理

## Testing Strategy

### 単体テスト
- 各フィラーパターン（「あー」「えーと」「うーん」「まあ」等）が正しく除去される
- 文頭フィラー: 「えーと今日は」→「今日は」
- 文中フィラー: 「今日はえーと天気が」→「今日は天気が」
- フィラーのみ: 「あー」→「""」
- 意味のある語の誤除去防止: 「あのね」が保持される
- 既存テスト（空白正規化、繰り返し除去）がリグレッションなく通過する

### 統合確認
- `textPostprocessingEnabled = true` 時にフィラー除去が実行される（既存テストで担保）
- `textPostprocessingEnabled = false` 時にフィラー除去がスキップされる（既存テストで担保）
