# PlezyTV TV UI

Put TV screens and their supporting code under `lib/plezytv/tv_ui/`, with tests
under `test/plezytv/tv_ui/`. `TvUi` in `tv_ui.dart` owns the typed replacement
lookups; `TvShell` in `tv_shell.dart` is the profile home. There is no UI switch:
TV always uses the PlezyTV UI. Until a replacement is ready, it can render the
upstream screen. Non-TV keeps the upstream UI.

## Adding a screen

Add a typed, nullable lookup to `TvUi`, with the arguments the screen needs;
do not use string keys. Return the TV replacement when enabled, or `null` for
the unchanged upstream fallback. Keep lookups synchronous and cheap: at most
one detection bool read per call, no I/O, async work or provider lookups.

Add a 1–3 line hook plus an import in the small/medium upstream factory that
builds the screen. Hooks only call the registry and retain the upstream fallback;
keep TV decisions and implementation in fork-owned files, with no
`context.watch` or provider lookups in hooks. The existing profile-home hook has
a budget of at most five changed lines plus one import, including its session
snapshot wiring. Its precedence in `ProfileSessionNavigator._onGenerateRoute`
(`lib/navigation/profile_session_screen.dart`) is:

```dart
widget.profileShellBuilder?.call(context) ??
TvUi.profileHome(context, enabled: _tvUiEnabled,
    isOfflineMode: widget.isOfflineMode,
    initialPromptHandled: widget.initialPromptHandled) ??
MainScreen(isOfflineMode: widget.isOfflineMode,
    initialPromptHandled: widget.initialPromptHandled)
```

The explicit test builder wins, then the registry, then upstream. The actual
lookup is `TvUi.profileHome(BuildContext context, {bool? enabled, required bool
isOfflineMode, required bool initialPromptHandled})`, returning `Widget?`.
`TvShell` currently builds upstream `MainScreen`, forwarding both flags.

Never add hooks to `lib/main.dart`, `lib/screens/main_screen.dart`,
`lib/screens/media_detail_screen.dart`, or other upstream files of thousands of
lines. `mediaDetailRoute` is a function inside `media_detail_screen.dart`, not a
separate small factory file. The stage replacing details must decide a suitable
small factory seam or minimal extraction while respecting this restriction and
keeping the upstream edit minimal; its name alone does not make it an allowed
hook location.

## Visual layer

Shared visuals live in `lib/plezytv/tv_ui/`: `tv_tokens.dart` mirrors the design
tokens, `tv_theme.dart` supplies `TvTheme`, `tv_focusable.dart` wraps upstream
focus logic, `tv_tint_service.dart` and `tv_tinted_background.dart` supply artwork
tinting and backgrounds, and `components/` contains the shared TV components.
`TvTheme` is opt-in; upstream screens keep their existing look until a TV
replacement explicitly wraps its subtree.

Component sizes are design px at 1920×1080. `TvTheme.of(context).px(value)`
converts them with `min(width / 1920, height / 1080)` using the theme root's
`MediaQuery` size. System text scaling is disabled inside the TV theme. Logic
comes from Plezy, including watch state, ratings, ordering and formatting; the
design only styles those results.

TV components manage their own scrolling; `TvFocusable.autoScroll` defaults to
off. Scrolling animates normally and jumps when `DevicePerformance.isReduced`;
screen stages must follow the same rule for vertical page scrolling. The reduced
scroll policy is a performance hypothesis to confirm with S2 measurements or
first screen acceptance.

Use `pumpTvWidget` from `test/plezytv/tv_ui/tv_theme_test_helper.dart` for component
tests. It supplies the TV theme and keyboard input mode at a chosen logical
`size`, accepts `reduced` and `textScaler`, and resets test state in teardown.

## Session choice and tests

