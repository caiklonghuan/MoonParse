import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { createServerCapabilities } from "./capabilities.js";

describe("server capabilities compatibility", () => {
  it("matches the tracked API snapshot", () => {
    const path = fileURLToPath(
      new URL("../../api/snapshots/lsp-capabilities.json", import.meta.url),
    );
    const expected = JSON.parse(readFileSync(path, "utf8"));
    expect(createServerCapabilities()).toEqual(expected);
  });
});

