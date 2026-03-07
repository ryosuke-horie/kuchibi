# UI 層 コードマップ

最終更新: 2026-03-07

## アーキテクチャ

```
KuchibiApp (@main)
    ├── MenuBarExtra "Kuchibi"
    │       └── MenuBarView          状態テキスト・設定リンク・終了ボタン
    │
    ├── Settings Scene
    │       └── SettingsView         設定パネル（AppSettings バインド）
    │
    └── FeedbackBarWindowController  セッション中に表示するフローティングバー
            └── FeedbackBarView
                    ├── AudioLevelBar × 10   音量レベルインジケーター
                    └── ProcessingWaveView   文字起こし中アニメーション
```

## 主要コンポーネント

| コンポーネント | 用途 | 場所 |
|:--|:--|:--|
| `KuchibiApp` | エントリーポイント・全サービスの DI 構築 | `Sources/KuchibiApp.swift` |
| `MenuBarView` | メニューバーポップアップ（状態表示・操作） | `Sources/KuchibiApp.swift`（`KuchibiApp` と同ファイル） |
| `FeedbackBarWindowController` | フローティングバーウィンドウの表示・非表示制御 | `Sources/Views/FeedbackBarView.swift` |
| `FeedbackBarView` | 音量バー・中間認識テキスト・処理中アニメーション | `Sources/Views/FeedbackBarView.swift` |
| `AudioLevelBar` | 個別の音量バー（RMS レベルに応じた高さ） | `Sources/Views/FeedbackBarView.swift` |
| `ProcessingWaveView` | 文字起こし中を示すウェーブアニメーション | `Sources/Views/FeedbackBarView.swift` |
| `SettingsView` | 全設定項目の UI（AppSettings ObservableObject） | `Sources/Views/SettingsView.swift` |

## アプリ起動シーケンス

```
KuchibiApp.init()
    │
    ├── AppSettings 生成（UserDefaults 復元）
    ├── AudioCaptureServiceImpl 生成
    ├── WhisperKitAdapter 生成
    ├── SpeechRecognitionServiceImpl 生成
    ├── ClipboardServiceImpl 生成
    ├── OutputManagerImpl 生成
    ├── NotificationServiceImpl 生成
    ├── AudioPreprocessorImpl 生成（SessionManagerImpl デフォルト引数）
    ├── TextPostprocessorImpl 生成（SessionManagerImpl デフォルト引数）
    ├── SessionMonitoringServiceImpl 生成（SessionManagerImpl デフォルト引数）
    ├── SessionManagerImpl 生成（上記サービスを注入）
    ├── HotKeyControllerImpl 生成（toggleSession コールバック）
    ├── FeedbackBarWindowController 生成
    ├── HotKeyController.register() ← グローバルホットキー登録
    └── Task: speechService.loadModel() ← 非同期モデルロード
```

## メニューバーアイコン

| 状態 | アイコン |
|:--|:--|
| `idle` | `mic` |
| `recording` | `mic.fill` |
| `processing` | `mic.badge.ellipsis` |

## FeedbackBar の表示ロジック

```
SessionManager.$state
    ├── .recording または .processing → FeedbackBarWindowController.show()
    └── .idle                         → FeedbackBarWindowController.hide()
```

- 画面下端に高さ 36pt のフローティングウィンドウ（`.borderless` + `.floating` レベル）
- マウスイベントを無視（`ignoresMouseEvents = true`）
- 全スペース表示（`.canJoinAllSpaces`）

## 外部依存関係

- SwiftUI - UI フレームワーク
- SettingsAccess - `SettingsLink` による Settings シーン連携

## 関連エリア

- [services.md](services.md) - サービス層・データフロー
- [INDEX.md](INDEX.md) - 全体概要
