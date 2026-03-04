# Research & Design Decisions

## Summary
- Feature: `settings-ui`
- Discovery Scope: Extension（既存 MenuBarExtra アプリへの Settings シーン追加）
- Key Findings:
  - SwiftUI Settings シーンは MenuBarExtra から直接開けない既知の制限がある
  - SettingsAccess ライブラリ（v2.1.0+）がこの制限を解決する
  - 現在のハードコード設定値は6箇所に分散しており、`@AppStorage` で一元化可能

## Research Log

### SwiftUI Settings と MenuBarExtra の互換性
- Context: MenuBarExtra アプリから Settings シーンを開く方法の調査
- Sources Consulted:
  - https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items
  - https://github.com/orchetect/SettingsAccess
  - Apple Developer Documentation: MenuBarExtra, Settings
- Findings:
  - macOS 14+ で `SettingsLink` が追加されたが、MenuBarExtra 内では動作が不安定
  - `openSettings` 環境アクションも MenuBarExtra コンテキストでは失敗する
  - 原因: MenuBarExtra は `NSApplication.ActivationPolicy.accessory` で動作し、SwiftUI のウィンドウ管理コンテキストが不完全
  - SettingsAccess ライブラリがカスタム `SettingsLink` イニシャライザを提供し、MenuBarExtra から確実に Settings を開ける
- Implications:
  - SettingsAccess を SPM 依存に追加する必要あり
  - MenuBarExtra 内では `SettingsLink` のカスタムイニシャライザを使用する

### 設定永続化の方式
- Context: 散在するハードコード設定値の一元管理方法
- Sources Consulted: Apple Developer Documentation（@AppStorage, UserDefaults）
- Findings:
  - 現在 UserDefaults を使用しているのは `outputMode` のみ（SessionManager.swift）
  - `@AppStorage` は SwiftUI View 内で UserDefaults を宣言的に扱えるプロパティラッパー
  - `@AppStorage` は View 以外（ObservableObject 等）では使用不可。ObservableObject 内では UserDefaults を直接使う
  - 設定値の集約先として ObservableObject クラスを用意し、各サービスへ DI するのが自然
- Implications:
  - `AppSettings` クラス（ObservableObject）を新設し、全設定を集約
  - 各サービスは init 時に設定値を受け取るか、`AppSettings` を参照する

### ハードコード設定値の所在
- Context: 設定画面で調整可能にすべき値の棚卸し
- Findings:
  - `silenceTimeoutSeconds = 30` — SessionManager.swift:8
  - `defaultModelName = "moonshine-tiny-ja"` — SpeechRecognitionService.swift:7
  - `modelArch: .tiny` — MoonshineAdapter.swift:28
  - `updateInterval: 0.5` — MoonshineAdapter.swift:93
  - `bufferSize: 1024` — AudioCaptureService.swift:21
  - `key: .space, modifiers: [.command, .shift]` — HotKeyController.swift:18
- Implications:
  - 上記すべてを `AppSettings` のプロパティとして定義し、デフォルト値を保持
  - 今回の settings-ui spec では設定基盤と既存設定（outputMode, launchAtLogin）の移行が対象
  - モデル名やバッファサイズ等の詳細パラメータは後続 spec（model-selection, audio-preprocessing 等）で設定画面に公開

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| @AppStorage in Views | 各 View で @AppStorage を直接使用 | 最もシンプル | View 以外から設定にアクセスしにくい、テスト困難 | 小規模なら有効 |
| AppSettings ObservableObject | 設定を集約した ObservableObject を DI | テスト可能、サービス層からもアクセス可能、拡張性高い | クラス追加が必要 | 採用 |
| 設定ファイル (JSON/plist) | カスタムファイルで設定管理 | 柔軟 | 手動のシリアライズが必要、macOS 標準から乖離 | 不採用 |

## Design Decisions

### Decision: SettingsAccess ライブラリの採用
- Context: MenuBarExtra から Settings シーンを開く必要がある
- Alternatives Considered:
  1. 自前で隠しウィンドウ + Notification パターンを実装
  2. SettingsAccess ライブラリを使用
  3. Settings シーンではなく独立した Window シーンを使用
- Selected Approach: SettingsAccess ライブラリを使用
- Rationale: 既知の問題に対する確立されたソリューション。macOS 11+ 対応で互換性も十分。メンテナンスされている OSS。
- Trade-offs: 外部依存が1つ増えるが、自前実装のメンテナンスコストと比較して合理的
- Follow-up: SettingsAccess v2.1.0 の MenuBarExtra 向けカスタム SettingsLink の動作検証

### Decision: AppSettings ObservableObject パターン
- Context: ハードコード設定値を一元管理し、サービス層にも DI する必要がある
- Alternatives Considered:
  1. 各 View で @AppStorage を直接使用
  2. AppSettings ObservableObject で集約
- Selected Approach: AppSettings ObservableObject で集約
- Rationale: サービス層（SessionManager, SpeechRecognitionService 等）からも設定値を参照する必要があり、View 限定の @AppStorage では対応できない。ObservableObject なら DI でテスト可能。
- Trade-offs: やや間接的だが、後続 spec での拡張に自然に対応可能

## Risks & Mitigations
- SettingsAccess が macOS 将来バージョンで動作しなくなるリスク — ライブラリがメンテナンスされており、Apple が Settings API を改善すればライブラリ自体が不要になる。移行コストは低い
- 設定変更がアクティブなセッション中に適用されるリスク — セッション中は設定変更を反映せず、次回セッション開始時に適用する方針で対応

## References
- [SettingsAccess GitHub](https://github.com/orchetect/SettingsAccess) — MenuBarExtra から Settings を開くためのライブラリ
- [Showing Settings from macOS Menu Bar Items](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items) — 問題の詳細と解決策の調査記事
- [Apple Developer: MenuBarExtra](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra) — 公式ドキュメント
- [Apple Developer: Settings](https://developer.apple.com/documentation/SwiftUI/Settings) — SwiftUI Settings シーンの公式ドキュメント
