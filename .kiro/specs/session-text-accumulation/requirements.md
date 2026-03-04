# Requirements Document

## Introduction

現在の SessionManager は lineCompleted イベントごとに OutputManager を呼び出してクリップボードを上書きしている。セッション中に複数行が認識された場合、最後の行しか残らず、細切れに喋った場合にテキストが失われる。本機能は、セッション開始から停止までの全認識テキストを蓄積し、セッション終了時にまとめて出力する仕組みを導入する。

## Requirements

### Requirement 1: セッション中のテキスト蓄積

Objective: ユーザーとして、セッション中に認識された全テキストを失わずに取得したい。これにより、一度の録音で喋った内容がすべて出力される。

#### Acceptance Criteria

1.1. When lineCompleted イベントが発生した, the SessionManager shall 確定テキストを内部バッファに追加する
1.2. While セッションが recording 状態である, the SessionManager shall lineCompleted のテキストを OutputManager に即座に渡さない
1.3. When セッションが開始された, the SessionManager shall 内部テキストバッファを空に初期化する

### Requirement 2: セッション終了時の一括出力

Objective: ユーザーとして、セッション停止時にすべての認識テキストがまとめて出力されるようにしたい。これにより、クリップボードや直接入力で完全なテキストが得られる。

#### Acceptance Criteria

2.1. When セッションが正常に終了した, the SessionManager shall 蓄積された全テキストを結合して OutputManager に出力する
2.2. When セッションが正常に終了し蓄積テキストが空である, the SessionManager shall OutputManager を呼び出さない
2.3. When 無音タイムアウトによりセッションが終了した, the SessionManager shall それまでに蓄積されたテキストを OutputManager に出力する

### Requirement 3: 後処理との統合

Objective: ユーザーとして、テキスト後処理が蓄積方式でも正しく適用されるようにしたい。これにより、後処理済みのテキストが出力される。

#### Acceptance Criteria

3.1. When lineCompleted イベントが発生しテキスト後処理が有効である, the SessionManager shall 後処理を適用した結果をバッファに追加する
3.2. When lineCompleted イベントが発生しテキスト後処理が無効である, the SessionManager shall 元のテキストをそのままバッファに追加する
