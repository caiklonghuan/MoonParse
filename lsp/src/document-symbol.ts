// documentSymbol — CST 遍历提取代码大纲（函数/类/结构体/变量/规则等）

import { SymbolKind, type DocumentSymbol } from "vscode-languageserver";
import type { TreeCursor, ParseTree } from "../../wasm/moonparse.js";
import type { DocumentEntry } from "./document-manager.js";
import { byteOffsetToUtf16, type LspPosition } from "./position.js";
// ── 节点类型 → SymbolKind 映射 ──
// Grammar DSL 特有类型在前，通用类型在后

// 通用节点类型 → SymbolKind（语言无关的 fallback）
const NODE_TYPE_TO_KIND: Record<string, SymbolKind> = {
  "function_definition": SymbolKind.Function,
  "struct_specifier": SymbolKind.Struct,
  "union_specifier": SymbolKind.Struct,
  "enum_specifier": SymbolKind.Enum,
  "declaration": SymbolKind.Variable,
  "class_definition": SymbolKind.Class,
  "module": SymbolKind.Module,
  "interface": SymbolKind.Interface,
};

// 语言 id → 额外节点类型映射（可与通用映射叠加）
const PER_LANG_KINDS: Record<string, Record<string, SymbolKind>> = {
  "__dsl__": {
    "rule_definition": SymbolKind.Function,
    "token_definition": SymbolKind.Variable,
    "start_definition": SymbolKind.Module,
    "external_definition": SymbolKind.Interface,
  },
  "c": {
    "function_definition": SymbolKind.Function,
    "struct_specifier": SymbolKind.Struct,
    "union_specifier": SymbolKind.Struct,
    "enum_specifier": SymbolKind.Enum,
    "declaration": SymbolKind.Variable,
  },
};

// ── 解析 ──

// 从 ParseTree 中提取 DocumentSymbol 数组
export function extractDocumentSymbols(
  entry: DocumentEntry,
  tree: ParseTree,
): DocumentSymbol[] {
  const cursor = tree.walk();
  const symbols: DocumentSymbol[] = [];
  const langKinds = PER_LANG_KINDS[entry.languageId] ?? {};

  function walk(c: TreeCursor, parentSymbols: DocumentSymbol[]): void {
    if (!c.gotoFirstChild()) return;

    do {
      const nodeType = c.nodeType;
      const rawKind = langKinds[nodeType] ?? NODE_TYPE_TO_KIND[nodeType];

      if (rawKind !== undefined && c.isNamed) {
        const nameInfo = findName(c);
        if (nameInfo) {
          const fullRange = posRange(entry, c.startByte, c.endByte);
          const selRange = posRange(entry, nameInfo.startByte, nameInfo.endByte);

          const children: DocumentSymbol[] = [];
          const sym: DocumentSymbol = {
            name: nameInfo.text,
            kind: rawKind,
            range: { start: fullRange[0], end: fullRange[1] },
            selectionRange: { start: selRange[0], end: selRange[1] },
            children,
          };
          parentSymbols.push(sym);

          // 递归解析该符号内部的子符号
          walk(c, children);
          continue;
        }
      }
      // 非符号节点继续递归
      walk(c, parentSymbols);
    } while (c.gotoNextSibling());

    c.gotoParent();
  }

  walk(cursor, symbols);
  cursor.free();
  return symbols;
}

// ── 名称提取 ──

interface NameInfo {
  text: string;
  startByte: number;
  endByte: number;
}

// 在当前游标节点的子节点中查找名称
// 优先查找 field="name" 的子节点，其次为第一个具名 identifier 子节点
function findName(c: TreeCursor): NameInfo | null {
  if (!c.gotoFirstChild()) return null;

  let best: NameInfo | null = null;

  do {
    if (c.nodeField === "name" && c.isNamed) {
      best = {
        text: c.nodeText,
        startByte: c.startByte,
        endByte: c.endByte,
      };
      break; // 明确指定 name field，直接使用
    }
    if (!best && c.isNamed && c.nodeType === "identifier") {
      best = {
        text: c.nodeText,
        startByte: c.startByte,
        endByte: c.endByte,
      };
      // 不 break，继续找可能存在的 name field
    }
  } while (c.gotoNextSibling());

  c.gotoParent();
  return best;
}

// ── 位置转换辅助 ──

function posRange(
  entry: DocumentEntry,
  startByte: number,
  endByte: number,
): [LspPosition, LspPosition] {
  const start = byteOffsetToUtf16(entry.text, entry.lineOffsets, startByte);
  const end = byteOffsetToUtf16(entry.text, entry.lineOffsets, endByte);
  return [start, end];
}
