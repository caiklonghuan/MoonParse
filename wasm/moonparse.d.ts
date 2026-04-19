
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
  free(): void;
}


export declare class ParseTree {
  readonly handle: TreeHandle;
  readonly json: string;
  readonly root: CstNode;
  sexp(): string;
  errorSummary(): string;
  walk(): TreeCursor;
  query(pattern: string): CaptureResult[];
  highlight(hlQuery: MoonQuery, locsQuery?: MoonQuery): HighlightRange[];
  free(): void;
}


export declare class MoonParser {
  parse(source: string): ParseTree;
  parseIncremental(source: string, oldTree: ParseTree, edit: InputEdit): ParseTree;
  readonly dsl: string;
  tableJson(): string;
  /** 导出二进制解析表（由 build 命令或 serialize_table 生成的 MPT 格式）。 */
  tableBytes(): Uint8Array;
  diagnosticsJson(): string;
  free(): void;
}

export interface MoonParseInstance {
  createParser(dsl: string): MoonParser;
  createParserFromJson(tableJson: string): MoonParser;
  /** 从预编译的二进制解析表创建解析器（由 build 命令或 tableBytes() 导出的 MPT 字节）。 */
  createParserFromBytes(bytes: Uint8Array): MoonParser;
  /** 从 grammar_to_json 格式的 Grammar 对象直接编译解析器，无需手写 DSL 字符串。 */
  createParserFromGrammarObject(grammarObj: object): MoonParser;
  validateDsl(dsl: string): boolean;
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
