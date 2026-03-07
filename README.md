# kuchibi

macOS で動作する個人用音声入力アプリ。ホットキー（Cmd+Shift+Space）で録音を開始・停止し、文字起こし結果をクリップボードへコピーまたはアクティブアプリに自動入力する。

## セットアップ

### 1. ビルドとインストール

Makefile を使ってビルドからインストール・起動まで実行できる。

初回（または再ビルド後）:

```bash
make build    # Xcode でビルド
make run      # /Applications にインストールして起動
```

その他のコマンド:

```bash
make install  # /Applications にインストール（起動なし）
make clean    # ビルドキャッシュを削除
```

> [!NOTE]
> `make run` / `make install` を実行する前に `make build` が必要。ビルド前に実行するとエラーになる。

### 2. /Applications へのインストール理由（自動入力に必要）

自動入力（directInput / autoInput モード）には macOS のアクセシビリティ権限が必要。
DerivedData のビルドでは権限が毎ビルドごとにリセットされるため、`/Applications` にインストールして使用すること。

再ビルド後は `make run` を再実行してインストールしなおす。

### 3. アクセシビリティ権限の付与

システム設定 > プライバシーとセキュリティ > アクセシビリティ で `/Applications/Kuchibi.app` を追加してオンにする。

権限を付与後はアプリの再起動不要で自動入力が有効になる。

## ホットキー

- Cmd+Shift+Space: 録音開始 / 停止
