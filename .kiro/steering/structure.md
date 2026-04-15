# Project Structure

## Organization Philosophy

レイヤー分離（Models / Services / Views）を基本とし、Services 内部はさらにプロトコル（抽象）と実装（具象）を物理的に分ける。DI コンテナ（`AppCoordinator`）は 1 箇所に集中し、ファイル間の配線は constructor injection のみ。

## Directory Patterns

### Sources/Models/
**Location**: `Sources/Models/`
**Purpose**: 値型のドメインモデルとエラー型。副作用を持たない純粋な型のみ
**Example**: `SessionState`（`enum`）、`RecognitionEvent`、`OutputMode`、`WhisperModel`、`KuchibiError`

### Sources/Services/
**Location**: `Sources/Services/`
**Purpose**: ビジネスロジックとシステム連携。`*Impl` 具象クラスを配置
**Example**: `SessionManagerImpl`、`AudioCaptureServiceImpl`、`WhisperKitAdapter`

### Sources/Services/Protocols/
**Location**: `Sources/Services/Protocols/`
**Purpose**: Services の抽象インターフェース。テスト・差し替えの境界
**Example**: `AudioCapturing`、`SpeechRecognizing`、`OutputManaging`

### Sources/Views/
**Location**: `Sources/Views/`
**Purpose**: SwiftUI ビューとウィンドウコントローラ。状態はサービスから `@ObservedObject` で受け取る
**Example**: `FeedbackBarView`（+ `FeedbackBarWindowController`）、`SettingsView`

### Tests/ と Tests/Mocks/
**Location**: `Tests/`
**Purpose**: サービス単位のユニットテスト（`*Tests.swift`）と手書きモック（`Tests/Mocks/Mock*.swift`）
**Example**: `SessionManagerTests.swift` + `Tests/Mocks/MockAudioCaptureService.swift`

### docs/CODEMAPS/
**Location**: `docs/CODEMAPS/`
**Purpose**: サービス層・UI 層のアーキテクチャ図とモジュール一覧（人間向けナビゲーション）

### .kiro/
**Location**: `.kiro/`
**Purpose**: Spec-Driven Development のステアリング（`steering/`）と個別仕様（`specs/`）

## Naming Conventions

- **プロトコル**: 現在分詞形 `-ing`（`AudioCapturing`、`SpeechRecognizing`、`OutputManaging`）
  - 例外: `SpeechRecognitionAdapting`（`Adapter` ではなく `Adapting`）
- **実装クラス**: プロトコル名から派生した `*Impl` 接尾辞（`AudioCaptureServiceImpl`）
  - 例外: 外部ライブラリラッパーは `*Adapter`（`WhisperKitAdapter`）
- **モック**: `Mock` + プロトコル対象のサービス名（`MockAudioCaptureService`）
- **ファイル名**: 型名と一致（`SessionManager.swift` に `SessionManagerImpl`）
- **テストファイル**: 対象サービス名 + `Tests.swift`
- **UserDefaults キー**: `setting.<camelCase>`（`AppSettings.Keys` 内に集約）
- **Logger subsystem**: `"com.kuchibi.app"` 固定、category はクラス名

## Import Organization

Swift のフレームワーク import を先頭に、外部パッケージ、プロジェクト内 import の順。プロジェクト内は同一モジュールなので import 不要。

```swift
import AppKit            // システムフレームワーク
import AVFoundation
import os
import SwiftUI

import WhisperKit        // 外部パッケージ（必要な実装のみ）
```

テストでは `@testable import Kuchibi` を使用。

## Code Organization Principles

- **DI は `AppCoordinator` 1 箇所に集中**: サービス間の配線はここだけで行う。他のクラスは constructor で受け取る
- **プロトコル境界でテスト可能性を確保**: 新しいサービスを追加する場合は必ず `Services/Protocols/` に `-ing` プロトコルを作り、対応する `Mock*` を `Tests/Mocks/` に追加する
- **`@MainActor` の徹底**: UI と状態管理クラス（`SessionManagerImpl`、`AppSettings`、`*WindowController`）はクラス単位で `@MainActor`
- **永続化は `AppSettings` に集約**: UserDefaults への直接アクセスは `AppSettings` のみ。新規設定項目は `AppSettings.Keys` と `defaults*` 定数を追加する
- **ドメインモデルは値型・`Sendable`**: `Models/` の型は副作用を持たず、`enum` は `Sendable` を明示
- **CODEMAPS の更新**: `Sources/Services/` または `Sources/Views/` に新規モジュールを追加した場合、`docs/CODEMAPS/` の対応する `.md` も更新する
- **グローバルキー監視は 2 系統**: `HotKeyControlling`（Cmd+Shift+Space でトグル）と `EscapeKeyMonitoring`（ESC でセッション破棄）。いずれも `AppCoordinator` で起動し、コールバックで `SessionManagerImpl` の `toggleSession()` / `cancelSession()` を呼ぶ

---
_Document patterns, not file trees. New files following patterns shouldn't require updates_
