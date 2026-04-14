# Technology Stack

## Architecture

- 単一プロセスの macOS メニューバー常駐アプリ（MenuBarExtra + Settings シーン）
- 依存注入は `AppCoordinator` を DI コンテナとして構築時に全サービスを配線する
- すべてのビジネスロジックはプロトコルで抽象化し、`SessionManagerImpl` が中心となってサービスを協調させる
- 音声ストリームは `AsyncStream` / `Task` ベースの非同期パイプライン

## Core Technologies

- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI（メニューバー・設定）+ AppKit（`NSWindow` / `NSPasteboard` / `CGEvent`）
- **Target**: macOS 14.0+
- **Project Generation**: XcodeGen（`project.yml` を唯一の信頼できるソース）

## Key Libraries

- `WhisperKit`（argmaxinc/WhisperKit）- 音声認識エンジン。モデルは tiny/base/small/medium/large-v2/large-v3
- `HotKey`（soffes/HotKey）- グローバルホットキー登録
- `SettingsAccess`（orchetect/SettingsAccess）- SwiftUI Settings シーンをプログラムから開く

## Development Standards

### Concurrency
- UI・状態を持つクラスは `@MainActor` を付与（`SessionManagerImpl`、`AppSettings`、`AppCoordinator` 等）
- `Sendable` を満たすドメインモデル（`enum` は `Sendable` を明示）
- 長時間処理は `Task` + `AsyncStream` でキャンセル可能に

### テスト
- Swift Testing（`@Suite`、`@Test`）を使用。XCTest ではない
- Mock は `Tests/Mocks/` にプロトコル名と対応する `Mock*` クラスを配置（古典派スタイル、モック不使用ではなく手書きスタブ）
- `Tests/*Tests.swift` はサービス単位で 1 ファイル

### 権限とシステム連携
- アクセシビリティ権限（`AXIsProcessTrusted`）が自動入力に必須
- DerivedData からの起動では TCC 権限がリセットされるため、必ず `/Applications/Kuchibi.app` にインストールして使用
- マイク権限は `AVCaptureDevice.authorizationStatus(for: .audio)`

## Development Environment

### Required Tools
- Xcode 15+（macOS 14 SDK）
- XcodeGen（`project.yml` から `.xcodeproj` を生成）
- `xcpretty`（任意、`make build` で整形出力）

### Common Commands
```bash
# プロジェクト生成: xcodegen generate
# Build: make build
# Install + 起動: make run
# インストールのみ: make install
# ビルドキャッシュ削除: make clean
```

`make install` は `rsync -a --delete` + `codesign --force --sign -` で `/Applications/Kuchibi.app` を更新し、TCC 権限を維持する。

## Key Technical Decisions

- **ローカル完結**: 外部 API・クラウド依存なし。WhisperKit のモデルをローカルロード
- **プロトコル駆動の DI**: テスト容易性のため全サービスを `-ing` プロトコルで抽象化（`AudioCapturing`、`SpeechRecognizing` 等）
- **UserDefaults 一元管理**: 全設定は `AppSettings` に集約し、`didSet` で自動永続化
- **OutputMode 3 方式**: `clipboard` / `directInput`（クリップボード復元あり）/ `autoInput`（上書き）
- **音声パイプラインの分離**: キャプチャ（`AudioCapturing`）と前処理（`AudioPreprocessing`）と認識アダプタ（`SpeechRecognitionAdapting`）を段階的に分離し、WhisperKit への依存を最小化
- **セッション制御は 3 操作**: `toggleSession()`（ホットキー）/ `cancelSession()`（ESC キーで出力せずに破棄）/ `stopSession()`（内部完了）
- **セッション音とキャンセル音は分離**: 開始・終了・キャンセルでシステムサウンドを使い分け、`sessionSoundEnabled` で一括無効化可能

---
_Document standards and patterns, not every dependency_
