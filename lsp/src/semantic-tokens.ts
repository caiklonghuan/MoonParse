// MoonParse highlight capture → LSP semantic token type 映射

import type { MoonQuery, ParseTree, HighlightRange } from "../../wasm/moonparse.js";
import type { DocumentEntry } from "./document-manager.js";
import { byteRangeToUtf16 } from "./position.js";
import type { MoonParseRuntime } from "./runtime.js";
import { LANGUAGE_PACK_RESOURCES } from "./language-pack-resources.js";

// ── Token type 映射 ──

// LSP 标准 token type 列表（按索引对应）
export const TOKEN_TYPES = [
  "function",
  "variable",
  "keyword",
  "string",
  "number",
  "comment",
  "type",
  "operator",
] as const;

// ── VSCode 主题对照（供主题定制参考） ──
//
// LSP token type     TextMate scope
// ─────────────────  ────────────────────────────
// function           entity.name.function
// variable           variable.other.readwrite
// keyword            keyword.control
// string             string.quoted
// number             constant.numeric
// comment            comment.line / comment.block
// type               entity.name.type / support.type
// operator           keyword.operator
//
// VSCode 主题通过 "semanticHighlighting": true 启用 semantic tokens，
// 并在 theme.json 的 "semanticTokenColors" 段自定义每种 type 的颜色。

// MoonParse highlight capture → LSP token type 索引
const CAPTURE_TO_TYPE: Record<string, number> = {
  "function": 0,
  "method": 0,
  "constructor": 0,
  "variable": 1,
  "parameter": 1,
  "property": 1,
  "constant": 1,
  "label": 1,
  "keyword": 2,
  "string": 3,
  "escape": 3,
  "embedded": 3,
  "number": 4,
  "comment": 5,
  "type": 6,
  "enum": 6,
  "struct": 6,
  "module": 6,
  "attribute": 6,
  "tag": 6,
  "operator": 7,
  "punctuation": 7,
};

export function captureTokenTypeIndex(capture: string): number | undefined {
  return CAPTURE_TO_TYPE[capture.split(".", 1)[0]];
}

// 暂不使用 modifiers
export const TOKEN_MODIFIERS: string[] = [];

// ── 各语言 highlight query ──

// Grammar DSL
const GRAMMAR_DSL_HL = `
; rule name
(rule_definition name: (identifier) @function)
; keywords
("start") @keyword
("extras") @keyword
("conflicts") @keyword
("rule") @keyword
("prec.left") @keyword
("prec.right") @keyword
("prec.dynamic") @keyword
("prec") @keyword
("externals") @keyword
("word") @keyword
("token") @keyword
; literals
(string) @string
(regex) @string
(number) @number
; comment
(comment) @comment
`;

// C
const C_HL = `
(function_definition declarator: (identifier) @function)
(type_specifier) @type
("if") @keyword ("else") @keyword ("while") @keyword ("for") @keyword
("do") @keyword ("return") @keyword ("break") @keyword ("continue") @keyword
("switch") @keyword ("case") @keyword ("default") @keyword ("goto") @keyword
("sizeof") @keyword
("struct") @keyword ("enum") @keyword ("union") @keyword ("typedef") @keyword
("const") @keyword ("static") @keyword ("extern") @keyword ("volatile") @keyword ("register") @keyword
("void") @keyword ("char") @keyword ("short") @keyword ("int") @keyword
("long") @keyword ("float") @keyword ("double") @keyword ("signed") @keyword ("unsigned") @keyword
("+") @operator ("-") @operator ("*") @operator ("/") @operator ("%") @operator
("=") @operator ("+=") @operator ("-=") @operator ("*=") @operator ("/=") @operator ("%=") @operator
("==") @operator ("!=") @operator ("<") @operator (">") @operator ("<=") @operator (">=") @operator
("&&") @operator ("||") @operator ("!") @operator ("&") @operator ("|") @operator ("^") @operator
("<<") @operator (">>") @operator ("++") @operator ("--") @operator (".") @operator ("->") @operator
(string_literal) @string (number_literal) @number (char_literal) @string
(comment) @comment
`;

// Python
const PYTHON_HL = `
(function_definition name: (identifier) @function)
(class_definition name: (identifier) @type)
(type) @type
("def") @keyword ("class") @keyword ("async") @keyword ("await") @keyword
("if") @keyword ("elif") @keyword ("else") @keyword
("while") @keyword ("for") @keyword ("in") @keyword
("return") @keyword ("yield") @keyword ("raise") @keyword
("pass") @keyword ("break") @keyword ("continue") @keyword
("import") @keyword ("from") @keyword ("as") @keyword
("try") @keyword ("except") @keyword ("finally") @keyword
("with") @keyword ("global") @keyword ("nonlocal") @keyword ("del") @keyword
("assert") @keyword ("lambda") @keyword
("and") @keyword ("or") @keyword ("not") @keyword ("is") @keyword
("True") @keyword ("False") @keyword ("None") @keyword
(identifier) @variable
("+") @operator ("-") @operator ("*") @operator ("/") @operator ("%") @operator
("//") @operator ("**") @operator ("@") @operator
("==") @operator ("!=") @operator ("<") @operator (">") @operator ("<=") @operator (">=") @operator
("=") @operator ("+=") @operator ("-=") @operator ("*=") @operator ("/=") @operator
(string) @string (integer) @number (float) @number
(comment) @comment
`;

