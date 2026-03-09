# Research & Design Decisions

## Summary
- Feature: `hotkey-toggle-session`
- Discovery Scope: Extension
- Key Findings:
  - `SessionManager.startSilenceTimeout()` が `startSession()` と `handleRecognitionEvent()` の3箇所から呼ばれている。全て削除する
  - `silenceTimeout` は `AppSettings`, `SettingsView`, `SessionManager`, テストに広く参照されている
  - `KuchibiError.silenceTimeout` と `NotificationService` のタイムアウト通知も不要になる

## Research Log

### 無音タイムアウト関連コードの影響範囲
- Context: 無音タイムアウト削除の影響範囲調査
- Findings:
  - `SessionManager`: `timeoutTask` プロパティ、`startSilenceTimeout()` メソッド、`startSession()` / `handleRecognitionEvent()` での呼び出し
  - `AppSettings`: `defaultSilenceTimeout`, `silenceTimeout` プロパティ, Keys, init, resetToDefaults
  - `SettingsView`: 無音タイムアウトの TextField UI
  - `KuchibiError`: `.silenceTimeout` case
  - `NotificationService`: silenceTimeout のエラー通知メッセージ
  - テスト: `SessionManagerTests`, `AppSettingsTests`, `NotificationServiceTests` に関連テストあり
- Implications: 削除量は多いが、全て単純な削除で複雑なリファクタリングは不要

## Design Decisions

### Decision: 無音タイムアウトの完全削除 vs オプション化
- Context: 要件では「無効化（またはオプション化）」とあった
- Alternatives Considered:
  1. 完全削除 — コードの簡素化
  2. 設定でオン/オフ切替 — 柔軟性維持
- Selected Approach: 完全削除
- Rationale: 個人用アプリで配布予定なし。ホットキー手動制御に統一することで複雑性を排除。将来必要になれば git から復元可能
- Trade-offs: 再導入時に再実装が必要だが、要件が明確なのでシンプルさを優先

## Risks & Mitigations
- 長時間録音によるメモリ増加 — 音声認識は逐次処理されるため蓄積は認識テキストのみ、影響は軽微
