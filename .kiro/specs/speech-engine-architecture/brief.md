# Brief: speech-engine-architecture

## Problem

- 現行 WhisperKit + Whisper medium は速度は許容だが、日本語の話し言葉精度に不満が残る
- 精度改善候補（Whisper Large V3 Turbo / Kotoba-Whisper Bilingual v1 / SenseVoice-Small）を試したいが、エンジンやモデルを差し替えるたびにソースコードを書き換える運用は現実的でない
- 加えて、`/Applications` へのインストール運用がビルド前後で揺れ、アクセシビリティ（TCC）権限が不安定になる事象が頻発している

## Current State

- `SpeechRecognitionAdapting` プロトコルは存在するが、実装は `WhisperKitAdapter` 1 系統のみ
- `WhisperModel` enum は WhisperKit 内のモデルサイズのみ表現（tiny/base/small/medium/large-v2/large-v3）
- 設定 UI ではモデル切替は可能だが、エンジン切替は不可
- インストール運用は `make run`（rsync + codesign）で `/Applications/Kuchibi.app` を更新するが、ビルド設定や手順の逸脱で権限が毎回リセットされるケースあり
- WhisperKit 以外のランタイム（whisper.cpp / MLX / ONNX）は未統合

## Desired Outcome

- UI から「エンジン × モデル」の組み合わせを選択できる
- 新エンジン追加時にコード変更が最小（`SpeechRecognitionAdapting` 実装追加 + enum 拡張のみで完結）
- 切替はベストエフォートで **再起動なしの hot-swap**、複雑化する場合は再起動フォールバックで合意
- `/Applications` インストール後に TCC 権限が一度付与されれば、**ビルドを繰り返しても権限が維持される**決定的な運用に
- 個人用の主観評価で候補 3 エンジンを実際に試して、好みのエンジンをデフォルトにできる

## Approach

1. **エンジン抽象化の強化**: `SpeechRecognitionAdapting` を中心に、エンジン固有モデル表現を内包する `SpeechEngine` + `SpeechEngineModel` 型を導入
2. **3 エンジン統合**:
   - WhisperKit（既存、large-v3-turbo を追加）
   - Kotoba-Whisper Bilingual v1（whisper.cpp / ggml 経由の新 Adapter）
   - SenseVoice-Small（ONNX Runtime Swift 経由の新 Adapter）
3. **選択 UI**: `AppSettings` に `speechEngine` と `engineModel` を追加、Settings 画面で 2 段階選択
4. **Hot-swap**: 録音中以外なら動的にアダプター差し替え、モデルロードは非同期で UI をブロックしない。失敗時は再起動ガイドを表示
5. **権限・インストール運用の固定化**:
   - `make run` を唯一の承認された起動経路とし、他経路（Xcode 直起動・DerivedData 起動）を非推奨化
   - コード署名の安定化（同一 identity 維持、codesign 失敗時の再試行）
   - TCC 権限チェックと自動復旧導線を `AppCoordinator` 初期化時に一元化
   - `kuchibi-build` skill を正とし、そこから逸脱しないワークフロー化

## Scope

- **In**:
  - `SpeechEngine` / `SpeechEngineModel` 型の導入と `SpeechRecognitionAdapting` の再設計
  - 3 エンジンの Adapter 実装（WhisperKit は既存拡張、他 2 エンジンは新規）
  - Settings UI のエンジン × モデル選択画面
  - 録音中以外の hot-swap（録音中切替はブロック）
  - `/Applications` インストール運用の固定化（Makefile / skill ドキュメント整備）
  - TCC 権限の初期化・状態表示の改善

- **Out**:
  - クラウド ASR サービスの統合
  - エンジン別のファインチューン・追加学習
  - モデル自動ダウンロード（初回は手動配置でも可）
  - 録音中の hot-swap（リアルタイム切替）
  - 複数言語同時認識
  - 評価自動化ベンチマーク（主観評価で代用）

## Boundary Candidates

- エンジン抽象レイヤ（`SpeechEngine` 型 + `SpeechRecognitionAdapting` 再設計）
- 各エンジン Adapter 実装（3 つを独立した実装ファイル）
- AppSettings の拡張（永続化キー追加・デフォルト値変更）
- Settings UI のエンジン選択コンポーネント
- 起動・権限運用の固定化（Makefile / skill / ドキュメント）

## Out of Boundary

- 録音中リアルタイムエンジン切替
- モデル配布サーバ・自動更新機構
- 他プラットフォーム（iOS 等）対応
- 複数エンジン同時実行・アンサンブル

## Upstream / Downstream

- **Upstream**:
  - `.kiro/steering/behaviors.md`（セッション状態機械・権限契約）
  - `whisperkit-migration` spec（WhisperKit 採用の経緯）
  - `completion-sound-accessibility` spec（TCC 権限フォールバックの設計）
  - `settings-ui` spec（AppSettings UI パターン）
- **Downstream**:
  - 将来のエンジン追加（例: Apple SpeechAnalyzer on macOS 26）
  - エンジン切替に依存する後処理の挙動調整（テキスト後処理パイプラインへの影響）

## Existing Spec Touchpoints

- **Extends**: なし（既存 spec は凍結スナップショットとして扱い、本 spec で新たなアーキテクチャを定義）
- **Adjacent**:
  - `settings-ui`（UI 追加の整合性）
  - `whisperkit-migration`（WhisperKit は 1 エンジンとして継続採用）
  - `completion-sound-accessibility`（TCC 権限フロー再設計）

## Constraints

- **オフライン動作必須**（全エンジンでネットワーク依存なし）
- **macOS 14+**（現行サポート）
- **Swift 統合**: SwiftPM で完結するか、CoreML / whisper.cpp / ONNX の Swift ラッパー経由
- **ライセンス**: MIT / Apache 2.0 / BSD（個人用だが LGPL / CC-BY-NC 等の制約は避ける）
- **評価は主観**（公開ベンチ数値は参考程度、実際に喋って気に入ったものをデフォルトに）
- **メモリ**: 個人 Mac での常駐前提、1 エンジン 1.5GB まで許容
- **切替は録音外**（録音中の hot-swap はスコープ外）
