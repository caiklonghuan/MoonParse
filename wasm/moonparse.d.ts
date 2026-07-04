
export type ParserHandle = number;

export type TreeHandle = number;

export interface CstNode {
  type: string;
  is_named: boolean;
  is_error: boolean;
  is_missing: boolean;
  extra: boolean;
  field?: string;
  start_byte: number;
  end_byte: number;
  start_row: number;
  start_col: number;
  end_row: number;
  end_col: number;
  text?: string;
  children?: CstNode[];
}


export interface InputEdit {
  start_byte: number;
  old_end_byte: number;
  new_end_byte: number;
  start_row: number;
  start_col: number;
  old_end_row: number;
  old_end_col: number;
  new_end_row: number;
  new_end_col: number;
}

export interface IncrementalTraceRange {
  startByte: number;
  endByte: number;
  startRow: number;
  startCol: number;
  endRow: number;
  endCol: number;
}

export interface IncrementalReuseRange extends IncrementalTraceRange {
  kind: "leaf" | "subtree" | string;
}

export interface IncrementalTrace {
  edit: {
    oldRange: IncrementalTraceRange;
    newRange: IncrementalTraceRange;
  };
  reparseRange: IncrementalTraceRange;
  reusedRanges: IncrementalReuseRange[];
  reusedNodeCount: number;
  reusedByteCount: number;
  sourceByteLength: number;
  incrementalElapsedMs: number;
  fullBaselineElapsedMs: number | null;
  speedup: number | null;
  baselineError?: string;
}

export interface IncrementalTraceResult {
  tree: ParseTree;
  trace: IncrementalTrace;
}


export interface CaptureResult {
  match_id: number;
  capture: string;
  start: number;
  end: number;
  start_row: number;
  start_col: number;
  end_row: number;
  end_col: number;
  text: string;
}

export interface HighlightRange {
  highlight: string;
  start_byte: number;
  end_byte: number;
  start_row: number;
  start_col: number;
  end_row: number;
  end_col: number;
}

export declare class TreeCursor {
  readonly nodeType: string;
  readonly nodeText: string;
  readonly nodeField: string | null;
  readonly isNamed: boolean;
  readonly isError: boolean;
  readonly isMissing: boolean;
  readonly isExtra: boolean;
  readonly hasChanges: boolean;
  readonly isKeyword: boolean;
  readonly childCount: number;
  readonly namedChildCount: number;
  readonly startByte: number;
  readonly endByte: number;
  readonly startRow: number;
  readonly startCol: number;
  readonly endRow: number;
  readonly endCol: number;
  gotoFirstChild(): boolean;
  gotoNextSibling(): boolean;
  gotoParent(): boolean;
  free(): void;
}


export declare class MoonQuery {
  exec(tree: ParseTree): CaptureResult[];
  /** 在语法树上运行 locals 查询，返回局部变量解析结果（start_byte → true 的映射）。 */
  resolveLocals(tree: ParseTree): Record<string, boolean>;
  /** 在语法树上运行 binding 查询，返回完整 BindingGraph。 */
  resolveBindings(tree: ParseTree): BindingGraph;
  free(): void;
}

// ── BindingGraph（来自 query/bindings.mbt 的 JSON wire type） ──

export interface BindingScope {
  id: number;
  parent: number;
  start_byte: number;
  end_byte: number;
  kind: string;
}

export interface BindingDefinition {
  id: number;
  name: string;
  kind: string;
  ns: string;
  scope_id: number;
  start_byte: number;
  end_byte: number;
  declaration_start_byte?: number;
  declaration_end_byte?: number;
}

export interface BindingReference {
  id: number;
  name: string;
  kind: string;
  ns: string;
  scope_id: number;
  start_byte: number;
  end_byte: number;
  diagnose_unresolved?: boolean;
}

export interface BindingEdge {
  reference_id: number;
  definition_id: number;
}

export interface BindingDiagnostic {
  kind: string;
  message: string;
  reference_id: number;
  definition_id: number;
  start_byte: number;
  end_byte: number;
}

