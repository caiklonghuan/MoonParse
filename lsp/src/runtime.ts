// MoonParse WASM 运行时封装
// 负责加载 WASM、管理 parser/tree/cursor/query 生命周期

import {
  loadMoonParse,
  TreeCursor,
  MoonQuery,
  type MoonParseInstance,
  type MoonParser,
  type ParseTree,
  type InputEdit,
  type CaptureResult,
  type HighlightRange,
  type CstNode,
  type ParseConfig,
  type MoonLanguage,
} from "../../wasm/moonparse.js";

import type { Logger } from "./logger.js";

// ── 资源句柄类型 ──

// 单个 parser 缓存条目
interface ParserCache {
  parser: MoonParser;
  languageId: string;
  language?: MoonLanguage;
}

// ── CST 错误节点（供 diagnostics 转换用） ──

export interface CstErrorNode {
  message: string;
  startByte: number;
  endByte: number;
  isError: boolean; // true=ERROR（多余 token），false=MISSING（缺失 token）
}

// ── MoonParseRuntime ──

export class MoonParseRuntime {
  private mp: MoonParseInstance | null = null;
  private parsers = new Map<string, ParserCache>();
  private _loaded = false;

  // 资源追踪，保证 dispose 时全部释放
  private trees = new Set<ParseTree>();
  private cursors = new Set<TreeCursor>();
  private queries = new Set<MoonQuery>();

  constructor(
    private logger: Logger,
    private wasmPath: string,
  ) {}

  // 是否已完成 WASM 加载
  get loaded(): boolean {
    return this._loaded;
  }

  // ── 加载 WASM ──

  async init(): Promise<void> {
    if (this._loaded) return;

    this.logger.info(`正在加载 MoonParse WASM: ${this.wasmPath}`);
    try {
      this.mp = await loadMoonParse(this.wasmPath);
      this._loaded = true;
      this.logger.info(`MoonParse WASM 加载成功 (v${this.mp.version()})`);
    } catch (err) {
      this.logger.error(`WASM 加载失败: ${safeErr(err)}`);
      throw err;
    }
  }

  // ── Parser 创建 ──

  // 从二进制解析表创建 parser（内置语法用）
  createFromBytes(languageId: string, bytes: Uint8Array): MoonParser {
    this.ensureLoaded();
    this.freeParser(languageId);

    const parser = this.mp!.createParserFromBytes(bytes);
    this.parsers.set(languageId, { parser, languageId });
    this.logger.info(`parser 已创建: ${languageId} (from bytes, ${bytes.length} 字节)`);
    return parser;
  }

  // 从 Grammar DSL 文本创建 parser
  createFromDsl(languageId: string, dsl: string): MoonParser {
    this.ensureLoaded();
    this.freeParser(languageId);

    const parser = this.mp!.createParser(dsl);
    this.parsers.set(languageId, { parser, languageId });
    this.logger.info(`parser 已创建: ${languageId} (from dsl, ${dsl.length} 字符)`);
    return parser;
  }

  // 从语法 JSON 对象创建 parser
  createFromGrammarJson(languageId: string, grammarObj: object): MoonParser {
    this.ensureLoaded();
    this.freeParser(languageId);

    const parser = this.mp!.createParserFromGrammarObject(grammarObj);
    this.parsers.set(languageId, { parser, languageId });
    this.logger.info(`parser 已创建: ${languageId} (from grammar json)`);
    return parser;
  }

  // 从内置 WASM grammar 数据创建 parser
  // builtin_grammars_json() 返回 { langId: dslString, ... }
  createFromBuiltinGrammar(languageId: string): MoonParser | null {
    this.ensureLoaded();
    this.freeParser(languageId);

    try {
      const bundles = JSON.parse(
        this.mp!.builtinBundlesJson?.() ?? "{}",
      ) as Record<string, string>;
      if (bundles[languageId]) {
        return this.loadBundle(bundles[languageId]).parser;
      }
      const builtinsJson = this.mp!.builtinGrammarsJson?.() ?? "{}";
      const all = JSON.parse(builtinsJson) as Record<string, string>;
      const dsl = all[languageId];
      if (!dsl) {
        this.logger.trace(`内置语法未找到: ${languageId}`);
        return null;
      }
      // builtin DSL 字符串 → createParser(dsl)
      const parser = this.mp!.createParser(dsl);
      this.parsers.set(languageId, { parser, languageId });
      this.logger.info(`parser 已创建: ${languageId} (from builtin dsl)`);
      return parser;
    } catch {
      this.logger.error(`内置语法解析失败: ${languageId}`);
      return null;
    }
  }

