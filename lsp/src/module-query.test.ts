import { describe, expect, it } from "vitest";

import { normalizeModuleCaptures } from "./module-query.js";
import type { BindingGraph, CaptureResult } from "../../wasm/moonparse.js";

function capture(
  match_id: number,
  name: string,
  start: number,
  end: number,
  text: string,
): CaptureResult {
  return {
    match_id,
    capture: name,
    start,
    end,
    start_row: 0,
    start_col: start,
    end_row: 0,
    end_col: end,
    text,
  };
}

describe("modules query normalization", () => {
  it("groups imports and qualified references by match id", () => {
    const graph: BindingGraph = {
      uri: "file:///main.mbt",
      scopes: [],
      definitions: [],
      references: [{
        id: 4,
        name: "parse",
        kind: "variable",
        ns: "value",
        scope_id: 0,
        start_byte: 20,
        end_byte: 25,
        diagnose_unresolved: true,
      }],
      edges: [],
      diagnostics: [],
    };
    const result = normalizeModuleCaptures([
      capture(1, "import.source", 0, 12, '"core/json"'),
      capture(1, "import.alias", 13, 18, "@json"),
      capture(2, "module.reference", 14, 19, "@json"),
      capture(2, "module.member.value", 20, 25, "parse"),
      capture(3, "module.export", 30, 33, "run"),
    ], 40, graph);

    expect(result.imports).toEqual([{
      source: "core/json",
      alias: "json",
      condition: "normal",
      sourceStartByte: 0,
      sourceEndByte: 12,
    }]);
    expect(result.qualifiedReferences[0]).toMatchObject({
      alias: "json",
      name: "parse",
      namespace: "value",
      referenceId: 4,
    });
    expect(result.publicExportRanges).toEqual([{ startByte: 30, endByte: 33 }]);
  });

  it("ignores malformed groups, invalid ranges, and duplicate captures", () => {
    const result = normalizeModuleCaptures([
      capture(1, "import.source", 0, 1, "a"),
      capture(1, "import.source", 2, 3, "b"),
      capture(2, "module.reference", 4, 5, "@m"),
      capture(2, "module.member", 6, 7, "x"),
      capture(2, "module.member.type", 6, 7, "x"),
      capture(3, "module.export", -1, 2, "bad"),
    ], 8);
    expect(result.imports).toEqual([]);
    expect(result.qualifiedReferences).toEqual([]);
    expect(result.publicExportRanges).toEqual([]);
  });

  it("uses the final path segment as a default alias", () => {
    const result = normalizeModuleCaptures([
      capture(1, "import.source", 0, 11, "core/json"),
    ], 20);
    expect(result.imports[0].alias).toBe("json");
  });
});
