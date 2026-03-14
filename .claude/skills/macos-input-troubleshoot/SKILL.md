---
name: macos-input-troubleshoot
description: |
  macOS アプリにおける音声入力・テキスト直接入力・CGEvent・アクセシビリティ権限のトラブルシューティングガイド。
  以下のいずれかに当てはまるときにこのスキルを使用すること：
  (1) CGEvent でキーイベントを送信しているが対象アプリに入力が届かない
  (2) AXIsProcessTrusted が false を返す、またはアクセシビリティ権限が付与済みなのに動かない
  (3) アプリのビルド・インストール後に TCC 権限がリセットされる
  (4) CGEvent の post が「成功」するが実際には何も起きない（サイレント失敗）
  (5) AppleScript の keystroke が届かない
  (6) macOS の入力監視・アクセシビリティ・オートメーション権限の問題
  (7) 音声認識結果をアクティブアプリに自動入力する機能のデバッグ
  音声入力、直接入力、ペースト、CGEvent、AXUIElement、TCC、権限、アクセシビリティ、入力監視といったキーワードが出たら積極的に参照すること。
---

# macOS 入力トラブルシューティングガイド

macOS でテキストをプログラム的にアクティブアプリに入力する際に発生する問題の診断と解決パターン集。

## 診断フローチャート

問題: テキストがアクティブアプリに入力されない

```
1. AXIsProcessTrusted() は true か？
   ├─ false → 「権限が付与されていない」を参照
   └─ true → 2 へ
2. CGEvent の生成は成功するか？（nil ではないか）
   ├─ nil → 「CGEvent 生成失敗」を参照
   └─ 非 nil → 3 へ
3. CGEvent を post しても何も起きない
   → 「CGEvent サイレント失敗」を参照
```

## よくある原因と解決策

### 権限が付与されていない

症状: `AXIsProcessTrusted()` が `false` を返す。ユーザーは権限を付与したと思っている。

原因:
- アプリの再インストール（`rm -rf` + `cp -R`）で TCC データベースのエントリが無効化された
- システム設定で許可しているのは古いパスのアプリ（DerivedData 内のビルド等）
- codesign の identity が変わったため macOS が別アプリと認識している

解決策:

1. インストールプロセスを `rsync` + `codesign` に変更して TCC 権限を維持する:

```makefile
# NG: rm -rf で TCC エントリが無効化される
install:
    rm -rf "/Applications/MyApp.app"
    cp -R "$(BUILT_APP)" "/Applications/MyApp.app"

# OK: rsync で差分更新し、codesign でアプリ identity を維持
install:
    rsync -a --delete "$(BUILT_APP)/" "/Applications/MyApp.app/"
    codesign --force --sign - "/Applications/MyApp.app"
```

2. 起動時に `AXIsProcessTrustedWithOptions` で権限プロンプトを明示的に表示する:

```swift
import ApplicationServices

let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(options)
```

`AXIsProcessTrusted()` は権限がなくても何も表示しない。`AXIsProcessTrustedWithOptions` の prompt オプションを使うとシステム設定を開くダイアログが表示される。

### CGEvent サイレント失敗

症状: `CGEvent()` コンストラクタは non-nil を返すが、`post()` しても対象アプリにイベントが届かない。

原因:
- CGEvent は生成時にはアクセシビリティ権限を検証しない
- `post()` はエラーを返さない（void）
- macOS 15 以降、一部の tap ポイントが制限されている

解決策:

1. CGEventSource の stateID を `combinedSessionState` にする（`hidSystemState` は macOS 15 で制限あり）:

```swift
// NG
let source = CGEventSource(stateID: .hidSystemState)

// OK
let source = CGEventSource(stateID: .combinedSessionState)
```

2. tap 先を `cgSessionEventTap` にする:

```swift
// NG: macOS 15 で制限される場合がある
event.post(tap: .cghidEventTap)
event.post(tap: .cgAnnotatedSessionEventTap)

// OK
event.post(tap: .cgSessionEventTap)
```

3. Unicode 直接入力の場合は `keyboardSetUnicodeString` を使う:

```swift
let source = CGEventSource(stateID: .combinedSessionState)
for scalar in text.unicodeScalars {
    let utf16 = Array(String(scalar).utf16)
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
        return false
    }
    keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
    keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
    keyDown.post(tap: .cgSessionEventTap)
    keyUp.post(tap: .cgSessionEventTap)
}
```

### AppleScript が届かない

症状: `NSAppleScript` でエラーは出ないが keystroke が対象アプリに届かない。

原因:
- Automation 権限（System Events へのアクセス）が付与されていない
- `NSAppleScript.executeAndReturnError` はスクリプトの実行自体が成功すれば true を返すが、keystroke が実際に届いたかは検証しない

確認方法:

```swift
let seScript = NSAppleScript(source: """
    tell application "System Events"
        return name of first process whose frontmost is true
    end tell
""")
var error: NSDictionary?
let result = seScript?.executeAndReturnError(&error)
// error があれば Automation 権限がない
```

### AXUIElement 経由の直接挿入が失敗

症状: `kAXSelectedTextAttribute` への書き込みが `.success` にならない。

原因:
- 多くのアプリは `kAXSelectedTextAttribute` の設定をサポートしていない
- ネイティブ NSTextField/NSTextView 系以外では動作しないことが多い
- Electron アプリ（VSCode 等）では role が `AXWebArea` になり非対応

対処: AXUIElement は「試してダメならフォールバック」の位置付けにする。メインの入力手段にはしない。

## 診断機能の実装パターン

Console.app でのログ確認が難しいユーザー向けに、ファイルベースの診断レポートを推奨:

```swift
func runDiagnostics() async -> String {
    var report = "=== 入力診断レポート ===\n"

    // 1. アクセシビリティ権限
    report += "[権限] AXIsProcessTrusted: \(AXIsProcessTrusted())\n"

    // 2. AXUIElement テスト
    let systemWide = AXUIElementCreateSystemWide()
    var focusedElement: AnyObject?
    let result = AXUIElementCopyAttributeValue(
        systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement
    )
    report += "[AXUIElement] \(result == .success ? "OK" : "失敗 (\(result.rawValue))")\n"

    // 3. CGEvent 生成テスト
    let source = CGEventSource(stateID: .combinedSessionState)
    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
    report += "[CGEvent] \(event != nil ? "生成成功" : "生成失敗")\n"

    // 4. System Events アクセステスト
    let script = NSAppleScript(source: """
        tell application "System Events"
            return name of first process whose frontmost is true
        end tell
    """)
    var error: NSDictionary?
    script?.executeAndReturnError(&error)
    report += "[System Events] \(error == nil ? "OK" : "失敗")\n"

    // ファイルに保存
    let path = NSHomeDirectory() + "/Desktop/input-diag.txt"
    try? report.write(toFile: path, atomically: true, encoding: .utf8)
    return report
}
```

## macOS 権限の種類と対応

| 権限 | 必要な操作 | 確認方法 | 設定パス |
|------|-----------|---------|---------|
| アクセシビリティ | CGEvent post, AXUIElement | `AXIsProcessTrusted()` | プライバシーとセキュリティ > アクセシビリティ |
| オートメーション | AppleScript System Events | NSAppleScript 実行エラー | プライバシーとセキュリティ > オートメーション |
| 入力監視 | CGEvent (macOS 15+で必要な場合あり) | 設定で確認 | プライバシーとセキュリティ > 入力監視 |
| マイク | 音声キャプチャ | `AVCaptureDevice.authorizationStatus(for: .audio)` | プライバシーとセキュリティ > マイク |

## 推奨フォールバック戦略

信頼性の高い順:

1. CGEvent + `keyboardSetUnicodeString`（クリップボード非破壊、Unicode 対応）
2. AppleScript `keystroke "v" using command down`（クリップボード経由）
3. CGEvent で Cmd+V 送信（クリップボード経由）
4. AXUIElement `kAXSelectedTextAttribute` 設定（対応アプリが限定的）
5. クリップボードにコピーのみ（最終手段）

各手段は前の手段が失敗した場合のフォールバックとして順番に試行する。
