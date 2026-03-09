# Requirements Document

## Introduction

kuchibi アプリケーションに設定ウィンドウを追加する。現在、出力モードは MenuBarView 内の Picker で、ログイン時起動は同メニュー内のトグルで管理されており、それ以外の設定値（モデル名、バッファサイズ、updateInterval、無音タイムアウト等）はすべてソースコード上にハードコードされている。今後の精度改善機能（モデル切替、音声前処理、後処理等）を設定画面から制御可能にするため、まず設定の一元管理基盤と設定ウィンドウを整備する。

## Requirements

### Requirement 1: 設定ウィンドウの表示

Objective: ユーザーとして、メニューバーから設定ウィンドウを開きたい。各種設定を一箇所で確認・変更できるようにするため。

#### Acceptance Criteria
1. When ユーザーがメニューバーの状態メニューから「設定...」を選択した, the kuchibi shall 設定ウィンドウを表示する
2. The kuchibi shall 設定ウィンドウを macOS 標準の Settings シーン（SwiftUI Settings）で実装する
3. The kuchibi shall 設定ウィンドウ表示中もメニューバー常駐とホットキー受付を維持する
4. When 設定ウィンドウが既に表示されている状態で「設定...」が再選択された, the kuchibi shall 既存の設定ウィンドウを前面に持ってくる

### Requirement 2: 設定値の一元管理

Objective: ユーザーとして、変更した設定がアプリ再起動後も保持されてほしい。設定のたびに同じ操作を繰り返さなくて済むようにするため。

#### Acceptance Criteria
1. The kuchibi shall すべてのユーザー設定を単一の設定管理層（UserDefaults / @AppStorage）で永続化する
2. When アプリケーションが起動された, the kuchibi shall 保存済みの設定値を復元して各サービスに適用する
3. The kuchibi shall 現在ハードコードされている設定値（モデル名、無音タイムアウト、バッファサイズ、updateInterval）にデフォルト値を定義し、未設定時はデフォルト値を使用する
4. The kuchibi shall 全設定をデフォルト値に一括リセットする機能を設定ウィンドウに提供する

### Requirement 3: 既存設定の設定ウィンドウへの移行

Objective: ユーザーとして、出力モードやログイン時起動の設定も設定ウィンドウから変更したい。設定が分散せず一箇所にまとまっているようにするため。

#### Acceptance Criteria
1. The kuchibi shall 出力モード（クリップボード / 直接入力）の選択を設定ウィンドウに移動する
2. The kuchibi shall ログイン時起動のトグルを設定ウィンドウに移動する
3. When 既存設定が設定ウィンドウに移行された, the kuchibi shall MenuBarView のメニュー項目からこれらの設定コントロールを除去する
4. The kuchibi shall MenuBarView には現在の状態表示（ステータス、選択中の設定の概要）と「設定...」メニュー項目を残す

### Requirement 4: 設定カテゴリの構成

Objective: ユーザーとして、設定項目がカテゴリ別に整理されていてほしい。目的の設定をすばやく見つけられるようにするため。

#### Acceptance Criteria
1. The kuchibi shall 設定ウィンドウの項目を論理的なカテゴリ（一般、音声認識 等）に分類して表示する
2. The kuchibi shall 各カテゴリ内の設定項目にラベルと現在値を表示する
3. The kuchibi shall 今後追加される設定項目（モデル選択、前処理、後処理等）を収容できるカテゴリ構造を持つ
4. When 設定カテゴリが複数存在する場合, the kuchibi shall macOS 標準の設定ウィンドウと同様のナビゲーション（タブまたはサイドバー）を提供する
