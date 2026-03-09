# Implementation Plan

- [x] 1. 音声認識アダプタープロトコルを汎用名にリネームし全参照箇所を更新する
  - `MoonshineAdapting` を `SpeechRecognitionAdapting` にリネームする
  - プロトコル定義ファイルのファイル名も合わせて変更する
  - SpeechRecognitionService、テスト Mock、DI サイトなど全参照箇所を更新する
  - リネーム後にコンパイルが通ることを確認する
  - _Requirements: 4.1_

- [x] 2. WhisperKit アダプターを実装する
- [x] 2.1 WhisperKit SPM 依存を追加しモデル初期化機能を実装する
  - Xcode プロジェクトに WhisperKit の SPM 依存を追加する
  - `SpeechRecognitionAdapting` プロトコルに準拠する WhisperKit アダプタークラスを作成する
  - `initialize` メソッドで WhisperKit インスタンスを生成しモデルを読み込む
  - モデル名に基づいて適切な WhisperKit 構成を設定する（モデルリポジトリ、ダウンロード設定）
  - 初期化エラーを `KuchibiError.modelLoadFailed` にマッピングする
  - 初期化の成功・失敗を検証するテストを作成する
  - _Requirements: 1.1, 3.1_

- [x] 2.2 音声バッファリングとストリーミング認識を実装する
  - `addAudio` で `AVAudioPCMBuffer` から `[Float]` に変換し内部バッファに蓄積する
  - `startStream` でコールバックを保持し、定期的に認識を実行するタイマーを開始する
  - タイマー発火時に蓄積音声全体を WhisperKit の認識 API に渡し、コールバックで部分テキストを通知する
  - 日本語を明示指定した認識オプションを設定する
  - バッファへの追加と認識処理の並行実行を安全に制御する
  - 音声バッファリングと部分テキスト通知を検証するテストを作成する
  - _Requirements: 1.2, 2.1, 2.2_

- [x] 2.3 セッション終了時の最終認識処理を実装する
  - `finalize` でタイマーを停止し、蓄積済み全音声に対して最終認識を実行する
  - 認識結果の確定テキストを返し、内部状態をクリアする
  - `getPartialText` で最新の部分テキストを返す
  - 最終認識と状態クリアを検証するテストを作成する
  - _Requirements: 1.3_

- [x] 3. 既存パイプラインとの統合と Moonshine 依存の除去を行う
- [x] 3.1 DI サイトを WhisperKit アダプターに差し替え Moonshine 関連コードを除去する
  - アプリケーション起動時の DI サイトで WhisperKit アダプターを注入する
  - SpeechRecognitionService のデフォルトモデル名を WhisperKit 用に変更する
  - AppSettings のデフォルトモデル名を WhisperKit 用に変更する
  - MoonshineAdapter 実装ファイルと MoonshineVoice SPM 依存を除去する
  - _Requirements: 3.2, 4.2_

- [x] 3.2 テスト Mock を更新し既存パイプラインの互換性を検証する
  - テスト用 Mock クラスの名前とプロトコル準拠を更新する
  - 既存の SpeechRecognitionService テストが変更なしで通ることを確認する
  - SessionManager のテストがエンジン変更に影響されず全て通ることを確認する
  - RecognitionEvent ストリームが同一の形式で生成されることを検証する
  - _Requirements: 2.3, 3.2, 3.3_