// JSON / JSON5（共用）
const JSON_HL = `
(pair key: (string) @variable)
(string) @string
(number) @number
("true") @keyword ("false") @keyword ("null") @keyword
("Infinity") @keyword ("NaN") @keyword
(comment) @comment
`;

// 语言 id → highlight query 字符串
const HL_QUERIES: Record<string, string> = {
  "__dsl__": GRAMMAR_DSL_HL,
  "c": C_HL,
  "python": LANGUAGE_PACK_RESOURCES.python.highlightQuery ?? PYTHON_HL,
  "json": LANGUAGE_PACK_RESOURCES.json.highlightQuery ?? JSON_HL,
  "json5": JSON_HL,
  "moonbit": LANGUAGE_PACK_RESOURCES.moonbit.highlightQuery ?? "",
};

// ── SemanticTokensManager ──

interface LanguageTokens {
  hlQuery: MoonQuery | null;
  compileError: string;
}

export class SemanticTokensManager {
  private cache = new Map<string, LanguageTokens>();

  constructor(private runtime: MoonParseRuntime) {}

  // 为某语言编译 highlight query（创建 parser 后调用一次）
  ensureQueries(languageId: string): void {
    if (this.cache.has(languageId)) return;

    const result: LanguageTokens = { hlQuery: null, compileError: "" };
    const pattern = HL_QUERIES[languageId];

    if (pattern && this.runtime.loaded) {
      try {
        result.hlQuery = this.runtime.compileQuery(pattern);
      } catch (err) {
        result.compileError = String(err);
      }
    }

    this.cache.set(languageId, result);
  }

  // 从 ParseTree 生成 LSP semantic tokens（全量）
  generateTokens(entry: DocumentEntry, tree: ParseTree): number[] | null {
    const bundleLanguage = this.runtime.getLanguage(entry.languageId);
    if (bundleLanguage) {
      try {
        return this.encodeTokens(entry, bundleLanguage.highlight(tree));
      } catch {
        return null;
      }
    }
    const lang = this.cache.get(entry.languageId);
    if (!lang?.hlQuery) return null;

    let highlights: HighlightRange[];
    try {
      highlights = this.runtime.highlightExec(lang.hlQuery, tree);
    } catch {
      return null;
    }

    if (highlights.length === 0) return [];

    return this.encodeTokens(entry, highlights);
  }

  // 从 ParseTree 生成指定范围内的 semantic tokens
  generateTokensRange(
    entry: DocumentEntry,
    tree: ParseTree,
    rangeStartByte: number,
    rangeEndByte: number,
  ): number[] | null {
    const bundleLanguage = this.runtime.getLanguage(entry.languageId);
    if (bundleLanguage) {
      try {
        const highlights = bundleLanguage.highlight(tree).filter(
          (h) => h.end_byte > rangeStartByte && h.start_byte < rangeEndByte,
        );
        return this.encodeTokens(entry, highlights);
      } catch {
        return null;
      }
    }
    const lang = this.cache.get(entry.languageId);
    if (!lang?.hlQuery) return null;

    let highlights: HighlightRange[];
    try {
      highlights = this.runtime.highlightExec(lang.hlQuery, tree);
    } catch {
      return null;
    }

    // 只保留与 [rangeStartByte, rangeEndByte) 有交集的 token
    const inRange = highlights.filter(
      (h) => h.end_byte > rangeStartByte && h.start_byte < rangeEndByte,
    );

    if (inRange.length === 0) return [];
    return this.encodeTokens(entry, inRange);
  }

  // ── 内部 delta 编码 ──

  private encodeTokens(
    entry: DocumentEntry,
    highlights: HighlightRange[],
  ): number[] {
    const sorted = highlights.filter(
      (h) => captureTokenTypeIndex(h.highlight) !== undefined,
    ).sort((a, b) => {
      if (a.start_byte !== b.start_byte) return a.start_byte - b.start_byte;
      return a.end_byte - b.end_byte;
    });

    const data: number[] = [];
    let prevLine = 0;
    let prevChar = 0;

    for (const h of sorted) {
      const lspRange = byteRangeToUtf16(
        entry.text,
        entry.lineOffsets,
        h.start_byte,
        h.end_byte,
      );

      const line = lspRange.start.line;
      const char = lspRange.start.character;
      const len = Math.max(lspRange.end.character - lspRange.start.character, 1);

      const deltaLine = line - prevLine;
      const deltaChar = deltaLine === 0 ? char - prevChar : char;

      data.push(deltaLine, deltaChar, len, captureTokenTypeIndex(h.highlight)!, 0);

      prevLine = line;
      prevChar = char;
    }

    return data;
  }

  // ── 资源管理 ──

  freeQueries(languageId: string): void {
    const lang = this.cache.get(languageId);
    if (lang?.hlQuery) {
      this.runtime.freeQuery(lang.hlQuery);
    }
    this.cache.delete(languageId);
  }

  dispose(): void {
    for (const [id] of this.cache) {
      this.freeQueries(id);
    }
    this.cache.clear();
  }
}
