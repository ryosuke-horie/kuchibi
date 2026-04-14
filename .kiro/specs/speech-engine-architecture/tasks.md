# Implementation Plan

- [ ] 1. 基盤: 型定義とプロトコル更新
- [x] 1.1 SpeechEngine と EngineModel の型定義
  - `SpeechEngine` enum（`whisperKit` / `kotobaWhisperBilingual` の 2 case）を associated `EngineModel` とともに定義する
  - `WhisperKitModel` enum に `largeV3Turbo` を含む 5 ケースを定義（既存 `WhisperModel` から改名移行）
  - `KotobaWhisperBilingualModel` enum を `v1Q5` / `v1Q8` で定義し、`expectedFileName` と `downloadPageURL` を持たせる
  - `SpeechEngineKind` enum で UI 列挙用の文字列キーを提供
  - `Codable` / `Equatable` / `Hashable` / `Sendable` 準拠、`displayName` / `engineDisplayName` / `modelDisplayName` を実装
  - `SpeechEngineTests` で Codable ラウンドトリップが同値を返すことを確認する
  - _Requirements: 1.1, 1.2, 1.3_
  - _Boundary: Models_

- [x] 1.2 SpeechRecognitionAdapting を新シグネチャへ更新し補助プロトコルを追加
  - `SpeechRecognitionAdapting.initialize` を `(engine: SpeechEngine, language: String) async throws` に変更
  - `ModelAvailabilityChecking` / `LaunchPathValidating` / `PermissionStateObserving` の 3 プロトコルを新規作成
  - プロトコルに準拠する既存コードがビルドエラーになることを確認した上でコンパイル可能な最小スタブをアダプター側に残す
  - _Requirements: 1.1, 2.1, 4.1_
  - _Boundary: Services/Protocols_
  - _Depends: 1.1_

- [x] 1.3 SpeechRecognizing プロトコルを hot-swap 対応へ拡張
  - `currentEngine: SpeechEngine` / `isSwitching: Bool` / `lastSwitchError: String?` を Published として宣言
  - `loadInitialEngine(_:language:)` と `switchEngine(to:language:)` を async throws メソッドとして追加
  - 既存 `loadModel(modelName:)` を削除し、呼び出し側のコンパイルを失敗させて全参照を洗い出す
  - _Requirements: 2.1, 2.3, 2.4, 3.1, 3.2_
  - _Boundary: Services/Protocols/SpeechRecognizing_
  - _Depends: 1.1, 1.2_

- [x] 1.4 project.yml に WhisperCppKit（whisper.cpp XCFramework）の SwiftPM を追加
  - `Packages/WhisperCppKit` をローカル SwiftPM として追加し、`ggml-org/whisper.cpp` 公式 XCFramework を `binaryTarget` で包む
  - `project.yml` で local package を参照し、`Kuchibi` と `KuchibiTests` の `dependencies` に組み込む
  - `xcodegen generate` が成功し、Xcode 上で `import WhisperCppKit` が解決することを確認する
  - _Requirements: 2.1_
  - _Boundary: project.yml, Packages/WhisperCppKit/_

- [x] 1.5 KuchibiError に新規エラーケースを追加
  - `engineMismatch(expected: SpeechEngine, actual: SpeechEngine)` を追加
  - `modelFileMissing(path: String)` を追加
  - `sessionActiveDuringSwitch` を追加
  - 各ケースの `localizedDescription` を日本語で実装する
  - `KuchibiErrorTests` で 3 ケースの `localizedDescription` が空でないことを確認する
  - _Requirements: 2.1, 2.4_
  - _Boundary: Models/KuchibiError_
  - _Depends: 1.1_

- [ ] 2. 基盤: AppSettings 拡張と migration
- [ ] 2.1 AppSettings に speechEngine を追加し旧キー migration を実装
  - `setting.speechEngine` を JSON 文字列として永続化する Published プロパティを追加
  - init 時に旧 `setting.modelName` が存在し新キーが無ければ `SpeechEngine.whisperKit(<対応モデル>)` に変換して書き込み、旧キーを削除する
  - デフォルト値を `SpeechEngine.whisperKit(.largeV3Turbo)` に設定する
  - `resetToDefaults` で新キーをデフォルトに戻す
  - `AppSettingsMigrationTests` で (a) 旧キーのみ → 変換、(b) 新キーのみ → 保持、(c) 両方 → 新キー採用、(d) どちらも無し → デフォルト、の 4 ケースを検証する
  - _Requirements: 1.3_
  - _Boundary: AppSettings_
  - _Depends: 1.1_

