## プロジェクト概要

完全個人用のmacOS内部で動作する、クライアントアプリ付きの音声入力ソフトを開発します。

基本的にはバックグラウンドで常駐する形で動作させ、AIのOSS（オープンソースソフトウェア）モデルを使用して音声認識を行います。私が日本語で喋った内容を文字起こし、またはストリーミングで入力しながら、コピペやクリップボードへの直接貼り付けなどができるようにするソフトウェアです。

操作については、ホットキーで呼び出す形を想定しています。
完全個人用で、ローカルで操作が完結すると考えているので、セキュリティについてはある程度目をつむって攻めた実装をすることができます。

これは配布するつもりは一切ありません。

## AIモデル

[WhisperKit](https://github.com/argmaxinc/WhisperKit) を使用。Whisper モデルサイズは tiny / base / small / medium / large-v2 / large-v3 から選択可能（デフォルト: base）。


# AI-DLC and Spec-Driven Development

Kiro-style Spec Driven Development implementation on AI-DLC (AI Development Life Cycle)

## Project Context

### Paths
- Steering: `.kiro/steering/`
- Specs: `.kiro/specs/`

### Steering vs Specification

Steering (`.kiro/steering/`) - Guide AI with project-wide rules and context
Specs (`.kiro/specs/`) - Formalize development process for individual features

### Active Specifications
- Check `.kiro/specs/` for active specifications
- Use `/kiro:spec-status [feature-name]` to check progress

## Development Guidelines
- Think in English, generate responses in Japanese. All Markdown content written to project files (e.g., requirements.md, design.md, tasks.md, research.md, validation reports) MUST be written in the target language configured for this specification (see spec.json.language).

## Minimal Workflow
- Phase 0 (optional): `/kiro:steering`, `/kiro:steering-custom`
- Phase 1 (Specification):
  - `/kiro:spec-init "description"`
  - `/kiro:spec-requirements {feature}`
  - `/kiro:validate-gap {feature}` (optional: for existing codebase)
  - `/kiro:spec-design {feature} [-y]`
  - `/kiro:validate-design {feature}` (optional: design review)
  - `/kiro:spec-tasks {feature} [-y]`
- Phase 2 (Implementation): `/kiro:spec-impl {feature} [tasks]`
  - `/kiro:validate-impl {feature}` (optional: after implementation)
- Progress check: `/kiro:spec-status {feature}` (use anytime)

## Development Rules
- 3-phase approval workflow: Requirements → Design → Tasks → Implementation
- Human review required each phase; use `-y` only for intentional fast-track
- Keep steering current and verify alignment with `/kiro:spec-status`
- Follow the user's instructions precisely, and within that scope act autonomously: gather the necessary context and complete the requested work end-to-end in this run, asking questions only when essential information is missing or the instructions are critically ambiguous.

## Steering Configuration
- Load entire `.kiro/steering/` as project memory
- Default files: `product.md`, `tech.md`, `structure.md`
- Custom files are supported (managed via `/kiro:steering-custom`)
