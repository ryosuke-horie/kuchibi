# Requirements Document

## Project Description (Input)
音声入力受け時にエスケープする方法を用意

escキーをホットキー1回押している状態で押したら音声入力を即時に切り上げて入力とかも行わないようにするようにしたい

（参照: KUCHIBI-17 https://dosen-web.ryosuke-horie37.workers.dev/issues/iss_d37eedfb38b84022a0fdac646bab76f3）

## Introduction

音声入力セッション中（recording / processing 状態）にユーザーが ESC キーを押すことで、録音と認識を即時キャンセルし、テキスト出力を一切行わずにアイドル状態へ戻す機能を実装する。

既存の通常終了フロー（ホットキーによる停止→テキスト出力）とは独立したキャンセル専用パスとして設計し、ユーザーが誤入力・不要な音声をキャンセルしたい場合に確実に機能する手段を提供する。

## Requirements

### Requirement 1: ESC キーによるセッションキャンセルトリガー

**Objective:** 個人ユーザーとして、音声入力セッション中に ESC キーを押すことで即時キャンセルできるようにしたい。そうすることで誤って録音を開始した場合や不要な音声を入力した場合に、テキストが出力されず安心して取り消せる。

#### Acceptance Criteria
1. While `recording` 状態のとき、When ESC キーが押下された, the Kuchibi shall セッションをキャンセルしてアイドル状態に遷移する
2. While `processing` 状態のとき、When ESC キーが押下された, the Kuchibi shall 認識処理を中断しアイドル状態に遷移する
3. While `idle` 状態のとき、When ESC キーが押下された, the Kuchibi shall 何も行わない（ESC キーイベントを無視する）
4. The Kuchibi shall ESC キーのグローバル監視をアプリ起動中は常時維持する

### Requirement 2: テキスト出力の完全抑止

**Objective:** 個人ユーザーとして、ESC キーでキャンセルしたときに一切のテキストが出力されないことを保証したい。そうすることで誤入力が現在フォーカスしているアプリに貼り付けられる事故を防ぐことができる。

#### Acceptance Criteria
1. When ESC キャンセルが実行された, the Kuchibi shall 蓄積済みテキスト（`accumulatedLines`）を破棄してテキスト出力を行わない
2. When ESC キャンセルが実行された, the Kuchibi shall 部分テキスト（`partialText`）をクリアする
3. If 音声認識サービスが認識処理中であっても ESC が押された場合, the Kuchibi shall その結果をテキスト出力に使用しない
4. The Kuchibi shall キャンセル時に OutputManager の出力メソッドを呼び出さない

### Requirement 3: 即時かつクリーンな状態リセット

**Objective:** 個人ユーザーとして、ESC キャンセル後にアプリが正常なアイドル状態に戻ることを期待する。そうすることでキャンセル後すぐに再度ホットキーで音声入力を開始できる。

#### Acceptance Criteria
1. When ESC キャンセルが実行された, the Kuchibi shall 音声キャプチャを即時停止する（`audioService.stopCapture()` を呼び出す）
2. When ESC キャンセルが実行された, the Kuchibi shall 進行中の録音タスク（`recordingTask`）をキャンセルする
3. When ESC キャンセルが実行された, the Kuchibi shall `state` を `.idle` に設定する
4. When ESC キャンセルが実行された, the Kuchibi shall `audioLevel` を 0.0 にリセットする
5. The Kuchibi shall キャンセル完了後に通常の `startSession()` が正常に動作できる状態を保証する

### Requirement 4: キャンセル時のユーザーフィードバック

**Objective:** 個人ユーザーとして、ESC キャンセルが正常に受け付けられたことを確認できるフィードバックが欲しい。そうすることで操作が意図通りに機能したかを即座に把握できる。

#### Acceptance Criteria
1. When ESC キャンセルが実行された, the Kuchibi shall キャンセルを示すシステムサウンドを再生する（セッション終了音とは区別できる音が望ましい）
2. Where セッションサウンドが無効化されている設定の場合, the Kuchibi shall サウンドを再生しない
3. The Kuchibi shall フィードバックバー（FeedbackBar）の表示をキャンセルと同時にクリアまたは非表示にする