- [ ] 3. 中核: 補助サービス
- [ ] 3.1 (P) ModelAvailabilityChecker を実装
  - `~/Library/Application Support/Kuchibi/models/` を標準配置ディレクトリとして解決する
  - WhisperKit 用 engine は常に `isAvailable == true` を返す
  - Kotoba 用 engine は `expectedFileName` をディレクトリ内で FileManager 検索し真偽を返す
  - `modelPath(for:)` と `downloadPageURL(for:)` を提供する
  - `ModelAvailabilityCheckerTests` で配置済み／未配置の両ケースを temp directory で検証する
  - _Requirements: 1.1, 3.2, 6.4_
  - _Boundary: ModelAvailabilityChecker_
  - _Depends: 1.2_

- [ ] 3.2 (P) LaunchPathValidator を実装
  - `Bundle.main.bundlePath` が `/Applications/Kuchibi.app` と一致するかで `isApproved` を返す
  - `currentPath` で実際の起動パスを公開する
  - `LaunchPathValidatorTests` で承認パス / DerivedData パスの両ケースを `Bundle` 差し替えで検証する
  - _Requirements: 5.1, 5.3_
  - _Boundary: LaunchPathValidator_
  - _Depends: 1.2_

- [ ] 3.3 (P) PermissionStateObserver を実装
  - `microphoneGranted` / `accessibilityTrusted` を Published プロパティとして公開する
  - `init` で初回 `refresh()`、`NSApplication.didBecomeActiveNotification` 購読でランタイム再評価する
  - `refresh()` は `AVCaptureDevice.authorizationStatus(for:.audio)` と `AXIsProcessTrusted()` を読む
  - `PermissionStateObserverTests` で 2 値のモック入力に対して Published が期待値を出すことを検証する
  - _Requirements: 6.1, 6.5_
  - _Boundary: PermissionStateObserver_
  - _Depends: 1.2_

- [ ] 4. 中核: Adapter 実装
- [ ] 4.1 (P) WhisperKitAdapter を新プロトコルへ移行
  - `initialize(engine:language:)` で engine が `.whisperKit(let model)` 以外なら `KuchibiError.engineMismatch` を throw
  - `largeV3Turbo` モデル名 `"openai_whisper-large-v3-v20240930_turbo"` を受理する
  - `language` 引数を `DecodingOptions(language:)` に渡し、ハードコード `"ja"` を撤廃する
  - 既存の 500ms 定期認識ループ・`finalize` 処理を新シグネチャに適合させる
  - 既存 `WhisperKitAdapterTests`（新規追加でも可）で largeV3Turbo とエンジン不一致の挙動を検証する
  - _Requirements: 2.1_
  - _Boundary: WhisperKitAdapter_
  - _Depends: 1.3, 1.5_

- [ ] 4.2 (P) WhisperCppAdapter の基本ラッパーを実装
  - `whisper_init_from_file` でコンテキストを初期化し `OpaquePointer` として保持する
  - `ModelAvailabilityChecker.modelPath(for:)` からパスを解決し、未配置なら `KuchibiError.modelFileMissing` を throw
  - `finalize` で `whisper_free` を呼んでリークを起こさないことを Swift Testing の deinit 検証で確認する
  - `language` 引数を `whisper_full_params` の `language` フィールドへ渡す
  - `WhisperCppAdapterTests` の最小ケース（モデルロード成功・失敗、finalize 後の再 initialize）を通す
  - _Requirements: 2.1_
  - _Boundary: WhisperCppAdapter_
  - _Depends: 1.3, 1.4, 1.5, 3.1_

- [ ] 4.3 WhisperCppAdapter に擬似ストリーミングを実装
  - 受信した 16kHz mono Float32 バッファを内部リングバッファへ蓄積する
  - 30 秒窓に到達した時点、または一定時間（例: 1 秒）新規バッファ追加が無い時点で `whisper_full` を同期実行する
  - 確定テキストは `onLineCompleted` コールバックで通知し、内部バッファをクリアする（stream 終了時は `finalize` が同じ処理を呼ぶ）
  - 窓境界ではコンテキストを prompt-shift せず単純リセットして整合性を優先する
  - サンプル音声入力（日英各 1 本、30 秒以内）に対し `onLineCompleted` が非空文字列を返すテストを通す
  - _Requirements: 2.1_
  - _Boundary: WhisperCppAdapter_
  - _Depends: 4.2_

