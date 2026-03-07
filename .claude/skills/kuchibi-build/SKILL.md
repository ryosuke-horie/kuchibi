---
name: kuchibi-build
description: >
  Kuchibi アプリを /Applications にインストールして起動するための make run 実行手順。
  以下のいずれかに当てはまるときは必ずこのスキルを呼び出すこと：
  (1) git push・PR マージ・main ブランチ更新の直後
  (2) 「ビルドして確認したい」「アプリで動作確認したい」「変更を反映して」「最新版で動かして」
  (3) 「アクセシビリティ権限ダイアログが毎回出る」「kuchibi を起動したら権限を求められた」
  (4) 「make run を実行して」「インストールして起動して」
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

- git push を実行した後
- PR をマージした後
- main ブランチを更新した後（`git pull`, `git merge` 後）
- ユーザーが「アプリに反映されてる？」「確認したい」「動かして」と言ったとき

git commit 単体（push なし）では実行しない。コミットはローカル操作であり、
アプリを更新するには push や明示的な確認依頼が必要なため。

重要: make run は Bash ツールで直接実行するのではなく、必ずこのスキル（Skill ツール）を
経由して呼び出すこと。チェックリストのユーザー確認まで含めて完結させること。

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

make run 実行後、以下のチェックリストを AskUserQuestion ツールで提示してユーザーに確認を依頼すること。

- [ ] Tink 音が鳴る（ホットキー1回目 = 録音開始）
- [ ] Pop 音が鳴る（ホットキー2回目 = 録音停止 + 出力完了）
- [ ] directInput / autoInput でテキストが自動貼り付けされる
- [ ] 起動時に不要なアクセシビリティ権限ダイアログが出ない
- [ ] 録音中に ESC キーで即時キャンセルできる（Basso 音・テキスト出力なし）
