# Research & Design Decisions

## Summary
- Feature: `session-start-sound`
- Discovery Scope: Simple Addition
- Key Findings:
  - macOS の `NSSound` API でシステムサウンドを非同期再生できる
  - `NSSound(named:)` は `/System/Library/Sounds/` 配下のサウンドファイルを名前指定で再生可能
  - `play()` メソッドは非ブロッキングで即座に制御を返す

## Research Log

### macOS システムサウンド再生 API
- Context: セッション開始時に通知音を鳴らす手段の調査
- Sources Consulted: Apple Developer Documentation - NSSound
- Findings:
  - `NSSound(named: NSSound.Name("Tink"))?.play()` で OS 組み込みサウンドを再生可能
  - `play()` は非同期再生でメインスレッドをブロックしない
  - `AudioToolbox` の `AudioServicesPlaySystemSound` も選択肢だが、`NSSound` の方が API がシンプル
- Implications: 追加の依存関係やフレームワークの導入は不要。AppKit の `NSSound` のみで実現可能

### 統合ポイント分析
- Context: サウンド再生をどこに挿入するか
- Findings:
  - `SessionManager.startSession()` 内の `state = .recording` 設定直後が適切
  - 録音処理（`audioService.startCapture`）の成功後、実際にセッションが開始された時点で鳴らす
  - エラー時（マイク不可、モデル未ロード）はサウンドを鳴らさない
- Implications: 既存のガード節の後に配置することで、正常開始時のみサウンドが再生される

## Design Decisions

### Decision: NSSound による直接再生
- Context: システムサウンドを再生する手段の選択
- Alternatives Considered:
  1. `NSSound(named:)` — AppKit 組み込み、シンプルな API
  2. `AudioServicesPlaySystemSound` — AudioToolbox、低レベル API
  3. `AVAudioPlayer` — 高機能だが設定が複雑
- Selected Approach: `NSSound(named:)` を使用
- Rationale: 最もシンプルで、非ブロッキング再生がデフォルト動作。macOS デスクトップアプリに最適
- Trade-offs: カスタムサウンドファイルの再生にも対応可能だが、現時点ではシステムサウンドで十分
- Follow-up: 将来的にサウンドの種類を設定で変更可能にする余地あり

## Risks & Mitigations
- システムサウンドファイルが存在しない場合 — `NSSound(named:)` は nil を返すため `?.play()` で安全にスキップ