- [ ] 5. 中核: Service の hot-swap 機構
- [ ] 5.1 SpeechRecognitionServiceImpl に adapter slot と switchEngine 本体を実装
  - 現在の adapter を 1 つだけ保持する slot と、engine に応じた adapter 生成ロジックを実装する
  - `loadInitialEngine(_:language:)` を init 直後のロード経路として提供し、既存の `loadModel(modelName:)` 呼び出しを全て置換する
  - `switchEngine(to:language:)` を実装し、旧 adapter の `finalize()` 完了を待ってから新 adapter を `initialize(engine:language:)` する
  - Mock Adapter で「WhisperKit → Kotoba → WhisperKit」の連続切替が state を汚さずに成立することを検証する
  - _Requirements: 2.1_
  - _Boundary: SpeechRecognitionServiceImpl_
  - _Depends: 1.3, 4.1, 4.2, 4.3_

- [ ] 5.2 Published プロパティ公開と precondition guard を実装
  - `currentEngine` / `isSwitching` / `isModelLoaded` を `@Published` として UI へ露出する
  - `switchEngine` 呼び出し時点で `SessionManagerImpl.state != .idle` の場合は `KuchibiError.sessionActiveDuringSwitch` を throw する
  - `isModelLoaded` が false のとき SessionManagerImpl の既存 `startSession` ガードが録音を阻止することを Mock で確認する
  - _Requirements: 2.3, 3.1, 3.3_
  - _Boundary: SpeechRecognitionServiceImpl_
  - _Depends: 5.1_

- [ ] 5.3 切替失敗時の rollback と lastSwitchError を実装
  - 新 adapter の `initialize` が throw した場合に `AppSettings.speechEngine` を元に戻し、旧 adapter を再度 `initialize` する
  - 再 initialize も失敗した場合はエラーをログして `lastSwitchError` に文字列メッセージを書き、`isSwitching` を false に落とす
  - `NotificationService` 経由でユーザーに失敗理由を通知し、サイレントフォールバックにしない
  - Mock が initialize 2 回連続失敗するシナリオで `lastSwitchError` に値が入り、`currentEngine` が旧エンジンのままであり、`NotificationService` の通知 API が呼ばれることをテストで確認する
  - _Requirements: 2.4, 6.4_
  - _Boundary: SpeechRecognitionServiceImpl_
  - _Depends: 5.1, 5.2_

- [ ] 6. 統合: AppCoordinator の配線
- [ ] 6.1 AppCoordinator に新コンポーネント DI と deferred switchEngine を実装
  - `ModelAvailabilityChecker` / `LaunchPathValidator` / `PermissionStateObserver` を `AppCoordinator` が生成して `@Published` に保持する
  - `AppSettings.$speechEngine` と `SessionManagerImpl.$state` を Combine で合成し、`state == .idle` の瞬間に最新要求を `SpeechRecognitionServiceImpl.switchEngine` に渡す
  - 起動時は `AppSettings.speechEngine` の `ModelAvailabilityChecker.isAvailable` を確認し、未配置なら `loadInitialEngine` をスキップして `SettingsView` で DL ガイドが出る状態のまま待機する
  - 起動時の初期ロードが成功した場合のみ `loadInitialEngine` を呼び、失敗時は `NotificationService` で通知する
  - Mock `SessionManagerImpl` で `recording → idle` 遷移時に保留中の `switchEngine` が 1 回だけ呼ばれることを確認する
  - 起動時ログに `LaunchPathValidator.isApproved` の結果を出す
  - _Requirements: 2.2, 1.3, 5.1, 6.1, 6.4_
  - _Boundary: AppCoordinator_
  - _Depends: 2.1, 3.1, 3.2, 3.3, 5.1, 5.2, 5.3_

- [ ] 7. 統合: SettingsView の拡張
- [ ] 7.1 エンジン × モデルの 2 段 Picker と現在状態表示
  - 認識タブに `SpeechEngineKind.allCases` を表示する Picker を追加する
  - 選択エンジンに応じたモデル Picker を `EngineModel.allCases` から生成する
  - 現在のエンジン・モデル名と `isSwitching` に応じた `ProgressView` を同タブに表示する
  - 選択変更は `AppSettings.speechEngine` にのみ書き込み、切替は Coordinator 経由であることを UI コメントに記す（実行責務の漏えい防止）
  - 既存のモデル変更注記を削除し、再起動文言を除去する
  - _Requirements: 1.1, 1.2, 3.1, 3.2_
  - _Boundary: SettingsView_
  - _Depends: 2.1, 6.1_

- [ ] 7.2 Kotoba モデル未配置時の DL ガイド UI
  - `ModelAvailabilityChecker.isAvailable` が false のモデルは Picker 上で disabled にし、ラベルに「モデル未配置」を付与する
  - 未配置時はバナーを出して「HuggingFace で開く」ボタン（`NSWorkspace.shared.open(downloadPageURL)`）と「配置を確認」ボタン（`ModelAvailabilityChecker` の再評価）を配置する
  - 配置完了後に Picker の disabled が解除され、選択可能になる UI 変化をテストで確認する
  - _Requirements: 1.1, 3.2, 6.4_
  - _Boundary: SettingsView_
  - _Depends: 3.1, 7.1_

