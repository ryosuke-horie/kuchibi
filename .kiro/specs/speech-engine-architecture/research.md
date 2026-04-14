# Gap Analysis: speech-engine-architecture

作成日: 2026-04-14
対象要件: `.kiro/specs/speech-engine-architecture/requirements.md`

## 1. 現状調査（既存資産）

### 主要ファイルとレイヤ

| 項目 | 場所 | 行数 |
|:--|:--|:--|
| エンジン抽象プロトコル | `Sources/Services/Protocols/SpeechRecognitionAdapting.swift` | 10 |
| WhisperKit アダプタ | `Sources/Services/WhisperKitAdapter.swift` | 140 |
| 認識サービス | `Sources/Services/SpeechRecognitionService.swift` | 60 |
| セッション管理 | `Sources/Services/SessionManager.swift` | 266 |
| 設定永続化 | `Sources/Services/AppSettings.swift` | 217 |
| モデル enum | `Sources/Models/WhisperModel.swift` | 33 |
| 設定 UI | `Sources/Views/SettingsView.swift` | 129 |
| Makefile | `Makefile` | 36 |

### 抽出された規約

- プロトコル命名は `-ing` 形（`AudioCapturing`、`SpeechRecognizing` 等）、実装は `*Impl`、外部ラッパーは `*Adapter`
- DI は `AppCoordinator`（`Sources/KuchibiApp.swift`）に集中、constructor injection のみ
- `@MainActor` が `SessionManagerImpl` / `AppSettings` / `AppCoordinator` に付与
- UserDefaults キー命名は `setting.<camelCase>`、`AppSettings.Keys` に集約
- テストは Swift Testing（`@Suite` / `@Test`）、モックは `Tests/Mocks/Mock*` で手書きスタブ

### 現行 `SpeechRecognitionAdapting` の設計

```swift
protocol SpeechRecognitionAdapting {
    func initialize(modelName: String) async throws
    func startStream(onTextChanged: @escaping (String) -> Void, onLineCompleted: @escaping (String) -> Void) throws
    func addAudio(_ buffer: AVAudioPCMBuffer)
    func getPartialText() -> String
    func finalize() async -> String
}
```

- `modelName: String` のみで、エンジン識別子を持たない（WhisperKit 前提）
- `startStream` のコールバックはストリーミング前提（WhisperKit は 500ms 間隔の定期認識で模倣）
- 言語ヒントのインターフェースなし（`DecodingOptions(language: "ja")` は WhisperKitAdapter 内部でハードコード）

### 現行 SettingsView

- `RecognitionSettingsTab` 内に `Picker` 1 個で `WhisperModel` を選ぶ UI のみ
- 注記 `モデル変更はアプリ再起動後に反映されます` が表示されている（hot-swap 未実装）

### インストール・起動経路

- `Makefile` に `build / install / run / clean` が定義済み
- `install` は `rsync -a --delete` + `codesign --force --sign -`
- `run` は `install` 後 `open /Applications/Kuchibi.app`
- DerivedData 起動の検知・警告は未実装

## 2. 要件 → 既存資産マッピング

| 要件 | 既存で満たされる部分 | 不足部分 | タグ |
|:--|:--|:--|:--|
| Req 1: エンジン・モデル選択 UI | `SettingsView` の `RecognitionSettingsTab` / `AppSettings` | 「エンジン」軸が無い（現在は `WhisperModel` のみ）。`SpeechEngine` enum と `AppSettings.speechEngine` / `AppSettings.engineModel` が未定義 | Missing |
| Req 2: 再起動なしエンジン切替 | `SessionManagerImpl` が AppSettings を参照、`SpeechRecognitionServiceImpl` にアダプタ 1 個を DI | アダプタ入れ替え機構がない。`SpeechRecognitionServiceImpl` は init 時に固定されたアダプタで動き、`loadModel` はモデル名の切替のみ | Missing |
| Req 3: エンジン状態可視化 | `SpeechRecognizing.isModelLoaded: Bool` | ロード中状態・現在エンジン名・現在モデル名の公開プロパティが UI に出ていない | Missing |
| Req 4: 既存セッション挙動の不変性 | 既存の状態機械・後処理・OutputMode・ESC キャンセル（`behaviors.md` の契約で明文化済み） | エンジン切替後も契約が維持されることを保証するテストが必要 | Constraint |
| Req 5: 起動経路の固定化 | `Makefile` に `/Applications` インストールフロー、`rsync -a --delete`、`codesign --force` | DerivedData 起動時の検知・警告、ad-hoc 署名のエントロピー問題（署名毎回変わる可能性）、Bundle ID は安定だが codesign identity は `-` で ad-hoc なので毎回 team ID が空 | Missing / Unknown |
| Req 6: 権限状態観測 | `AXIsProcessTrusted()` / `AVCaptureDevice.authorizationStatus` のチェック有（`SessionManagerImpl` / `KuchibiApp.init`）| Settings UI に権限状態を出す表示がない。ランタイム再チェック導線なし | Missing |

