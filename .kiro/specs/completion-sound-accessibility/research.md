# Research & Design Decisions

---
**Purpose**: Capture discovery findings, architectural investigations, and rationale that inform the technical design.

---

## Summary

- **Feature**: `completion-sound-accessibility`
- **Discovery Scope**: Extension（既存 SessionManager・KuchibiApp への追加）
- **Key Findings**:
  - `NSSound(named:)` はローカル変数への代入のみで `play()` を呼ぶと、ARC により sound オブジェクトが再生完了前に解放される可能性がある。MenuBar アプリでは特に不安定。
  - `AudioServicesPlaySystemSound` (AudioToolbox) は C レベル API で、オブジェクトライフタイムを気にせず確実に再生できる。macOS 16 (Darwin 25) でも動作する。
  - `AXIsProcessTrusted()` は権限確認のみ。`AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` を使うとシステムダイアログを表示でき、ユーザーを設定アプリに誘導できる。

## Research Log

### NSSound 再生失敗の原因

- **Context**: ユーザーが「完了音が全く鳴らない」と報告。コードには `NSSound(named:).play()` が実装済み。
- **Sources Consulted**: Apple Developer Documentation — NSSound, AudioToolbox
- **Findings**:
  - `NSSound(named:)` が返すインスタンスを局所変数に代入して `play()` を呼ぶと、非同期再生中に ARC がオブジェクトを解放するリスクがある。
  - macOS 15+ (Darwin 24+) 以降、MenuBarExtra ベースのアプリでは NSSound の再生が安定しない事例が報告されている。
  - `AudioServicesPlaySystemSound` は再生完了コールバックを内部で保持するため、呼び出し元のスコープに依存しない。
- **Implications**: 完了音・開始音を両方 `AudioServicesPlaySystemSound` に変更する。

### AudioToolbox システムサウンド ID

- **Context**: 既存の "Pop" / "Tink" に対応するシステムサウンド ID が必要。
- **Findings**:
  - Tink: `1057` (macOS 内部 ID)
  - Pop: `1054` (macOS 内部 ID)
  - セッション開始音 → `1057` (Tink に相当)、完了音 → `1054` (Pop に相当)
- **Implications**: `AudioToolbox` を import し、定数として管理する。

### AXIsProcessTrustedWithOptions によるプロンプト

- **Context**: アクセシビリティ権限が未取得の場合、現在はクリップボードフォールバックの通知のみ。プロンプト表示が必要。
- **Findings**:
  - `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)` はシステムダイアログを表示し、設定 > プライバシーとセキュリティ > アクセシビリティ への誘導を行う。
  - `kAXTrustedCheckOptionPrompt` を `true` にすると初回呼び出し時のみダイアログが出るが、毎回権限チェックを行い false を返せばその都度プロンプトを表示できる。
  - アプリ起動直後（UIが安定する前）に呼ぶと macOS がダイアログを表示しないケースがあるため、起動後に非同期（短い遅延）で呼ぶ。
- **Implications**: `KuchibiApp.init()` 内で `Task { try? await Task.sleep(for: .seconds(1)); if !AXIsProcessTrusted() { AXIsProcessTrustedWithOptions(...) } }` パターンを採用。

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| NSSound 保持 | SessionManager に NSSound を @MainActor プロパティとして保持 | 既存 API のまま | macOS 16 での安定性不明 | 暫定対策にしかならない |
| AudioServicesPlaySystemSound | AudioToolbox の C API 使用 | 確実・軽量・OS バージョン依存なし | システムサウンド ID が非公式 | 採用 |
| AVAudioPlayer | AVFoundation で .aiff ファイルを直接再生 | 完全なコントロール | ファイルパス解決が必要・過剰 | 不採用 |

## Design Decisions

### Decision: NSSound から AudioServicesPlaySystemSound への移行

- **Context**: 完了音・開始音が再生されない（macOS 16 + MenuBarExtra 環境）
- **Alternatives Considered**:
  1. NSSound を @MainActor プロパティとして保持 — ARC 問題は解決するが macOS バージョン依存
  2. AudioServicesPlaySystemSound — OS レベルの API でライフタイム管理不要
- **Selected Approach**: `AudioServicesPlaySystemSound(1054)` (Pop), `AudioServicesPlaySystemSound(1057)` (Tink)
- **Rationale**: C API はオブジェクトライフタイムに依存せず、あらゆる macOS バージョンで安定動作する
- **Trade-offs**: サウンド ID が非公式定数なため、将来の macOS で変わる可能性があるが、その場合 `kSystemSoundID_UserPreferredAlert` にフォールバックできる

### Decision: 起動時アクセシビリティ権限プロンプト

- **Context**: 権限がないと directInput/autoInput がサイレントにクリップボードフォールバックする
- **Alternatives Considered**:
  1. SettingsView にボタンを追加して手動でプロンプト起動
  2. 起動時に自動プロンプト（1秒遅延）
- **Selected Approach**: 起動後 1 秒遅延で権限を確認し、未取得なら `AXIsProcessTrustedWithOptions` でシステムダイアログを表示。さらにセッション終了時（directInput/autoInput でフォールバック時）にも再度プロンプトを表示する。
- **Rationale**: ユーザーの操作なしに初回起動で権限を取得できる
- **Trade-offs**: 1 秒遅延は経験値ベース。UI が完全に準備できていれば即時でも可

## Risks & Mitigations

- AudioToolbox のサウンド ID (1054/1057) が将来の macOS で変わるリスク — `kSystemSoundID_UserPreferredAlert` をフォールバックとして用意
- 起動時プロンプトがユーザーに煩わしいと感じられるリスク — 権限が既に取得済みの場合はプロンプトを出さない条件分岐で対処
- directInput/autoInput モード使用時に毎回プロンプトが出るリスク — フォールバック通知は既存の UNUserNotification を維持しつつ、プロンプトは一度だけ（再起動まで）表示する

## References

- Apple Developer Documentation — AudioToolbox: AudioServicesPlaySystemSound
- Apple Developer Documentation — Accessibility: AXIsProcessTrustedWithOptions
