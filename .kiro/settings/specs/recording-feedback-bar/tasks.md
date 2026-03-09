# Implementation Plan

- [x] 1. 音量レベル計算基盤の実装
- [x] 1.1 (P) AudioCapturing プロトコルに音量レベルプロパティを追加する
  - `currentAudioLevel` プロパティをプロトコルに追加し、0.0〜1.0 の範囲で現在の音量レベルを返すようにする
  - モックの AudioCapturing 実装も合わせて更新する
  - _Requirements: 2.1_
  - _Contracts: AudioCaptureService_

- [x] 1.2 AudioCaptureService でPCMバッファからRMS音量レベルを計算する
  - オーディオタップのコールバック内で、バッファの floatChannelData からRMS値を算出する
  - 小さい声でも反応するよう感度補正を加え、0.0〜1.0 に正規化する
  - キャプチャ停止時に音量レベルを 0.0 にリセットする
  - 1.1 のプロトコル変更に依存
  - _Requirements: 2.1, 2.4_
  - _Contracts: AudioCaptureService_

- [x] 2. SessionManager への音量レベル公開機能の追加
- [x] 2.1 SessionManager に audioLevel Published プロパティを追加する
  - `@Published audioLevel: Float` を追加し、録音中に AudioCaptureService の音量レベルを定期的に読み取って公開する
  - セッション終了時に 0.0 にリセットする
  - 既存の状態遷移（idle/recording/processing）との整合性を維持する
  - タスク1 に依存
  - _Requirements: 2.1, 4.2_

- [x] 3. バー型インジケーターUIの実装
- [x] 3.1 (P) FeedbackBarView を実装する
  - 音量レベルに応じて高さが変化する複数の縦棒によるアニメーション表示を実装する
  - 認識途中テキスト（partialText）をバー内に表示し、テキストが空の場合は非表示にする
  - 高さを控えめに制限し、半透明マテリアル背景で他のコンテンツを邪魔しないデザインにする
  - 無音時はバーを最小高さで表示し、音声入力時は音量に連動してアニメーションする
  - _Requirements: 1.4, 2.2, 2.3, 3.1, 3.2, 3.3_

- [x] 3.2 FeedbackBarWindowController を実装する
  - NSWindow を画面最下部に全幅で配置し、フローティングレベルでフォーカスを奪わないウィンドウを生成する
  - SessionManager の状態を Combine で監視し、recording 時に表示、それ以外で非表示にする
  - 全 Space で表示され、マウスイベントを無視する設定を行う
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 4. 既存オーバーレイの置き換えと統合
- [x] 4.1 KuchibiApp のオーバーレイ配線を新しいバー型インジケーターに切り替える
  - KuchibiApp 内の OverlayWindowController を FeedbackBarWindowController に置き換える
  - 既存の RecordingOverlayView と OverlayWindowController を削除する
  - SessionManager との状態連携が維持されていることを確認する
  - タスク2, 3 に依存
  - _Requirements: 4.1, 4.2_

- [x] 5. テストとリグレッション確認
- [x] 5.1 音量レベル関連のユニットテストを追加する
  - MockAudioCaptureService が currentAudioLevel を返せることを確認するテストを追加する
  - SessionManager の audioLevel が recording 時に更新され、idle 時に 0.0 であることを確認するテストを追加する
  - 既存の全テストがリグレッションなく通ることを確認する
  - _Requirements: 2.1_
