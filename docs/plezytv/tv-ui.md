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
`TvShell` builds the fork-owned `TvSectionShell`, forwarding both flags.
Non-TV profile homes still build upstream `MainScreen`.

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
including `null`, so navigator tests can avoid starting the full TV shell.
In teardown call `TvUi.resetForTesting()` (also clears the profile-home
interceptor). Do not use `TvDetectionService.debugSetAppleTVOverride`: it also
enables Apple TV paths.

The live `TvShell` builds `TvSectionShell` in
`lib/plezytv/tv_ui/shell/tv_section_shell.dart`. Tests use
`TvSectionShell.sectionBuilderForTesting(context, NavigationTabId tab, GlobalKey key)`:
return a stateful lightweight section using that key and implement the upstream
`FocusableTab`, `LibraryLoadable`, `SearchInputFocusable`, `Refreshable`,
`FullRefreshable` and `TabVisibilityAware` capabilities as needed. The shell
mounts sections lazily and keeps one Libraries section for all library identities.
`TvSectionShell.sessionControllerFactoryForTesting(context, onContentIntent)`
can supply a fake session controller, or return null to avoid starting services.
Reset both hooks to null in teardown. The former
`TvShell.mainScreenBuilderForTesting` hook has been removed.

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

## Shell and upstream parity

`TvSectionShell` in `lib/plezytv/tv_ui/shell/` owns section selection, focus,
Back, and companion navigation. It wraps the upstream Discover, Libraries,
Live TV, Explore, Search, Downloads and Settings screens in `TvTheme`, an
`IndexedStack` with lazy mounting and `TickerMode`, `TvSideMenu`,
`MainScreenFocusScope`, `SideNavigationScope`, `OverlaySheetHost` and
`AuthErrorBanner`. The Libraries screen is shared across library identities.
The menu follows provider availability and hidden libraries; More opens the
upstream library quick picker. `TvSettings.showDownloads` defaults to false and
only hides the menu entry, leaving links and remote navigation available.

`TvShellSessionController` owns session services and lifecycle observation;
`tv_shell_session_services.dart` supplies production provider/navigation
adapters. It starts after the first frame and is disposed with the shell.
`TvNoConnectionScreen` is the offline root, with retry progress and connection
settings. Losing connectivity keeps the current content visible while reducing
the menu. Reconnection restores the previous available section or the startup
section, unless a later selection superseded the retry. Online Back goes through
the menu to Home; offline Back goes to No connection. At the root, a second Back
within three seconds exits. Sheets consume Back before shell navigation.

The shell repeats the following duties from
[`lib/screens/main_screen.dart`](../../lib/screens/main_screen.dart). Upstream
fixes to these private methods do not automatically reach the TV shell. Compare
both implementations whenever upstream changes them; reuse shared policies
rather than copying their implementations.

| Duty | MainScreen methods | TV implementation in `shell/` |
|---|---|---|
| Session bootstrap: binder, Plex Home, active preferences | `initState`, `_handleOfflineStatusChanged` | Controller `start`, `_enterOnline`; production adapters |
| Prime after profile binding, with 15-second fallback; load libraries before content, watch sync and cached download metadata | `_runStartupOnFirstOnlineServer`, `_primeOnlineServices`, `_primeContentTabs` | Controller `_armStartup`, `_primeOnSettle`, `_primeOnlineServices`; shell `handleContentIntent(initialLoad)` |
| Resume queued downloads and sync collections for newly online servers | `_resumeQueuedDownloadsForServers` | Controller `_resumeDownloads` and server status subscription |
| Initial and late-arriving profile selection, respecting `initialPromptHandled` | `_promptForInitialProfileSelection`, `_pushProfileSelection`, `_onActiveProfileChanged` | Controller `_initialPrompt`, `_pushPicker`, `_profileChanged`; shared `runInitialProfilePrompt` |
| Profile/rebind invalidation: volatile cache, hidden libraries, library reload, shuffle and mounted content reset | `_onActiveProfileChanged`, `_invalidateAllScreens`, `_fullRefreshContentTabs` | Controller `_profileChanged`, `_invalidate`; shared `profileInvalidationAction`; shell `handleContentIntent(fullReset)` |
| Resume: Seerr user, conditional profile picker and stale content refresh | `didChangeAppLifecycleState`, `_showProfileSelectionOnResume`, `_refreshContentAfterStaleResume` | Controller `didChangeAppLifecycleState`, shared resume gates/policy; shell `handleContentIntent(refreshAfterResume)` |
| Launcher cold/warm links and Live TV playback | `_setupSystemShelfDeepLink`, `_handleShelfContentId` | Controller `_readColdShelfLink`, `_onShelfTap`; production `openShelfContent` and `launchLiveTv` adapters |
| Watch Together navigation and cleanup | `_setupWatchTogetherCallback`, `_navigateToWatchTogetherMedia`, `dispose` | Controller `start`, `_openWatch`, `dispose`; production playback adapter |
| Companion command routing, navigation ownership and optional host startup | `_setupCompanionRemote`, `_autoStartCompanionRemoteServer`, `dispose` | Shell `_setupCompanionRemote`, `_search`, `dispose`; controller `start` and host adapter |
| Optional Plezy update check/dialog | `_checkForUpdatesOnStartup`, `_showUpdateDialog` | Controller `start` and production `checkForUpdates` adapter (separate from the PlezyTV updater) |
| Offline state, reconnection and section availability | `_handleOfflineStatusChanged`, `_triggerReconnect`, `_handleTabAvailabilityChanged`, `_handleLiveTvChanged`, `_handleCatalogSourcesChanged` | Controller `_offlineChanged`, `_enterOnline`, `retry`; shell `_sessionChanged`, `_retry`, `availableTabs`, `_surface` |
| Startup section, lazy screens, tab visibility, library selection and quick picker | `initState`, `_buildScreens`, `_buildScreenSlot`, `_buildTickerAwareStack`, `_selectTab`, `_selectLibrary`, `_handleLibrariesScreenSelected`, `_showLibraryQuickPicker` | Shell `didChangeDependencies`, `_screen`, `_surface`, `selectSection`, `selectLibrary`, `_showMore` |
| Content/menu focus, Back, refresh/search/settings shortcuts and scope geometry | `_focusSidebar`, `_focusContent`, `_handleMainBack`, `_handleMainBackKeyAction`, `_handleBackKey`, `_handlePageRefreshShortcut`, `_handleSearchShortcut`, `_handleSettingsShortcut`, `_buildContent` | Shell `focusMenu`, `_focusContent`, `_back`, `_keyEvent`, `_surface`, `build` |
| Route coverage: Discover visibility/refresh and mini-player inset suspension | `didChangeDependencies`, `didPushNext`, `didPopNext`, `_onDiscoverBecameVisible`, `dispose` | Shell route subscription, `didPushNext`, `didPopNext`, `dispose` |

