# Research & Design Decisions

## Summary
- Feature: `recognition-monitoring`
- Discovery Scope: Extension
- Key Findings:
  - SessionManager には既に `os.Logger` によるログ基盤が存在し、同じパターンで拡張可能
  - プロトコルベース DI が全サービスで統一されており、MonitoringService も同パターンで注入
  - メトリクス収集はセッション単位の値オブジェクトで管理し、セッション完了時にログ出力する設計が最もシンプル

## Research Log

### 既存ログ基盤の分析
- Context: 現在のモニタリング状況を把握するため
- Sources Consulted: SessionManager.swift, NotificationService.swift, KuchibiError.swift
- Findings:
  - `os.Logger(subsystem: "com.kuchibi.app", category: "SessionManager")` で基本ログ出力済み
  - セッション開始、停止、完了、エラーのログポイントが既に存在
  - KuchibiError enum でエラー種別が型安全に定義済み
  - メトリクス（継続時間、文字数等）の収集・記録の仕組みは未実装
- Implications: 既存の Logger パターンに合わせて category を分けるだけで統合可能

### DI パターンの確認
- Context: MonitoringService の注入方式を決定するため
- Sources Consulted: SessionManager.swift の init シグネチャ
- Findings:
  - init パラメータにプロトコル型 + デフォルト実装のパターンが確立
  - AudioPreprocessing, TextPostprocessing と同じ方式で追加可能
- Implications: `SessionMonitoring` プロトコルを定義し、デフォルト引数で実装を注入

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| SessionManager 内蔵 | メトリクス収集をSessionManager内に直接実装 | 変更が少ない | 単一責任原則に反する、テスト困難 | 不採用 |
| 専用 MonitoringService | プロトコル + 実装クラスとして分離 | テスト容易、関心分離、既存パターン準拠 | ファイル数が増える | 採用 |

## Design Decisions

### Decision: メトリクス収集の責務分離
- Context: SessionManager が肥大化しつつあり、モニタリングロジックの追加場所を決定する必要がある
- Alternatives Considered:
  1. SessionManager に直接メトリクス変数を追加
  2. 専用の MonitoringService にメトリクス収集とログ出力を委譲
- Selected Approach: 専用 MonitoringService
- Rationale: 既存の DI パターンに合致し、テスト時にモック差し替え可能
- Trade-offs: ファイル数増加 vs テスト容易性・保守性

### Decision: ログ出力のみ（永続化なし）
- Context: 完全個人用アプリであり、複雑な分析基盤は不要
- Selected Approach: os.Logger によるログ出力のみ
- Rationale: Console.app で確認可能、永続化層の追加コストを避ける
- Trade-offs: 過去データの集計不可 vs シンプルさ

## Risks & Mitigations
- メトリクス収集のパフォーマンス影響 -- 軽量な値の加算のみなので無視可能
- ログ出力量の増大 -- モニタリング無効時は一切出力しないガード付き
