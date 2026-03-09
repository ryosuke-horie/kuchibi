# Requirements Document

## Project Description (Input)

ホットキーを1度押して録音開始、2度目のホットキー押下で録音停止後に文字起こし処理（`.processing` 状態）が走る間、ユーザーに処理中であることを視覚的・UX的に伝えるインジケーターを実装する。
現状は `.processing` 状態でフィードバックバーが非表示になるため、ユーザーが処理中かどうかわからない。

## Introduction

本機能は、macOS 音声入力アプリ「くちび」において、録音停止後の文字起こし処理中（`.processing` 状態）にユーザーへ視覚的フィードバックを提供する。
ホットキー操作後に処理が進行していることを明示することで、ユーザーが操作結果を待てるようにする。

## Requirements

### Requirement 1: 処理中フィードバックバーの継続表示

**Objective:** ユーザーとして、録音を停止した後も文字起こしが完了するまでフィードバックバーが表示され続けることを望む。それにより、アプリが処理を続けていることを確認できる。

#### Acceptance Criteria

1. When ホットキーが2回目に押されて `.recording` から `.processing` に状態遷移した, the FeedbackBar shall 画面上のフィードバックバーウィンドウを表示し続ける
2. When `.processing` 状態が終了して `.idle` に遷移した, the FeedbackBar shall フィードバックバーウィンドウを非表示にする
3. While `.processing` 状態である, the FeedbackBar shall フィードバックバーウィンドウが画面に表示されている状態を維持する
4. When `.idle` 状態でホットキーが押されて `.recording` に遷移した, the FeedbackBar shall フィードバックバーウィンドウを新たに表示する

### Requirement 2: 処理中専用アニメーションの表示

**Objective:** ユーザーとして、録音中の音量バーとは異なる専用アニメーションを処理中に見ることを望む。それにより、録音が終了して文字起こし処理中であることを直感的に判断できる。

#### Acceptance Criteria

1. While `.processing` 状態である, the FeedbackBar shall 音量レベルバーの代わりに処理中アニメーションを表示する
2. While `.processing` 状態である, the FeedbackBar shall 音声入力と無関係な自律的なアニメーション（例: ウェーブ・パルス）を再生する
3. When `.processing` 状態に遷移した, the FeedbackBar shall アニメーションを即座に開始する
4. When `.processing` 状態が終了した, the FeedbackBar shall アニメーションを停止する
5. The FeedbackBar shall 処理中アニメーションを `.recording` 中の音量バーアニメーションと視覚的に区別できるデザインにする

### Requirement 3: 処理中ラベルの表示

**Objective:** ユーザーとして、文字起こし処理中であることをテキストで確認したい。それにより、アプリの現在の状態を即座に理解できる。

#### Acceptance Criteria

1. While `.processing` 状態である, the FeedbackBar shall "文字起こし中..." のような処理中を示すテキストラベルを表示する
2. While `.processing` 状態である, the FeedbackBar shall 録音中に表示していた部分テキスト（partialText）を表示しない
3. The FeedbackBar shall 処理中ラベルのテキストをユーザーが直感的に理解できる日本語で表示する

### Requirement 4: 状態遷移時のスムーズな切り替え

**Objective:** ユーザーとして、録音中から処理中への表示切り替えが自然に感じられることを望む。それにより、UX の連続性が保たれ、不自然なちらつきが生じない。

#### Acceptance Criteria

1. When `.recording` から `.processing` へ遷移した, the FeedbackBar shall フィードバックバーウィンドウを閉じることなく表示内容を切り替える
2. When `.processing` から `.idle` へ遷移した, the FeedbackBar shall フィードバックバーウィンドウを非表示にする
3. The FeedbackBar shall 状態遷移時にウィンドウの再生成（close → open）なしに表示内容の差し替えだけで切り替えを完了する
