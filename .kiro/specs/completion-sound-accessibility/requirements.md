# Requirements Document

## Project Description (Input)
クリップボード/自動入力完了時の通知音 + アクセシビリティ権限の永続的リクエスト (KUCHIBI-16)

## Introduction
ホットキー2回目押下後、音声認識結果のクリップボードコピーまたは自動ペーストが完了したタイミングで通知音を再生する。また、自動入力モード（directInput / autoInput）に必要なアクセシビリティ権限が未取得の場合、アプリ起動時またはユーザー操作時にシステムダイアログを通じて権限を永続的にリクエストする機能を実装する。

## Requirements

### Requirement 1: 出力完了通知音の再生

**Objective:** 個人ユーザーとして、クリップボードコピーまたは自動ペーストが完了したときに通知音を聞きたい。そうすることで、画面を見ずに出力完了を認識できる。

#### Acceptance Criteria

1. When クリップボードへのコピー（clipboard モード）が完了したとき、Kuchibi shall `sessionSoundEnabled` 設定が有効であれば完了音を再生する
2. When 自動ペースト（directInput / autoInput モード）のキー送信が完了したとき、Kuchibi shall `sessionSoundEnabled` 設定が有効であれば完了音を再生する
3. The Kuchibi shall 完了音の再生を出力処理が終わった後に行う（出力前には再生しない）
4. If `NSSound(named:)` によるシステムサウンドの取得に失敗したとき、Kuchibi shall 代替サウンドAPIを使用して完了音を再生する
5. Where `sessionSoundEnabled` が無効のとき、Kuchibi shall 完了音を再生しない

### Requirement 2: アクセシビリティ権限の永続的リクエスト

**Objective:** 個人ユーザーとして、アプリ起動時や自動入力時に自動でアクセシビリティ権限のダイアログが表示されてほしい。そうすることで、手動でシステム設定を開かずに権限を付与できる。

#### Acceptance Criteria

1. When アプリ起動時にアクセシビリティ権限（`AXIsProcessTrusted`）が未取得のとき、Kuchibi shall macOS システムの権限リクエストダイアログ（`AXIsProcessTrustedWithOptions`）を表示する
2. When ユーザーが directInput または autoInput モードで録音を停止したとき and アクセシビリティ権限が未取得のとき、Kuchibi shall 権限リクエストダイアログを再度表示する
3. If アクセシビリティ権限が付与されていないとき、Kuchibi shall クリップボードモードにフォールバックしてテキストをコピーする
4. If アクセシビリティ権限が付与されていないとき、Kuchibi shall ユーザーに権限が不足していることとクリップボードへのフォールバックを通知する
5. The Kuchibi shall アクセシビリティ権限の状態をセッション開始前に確認する

### Requirement 3: 通知音の設定制御

**Objective:** 個人ユーザーとして、通知音のON/OFFを設定から制御したい。そうすることで、状況に応じて音の有無を選択できる。

#### Acceptance Criteria

1. The Kuchibi shall 既存の `sessionSoundEnabled` 設定で完了音のON/OFFを制御する
2. Where `sessionSoundEnabled` が有効のとき、Kuchibi shall セッション開始音（Tink）と完了音の両方を再生する
3. Where `sessionSoundEnabled` が無効のとき、Kuchibi shall セッション開始音と完了音の両方を再生しない
