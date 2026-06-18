import assert from "node:assert/strict";
import test from "node:test";

import { expectedVersionFiles } from "./version.mjs";

test("VERSION is propagated to every declared version surface", async () => {
  const { version, files } = await expectedVersionFiles();
  assert.match(version, /^\d+\.\d+\.\d+/);
  assert.match(files.get("wasm/wasm.mbt"), new RegExp(`"${version.replaceAll(".", "\\.")}"`));
  assert.match(files.get("cmd/main/main.mbt"), new RegExp(`moonparse ${version.replaceAll(".", "\\.")}`));
});

