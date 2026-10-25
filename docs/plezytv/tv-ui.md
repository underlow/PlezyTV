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
when TV UI is enabled; online movies take the S8 branch beside it. Phone,
offline details and seasons without a known show retain Plezy's route.
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

## Movie screen (S8)

`TvUi.showDetailRoute` returns a `TvMovieScreen` route for online `MediaKind.movie`
items under the same conditions as shows; `media_navigation_helper.dart` is
unchanged and `playDirectly` still bypasses details. The route pops `true` when
watch state changed. Movie screens stack: a related movie pushes a new screen and
Back pops one at a time. Accepted gap: movies opened inside upstream screens by a
direct `mediaDetailRoute` call stay on Plezy's details screen.

`movie/TvMovieController` owns data: `fetchItemWithOnDeck`, community ratings,
extras, related hubs, watch-event patching and the changed flag. `tv_movie_logic`
holds pure rules (button label, chosen version, tech info). `TvMovieScreen` owns
focus, last-button memory, scrolling, the collapsed title line, Back and player
return. `TvMovieActions` mirrors Plezy's action visibility and the watchlist and
download handlers of `action_buttons.dart`. The main button calls
`navigateToVideoPlayer`, not the refreshing variant, so Rewatch starts from zero;
the screen reloads afterwards. Partial, queued, paused and failed downloads open
Downloads, as in S7.

Quality chips and the bottom technical block (R7) describe the version Plezy will
play: the remembered choice, else the first. Studio, audio, subtitles and file
(resolution, codec, size) come from that version's already loaded
`mediaVersions`/parts/streams, for Plex and Jellyfin, with no extra request;
missing fields and an empty block are hidden.

Server deletion closes the screen; download-only deletion does not. When the
server reports the movie missing, the screen follows `media_detail_screen.dart`:
it closes, or shows an unavailable state when it is the first route. A failed
full-metadata load keeps the passed metadata. The upstream workflow warns on the
S8 paths; recheck the copied rules against them when merging.

## Player panel (S9)

On TV, outside Live TV, the player keeps Plezy's `PlexVideoControls` (keys,
markers, auto-skip, toasts, chrome fade) and replaces only what it draws. The
lookups in `TvUi` are synchronous and return `null`/`false` when TV UI is off or
the player is Live TV; then Plezy's widget or behaviour stays. Code lives in
`lib/plezytv/tv_ui/player/`; hook argument types are in `tv_player_hooks.dart`.

| Hook | File, place | Lookup returns | Fallback |
|---|---|---|---|
| H1 | `lib/widgets/video_controls/parts/navigation.dart`, the desktop-controls builder | `TvUi.playerPanel`: `TvPlayerPanel` built from the unmounted `DesktopVideoControls` plus `canControl`, `canNavigateMediaItems`, `playbackPromptOpen`, `playNextFocusNode`, `isOfflinePlayback`, `_skipMarkerFocusNode` | Plezy's `DesktopVideoControls` |
| H2 | `lib/widgets/video_controls/widgets/skip_marker_button.dart`, `SkipMarkerButton.build` | `TvUi.playerSkipButton`: `TvSkipButton` | Plezy's button |
| H3 | `lib/widgets/video_controls/parts/markers.dart`, skip-button focus request | `TvUi.playerPanelOwnsRemote`: `true` while the panel is shown, so the skip button does not take focus | `false`, Plezy focuses the button |
| H4 | `lib/screens/video_player/widgets/player_prompt_overlays.dart`, `VideoPlayerPlayNextOverlay.build` | `TvUi.playerUpNextCard`: `TvUpNextCard`, passed as `tvContent` into Plezy's `_VideoPlayerPromptShell` (position, PiP, prompt hold stay Plezy's) | Plezy's card |
| H5 | same file, `VideoPlayerBufferingOverlay.build` | `TvUi.playerBuffering`: `TvBufferingDots` | Plezy's spinner |
| H6 | `lib/screens/video_player/parts/build.dart`, `_buildPlaybackFailure` | `TvUi.playerPlaybackError`: `TvPlaybackError` with Plezy's message, retry, focus node and Back | Plezy's failure screen |
| H7 | same file, overlay stack | `TvUi.playerPauseIndicator`: `TvPauseIndicator` layer; it raises the panel (focus on play) only after a remote transport pause key with no prompt open | no layer |

