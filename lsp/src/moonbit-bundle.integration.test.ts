import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { fileURLToPath } from "node:url";

import {
  DiagnosticSeverity,
  DocumentHighlightKind,
  type CompletionItem,
} from "vscode-languageserver";

import { BindingIndex } from "./binding-index.js";
import { getCompletions } from "./completion.js";
import { bindingDiagnosticsToDiagnostics } from "./diagnostics.js";
import type { DocumentEntry } from "./document-manager.js";
import { getDocumentHighlights } from "./document-highlight.js";
import { extractDocumentSymbols } from "./document-symbol.js";
import { foldingRangesFromCaptures } from "./folding.js";
import { getDefinitionLocation, getReferenceLocations } from "./navigation.js";
import { parseTableInfo } from "./parse-table-info.js";
import { prepareRename, renameSymbol } from "./rename.js";
import {
  loadMoonParse,
  type CstNode,
  type MoonLanguage,
  type ParseTree,
} from "../../wasm/moonparse.js";

function makeEntry(text: string): DocumentEntry {
  const offsets = [0];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "\n") offsets.push(i + 1);
  }
  return {
    uri: "file:///sample.mbt",
    text,
    version: 1,
    languageId: "moonbit",
    parserHandle: -1,
    treeHandle: -1,
    lastDiagnostics: [],
    lineOffsets: new Uint32Array(offsets),
  };
}

function buildIndex(language: MoonLanguage, entry: DocumentEntry, tree: ParseTree): BindingIndex {
  const index = new BindingIndex();
  index.update(entry.uri, entry, language.resolveBindings(tree));
  return index;
}

function rebuildIndex(language: MoonLanguage, text: string): BindingIndex {
  const entry = makeEntry(text);
  const tree = language.parse(text);
  try {
    return buildIndex(language, entry, tree);
  } finally {
    tree.free();
  }
}

function labels(items: CompletionItem[] | null): string[] {
  return (items ?? []).map((item) => item.label);
}

function findNode(node: CstNode, type: string): CstNode | null {
  if (node.type === type) return node;
  for (const child of node.children ?? []) {
    const found = findNode(child, type);
    if (found) return found;
  }
  return null;
}

