# S3 — Plan

Contract: `specification.md` (agreed). Checkout `/Users/underlow/Projects/PlezyTV`,
branch `flow/s3-tv-shell`. Diff base for upstream-footprint checks: `4a510b351`.

## Result

On TV the profile home is `TvShell` (showing upstream `MainScreen`), chosen once
per profile session; on non-TV nothing changes. Registry and convention ready for
S6+.

## T1 — Registry, shell and profile-home hook

Files: new `lib/plezytv/tv_ui/tv_ui.dart`, `lib/plezytv/tv_ui/tv_shell.dart`,
`test/plezytv/tv_ui/*_test.dart`; hook in `lib/navigation/profile_session_screen.dart`
(≤ 5 lines + import, only in `ProfileSessionNavigator` state / `_onGenerateRoute`).

- `TvUi`: `enabled` via injectable `bool Function()` (default `PlatformDetector.isTV`,
  `@visibleForTesting` setter/reset); typed `profileHome(...)` lookup per spec §3.
- Navigator state captures `TvUi.enabled` once in `initState`; fallback order
  `profileShellBuilder ?? TvUi lookup ?? MainScreen(...)`.
- `TvShell` renders `MainScreen` with the passed `isOfflineMode` / `initialPromptHandled`.
- Tests: A1, A2, A3, A3a, A3b. Build test trees like
  `test/navigation/profile_session_screen_test.dart`; where full `MainScreen` is too
  heavy for a widget test, verify the selected builder/arguments through a
  fork-owned seam rather than editing upstream further.

Verification: new tests pass and fail without the hook (negative control);
`flutter test test/navigation test/plezytv`; `flutter analyze` clean;
A5 diff check.

## T2 — Convention guide

File: `docs/plezytv/tv-ui.md` covering R6 (where code goes, registering, adding a
typed lookup + factory hook, fallback rule, forbidden upstream files, per-session
choice, screen-link targeting, the S12 replace-not-wrap contract). Depends on T1
(describe the actual API). Verification: coordinator checks names against code.

## Not in scope / limits

No visible change; TV run (A6) only if a TV has free storage.
