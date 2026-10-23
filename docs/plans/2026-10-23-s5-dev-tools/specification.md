# S5 — Инструменты разработки и обслуживания

Project: `docs/projects/plezy-tv/project.md`, stage S5. Profile: medium.

## 1. Purpose and scope

Original stage text: «Ссылки на любой экран через `am start` (для скриншотов и
проверки агентом), свой тег логов, обновление со своих релизов. Сразу после S1,
до S3».

Outcome: an agent or user can open any main screen of PlezyTV on a TV with one
`adb shell am start`, filter the fork's logs with one logcat tag, and the TV
installs new PlezyTV releases from `github.com/underlow/PlezyTV` without a
browser.

Included: `plezytv://screen/...` links, `PlezyTV` logcat tag on Android, in-app
update check, APK download and install from own GitHub Releases, CI baking the
release version.

Excluded: links into the player (existing `plezytv://play` stays), changes to
upstream `UpdateService` behavior, non-Android update paths, uninstalling or
touching original Plezy, update sources other than GitHub Releases, own TV
screens (S3).

Repository rules (project): upstream stays mergeable; do not edit upstream files
of thousands of lines (`main_screen.dart`, `main.dart`, `media_detail_screen.dart`
are untouchable); fork code lives in fork-owned files with minimal hooks into
small/medium upstream files; mobile behavior unchanged.

## 2. Requirements

### Screen links
- **R1** `adb shell am start -a android.intent.action.VIEW -d 'plezytv://screen/<target>[?params]'`
  opens the target screen, both when PlezyTV is running and from a cold start.
- **R2** Targets: `home` (default start tab), `libraries`, `library?id=<sectionId>[&server=<machineId>]`,
  `item?id=<ratingKey>[&server=<machineId>]` (movie, show, season, episode detail),
  `search[?q=<text>]`, `livetv`, `downloads`, `settings`, `update` (runs a manual
  update check, R12). When `server` is omitted the first connected server that
  resolves the ID is used.
- **R3** On a cold start the link is applied after the active profile's servers
  are connected; if they do not connect within 30 s, the link is dropped with a
  warning log.
- **R4** An invalid link (unknown target, missing required parameter, unknown
  server or ID, target unavailable e.g. Live TV absent) changes nothing visible:
  the app stays where it was and logs one warning naming the link and reason.
  It never crashes.
- **R5** Existing `plezytv://play` and `plezytv://live` links keep working
  unchanged; original `plezy://` links are unaffected.
- **R6** Target names are a stable contract: S3 may redirect them to own TV
  screens without changing link syntax.
- **R7** Links are documented (`docs/plezytv/dev-tools.md`) with an example per
  target and a screenshot recipe (`adb exec-out screencap -p > x.png`).

### Log tag
- **R8** On Android every `appLogger` line is written to logcat with tag
  `PlezyTV` and the matching priority (d/i/w/e), so `adb logcat -s PlezyTV`
  shows the fork's app logs. Lines no longer go to the `flutter` tag.
- **R9** Redaction, in-memory log buffer (in-app log viewer/export), level
  filtering (debug only with the debug setting) are preserved. Non-Android
  platforms and tests keep current output.
- **R10** Logging must not block the UI thread noticeably: no synchronous
  round-trip per line; ordering of lines is preserved.

### Updates
- **R11** Release builds made from a `v*` tag carry that version
  (`PLEZYTV_VERSION`, e.g. `0.2.0`). Builds without it (manual CI runs, local)
  never check for updates and show no update UI.
