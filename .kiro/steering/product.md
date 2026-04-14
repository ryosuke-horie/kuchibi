# Product Overview

Kuchibi は macOS 向けの完全個人用音声入力アプリ。バックグラウンドに常駐し、ホットキー（Cmd+Shift+Space）で録音を開始・停止し、WhisperKit による音声認識結果を日本語テキストとして出力する。

## Core Capabilities

- グローバルホットキーによる録音トグル（メニューバー常駐）
- WhisperKit によるローカル音声認識（tiny / base / small / medium / large-v2 / large-v3）
- 認識結果の自動出力（クリップボードコピー / アクティブアプリへ Cmd+V 自動入力）
- 音声前処理（16kHz モノラルリサンプリング + VAD）と日本語向けテキスト後処理（フィラー除去など）
- セッション状態を示すフローティングバー UI

## Target Use Cases

- 開発者本人（単一ユーザー）がチャット・ドキュメント・コードコメントを音声で素早く入力する
- クリップボードを壊さずに他アプリへ直接入力する（directInput モード）
- ローカル完結で外部 API を使わず、プライバシーを保つ

## Value Proposition

- 配布前提のプロダクトではなく、個人最適化された攻めた実装が許される（セキュリティ・互換性に強い制約をかけない）
- すべての処理がローカル完結（クラウド不要、ネットワーク不要）
- Whisper モデルサイズを用途に応じて切り替え可能

---
_Focus on patterns and purpose, not exhaustive feature lists_
