import { describe, it, expect } from "vitest";
import {
  createScope,
  createDefinition,
  createReference,
  createEdge,
  createDiagnostic,
  emptyBindingGraph,
  resetIdCounter,
} from "./binding-types.js";

describe("Scope", () => {
  it("创建根作用域", () => {
    resetIdCounter();
    const s = createScope(-1, 0, 100, "module");
    expect(s.id).toBeGreaterThan(0);
    expect(s.parent).toBe(-1);
    expect(s.startByte).toBe(0);
    expect(s.endByte).toBe(100);
    expect(s.kind).toBe("module");
  });

  it("创建嵌套作用域", () => {
    const root = createScope(-1, 0, 200, "module");
    const child = createScope(root.id, 10, 50, "block");
    expect(child.parent).toBe(root.id);
    expect(child.parent).toBeLessThan(child.id);
  });
});

describe("Definition", () => {
  it("创建函数定义", () => {
    resetIdCounter();
    const scope = createScope(-1, 0, 100, "module");
    const def = createDefinition("add", "function", "value", scope.id, 5, 8);
    expect(def.name).toBe("add");
    expect(def.kind).toBe("function");
    expect(def.ns).toBe("value");
    expect(def.scopeId).toBe(scope.id);
  });

  it("不同类型有不同的 kind", () => {
    const scope = createScope(-1, 0, 100, "module");
    const v = createDefinition("x", "variable", "value", scope.id, 0, 1);
    const f = createDefinition("f", "function", "value", scope.id, 10, 11);
    const t = createDefinition("T", "type", "type", scope.id, 20, 21);
    expect(v.kind).toBe("variable");
    expect(f.kind).toBe("function");
    expect(t.kind).toBe("type");
    // type 在 type namespace，value 在 value namespace，允许重名
    expect(t.ns).not.toBe(v.ns);
  });
});

describe("Reference", () => {
  it("创建引用", () => {
    resetIdCounter();
    const scope = createScope(-1, 0, 100, "module");
    const ref = createReference("add", "function", "value", scope.id, 30, 33);
    expect(ref.name).toBe("add");
    expect(ref.kind).toBe("function");
  });
});

describe("BindingEdge", () => {
  it("连接引用到定义", () => {
    resetIdCounter();
    const scope = createScope(-1, 0, 100, "module");
    const def = createDefinition("f", "function", "value", scope.id, 0, 1);
    const ref = createReference("f", "function", "value", scope.id, 20, 21);
    const edge = createEdge(ref.id, def.id);
    expect(edge.referenceId).toBe(ref.id);
    expect(edge.definitionId).toBe(def.id);
  });
});

describe("BindingDiagnostic", () => {
  it("unresolved 引用", () => {
    resetIdCounter();
    const scope = createScope(-1, 0, 100, "module");
    const ref = createReference("unknown", "variable", "value", scope.id, 5, 12);
    const d = createDiagnostic("unresolved", "unresolved reference 'unknown'", 5, 12, ref.id);
    expect(d.kind).toBe("unresolved");
    expect(d.referenceId).toBe(ref.id);
    expect(d.definitionId).toBe(-1);
  });

  it("duplicate 定义", () => {
    const d = createDiagnostic("duplicate", "duplicate definition 'x'", 10, 11, -1, 5);
    expect(d.kind).toBe("duplicate");
    expect(d.referenceId).toBe(-1);
    expect(d.definitionId).toBe(5);
  });

  it("ambiguous 引用", () => {
    const d = createDiagnostic("ambiguous", "ambiguous reference 'f'", 20, 21, 3);
    expect(d.kind).toBe("ambiguous");
    expect(d.referenceId).toBe(3);
  });
});

describe("BindingGraph", () => {
  it("空图", () => {
    const g = emptyBindingGraph("file:///test.grammar");
    expect(g.uri).toBe("file:///test.grammar");
    expect(g.scopes).toEqual([]);
    expect(g.definitions).toEqual([]);
    expect(g.references).toEqual([]);
    expect(g.edges).toEqual([]);
    expect(g.diagnostics).toEqual([]);
  });

  it("完整绑定图 — 嵌套作用域 + 定义 + 引用 + 边", () => {
    resetIdCounter();
    const g = emptyBindingGraph("file:///main.c");

    // module scope
    const mod = createScope(-1, 0, 200, "module");
    g.scopes.push(mod);

    // function scope
    const fn = createScope(mod.id, 20, 180, "function");
    g.scopes.push(fn);

    // 定义：全局变量 x
    const defX = createDefinition("x", "variable", "value", mod.id, 4, 5);
    g.definitions.push(defX);

    // 定义：函数 add
    const defAdd = createDefinition("add", "function", "value", mod.id, 10, 13);
    g.definitions.push(defAdd);

    // 定义：参数 y（在 fn 作用域内）
    const defY = createDefinition("y", "parameter", "value", fn.id, 30, 31);
    g.definitions.push(defY);

    // 引用：在 fn 体内引用 x
    const refX = createReference("x", "variable", "value", fn.id, 50, 51);
    g.references.push(refX);

    // 引用：在 fn 体内引用 y
    const refY = createReference("y", "parameter", "value", fn.id, 70, 71);
    g.references.push(refY);

    // 边
    g.edges.push(createEdge(refX.id, defX.id));
    g.edges.push(createEdge(refY.id, defY.id));

    // 诊断：未找到的引用
    const refBad = createReference("z", "variable", "value", fn.id, 90, 91);
    g.references.push(refBad);
    g.diagnostics.push(
      createDiagnostic("unresolved", "unresolved reference 'z'", 90, 91, refBad.id),
    );

    expect(g.scopes.length).toBe(2);
    expect(g.definitions.length).toBe(3);
    expect(g.references.length).toBe(3);
    expect(g.edges.length).toBe(2);
    expect(g.diagnostics.length).toBe(1);
    expect(g.diagnostics[0].kind).toBe("unresolved");

    // fn 作用域嵌套在 mod 下
    expect(g.scopes[1].parent).toBe(g.scopes[0].id);
  });
});
