import {
  CompletionItemKind,
  InsertTextFormat,
  type CompletionItem,
} from "vscode-languageserver";

import type { ParseTree, TreeCursor } from "../../wasm/moonparse.js";
import type { DocumentEntry } from "./document-manager.js";
import type { BindingIndex } from "./binding-index.js";
import type { ParseTableInfo } from "./parse-table-info.js";
import { utf16ToByteOffset } from "./position.js";

interface KeywordItem {
  label: string;
  detail: string;
  insertText?: string;
}

const GRAMMAR_KEYWORDS: KeywordItem[] = [
  { label: "start", detail: "start rule" },
  { label: "rule", detail: "grammar rule", insertText: "rule ${1:name}: " },
  { label: "extras", detail: "extra tokens", insertText: "extras [" },
  { label: "conflicts", detail: "declared conflicts", insertText: "conflicts [[" },
  { label: "externals", detail: "external scanner tokens", insertText: "externals [" },
  { label: "word", detail: "word token", insertText: "word " },
  { label: "prec.left", detail: "left precedence" },
  { label: "prec.right", detail: "right precedence" },
  { label: "prec.dynamic", detail: "dynamic precedence" },
  { label: "prec", detail: "precedence" },
  { label: "token", detail: "named token" },
];

const PREC_VARIANTS: KeywordItem[] = [
  { label: "left", detail: "left associative" },
  { label: "right", detail: "right associative" },
  { label: "dynamic", detail: "dynamic precedence" },
];

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
  "scope",
  "definition",
  "reference",
  "reference.soft",
  "symbol",
  "fold",
  "fold.region",
  "fold.comment",
  "fold.imports",
];

export function getCompletions(
  entry: DocumentEntry,
  tree: ParseTree,
  bindingIndex: BindingIndex | undefined,
  tableInfo: ParseTableInfo,
  line: number,
  character: number,
): CompletionItem[] | null {
  const targetByte = utf16ToByteOffset(
    entry.text,
    entry.lineOffsets,
    line,
    character,
  );
  const prefix = extractPrefix(entry.text, targetByte);

  if (entry.languageId === "__dsl__") {
    return grammarDslCompletions(entry, tree, bindingIndex, targetByte, prefix);
  }

  if (entry.languageId.endsWith("_query") || entry.uri.endsWith(".scm")) {
    return queryCompletions(entry, tree, targetByte, prefix);
  }

  return genericCompletions(bindingIndex, tableInfo, targetByte, prefix);
}

