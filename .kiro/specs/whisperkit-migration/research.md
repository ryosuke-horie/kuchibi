# Research & Design Decisions

## Summary
- Feature: `whisperkit-migration`
- Discovery Scope: Complex Integration
- Key Findings:
  - WhisperKit はバッチ処理ベースの API であり、Moonshine のようなリアルタイムストリーミングは提供しない。チャンク分割＋コールバックでストリーミングを模倣する設計が必要
  - `TranscriptionCallback = ((TranscriptionProgress) -> Bool?)?)` により、認識途中のテキストをコールバックで取得可能。戻り値 `false` で認識を中断できる
  - 既存の `MoonshineAdapting` プロトコルは WhisperKit でもほぼそのまま利用可能だが、汎用的な命名へのリネームが要件に含まれる

## Research Log

### WhisperKit API 構造

- Context: WhisperKit の公開 API を調査し、既存アダプターパターンへの適合性を評価する
- Sources Consulted:
  - https://github.com/argmaxinc/WhisperKit (GitHub リポジトリ)
  - WhisperKit API ドキュメント（Swift DocC）
  - HuggingFace モデルリポジトリ
- Findings:
  - メインクラス `WhisperKit` の初期化は `WhisperKitConfig` で行う
  - 認識メソッド: `transcribe(audioArray: [Float], decodeOptions: DecodingOptions?, callback: TranscriptionCallback) async throws -> [TranscriptionResult]`
  - `TranscriptionCallback` 型: `((TranscriptionProgress) -> Bool?)?`
  - `TranscriptionProgress` は `.text`（現在の認識テキスト）、`.tokens`、`.windowId` を持つ
  - `DecodingOptions` で `language: "ja"` を明示指定可能
  - モデルは HuggingFace から自動ダウンロード。`modelRepo`、`model` で指定
- Implications:
  - `transcribe()` は `[Float]` 配列を受け取るため、`AVAudioPCMBuffer` から変換が必要（既存 MoonshineAdapter と同様のパターン）
  - バッチ処理のため、ストリーミング対応にはオーディオチャンクのバッファリングとタイマーベースの認識呼び出しが必要

### ストリーミング実現方式

- Context: WhisperKit でリアルタイム認識を実現する方式を検討
- Sources Consulted:
  - WhisperKit サンプルアプリ（whisper-app）の実装パターン
  - `AudioStreamTranscriber` クラスの公開 API 調査
- Findings:
  - WhisperKit 公式サンプルでは `AudioStreamTranscriber` が内部でチャンクバッファリングを行う
  - 一般的なパターン: 音声データを内部バッファに蓄積し、一定間隔で `transcribe()` を呼び出す
  - コールバック内で `TranscriptionProgress.text` を取得し、部分テキストとして利用
  - 最終テキストは `TranscriptionResult` から取得
- Implications:
  - アダプター内でオーディオバッファ（`[Float]`）を保持し、タイマーまたは一定サンプル数ごとに認識を実行する設計が適切
  - `startStream` の `onTextChanged` コールバックは `TranscriptionProgress.text` で実現
  - `finalize()` で蓄積済み全音声に対して最終認識を実行し、確定テキストを返す

### モデル選定と構成

- Context: 日本語認識に最適なモデルサイズと構成を決定
- Sources Consulted:
  - WhisperKit モデルリポジトリ（argmaxinc/whisperkit-coreml）
  - Whisper モデルの日本語ベンチマーク
- Findings:
  - 利用可能モデル: tiny, base, small, medium, large-v2, large-v3
  - 日本語精度: large > medium > small >> base > tiny
  - macOS ローカル実行ではメモリと速度のバランスから `small` または `base` が候補
  - `large-v3` は高精度だがメモリ消費が大きく、初回ロードが遅い
  - 初回起動時にモデルを HuggingFace からダウンロードする仕組みが組み込まれている
- Implications:
  - デフォルトモデルは `base` とし、AppSettings の `modelName` で変更可能にする
  - `DecodingOptions(language: "ja")` で日本語を明示指定し、言語検出オーバーヘッドを回避

### プラットフォーム要件

- Context: WhisperKit の動作要件と現行プロジェクトとの互換性確認
- Sources Consulted:
  - WhisperKit README、Package.swift
- Findings:
  - macOS 13+ 必須（Ventura 以降）
  - Swift 5.9+
  - 最新バージョン: v0.15.0
  - 依存: swift-transformers (huggingface)、swift-argument-parser (apple)
  - Xcode プロジェクトへの追加は Swift Package Manager 経由
