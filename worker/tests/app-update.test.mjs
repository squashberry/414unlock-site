import test from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";

function makeDb(overrides = {}) {
  const values = {
    geoRestriction: "true",
    appLatestVersion: "1.4.2",
    appMinimumVersion: "1.0.0",
    appReleaseUrl: "https://github.com/squashberry/414unlock-site/releases/latest",
    appReleaseNotes: "Stability improvements and fixes.",
    appForceUpdate: "false",
    appPublishedAt: "1793350000",
    ...overrides
  };
  return { prepare() { return { all: async () => ({ results: Object.entries(values).map(([control_key, control_value]) => ({ control_key, control_value })) }) }; } };
}

async function getUpdate(version, controls = {}, platform = "windows", country = "GM") {
  const url = new URL("https://api.example.test/api/app/update");
  if (version !== undefined) url.searchParams.set("version", version);
  url.searchParams.set("platform", platform);
  const request = new Request(url, { headers: { "cf-ipcountry": country } });
  const response = await worker.fetch(request, { DB: makeDb(controls) });
  return { response, data: await response.json() };
}

test("reports an optional update with its published release details", async () => {
  const { response, data } = await getUpdate("1.2.0");
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.equal(data.updateAvailable, true);
  assert.equal(data.updateRequired, false);
  assert.equal(data.latestVersion, "1.4.2");
  assert.equal(data.releaseNotes, "Stability improvements and fixes.");
});

test("requires an update when the installed version is below minimum", async () => {
  const { response, data } = await getUpdate("0.9.9");
  assert.equal(response.status, 200);
  assert.equal(data.updateRequired, true);
  assert.equal(data.forceUpdate, true);
});

test("administrator can force all older versions to update", async () => {
  const { data } = await getUpdate("1.4.1", { appForceUpdate: "true" });
  assert.equal(data.updateAvailable, true);
  assert.equal(data.updateRequired, true);
});

test("does not prompt when the installed version is current", async () => {
  const { data } = await getUpdate("1.4.2");
  assert.equal(data.updateAvailable, false);
  assert.equal(data.updateRequired, false);
});

test("rejects a malformed version and an unsupported platform", async () => {
  const malformed = await getUpdate("1.4");
  assert.equal(malformed.response.status, 400);
  assert.equal(malformed.data.error, "INVALID_APP_VERSION");
  const platform = await getUpdate("1.4.2", {}, "linux");
  assert.equal(platform.response.status, 400);
  assert.equal(platform.data.error, "UNSUPPORTED_PLATFORM");
});

test("compares semantic version components numerically", async () => {
  const { data } = await getUpdate("1.9.9", { appLatestVersion: "1.10.0", appMinimumVersion: "1.0.0" });
  assert.equal(data.updateAvailable, true);
  assert.equal(data.updateRequired, false);
});

test("update checks remain available during maintenance and outside the site geo gate", async () => {
  const { response, data } = await getUpdate("1.0.0", { serviceMode: "true", geoRestriction: "true" }, "windows", "NG");
  assert.equal(response.status, 200);
  assert.equal(data.updateAvailable, true);
});
