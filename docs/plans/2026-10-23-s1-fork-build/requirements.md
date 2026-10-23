# S1 — Fork, build, rename (small)

Project: `docs/projects/plezy-tv/project.md`, stage S1.

## Request
Public fork, Android TV APK build, side-by-side install with original Plezy (own name, icon,
banner, applicationId, link scheme), APK build in CI and releases; regular upstream merge with
automatic check.

## Result and scope
A PlezyTV APK that installs next to Plezy, built and released by own CI, with a regular
automated upstream merge check. Out of scope: updater on own releases, screen links, log tag (S5);
final icon art (Claude Design); non-Android platforms.

## Requirements
- **R1 Identity.** applicationId `com.underlow.plezytv`, label "PlezyTV". Kotlin package and
  `namespace` stay `com.edde746.plezy`. FileProvider and system-shelf artwork authorities derive
  from the applicationId so install next to Plezy succeeds. Upstream large files are not edited
  beyond minimal identifier changes.
- **R2 Links.** Deep links use `plezytv://play` and `plezytv://live` everywhere (manifest, Watch
  Next / shelf links, Dart parsing). `plezy://` is not claimed.
- **R3 Icon/banner.** Brief for Claude Design in `docs/design/icon.md` (launcher icon + 320×180 TV
  banner). No placeholder (user decision 2026-10-23). Designer art in `docs/design/icon/` is wired as the
  default launcher icon (adaptive + monochrome + legacy) and TV banner within S1. Alternate icons untouched.
- **R4 Build.** `plezytv-build.yml`: release APKs arm64-v8a and armeabi-v7a, signed with own
  keystore from repo secrets; manual run or `v*` tag; tag publishes a GitHub Release with APKs.
  Missing secrets fail the job clearly (no debug-signed fallback). Doc on creating keystore and secrets.
- **R5 Updater/telemetry.** Own builds: update check off, Sentry off.
- **R6 Upstream check.** `plezytv-upstream.yml`, weekly + manual: merge `upstream/main` into a
  branch, run analyze, tests, Android build; open/update a PR on success; open an issue with
  details on conflict or failure. Never pushes to main.
- **R7 Upstream workflows.** Not edited; disabling them in GitHub settings is a documented manual step.

## Acceptance
- A1 (R1,R3): Plezy installed; `adb install` PlezyTV → both on launcher with different icon/banner, both launch.
- A2 (R2): `am start -d "plezytv://live?channel=…"` opens PlezyTV; `plezy://` opens Plezy.
- A3 (R4): push tag `v0.1.0` → Release with signed APKs.
- A4 (R6): clean upstream change → PR with green checks; conflicting → issue.
- A5 (R5): release build never shows an update dialog.

## Confirmation
Confirmed by user 2026-10-23. Delegated: placeholder generation method, workflow internals.