## 3. 実装アプローチ案

### Option A: 既存プロトコル拡張のみ（最小変更）

**概要**: 現行 `SpeechRecognitionAdapting` を `modelName: String` に `engine:` プレフィックスや identifier を含ませるだけで複数エンジンを表現し、`WhisperKitAdapter` 以外のアダプタクラスを追加する。

- **拡張ファイル**: `SpeechRecognitionAdapting.swift`, `SpeechRecognitionService.swift`, `AppSettings.swift`, `WhisperModel.swift`, `SettingsView.swift`
- **新規ファイル**: `Services/KotobaWhisperAdapter.swift`, `Services/SenseVoiceAdapter.swift`, `Mocks/MockKotoba...swift`, `Mocks/MockSenseVoice...swift`
- **互換性**: 既存 `WhisperKitAdapter` の API 変更は最小。`modelName` 文字列で全エンジンを一意識別

**Trade-offs**:
- 既存パターン踏襲で最速（S〜M 工数）
- エンジンごとの capabilities（言語・ストリーミング能力）が表現できず、UI 側で分岐しにくい
- `modelName` 文字列に情報が詰まりすぎる（エンジン × モデル + 言語ヒント）

### Option B: エンジン抽象を第 1 級型で導入（再設計）

**概要**: 新規型 `SpeechEngine`（enum）と `SpeechEngineModel`（各エンジン固有モデル）を導入し、`SpeechRecognitionAdapting` に `engine: SpeechEngine` と `capabilities: Set<Capability>` を持たせる。`AppSettings` に `speechEngine` / `engineModel` を分離して永続化。`SpeechRecognitionServiceImpl` はアダプタファクトリーを介して起動時にアダプタを差し替え可能にする。

- **拡張ファイル**: `SpeechRecognitionAdapting.swift`（再設計）、`SpeechRecognitionService.swift`（hot-swap 対応）、`AppSettings.swift`、`WhisperModel.swift`（分解）、`SettingsView.swift`（2 段 Picker）
- **新規ファイル**: `Models/SpeechEngine.swift`, `Models/SpeechEngineModel.swift`, `Services/SpeechEngineFactory.swift`, `Services/KotobaWhisperAdapter.swift`, `Services/SenseVoiceAdapter.swift` + 対応する Mock
- **互換性**: 既存 `WhisperKitAdapter` は API 変更あり（initialize シグネチャ拡張）。`WhisperModel` enum は `SpeechEngine.whisperKit` のサブモデルに再編（後方互換のため migration コード要）

**Trade-offs**:
- 設計が拡張に強く、将来の Apple SpeechAnalyzer 等の追加が容易
- 初期コストが Option A より大きい（M 工数、+ 型定義とテスト修正）
- `AppSettings` のマイグレーション（既存の `setting.modelName` → 新キー `setting.speechEngine` + `setting.engineModel`）が必要

### Option C: ハイブリッド（段階導入）

**概要**: フェーズ 1 で Option A 的にエンジン識別子付き文字列で Kotoba / SenseVoice を統合し、フェーズ 2 で Option B の型再設計に移行する。

