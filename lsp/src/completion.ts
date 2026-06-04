// textDocument/completion — 代码补全

import {
  CompletionItemKind,
  InsertTextFormat,
  type CompletionItem,
} from "vscode-languageserver";
import type { TreeCursor, ParseTree } from "../../wasm/moonparse.js";
import type { DocumentEntry } from "./document-manager.js";
import { utf16ToByteOffset } from "./position.js";
import type { SymbolIndex } from "./symbol-index.js";

// ── Grammar DSL 关键字 ──

interface KeywordItem {
  label: string;
  detail: string;
  insertText?: string;
}

const GRAMMAR_KEYWORDS: KeywordItem[] = [
  { label: "start", detail: "起始规则" },
  { label: "rule", detail: "定义语法规则", insertText: "rule ${1:name}: " },
  { label: "extras", detail: "额外 token（空白/注释）", insertText: "extras [" },
  { label: "conflicts", detail: "声明预期冲突", insertText: "conflicts [[" },
  { label: "externals", detail: "外部扫描器 token", insertText: "externals [" },
  { label: "word", detail: "关键字边界标记", insertText: "word " },
  { label: "prec.left", detail: "左结合优先级" },
  { label: "prec.right", detail: "右结合优先级" },
  { label: "prec.dynamic", detail: "动态优先级" },
  { label: "prec", detail: "优先级声明" },
  { label: "token", detail: "具名 token 定义" },
];

// prec 子项补全
const PREC_VARIANTS: KeywordItem[] = [
  { label: "left", detail: "左结合" },
  { label: "right", detail: "右结合" },
  { label: "dynamic", detail: "运行时决定" },
];

// ── Query 文件补全 ──

const QUERY_CAPTURES: string[] = [
  "function",
  "variable",
  "keyword",
  "string",
  "number",
  "comment",
  "type",
  "operator",
  "parameter",
  "method",
  "enum",
  "struct",
  "punctuation",
];

// ── 主入口 ──

export function getCompletions(
  entry: DocumentEntry,
  tree: ParseTree,
  symbolIdx: SymbolIndex,
  line: number,
  character: number,
): CompletionItem[] | null {
  const targetByte = utf16ToByteOffset(
    entry.text,
    entry.lineOffsets,
    line,
    character,
  );

  // 提取当前单词前缀
  const prefix = extractPrefix(entry.text, targetByte);

  // 根据语言和上下文返回补全
  if (entry.languageId === "__dsl__") {
    return grammarDslCompletions(entry, tree, symbolIdx, targetByte, prefix);
  }

  // query/scm 文件
  if (entry.languageId.endsWith("_query") || entry.uri.endsWith(".scm")) {
    return queryCompletions(entry, tree, targetByte, prefix);
  }

  // 通用：返回基础结构补全（当前仅关键字回退）
  return genericCompletions(entry, tree, targetByte, prefix);
}

// ── Grammar DSL 补全 ──

function grammarDslCompletions(
  entry: DocumentEntry,
  tree: ParseTree,
  symbolIdx: SymbolIndex,
  targetByte: number,
  prefix: string,
): CompletionItem[] {
  const cursor = tree.walk();
  const node = findCoveringNode(cursor, targetByte);
  cursor.free();

  // 默认提供关键字补全
  const items: CompletionItem[] = [];

  // 上下文判断：在 rule body 中补充已有 rule 名
  const inRuleBody = node && node.type !== "grammar" && !isTopLevel(node);

  if (inRuleBody) {
    // rule name 补全
    for (const name of symbolIdx.ruleNameSet()) {
      if (name.startsWith(prefix)) {
        items.push({
          label: name,
          kind: CompletionItemKind.Reference,
          detail: "rule reference",
        });
      }
    }
  } else {
    // 顶层关键字补全
    for (const kw of GRAMMAR_KEYWORDS) {
      if (kw.label.startsWith(prefix)) {
        const item: CompletionItem = {
          label: kw.label,
          kind: CompletionItemKind.Keyword,
          detail: kw.detail,
        };
        if (kw.insertText) {
          item.insertText = kw.insertText;
          item.insertTextFormat = InsertTextFormat.Snippet;
        }
        items.push(item);
      }
    }
  }

  // 如果前缀匹配 prec. 则补全子项
  if (prefix.includes(".")) {
    const afterDot = prefix.split(".").pop() ?? "";
    for (const v of PREC_VARIANTS) {
      if (v.label.startsWith(afterDot) && !items.some((i) => i.label === prefix + v.label)) {
        items.push({
          label: prefix.slice(0, prefix.lastIndexOf(".") + 1) + v.label,
          kind: CompletionItemKind.EnumMember,
          detail: v.detail,
        });
      }
    }
  }

  return items;
}

// ── Query 文件补全 ──

