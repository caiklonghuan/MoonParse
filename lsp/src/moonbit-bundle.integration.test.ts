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
