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
- ESC: 録音キャンセル（出力抑止）

## エンジンの主観評価手順

複数の音声認識エンジンを切り替えて主観的に精度比較できる。

### 対応エンジン

- **WhisperKit** (モデル: tiny / base / small / medium / large-v3-turbo)
- **Kotoba-Whisper Bilingual** v1（Q5 / Q8 量子化版、日英混交に強い）

### 手順

1. アプリを起動し、メニューバー > 設定 > 音声認識タブを開く
2. 「エンジン」Picker と「モデル」Picker で試したい組み合わせを選択
3. 切替は録音待機中（idle）に自動適用。録音中の変更は録音終了後に反映される
4. 同じ音声サンプルを用意（推奨）:
   - **日本語話し言葉サンプル**: 10〜30 秒程度の口語的な文章
   - **日英混交サンプル**: コード・IT 用語・固有名詞が混じる技術的な説明文
5. Cmd+Shift+Space で録音し、各エンジン × モデルで同じ内容を認識させる
6. 認識結果を比較してデフォルトとしたいエンジンを選定、Picker で最終選択

### Kotoba モデルの配置

Kotoba 系モデルは自動 DL されない。未配置のモデルは Picker で `(未配置)` 表示され選択不可。

1. 設定画面で Kotoba モデルを選ぶと配置ガイドバナーが表示される
2. 「HuggingFace で開く」ボタンでブラウザが開く
3. 表示された ggml `.bin` ファイルを `~/Library/Application Support/Kuchibi/models/` に保存
4. 「配置を確認」ボタンで再評価、disabled 解除を確認
