# S3 — Каркас своего TV-интерфейса

Project: `docs/projects/plezy-tv/project.md`, stage S3. Profile: medium.

## 1. Purpose and scope

Stage text (revised 2026-10-23): «Место для своих TV-экранов: реестр PlezyTV и
маленькие точки подключения в фабриках апстрима (каждый экранный этап добавляет
свою). Переключателя нет: на TV всегда свой интерфейс (пока экраны не готовы —
внутри апстримные, допускается криво), на телефоне — апстримный.»

Outcome: later screen stages (S6–S12, S14) add a TV screen by writing fork-owned
code under `lib/plezytv/tv_ui/` and, at most, a 1–3 line hook in the upstream
factory that builds the corresponding screen. S3 delivers the registry, the
first hook (the profile home), a TV shell that for now shows the upstream
`MainScreen`, and the written convention.

Included: TV UI registry; TV profile shell; hook in `ProfileSessionScreen`'s
home route; convention document `docs/plezytv/tv-ui.md`; tests.

Excluded: any visible design change (S6), any custom screen (S7+), a settings or
adb switch between interfaces (explicitly rejected by the user), hooks in other
factories such as `mediaDetailRoute` (added by the stage that replaces that
screen), non-TV platforms.

Repository rules (project): upstream stays mergeable; do not edit upstream files
of thousands of lines (`main_screen.dart`, `main.dart`, `media_detail_screen.dart`);
fork code lives in fork-owned files with minimal hooks into small/medium upstream
files; mobile behavior unchanged.

Premises checked during analysis (code reading of this checkout, not a TV run):
- Upstream already has one place building the profile home:
  `ProfileSessionNavigator._onGenerateRoute` in
  `lib/navigation/profile_session_screen.dart` (~430 lines), falling back to
  `MainScreen(...)`. Detail pages go through `mediaDetailRoute` in
  `media_detail_screen.dart`; settings are constructed from ~20 call sites. So a
  literal single hook cannot cover all screens; per-factory hooks are needed.
- TV detection: `PlatformDetector.isTV()` = device detection or the user's
  Force TV setting. Force TV can change at runtime
  (`settings_mutation_service.dart:73`, `platform_detector.dart:173`), and the
  route builder can re-run, so a live read in the hook would remount `MainScreen`.
  Detection is awaited before the UI starts (`main.dart:219`).
- S5 screen links (on this branch, not yet in `main`) locate
  `MainScreenFocusScope` in the widget tree; they keep working while the shell
  contains upstream `MainScreen`.

## 2. Requirements

R1. On TV (`PlatformDetector.isTV()` true) the profile home route builds the
PlezyTV TV shell. On non-TV it builds upstream `MainScreen` exactly as before.
An explicitly supplied `profileShellBuilder` (tests) still takes precedence.

R2. In S3 the TV shell renders upstream `MainScreen` with the same
`isOfflineMode` and `initialPromptHandled` values; user-visible behavior on TV
is unchanged (sign-in, profile picker/switch, tabs, Back, offline mode, S5
screen links and updater).

R3. A registry under `lib/plezytv/tv_ui/` is the single fork-owned place where
TV replacements are declared. Each upstream hook asks the registry for a
replacement for its screen and, when there is none or the device is not TV,
continues with upstream code unchanged. Hooks contain no TV logic beyond that
call.

R4. Registry lookup is synchronous and cheap: one bool read per call, no I/O,
async, `context.watch` or provider lookups in hooks (navigation paths on Mi Box 4).

R7. The TV/non-TV choice for the profile home is made once per profile session
(when its navigator state is created) and kept; toggling Force TV mid-session
does not remount `MainScreen` and applies from the next profile session.
Sign-in, offline entry and the updater sit above `ProfileSessionNavigator` and
are unaffected by construction.

R5. Upstream diff for S3 is limited to the profile-home hook (target: ≤ 5 changed
lines in `profile_session_screen.dart` plus one import).

R6. `docs/plezytv/tv-ui.md` explains how a stage adds a TV screen: where code
goes, how to register it, how to add a hook to an upstream factory, the
fallback rule, which upstream files must not get hooks, and how screen links
should target the new screen. It states that `TvShell` will later replace
`MainScreen` rather than wrap it, and lists what it must then provide:
`MainScreenFocusScope` (S5 links, `screen_link_router.dart:128`), bottom-bar
inset reporting (`profile_session_screen.dart:338`), and first-prompt /
`initialPromptHandled` handling.

## 3. Design

- `lib/plezytv/tv_ui/tv_ui.dart`: `TvUi` with `bool get enabled`
  (= `PlatformDetector.isTV()`) and typed lookup functions per hook point. S3
  defines one: `Widget? profileHome(BuildContext, {required bool isOfflineMode,
  required bool initialPromptHandled})` returning the shell on TV, `null`
  otherwise. Later stages add their own typed lookup (e.g. `mediaDetailPage`)
  rather than a stringly-keyed map, so call sites stay compile-checked.
- `lib/plezytv/tv_ui/tv_shell.dart`: `TvShell` widget; in S3 returns
  `MainScreen(...)`. It is the future home for the TV side menu (S12).
- Hook: `_onGenerateRoute` fallback becomes
  `widget.profileShellBuilder?.call(context) ?? TvUi.profileHome(...) ?? MainScreen(...)`.
- `TvUi.enabled` reads an injectable `bool Function()` defaulting to
  `PlatformDetector.isTV`; tests override it (fork-owned, `@visibleForTesting`).
  The upstream `debugSetAppleTVOverride` is not used: it also enables Apple TV paths.
- The navigator state captures `TvUi.enabled` once in `initState` and passes it
  to the lookup.
- Tests under `test/plezytv/tv_ui/`, using the existing `profile_session_screen_test`
  harness patterns.

## 4. Acceptance examples

A1. Non-TV test environment: profile session home is `MainScreen`, no `TvShell`
in the tree.
A2. TV forced: profile session home contains `TvShell` whose child is
`MainScreen` with the passed `isOfflineMode`/`initialPromptHandled`.
A3. `profileShellBuilder` given: it is used on TV and non-TV.
A3a. TV with `isOfflineMode: true`: shell's `MainScreen` gets offline mode.
A3b. TV session mounted, then Force TV / TV override flips: the same `MainScreen`
`State` object remains mounted.
A4. Existing tests (`test/navigation`, `test/plezytv`) pass unchanged.
A5. `git diff 4a510b351 -- lib ':!lib/plezytv'` shows only the hook and import
(S5 is not yet in `main`).
A6. On a TV (when one has free storage): app starts to home, profile switch,
Back from a detail page, and `plezytv://screen/item?id=…` behave as before.
Not blocking delivery if no TV is available; recorded as unverified.

## 5. Agreement

Agreed by the user 2026-10-23 after independent challenge (findings applied: per-session TV choice, fork-owned test override, R4 wording, S12 contract in the guide, fixed diff base, offline/toggle tests).
