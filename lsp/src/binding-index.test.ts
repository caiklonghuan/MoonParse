import { describe, it, expect, beforeEach } from "vitest";
import { BindingIndex, bindingQueryForLang } from "./binding-index.js";
import type {
  BindingGraph,
  BindingScope,
  BindingDefinition,
  BindingReference,
  BindingEdge,
  BindingDiagnostic,
} from "../../wasm/moonparse.js";

function makeEntry(text: string) {
  const offsets: number[] = [0];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "\n") offsets.push(i + 1);
  }
  return {
    uri: "file:///test",
    text,
    version: 1,
    languageId: "c",
    parserHandle: -1,
    treeHandle: -1,
    lastDiagnostics: [],
    lineOffsets: new Uint32Array(offsets),
  };
}

// 构建一个简单的 C 语言 binding graph：
//  entry: "int x = 1;\nint add(int y) { return x + y; }"
//    byte positions:
//      x(4) add(15-18) y(23-24) x-ref(35-36) y-ref(39-40)
//      function scope {..} at byte 26-42

function makeSimpleCGraph(): BindingGraph {
  const scopes: BindingScope[] = [
    { id: 0, parent: -1, start_byte: 0, end_byte: 43, kind: "module" },
    { id: 1, parent: 0, start_byte: 26, end_byte: 42, kind: "function" },
  ];

  const definitions: BindingDefinition[] = [
    { id: 0, name: "x", kind: "variable", ns: "value", scope_id: 0, start_byte: 4, end_byte: 5 },
    { id: 1, name: "add", kind: "function", ns: "value", scope_id: 0, start_byte: 15, end_byte: 18 },
    { id: 2, name: "y", kind: "parameter", ns: "value", scope_id: 1, start_byte: 23, end_byte: 24 },
  ];

  const references: BindingReference[] = [
    { id: 3, name: "x", kind: "variable", ns: "value", scope_id: 1, start_byte: 35, end_byte: 36 },
    { id: 4, name: "y", kind: "parameter", ns: "value", scope_id: 1, start_byte: 39, end_byte: 40 },
  ];

  const edges: BindingEdge[] = [
    { reference_id: 3, definition_id: 0 },
    { reference_id: 4, definition_id: 2 },
  ];

  const diagnostics: BindingDiagnostic[] = [];

  return { uri: "file:///test.c", scopes, definitions, references, edges, diagnostics };
}

// 构建一个带未解析引用的 graph：
//   int add(int y) {
//     return x + z;   // z 未定义
//   }

function makeUnresolvedGraph(): BindingGraph {
  const scopes: BindingScope[] = [
    { id: 0, parent: -1, start_byte: 0, end_byte: 50, kind: "module" },
    { id: 1, parent: 0, start_byte: 15, end_byte: 48, kind: "function" },
  ];

  const definitions: BindingDefinition[] = [
    { id: 0, name: "add", kind: "function", ns: "value", scope_id: 0, start_byte: 4, end_byte: 7 },
    { id: 1, name: "y", kind: "parameter", ns: "value", scope_id: 1, start_byte: 12, end_byte: 13 },
  ];

  const references: BindingReference[] = [
    { id: 2, name: "x", kind: "variable", ns: "value", scope_id: 1, start_byte: 25, end_byte: 26 },
    { id: 3, name: "z", kind: "variable", ns: "value", scope_id: 1, start_byte: 29, end_byte: 30 },
  ];

  // x 找到定义（edge 指向 def 0 — 但实际上 x 是参数 y... 这里简化，只给 x 绑定但不给 z）
  // 实际场景：x 和 add 匹配？不，x 是引用，def 0 是 add（function），z 没有匹配
  const edges: BindingEdge[] = [
    { reference_id: 2, definition_id: 0 }, // x → add? 不合理但测试用
    // z 没有 edge → unresolved
  ];

  const diagnostics: BindingDiagnostic[] = [
    {
      kind: "unresolved",
      message: "unresolved reference 'z'",
      reference_id: 3,
      definition_id: -1,
      start_byte: 29,
      end_byte: 30,
    },
  ];

  return { uri: "file:///test.c", scopes, definitions, references, edges, diagnostics };
}