- **フェーズ 1 範囲**: 既存 `SpeechRecognitionAdapting` は触らず、`AppSettings.modelName` に `"whisperkit:large-v3-turbo"` のようなプレフィックスで運用
- **フェーズ 2 範囲**: 型を導入し、AppSettings の UserDefaults マイグレーション

**Trade-offs**:
- 初期リリースが早い
- 中間状態の技術的負債が残る（フェーズ 2 への移行モチベーションが薄れる恐れ）
- テスト・UI が 2 回書き直される可能性

## 4. 外部依存・統合課題

### WhisperKit + large-v3-turbo
- 現行 WhisperKit 0.18 で対応。モデル名 `"openai_whisper-large-v3-v20240930_turbo"` 相当を `WhisperKitConfig.model` に渡すのみ
- OD-MBP 4bit 圧縮版（約 954MB）が HF にある。現行 medium（1.5GB）から置き換え可能
- **工数**: S（1〜2 日）

### Kotoba-Whisper Bilingual v1.0（whisper.cpp 経由）
- whisper.cpp の SwiftPM サポートあり、`ggml-org/whisper.cpp` の `Package.swift` を依存追加
- モデルは `kotoba-tech/kotoba-whisper-bilingual-v1.0-ggml` の Q5/Q8 量子化版
- 薄い Swift ラッパーを自作する必要あり（SwiftWhisper は古い）
- whisper.cpp は擬似ストリーミングのみ（VAD 窓で区切り再投入を自前実装）
- WhisperKit との共存は可能（ランタイム独立）、ただし同時常駐で ~2GB 消費
- **工数**: M（4〜6 日、Swift ラッパー + VAD ストリーム再投入込み）

### SenseVoice-Small（CoreML 変換）
- Swift 統合は CoreML `.mlpackage` バンドル推奨（ONNX Runtime Swift も可）
- 参考実装: `mefengl/SenseVoiceSmall-coreml`（低 star）
- 非自己回帰モデル → 固定 30 秒窓前提でストリーミング不可、VAD でチャンク化必須
- 前処理（Kaldi fbank）と SentencePiece トークナイザの Swift 実装が必要
- ライセンスは研究利用寄り（非商用条項）だが Kuchibi は個人用なので許容
- **工数**: L（7〜10 日）

### インストール・権限の安定化
- `codesign --force --sign -` は ad-hoc 署名で、`rsync -a` の inode 変更で TCC が不安定になり得る
- 安定化策の候補:
  - `codesign --preserve-metadata=entitlements` で元の署名属性を保持
  - Bundle ID は既に `com.kuchibi.app` で固定、`INFOPLIST_FILE` も固定
  - ビルド時の `CODE_SIGN_IDENTITY` を開発者証明書に固定（Apple Developer アカウントが必要、個人用は ad-hoc のままが現実的）
- **Research Needed**: ad-hoc 署名でも TCC が維持される条件（`rsync --inplace` / `--no-whole-file` の影響、codesign の `--identifier` 明示固定）

## 5. 複雑度・リスク評価

| 要件 | 複雑度 | リスク | 備考 |
|:--|:--|:--|:--|
| Req 1: エンジン選択 UI | S | Low | `AppSettings` + `SettingsView` 拡張のみ |
| Req 2: hot-swap | M | Medium | `SpeechRecognitionServiceImpl` の再構築、アダプタ入れ替え時の Task キャンセル／新 Task 起動の順序制御 |
| Req 3: 状態可視化 | S | Low | `SpeechRecognizing` に Published プロパティ追加 |
| Req 4: 既存挙動の不変性 | S | Medium | テストを全エンジンで回すためアダプタごとの Mock / 統合テストが必要 |
| Req 5: 起動経路固定化 | M | Medium | `Bundle.main.bundlePath` 検査 + Makefile の codesign 安定化 |
| Req 6: 権限観測性 | S | Low | 既存 `AXIsProcessTrusted` 呼び出しを Published に昇格 |
| 新エンジン統合（Kotoba） | M | Medium | Swift ラッパー自作、VAD 再投入 |
| 新エンジン統合（SenseVoice） | L | High | 前処理・トークナイザ自作、非自己回帰ストリーミング設計 |

**総合**: M〜L（3〜10 日 × 2〜3 エンジン）、リスク Medium-High

