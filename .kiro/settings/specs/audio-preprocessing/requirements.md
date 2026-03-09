# Requirements Document

## Introduction

kuchibi の音声キャプチャパイプラインに前処理を追加し、音声認識エンジンに渡す入力品質を向上させる。現在はマイクから取得した生の音声データをそのまま moonshine に渡しているが、環境ノイズの影響を受けやすく、無音区間も含めてすべて認識エンジンに送信している。macOS の音声処理機能（Voice Processing）によるノイズ抑制と、エネルギーベースの音声アクティビティ検出（VAD）を導入し、認識精度と処理効率を改善する。

## Requirements

### Requirement 1: ノイズ抑制

Objective: ユーザーとして、周囲にノイズがある環境でも正確に文字起こしされてほしい。環境音によって認識精度が下がることを防ぐため。

#### Acceptance Criteria
1. The kuchibi shall macOS の Voice Processing 機能を使用してマイク入力にノイズ抑制を適用する
2. The kuchibi shall ノイズ抑制のオン・オフを設定画面から切り替え可能にする
3. When ノイズ抑制が有効な状態で音声入力が行われた, the kuchibi shall ノイズ抑制処理後の音声データを認識エンジンに渡す
4. When ノイズ抑制が無効に設定された, the kuchibi shall 生の音声データをそのまま認識エンジンに渡す

### Requirement 2: 音声アクティビティ検出（VAD）

Objective: ユーザーとして、発話していない区間の無駄な処理を省き、認識精度と効率を高めたい。無音区間のノイズが誤認識の原因になることを防ぐため。

#### Acceptance Criteria
1. While 音声入力セッションが進行中, the kuchibi shall 各音声バッファのエネルギーレベルを計算し、発話区間と無音区間を判別する
2. When VAD が無音区間と判定した, the kuchibi shall そのバッファを認識エンジンに送信しない
3. The kuchibi shall VAD のオン・オフを設定画面から切り替え可能にする
4. The kuchibi shall VAD の感度閾値を設定画面から調整可能にする

### Requirement 3: 16kHz リサンプリング

Objective: ユーザーとして、使用するマイクに関わらず最適な音声フォーマットで認識処理されてほしい。サンプルレートの不一致による精度低下を防ぐため。

#### Acceptance Criteria
1. The kuchibi shall マイク入力の音声を 16kHz モノラルにリサンプリングしてから認識エンジンに渡す
2. The kuchibi shall リサンプリングに AVAudioConverter を使用する
3. When マイクの出力フォーマットが既に 16kHz モノラルの場合, the kuchibi shall リサンプリングをスキップする
