# サービス層 コードマップ

最終更新: 2026-04-15

## アーキテクチャ

```
AppCoordinator（DI + EngineSwitchCoordinator 起動）
    ├── SessionManagerImpl
    │       ├── AudioCapturing          (AudioCaptureServiceImpl)
    │       │       └── AsyncStream<AVAudioPCMBuffer>
    │       ├── AudioPreprocessing      (AudioPreprocessorImpl)
    │       │       ├── リサンプリング: 任意サンプルレート → 16kHz モノラル（線形補間）
    │       │       └── VAD: RMS がしきい値未満のバッファを破棄
    │       ├── SpeechRecognizing       (SpeechRecognitionServiceImpl)
    │       │       └── SpeechRecognitionAdapting（hot-swap slot、1 つ常駐）
    │       │               ├── WhisperKitAdapter（WhisperKit、500ms 定期認識）
    │       │               └── WhisperCppAdapter（whisper.cpp、30s窓/gap 擬似ストリーミング）
    │       ├── TextPostprocessing      (TextPostprocessorImpl)
    │       │       ├── 先頭・末尾空白除去
    │       │       ├── 連続スペース正規化
    │       │       ├── 日本語フィラー除去（えーと、あー等）
    │       │       ├── 日本語文字間スペース除去
    │       │       └── 3文字以上の繰り返しフレーズ集約
    │       ├── OutputManaging          (OutputManagerImpl)
    │       │       └── ClipboardServicing (ClipboardServiceImpl)
    │       ├── NotificationServicing   (NotificationServiceImpl)
    │       ├── SessionMonitoring       (SessionMonitoringServiceImpl)
    │       └── AppSettings（speechEngine 含む）
    ├── EngineSwitchCoordinator（AppSettings.$speechEngine × SessionState 合成、idle 時のみ適用）
    ├── ModelAvailabilityChecker（Kotoba GGML ファイル存在判定、DL ガイド連動）
    ├── LaunchPathValidator（/Applications/Kuchibi.app 判定、起動経路警告）
    └── PermissionStateObserver（マイク・アクセシビリティ権限 Published）
```

## 主要モジュール

| モジュール | 用途 | 場所 |
|:--|:--|:--|
| `SessionManagerImpl` | セッションライフサイクル管理・状態機械 | `Sources/Services/SessionManager.swift` |
| `AudioCaptureServiceImpl` | AVAudioEngine によるマイク音声キャプチャ | `Sources/Services/AudioCaptureService.swift` |
| `AudioPreprocessorImpl` | リサンプリング（16kHz モノラル）・VAD | `Sources/Services/AudioPreprocessor.swift` |
| `SpeechRecognitionServiceImpl` | adapter slot 保持 + hot-swap + 音声ストリームを RecognitionEvent に変換 | `Sources/Services/SpeechRecognitionService.swift` |
| `WhisperKitAdapter` | WhisperKit ライブラリのラッパー（Whisper 系モデル） | `Sources/Services/WhisperKitAdapter.swift` |
| `WhisperCppAdapter` | whisper.cpp（WhisperCppKit XCFramework）のラッパー（Kotoba-Whisper Bilingual）| `Sources/Services/WhisperCppAdapter.swift` |
| `HallucinationFilter` | Whisper 系共通 hallucination 検出（同一文字連続・低多様性・句読点のみ）| `Sources/Services/HallucinationFilter.swift` |
| `EngineSwitchCoordinator` | `AppSettings.$speechEngine` × `SessionState` 合成の deferred switchEngine 配線 | `Sources/Services/EngineSwitchCoordinator.swift` |
| `ModelAvailabilityChecker` | Kotoba GGML ファイル存在判定（DL ガイド連動） | `Sources/Services/ModelAvailabilityChecker.swift` |
| `LaunchPathValidator` | `Bundle.main.bundlePath` 判定（承認外起動警告） | `Sources/Services/LaunchPathValidator.swift` |
| `PermissionStateObserver` | マイク・アクセシビリティ権限の Published 観測 | `Sources/Services/PermissionStateObserver.swift` |
| `TextPostprocessorImpl` | 認識テキストの後処理 | `Sources/Services/TextPostprocessor.swift` |
| `OutputManagerImpl` | OutputMode に応じたテキスト出力 | `Sources/Services/OutputManager.swift` |
| `ClipboardServiceImpl` | NSPasteboard + CGEvent による Cmd+V | `Sources/Services/ClipboardService.swift` |
| `NotificationServiceImpl` | macOS ユーザー通知の送信 | `Sources/Services/NotificationService.swift` |
| `SessionMonitoringServiceImpl` | セッション統計・監視 | `Sources/Services/SessionMonitoringService.swift` |
| `HotKeyControllerImpl` | グローバルホットキー登録（Cmd+Shift+Space） | `Sources/Services/HotKeyController.swift` |
| `EscapeKeyMonitorImpl` | ESC キーのグローバル監視（セッションキャンセル） | `Sources/Services/EscapeKeyMonitor.swift` |
| `AppSettings` | 全設定値の UserDefaults 永続化（`speechEngine` 含む）| `Sources/Services/AppSettings.swift` |

## ドメインモデル

| モデル | 値 | 場所 |
|:--|:--|:--|
| `SessionState` | `idle` / `recording` / `processing` | `Sources/Models/SessionState.swift` |
| `RecognitionEvent` | `lineStarted` / `textChanged(String)` / `lineCompleted(String)` | `Sources/Models/RecognitionEvent.swift` |
| `OutputMode` | `clipboard` / `directInput` / `autoInput` | `Sources/Models/OutputMode.swift` |
| `SpeechEngine` | `whisperKit(WhisperKitModel)` / `kotobaWhisperBilingual(KotobaWhisperBilingualModel)` | `Sources/Models/SpeechEngine.swift` |
| `WhisperKitModel` | `tiny` / `base` / `small` / `medium` / `largeV3Turbo` | `Sources/Models/EngineModel.swift` |
| `KotobaWhisperBilingualModel` | `v1Q5` / `v1Full` | `Sources/Models/EngineModel.swift` |
| `KuchibiError` | `modelLoadFailed` / `microphonePermissionDenied` / `microphoneUnavailable` / `engineMismatch` / `modelFileMissing` / `sessionActiveDuringSwitch` 等 | `Sources/Models/KuchibiError.swift` |

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
