// binding-index — 消费 BindingGraph，提供按字节/ID 的名称查找 API
//
// 逐步替换 symbol-index.ts（仅 Grammar DSL，按 name 字符串匹配）。
// 新索引基于 BindingGraph 的 scope/d edge 结构，同名不同作用域的变量不会混淆。

import type {
  BindingGraph,
  BindingDefinition,
  BindingReference,
  BindingEdge,
  BindingDiagnostic,
  BindingScope,
} from "../../wasm/moonparse.js";

import type { DocumentEntry } from "./document-manager.js";
import { utf16ToByteOffset } from "./position.js";

// ── 查找结果 ──

export type SymbolKind = "definition" | "reference";

export interface SymbolHit {
  kind: SymbolKind;
  id: number;            // Definition.id 或 Reference.id
  name: string;
  scopeId: number;
  startByte: number;
  endByte: number;
}

// ── BindingIndex ──

export class BindingIndex {
  private uri = "";
  private graph: BindingGraph | null = null;

  // 字节 → 定义/引用 的快速查找
  private defByByte = new Map<number, BindingDefinition>();
  private refByByte = new Map<number, BindingReference>();

  // id → 条目
  private defs = new Map<number, BindingDefinition>();
  private refs = new Map<number, BindingReference>();

  // definitionId → referenceId[]（通过 edge）
  private defToRefs = new Map<number, number[]>();
  // referenceId → definitionId（通过 edge）
  private refToDef = new Map<number, number>();

  // scope → definitions
  private scopeDefs = new Map<number, BindingDefinition[]>();

  // ── 构建 ──

  update(uri: string, _entry: DocumentEntry, graph: BindingGraph): void {
    this.clear();
    this.uri = uri;
    this.graph = graph;

    // 索引定义
    for (const d of graph.definitions) {
      const key = d.start_byte;
      if (!this.defByByte.has(key)) {
        this.defByByte.set(key, d);
      }
      this.defs.set(d.id, d);

      // scope → defs
      const list = this.scopeDefs.get(d.scope_id);
      if (list) {
        list.push(d);
      } else {
        this.scopeDefs.set(d.scope_id, [d]);
      }
    }

    // 索引引用
    for (const r of graph.references) {
      const key = r.start_byte;
      if (!this.refByByte.has(key)) {
        this.refByByte.set(key, r);
      }
      this.refs.set(r.id, r);
    }

    // 索引边
    for (const e of graph.edges) {
      this.refToDef.set(e.reference_id, e.definition_id);

      const list = this.defToRefs.get(e.definition_id);
      if (list) {
        list.push(e.reference_id);
      } else {
        this.defToRefs.set(e.definition_id, [e.reference_id]);
      }
    }

    void _entry;
  }

  // ── 查询 API ──

  // 在指定 LSP 位置查找符号（定义或引用）
  // 使用区间判断 [start_byte, end_byte)，支持光标在标识符任意位置
  getSymbolAt(entry: DocumentEntry, line: number, character: number): SymbolHit | null {
    const byte = utf16ToByteOffset(entry.text, entry.lineOffsets, line, character);

    // 先查精确 start_byte 命中（快速路径）
    const exactDef = this.defByByte.get(byte);
    if (exactDef) {
      return {
        kind: "definition",
        id: exactDef.id,
        name: exactDef.name,
        scopeId: exactDef.scope_id,
        startByte: exactDef.start_byte,
        endByte: exactDef.end_byte,
      };
    }

    const exactRef = this.refByByte.get(byte);
    if (exactRef) {
      return {
        kind: "reference",
        id: exactRef.id,
        name: exactRef.name,
        scopeId: exactRef.scope_id,
        startByte: exactRef.start_byte,
        endByte: exactRef.end_byte,
      };
    }

    // 区间扫描：光标在标识符中间位置
    for (const d of this.defs.values()) {
      if (d.start_byte <= byte && byte < d.end_byte) {
        return {
          kind: "definition",
          id: d.id,
          name: d.name,
          scopeId: d.scope_id,
          startByte: d.start_byte,
          endByte: d.end_byte,
        };
      }
    }

    for (const r of this.refs.values()) {
      if (r.start_byte <= byte && byte < r.end_byte) {
        return {
          kind: "reference",
          id: r.id,
          name: r.name,
          scopeId: r.scope_id,
          startByte: r.start_byte,
          endByte: r.end_byte,
        };
      }
    }

    return null;
  }

  // 根据引用 ID 找到对应定义
  findDefinition(refId: number): BindingDefinition | null {
    const defId = this.refToDef.get(refId);
    if (defId === undefined) return null;
    return this.defs.get(defId) ?? null;
  }

