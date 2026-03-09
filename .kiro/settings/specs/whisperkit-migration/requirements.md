# Requirements Document

## Introduction

現在の音声認識エンジン Moonshine (moonshine-tiny-ja) は日本語認識精度が不十分であり、特に漢語（音読み熟語）や文脈依存の表現で誤認識が頻発する。本機能では、音声認識エンジンを WhisperKit に差し替え、既存のアダプターパターン（MoonshineAdapting プロトコル）を汎用化して音声認識バックエンドを交換可能にする。多少の処理速度低下を許容しつつ、実用的な日本語音声入力精度を実現する。

## Requirements

### Requirement 1: WhisperKit アダプターの実装

Objective: ユーザーとして、WhisperKit ベースの音声認識が利用できるようにしたい。これにより、Moonshine より高精度な日本語認識が実現される。

#### Acceptance Criteria

1.1. When アプリケーションが起動した, the SpeechRecognitionService shall WhisperKit のモデルを読み込み、認識可能な状態にする
1.2. While セッションが recording 状態である, the WhisperKit アダプター shall 16kHz モノラル PCM Float32 形式の音声バッファを受け付けて認識処理を行う
1.3. When セッションが停止した, the WhisperKit アダプター shall 未処理の音声データを最終処理し、確定テキストを返す

### Requirement 2: ストリーミング認識とイベント生成

Objective: ユーザーとして、発話中にリアルタイムで認識テキストが表示されるようにしたい。これにより、認識状況を確認しながら発話できる。

#### Acceptance Criteria

2.1. While 音声認識が進行中である, the WhisperKit アダプター shall 部分テキストを定期的に onTextChanged コールバックで通知する
2.2. When 認識エンジンがテキストを確定した, the WhisperKit アダプター shall onLineCompleted コールバックで確定テキストを通知する
2.3. When ストリーム終了時に onLineCompleted が一度も発行されていない, the SpeechRecognitionService shall finalize の結果を lineCompleted として発行する

### Requirement 3: 既存パイプラインとの互換性

Objective: ユーザーとして、エンジン差し替え後も既存の機能（テキスト蓄積、後処理、クリップボード出力、直接入力）がそのまま動作するようにしたい。

#### Acceptance Criteria

3.1. The WhisperKit アダプター shall 既存の音声認識アダプタープロトコルに準拠する
3.2. The SpeechRecognitionService shall アダプター差し替え後も同じ RecognitionEvent ストリームを生成する
3.3. The SessionManager shall エンジン変更による修正なしに、テキスト蓄積・後処理・出力を引き続き実行する

### Requirement 4: プロトコルの汎用化

Objective: 開発者として、音声認識アダプタープロトコルが特定のエンジンに依存しない汎用的な名前と設計になっていてほしい。これにより、将来のエンジン差し替えが容易になる。

#### Acceptance Criteria

4.1. The 音声認識アダプタープロトコル shall Moonshine 固有の命名ではなく、汎用的な命名を使用する
4.2. When 新しいアダプターが実装された, the アプリケーション shall 依存注入により使用するアダプターを切り替えられる
