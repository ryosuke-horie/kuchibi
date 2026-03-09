# Requirements Document

## Introduction

音声入力セッション中のユーザーフィードバックを改善する。現在の画面上部中央のオーバーレイを廃止し、フォーカス中の画面の下部に細いバー型インジケーターを表示する。バーにはマイク入力の音量レベルをリアルタイムに反映するアニメーションを含め、音声が入力されていることを直感的に把握できるようにする。

## Requirements

### Requirement 1: 画面下部へのバー型インジケーター表示

Objective: ユーザーとして、音声入力中にフォーカス画面の下部に控えめなバーを表示してほしい。作業を邪魔せず、録音状態を一目で確認できるようにするため。

#### Acceptance Criteria
1. When 音声入力セッションが開始された, the kuchibi shall フォーカス中の画面の最下部に横長のバー型インジケーターを表示する
2. When 音声入力セッションが終了した, the kuchibi shall バー型インジケーターを非表示にする
3. The kuchibi shall バー型インジケーターを他のウィンドウよりも前面に表示し、フォーカスを奪わない
4. The kuchibi shall バー型インジケーターの高さを控えめなサイズ（画面の邪魔にならない程度）に制限する

### Requirement 2: 音量レベルのリアルタイム可視化

Objective: ユーザーとして、マイクに音声が入力されていることをバーの動きで視覚的に確認したい。音声が正しくキャプチャされているかをリアルタイムに把握するため。

#### Acceptance Criteria
1. While 音声入力セッションが進行中, the kuchibi shall マイク入力の音量レベルをリアルタイムに取得してバーの表示に反映する
2. When マイクに音声が入力された, the kuchibi shall 音量レベルに応じてバーのアニメーション（波形・振幅等）を変化させる
3. While マイクへの入力が無音状態, the kuchibi shall バーのアニメーションを最小限の状態（静止またはごく小さい動き）で表示する
4. The kuchibi shall 音量レベルの更新を十分な頻度（滑らかなアニメーションを維持できる程度）で行う

### Requirement 3: 認識テキストの表示

Objective: ユーザーとして、音声認識の途中結果をバー上で確認したい。発話内容が正しく認識されているかをリアルタイムに把握するため。

#### Acceptance Criteria
1. While 音声認識が進行中, the kuchibi shall 認識途中テキスト（partialText）をバー内に表示する
2. When 認識途中テキストが更新された, the kuchibi shall バー内の表示テキストをリアルタイムに更新する
3. If 認識途中テキストが空, the kuchibi shall テキスト表示領域を非表示にするか、プレースホルダーを表示する

### Requirement 4: 既存オーバーレイの置き換え

Objective: ユーザーとして、画面上部の旧オーバーレイの代わりにバー型インジケーターを使いたい。統一された視覚フィードバックを受け取るため。

#### Acceptance Criteria
1. The kuchibi shall 既存の画面上部中央のオーバーレイ表示を新しいバー型インジケーターに置き換える
2. The kuchibi shall 既存のSessionManagerとの状態連携（recording/idle/processing）を維持する