  // 根据定义 ID 找到所有引用
  findReferences(defId: number): BindingReference[] {
    const refIds = this.defToRefs.get(defId);
    if (!refIds) return [];
    const result: BindingReference[] = [];
    for (const rid of refIds) {
      const r = this.refs.get(rid);
      if (r) result.push(r);
    }
    return result;
  }

  // 在指定作用域（含父作用域）中可见的所有定义
  visibleDefinitions(scopeId: number): BindingDefinition[] {
    if (!this.graph) return [];

    const result: BindingDefinition[] = [];
    let current = scopeId;
    while (current >= 0) {
      const defs = this.scopeDefs.get(current);
      if (defs) result.push(...defs);

      // 找父作用域
      const scope = this.graph.scopes.find((s) => s.id === current);
      current = scope ? scope.parent : -1;
    }
    return result;
  }

  // 返回所有绑定诊断
  diagnostics(): BindingDiagnostic[] {
    return this.graph?.diagnostics ?? [];
  }

  // 获取定义详情
  getDefinition(defId: number): BindingDefinition | null {
    return this.defs.get(defId) ?? null;
  }

  // 获取引用详情
  getReference(refId: number): BindingReference | null {
    return this.refs.get(refId) ?? null;
  }

  // 获取作用域详情
  getScope(scopeId: number): BindingScope | null {
    return this.graph?.scopes.find((s) => s.id === scopeId) ?? null;
  }

  // ── 未解析引用 ──

  // 所有没有对应 definition 的 reference（排除与 def 重叠的自引用节点）
  unresolvedReferences(): BindingReference[] {
    const result: BindingReference[] = [];
    for (const r of this.refs.values()) {
      if (!this.refToDef.has(r.id)) {
        // 排除与 definition 同名的 self-reference（def 节点被 ref query 误捕获）
        let isSelfRef = false;
        for (const d of this.defs.values()) {
          if (d.start_byte === r.start_byte &&
            d.end_byte === r.end_byte &&
            d.name === r.name) {
            isSelfRef = true;
            break;
          }
        }
        if (!isSelfRef) {
          result.push(r);
        }
      }
    }
    return result;
  }

  // ── 工具 ──

  isEmpty(): boolean {
    return this.graph === null || this.defs.size === 0;
  }

  clear(): void {
    this.graph = null;
    this.defByByte.clear();
    this.refByByte.clear();
    this.defs.clear();
    this.refs.clear();
    this.defToRefs.clear();
    this.refToDef.clear();
    this.scopeDefs.clear();
    this.uri = "";
  }
}

// ── 内置 binding query 映射（与 grammars/bindings.mbt 中的常量一致） ──

const GRAMMAR_DSL_BINDINGS = `
; rule 名 → definition（归入隐式 root Module scope）
(rule_definition name: (identifier) @definition.rule)
; rule body 中的标识符 → reference
(rule_definition (identifier) @reference.rule)
`;

const MOONBIT_BINDINGS = `
(block) @scope.block
(function_decl) @scope.function
(function_decl (fn_name (identifier) @definition.function))
(let_statement (identifier) @definition.variable)
(parameter (identifier) @definition.parameter)
(struct_decl (identifier) @definition.type)
(enum_decl (identifier) @definition.type)
(type_alias_decl (identifier) @definition.type)
(enum_case (identifier) @definition.variable)
(identifier) @reference.variable
`;

const PYTHON_BINDINGS = `
(function_definition) @scope.function
(class_definition) @scope.class
(function_definition name: (identifier) @definition.function)
(class_definition name: (identifier) @definition.type)
(parameters (identifier) @definition.parameter)
(identifier) @reference.variable
`;

const C_BINDINGS = `
(compound_statement) @scope.block
(function_definition) @scope.function
(function_definition (declarator (identifier) @definition.function))
(declaration (init_declarator_list (identifier) @definition.variable))
(parameter_declaration (identifier) @definition.parameter)
(struct_specifier (identifier) @definition.type)
(enum_specifier (identifier) @definition.type)
(identifier) @reference.variable
`;

const BINDING_QUERIES: Record<string, string> = {
  "__dsl__": GRAMMAR_DSL_BINDINGS,
  "moonbit": MOONBIT_BINDINGS,
  "python": PYTHON_BINDINGS,
  "c": C_BINDINGS,
};

// 按 languageId 获取 binding query 字符串
export function bindingQueryForLang(langId: string): string | null {
  return BINDING_QUERIES[langId] ?? null;
}