`isLive` is passed into `VideoPlayerPlayNextOverlay` and
`VideoPlayerBufferingOverlay` as an optional field (default `false`) so the
lookups can exclude Live TV.

Part-file rule, clarified: `build.dart`, `navigation.dart` and `markers.dart`
are `part` files and cannot import. The `tv_ui.dart` and `tv_player_hooks.dart`
imports go into their libraries, `lib/screens/video_player_screen.dart` and
`lib/widgets/video_controls/video_controls.dart`; the hook lines stay in the
parts. Upstream hook lines are kept minimal (mostly one line) and are
deliberately not `dart format`-clean, to keep merge conflicts small.

`TvPlayerSession` (one per `Player`, outside widgets) holds focus memory, the
"focus play next time" flag, `sidePanelOpen` and the icons' focus node; it
resets when the video changes. The panel holds the chrome while the right
panel is open via `setContentStripVisible(true)`, like Plezy's content strip,
and is invisible and inert while a play-next or still-watching prompt is open.

Upstream tests `test/widgets/video_controls_auto_hide_test.dart`,
`video_controls_quiescence_test.dart` and `video_controls_startup_chrome_test.dart`
set `TvUi.enabledForTesting = () => false`: they test Plezy's desktop controls,
not the TV panel. The shared TV player test stand is
`test/test_helpers/tv_player_stand.dart`.

The panel repeats the following from Plezy (D6). Upstream changes to these
places do not reach the TV player; recheck them on every upstream merge.

| Duty | Plezy source | TV copy |
|---|---|---|
| Held ←/→ seeking on the bar: direction change, repeat count, step cap, preview, reset on release (D8) | `DesktopVideoControlsState` in `lib/widgets/video_controls/desktop_video_controls.dart`, over `lib/media/stepped_seek.dart` | `tv_player_panel.dart` |
| The four `_desktopControlsKey` methods (`requestPlayPauseFocus`, `abandonPendingSeek`, `dismissContentStrip`, `hideContentStrip`) replaced by panel subscriptions to `contentStripVisible`, `controlsVisible`, video change and prompt state (D7) | `desktop_video_controls.dart`, `video_controls.dart`, `parts/navigation.dart` | `tv_player_panel.dart`, `tv_player_session.dart` |
| Focus inside the panel and Back inside it (R16) | `desktop_video_controls.dart` | `tv_player_panel.dart`, `tv_player_side_panel.dart` |
| `DesktopVideoControls` constructor fields used by the test stand | `desktop_video_controls.dart` | `test/test_helpers/tv_player_stand.dart` |
| Skip-button position: right 24, bottom 24 / 115 / 180 (hidden, shown, content strip) | skip wrapper in `lib/widgets/video_controls/video_controls.dart` | `TvSkipButton` offsets in `tv_player_overlays.dart` |
| Settings, subtitle and audio items: visibility, values and callbacks | `lib/widgets/video_controls/sheets/video_settings_sheet.dart`, `track_sheet.dart` | `tv_player_side_panel.dart` |
| Play-next card content inside the prompt shell (`tvContent`) | `player_prompt_overlays.dart` | `TvUpNextCard` in `tv_player_overlays.dart` |

The upstream workflow warns when the merge changes
`desktop_video_controls.dart`, `markers.dart`, `player_prompt_overlays.dart`,
`build.dart`, `navigation.dart`, `video_controls.dart`, the two sheets or `stepped_seek.dart`; use this table
as the checklist.
