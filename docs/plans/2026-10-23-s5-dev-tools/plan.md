# S5 plan

Contract: `specification.md` (R1–R18, A1–A24). Fork-owned Dart code goes under
`lib/plezytv/`, tests under `test/plezytv/`, fork Kotlin under
`android/app/src/main/kotlin/com/edde746/plezy/plezytv/`. Do not edit
`lib/main.dart`, `lib/screens/main_screen.dart`, or any other upstream file over
~1500 lines. Hooks into upstream files stay minimal and are listed per task.
Checks for every task: `flutter analyze` on changed files, `dart format`, the
task's unit tests, `flutter build apk --debug --target-platform android-arm`
(toolchain in `.tools/`, see `docs/plezytv/release.md`) when Kotlin/Gradle
changes. Commit only the task's files.

## T1 — Screen links (R1–R7)

Result: `plezytv://screen/<target>` opens home, libraries, library, item,
search(q), downloads, settings, and reserves `update` for T4 (until T4 lands,
`update` logs "unavailable").

- Manifest: add a `plezytv`/`screen` intent filter next to `play`/`live`.
  `WatchNextPlugin.handleIntent`: return the whole URI for host `screen`, like
  `live`.
- `SystemShelfService` hook (only this file in Dart upstream): in
  `_handleMethodCall` and `getInitialDeepLink`, pass the string to the router
  first; a claimed link is neither forwarded to `onShelfItemTap` nor returned.
  `plezytv://play|live` and shelf IDs must pass through unchanged (A5, A18).
- Router: pure parser to a typed link (unit-tested for every target, bad input,
  missing params); one pending link (latest wins, no timeout, R3); readiness =
  `CompanionRemoteReceiver.instance` tab callbacks registered by the main screen
  (verify `PlatformDetector.shouldActAsRemoteHost` is true on Android TV; if not,
  stop and report). Watch readiness without polling heavily (a short periodic
  check or a listener exposed from the receiver file if small — receiver file
  is upstream; a minimal notifier hook there is allowed). Tab targets call the
  receiver callbacks (`onHome`, `onTabLibraries`, `onSearchAction(q)` /
  `onTabSearch`, `onTabDownloads`, `onTabSettings`). `library` and `item`
  resolve via `MultiServerProvider` clients and push existing screens through
  existing navigation helpers using `rootNavigatorKey`. Target table is one map
  so S3 can replace handlers (R6). Every failure: one `appLogger.w` with link
  and reason (R4).
- Docs: `docs/plezytv/dev-tools.md` with an `am start` example per target and the
  screencap recipe (R7).

## T2 — Log tag (R8–R10)

Result: on Android `appLogger` lines go to logcat tag `PlezyTV`; debug builds
also keep console output; buffer/redaction/filter unchanged.

- Hook: `lib/utils/app_logger.dart` — give the `Logger` a fork-owned output on
  Android (non-Android and tests keep current behavior).
- Output batches lines (preserving order) to a fork Kotlin channel that calls
  `android.util.Log.println(priority, "PlezyTV", chunk)`, chunked under ~4000
  chars. Register the channel with the smallest hook in `PlezyActivity`'s plugin
  registration (single line) or as a Flutter plugin class registered from
  existing registration code.
- Tests: batching/order/level mapping/chunking with a fake channel; existing
  logger tests still pass.

## T3 — Release versioning (R11)

Result: tag builds carry `PLEZYTV_VERSION` and `versionCode = major*10000 +
minor*100 + patch`, equal for both ABIs; non-tag builds carry no
`PLEZYTV_VERSION`.

- `.github/workflows/plezytv-build.yml`: on tag builds compute both values from
  `vX.Y.Z` (fail on other tag formats), pass `--build-number` and
  `--dart-define=PLEZYTV_VERSION=X.Y.Z`. Manual builds unchanged.
