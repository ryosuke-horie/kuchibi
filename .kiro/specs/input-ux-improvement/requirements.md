# Requirements Document

## Introduction
音声認識結果のテキスト出力UXを改善する。現在の `clipboard`（クリップボードにコピー）と `directInput`（Cmd+V で貼り付け）に加え、カーソル位置への直接タイピング入力を優先し、入力不可の場合のみクリップボード貼り付けにフォールバックする新モードを導入する。この新モードを設定に追加し、デフォルトとする。

## Requirements

### Requirement 1: 直接タイピング入力モード

Objective: ユーザーとして、音声認識結果をカーソル位置に直接タイピングで入力したい。クリップボードの内容を破壊せずに済むため。

#### Acceptance Criteria
1. When 音声認識セッションが完了し出力モードが `autoInput` である場合, the kuchibi shall CGEvent を使用して認識結果テキストを1文字ずつキーボードイベントとしてアクティブアプリのカーソル位置に入力する
2. When 直接タイピング入力中にキーイベントの送信が失敗した場合, the kuchibi shall クリップボード経由の貼り付け（既存の `directInput` と同等の処理）にフォールバックする
3. The kuchibi shall 直接タイピング入力時にユーザーの既存クリップボード内容を変更しない

### Requirement 2: 出力モード設定の拡張

Objective: ユーザーとして、3つの出力モードから選択できるようにしたい。用途に応じて最適な入力方式を選べるため。

#### Acceptance Criteria
1. The kuchibi shall `OutputMode` に `autoInput` を新しい選択肢として追加する
2. The kuchibi shall 設定UIの出力モード Picker に `autoInput` の選択肢を表示する
3. The kuchibi shall `autoInput` モードの表示名を「自動入力（推奨）」とする
4. When アプリを新規インストールした場合, the kuchibi shall デフォルトの出力モードを `autoInput` に設定する

### Requirement 3: フォールバック動作

Objective: ユーザーとして、直接タイピングが利用できない状況でも確実にテキストが出力されるようにしたい。入力先がテキストフィールドでない場合でもテキストを取得できるため。

#### Acceptance Criteria
1. If CGEvent によるキーボードイベント送信が失敗した場合, the kuchibi shall 自動的にクリップボード経由の貼り付け（Cmd+V）にフォールバックする
2. If フォールバックが発生した場合, the kuchibi shall フォールバック完了後に元のクリップボード内容を復元する
3. The kuchibi shall フォールバック時も既存の `directInput` モードと同等の信頼性でテキストを出力する
