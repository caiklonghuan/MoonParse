import assert from "node:assert/strict";
import test from "node:test";

import { verifyDeclarationScope } from "./declaration-scope.mjs";

test("contract declaration exception is exact and usable only before release", () => {
  const receipt = verifyDeclarationScope({ profile: "pr" });
  assert.deepEqual(receipt.allowed_paths, ["compiler/spec.mbt", "spec.mbt"]);
  assert.equal(receipt.warning_code, 68);
  assert.equal(receipt.declarations.length > 0, true);
  assert.throws(() => verifyDeclarationScope({ profile: "release" }), /release rejects every warning exception/);
});