  // 从 LanguageBundle 创建语言。先完成全部验证，再原子替换旧实例。
  loadBundle(bundleJson: string): MoonLanguage {
    this.ensureLoaded();
    const language = this.mp!.loadBundle(bundleJson);
    const previous = this.parsers.get(language.id);
    this.parsers.set(language.id, {
      parser: language.parser,
      languageId: language.id,
      language,
    });
    if (previous) {
      try {
        if (previous.language) previous.language.free();
        else previous.parser.free();
      } catch { /* 保留已经成功注册的新语言 */ }
    }
    this.logger.info(`LanguageBundle 已加载: ${language.id}@${language.version}`);
    return language;
  }

  getLanguage(languageId: string): MoonLanguage | undefined {
    return this.parsers.get(languageId)?.language;
  }

  // ── 解析 ──

  // 全量解析，返回的 tree 自动纳入资源追踪
  parseFull(languageId: string, source: string): ParseTree {
    this.ensureLoaded();
    const cached = this.parsers.get(languageId);
    if (!cached) {
      throw new Error(`parser 未找到: ${languageId}`);
    }
    const tree = cached.parser.parse(source);
    this.trackTree(tree);
    return tree;
  }

  // 增量解析，oldTree 会被自动释放
  parseIncremental(
    languageId: string,
    source: string,
    oldTree: ParseTree,
    edit: InputEdit,
  ): ParseTree {
    this.ensureLoaded();
    const cached = this.parsers.get(languageId);
    if (!cached) {
      throw new Error(`parser 未找到: ${languageId}`);
    }
    // 增量解析（需要旧 tree handle），完成后释放旧 tree
    const tree = cached.parser.parseIncremental(source, oldTree, edit);
    this.freeTree(oldTree);
    this.trackTree(tree);
    return tree;
  }

  // ── 缓存管理 ──

  hasParser(languageId: string): boolean {
    return this.parsers.has(languageId);
  }

  getParser(languageId: string): MoonParser | undefined {
    return this.parsers.get(languageId)?.parser;
  }

  freeParser(languageId: string): void {
    const cached = this.parsers.get(languageId);
    if (cached) {
      try {
        if (cached.language) cached.language.free();
        else cached.parser.free();
      } catch { /* 忽略 */ }
      this.parsers.delete(languageId);
    }
  }

  // ── 错误摘要（tree → 结构化错误列表） ──

  // 从 CST 中提取 ERROR / MISSING 节点
  collectErrors(tree: ParseTree): CstErrorNode[] {
    const errors: CstErrorNode[] = [];
    this.walkErrorNodes(tree.root, errors);
    return errors;
  }

  // 错误摘要文本（debug 用）
  treeErrorSummary(tree: ParseTree): string {
    return tree.errorSummary();
  }

  // ── Cursor 遍历 ──

  // 创建游标，自动纳入资源追踪
  createCursor(tree: ParseTree): TreeCursor {
    const cursor = tree.walk();
    this.trackCursor(cursor);
    return cursor;
  }

  // ── Query 编译 & 执行 ──

  // 编译查询模式，自动纳入资源追踪
  compileQuery(pattern: string): MoonQuery {
    this.ensureLoaded();
    const query = this.mp!.compileQuery(pattern);
    this.trackQuery(query);
    return query;
  }

  // 在树上执行查询
  queryExec(query: MoonQuery, tree: ParseTree): CaptureResult[] {
    return query.exec(tree);
  }

  // 局部变量解析
  queryResolveLocals(query: MoonQuery, tree: ParseTree): Record<string, boolean> {
    return query.resolveLocals(tree);
  }

  // 通用名称绑定解析（scope + definition + reference + edge + diagnostic）
  queryResolveBindings(query: MoonQuery, tree: ParseTree): import("../../wasm/moonparse.js").BindingGraph {
    return query.resolveBindings(tree);
  }

  // ── Highlight ──

  // 执行高亮查询
  highlightExec(hlQuery: MoonQuery, tree: ParseTree): HighlightRange[] {
    return tree.highlight(hlQuery);
  }

  // 带局部变量的高亮查询
  highlightExecWithLocals(
    hlQuery: MoonQuery,
    locsQuery: MoonQuery,
    tree: ParseTree,
  ): HighlightRange[] {
    return tree.highlight(hlQuery, locsQuery);
  }

  // 列出所有可用的高亮名称
  highlightNames(): string[] {
    this.ensureLoaded();
    return this.mp!.highlightNames();
  }

  // ── DSL 校验 ──

