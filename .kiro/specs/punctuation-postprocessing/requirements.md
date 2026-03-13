# Requirements Document

## Introduction

音声認識（WhisperKit）が生成したテキストに対して、句読点を後処理で制御する機能。
読みやすさのために句点（。）を文末に自動付与するが、読点（、）は自動付与しない。
既存の `TextPostprocessor` に処理を追加する形で実装する。

## Requirements

### Requirement 1: 句点の自動付与

目的: 音声認識ユーザーとして、出力テキストの文末に句点（。）が付くことで、読みやすいテキストを得たい。

#### Acceptance Criteria

1. When 音声認識セッションが完了してテキストが確定した, the TextPostprocessor shall テキスト末尾に句点（。）が存在しない場合に限り「。」を追加する
2. When テキストが既に「。」「！」「!」「？」「?」で終わっている, the TextPostprocessor shall 句点を追加しない（重複防止）
3. When テキストが空文字列または空白のみ, the TextPostprocessor shall 句点を追加しない
4. The TextPostprocessor shall 句点付与処理は既存の後処理ステップ（フィラー除去・スペース正規化）の後に実行する

### Requirement 2: 読点の自動付与禁止

目的: 音声認識ユーザーとして、読点（、）が自動的に挿入されないことで、自然な文体を維持したい。

#### Acceptance Criteria

1. The TextPostprocessor shall WhisperKitが生成したテキスト中の読点（、）を追加・変更しない
2. The TextPostprocessor shall WhisperKitが出力した既存の読点（、）を削除しない
3. The TextPostprocessor shall 後処理ステップとして読点を独自に挿入するロジックを持たない

### Requirement 3: 既存後処理との統合

目的: 音声認識ユーザーとして、句点付与が既存の後処理（フィラー除去・スペース正規化）と一貫して動作することで、クリーンなテキスト出力を得たい。

#### Acceptance Criteria

1. The TextPostprocessor shall 句点付与処理をフィラー除去・スペース正規化の後の最終ステップとして実行する
2. When テキスト後処理パイプラインが実行される, the TextPostprocessor shall 句点付与の前にすべての正規化処理が完了していることを保証する
3. Where テキスト後処理機能（`textPostprocessingEnabled`）が無効の場合, the TextPostprocessor shall 句点自動付与処理も実行しない
