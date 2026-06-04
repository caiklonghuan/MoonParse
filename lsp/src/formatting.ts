// textDocument/formatting — Grammar DSL 格式化

import { TextEdit, Range, type Position } from "vscode-languageserver";

// ── 主入口 ──

// 全量格式化 — 返回替换整个文档的 TextEdit
export function formatGrammar(text: string, pos: (line: number, char: number) => Position): TextEdit[] {
  const formatted = reformat(text);
  if (formatted === text) return [];

  const lines = text.split("\n");
  const endLine = Math.max(lines.length - 1, 0);
  const endChar = lines[endLine].length;

  return [
    {
      range: Range.create(pos(0, 0), pos(endLine, endChar)),
      newText: formatted,
    },
  ];
}

// 范围格式化 — 格式化指定范围（当前退化为全量，后续细化）
export function formatGrammarRange(
  text: string,
  _rangeStart: Position,
  _rangeEnd: Position,
  pos: (line: number, char: number) => Position,
): TextEdit[] {
  return formatGrammar(text, pos);
}

// ── 核心格式化 ──

function reformat(text: string): string {
  // 去掉首尾空行
  let t = text.trim();

  // 按声明拆分（顶级声明以关键字开头）
  const decls = splitDeclarations(t);
  if (decls.length === 0) return t;

  const out: string[] = [];
  for (let i = 0; i < decls.length; i++) {
    if (i > 0) out.push(""); // 声明间空一行
    out.push(formatDeclaration(decls[i]));
  }
  return out.join("\n") + "\n";
}

// ── 声明拆分 ──

// 顶级声明以 start / rule / extras / conflicts / externals / word 开头
const TOP_KEYWORDS = [
  "start ", "rule ", "extras ", "conflicts ", "externals ", "word ",
];

function splitDeclarations(text: string): string[] {
  const decls: string[] = [];
  let current = "";

  for (const line of text.split("\n")) {
    const trimmed = line.trimStart();
    if (hasPrefix(trimmed, TOP_KEYWORDS) && current.trim()) {
      decls.push(current.trimEnd());
      current = "";
    }
    current += (current ? "\n" : "") + line;
  }

  if (current.trim()) {
    decls.push(current.trimEnd());
  }

  return decls;
}

function hasPrefix(s: string, prefixes: string[]): boolean {
  for (const p of prefixes) {
    if (s.startsWith(p)) return true;
  }
  return false;
}

// ── 单条声明格式化 ──

function formatDeclaration(text: string): string {
  const trimmed = text.trim();

  if (trimmed.startsWith("start ")) {
    return formatStart(trimmed);
  }
  if (trimmed.startsWith("rule ")) {
    return formatRule(trimmed);
  }
  if (trimmed.startsWith("extras ")) {
    return formatExtras(trimmed);
  }
  if (trimmed.startsWith("conflicts ")) {
    return formatConflicts(trimmed);
  }
  if (trimmed.startsWith("externals ")) {
    return formatExternals(trimmed);
  }
  if (trimmed.startsWith("word ")) {
    return "word " + trimmed.slice("word ".length).trim();
  }

  return trimmed;
}

// ── 各声明类型格式化 ──

function formatStart(text: string): string {
  // start <name>  — 单行
  const body = text.slice("start ".length).trim();
  return "start " + body;
}

function formatRule(text: string): string {
  // rule <name>: <body>
  const afterRule = text.slice("rule ".length).trim();
  const colonPos = findColon(afterRule);
  if (colonPos < 0) return "rule " + afterRule;

  const name = afterRule.slice(0, colonPos).trim();
  let body = afterRule.slice(colonPos + 1).trim();

  // 格式化 rule body
  body = formatRuleBody(body);

  if (body) {
    return `rule ${name}: ${body}`;
  }
  return `rule ${name}:`;
}

// Rule body 格式化：保留结构，处理 | 分支
function formatRuleBody(body: string): string {
  // 去掉内部多余空格
  body = collapseSpaces(body);

  // 如果有 | 分支，保持原样但确保合理换行
  // （完整的 body 格式化需要 parser 支持，这里做基础清理）
  return body;
}

function formatExtras(text: string): string {
  // extras [...]  — 保持括号内容在一行（如果不太长）
  const after = text.slice("extras ".length).trim();
  // 规范化内部空格
  return "extras " + normalizeBrackets(after);
}

function formatConflicts(text: string): string {
  // conflicts [[...], [...]]  — 每个冲突组一行
  const after = text.slice("conflicts ".length).trim();

  // 如果太长则每个 [[ ]] 组单独一行
  if (after.length > 80) {
    const groups = splitConflictGroups(after);
    if (groups.length > 1) {
      const formatted = groups.map((g) => "  " + g).join("\n");
      return "conflicts [\n" + formatted + "\n]";
    }
  }

  return "conflicts " + normalizeBrackets(after);
}

function formatExternals(text: string): string {
  const after = text.slice("externals ".length).trim();
  return "externals " + normalizeBrackets(after);
}

// ── 辅助函数 ──

// 在规则文本中找冒号位置（不在括号/引号/正则里的冒号）
function findColon(s: string): number {
  let depth = 0;
  let inString = false;
  let inRegex = false;
  let inSlashSlash = false;

  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    const next = s[i + 1] ?? "";

    if (inSlashSlash) {
      if (ch === "\n") inSlashSlash = false;
      continue;
    }
    if (ch === "/" && next === "/") { inSlashSlash = true; continue; }
    if (ch === "/" && next !== "*" && !inString) { inRegex = !inRegex; continue; }
    if (inRegex) continue;
    if (ch === '"' || ch === "'") { inString = !inString; continue; }

    if (!inString && !inRegex) {
      if (ch === "(" || ch === "[") depth++;
      else if (ch === ")" || ch === "]") depth--;
      else if (ch === ":" && depth === 0) return i;
    }
  }
  return -1;
}

// 规范化括号内空格
function normalizeBrackets(s: string): string {
  // 在 [  (  后和 ]  )  ,  前保持合理空格
  return s
    .replace(/\s+/g, " ")
    .replace(/\[\s+/g, "[")
    .replace(/\s+\]/g, "]")
    .replace(/\s+,\s*/g, ", ")
    .replace(/\(\s+/g, "(")
    .replace(/\s+\)/g, ")")
    .trim();
}

// 将连续空白压缩为单个空格
function collapseSpaces(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

// 拆分 conflict 组
function splitConflictGroups(text: string): string[] {
  const groups: string[] = [];
  let depthBracket = 0;
  let depthParen = 0;
  let start = 0;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === "[") depthBracket++;
    else if (ch === "]") {
      depthBracket--;
      if (depthBracket === 0) {
        groups.push(text.slice(start, i + 1).trim());
        start = i + 1;
      }
    } else if (ch === "(") depthParen++;
    else if (ch === ")") depthParen--;
  }
  return groups;
}
