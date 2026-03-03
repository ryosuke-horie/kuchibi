# Research & Design Decisions

## Summary
- Feature: `macos-voice-input-client`
- Discovery Scope: New Feature (greenfield)
- Key Findings:
  - Moonshine v2がSwift Package Manager (SPM)によるネイティブmacOS統合を提供しており、Python bridgeが不要
  - 日本語専用モデル（moonshine-tiny-ja等）がオープンソースで公開済み
  - SwiftUIの`MenuBarExtra`シーンとLSUIElementフラグにより、メニューバー常駐アプリを標準APIのみで構築可能

## Research Log

### Moonshine v2 ASR エンジン
- Context: 音声認識の中核エンジン選定
- Sources Consulted:
  - https://github.com/moonshine-ai/moonshine
  - https://huggingface.co/UsefulSensors/moonshine-tiny-ja
  - https://gigazine.net/gsc_news/en/20260225-moonshine-voice/
- Findings:
  - Moonshine v2（2026年2月リリース）はエッジデバイス向けに最適化されたASR
  - モデルサイズ: Tiny (34M params), Small (123M), Medium (245M)
  - MacBook Proで107msのレイテンシ、Whisper Large V3を上回る精度
  - ポータブルC++コアライブラリ + OnnxRuntimeで動作
  - Swift Package Manager経由でmacOS/iOSネイティブ統合可能
  - ストリーミングAPI: `add_audio()`メソッドで逐次音声データを投入可能
  - イベントリスナー: `on_line_started()`, `on_line_text_changed()`, `on_line_completed()`コールバック
  - 日本語モデルはMoonshine Community License（非商用）で利用可能（個人用途では問題なし）
- Implications: PythonKit等のbridge不要でSwiftネイティブアプリとして構築可能。SPMでの依存管理が可能。

### macOS メニューバーアプリアーキテクチャ
- Context: バックグラウンド常駐型アプリの実装パターン調査
- Sources Consulted:
  - https://developer.apple.com/documentation/swiftui/menubarextra
  - https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/
  - https://sarunw.com/posts/swiftui-menu-bar-app/
- Findings:
  - SwiftUIの`MenuBarExtra`シーン（macOS 13+）でメニューバーアイコンと操作メニューを宣言的に構成
  - Info.plistの`LSUIElement = YES`でDockアイコン非表示（バックグラウンドエージェント化）
  - WindowGroupシーンを除外することでメインウィンドウなしの動作が可能
- Implications: SwiftUI + MenuBarExtraで最小構成のメニューバーアプリを構築。macOS 13以上を対象。

### グローバルホットキー
- Context: どのアプリがフォーカスされていてもホットキーを受け付ける仕組み
- Sources Consulted:
  - https://github.com/soffes/HotKey
  - https://github.com/sindresorhus/KeyboardShortcuts
  - https://developer.apple.com/forums/thread/735223
- Findings:
  - `HotKey`ライブラリ: Carbon APIをSwiftでラップ、軽量でシンプル
  - `KeyboardShortcuts`ライブラリ: ユーザーカスタマイズ可能なUIコンポーネント付き、App Sandbox対応
  - CGEvent tapはAccessibility権限が必要で非サンドボックス前提
  - 個人用・非配布アプリのためサンドボックス制約は不要
- Implications: `HotKey`ライブラリが軽量かつ十分な機能を提供。非サンドボックス環境で使用可能。

### 音声キャプチャ
- Context: マイクからのリアルタイム音声取得
- Sources Consulted:
  - https://developer.apple.com/documentation/avfaudio/avaudiorecorder
  - https://developer.apple.com/documentation/avfaudio/avaudioengine
- Findings:
  - `AVAudioEngine`がリアルタイム音声処理に最適（低レイテンシ、タップ機能）
  - 入力ノードにタップを設置してPCMバッファを取得可能
  - macOSではマイクアクセスに`NSMicrophoneUsageDescription`とユーザー許可が必要
  - `AVAudioSession`はiOS向け、macOSでは`AVAudioEngine`を直接使用
- Implications: AVAudioEngineでマイク音声をリアルタイムキャプチャし、moonshineのadd_audio APIに渡す構成。