describe("MoonBit bundle LSP integration", () => {
  let language: MoonLanguage | undefined;

  beforeAll(async () => {
    const wasmPath = fileURLToPath(new URL("../../wasm/moonparse.wasm", import.meta.url));
    const api = await loadMoonParse(wasmPath);
    const bundles = JSON.parse(api.builtinBundlesJson()) as Record<string, string>;
    language = api.loadBundle(bundles.moonbit);
  }, 30_000);

  afterAll(() => {
    language?.free();
  });

  it("drives LSP helpers from a real MoonBit Bundle", () => {
    const source = "fn main() {\n  let value = 1\n  value\n}\n";
    const moonbit = language!;
    const entry = makeEntry(source);
    const tree = moonbit.parse(source);
    try {
      const index = buildIndex(moonbit, entry, tree);
      const tableInfo = parseTableInfo(moonbit.parser.tableJson());

      expect(moonbit.highlight(tree).map((item) => item.highlight)).toEqual(
        expect.arrayContaining(["keyword.function", "function", "keyword", "variable"]),
      );
      expect(bindingDiagnosticsToDiagnostics(entry, index.diagnostics(), 100)).toEqual([]);

      expect(getDefinitionLocation(entry, index, 2, 2)?.range.start).toEqual({
        line: 1,
        character: 6,
      });
      expect(getReferenceLocations(entry, index, 2, 2, false).map((item) => item.range.start))
        .toEqual([{ line: 2, character: 2 }]);
      expect(getReferenceLocations(entry, index, 2, 2, true).map((item) => item.range.start))
        .toEqual([{ line: 1, character: 6 }, { line: 2, character: 2 }]);

      const highlights = getDocumentHighlights(entry, index, 1, 6);
      expect(highlights.map((item) => item.kind)).toEqual([
        DocumentHighlightKind.Write,
        DocumentHighlightKind.Read,
      ]);

      const symbols = extractDocumentSymbols(entry, tree, index);
      expect(symbols[0]?.name).toBe("main");
      expect(symbols[0]?.children?.some((symbol) => symbol.name === "value")).toBe(true);

      expect(foldingRangesFromCaptures(entry, moonbit.fold(tree)).length).toBeGreaterThan(0);
      const lint = moonbit.lint(tree);
      expect(lint).toEqual([]);
      expect(labels(getCompletions(entry, tree, index, tableInfo, 2, 3))).toContain("value");

      expect(prepareRename(entry, index, tableInfo, 2, 2)?.placeholder).toBe("value");
      const edit = renameSymbol(
        entry,
        index,
        tableInfo,
        2,
        2,
        "result",
        (text) => rebuildIndex(moonbit, text),
      );
      expect(edit?.changes?.[entry.uri]?.map((item) => item.newText)).toEqual([
        "result",
        "result",
      ]);
    } finally {
      tree.free();
    }
  });

  it("runs configured MoonBit lint rules and severity overrides", () => {
    const moonbit = language!;
    const tree = moonbit.parse("let value = -0\n// TODO: demo\n");
    try {
      const diagnostics = moonbit.lint(tree);
      expect(diagnostics.map((item) => item.ruleId)).toEqual([
        "moonbit/recommended/negative-zero",
        "moonbit/recommended/todo-comment",
      ]);
      expect(diagnostics[0].fix?.edit.replacement).toBe("0");
      expect(moonbit.lint(tree, {
        rules: {
          "moonbit/recommended/negative-zero": "off",
          "moonbit/recommended/todo-comment": "error",
        },
      }).map((item) => item.severity)).toEqual(["error"]);
    } finally {
      tree.free();
    }
  });

  it("exposes public exports and qualified references through the modules query", () => {
    const moonbit = language!;
    const tree = moonbit.parse(
      "pub fn run() { @json.parse(value) }\n" +
      "priv fn hidden() {}\n" +
      "type Box = @types.User\n",
    );
    try {
      expect(tree.errorSummary()).toBe("ok");
      expect(findNode(tree.root, "visibility")).toMatchObject({
        start_byte: 0,
        end_byte: 3,
      });
      expect(findNode(tree.root, "fn_name")).toMatchObject({
        start_byte: 7,
        end_byte: 10,
      });
      const modules = moonbit.modules(tree);
      expect(modules.map((capture) => ({
        capture: capture.capture,
        text: capture.text,
      }))).toEqual([
        { capture: "module.export", text: "run" },
        { capture: "module.reference", text: "@json" },
        { capture: "module.member.value", text: "parse" },
        { capture: "module.reference", text: "@types" },
        { capture: "module.member.type", text: "User" },
      ]);
      expect(modules[1].match_id).toBe(modules[2].match_id);
      expect(modules[3].match_id).toBe(modules[4].match_id);
    } finally {
      tree.free();
    }
  });

  it("parses every supported function visibility prefix without recovery", () => {
    const moonbit = language!;
    const cases = [
      { source: "fn run() {}\n", visibilityEnd: null, exported: false },
      { source: "pub fn run() {}\n", visibilityEnd: 3, exported: true },
      { source: "priv fn run() {}\n", visibilityEnd: 4, exported: false },
      { source: "pub(all) fn run() {}\n", visibilityEnd: 8, exported: true },
      { source: "pub(readonly) fn run() {}\n", visibilityEnd: 13, exported: true },
      { source: "pub(open) fn run() {}\n", visibilityEnd: 9, exported: true },
    ];

    for (const item of cases) {
      const tree = moonbit.parse(item.source);
      try {
        expect(tree.errorSummary(), item.source).toBe("ok");
        const visibility = findNode(tree.root, "visibility");
        if (item.visibilityEnd == null) {
          expect(visibility, item.source).toBeNull();
        } else {
          expect(visibility, item.source).toMatchObject({
            start_byte: 0,
            end_byte: item.visibilityEnd,
          });
        }
        const nameStart = item.source.indexOf("run");
        expect(findNode(tree.root, "fn_name"), item.source).toMatchObject({
          start_byte: nameStart,
          end_byte: nameStart + 3,
        });
        expect(moonbit.modules(tree).some((capture) =>
          capture.capture === "module.export" && capture.text === "run"), item.source)
          .toBe(item.exported);
      } finally {
        tree.free();
      }
    }
  });

  it("maps real binding diagnostics to stable LSP codes", () => {
    const unresolved = makeEntry("fn main() {\n  missing\n}\n");
    const moonbit = language!;
    const unresolvedTree = moonbit.parse(unresolved.text);
    try {
      const unresolvedIndex = buildIndex(moonbit, unresolved, unresolvedTree);
      const diagnostics = bindingDiagnosticsToDiagnostics(
        unresolved,
        unresolvedIndex.diagnostics(),
        100,
      );
      expect(diagnostics).toHaveLength(1);
      expect(diagnostics[0].code).toBe("MP_BIND_UNRESOLVED");
      expect(diagnostics[0].severity).toBe(DiagnosticSeverity.Warning);
    } finally {
      unresolvedTree.free();
    }

    const duplicate = makeEntry(
      "fn main() {\n  let value = 1\n  let value = 2\n  value\n}\n",
    );
    const duplicateTree = moonbit.parse(duplicate.text);
    try {
      const duplicateIndex = buildIndex(moonbit, duplicate, duplicateTree);
      const diagnostics = bindingDiagnosticsToDiagnostics(
        duplicate,
        duplicateIndex.diagnostics(),
        100,
      );
      expect(diagnostics.map((item) => item.code).sort()).toEqual([
        "MP_BIND_AMBIGUOUS",
        "MP_BIND_DUPLICATE",
      ]);
      expect(diagnostics.every((item) => item.severity === DiagnosticSeverity.Error)).toBe(true);
    } finally {
      duplicateTree.free();
    }
  });
});