- [ ] 7.3 起動経路警告バナー
  - `LaunchPathValidator.isApproved == false` のとき認識タブ上部に赤いバナーと `make run` による再インストール案内を表示する
  - 警告バナーのタップで `Bundle.main.bundlePath` を含むヘルプテキストを展開する
  - `LaunchPathValidator` が approved を返すケースではバナーが表示されないことを UI テストで確認する
  - _Requirements: 5.3_
  - _Boundary: SettingsView_
  - _Depends: 3.2, 7.1_

- [ ] 7.4 権限状態表示と復旧導線
  - マイク権限・アクセシビリティ権限の状態を緑／赤チェックで表示する
  - アクセシビリティ権限欠如時に `AXIsProcessTrustedWithOptions` を呼ぶボタンを設置する
  - マイク権限欠如時は既存 `SessionManagerImpl` のガードで session start が阻止され、その理由（マイク権限欠如）が認識タブに明示されることを UI から確認できるようにする
  - 「システム設定を開く」ボタンで該当 URL（`x-apple.systempreferences:com.apple.preference.security`）を `NSWorkspace.shared.open` で開く
  - 権限状態の変化が画面上で再起動なしに反映されることを UI テストで確認する
  - _Requirements: 6.1, 6.2, 6.3, 6.5_
  - _Boundary: SettingsView_
  - _Depends: 3.3, 7.1_

- [ ] 8. インフラ: Makefile の codesign 安定化
- [ ] 8.1 install ターゲットに identifier 明示と metadata 保持を追加
  - `codesign --force --sign -` を `codesign --force --sign - --identifier com.kuchibi.app --preserve-metadata=entitlements,requirements,flags,runtime` に差し替える
  - `make run` を 2 回連続実行し、2 回目以降の起動でアクセシビリティ権限ダイアログが出ないことを手動で確認する手順を task Implementation Notes に記載する
  - 実行後の `/Applications/Kuchibi.app` が起動することを確認する
  - _Requirements: 5.2_
  - _Boundary: Makefile_

- [ ] 9. 検証: 統合テストと主観評価
- [ ] 9.1 (P) Hot-swap シナリオの統合テスト
  - 「idle での即時切替成功」「録音中切替要求を idle 後に適用」「新 adapter initialize 失敗時に旧エンジンへ rollback」の 3 シナリオを Swift Testing で実装する
  - 各シナリオで `currentEngine` / `isSwitching` / `lastSwitchError` の遷移を assert する
  - Mock Adapter が idle 以外で `switchEngine` を呼ばれたら throw することを確認する
  - _Requirements: 2.1, 2.2, 2.4_
  - _Boundary: SpeechRecognitionServiceImpl, AppCoordinator_
  - _Depends: 5.3, 6.1_

- [ ] 9.2 (P) SettingsView の UI テスト
  - Picker 切替でモデルリストが差し替わる、未配置モデルが disabled、「HuggingFace で開く」ボタン押下で `NSWorkspace` に URL が渡る、ロード中に ProgressView が出る、起動経路警告が出る、権限状態インジケータが切り替わる、の 6 ケースを検証する
  - _Requirements: 1.1, 1.2, 3.1, 3.2, 5.3, 6.1, 6.2_
  - _Boundary: SettingsView_
  - _Depends: 7.1, 7.2, 7.3, 7.4_

- [ ] 9.3 (P) セッション契約不変性の回帰テスト
  - 「WhisperKit と Kotoba の各エンジンでセッション状態機械が idle→recording→processing→idle を遷移する」「どちらのエンジンでも TextPostprocessor が適用される」「どちらのエンジンでも OutputManager が所定の OutputMode で出力する」「どちらのエンジンでも ESC キャンセルで出力抑止される」の 4 ケースを確認する
  - _Requirements: 4.1, 4.2, 4.3, 4.4_
  - _Boundary: SessionManagerImpl（既存挙動の検証のみ）_
  - _Depends: 5.1_

- [ ] 9.4 主観評価チェックリスト（手動実施）
  - 同じ日本語サンプル（話し言葉）・日英混交サンプル（技術用語混じり）を 2 エンジン × 利用可能モデル全組み合わせで認識させる手順書を README またはコメントに残す
  - 認識結果を手元でメモし、デフォルトエンジン候補を選定する
  - 本タスクは自動テストではなくユーザーが実施する
  - _Requirements: 1.3, 3.1_
  - _Boundary: 手動検証_
  - _Depends: 7.1, 7.2_