`TvUi.enabled` defaults to `PlatformDetector.isTV()`, which includes the Force TV
setting. Force TV can change at runtime. `ProfileSessionNavigator` captures
`TvUi.enabled` in `initState` as `_tvUiEnabled` and passes it as `enabled:` to
`profileHome`. Keep this per-session choice: changing Force TV must not remount
the home mid-session; the new choice applies when the next profile navigator
state is created. A lookup without `enabled:` reads the current detection value.

Follow `test/plezytv/tv_ui/tv_ui_test.dart` and the profile-session test harness.
Set `TvUi.enabledForTesting = () => true` (or `false`) to control detection.
`TvUi.profileHomeBuilderForTesting` intercepts the selected replacement,
including `null`, so navigator tests can avoid starting the full upstream home.
`TvShell.mainScreenBuilderForTesting` receives the configured `MainScreen` and
can substitute a lightweight stateful probe. In teardown call
`TvUi.resetForTesting()` (also clears the profile-home interceptor), and reset
`TvShell.mainScreenBuilderForTesting = null` separately. Do not use
`TvDetectionService.debugSetAppleTVOverride`: it also enables Apple TV paths.
These probes check selection, arguments and state retention; they do not verify
the full upstream home on a device.

S12 T4 introduces the separate `TvSectionShell` in
`lib/plezytv/tv_ui/shell/tv_section_shell.dart`. The live `TvShell` still builds
`MainScreen` until T6. Tests of the new surface use
`TvSectionShell.sectionBuilderForTesting(context, NavigationTabId tab, GlobalKey key)`:
return a stateful lightweight section using that key and implement the upstream
`FocusableTab`, `LibraryLoadable`, `Refreshable`, `FullRefreshable` and
`TabVisibilityAware` capabilities as needed. The shell mounts sections lazily and
keeps one Libraries section for all library identities. T5 and T6 must reuse this
hook. `TvSectionShell.sessionControllerFactoryForTesting(context, onContentIntent)`
can supply a fake T2 controller, or return null to avoid starting session services.
Reset both hooks to null in teardown. Keep the older MainScreen hook while the
live shell still uses it; T6 removes it when switching the live shell.

`TvShellSection.tab(NavigationTabId)` and `TvShellSection.library(globalKey)`
are the shared section identities. `TvSectionShellState` exposes `currentSection`,
`selectionCommand`, `isSectionAvailable`, `selectSection`, `selectLibrary` and
`focusMenu` for the remaining shell integration. Every accepted selection
increments the command counter, including a repeated selection, so deferred
library loads and focus cannot override a later command. Availability uses
upstream tab visibility and library existence; Show downloads only filters the
menu. `handleContentIntent` maps T2 initial load to `primeRefresh`, stale resume
to `LibrariesProvider.refresh` plus `Refreshable.refresh`, and profile reset to
`fullRefresh`, only on mounted Home, Libraries and Search sections.

## Screen links and the later home

Keep S5 screen links in `lib/plezytv/screen_links/` working as documented in
[dev-tools.md](dev-tools.md). New screens must remain reachable through those
existing targets and the profile navigator, preserving readiness, tab/navigation
callbacks and Back behavior. `screen_link_router.dart` searches descendant
widgets for `MainScreenFocusScope` to obtain `selectLibrary`; retaining only a
similar-looking TV library screen is insufficient. Today the upstream
`MainScreen` inside `TvShell` supplies that scope and the navigation callbacks.

In S12, `TvShell` must replace `MainScreen`, rather than keep wrapping it. Before
removing the upstream home, the TV implementation must provide:

- `MainScreenFocusScope`, including library selection, and the navigation
  callbacks/readiness used by S5 links.
- Bottom-bar inset reporting to the session’s `MiniPlayerInsetController`, so
  the mini-player stays above the TV navigation UI.
- First-prompt handling that respects `initialPromptHandled`, preserving the
  profile-session contract and avoiding repeated startup prompts.

These are requirements for the replacement, not functionality already
implemented independently by `TvShell`.
