# Requirements Document

## Project Description (Input)

アプリ起動中、音声入力を受け付けない場合もマイクに影響を与えている

Google Meetで会議中に気がついたバグ。アプリの音声入力を受けていない時間にもマイクやスピーカーに影響を与えているようで、スピーカーは出てくる音が小さくなり、マイクは異常に小さく伝わってしまう。近づいて喋っているにも関わらずかなり声が小さく伝わってしまうという問題。

参照Issue: iss_4ae6a71cdcd6490a89cdf9c7735b1dee (KUCHIBI #19)

## Introduction

本ドキュメントは Kuchibi アプリが音声録音を行っていないアイドル状態においても `AVAudioSession` を保持し続け、Google Meet などの他アプリのマイク・スピーカー品質を劣化させるバグを解消するための要件を定義する。

現状の問題点:
- `AudioCaptureService` の `stopCapture()` は `AVAudioEngine.stop()` を呼ぶが、`AVAudioSession.sharedInstance().setActive(false)` を呼んでいない
- `inputNode` への tap が停止後も残存している可能性がある
- これにより他アプリが優先的にオーディオセッションを取得できず、音量・音質の低下が発生する

## Requirements

### Requirement 1: アイドル時のオーディオセッション解放

**Objective:** アプリユーザーとして、音声入力を行っていない間は他のアプリ（ビデオ会議ツール等）のマイクおよびスピーカーが正常に動作してほしい。

#### Acceptance Criteria

1. When `stopCapture()` が呼ばれた, the AudioCaptureService shall `AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)` を呼び出してセッションを解放する
2. When `cancelSession()` が呼ばれた, the AudioCaptureService shall オーディオセッションを即座に非アクティブ化する
3. While アプリが idle 状態である, the Kuchibi shall 他アプリのオーディオセッションを妨害しない
4. If `setActive(false)` の呼び出しが失敗した, then the AudioCaptureService shall エラーをログに記録し、次回の録音開始前に再試行する

### Requirement 2: 録音開始時のオーディオセッション明示的設定

**Objective:** アプリユーザーとして、録音開始時に確実かつ適切なオーディオセッション設定が行われてほしい。

#### Acceptance Criteria

1. When `startCapture()` が呼ばれた, the AudioCaptureService shall `AVAudioSession` のカテゴリを `.playAndRecord` または `.record`、モードを `.measurement` に明示的に設定してからエンジンを起動する
2. When `startCapture()` が呼ばれた, the AudioCaptureService shall `setActive(true)` を呼び出してセッションをアクティブ化する
3. If 録音開始時に `AVAudioSession` のアクティブ化が失敗した, then the AudioCaptureService shall エラーをスローし、エンジンを起動しない

### Requirement 3: `inputNode` の tap 適切なクリーンアップ

**Objective:** アプリユーザーとして、録音停止後にマイクリソースが完全に解放されてほしい。

#### Acceptance Criteria

1. When `stopCapture()` が呼ばれた, the AudioCaptureService shall `inputNode.removeTap(onBus:)` を呼び出して tap を除去する
2. When `stopCapture()` が呼ばれた, the AudioCaptureService shall `engine.stop()` の後に tap の除去とセッション非アクティブ化を順番に実行する
3. The AudioCaptureService shall 録音停止後に `inputNode` に残留する tap が存在しない状態を保証する

### Requirement 4: 他アプリへの影響の非回帰保証

**Objective:** アプリユーザーとして、Kuchibi を起動したまま Google Meet などのビデオ会議ツールを正常に使用できてほしい。

#### Acceptance Criteria

1. While Kuchibi が起動済みかつ idle 状態である, the Kuchibi shall 他アプリによるマイク使用を妨害しない
2. While Kuchibi が起動済みかつ idle 状態である, the Kuchibi shall システムのスピーカー出力音量に影響を与えない
3. When Kuchibi の録音セッションが終了した, the Kuchibi shall `AVAudioSession` の制御を速やかにシステムへ返却する