// 构建一个带作用域遮蔽的 graph：
//   int x = 1;
//   void f() {
//     int x = 2;   // 遮蔽外层 x
//     x;           // 引用内层 x
//   }

function makeShadowGraph(): BindingGraph {
  const scopes: BindingScope[] = [
    { id: 0, parent: -1, start_byte: 0, end_byte: 70, kind: "module" },
    { id: 1, parent: 0, start_byte: 20, end_byte: 65, kind: "function" },
  ];

  const definitions: BindingDefinition[] = [
    { id: 0, name: "x", kind: "variable", ns: "value", scope_id: 0, start_byte: 4, end_byte: 5 },
    { id: 1, name: "f", kind: "function", ns: "value", scope_id: 0, start_byte: 10, end_byte: 11 },
    { id: 2, name: "x", kind: "variable", ns: "value", scope_id: 1, start_byte: 28, end_byte: 29 }, // 内层 x
  ];

  const references: BindingReference[] = [
    { id: 3, name: "x", kind: "variable", ns: "value", scope_id: 1, start_byte: 45, end_byte: 46 },
  ];

  // 引用指向内层 def 2（遮蔽了 def 0）
  const edges: BindingEdge[] = [
    { reference_id: 3, definition_id: 2 },
  ];

  const diagnostics: BindingDiagnostic[] = [];

  return { uri: "file:///test.c", scopes, definitions, references, edges, diagnostics };
}

// ── 测试 ──

