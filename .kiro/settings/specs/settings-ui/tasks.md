# Implementation Plan

- [x] 1. (P) SettingsAccess SPM 依存を追加する
  - project.yml に SettingsAccess パッケージ（v2.1.0+）を追加し、ビルドが通ることを確認する
  - _Requirements: 1.2_

- [x] 2. (P) AppSettings クラスを作成する
- [x] 2.1 設定プロパティの定義と UserDefaults 永続化を実装する
  - 全設定プロパティ（outputMode, silenceTimeout, modelName, updateInterval, bufferSize）を `@Published` で公開する
  - 各プロパティに static なデフォルト値を定義する
  - `init` で UserDefaults から保存済みの値を復元し、未保存時はデフォルト値を使用する
  - 各プロパティの `didSet` で UserDefaults に即座に保存する
  - UserDefaults キーは `"setting.<propertyName>"` の命名規則に従う
  - 不正値（負数等）の検証を setter に含める
  - _Requirements: 2.1, 2.2, 2.3_

- [x] 2.2 全設定のデフォルト値一括リセット機能を実装する
  - `resetToDefaults()` メソッドで全プロパティをデフォルト値に戻す
  - 対応する UserDefaults キーもクリアする
  - _Requirements: 2.4_

- [x] 3. SettingsView を作成する
- [x] 3.1 TabView ベースの設定ウィンドウ構造を構築する
  - 「一般」と「音声認識」の2タブを持つ TabView を作成する
  - 各タブ内は Form を使用して設定項目を表示する
  - 後続 spec でタブやセクションを追加できる拡張可能な構造にする
  - _Requirements: 4.1, 4.3, 4.4_

- [x] 3.2 「一般」タブに出力モードとログイン時起動の設定を配置する
  - 出力モード（クリップボード / 直接入力）の Picker を配置し、AppSettings の outputMode にバインドする
  - ログイン時起動の Toggle を配置し、SMAppService を使用して制御する
  - 各設定項目にラベルと現在値を表示する
  - _Requirements: 3.1, 3.2, 4.2_

- [x] 3.3 「音声認識」タブにモデル情報とタイムアウト設定を配置し、リセットボタンを追加する
  - モデル名を読み取り専用テキストとして表示する
  - 無音タイムアウト（秒）を調整可能なコントロールとして表示する
  - 設定ウィンドウ下部に「デフォルトに戻す」ボタンを配置し、AppSettings の resetToDefaults() を呼び出す
  - _Requirements: 2.4, 4.2_

- [x] 4. KuchibiApp と MenuBarView を統合改修する
- [x] 4.1 KuchibiApp に Settings シーンを追加し、AppSettings を DI する
  - AppSettings を `@StateObject` として KuchibiApp に追加する
  - `body` に SwiftUI Settings シーンを追加し、SettingsView を表示する
  - AppSettings を SessionManager およびその他サービスの初期化に渡す
  - 設定ウィンドウ表示中もメニューバー常駐とホットキー受付が維持されることを確認する
  - _Requirements: 1.2, 1.3, 2.2_

- [x] 4.2 MenuBarView を簡素化し、SettingsLink による設定画面導線を追加する
  - 出力モード Picker とログイン時起動 Toggle を MenuBarView から除去する
  - SettingsAccess のカスタム SettingsLink を使用して「設定...」メニュー項目を追加する
  - ステータステキスト（待機中/録音中.../認識処理中...）と「終了」ボタンは維持する
  - 設定ウィンドウが既に表示中の場合は前面に持ってくる動作を確認する
  - _Requirements: 1.1, 1.4, 3.3, 3.4_

- [x] 4.3 SessionManager の outputMode 管理を AppSettings に移行する
  - SessionManager 内の outputMode プロパティと UserDefaults 管理コードを除去する
  - SessionManager が AppSettings の outputMode を参照するように変更する
  - 既存テストがあれば更新する
  - _Requirements: 2.1, 3.1_

- [x] 5. AppSettings のユニットテストを追加する
  - デフォルト値での初期化が正しく動作することを検証する
  - プロパティ変更が UserDefaults に永続化されることを検証する
  - UserDefaults に保存済みの値がある場合、init で正しく復元されることを検証する
  - resetToDefaults() で全プロパティがデフォルト値に戻ることを検証する
  - _Requirements: 2.1, 2.2, 2.3, 2.4_