### テキスト出力（クリップボード・直接入力）
- Context: 認識結果テキストの出力方法
- Sources Consulted:
  - https://developer.apple.com/documentation/appkit/nspasteboard
  - https://nilcoalescing.com/blog/CopyStringToClipboardInSwiftOnMacOS/
- Findings:
  - `NSPasteboard.general`でシステムクリップボードへの書き込みが可能
  - 直接入力（ペースト）は`CGEvent`でCmd+Vキーストロークをシミュレートするアプローチ
  - Accessibility権限があれば`CGEvent.post()`でキーボードイベントを送信可能
- Implications: クリップボードにコピー → CGEventでCmd+Vペーストが最もシンプルな直接入力の実装方法。

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| Layered + Event-Driven | レイヤード構成にイベントベースの音声パイプラインを組み合わせ | シンプル、各層の責務が明確、テスト容易 | 大規模化時にレイヤー間結合が増加 | 個人用アプリの規模に最適 |
| Clean Architecture | ドメイン中心にPort/Adapter分離 | テスタビリティ、外部依存の差し替え容易 | 過剰な抽象化、個人プロジェクトにはオーバーヘッド | 不採用: 規模に対して複雑すぎる |

## Design Decisions

### Decision: Swift ネイティブ構成（Python bridge不使用）
- Context: Moonshineモデルの実行環境選定
- Alternatives Considered:
  1. Python subprocess/PythonKit経由でmoonshine-voiceを呼び出す
  2. Swift Package Manager経由でMoonshine Swiftパッケージを直接利用
- Selected Approach: SPM経由のSwiftネイティブ統合
- Rationale: Moonshine v2がSPMをサポートしており、C++コア + OnnxRuntimeがmacOSネイティブで動作する。Python bridgeの複雑さ（GIL、環境管理、プロセス間通信）を回避できる。
- Trade-offs: Pythonエコシステムの柔軟性は失うが、パフォーマンスと配布の簡素化を得る
- Follow-up: SPMパッケージの具体的なAPIシグネチャを実装時に確認

### Decision: HotKeyライブラリの採用
- Context: グローバルホットキー機能の実装方法
- Alternatives Considered:
  1. HotKey（Carbon API wrapper）
  2. KeyboardShortcuts（SwiftUI UI付き）
  3. CGEvent tap（低レベルAPI）
- Selected Approach: HotKey
- Rationale: 軽量で目的に十分。個人用アプリでユーザー設定UIは不要。Carbonベースだが安定動作。
- Trade-offs: ユーザーカスタマイズUIは付属しないが、コードで直接設定すれば十分
- Follow-up: 特定のホットキーの衝突がないか実装時に確認

### Decision: クリップボード経由の直接入力
- Context: 認識テキストの「直接入力」モードの実装
- Alternatives Considered:
  1. CGEventでキーストロークを1文字ずつ送信
  2. NSPasteboardにコピー後、CGEventでCmd+Vをシミュレート
  3. Accessibility APIでテキストフィールドに直接設定
- Selected Approach: NSPasteboard + CGEvent(Cmd+V)
- Rationale: 日本語テキストの文字ごと送信は遅延とIME干渉のリスクが高い。クリップボード経由なら一括挿入で確実。
- Trade-offs: ユーザーのクリップボード内容を上書きする（元の内容を退避・復元する設計で対応可能）
- Follow-up: クリップボード退避・復元のタイミング制御

## Risks & Mitigations
- Moonshine SPMパッケージの安定性 — フォールバックとしてPython subprocess方式を検討
- マイク権限拒否時のUX — 権限状態の監視と再要求フローを実装
- CGEvent使用時のAccessibility権限 — アプリ初回起動時に権限要求ダイアログを表示

## References
- [Moonshine GitHub](https://github.com/moonshine-ai/moonshine) — ASRエンジン公式リポジトリ
- [moonshine-tiny-ja on HuggingFace](https://huggingface.co/UsefulSensors/moonshine-tiny-ja) — 日本語モデル
- [MenuBarExtra Apple Docs](https://developer.apple.com/documentation/swiftui/menubarextra) — SwiftUIメニューバーAPI
- [HotKey GitHub](https://github.com/soffes/HotKey) — グローバルホットキーライブラリ
- [NSPasteboard Apple Docs](https://developer.apple.com/documentation/appkit/nspasteboard) — クリップボードAPI