function queryCompletions(
  _entry: DocumentEntry,
  _tree: ParseTree,
  targetByte: number,
  prefix: string,
): CompletionItem[] {
  const items: CompletionItem[] = [];
  const textBefore = _entry.text.slice(0, targetByte);
  const lastAt = textBefore.lastIndexOf("@");
  const lastSpace = Math.max(
    textBefore.lastIndexOf(" "),
    textBefore.lastIndexOf("\n"),
    textBefore.lastIndexOf("("),
    textBefore.lastIndexOf(")"),
  );

  // 在 @ 之后补全 capture 名称
  if (lastAt > lastSpace) {
    const atPrefix = textBefore.slice(lastAt + 1);
    for (const cap of QUERY_CAPTURES) {
      if (cap.startsWith(atPrefix)) {
        items.push({
          label: cap,
          kind: CompletionItemKind.EnumMember,
          detail: "query capture",
        });
      }
    }
  }

  // 在 ( 之后且不在 @ 之后时补全 node type
  const lastParen = textBefore.lastIndexOf("(");
  if (lastParen > lastAt && lastParen > lastSpace) {
    const nodePrefix = textBefore.slice(lastParen + 1);
    const seenTypes = collectNamedTypes(_tree);
    for (const nt of seenTypes) {
      if (nt.startsWith(nodePrefix) && nt !== "source_file" && nt !== "grammar") {
        items.push({
          label: nt,
          kind: CompletionItemKind.Struct,
          detail: "node type",
        });
      }
    }
  }

  // 总是提供 capture 名称
  if (prefix.length >= 1 || (!lastAt && !lastSpace)) {
    for (const cap of QUERY_CAPTURES) {
      if (cap.startsWith(prefix) || prefix === "@" && cap.startsWith(prefix.slice(1))) {
        if (!items.some((i) => i.label === cap)) {
          items.push({
            label: prefix.startsWith("@") ? prefix.slice(1) + cap : cap,
            kind: CompletionItemKind.EnumMember,
            detail: "query capture",
          });
        }
      }
    }
  }

  void _tree;
  return items;
}

// ── 通用回退补全 ──

function genericCompletions(
  entry: DocumentEntry,
  tree: ParseTree,
  targetByte: number,
  prefix: string,
): CompletionItem[] {
  // 结构感知：列出当前 CST 中出现的具名节点类型作为候选
  const items: CompletionItem[] = [];
  const seen = new Set<string>();

  const cursor = tree.walk();
  if (cursor.gotoFirstChild()) {
    collectNamedTypesRec(cursor, seen);
    cursor.gotoParent();
  }
  cursor.free();

  for (const nt of seen) {
    if (nt.startsWith(prefix) && nt.length > 1) {
      items.push({
        label: nt,
        kind: CompletionItemKind.Struct,
        detail: "node type",
      });
    }
  }

  void entry;
  void targetByte;
  return items.slice(0, 30);
}

// ── 节点查找 ──

interface CoveringNode {
  type: string;
  isNamed: boolean;
}

function findCoveringNode(cursor: TreeCursor, targetByte: number): CoveringNode | null {
  if (!cursor.gotoFirstChild()) return null;

  let best: CoveringNode | null = null;

  function walk(): void {
    if (cursor.startByte <= targetByte && cursor.endByte >= targetByte) {
      best = { type: cursor.nodeType, isNamed: cursor.isNamed };
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

function isTopLevel(node: CoveringNode): boolean {
  const tl = [
    "grammar", "start_definition", "extras_definition",
    "conflicts_definition", "externals_definition", "word_definition",
  ];
  return tl.includes(node.type);
}

// ── 文本辅助 ──

// 从 targetByte 往前提取连续单词字符作为前缀
function extractPrefix(text: string, targetByte: number): string {
  if (targetByte <= 0) return "";
  let i = targetByte - 1;
  while (i >= 0 && isWordChar(text[i])) {
    i--;
  }
  return text.slice(i + 1, targetByte);
}

function isWordChar(ch: string): boolean {
  return /[a-zA-Z0-9_.@]/.test(ch);
}

// ── CST 节点类型收集 ──

function collectNamedTypesRec(cursor: TreeCursor, out: Set<string>): void {
  if (cursor.isNamed && cursor.nodeType.length > 0) {
    out.add(cursor.nodeType);
  }
  if (cursor.gotoFirstChild()) {
    do { collectNamedTypesRec(cursor, out); } while (cursor.gotoNextSibling());
    cursor.gotoParent();
  }
}

function collectNamedTypes(tree: ParseTree): string[] {
  const seen = new Set<string>();
  const cursor = tree.walk();
  if (cursor.gotoFirstChild()) {
    collectNamedTypesRec(cursor, seen);
    cursor.gotoParent();
  }
  cursor.free();
  return [...seen];
}