function grammarDslCompletions(
  _entry: DocumentEntry,
  tree: ParseTree,
  bindingIndex: BindingIndex | undefined,
  targetByte: number,
  prefix: string,
): CompletionItem[] {
  const cursor = tree.walk();
  const node = findCoveringNode(cursor, targetByte);
  cursor.free();

  const items: CompletionItem[] = [];
  const inRuleBody = node && node.type !== "grammar" && !isTopLevel(node);

  if (inRuleBody) {
    for (const def of bindingIndex?.allDefinitions() ?? []) {
      if (def.kind === "rule" && def.name.startsWith(prefix)) {
        items.push({
          label: def.name,
          kind: CompletionItemKind.Reference,
          detail: "rule reference",
        });
      }
    }
  } else {
    for (const kw of GRAMMAR_KEYWORDS) {
      if (!kw.label.startsWith(prefix)) continue;
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

  if (prefix.includes(".")) {
    const afterDot = prefix.split(".").pop() ?? "";
    const stem = prefix.slice(0, prefix.lastIndexOf(".") + 1);
    for (const variant of PREC_VARIANTS) {
      const label = stem + variant.label;
      if (variant.label.startsWith(afterDot) && !items.some((item) => item.label === label)) {
        items.push({
          label,
          kind: CompletionItemKind.EnumMember,
          detail: variant.detail,
        });
      }
    }
  }

  return items;
}

function queryCompletions(
  entry: DocumentEntry,
  tree: ParseTree,
  targetByte: number,
  prefix: string,
): CompletionItem[] {
  const items: CompletionItem[] = [];
  const textBefore = entry.text.slice(0, targetByte);
  const lastAt = textBefore.lastIndexOf("@");
  const lastSpace = Math.max(
    textBefore.lastIndexOf(" "),
    textBefore.lastIndexOf("\n"),
    textBefore.lastIndexOf("("),
    textBefore.lastIndexOf(")"),
  );

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

  const lastParen = textBefore.lastIndexOf("(");
  if (lastParen > lastAt && lastParen > lastSpace) {
    const nodePrefix = textBefore.slice(lastParen + 1);
    for (const nt of collectNamedTypes(tree)) {
      if (nt.startsWith(nodePrefix) && nt !== "source_file" && nt !== "grammar") {
        items.push({
          label: nt,
          kind: CompletionItemKind.Struct,
          detail: "node type",
        });
      }
    }
  }

  if (prefix.length >= 1 || (!lastAt && !lastSpace)) {
    for (const cap of QUERY_CAPTURES) {
      if (cap.startsWith(prefix) || prefix === "@") {
        if (!items.some((item) => item.label === cap)) {
          items.push({
            label: cap,
            kind: CompletionItemKind.EnumMember,
            detail: "query capture",
          });
        }
      }
    }
  }

  return items;
}

function genericCompletions(
  bindingIndex: BindingIndex | undefined,
  tableInfo: ParseTableInfo,
  targetByte: number,
  prefix: string,
): CompletionItem[] {
  const items: CompletionItem[] = [];
  const seen = new Set<string>();

  for (const def of bindingIndex?.visibleDefinitionsAtByte(targetByte) ?? []) {
    if (!def.name.startsWith(prefix) || seen.has(def.name)) continue;
    seen.add(def.name);
    items.push({
      label: def.name,
      kind: completionKindForBinding(def.kind),
      detail: `${def.kind} in scope`,
    });
  }

  for (const literal of tableInfo.literalTerminals) {
    if (!literal.startsWith(prefix) || seen.has(literal)) continue;
    seen.add(literal);
    items.push({
      label: literal,
      kind: completionKindForLiteral(literal),
      detail: "literal terminal",
    });
  }

  return items.slice(0, 30);
}

function completionKindForBinding(kind: string): CompletionItemKind {
  switch (kind) {
    case "function":
      return CompletionItemKind.Function;
    case "method":
      return CompletionItemKind.Method;
    case "constant":
      return CompletionItemKind.Constant;
    case "struct":
    case "type":
      return CompletionItemKind.Struct;
    case "enum":
      return CompletionItemKind.Enum;
    case "trait":
      return CompletionItemKind.Interface;
    case "field":
      return CompletionItemKind.Field;
    case "enum_member":
      return CompletionItemKind.EnumMember;
    case "parameter":
    case "variable":
      return CompletionItemKind.Variable;
    case "type_parameter":
      return CompletionItemKind.TypeParameter;
    case "rule":
      return CompletionItemKind.Reference;
    case "token":
      return CompletionItemKind.Value;
    default:
      return CompletionItemKind.Text;
  }
}

function completionKindForLiteral(literal: string): CompletionItemKind {
  if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(literal)) return CompletionItemKind.Keyword;
  if (/^[+\-*/%=!<>&|^~?:.]+$/.test(literal)) return CompletionItemKind.Operator;
  return CompletionItemKind.Text;
}

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
  return [
    "grammar",
    "start_definition",
    "extras_definition",
    "conflicts_definition",
    "externals_definition",
    "word_definition",
  ].includes(node.type);
}

function extractPrefix(text: string, targetByte: number): string {
  if (targetByte <= 0) return "";
  let i = targetByte - 1;
  while (i >= 0 && isWordChar(text[i])) i--;
  return text.slice(i + 1, targetByte);
}

function isWordChar(ch: string): boolean {
  return /[a-zA-Z0-9_.@]/.test(ch);
}

function collectNamedTypesRec(cursor: TreeCursor, out: Set<string>): void {
  if (cursor.isNamed && cursor.nodeType.length > 0) out.add(cursor.nodeType);
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
