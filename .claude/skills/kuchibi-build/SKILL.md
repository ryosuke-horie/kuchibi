---
name: kuchibi-build
description: >
  Kuchibi アプリをビルドして /Applications にインストールし起動するまでの実行手順。
  PR をマージした後、main ブランチを更新した後、コードを変更してコミットした後、
  実装が完了した後は必ずこのスキルを参照して make run まで実行すること。
  コミット・マージ・プッシュなどの変更操作の完了後に自動的に適用する。
  「ビルドして動作確認したい」「変更を反映したい」「アプリを更新して起動したい」
  「アクセシビリティ権限ダイアログが毎回出る」といった状況でも参照する。
---

# Kuchibi ビルド・インストール手順

## 前提

Kuchibi は常に `/Applications/Kuchibi.app` を使って動作確認する。
DerivedData のビルド結果を直接起動することはない。

アクセシビリティ権限（directInput / autoInput の自動貼り付け）は
`/Applications/Kuchibi.app` に対して付与されており、初回のみ設定が必要。
`make run` でインストールしなおしても同じパスなので再付与不要。

## いつ make run を実行するか

以下のタイミングで必ず `make run` を実行する（ユーザーが言わなくても自発的に行う）：

- PR をマージした後
- main ブランチを更新した後（`git pull`, `git merge` 後）
- コードを変更してコミットした後
- 実装タスクが完了した後

## make run の実行

```bash
# プロジェクトルートで実行
make run
```

これ一発で完結する：
1. 既存の /Applications/Kuchibi.app を終了
2. DerivedData のビルド済みアプリを /Applications にコピー
3. /Applications/Kuchibi.app を起動

## make コマンド一覧

| コマンド | 内容 |
|---------|------|
| `make run` | インストール + 起動（標準手順） |
| `make install` | インストールのみ（起動なし） |
| `make build` | Xcode ビルドのみ |
| `make clean` | DerivedData キャッシュ削除 |

## アクセシビリティ権限（初回のみ）

システム設定 > プライバシーとセキュリティ > アクセシビリティ で
`/Applications/Kuchibi.app` を追加してオンにする。
以降は `make run` で更新するたびに自動で維持される。

## 動作確認チェックリスト

- [ ] Tink 音が鳴る（ホットキー1回目 = 録音開始）
- [ ] Pop 音が鳴る（ホットキー2回目 = 録音停止 + 出力完了）
- [ ] directInput / autoInput でテキストが自動貼り付けされる
- [ ] 起動時に不要なアクセシビリティ権限ダイアログが出ない
