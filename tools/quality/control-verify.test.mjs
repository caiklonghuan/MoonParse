import assert from "node:assert/strict";
import test from "node:test";

import { verifyControlPlane } from "./control-verify.mjs";

test("evidence control plane has mechanically checkable v1 requirements", () => {
  const receipt = verifyControlPlane();
  assert.equal(receipt.schema_version, 1);
  assert.equal(receipt.checked_files.length, 13);
  assert.equal(receipt.threshold_statuses.every(({ status }) => status === "candidate" || status === "hard"), true);
});
