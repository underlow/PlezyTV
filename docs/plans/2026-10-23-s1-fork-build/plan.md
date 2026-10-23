# S1 plan

Contract: `requirements.md` (R1–R7, A1–A5). One developer pass, four ordered units; commit per unit.
General rule: minimal edits to upstream files (merge-friendliness); new files prefixed `plezytv`.

## U1 — Identity and authorities (R1)
- `android/app/build.gradle.kts`: `applicationId = "com.underlow.plezytv"`; keep `namespace`.
- Manifest: label "PlezyTV" (incl. alias labels if they hardcode "Plezy"); `fileprovider` and
  `systemshelf.artwork` authorities via `${applicationId}`; Kotlin users
  (`ExternalPlayerChannel.kt`, `SystemShelfArtworkProvider.AUTHORITY`) derive from package name /
  `BuildConfig.APPLICATION_ID`, not a literal. Check the remaining `com.edde746.plezy` string
  literals in `android/app/src/main` (not `package` lines) for anything that must equal the
  installed package (authorities, intent actions/component names built from strings, account
  types, prefs names visible to other apps); change only those that would clash or break.
- Preserve: component class names (launcher alias ids are permanent upstream), Kotlin packages.

## U2 — Link scheme (R2)
`plezy` → `plezytv` for the `play`/`live` scheme only: manifest intent filters,
`WatchNextProvider.kt`, `WatchNextPlugin.kt`, `lib/utils/live_tv_deep_link.dart`,
`lib/screens/main_screen.dart`, and their tests (`WatchNextProviderTest.kt`,
`test/utils/live_tv_deep_link_test.dart`). Prefer one constant per language if it reduces edits.
Do NOT touch unrelated "plezy" strings (companion-remote LAN discovery, trackers' OAuth
redirects, etc. — those are protocol/registered identifiers).

## U3 — Icon placeholder and design brief (R3)
- `docs/design/icon.md`: brief for Claude Design — launcher icon (adaptive fg/bg, legacy sizes),
  TV banner 320×180 (xhdpi), "PlezyTV" wordmark, must differ clearly from Plezy, references to
  `docs/design/tokens.json`; deliverable formats and where they'll be placed.
- `scripts/plezytv/make_placeholder_icons.*`: generate default `ic_launcher` (all densities,
  adaptive foreground) and `tv_banner` from the existing ones with a visible "TV" mark; commit
  the generated outputs. Alternate icons untouched.

## U4 — CI (R4–R7)
- `.github/workflows/plezytv-build.yml`: triggers `workflow_dispatch` and push tags `v*`. Reuse
  repo's `.github/actions/setup-flutter-git` and the Flutter version pin approach of `build.yml`.
  Fail early if `ANDROID_KEYSTORE_BASE64`/`ANDROID_STORE_PASSWORD`/`ANDROID_KEY_PASSWORD`/
  `ANDROID_KEY_ALIAS` are missing. `flutter build apk --release --split-per-abi
  --target-platform android-arm,android-arm64` with `GIT_COMMIT` define, without
  `ENABLE_UPDATE_CHECK` and `ENABLE_SENTRY` (R5). Remove keystore afterwards. Artifacts named
  `plezytv-<ver>-<abi>.apk`; on tag, create a GitHub Release with them (`gh release create`).
- `.github/workflows/plezytv-upstream.yml`: weekly cron + dispatch; fetch upstream, merge
  `upstream/main` into `upstream-sync` branch from `main`; on conflict open/update an issue
  (label `upstream-sync`) listing conflicted files; else run `flutter analyze`, `flutter test`,
  debug Android build; push branch and open/update PR to main; on check failure, PR still opened
  but marked/commented failing and issue opened. Never push main. Minimal permissions
  (`contents: write`, `pull-requests: write`, `issues: write`).
- `docs/plezytv/release.md`: keystore creation (`keytool`), adding secrets, tagging a release,
  disabling upstream workflows (build/ci/update-packages) in GitHub Actions UI (R7), installing via adb.

## Verification
- Developer: `flutter analyze`; `flutter test test/utils/live_tv_deep_link_test.dart` and the
  touched Dart tests; Android unit tests for watchnext (`./gradlew :app:testDebugUnitTest --tests '*WatchNext*'`);
  `flutter build apk --debug` succeeds; `aapt2 dump badging`/`apkanalyzer` shows package
  `com.underlow.plezytv`, label PlezyTV, and authorities with the new prefix; `actionlint` on
  new workflows if available; grep shows no remaining `plezy://` play/live claims.
- Coordinator/user on TV (A1, A2, A5): install next to Plezy, launch, `am start` both schemes.
- A3/A4 need pushing to GitHub with secrets — done by the user after delivery; not claimed here.

## Outcome (2026-10-23)
Implemented by Codex (gpt-6.1-sol, low): 63f4eeb9b identity/authorities, 18dba2b20 plezytv:// links,
3e21bd542 context-derived artwork authority, d1e4166ed/fff8b685b placeholder added then removed (user
decision), 0c03e07c3 CI + docs/plezytv/release.md, c8418649f designer art, df1a3413d art wired,
6e0d96315 UPSTREAM_SYNC_TOKEN guard, b45255a70 test authority fixes.
Review: one Codex reviewer over 052942a64..b45255a70; one finding (stale authority in
SystemShelfArtworkManifestTest) fixed and re-checked; no open findings.
Verified: resource XML parse, aapt2 compile of res, PNG equality with design, YAML parse, bash -n,
local simulation of push guard, source greps. NOT run (no Flutter SDK locally): flutter analyze/test/
build, Gradle/Robolectric tests, actionlint. Pending external acceptance: A1/A2/A5 on a TV, A3/A4 on
GitHub (needs keystore secrets, optional UPSTREAM_SYNC_TOKEN, upstream workflows disabled per release.md).
