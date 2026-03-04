# Requirements Document

## Introduction

音声認識セッションの実行状況を計測・記録し、認識品質の把握とチューニングに役立てるモニタリング機能を追加する。完全個人用のローカルアプリであるため、外部送信やダッシュボード等は不要で、ログベースの軽量な仕組みとする。

## Requirements

### Requirement 1: セッションメトリクスの収集

Objective: ユーザーとして、各セッションの統計情報を自動的に収集したい。認識品質を定量的に把握し設定チューニングの判断材料にするため。

#### Acceptance Criteria

1.1. When セッションが開始された時, the SessionManager shall セッション開始時刻を記録する
1.2. When セッションが完了した時, the SessionManager shall セッション継続時間（秒）を算出して記録する
1.3. When 認識テキストが確定した時, the SessionManager shall 確定テキストの文字数を累計する
1.4. When セッションが完了した時, the SessionManager shall 確定した行数を記録する
1.5. When セッションがエラーで終了した時, the SessionManager shall エラー種別を記録する

### Requirement 2: メトリクスのログ出力

Objective: ユーザーとして、セッションメトリクスを os.Logger でログ出力したい。macOS Console.app で認識品質を確認できるようにするため。

#### Acceptance Criteria

2.1. When セッションが完了した時, the MonitoringService shall セッション継続時間、確定行数、合計文字数を含むサマリーログを info レベルで出力する
2.2. When セッションがエラーで終了した時, the MonitoringService shall エラー種別を含むログを error レベルで出力する

### Requirement 3: 設定

Objective: ユーザーとして、モニタリング機能のオン・オフを切り替えたい。不要なログ出力を抑制するため。

#### Acceptance Criteria

3.1. The AppSettings shall モニタリング有効フラグ（デフォルト: 有効）を提供する
3.2. When モニタリングが無効の場合, the SessionManager shall メトリクスの収集とログ出力を行わない
3.3. When 設定画面でモニタリングの有効・無効を切り替えた時, the SettingsView shall 次回セッションから設定を反映する
