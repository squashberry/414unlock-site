import test from "node:test";
import assert from "node:assert/strict";
import { hasLeadingZeroBits } from "../src/index.js";

test("accepts the required leading zero bits", () => {
  assert.equal(hasLeadingZeroBits("000f" + "a".repeat(60), 12), true);
  assert.equal(hasLeadingZeroBits("0000" + "a".repeat(60), 16), true);
});

test("rejects proof hashes that do not meet the difficulty", () => {
  assert.equal(hasLeadingZeroBits("001f" + "a".repeat(60), 12), false);
  assert.equal(hasLeadingZeroBits("000f" + "a".repeat(60), 13), false);
});

test("rejects malformed hashes and unsupported difficulty values", () => {
  assert.equal(hasLeadingZeroBits("not-a-hash", 12), false);
  assert.equal(hasLeadingZeroBits("0".repeat(64), 0), false);
  assert.equal(hasLeadingZeroBits("0".repeat(64), 25), false);
});