## 6. 推奨事項（設計フェーズへの申し送り）

### 優先アプローチ
**Option B（エンジン抽象の第 1 級型導入）を推奨**。理由:

- Req 1〜3 の UI・永続化・可視化が型で表現でき、EARS 要件のテスト可能性が上がる
- Req 4 の「エンジン差し替え後も挙動不変」を型安全に保証できる（capabilities で UI 分岐）
- 3 エンジン同時統合が避けられず、文字列 identifier 運用では管理限界が来る

### 推奨される段階的実装計画（design フェーズで詰める）

- Stage 0: `SpeechEngine` / `SpeechEngineModel` 型と `AppSettings` マイグレーション
- Stage 1: `SpeechRecognitionAdapting` 再設計、既存 `WhisperKitAdapter` を新プロトコルに追従 + large-v3-turbo モデル対応
- Stage 2: Settings UI の 2 段 Picker 化 + 状態表示 + hot-swap
- Stage 3: Kotoba-Whisper Bilingual Adapter（whisper.cpp SwiftPM + 自作ラッパー）
- Stage 4: SenseVoice Adapter（CoreML + 自作前処理）
- Stage 5: 起動経路固定化（Bundle path 検査 + Makefile codesign 安定化）
- Stage 6: 権限観測性の UI 化と統合テスト

### Research Needed（設計フェーズで検証）

- **ad-hoc 署名 + rsync で TCC 権限が維持される条件**（`--inplace` フラグの効果、codesign `--identifier` 明示指定）
- **whisper.cpp Swift ラッパー**: SwiftWhisper は古く、自作が現実的だが、ggml モデルの量子化オプション（Q5 / Q8）の精度差を個人評価で確認
- **SenseVoice 前処理の Swift 実装**: Kaldi fbank 互換を Accelerate で書く、既存のオープンソース実装を探索
- **hot-swap 時の Task キャンセル順序**: 現行 `WhisperKitAdapter.recognitionTask` をキャンセル → `finalize` 完了待ち → 新アダプタ init の連携で、UI ブロック時間の見積もり

### 既存契約との整合

- `.kiro/steering/behaviors.md` の契約（セッション状態機械、テキストパイプライン、出力モード）は設計で**全て維持**する。エンジン差し替えは `SpeechRecognitionAdapting` 層より下で完結させ、上位契約に一切影響しないことを design で `Boundary Commitments` として明記

---

## Synthesis（design 生成前の整理）

### 1. Generalization
- 「エンジン初期ロード」「エンジン切替（hot-swap）」「モデル切替」は、**実体としては 1 つの capability**「`SpeechEngine × EngineModel` ペアに対応する Adapter を初期化済み状態で保持する」に集約できる。初期起動も切替も同じ経路で実装する。
- Requirement 1-3 は表裏一体（選択 UI → 選択永続化 → ロード状態可視化 → 切替失敗フォールバック）で、`SpeechRecognitionServiceImpl` に一元化するのが自然。

### 2. Build vs Adopt
- **WhisperKit（既存採用継続）**: 0.18+ の `WhisperKitConfig` に large-v3-turbo 対応モデル名を渡すだけで済む。拡張不要。
- **whisper.cpp（Kotoba-Whisper Bilingual）**: `ggml-org/whisper.cpp` の公式 SwiftPM `Package.swift` を採用、その上に薄い Swift ラッパー（`WhisperCppAdapter`）を自作する。`exPHAT/SwiftWhisper` は更新が古いため不採用。
- **SenseVoice**: CoreML 変換（`mefengl/SenseVoiceSmall-coreml` 参照）で `.mlpackage` をバンドル。ONNX Runtime は保険候補だが、CoreML のほうが ANE 利用・依存最小。前処理（Kaldi fbank 互換）と SentencePiece トークナイザは自作。
- **launch path check**: `Bundle.main.bundlePath` 比較のみ。ライブラリ不要。
- **codesign 安定化**: `--identifier com.kuchibi.app` 明示と `--preserve-metadata=entitlements,requirements,flags,runtime` の Makefile 追記のみ。

