# Kuchibi コードマップ INDEX

最終更新: 2026-03-07

## プロジェクト概要

macOS 用の個人向け音声入力アプリ。ホットキー（Cmd+Shift+Space）で録音を開始・停止し、WhisperKit による音声認識結果をクリップボードコピーまたはアクティブアプリへ自動入力する。

## ディレクトリ構造

```
Sources/
├── KuchibiApp.swift          エントリーポイント・DIコンテナ
├── Models/                   ドメインモデル
├── Services/                 ビジネスロジック層
│   └── Protocols/            サービス抽象インターフェース
└── Views/                    UI コンポーネント

Tests/
├── Mocks/                    テスト用モック
└── *Tests.swift              単体テスト
```

## コードマップ一覧

| ファイル | 対象エリア |
|:--|:--|
| [services.md](services.md) | サービス層・モデル・データフロー |
| [ui.md](ui.md) | UI コンポーネント・アプリ起動・設定 |

## 主要データフロー（概要）

```
ホットキー
    │
    ▼
SessionManager ──── AudioCaptureService ──► AudioPreprocessor
    │                                            │ (16kHz モノラル + VAD)
    │                                            ▼
    │                                   SpeechRecognitionService
    │                                   (WhisperKitAdapter)
    │                                            │ RecognitionEvent
    │◄───────────────────────────────────────────┘
    │
    ├─ TextPostprocessor (正規化・フィラー除去)
    │
    └─► OutputManager ──► ClipboardService
                             ├── clipboard  (コピーのみ)
                             ├── directInput (Cmd+V、元のクリップボード復元)
                             └── autoInput   (Cmd+V、クリップボード上書き)
```

## 外部依存関係

- WhisperKit - 音声認識エンジン（Whisper モデル）
- SettingsAccess - SwiftUI Settings シーン用ヘルパー