- Implications:
  - 現行プロジェクトは Xcode ベース（.xcodeproj）のため、SPM 依存として WhisperKit を追加
  - MoonshineVoice 依存を WhisperKit に差し替え

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| プロトコルリネーム＋新アダプター追加 | `MoonshineAdapting` を汎用名にリネームし、WhisperKit アダプターを新規実装 | 最小変更、既存パターン活用 | リネーム時の全参照箇所の更新が必要 | 要件 4.1 に対応 |
| 新プロトコル作成＋旧プロトコル廃止 | 完全に新しいプロトコルを定義し、旧プロトコルを削除 | クリーンな設計 | 変更量が大きく互換性リスクあり | 過剰な変更 |
| Strategy パターンで動的切替 | 実行時にエンジンを切り替え可能にする | 柔軟性が高い | 現時点で不要な複雑さ | 将来検討 |

## Design Decisions

### Decision: プロトコルリネームによる汎用化

- Context: 要件 4 で Moonshine 固有の命名を排除し、汎用的な命名にする必要がある
- Alternatives Considered:
  1. `MoonshineAdapting` → `SpeechRecognitionAdapting` にリネーム
  2. 新プロトコル `SpeechEngineAdapting` を作成し、旧プロトコルを削除
- Selected Approach: `MoonshineAdapting` を `SpeechRecognitionAdapting` にリネーム
- Rationale: 既存の API シグネチャはエンジン非依存のため、名前変更のみで汎用化が達成できる。`initialize(modelName:)` / `startStream(...)` / `addAudio(_:)` / `finalize()` はいずれも WhisperKit でもそのまま実装可能
- Trade-offs: 全参照箇所（プロトコル定義、実装、テスト Mock、DI サイト）の更新が必要だが、機械的な置換で済む
- Follow-up: リネーム後のコンパイル確認

### Decision: チャンクバッファリング方式によるストリーミング模倣

- Context: WhisperKit はバッチ処理 API のため、リアルタイム認識にはアダプター側でバッファリングが必要
- Alternatives Considered:
  1. タイマーベース: 一定時間間隔で蓄積音声を認識
  2. サンプル数ベース: 一定サンプル数蓄積後に認識を実行
  3. 蓄積音声全体を毎回認識（累積方式）
- Selected Approach: 累積方式。`addAudio` ごとに内部バッファ `[Float]` に追加し、一定間隔（updateInterval 設定値）のタイマーで蓄積全体を `transcribe()` に渡す。コールバックから部分テキストを取得
- Rationale: 累積方式はウィンドウ境界での認識切れが発生しない。WhisperKit のサンプルアプリでも類似パターンを採用。処理速度は Moonshine より遅くなるが、精度を最優先する方針と合致
- Trade-offs: 音声が長くなるほど認識処理時間が増加。実用的には1セッション数十秒〜数分を想定しており許容範囲
- Follow-up: 長時間セッションでの性能を実装後に検証

### Decision: デフォルトモデルの選定

- Context: 日本語精度と処理速度のバランスでデフォルトモデルを決定
- Alternatives Considered:
  1. tiny: 高速だが日本語精度が低い（Moonshine と同等の問題）
  2. base: バランス型
  3. small: 高精度だがやや遅い
  4. large-v3: 最高精度だがメモリ・速度コスト大
- Selected Approach: `base` をデフォルトとし、AppSettings で変更可能にする
- Rationale: base は tiny に比べ大幅な精度向上があり、small ほどの処理コストは不要。ユーザーが精度を求める場合は設定で small 以上に変更可能
- Trade-offs: base の精度が不十分な場合はデフォルトを small に昇格する可能性あり

## Risks & Mitigations

- WhisperKit の初回モデルダウンロードに時間がかかる — 起動時に非同期ダウンロードを実行し、UI で状態を通知
- 長時間セッションで累積音声の認識が遅延する — セッションは通常短時間であり、実用上問題ない想定。必要に応じてウィンドウ方式への切り替えを検討
- MoonshineVoice 依存の除去による既存テストへの影響 — Mock が MoonshineAdapting プロトコルに依存しているため、リネームと同時に更新

## References

- [WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit) — メインリポジトリ、API リファレンス
- [WhisperKit CoreML Models](https://huggingface.co/argmaxinc/whisperkit-coreml) — 利用可能なモデル一覧
- [Whisper](https://github.com/openai/whisper) — OpenAI の元モデル、日本語ベンチマーク参考