export interface BindingGraph {
  uri: string;
  scopes: BindingScope[];
  definitions: BindingDefinition[];
  references: BindingReference[];
  edges: BindingEdge[];
  diagnostics: BindingDiagnostic[];
}


export declare class ParseTree {
  readonly handle: TreeHandle;
  readonly json: string;
  readonly root: CstNode;
  sexp(): string;
  /** 导出带缩进、span 和叶子原文的完整调试树文本。 */
  text(): string;
  /** 导出隐藏 extras/token/零宽节点并折叠常见包装节点的简化调试树文本。 */
  prettyText(): string;
  errorSummary(): string;
  walk(): TreeCursor;
  query(pattern: string): CaptureResult[];
  highlight(hlQuery: MoonQuery, locsQuery?: MoonQuery): HighlightRange[];
  free(): void;
}


export declare class MoonParser {
  parse(source: string): ParseTree;
  parseIncremental(source: string, oldTree: ParseTree, edit: InputEdit): ParseTree;
  parseIncrementalTrace(source: string, oldTree: ParseTree, edit: InputEdit): IncrementalTraceResult;
  readonly dsl: string;
  tableJson(): string;
  /** 导出二进制解析表（由 build 命令或 serialize_table 生成的 MPT 格式）。 */
  tableBytes(): Uint8Array;
  diagnosticsJson(): string;
  free(): void;
}

export interface LanguageBundleCapabilities {
  highlights: boolean;
  locals: boolean;
  bindings: boolean;
  folding: boolean;
  modules: boolean;
  lint: boolean;
  rewrite: boolean;
  scanner: boolean;
}

export type LintSeverity = "hint" | "information" | "warning" | "error";

export type LintRuleSetting = "off" | LintSeverity;

export interface LintOptions {
  enabled?: boolean;
  ruleSets?: Record<string, boolean>;
  rules?: Record<string, LintRuleSetting>;
}

export interface LintTextEdit {
  startByte: number;
  endByte: number;
  replacement: string;
}

export interface LintFix {
  title: string;
  edit: LintTextEdit;
}

export interface LintDiagnostic {
  ruleId: string;
  message: string;
  severity: LintSeverity;
  startByte: number;
  endByte: number;
  fix: LintFix | null;
}

export type PackFiles = Record<string, string>;

export type PackDiagnosticSeverity = "info" | "warning" | "error";

export interface PackDiagnostic {
  code: string;
  severity: PackDiagnosticSeverity;
  message: string;
  path: string;
  line: number;
  column: number;
  hint: string | null;
}

export interface PackCheckResult {
  ok: boolean;
  diagnostics: PackDiagnostic[];
}

export type CorpusFailureKind = "error" | "sexp" | "contains" | "notContains" | "parse";

export interface CorpusFailure {
  kind: CorpusFailureKind;
  expected: string;
  actual: string;
  message: string;
}

export interface CorpusTestCaseResult {
  path: string;
  caseIndex: number;
  name: string;
  sourceLine: number;
  actualError: string;
  actualSexp: string;
  failures: CorpusFailure[];
  passed: boolean;
}

export interface PackTestResult {
  ok: boolean;
  diagnostics: PackDiagnostic[];
  cases: CorpusTestCaseResult[];
}

export interface CorpusSnapshotUpdate {
  caseIndex: number;
  caseName: string;
  sexp: string;
}

export interface SnapshotRewriteRequest {
  path: string;
  text: string;
  format: "moonparse-corpus-v1" | "moonparse-corpus-v2";
  updates: CorpusSnapshotUpdate[];
}

export interface SnapshotRewriteResult {
  ok: boolean;
  diagnostics: PackDiagnostic[];
  updatedText: string | null;
}