- **R12** Check: GitHub `releases/latest` of `underlow/PlezyTV`; an update exists
  when its tag (without `v`) is semver-newer than `PLEZYTV_VERSION` and the
  release has an APK asset for the device ABI (`plezytv-v<ver>-armeabi-v7a.apk`
  or `-arm64-v8a.apk`; 64-bit devices prefer arm64 and fall back to v7a only if
  the installed app is v7a — i.e. use the installed app's ABI).
- **R13** Automatic check after startup, at most once per 6 hours, respecting a
  skipped version. Manual check (settings item, `plezytv://screen/update`)
  ignores cooldown and skip, and reports "up to date" or the failure.
- **R14** Update dialog: version, current version, actions Install / Later /
  Skip this version (skip only for automatic). Remote-navigable with focus on
  Install.
- **R15** Install: download APK to app cache with visible progress and cancel;
  then hand it to the system package installer. If installing unknown apps is
  not allowed for PlezyTV, open that system setting and explain; after the user
  returns, Install can be retried.
- **R16** Failures (no network, HTTP error, no matching asset, download
  interrupted, insufficient space) show a short message; the app keeps working;
  a partial file is deleted. The automatic check fails silently (log only).
- **R17** Settings shows one "Check for updates" item (with current
  PlezyTV version) only when R11 enables updates. Upstream update section stays
  hidden (ENABLE_UPDATE_CHECK remains false).
- **R18** No token or credential is sent to GitHub; requests are anonymous.

## 3. Design

**Link entry.** Android already routes `plezytv://play|live` from
`PlezyActivity` (cold start and `onNewIntent`) through
`WatchNextPlugin.handleIntent`, which returns the whole URI for `live`; Dart
receives it via `SystemShelfService` (`onShelfItemTap` warm, `getInitialDeepLink`
cold) and `main_screen` dispatches. Add `screen` host to the manifest filter and
`handleIntent` (return the whole URI, like `live`). In `SystemShelfService`,
before invoking `onShelfItemTap` and before returning `getInitialDeepLink`, offer
the string to a fork-owned `ScreenLinkRouter`; if it claims the link it is not
passed on. `main_screen.dart` is not changed.

**ScreenLinkRouter** (fork-owned, e.g. `lib/plezytv/screen_links/`): parses into
a typed `ScreenLink` (pure, unit-tested), then waits for readiness (active
profile session with `MultiServerProvider` having connected clients, bounded by
R3), and navigates using `rootNavigatorKey`. Tab targets select the main tab via
the existing main-screen scope API (`main_screen_scope.dart`) if it exposes tab
switching; otherwise the plan picks the smallest hook outside large files.
`library` and `item` resolve data with existing clients (`fetchItem`, library
sections) and push the existing screens via existing navigation helpers
(`media_navigation_helper.dart`). One target table maps names to handlers so S3
can swap handlers (R6). State: a single pending link (latest wins) held until
readiness or timeout.

**Log output.** In `app_logger.dart` the `Logger` gets a fork-owned output on
Android: a `LogOutput` that queues lines and sends them in batches over a
method channel to a small Kotlin handler calling `android.util.Log.println`
with tag `PlezyTV` (lines split under logcat's ~4 KB limit). Printer, filter,
redaction and `MemoryLogOutput` stay as is. Batching on a microtask/short timer
keeps order and avoids per-line round-trips (R10). Native Kotlin `Log` calls
with their existing tags are untouched.

**Updates.** Fork-owned `PlezyTvUpdater` (Dart) + Kotlin installer helper.
Version from `String.fromEnvironment('PLEZYTV_VERSION')`; empty → disabled.
`plezytv-build.yml` adds `--dart-define=PLEZYTV_VERSION=<tag without v>` on tag
builds only. Check uses existing HTTP client to GitHub API; ABI from the
installed APK (`Build`/`ApplicationInfo` via channel). Download to cache with
progress; installer via existing `${applicationId}.fileprovider` (add cache path
if missing) and `ACTION_VIEW`/`ACTION_INSTALL_PACKAGE`; manifest adds
`REQUEST_INSTALL_PACKAGES`; `canRequestPackageInstalls()` false → open
`ACTION_MANAGE_UNKNOWN_APP_SOURCES` for the package. Cooldown and skipped
version in shared prefs under fork-specific keys. Startup trigger: a hook
outside `main_screen.dart`/`main.dart` (plan chooses: profile session screen or
the router's readiness signal). Settings: one guarded tile hook in
`settings_screen.dart`.

Android versionCode comes from upstream pubspec and only grows with merges, so a
newer release normally installs over an older one; if the installer rejects a
downgrade, R16 applies.

## 4. Acceptance examples

| # | Initial state | Action | Expected | R |
|---|---|---|---|---|
| A1 | PlezyTV running on home | `am start ... -d plezytv://screen/settings` | Settings open | R1,R2 |
| A2 | PlezyTV not running, server reachable | `... -d 'plezytv://screen/item?id=12345'` (a show) | App starts, show detail opens after connect | R1,R3 |
| A3 | Running | `plezytv://screen/library?id=999999` | Nothing changes; logcat `PlezyTV` warns "library 999999 not found" | R4,R8 |
| A4 | Running | `plezytv://screen/foo` | Nothing changes; warning "unknown target foo" | R4 |
| A5 | Installed v0.1.0 tagged build | `plezytv://live?channel=4.1` | Channel tunes as before | R5 |
| A6 | Any | `adb logcat -s PlezyTV` while browsing | App log lines appear; none under `flutter` | R8 |
| A7 | Debug logging off | browse | Only info+ lines in logcat | R9 |
| A8 | Installed v0.2.0, release v0.3.0 with both APKs | start app (no check in 6 h) | Update dialog 0.3.0, Install focused | R12-R14 |
| A9 | A8, unknown sources not allowed | Install | Download completes, system setting for PlezyTV opens with explanation; after allowing, Install → system installer | R15 |
| A10 | A8, network drops mid-download | — | Message shown, partial file removed, app usable | R16 |
| A11 | Installed v0.3.0 = latest | Settings → Check for updates | "Up to date" | R13,R17 |
| A12 | Manual CI build (no tag) | open settings, start | No update item, no check | R11,R17 |
| A13 | Release has only arm64 APK, app is armeabi-v7a | check | No update offered; manual check says no compatible APK | R12,R16 |

## 5. Agreement

Confirmed by the user 2026-10-23: all three parts in S5; APK download and
install; profile medium; manual check as one item in settings; links, log tag
and tag-based version as proposed. Delegated to planning: exact file locations,
startup-trigger hook point, tab-switching mechanism, batching details.
