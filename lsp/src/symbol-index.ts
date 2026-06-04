// Grammar DSL symbol index — rule/token 定义与引用索引

import type { TreeCursor, ParseTree } from "../../wasm/moonparse.js";
import type { DocumentEntry } from "./document-manager.js";
import { byteOffsetToUtf16, utf16ToByteOffset, type LspPosition } from "./position.js";

// ── 数据结构 ──

export interface SymbolLocation {
  uri: string;
  name: string;
  range: { start: LspPosition; end: LspPosition };
  kind: "definition" | "reference";
}

// 单文件符号索引
export class SymbolIndex {
  // name → definition location
  private definitions = new Map<string, SymbolLocation>();
  // name → reference locations
  private references = new Map<string, SymbolLocation[]>();

  // rule name 列表（用于判断 identifier 是否为引用）
  private ruleNames = new Set<string>();

  // 已索引的 URI
  private indexedUri: string | null = null;

  // ── 构建索引 ──

  // 从 CST 中提取所有 rule/token 定义和引用
  build(uri: string, entry: DocumentEntry, tree: ParseTree): void {
    // 清空旧索引
    this.clear();

    // 第一遍：收集所有 rule 定义
    this.collectDefinitions(uri, entry, tree);

    // 第二遍：收集所有 rule 引用
    this.collectReferences(uri, entry, tree);

    this.indexedUri = uri;
  }

  // ── 查询 ──

  findDefinition(name: string): SymbolLocation | null {
    return this.definitions.get(name) ?? null;
  }

  findReferences(name: string): SymbolLocation[] {
    const refs = this.references.get(name) ?? [];
    const def = this.definitions.get(name);
    // references 请求通常包含 declaration
    if (def) {
      return [{ ...def, kind: "reference" }, ...refs];
    }
    return refs;
  }

  // 获取指定位置的符号名（如果是定义或引用）
  getNameAt(
    entry: DocumentEntry,
    line: number,
    character: number,
  ): { name: string; isDef: boolean } | null {
    const targetByte = utf16ToByteOffset(
      entry.text,
      entry.lineOffsets,
      line,
      character,
    );

    // 检查是否命中某个定义
    for (const [name, loc] of this.definitions) {
      const startByte = utf16ToByteOffset(
        entry.text,
        entry.lineOffsets,
        loc.range.start.line,
        loc.range.start.character,
      );
      const endByte = utf16ToByteOffset(
        entry.text,
        entry.lineOffsets,
        loc.range.end.line,
        loc.range.end.character,
      );
      if (targetByte >= startByte && targetByte <= endByte) {
        return { name, isDef: true };
      }
    }

    // 检查是否命中某个引用
    for (const [name, refs] of this.references) {
      for (const ref of refs) {
        const startByte = utf16ToByteOffset(
          entry.text,
          entry.lineOffsets,
          ref.range.start.line,
          ref.range.start.character,
        );
        const endByte = utf16ToByteOffset(
          entry.text,
          entry.lineOffsets,
          ref.range.end.line,
          ref.range.end.character,
        );
        if (targetByte >= startByte && targetByte <= endByte) {
          return { name, isDef: false };
        }
      }
    }

    return null;
  }

  // 获取所有 rule 名称（completion 用）
  ruleNameSet(): Set<string> {
    return this.ruleNames;
  }

  clear(): void {
    this.definitions.clear();
    this.references.clear();
    this.ruleNames.clear();
    this.indexedUri = null;
  }

  // ── 内部 ──

  // 第一遍：找所有 rule_definition → 收集定义名
  private collectDefinitions(
    uri: string,
    entry: DocumentEntry,
    tree: ParseTree,
  ): void {
    const cursor = tree.walk();
    if (!cursor.gotoFirstChild()) {
      cursor.free();
      return;
    }

    const walk = (c: TreeCursor): void => {
      if (c.nodeType === "rule_definition") {
        const nameNode = this.findNameChild(c);
        if (nameNode) {
          const name = nameNode.text;
          const range = this.toLspRange(entry, nameNode.startByte, nameNode.endByte);

          this.definitions.set(name, {
            uri,
            name,
            range,
            kind: "definition",
          });
          this.ruleNames.add(name);
        }
      }

      if (c.gotoFirstChild()) {
        do { walk(c); } while (c.gotoNextSibling());
        c.gotoParent();
      }
    };

    do { walk(cursor); } while (cursor.gotoNextSibling());
    cursor.gotoParent();
    cursor.free();
  }

  // 第二遍：找所有 identifier → 如果文本命中 ruleNames 则记录为引用
  private collectReferences(
    uri: string,
    entry: DocumentEntry,
    tree: ParseTree,
  ): void {
    const cursor = tree.walk();
    if (!cursor.gotoFirstChild()) {
      cursor.free();
      return;
    }

    const walk = (c: TreeCursor): void => {
      if (
        c.nodeType === "identifier" &&
        c.isNamed &&
        this.ruleNames.has(c.nodeText)
      ) {
        const name = c.nodeText;
        // 排除 rule 定义自身的 name identifier（那已经是 definition）
        const isNameField = c.nodeField === "name";
        if (!isNameField) {
          const loc: SymbolLocation = {
            uri,
            name,
            range: this.toLspRange(entry, c.startByte, c.endByte),
            kind: "reference",
          };

          const list = this.references.get(name);
          if (list) {
            list.push(loc);
          } else {
            this.references.set(name, [loc]);
          }
        }
      }

      if (c.gotoFirstChild()) {
        do { walk(c); } while (c.gotoNextSibling());
        c.gotoParent();
      }
    };

    do { walk(cursor); } while (cursor.gotoNextSibling());
    cursor.gotoParent();
    cursor.free();
  }

  // 在当前 cursor 节点的子节点中找 field="name" 的子节点
  private findNameChild(c: TreeCursor): { text: string; startByte: number; endByte: number } | null {
    if (!c.gotoFirstChild()) return null;

    let found: { text: string; startByte: number; endByte: number } | null = null;

    do {
      if (c.nodeField === "name" && c.isNamed) {
        found = {
          text: c.nodeText,
          startByte: c.startByte,
          endByte: c.endByte,
        };
        break;
      }
      if (!found && c.isNamed && c.nodeType === "identifier") {
        found = {
          text: c.nodeText,
          startByte: c.startByte,
          endByte: c.endByte,
        };
      }
    } while (c.gotoNextSibling());

    c.gotoParent();
    return found;
  }

  private toLspRange(
    entry: DocumentEntry,
    startByte: number,
    endByte: number,
  ): { start: LspPosition; end: LspPosition } {
    return {
      start: byteOffsetToUtf16(entry.text, entry.lineOffsets, startByte),
      end: byteOffsetToUtf16(entry.text, entry.lineOffsets, endByte),
    };
  }
}