  validateDsl(dsl: string): boolean {
    this.ensureLoaded();
    return this.mp!.validateDsl(dsl);
  }

  validateDslErrors(dsl: string): Array<{ rule: string; kind?: string; message: string }> {
    this.ensureLoaded();
    return this.mp!.validateDslErrors(dsl);
  }

  // ── 配置 ──

  setParseConfig(config: Partial<ParseConfig>): void {
    if (this.mp) this.mp.setParseConfig(config);
  }

  resetParseConfig(): void {
    if (this.mp) this.mp.resetParseConfig();
  }

  // ── 工具 ──

  version(): string {
    return this.mp?.version() ?? "not loaded";
  }

  parseErrorLast(): string {
    return this.mp?.parseErrorLast() ?? "";
  }

  byteOffsetToCharCol(source: string, line: number, colBytes: number): number {
    if (!this.mp) return colBytes;
    return this.mp.byteOffsetToCharCol(source, line, colBytes);
  }

  // ── 资源追踪 & 释放 ──

  // 将 tree 纳入追踪
  private trackTree(tree: ParseTree): void {
    this.trees.add(tree);
  }

  // 将 cursor 纳入追踪
  private trackCursor(cursor: TreeCursor): void {
    this.cursors.add(cursor);
  }

  // 将 query 纳入追踪
  private trackQuery(query: MoonQuery): void {
    this.queries.add(query);
  }

  // 释放单个 tree
  freeTree(tree: ParseTree): void {
    if (this.trees.has(tree)) {
      try { tree.free(); } catch { /* 忽略 */ }
      this.trees.delete(tree);
    }
  }

  // 释放单个 cursor
  freeCursor(cursor: TreeCursor): void {
    if (this.cursors.has(cursor)) {
      try { cursor.free(); } catch { /* 忽略 */ }
      this.cursors.delete(cursor);
    }
  }

  // 释放单个 query
  freeQuery(query: MoonQuery): void {
    if (this.queries.has(query)) {
      try { query.free(); } catch { /* 忽略 */ }
      this.queries.delete(query);
    }
  }

  // 释放所有资源
  dispose(): void {
    // 按依赖顺序释放：cursor → query → tree → parser
    for (const c of this.cursors) {
      try { c.free(); } catch { /* 忽略 */ }
    }
    this.cursors.clear();

    for (const q of this.queries) {
      try { q.free(); } catch { /* 忽略 */ }
    }
    this.queries.clear();

    for (const t of this.trees) {
      try { t.free(); } catch { /* 忽略 */ }
    }
    this.trees.clear();

    for (const [id] of this.parsers) {
      this.freeParser(id);
    }
    this.parsers.clear();

    this.mp = null;
    this._loaded = false;
  }

  // ── 内部 ──

  private ensureLoaded(): void {
    if (!this._loaded || !this.mp) {
      throw new Error("MoonParse WASM 未加载，请先调用 init()");
    }
  }

  // 递归遍历 CST，收集 ERROR / MISSING 节点并生成友好消息
  private walkErrorNodes(node: CstNode, out: CstErrorNode[]): void {
    if (node.is_error || node.is_missing) {
      const text = node.text ?? "";
      const typeStr = stripQuotes(node.type);
      let message: string;

      if (node.is_error) {
        // Unexpected token
        if (text.length > 0) {
          message = `Unexpected token '${text}'`;
        } else {
          message = `Unexpected token (${typeStr})`;
        }
      } else {
        // Missing token
        if (isCloseDelimiter(typeStr)) {
          message = `Unclosed construct — missing '${typeStr}'`;
        } else {
          message = `Missing '${typeStr}'`;
        }
      }

      out.push({
        message,
        startByte: node.start_byte,
        endByte: Math.max(node.end_byte, node.start_byte + 1),
        isError: node.is_error,
      });
    }
    if (node.children) {
      for (const child of node.children) {
        this.walkErrorNodes(child, out);
      }
    }
  }
}

function safeErr(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}

// 去掉 token 类型名首尾引号（MoonParse 匿名 token 如 "\"}\"" → "}"）
export function stripQuotes(t: string): string {
  if (t.length >= 2) {
    const first = t[0];
    const last = t[t.length - 1];
    if ((first === '"' || first === "'") && first === last) {
      return t.slice(1, -1);
    }
  }
  return t;
}

// 判断是否为闭合分隔符
export function isCloseDelimiter(t: string): boolean {
  return t === "}" || t === ")" || t === "]" ||
    t === "end" || t === "endif" || t === "fi" || t === "done" ||
    t.startsWith("end");
}