- Gradle: neutralize Flutter's per-ABI versionCode offset for these builds in
  `android/app/build.gradle*` (e.g. override `versionCodeOverride` per output
  in the fork's own small block), without affecting the `AMAZON` branch.
- Verify locally: build split APKs with `--build-number=200` and check
  `aapt2 dump badging` shows versionCode 200 for both ABIs.
- Update `docs/plezytv/release.md`: version scheme, one-time reinstall over
  v0.1.0.

## T4 — Updates (R11–R18), after T1 and T3

Result: automatic and manual update check against `underlow/PlezyTV`, dialog,
APK download with progress/cancel, install via system installer.

- Dart service in `lib/plezytv/update/`: version from `PLEZYTV_VERSION`
  (empty → disabled everywhere); anonymous GitHub `releases/latest`; strict
  `vX.Y.Z` compare; asset for installed ABI; cooldown 6 h set on automatic
  request; skipped version; fork-specific pref keys. Unit tests with HTTP mock
  (A8, A11–A13, A20, A22, A23).
- Kotlin helper: installed ABI, `canRequestPackageInstalls`, open
  `ACTION_MANAGE_UNKNOWN_APP_SOURCES` for the package, launch installer for a
  cache file through `${applicationId}.fileprovider` (cache path exists).
  Manifest: `REQUEST_INSTALL_PACKAGES`.
- Download: to cache with progress and cancel; delete partial on failure/cancel;
  delete old APKs on start and before download; reuse a completed download.
- Dialog (remote-navigable, focus on Install; Skip only for automatic) using
  existing dialog helpers and i18n strings in fork-owned code (English plus
  Russian if the i18n setup allows fork keys without editing generated upstream
  files; otherwise English only and note it).
- Startup trigger: from the T1 readiness signal (main screen ready), never
  over the player — defer while a video player route is active.
- Settings: one guarded tile hook in `settings_screen.dart` showing PlezyTV
  version and running the manual check. Router target `update` runs the manual
  check.

## Integration and verification

After all tasks: full `flutter test test/plezytv` plus touched upstream tests,
`flutter analyze`, debug APK build. On a TV (if connected via adb): A1–A4, A6,
A14–A18 by `am start` + `logcat -s PlezyTV` + screencap. Update flow end-to-end
needs a real tagged release; if unavailable, verify by unit tests and a manual
install of a locally built APK through the installer path, and report the gap.

## Outcome

Delivered 2026-10-23 (branch `flow/s5-dev-tools`, not pushed):
- T1 screen links `plezytv://screen/<target>` — `d03bd25ff`; usage in `docs/plezytv/dev-tools.md`.
- T2 logcat tag `PlezyTV` — `97048182f`.
- T3 tag-derived versions (`versionCode = major*10000+minor*100+patch`, same for both ABIs) — `908c58e96`;
  v0.1.0 (codes 1156/2156) needs a one-time uninstall, see `docs/plezytv/release.md`.
- T4 updater from `underlow/PlezyTV` releases (auto every 6 h, Settings tile, `screen/update`) — `18fc84d39`.
- Review fixes: `8dcc51bbd` (id/server validation against Plex path injection; links wait for profile
  picker, binding, library init; update link no longer blocks the queue; retry after profile switch),
  `173973bad` (no network polling for offline servers, one R4 warning; library delta-merge race; router
  test for update link).

Verification: 69 tests (`test/plezytv`, system_shelf_service, video_player_navigation) pass, rerun by the
coordinator; new tests fail without their fixes (negative controls); analyzer clean; debug ARM APK built;
split release build gives versionCode 200 on both ABIs. Independent reviews: behavior/tests and
security/performance on the whole change, targeted re-review of `8dcc51bbd`; `173973bad` was not
independently re-reviewed (user chose to deliver).

Not verified: nothing run on a TV (192.168.1.118 storage full) — A1–A4, A6, A14–A18 by `am start`,
logcat and screencap remain open; update download/install end-to-end needs a real tagged release;
AMAZON build and live CI not run. For S3+: screen links are ready for screenshot acceptance once the
build is on a TV; handlers in the router target table are replaceable.
