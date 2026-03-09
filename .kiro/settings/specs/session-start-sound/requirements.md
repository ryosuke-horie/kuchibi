# Requirements Document

## Introduction
複数画面運用時に録音セッションの開始がわかりにくい問題を解決するため、セッション開始時にシステムサウンドを再生する。録音バーが表示されていない画面を見ている場合でも、音で開始を認識できるようにする。

## Requirements

### Requirement 1: セッション開始時のサウンド再生

Objective: ユーザーとして、録音セッションの開始時に音が鳴ってほしい。複数画面を使っていて録音バーが見えなくても、セッションが開始されたことを認識できるため。

#### Acceptance Criteria
1. When ホットキーが押されて録音セッションが開始された場合, the kuchibi shall システムサウンドを再生する
2. The kuchibi shall サウンド再生が録音処理をブロックしない
