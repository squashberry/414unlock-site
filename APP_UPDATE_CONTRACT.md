# 414Unlock Windows app update contract

This contract is the integration hand-off for the Windows desktop app and its installer. The website/Worker publishes the release policy; the native client is responsible for displaying the update prompt and launching the downloaded installer.

## Endpoint

`GET https://414unlock-auth-api.414unlock.workers.dev/api/app/update?version={CURRENT_VERSION}&platform=windows`

- `version` is required and must use `major.minor.patch` (for example `1.4.2`).
- `platform=windows` is currently supported.
- No account token or browser login is required. The endpoint contains release metadata only.
- The response is `Cache-Control: no-store`; perform a fresh request at app startup and again periodically while the app is open (for example every 60 minutes). The installer should also check before installing or launching the installed app.

## Response

```json
{
  "ok": true,
  "product": "414Unlock",
  "channel": "stable",
  "platform": "windows",
  "currentVersion": "1.2.0",
  "latestVersion": "1.4.2",
  "minimumVersion": "1.0.0",
  "updateAvailable": true,
  "updateRequired": false,
  "forceUpdate": false,
  "releaseUrl": "https://github.com/squashberry/414unlock-site/releases/latest",
  "releaseNotes": "Stability improvements and fixes.",
  "publishedAt": 1793350000,
  "checkedAt": 1793350100,
  "message": "A newer version of 414Unlock is available."
}
```

Use numeric semantic-version comparison, not a text/lexicographic comparison. `updateAvailable` means `currentVersion` is lower than `latestVersion`. `updateRequired` is true when the user is behind and either the administrator enabled the force-update switch or the installed version is lower than `minimumVersion`.

## Required client behavior

1. Keep the app's current version in one authoritative constant that matches the actual packaged executable/installer version. Do not infer it from the API response.
2. On startup, call the endpoint with the actual installed version. Check again about once per hour while running. Do not block startup if the update service is temporarily offline; retain any last known result and retry later. Never invent an update when the request fails.
3. When `updateAvailable` is true and `updateRequired` is false, show a clear non-blocking banner/dialog: **A new version is available**, display `latestVersion` and `releaseNotes`, and offer **Update now** (open `releaseUrl`) and **Later**.
4. When `updateRequired` is true, show a blocking **Update required** screen, explain that this version is no longer supported, display `latestVersion` and `releaseNotes`, and provide an **Update now** action that opens `releaseUrl`. Disable access to service/unlock operations until the app has been updated. Do not disable account sign-out or the ability to open the release page.
5. After the installer completes, restart/relaunch the application and re-check the endpoint using the new executable version. Do not claim that an update succeeded merely because the link was opened.
6. Validate the release URL as HTTPS before opening it. Treat all release notes as plain text, not executable markup.
7. If `ok` is false or the server returns a non-success status, do not enforce a new update based on that failed response. Log a safe diagnostic and retry later.

## Admin publishing

In **Admin → Website controls → Desktop app updates**, set:

- **Latest app version**: the actual version being released.
- **Minimum supported version**: the oldest version that may continue using the app.
- **Release / installer URL**: the HTTPS download/release page for that build.
- **Release notes**: plain-text change summary.
- **Require this version from every older app version**: enables the blocking update prompt for all older versions.

Publish only after the installer/release asset is available. The site does not automatically build or upload the native installer; Antigravity must wire this endpoint into the installer/app update flow.