### 3. Simplification
- **`Capabilities` Set<Capability> 導入は見送り**（YAGNI）。現行 3 エンジンはすべて「日本語 or 日英混交の音声→テキスト」として等価的に扱える。将来必要になったら追加。
- **`SpeechEngineFactory` は単独ファイルを作らず、`SpeechRecognitionServiceImpl` 内の private メソッドに内包**する。DI 必要性が出たら抽出。
- **モデル名の String 識別子運用は廃止**。`SpeechEngine` + associated `EngineModel` enum で型安全に表現。
- **UI 2 段 Picker は `SettingsView` 内で完結**。別コンポーネント化しない。
- **`language` 引数は adapter 内にハードコードしない**。現行 WhisperKitAdapter の `"ja"` ハードコードは `initialize` の引数に昇格させ、`AppSettings.language` （将来）に備える。ただし本 spec のスコープでは `"ja"` デフォルト固定でよい。

## Design Decisions

### Decision: SpeechEngine と EngineModel を型で表現（文字列 identifier を廃止）
- **Context**: 現行 `SpeechRecognitionAdapting.initialize(modelName: String)` は WhisperKit のモデル名空間を前提。3 エンジンで名前空間が衝突する。
- **Alternatives Considered**:
  1. 文字列プレフィックス（`"whisperkit:large-v3-turbo"`）- 型安全性なし
  2. `SpeechEngine` enum + associated `EngineModel` - 型安全、拡張時の変更点が明確
- **Selected Approach**: `enum SpeechEngine { case whisperKit(WhisperKitModel); case kotobaWhisperBilingual(KotobaWhisperBilingualModel); case senseVoiceSmall }` のような形
- **Rationale**: Swift の enum associated value で自然に表現でき、新エンジン追加時は case 追加のみ。UI の Picker も enum を走査するだけで生成可能。
- **Trade-offs**: AppSettings の UserDefaults 永続化で Codable エンコードが必要。既存 `setting.modelName` からの migration コードを書く必要あり。

### Decision: Hot-swap は `SpeechRecognitionServiceImpl` に一元化
- **Context**: 現行は `SessionManagerImpl` が `SpeechRecognizing` を固定注入で持つ。切替には内部で adapter を入れ替える必要。
- **Alternatives Considered**:
  1. `SessionManagerImpl` が切替ロジックを持つ - session と engine の責務混在
  2. `SpeechRecognitionServiceImpl` が adapter slot を持ち、`switchEngine(to:)` メソッドで差し替え
- **Selected Approach**: 後者。`SpeechRecognizing` プロトコルに `switchEngine(to: SpeechEngine) async throws` を追加
- **Rationale**: セッション状態機械には触れず、エンジン切替の責務を分離。`behaviors.md` のセッション契約を破らない。

### Decision: codesign 安定化は Makefile 改修のみ
- **Context**: ad-hoc 署名 + `rsync -a --delete` で TCC 権限がしばしばリセットされる。
- **Alternatives Considered**:
  1. Apple Developer 証明書取得 - 個人用として過剰
  2. `codesign --identifier com.kuchibi.app --preserve-metadata=entitlements,requirements,flags,runtime` 明示
  3. `rsync --inplace` に変更
- **Selected Approach**: (2) を採用、(3) は副作用があるため見送り
- **Rationale**: ad-hoc 署名でも identifier 明示と metadata 保持で TCC の再承認要求を抑止できる可能性が高い（Apple 公式ドキュメントの codesign manpage より）
- **Follow-up**: 実装後にリビルド→起動で権限が保持されるか主観確認

## Risks & Mitigations
- **SenseVoice 前処理の精度**: Kaldi fbank 互換の Accelerate 実装に誤差があると認識精度が落ちる → 実装後に fbank 出力値を Python リファレンスと比較するテストを用意
- **whisper.cpp の擬似ストリーミング**: 30 秒窓を切りながら再投入する設計が必要 → 既存 `AudioPreprocessor` の VAD 出力を再利用し、窓境界で adapter 側がリセット
- **codesign 安定化の効果が出ない場合**: `--preserve-metadata` では解決せず、`rsync --inplace` が必要なケース → 実測後に Makefile を追加改修
