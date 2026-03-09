# Requirements Document

## Introduction

macOS上でバックグラウンド常駐し、ホットキーで呼び出して日本語音声をリアルタイムにテキスト変換する個人用音声入力アプリケーション。moonshineモデルを使用したローカル完結型の音声認識により、外部サービスへの依存なく動作する。認識結果はクリップボードへのコピーやアクティブなアプリケーションへの直接入力として出力される。

## Requirements

### Requirement 1: バックグラウンド常駐

Objective: ユーザーとして、アプリケーションが常にバックグラウンドで待機していてほしい。必要なときにすぐ音声入力を開始できるようにするため。

#### Acceptance Criteria
1. When アプリケーションが起動された, the kuchibi shall メニューバーに常駐アイコンを表示する
2. While アプリケーションが起動中, the kuchibi shall Dockにウィンドウを表示せずバックグラウンドで動作する
3. When メニューバーアイコンがクリックされた, the kuchibi shall アプリケーションの状態メニュー（音声認識の状態、終了ボタン等）を表示する
4. When macOSが再起動された場合でも, the kuchibi shall ログイン項目として自動起動できる設定を提供する

### Requirement 2: ホットキーによる音声入力制御

Objective: ユーザーとして、グローバルホットキーで音声入力の開始・停止を制御したい。どのアプリケーションを使用中でも即座に音声入力を呼び出せるようにするため。

#### Acceptance Criteria
1. When ユーザーがグローバルホットキーを押下した, the kuchibi shall 音声入力セッションを開始する
2. When 音声入力中にユーザーがホットキーを再度押下した, the kuchibi shall 音声入力セッションを終了し認識結果を確定する
3. While 他のアプリケーションがフォーカスされている状態でも, the kuchibi shall グローバルホットキーを受け付ける
4. When 音声入力セッションが開始された, the kuchibi shall 録音中であることを視覚的に示すインジケーターを表示する

### Requirement 3: 音声認識（moonshine）

Objective: ユーザーとして、日本語の発話をローカルのAIモデルで正確にテキスト変換してほしい。外部サービスに依存せずプライバシーを保ちながら音声入力を行うため。

#### Acceptance Criteria
1. The kuchibi shall moonshineモデルを使用してローカルで音声認識を実行する
2. When ユーザーが日本語で発話した, the kuchibi shall 発話内容を日本語テキストに変換する
3. The kuchibi shall すべての音声認識処理をローカルマシン上で完結させ、外部APIへの送信を行わない
4. When 音声入力セッションが開始された, the kuchibi shall マイクからの音声キャプチャを開始する
5. If マイクへのアクセスが許可されていない場合, the kuchibi shall ユーザーにマイク権限の付与を促す通知を表示する

### Requirement 4: テキスト出力

Objective: ユーザーとして、認識されたテキストをクリップボードへのコピーやアクティブアプリへの直接入力など、複数の方法で利用したい。用途に応じた柔軟なテキスト活用を行うため。

#### Acceptance Criteria
1. When 音声認識が完了した, the kuchibi shall 認識結果テキストをシステムクリップボードにコピーする
2. When 音声認識が完了した, the kuchibi shall アクティブなテキストフィールドに認識結果を直接入力（ペースト）する出力モードを提供する
3. While 音声認識が進行中, the kuchibi shall 認識途中のテキストをストリーミング表示する
4. When 出力モードが「直接入力」に設定されている場合に音声認識が完了した, the kuchibi shall フォーカス中のアプリケーションのカーソル位置にテキストを挿入する

### Requirement 5: エラーハンドリングとフィードバック

Objective: ユーザーとして、音声認識の成否や問題発生時に適切なフィードバックを受け取りたい。操作結果を把握し、問題があれば対処できるようにするため。

#### Acceptance Criteria
1. If 音声認識モデルの読み込みに失敗した場合, the kuchibi shall エラー内容をmacOS通知で表示する
2. If マイクからの音声が検出されないまま一定時間が経過した場合, the kuchibi shall 音声入力セッションを自動的にタイムアウト終了する
3. When 音声認識が正常に完了した, the kuchibi shall 完了を示すサウンドまたは視覚的フィードバックを提供する
4. If 音声認識処理中にエラーが発生した場合, the kuchibi shall エラー内容をユーザーに通知し、音声入力セッションを安全に終了する
