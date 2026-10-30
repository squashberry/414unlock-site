import test from "node:test";
import assert from "node:assert/strict";
import {
  normalizeIosVersion,
  compareIosVersions,
  resolveIosSupportRule
} from "../src/index.js";

test("normalizes numeric dotted iOS versions and rejects malformed values", () => {
  assert.equal(normalizeIosVersion(" 18.07 "), "18.7");
  assert.equal(normalizeIosVersion("26.1"), "26.1");
  assert.equal(normalizeIosVersion("18.beta"), null);
  assert.equal(normalizeIosVersion(""), null);
});

test("compares version components numerically rather than lexically", () => {
  assert.equal(compareIosVersions("18.7", "18.7.0"), 0);
  assert.equal(compareIosVersions("18.10", "18.7"), 1);
  assert.equal(compareIosVersions("17.9.9", "18.0"), -1);
});

test("an exact disabled rule blocks a version even inside an enabled range", () => {
  const rules = [
    {
      id: "enabled-range",
      match_type: "range",
      version: null,
      min_version: "17.0.1",
      max_version: "26.1",
      enabled: 1,
      updated_at: 100
    },
    {
      id: "blocked-exact",
      match_type: "exact",
      version: "18.7.0",
      min_version: null,
      max_version: null,
      enabled: 0,
      updated_at: 200
    }
  ];
  assert.equal(resolveIosSupportRule(rules, "18.7").id, "blocked-exact");
  assert.equal(resolveIosSupportRule(rules, "18.6").id, "enabled-range");
});

test("the narrowest overlapping range takes precedence", () => {
  const rules = [
    {
      id: "wide",
      match_type: "range",
      version: null,
      min_version: "17.0.1",
      max_version: "26.1",
      enabled: 1,
      updated_at: 100
    },
    {
      id: "narrow",
      match_type: "range",
      version: null,
      min_version: "18.0",
      max_version: "19.0",
      enabled: 1,
      updated_at: 100
    }
  ];
  assert.equal(resolveIosSupportRule(rules, "18.7").id, "narrow");
});

test("a disabled range wins when two matching ranges have equal width", () => {
  const rules = [
    {
      id: "allowed",
      match_type: "range",
      version: null,
      min_version: "18.0",
      max_version: "19.0",
      enabled: 1,
      updated_at: 200
    },
    {
      id: "blocked",
      match_type: "range",
      version: null,
      min_version: "18.0.0",
      max_version: "19.0.0",
      enabled: 0,
      updated_at: 100
    }
  ];
  assert.equal(resolveIosSupportRule(rules, "18.7").id, "blocked");
});

test("an unlisted version has no matching rule and must be blocked by the API", () => {
  assert.equal(resolveIosSupportRule([], "18.7"), null);
});