export declare class MoonLanguage {
  readonly id: string;
  readonly version: string;
  readonly name: string;
  readonly extensions: string[];
  readonly capabilities: LanguageBundleCapabilities;
  readonly bundle: object;
  readonly parser: MoonParser;
  parse(source: string): ParseTree;
  highlight(tree: ParseTree): HighlightRange[];
  resolveLocals(tree: ParseTree): Record<string, boolean>;
  resolveBindings(tree: ParseTree): BindingGraph;
  fold(tree: ParseTree): CaptureResult[];
  /** Run the Language Pack modules query. Returns [] when the capability is absent. */
  modules(tree: ParseTree): CaptureResult[];
  lint(tree: ParseTree, options?: LintOptions): LintDiagnostic[];
  free(): void;
}

export interface PackBuildResult {
  ok: boolean;
  diagnostics: PackDiagnostic[];
  bundleJson: string | null;
  language: MoonLanguage | null;
}

export interface MoonParseInstance {
  checkPack(files: PackFiles): PackCheckResult;
  buildPack(files: PackFiles): PackBuildResult;
  runCorpus(files: PackFiles): PackTestResult;
  rewriteCorpusSnapshots(request: SnapshotRewriteRequest): SnapshotRewriteResult;
  loadBundle(bundleJson: string): MoonLanguage;
  createParser(dsl: string): MoonParser;
  createParserFromJson(tableJson: string, builtinId?: string | null): MoonParser;
  /** 从预编译的二进制解析表创建解析器（由 build 命令或 tableBytes() 导出的 MPT 字节）。 */
  createParserFromBytes(bytes: Uint8Array): MoonParser;
  /** 从 grammar_to_json 格式的 Grammar 对象直接编译解析器，无需手写 DSL 字符串。 */
  createParserFromGrammarObject(grammarObj: object): MoonParser;
  validateDsl(dsl: string): boolean;
  /** 返回所有内置语法（JSON 格式），key 为 languageId。 */
  builtinGrammarsJson(): string;
  builtinBundlesJson(): string;
  /**
   * 对 DSL 字符串做纯语法 + 语义校验（不执行 tablegen），返回错误数组。
   * 无错误时返回空数组，有错误时返回 [{rule, kind?, message}, ...]。
   */
  validateDslErrors(dsl: string): Array<{ rule: string; kind?: string; message: string }>;
  compileQuery(pattern: string): MoonQuery;
  highlightNames(): string[];
  version(): string;
  /** 返回最近一次 parse() / parseIncremental() 的运行时错误信息。正常情况下返回空串。 */
  parseErrorLast(): string;
  /**
   * 调节 GLR 错误恢复参数，影响所有后续解析调用。
   * 省略的字段保留当前值（传 -1 同样表示"不修改"）。
   */
  setParseConfig(config: Partial<ParseConfig>): void;
  /** 将 GLR 错误恢复参数重置为默认值。 */
  resetParseConfig(): void;
  /**
   * 将行内字节偏移转换为字符列号（处理 UTF-8 多字节字符）。
   * @param source 完整源代码字符串
   * @param line 行号（0-based）
   * @param colBytes 行内字节偏移
   */
  byteOffsetToCharCol(source: string, line: number, colBytes: number): number;
}

/** GLR 错误恢复可调参数（所有字段均为正整数，省略时使用默认值）。 */
export interface ParseConfig {
  /** 跳过一棵子树的代价（默认 100）。 */
  errorCostPerSkippedTree: number;
  /** 跳过一个字符的代价（默认 1）。 */
  errorCostPerSkippedChar: number;
  /** 跳过一行的额外代价（默认 30）。 */
  errorCostPerSkippedLine: number;
  /** 插入一个 MISSING 节点的代价（默认 110）。 */
  errorCostPerMissingTree: number;
  /** 首次进入错误恢复的固定惩罚（默认 500）。 */
  errorCostPerRecovery: number;
  /** GLR 并行版本数上限（默认 6）。 */
  maxVersionCount: number;
  /** 超出 maxVersionCount 后的容忍量（默认 4）。 */
  maxVersionCountOverflow: number;
}

export declare function loadMoonParse(wasmUrl?: string): Promise<MoonParseInstance>;