The upstream-sync workflow adds a PR warning when the merged diff changes
`lib/screens/main_screen.dart`, `lib/navigation/navigation_tabs.dart` or
`lib/navigation/main_screen_scope.dart`. Use this table as the review checklist.
TV has side navigation and no mini-player; it suspends existing inset reporting
while another route covers it, and does not report a bottom navigation bar height.

## Screen links and the shell

Keep S5 screen links in `lib/plezytv/screen_links/` working as documented in
[dev-tools.md](dev-tools.md). The live `TvSectionShell` supplies the descendant
`MainScreenFocusScope` used by `screen_link_router.dart` for `selectLibrary`,
and owns `CompanionRemoteReceiver.navigationOwner` and its tab/search/Home
callbacks. Command routing is installed after the first frame, once the scope is
mounted, and owned callbacks are removed on disposal. The router can then report
readiness and the PlezyTV updater can process pending startup work.

Links to home, libraries, a specific library, item, downloads, search, settings
and update use the existing targets. Downloads remains reachable when Show
downloads is off. Availability follows upstream tab visibility and library
existence. Remote Libraries opens the general Libraries section; Home selects
Home online or No connection offline. Section replacement stages must preserve
these scopes, callbacks, readiness and Back behavior. Initial profile prompting
continues to respect the profile session’s `initialPromptHandled` flag.

### S16 library section hookup

The shell's libraries section mounts `TvLibrariesSwitch` under its stable section key.
It alone resolves explicit keys (including hidden libraries), then Plezy's saved visible
selection, then the first visible library. Unknown keys use the same default resolution.
It saves selection through `StorageService` and reports it to the shell for the menu mark.
`isTvVideoLibrary` is shared by the switch and filtered links: movies, shows, and shared
video-only libraries use `TvLibraryScreen`; other kinds use `LibrariesScreen`.
The active child key and controller are replaced when the library or screen kind changes.
Refresh, full refresh, visibility and focus capabilities are forwarded to the active child.
Hiding the current library keeps it open; the all-hidden state opens T7's management panel.

`TvLibraryScreen.filtered` owns a separate controller with memory preferences, seeded from
saved grouping/sort and one incoming filter. Push it above the current route, without calling
the shell selector. Dispose that controller when the route closes. Normal section controllers
belong to the switch. Keep copied query glue and actions aligned with the seven upstream
paths listed in the S16 warning in `plezytv-upstream.yml` (design D1).

## Detail route hook and show screen (S7)

`navigateToMediaItemDetails` in `lib/utils/media_navigation_helper.dart` resolves
season/episode parents first, then calls `TvUi.showDetailRoute` with the resolved
metadata and initial season/episode arguments, falling back to `mediaDetailRoute`.
The synchronous lookup returns an opaque TV fade route only for online shows
when TV UI is enabled. Movie support belongs beside this branch in S8. Phone,
offline details, movies and seasons without a known show retain Plezy's route.
The accepted gap is “go to series” in `media_context_menu.dart`, plus navigation
inside upstream details: those direct `mediaDetailRoute` calls remain upstream.
Do not add hooks to those large files.

`show/TvShowController` owns server data and paged episodes; `TvShowScreen` owns
tabs, focus memory, delayed episode headers, Back and player return. The Show tab
uses `TvShowActions` for Plezy's trailer, shuffle, per-source watchlist, watched,
download and context-menu actions. Empty cast, extras and related rows are omitted.
Cast opens filmography; extras play directly; related posters use the shared media
navigation and menu. Vertical reveal animates for 150 ms and jumps on reduced
performance devices. Up returns to the selected tab.

Watch events patch cached episodes and mark the route result changed; playback
and actions reload metadata, seasons and previously loaded episode pages. Server
deletions close a deleted show or reload its children; download-only deletion
leaves online content visible. Downloads use the public Plezy options/deletion
flow for new/completed downloads. Partial, queued, paused, failed downloads and
sync rules open Downloads for management (S7 D3). Watchlist membership listens
to each candidate source's snapshot changes.

The upstream workflow warns on the seven S7 D2 dependency paths. Recheck the
show's copied orchestration and action visibility against those upstream files
when merging; private detail-screen handlers are not shared with this screen.
