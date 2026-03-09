# Requirements Document

## Introduction
セッションのライフサイクルをホットキーによる手動制御に統一する。現在は無音タイムアウトでセッションが自動停止するが、ホットキー2回目の押下まで録音を継続し、停止時に認識結果を一括入力する動作に変更する。

## Requirements

### Requirement 1: ホットキーによるセッション手動制御

Objective: ユーザーとして、ホットキーで録音の開始と停止を完全に制御したい。話の途中で自動停止されず、話し終わるタイミングを自分で決められるため。

#### Acceptance Criteria
1. When ホットキーが1回目に押された場合, the kuchibi shall 録音セッションを開始し音声キャプチャを開始する
2. While セッションが録音中である場合, the kuchibi shall ホットキーが再度押されるまで録音を継続する
3. When セッションが録音中にホットキーが2回目に押された場合, the kuchibi shall 録音を停止し、蓄積された認識結果を設定された出力モードで一括入力する

### Requirement 2: 無音タイムアウトの無効化

Objective: ユーザーとして、録音中に無音が続いてもセッションが自動停止しないようにしたい。考えながら話す際に途中で切れないため。

#### Acceptance Criteria
1. While セッションが録音中である場合, the kuchibi shall 無音タイムアウトによる自動停止を行わない
2. The kuchibi shall 無音タイムアウトの設定項目を設定UIから削除する
