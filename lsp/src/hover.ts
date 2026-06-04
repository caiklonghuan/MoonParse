// textDocument/hover — 光标悬停显示节点信息

import { MarkupKind, type Hover } from "vscode-languageserver";
import type { TreeCursor, ParseTree } from "../../wasm/moonparse.js";
import type { DocumentEntry } from "./document-manager.js";
import { byteOffsetToUtf16, utf16ToByteOffset } from "./position.js";

// ── 主入口 ──

// 返回光标位置处最小覆盖节点的 hover 信息
export function getHover(
  entry: DocumentEntry,
  tree: ParseTree,
  line: number,
  character: number,
): Hover | null {
  const targetByte = utf16ToByteOffset(
    entry.text,
    entry.lineOffsets,
    line,
    character,
  );

  const cursor = tree.walk();
  const node = findDeepestNode(cursor, targetByte);
  if (!node) {
    cursor.free();
    return null;
  }

  const content = formatHover(entry, node);
  cursor.free();

  if (!content) return null;

  const start = byteOffsetToUtf16(entry.text, entry.lineOffsets, node.startByte);
  const end = byteOffsetToUtf16(entry.text, entry.lineOffsets, node.endByte);

  return {
    contents: {
      kind: MarkupKind.Markdown,
      value: content,
    },
    range: { start, end },
  };
}

// ── 节点查找 ──

// 在 CST 中找到包含 targetByte 的最深层节点
interface NodeInfo {
  type: string;
  text: string;
  startByte: number;
  endByte: number;
  isNamed: boolean;
  field: string | null;
}

function findDeepestNode(cursor: TreeCursor, targetByte: number): NodeInfo | null {
  if (!cursor.gotoFirstChild()) return null;

  let best: NodeInfo | null = null;

  function walk(): void {
    if (cursor.startByte <= targetByte && cursor.endByte >= targetByte) {
      best = {
        type: cursor.nodeType,
        text: cursor.nodeText,
        startByte: cursor.startByte,
        endByte: cursor.endByte,
        isNamed: cursor.isNamed,
        field: cursor.nodeField,
      };
      // 继续向下找更深的匹配节点
      if (cursor.gotoFirstChild()) {
        do { walk(); } while (cursor.gotoNextSibling());
        cursor.gotoParent();
      }
    }
  }

  do { walk(); } while (cursor.gotoNextSibling());
  cursor.gotoParent();
  return best;
}

// ── 内容格式化 ──

function formatHover(entry: DocumentEntry, node: NodeInfo): string | null {
  switch (entry.languageId) {
    case "__dsl__":
      return formatGrammarHover(entry, node);
    default:
      return formatGenericHover(entry, node);
  }
}

// ── Grammar DSL hover ──

function formatGrammarHover(entry: DocumentEntry, node: NodeInfo): string | null {
  const t = node.type;

  // rule 定义体 — 显示完整定义
  if (t === "rule_definition") {
    return formatRuleDef(node);
  }

  // rule 体中的标识符 — 检查是否引用其他 rule
  if (t === "identifier" && node.isNamed) {
    return formatRuleRef(entry.text, node);
  }

  // 字符串 token 字面量
  if (t === "string") {
    return formatToken(node);
  }

  // regex 字面量
  if (t === "regex") {
    return formatRegex(node);
  }

  // conflicts 声明
  if (t === "conflicts") {
    return formatConflicts(node);
  }

  // prec 优先级声明
  if (t.startsWith("prec")) {
    return formatPrec(node);
  }

  // 字面量 token（匿名，如 "start", "extras"）
  if (!node.isNamed && node.text.length > 0) {
    return formatLiteral(node);
  }

  // 通用回退
  return formatGenericHover(entry, node);
}

// ── 格式化函数 ──

function formatRuleDef(node: NodeInfo): string {
  return [
    "**Rule definition**",
    "",
    "```",
    node.text,
    "```",
  ].join("\n");
}

function formatRuleRef(text: string, node: NodeInfo): string {
  // 在源文本中搜索同名 rule 定义
  const name = node.text;
  const defText = findRuleDefinition(text, name);

  const lines = ["**Rule reference** `" + name + "`"];
  if (defText) {
    lines.push("", "→ defined as:", "", "```", defText, "```");
  }
  return lines.join("\n");
}

function formatToken(node: NodeInfo): string {
  return [
    "**Token literal**",
    "",
    "```",
    node.text,
    "```",
  ].join("\n");
}

function formatRegex(node: NodeInfo): string {
  return [
    "**Regex token**",
    "",
    "```",
    node.text,
    "```",
  ].join("\n");
}

function formatConflicts(node: NodeInfo): string {
  return [
    "**Conflict declaration**",
    "",
    "Declares expected conflicts that the GLR engine will handle.",
    "",
    "```",
    node.text,
    "```",
  ].join("\n");
}

function formatPrec(node: NodeInfo): string {
  let desc = "";
  if (node.type.includes("left")) desc = "Left-associative precedence";
  else if (node.type.includes("right")) desc = "Right-associative precedence";
  else if (node.type.includes("dynamic")) desc = "Dynamic precedence (resolved at runtime)";
  else desc = "Precedence declaration";

  return [
    "**" + desc + "**",
    "",
    "```",
    node.text,
    "```",
  ].join("\n");
}

function formatLiteral(node: NodeInfo): string {
  const kw = [
    "start", "extras", "conflicts", "rule", "externals",
    "word", "token", "prec.left", "prec.right", "prec.dynamic",
    "prec",
  ];
  if (kw.includes(node.text)) {
    return `**Grammar keyword** \`${node.text}\``;
  }

  return [
    "**Literal token**",
    "",
    "```",
    node.text,
    "```",
  ].join("\n");
}

// ── 通用 hover：节点类型 + 字段名 + range + 文本 ──

function formatGenericHover(entry: DocumentEntry, node: NodeInfo): string | null {
  const start = byteOffsetToUtf16(entry.text, entry.lineOffsets, node.startByte);
  const end = byteOffsetToUtf16(entry.text, entry.lineOffsets, node.endByte);

  const lines: string[] = [];

  // 节点类型
  const kind = node.isNamed ? "named node" : "anonymous token";
  lines.push(`**${node.type}**  \`${kind}\``);

  // 字段名（如果存在）
  if (node.field) {
    lines.push(`field: \`${node.field}\``);
  }

  // range
  lines.push(
    `range: \`[${start.line}:${start.character}–${end.line}:${end.character}]\``,
  );

  // 节点文本（截断过长内容）
  if (node.text.length > 0) {
    const text = node.text.length > 200
      ? node.text.slice(0, 200) + "…"
      : node.text;
    lines.push("", "```", text, "```");
  }

  return lines.join("\n");
}

// ── 简化的 rule 引用查找 ──

// 在 grammar 源文本中用简单方式查找 `rule <name>` 定义
function findRuleDefinition(text: string, name: string): string | null {
  // 匹配 "rule name:" 或 "rule  name:" 等变体
  const re = new RegExp(
    `rule\\s+${escapeRegex(name)}\\s*:\\s*([^\\n]*(?:\\n\\s+[^\\n]*)*)`,
    "g",
  );
  const m = re.exec(text);
  if (!m) return null;

  let body = m[1].trim();
  // 多行截断
  if (body.length > 300) {
    body = body.slice(0, 300) + " …";
  }
  return `rule ${name}: ${body}`;
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