describe("BindingIndex", () => {
  let idx: BindingIndex;

  beforeEach(() => {
    idx = new BindingIndex();
  });

  describe("getSymbolAt", () => {
    it("按字节找到定义", () => {
      const entry = makeEntry("int x = 1;\nint add(int y) { return x + y; }");
      const graph = makeSimpleCGraph();
      idx.update("file:///test.c", entry, graph);

      const sym = idx.getSymbolAt(entry, 0, 4); // "x" at byte 4
      expect(sym).not.toBeNull();
      expect(sym!.kind).toBe("definition");
      expect(sym!.name).toBe("x");
    });

    it("按字节找到引用", () => {
      const entry = makeEntry("int x = 1;\nint add(int y) { return x + y; }");
      const graph = makeSimpleCGraph();
      idx.update("file:///test.c", entry, graph);

      const sym = idx.getSymbolAt(entry, 1, 24); // "x" in "return x + y" (byte 35, line starts at 11)
      expect(sym).not.toBeNull();
      expect(sym!.kind).toBe("reference");
      expect(sym!.name).toBe("x");
    });

    it("光标在标识符中间位置也能命中（区间判断）", () => {
      const entry = makeEntry("int x = 1;\nint add(int y) { return x + y; }");
      const graph = makeSimpleCGraph();
      idx.update("file:///test.c", entry, graph);

      // "add" 在字节 15-18，光标在字节 16（中间 'd'）处
      const sym = idx.getSymbolAt(entry, 1, 5); // line 1, char 5 → byte 16 ('d' in "add")
      expect(sym).not.toBeNull();
      expect(sym!.name).toBe("add");
      expect(sym!.kind).toBe("definition");
    });

    it("空索引返回 null", () => {
      const entry = makeEntry("hello");
      const sym = idx.getSymbolAt(entry, 0, 1);
      expect(sym).toBeNull();
    });
  });

  describe("findDefinition", () => {
    it("通过引用找到定义", () => {
      const entry = makeEntry("");
      const graph = makeSimpleCGraph();
      idx.update("file:///test.c", entry, graph);

      // ref id=3 (x at byte 35) → def id=0 (x at byte 4)
      const def = idx.findDefinition(3);
      expect(def).not.toBeNull();
      expect(def!.name).toBe("x");
      expect(def!.id).toBe(0);
      expect(def!.scope_id).toBe(0); // 在 module scope 定义的
    });

    it("未绑定引用返回 null", () => {
      const entry = makeEntry("");
      const graph = makeUnresolvedGraph();
      idx.update("file:///test.c", entry, graph);

      // ref id=3 (z) 没有 edge
      const def = idx.findDefinition(3);
      expect(def).toBeNull();
    });
  });

  describe("findReferences", () => {
    it("通过定义找到所有引用", () => {
      const entry = makeEntry("");
      const graph = makeSimpleCGraph();
      idx.update("file:///test.c", entry, graph);

      const refs = idx.findReferences(2); // def y (id=2)
      expect(refs).toHaveLength(1);
      expect(refs[0].name).toBe("y");
    });

    it("无引用时返回空数组", () => {
      const entry = makeEntry("");
      const graph = makeSimpleCGraph();
      idx.update("file:///test.c", entry, graph);

      const refs = idx.findReferences(1); // add — 没有引用它的 ref
      expect(refs).toEqual([]);
    });
  });

  describe("visibleDefinitions", () => {
    it("作用域链上可见所有定义", () => {
      const entry = makeEntry("");
      const graph = makeSimpleCGraph();
      idx.update("file:///test.c", entry, graph);

      const visible = idx.visibleDefinitions(1); // function scope (id=1)
      // 应该能看到 scope 1 (y) + scope 0 (x, add)
      const names = visible.map((d) => d.name).sort();
      expect(names).toContain("x");
      expect(names).toContain("add");
      expect(names).toContain("y");
    });
  });

  describe("unresolvedReferences", () => {
    it("返回未绑定的引用", () => {
      const entry = makeEntry("");
      const graph = makeUnresolvedGraph();
      idx.update("file:///test.c", entry, graph);

      const unresolved = idx.unresolvedReferences();
      expect(unresolved).toHaveLength(1);
      expect(unresolved[0].name).toBe("z");
    });

    it("全部绑定时返回空数组", () => {
      const entry = makeEntry("");
      const graph = makeSimpleCGraph();
      idx.update("file:///test.c", entry, graph);

      const unresolved = idx.unresolvedReferences();
      expect(unresolved).toEqual([]);
    });
  });

  describe("diagnostics", () => {
    it("返回 binding graph 的诊断", () => {
      const entry = makeEntry("");
      const graph = makeUnresolvedGraph();
      idx.update("file:///test.c", entry, graph);

      const diags = idx.diagnostics();
      expect(diags).toHaveLength(1);
      expect(diags[0].kind).toBe("unresolved");
      expect(diags[0].message).toContain("z");
    });

    it("无诊断时返回空数组", () => {
      const entry = makeEntry("");
      const graph = makeSimpleCGraph();
      idx.update("file:///test.c", entry, graph);

      expect(idx.diagnostics()).toEqual([]);
    });
  });

  describe("shadowing 不串", () => {
    it("内层引用指向内层定义而非外层同名定义", () => {
      const entry = makeEntry("");
      const graph = makeShadowGraph();
      idx.update("file:///test.c", entry, graph);

      // ref id=3 (x at byte 45 in function scope)
      const def = idx.findDefinition(3);
      expect(def).not.toBeNull();
      expect(def!.id).toBe(2);  // 内层 x (def id=2)
      expect(def!.scope_id).toBe(1); // function scope
      expect(def!.name).toBe("x");

      // 外层 x (def id=0) 仍然存在
      const outerDef = idx.getDefinition(0);
      expect(outerDef).not.toBeNull();
      expect(outerDef!.scope_id).toBe(0); // module scope
    });

    it("外层定义没有被内层引用关联", () => {
      const entry = makeEntry("");
      const graph = makeShadowGraph();
      idx.update("file:///test.c", entry, graph);

      // 外层 def id=0 (x in module) 没有指向它的引用
      const refs = idx.findReferences(0);
      expect(refs).toEqual([]);
    });
  });
});

describe("bindingQueryForLang", () => {
  it("Grammar DSL 有 binding query", () => {
    const q = bindingQueryForLang("__dsl__");
    expect(q).toBeTruthy();
    expect(q).toContain("@definition.rule");
  });

  it("MoonBit 有 binding query", () => {
    const q = bindingQueryForLang("moonbit");
    expect(q).toContain("@scope.block");
    expect(q).toContain("@definition.function");
  });

  it("Python 有 binding query", () => {
    expect(bindingQueryForLang("python")).toBeTruthy();
  });

  it("C 有 binding query", () => {
    expect(bindingQueryForLang("c")).toBeTruthy();
  });

  it("未知语言返回 null", () => {
    expect(bindingQueryForLang("rust")).toBeNull();
  });
});
