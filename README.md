# kuchibi

macOS で動作する個人用音声入力アプリ。ホットキー（Cmd+Shift+Space）で録音を開始・停止し、文字起こし結果をクリップボードへコピーまたはアクティブアプリに自動入力する。

## セットアップ

### 1. ビルド

Xcode でビルドする。

### 2. /Applications へのインストール（自動入力に必要）

自動入力（directInput / autoInput モード）には macOS のアクセシビリティ権限が必要。
DerivedData のビルドでは権限が毎ビルドごとにリセットされるため、`/Applications` にインストールして使用すること。

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/Kuchibi-*/Build/Products/Debug/Kuchibi.app /Applications/
```

再ビルド後はこのコマンドを再実行してインストールしなおす。

### 3. アクセシビリティ権限の付与

システム設定 > プライバシーとセキュリティ > アクセシビリティ で `/Applications/Kuchibi.app` を追加してオンにする。

権限を付与後はアプリの再起動不要で自動入力が有効になる。

## ホットキー

- Cmd+Shift+Space: 録音開始 / 停止
