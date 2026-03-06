# Research & Design Decisions

## Summary
- Feature: `filler-removal`
- Discovery Scope: Extension
- Key Findings:
  - `TextPostprocessorImpl.process()` は4段階の変換パイプライン構造。新ルールは既存ステップの間に挿入可能
  - フィラーは単独語として出現するため、正規表現による単語境界マッチで誤除去を防止できる
  - 既存の `textPostprocessingEnabled` フラグで有効/無効制御が自動的に適用される

## Research Log

### 日本語フィラーのパターン分析
- Context: WhisperKit Medium モデルの認識結果にフィラーが混入する事象の調査
- Findings:
  - 一般的な日本語フィラー: 「あー」「あ、」「えー」「えーと」「えっと」「うーん」「んー」「まあ」「ま、」「その」「なんか」「あの」
  - WhisperKit は長音記号（ー）を含む形で出力する傾向がある
  - フィラーは文頭・文中に出現し、前後にスペースまたは日本語文字が続く
- Implications: 正規表現で長音バリエーションを含むパターンリストを定義し、単語境界で照合する

### 既存パイプラインへの挿入位置
- Context: フィラー除去を既存の4段階処理のどこに挿入するか
- Findings:
  - Step 1（空白トリム）→ Step 2（連続スペース正規化）の後にフィラー除去を実行すると、スペース正規化済みのテキストに対してパターンマッチできる
  - Step 3（日本語文字間スペース除去）の前に実行する必要がある（フィラー除去後に残ったスペースを Step 3 で処理）
- Implications: フィラー除去は Step 2 と Step 3 の間に挿入する

## Design Decisions

### Decision: フィラーパターンの定義方式
- Context: フィラーリストをハードコードするか、設定可能にするか
- Alternatives Considered:
  1. 正規表現リテラルで直接定義 -- シンプル、変更時は再コンパイル
  2. 外部設定ファイルから読み込み -- 柔軟だが複雑
- Selected Approach: 正規表現リテラルで直接定義
- Rationale: 個人用アプリで配布予定なし。フィラーパターンの変更頻度は低く、コード内定義で十分
- Trade-offs: パターン追加時に再コンパイルが必要だが、影響は軽微

### Decision: フィラー除去のパイプライン挿入位置
- Context: 既存の4ステップ処理のどこにフィラー除去を追加するか
- Selected Approach: Step 2（連続スペース正規化）と Step 3（日本語文字間スペース除去）の間
- Rationale: スペース正規化後の安定した状態でパターンマッチし、フィラー除去後の余分なスペースは Step 3 以降で処理される

## Risks & Mitigations
- 「まあ」が意味のある副詞として使われる場合に誤除去 -- 単独出現（前後がスペースや文頭文末）のみを対象とし、文中で他の語と結合している場合は保持
