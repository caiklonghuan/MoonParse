import assert from "node:assert/strict";
import test from "node:test";

import { verifyHistory } from "./history-verify.mjs";

test("V00 validates the immutable contest and archive anchors", () => {
  const receipt = verifyHistory();
  assert.equal(receipt.gate, "V00");
  assert.equal(receipt.baseline.sha, "68065b686857af26966f084114966c59c347a562");
  assert.equal(receipt.archive.sha, "d8bffb8be6a9a387fdfdbb7812fdfaf66d89b06f");
  assert.match(receipt.candidate_sha, /^[0-9a-f]{40}$/);
});
