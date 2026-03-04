# Implementation Plan

- [x] 1. (P) AppSettings に前処理設定プロパティを追加する
  - ノイズ抑制のオン・オフ（デフォルト: 有効）、VAD のオン・オフ（デフォルト: 有効）、VAD 感度閾値（デフォルト: 0.01、範囲 0.0-1.0）の3プロパティを追加する
  - 各プロパティを UserDefaults に即座に永続化し、起動時に復元する
  - 閾値の範囲外バリデーションを実装し、不正値はデフォルトに戻す
  - `resetToDefaults()` に新規プロパティを含める
  - 既存の AppSettingsTests を拡張し、新規プロパティのデフォルト値・永続化・復元・バリデーション・リセットを検証する
  - _Requirements: 1.2, 2.3, 2.4_

- [x] 2. (P) AudioCaptureService に Voice Processing ノイズ抑制を追加する
  - AudioCapturing プロトコルの `startCapture` にノイズ抑制有効フラグのパラメータを追加する（デフォルト値で後方互換性を維持）
  - エンジン起動前に `inputNode.setVoiceProcessingEnabled` を呼び出し、有効化後にフォーマットを再取得してから tap をインストールする
  - Voice Processing の有効化に失敗した場合はログ出力し、ノイズ抑制なしで続行する
  - モックやテストのプロトコル準拠を更新する
  - _Requirements: 1.1, 1.3, 1.4_

- [x] 3. AudioPreprocessor を新設する
- [x] 3.1 リサンプリング機能を実装する
  - AudioPreprocessing プロトコルを定義し、音声ストリームを受け取って前処理済みストリームを返すインターフェースを作る
  - AVAudioConverter のコールバック形式を使用して、入力バッファを 16kHz モノラル Float32 に変換する
  - 入力フォーマットが既に 16kHz モノラルの場合はリサンプリングをスキップする
  - _Requirements: 3.1, 3.2, 3.3_

- [x] 3.2 VAD フィルタリング機能を実装する
  - リサンプリング後のバッファに対して RMS エネルギーを計算し、閾値と比較して発話区間を判別する
  - 閾値以下のバッファは出力ストリームに含めないようにフィルタリングする
  - VAD が無効の場合はフィルタリングをスキップして全バッファを通す
  - _Requirements: 2.1, 2.2_

- [x] 4. SessionManager で前処理パイプラインを統合する
  - SessionManager の初期化時に AudioPreprocessor を依存注入で受け取る
  - `startSession` 内で、キャプチャストリームを AudioPreprocessor に通してから認識サービスに渡す
  - ノイズ抑制設定を `startCapture` のパラメータとして AppSettings から渡す
  - VAD の設定値（有効フラグ、閾値）を AudioPreprocessor に AppSettings から渡す
  - 既存の SessionManagerTests をプロトコル変更に合わせて更新する
  - _Requirements: 1.3, 2.2_

- [x] 5. SettingsView に前処理設定 UI を追加する
  - 「音声認識」タブに前処理セクションを追加する
  - ノイズ抑制の Toggle コントロールを配置する
  - VAD の Toggle コントロールと感度閾値の Slider（0.0-1.0）を配置する
  - VAD が無効時は閾値 Slider を非活性にする
  - _Requirements: 1.2, 2.3, 2.4_

- [x] 6. AudioPreprocessor のユニットテストを追加する
- [x] 6.1 (P) リサンプリングのテストを追加する
  - 48kHz のテストバッファを入力し、出力が 16kHz モノラルフォーマットであることを検証する
  - 入力が既に 16kHz モノラルの場合にリサンプリングがスキップされることを検証する
  - _Requirements: 3.1, 3.3_

- [x] 6.2 (P) VAD フィルタリングのテストを追加する
  - 閾値以上のエネルギーを持つバッファが通過することを検証する
  - 閾値以下のバッファがフィルタリングされることを検証する
  - VAD 無効時に全バッファが通過することを検証する
  - _Requirements: 2.1, 2.2_
