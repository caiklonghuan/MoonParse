// P1: Binding 数据模型 — scope / definition / reference / edge / diagnostic / graph

// ── Scope ──

// 作用域种类
export type ScopeKind =
  | "module"      // 文件顶层
  | "function"    // 函数体
  | "block"       // 花括号块 { ... }
  | "class"       // 类体
  | "loop"        // for / while 循环体（C99 for-init）
  | "rule";       // Grammar DSL rule 体

// 一个作用域区域
export interface Scope {
  id: number;
  parent: number;           // 父作用域 id，-1 表示根（module）
  startByte: number;
  endByte: number;
  kind: ScopeKind;
}

// ── Definition ──

// 定义/引用的符号种类
export type SymbolKind =
  | "variable"
  | "function"
  | "type"
  | "parameter"
  | "rule"        // Grammar DSL rule
  | "token";      // Grammar DSL token

// 命名空间（同一作用域内同 namespace 不允许重名，不同 namespace 可以）
export type Namespace =
  | "value"       // 变量/函数
  | "type"        // 类型/类/接口
  | "rule";       // Grammar DSL rule name

// 一个符号定义（声明处）
export interface Definition {
  id: number;
  name: string;
  kind: SymbolKind;
  ns: Namespace;   // MoonBit 侧 'namespace' 是保留字，统一用 ns
  scopeId: number;          // 定义所在的作用域
  startByte: number;
  endByte: number;
}

// ── Reference ──

// 一个符号引用（使用处）
export interface Reference {
  id: number;
  name: string;
  kind: SymbolKind;
  ns: Namespace;   // MoonBit 侧 'namespace' 是保留字，统一用 ns
  scopeId: number;          // 引用所在的作用域
  startByte: number;
  endByte: number;
}

// ── BindingEdge ──

// 引用 → 定义的绑定边
export interface BindingEdge {
  referenceId: number;
  definitionId: number;
}

// ── BindingDiagnostic ──

// 绑定问题种类
export type BindingDiagKind =
  | "unresolved"   // 引用找不到对应定义
  | "duplicate"    // 同一作用域内重复定义
  | "ambiguous";   // 引用可解析到多个定义（GLR 歧义残留）

// 绑定诊断
export interface BindingDiagnostic {
  kind: BindingDiagKind;
  message: string;
  referenceId: number;        // -1 表示不关联引用（如 duplicate 关联 definitionId）
  definitionId: number;       // -1 同理
  startByte: number;
  endByte: number;
}

// ── BindingGraph ──

// 单文件的完整绑定图
export interface BindingGraph {
  uri: string;
  scopes: Scope[];
  definitions: Definition[];
  references: Reference[];
  edges: BindingEdge[];
  diagnostics: BindingDiagnostic[];
}

// ── 工厂函数 ──

let nextId = 1;

export function resetIdCounter(): void {
  nextId = 1;
}

function genId(): number {
  return nextId++;
}

export function createScope(
  parent: number,
  startByte: number,
  endByte: number,
  kind: ScopeKind,
): Scope {
  return { id: genId(), parent, startByte, endByte, kind };
}

export function createDefinition(
  name: string,
  kind: SymbolKind,
  ns: Namespace,
  scopeId: number,
  startByte: number,
  endByte: number,
): Definition {
  return { id: genId(), name, kind, ns, scopeId, startByte, endByte };
}

export function createReference(
  name: string,
  kind: SymbolKind,
  ns: Namespace,
  scopeId: number,
  startByte: number,
  endByte: number,
): Reference {
  return { id: genId(), name, kind, ns, scopeId, startByte, endByte };
}

export function createEdge(referenceId: number, definitionId: number): BindingEdge {
  return { referenceId, definitionId };
}

export function createDiagnostic(
  kind: BindingDiagKind,
  message: string,
  startByte: number,
  endByte: number,
  referenceId: number = -1,
  definitionId: number = -1,
): BindingDiagnostic {
  return { kind, message, referenceId, definitionId, startByte, endByte };
}

// ── 空 BindingGraph ──

export function emptyBindingGraph(uri: string = ""): BindingGraph {
  return {
    uri,
    scopes: [],
    definitions: [],
    references: [],
    edges: [],
    diagnostics: [],
  };
}
