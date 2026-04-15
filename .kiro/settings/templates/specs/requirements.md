# Requirements Document

## Introduction
{{INTRODUCTION}}

## Requirements

### Requirement 1: {{REQUIREMENT_AREA_1}}
<!-- Requirement headings MUST include a leading numeric ID only (for example: "Requirement 1: ...", "1. Overview", "2 Feature: ..."). Alphabetic IDs like "Requirement A" are not allowed. -->
**Objective:** {{ROLE}} として、{{CAPABILITY}} したい。{{BENEFIT}} のため。

#### Acceptance Criteria

<!--
このプロジェクトでは Acceptance Criteria を以下の形式で記述する:
- 連番（1. 2. 3. ...）は振る舞いのサマリ見出し（太字）
- 配下に EARS のキーワード（When / If / While / Where / The Kuchibi app shall）ごとに
  ハイフン箇条書きで改行して列挙する（ネストしない、同じインデントレベルに揃える）
- 1 つの条件に対する応答は、条件行の直後に shall 行を置いて隣接させることで対応を示す

EARS のトリガー語（When / If / While / Where / The Kuchibi app shall）は英語のまま保持し、
可変部分のみ日本語にする。
-->

1. **[サマリ見出し: この項目が扱う振る舞い]**
   - When [イベント]
   - The Kuchibi app shall [応答]
   - If [条件]
   - The Kuchibi app shall [応答]
   - Where [前提]
   - The Kuchibi app shall [応答]

2. **[サマリ見出し: 次の振る舞い]**
   - The Kuchibi app shall [応答]
   - While [状態]
   - The Kuchibi app shall [応答]

### Requirement 2: {{REQUIREMENT_AREA_2}}
**Objective:** {{ROLE}} として、{{CAPABILITY}} したい。{{BENEFIT}} のため。

#### Acceptance Criteria

1. **[サマリ見出し]**
   - When [イベント]
   - The Kuchibi app shall [応答]
   - When [イベント] and [追加条件]
   - The Kuchibi app shall [応答]

<!-- 以降の要件も同じパターンに従う -->
