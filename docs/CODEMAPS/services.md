# サービス層 コードマップ

最終更新: 2026-03-07

## アーキテクチャ

```
SessionManagerImpl
    ├── AudioCapturing          (AudioCaptureServiceImpl)
    │       └── AsyncStream<AVAudioPCMBuffer>
    ├── AudioPreprocessing      (AudioPreprocessorImpl)
    │       ├── リサンプリング: 任意サンプルレート → 16kHz モノラル（線形補間）
    │       └── VAD: RMS がしきい値未満のバッファを破棄
    ├── SpeechRecognizing       (SpeechRecognitionServiceImpl)
    │       └── SpeechRecognitionAdapting (WhisperKitAdapter)
    │               └── WhisperKit（500ms 間隔の定期認識ループ）
    ├── TextPostprocessing      (TextPostprocessorImpl)
    │       ├── 先頭・末尾空白除去
    │       ├── 連続スペース正規化
    │       ├── 日本語フィラー除去（えーと、あー等）
    │       ├── 日本語文字間スペース除去
    │       └── 3文字以上の繰り返しフレーズ集約
    ├── OutputManaging          (OutputManagerImpl)
    │       └── ClipboardServicing (ClipboardServiceImpl)
    ├── NotificationServicing   (NotificationServiceImpl)
    ├── SessionMonitoring       (SessionMonitoringServiceImpl)
    └── AppSettings
```

## 主要モジュール

| モジュール | 用途 | 場所 |
|:--|:--|:--|
| `SessionManagerImpl` | セッションライフサイクル管理・状態機械 | `Sources/Services/SessionManager.swift` |
| `AudioCaptureServiceImpl` | AVAudioEngine によるマイク音声キャプチャ | `Sources/Services/AudioCaptureService.swift` |
| `AudioPreprocessorImpl` | リサンプリング（16kHz モノラル）・VAD | `Sources/Services/AudioPreprocessor.swift` |
| `SpeechRecognitionServiceImpl` | 音声ストリームを RecognitionEvent に変換 | `Sources/Services/SpeechRecognitionService.swift` |
| `WhisperKitAdapter` | WhisperKit ライブラリのラッパー | `Sources/Services/WhisperKitAdapter.swift` |
| `TextPostprocessorImpl` | 認識テキストの後処理 | `Sources/Services/TextPostprocessor.swift` |
| `OutputManagerImpl` | OutputMode に応じたテキスト出力 | `Sources/Services/OutputManager.swift` |
| `ClipboardServiceImpl` | NSPasteboard + CGEvent による Cmd+V | `Sources/Services/ClipboardService.swift` |
| `NotificationServiceImpl` | macOS ユーザー通知の送信 | `Sources/Services/NotificationService.swift` |
| `SessionMonitoringServiceImpl` | セッション統計・監視 | `Sources/Services/SessionMonitoringService.swift` |
| `HotKeyControllerImpl` | グローバルホットキー登録（Cmd+Shift+Space） | `Sources/Services/HotKeyController.swift` |
| `AppSettings` | 全設定値の UserDefaults 永続化 | `Sources/Services/AppSettings.swift` |

## ドメインモデル

| モデル | 値 | 場所 |
|:--|:--|:--|
| `SessionState` | `idle` / `recording` / `processing` | `Sources/Models/SessionState.swift` |
| `RecognitionEvent` | `lineStarted` / `textChanged(String)` / `lineCompleted(String)` | `Sources/Models/RecognitionEvent.swift` |
| `OutputMode` | `clipboard` / `directInput` / `autoInput` | `Sources/Models/OutputMode.swift` |
| `WhisperModel` | `tiny` / `base` / `small` / `medium` / `large-v2` / `large-v3` | `Sources/Models/WhisperModel.swift` |
| `KuchibiError` | `modelLoadFailed` / `microphonePermissionDenied` / `microphoneUnavailable` 等 | `Sources/Models/KuchibiError.swift` |

## セッションライフサイクル

```
idle ──(toggleSession)──► recording ──(toggleSession)──► processing ──► idle
 ▲                                                                        │
 └────────────────────────────────────────────────────────────────────────┘
```

- `idle → recording`: 音声キャプチャ開始、前処理・認識ストリーム起動
- `recording → processing`: 音声キャプチャ停止、最終認識待機
- `processing → idle`: テキスト出力、セッション完了音

## RecognitionEvent のフロー

```
SpeechRecognitionService
    │
    ├─ lineStarted                  認識行の開始（audioLevel 更新）
    ├─ textChanged(partial: String) 中間認識テキスト（partialText 更新）
    └─ lineCompleted(final: String) 確定テキスト → TextPostprocessor → accumulatedLines に追記

セッション終了時: accumulatedLines.joined("\n") → OutputManager
```

## OutputMode の動作

| モード | 動作 |
|:--|:--|
| `clipboard` | NSPasteboard にコピーのみ |
| `directInput` | Cmd+V 送信後、元のクリップボード内容を復元 |
| `autoInput` | Cmd+V 送信、クリップボードは上書きのまま |

## AppSettings の設定項目

| 設定 | デフォルト | 型 |
|:--|:--|:--|
| `outputMode` | `.autoInput` | `OutputMode` |
| `model` | `.base` | `WhisperModel` |
| `updateInterval` | `0.5` 秒 | `Double` |
| `bufferSize` | `1024` | `Int` |
| `noiseSuppressionEnabled` | `true` | `Bool` |
| `vadEnabled` | `true` | `Bool` |
| `vadThreshold` | `0.01` | `Float` |
| `textPostprocessingEnabled` | `true` | `Bool` |
| `monitoringEnabled` | `true` | `Bool` |
| `sessionSoundEnabled` | `true` | `Bool` |

## サービスプロトコル一覧

| プロトコル | 実装 | 場所 |
|:--|:--|:--|
| `AudioCapturing` | `AudioCaptureServiceImpl` | `Sources/Services/Protocols/AudioCapturing.swift` |
| `AudioPreprocessing` | `AudioPreprocessorImpl` | `Sources/Services/Protocols/AudioPreprocessing.swift` |
| `SpeechRecognizing` | `SpeechRecognitionServiceImpl` | `Sources/Services/Protocols/SpeechRecognizing.swift` |
| `SpeechRecognitionAdapting` | `WhisperKitAdapter` | `Sources/Services/Protocols/SpeechRecognitionAdapting.swift` |
| `TextPostprocessing` | `TextPostprocessorImpl` | `Sources/Services/Protocols/TextPostprocessing.swift` |
| `OutputManaging` | `OutputManagerImpl` | `Sources/Services/Protocols/OutputManaging.swift` |
| `ClipboardServicing` | `ClipboardServiceImpl` | `Sources/Services/Protocols/ClipboardServicing.swift` |
| `NotificationServicing` | `NotificationServiceImpl` | `Sources/Services/Protocols/NotificationServicing.swift` |
| `SessionMonitoring` | `SessionMonitoringServiceImpl` | `Sources/Services/Protocols/SessionMonitoring.swift` |
| `HotKeyControlling` | `HotKeyControllerImpl` | `Sources/Services/Protocols/HotKeyControlling.swift` |

## 関連エリア

- [ui.md](ui.md) - UI コンポーネント・アプリ起動
- [INDEX.md](INDEX.md) - 全体概要
