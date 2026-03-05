# ギャップ分析: WhisperKit 移行

## 分析サマリー

- 移行は `de8421f` コミットで完了済み。プロトコル汎用化、アダプター実装、DI 差し替え、テスト更新がすべて実施されている
- 全 4 要件（12 受入基準）に対し、コードベースがカバーしている
- テストコード内に `moonshine-small-ja` という旧モデル名のテストデータが残っている（5 箇所）。機能上は無害だが一貫性の課題あり
- design.md 記載の WhisperKit バージョン（v0.15+）と project.yml の実際のバージョン（0.9.0+）に差異がある
- WhisperKitAdapter の直接単体テストが未作成（Mock 経由の間接テストのみ）

## 要件-資産マッピング

| 要件 | 受入基準 | 対応コンポーネント | ギャップ |
|------|---------|-------------------|---------|
| 1.1 | モデル読込・初期化 | `WhisperKitAdapter.initialize` | なし |
| 1.2 | 16kHz PCM Float32 認識 | `WhisperKitAdapter.addAudio` + `performRecognition` | なし |
| 1.3 | 停止時の最終認識 | `WhisperKitAdapter.finalize` | なし |
| 2.1 | 部分テキスト定期通知 | `WhisperKitAdapter` Task ループ（500ms） | なし |
| 2.2 | 確定テキスト通知 | `SpeechRecognitionService.processAudioStream` | なし（finalize フォールバック） |
| 2.3 | lineCompleted 未発行時のフォールバック | `SpeechRecognitionService.processAudioStream` | なし |
| 3.1 | 汎用プロトコル準拠 | `SpeechRecognitionAdapting` | なし |
| 3.2 | 同一 RecognitionEvent ストリーム | `SpeechRecognitionService` | なし |
| 3.3 | SessionManager 修正不要 | `SessionManager` | なし（変更なしで動作） |
| 4.1 | 汎用命名 | `SpeechRecognitionAdapting.swift` | なし |
| 4.2 | DI によるアダプター切替 | `KuchibiApp.init` | なし |

## 残存課題

### 1. テストデータ内の旧モデル名（低優先度）

場所: `Tests/AppSettingsTests.swift`（5 箇所）

テスト内で `"moonshine-small-ja"` をモデル名の保存・復元テストに使用している。機能上は任意の文字列で動作するため問題ないが、移行の完了を示すなら `"whisper-base"` 等に更新すると一貫性が保たれる。

タグ: Constraint（一貫性のみの課題）

### 2. design.md と project.yml のバージョン不一致

design.md では `WhisperKit v0.15+` と記載されているが、project.yml の実際の依存は `from: "0.9.0"` となっている。ドキュメントの誤記の可能性が高い。

タグ: Constraint（ドキュメント整合性）

### 3. WhisperKitAdapter の直接テスト未作成

design.md のテスト戦略で計画されていた `WhisperKitAdapter` 単体テスト（initialize、addAudio、finalize、startStream のコールバック）が未作成。WhisperKit ライブラリへの依存があるため、直接テストには WhisperKit 自体のモックまたはスタブが必要となり、実装コストが高い。現状は `MockSpeechRecognitionAdapter` を通じた間接テストで品質を担保している。

タグ: Missing（テストカバレッジ、ただし実質的リスクは低い）

## 実装アプローチ評価

この移行は既に完了しているため、アプローチ評価は実装後の振り返りとして記載する。

### 採用されたアプローチ: ハイブリッド（Option C）

- プロトコルリネーム（既存コンポーネントの拡張）
- WhisperKitAdapter の新規作成（新コンポーネント）
- MoonshineAdapter の完全除去

このアプローチは以下の点で適切:
- プロトコルの汎用化により将来のエンジン差し替えが容易
- アダプターパターンにより既存パイプラインへの影響がゼロ
- DI サイトが 1 箇所に集約されており、差し替えが明確

### 設計上の注目点

1. Task ベースの定期認識ループ（Timer ではなく Task.sleep）— RunLoop の問題を回避する適切な判断
2. `OSAllocatedUnfairLock` によるスレッドセーフな状態管理 — 軽量なロック機構の選択
3. 累積バッファ方式（チャンク分割ではなく全バッファ再認識）— 精度優先の設計、長時間セッションではパフォーマンス低下の可能性あり

## 工数とリスク

- 工数: S（完了済み。実装規模は 850 insertions / 204 deletions）
- リスク: Low — 既存パターンの踏襲、プロトコルベースの明確な境界、SessionManager への影響なし

## 設計フェーズへの推奨事項

移行は完了済みのため、今後の改善として以下を検討可能:

1. 長時間セッション対応: 累積バッファ方式は長時間の録音で認識コストが増大する。スライディングウィンドウ方式への移行を検討（Research Needed）
2. モデル選択 UI: 設定画面でのモデルサイズ変更（tiny / base / small / medium）。精度と速度のトレードオフをユーザーが選択可能に
3. テストデータの更新: `AppSettingsTests` 内の `moonshine-small-ja` を適切な WhisperKit モデル名に更新
4. ドキュメント整合性: design.md の WhisperKit バージョン記載を実際の依存と合わせて修正
