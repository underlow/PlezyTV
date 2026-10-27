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

Screens with rows should build only rows near the viewport, with roughly one
screen of reserve above and below. Keep row memory (selected card and horizontal
offset) in the screen owner, keyed by row, so it survives the row leaving the
widget tree. `TvHorizontalRow` accepts external row memory; without it, memory
stays local to the row.

Home loads once at startup, after hidden libraries are initialized. Rows appear
as each server answers, with a short grace period to batch nearby answers, and
merge in library order; Continue Watching gains the later servers' cards.
Inserting rows keeps focus on the same card and preserves the focused row's
on-screen position.

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
`TvSectionShell.watchlistBuilderForTesting(context, key, onOpenSearch)` supplies
the «Список» probe while `sectionBuilderForTesting` is set (otherwise the slot is
an empty box). Reset these hooks to null in teardown. The former
`TvShell.mainScreenBuilderForTesting` hook has been removed.

`TvShellSection.tab(NavigationTabId)`, `TvShellSection.library(globalKey)` and
`TvShellSection.watchlist()` are the shared section identities. `tab` is null for
the watchlist and No connection; mounted screens, keys and visibility hooks use
`TvShellSection.slot` (the tab, or `TvShellSection.watchlistSlot`), so code that
compares `tab` with Home never mistakes either for Home. `TvSectionShellState` exposes `currentSection`,
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
upstream library quick picker. Up on the first enabled menu item and Down on
the last keep focus in the open menu, including offline mode; content stays put. `TvSettings.showDownloads` defaults to false and
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

### S10 watchlist section

«Список» (`lib/plezytv/tv_ui/watchlist/`) is a fork-owned section with no upstream
tab. Its menu entry (bookmark icon) follows the library entries directly, before
More, Live TV and Explore; the companion remote's next/previous step visits it after
Libraries. It is available while online with a non-empty
`CatalogSourcesProvider.watchlistCapableSources`; losing every source leaves for
Home, and a soft connection loss restores it like other sections.
`TvWatchlistScreen` is mounted lazily and owns its controller and availability
service. The shell calls `onTabShown`/`onTabHidden` only on section changes,
never for a covering route (that would cancel playback started from the list);
`handleContentIntent` maps resume to `refresh` (`backgroundRefresh`), the
cold-start/reconnect prime to `primeRefresh` (also `backgroundRefresh`: a silent
re-read when ready, retry after an error, nothing while loading, so focus and
scroll survive), and profile reset to `fullRefresh` (`fullReset`, which also
forgets every availability result and the check queue). «Go to search» selects
Search.

`TvWatchlistAvailability` re-checks every item when `expectedServerIds` changes
(the old result shows until the new one replaces it) and incomplete items when a
server comes online; checks running at that moment are queued again once after
they finish (incomplete ones only, for a server coming online); this includes
card checks, and a card check that supersedes a queued one inherits its
re-check and `refreshIncomplete` requirements. Posters listen to
their own item (`watch`); the «Есть на сервере» tab rebuilds only when the set of
found items changes (`foundRevision`). Membership notifications drop only items
whose `isOnWatchlist` flipped from true to false, since the membership snapshot
may not know items added on another device; such a drop is remembered like a card
removal (original place for «Вернуть в список», not resurrected by a lagging
re-read). A removed item comes back either through the card's `itemRestored` or
when membership data that has already read it as not listed reads it as listed
again; a `true` reading never preceded by `false` for that item (for example
membership finishing its first load after a card removal) may predate the
removal and does not restore it. A first snapshot that misses a listed item triggers one re-read.

Two upstream edits support it: `CatalogLibraryMatcher.match` takes
`refreshIncomplete` (re-queries servers that failed, were cancelled or not
queried, folding results into cached copies), and `plex_catalog_source.dart`
parses Plex `watchlistedAt` into `CatalogItem.addedAt` for the date-added sort.
`TvPagedSource.replaceAll(items, keepFocus:)` replaces in-memory content in one
notification; `TvPagedGrid` gained optional `onVisibleRangeChanged`,
`onPlayPause` and `keyOf` (focus kept by key with scroll compensation; a second
keep-focus replacement before the next frame corrects from the pending offset).
With `onVisibleRangeChanged`, the range is reported again after every
`replaceAll`. Without
them the S16 grid behaves as before.

### S11 search section

On TV the shell mounts `TvSearchScreen` (`lib/plezytv/tv_ui/search/`) for
`NavigationTabId.search`; phones keep upstream `SearchScreen`. No upstream edits.
The screen implements `SearchInputFocusable`, `Refreshable`, `FullRefreshable`,
`FocusableTab` and `TabVisibilityAware`, so companion search, `search?q=` links and
`handleContentIntent` reach it unchanged. `submitSearchQuery` searches at once and
focuses the first result (the first key when nothing is found); after such a
query, ← from results goes to the first key of the layout, otherwise to the last
pressed key. `primeRefresh` repeats the current query instead of clearing it
(reconnect keeps «дюн»); `fullRefresh` (profile reset) clears the query and
re-reads the profile's history.

`TvSearchController` (one per screen) owns the query, a 300 ms debounce, a
generation guard against stale answers and `AbortController` cancellation. It
calls `aggregationService.searchAcrossServers` with hidden library keys, as
`SearchScreen` does, and repeats `DebouncedMediaSearch`'s stale-response logic
and `SearchScreen.updateItem`'s item refresh; keep them aligned with the three
paths in the S11 warning in `plezytv-upstream.yml`. Results show tabs (All,
Movies, Shows, Episodes, People) and stacked rows in All; music, photos,
collections, seasons and clips are not shown.

`TvSearchKeyboard` is fork-owned (РУС/ENG/123, no microphone); the last layout is
a TV setting. Hardware text input types into the field. `TvSearchHistory` is
profile-scoped through `StorageService` and records only queries with results,
on opening a result, Back, `onTabHidden`, a covering route (`didPushNext`, which
includes item links) and `AppLifecycleState.paused`. The idle screen shows the
history and up to two Home hubs (Continue Watching excluded) selected by
`TvHomeModelBuilder` (poster rows only); their titles are server hub names, not the mockup's.
Card actions follow `TvHomeScreen`: `navigateToMediaItem` (episodes by Plezy's
episode setting), `MediaContextMenu`, Play/Pause through `TvHomePlayback`.
Home and the idle rows build hub cards with `TvHomeHubCard` and open "All" with
`openTvHubDetail` (`home/tv_home_card.dart`); search results reuse `tvHomeCardKeys`.
Home also shows artist, album and track hubs as lazy music rows: 216×216 covers
(round for artists), title and artist/album captions, without watch status.
Their trailing "All" card is square. Focus updates the existing hero and tinted
background; OK opens Plezy artist/album screens or plays a track in its album queue.
Play/Pause on Home and search cards yields to Plezy whenever a current music track
exists, including paused sessions. A restored parked session has no transport
handler until music starts again: Play/Pause does nothing there; resume from
Now Playing. Without a music session, card Play/Pause keeps its normal action.
The round person card shared with S7/S8 cast rows is `TvPersonCard`; in the People
grid it uses `externalFocus`, so the grid slot is the only focusable node.
A focus repair (R10) whose answer arrives while search is hidden or covered is
applied once the screen is current again (`onTabShown`, `didPopNext`).

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

Online Plex movies show a lazy **Reviews** rail after cast and before extras and
related titles. `TvMovieController.reviews` owns the immutable reviews for one
opening; `tv_movie_reviews.dart` requests `includeReviews=1` after metadata,
independently of other rows. Errors and empty results stay silent. Refresh keeps
reviews and does not repeat the request; disposal aborts it. Jellyfin and offline
movies have no request or rail. Reviews without text or both author fields are
filtered by the loader.

`TvMovieReviewCard` shows freshness, publication, critic and an ellipsized excerpt.
OK opens the full review in `TvRightPanel`, with a single-line ellipsized title;
Up/Down scroll by 102 design pixels, Left/Right stay put, and Back restores the
same card and page offset even if other rows finished loading behind the panel.
A late rail insertion above the focused row adds its measured height to the page
offset, preserving the card's screen position. Insertion while focus
is on the actions leaves page offset and focus unchanged.


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
| H7 | same file, overlay stack | `TvUi.playerPauseIndicator`: `TvPauseIndicator` layer; it raises the panel (focus on play, or the bar when play is unavailable) only when a remote transport pause key that Plezy could act on (`canControl`, from `_canControlPlayback`) went down within 1.5 s before the pause, with no prompt open. Key based (Android TV): Apple TV's Siri Remote Play/Pause goes through the native `play_pause` channel, not a Flutter key, so it does not raise the panel; the fork targets Android TV | no layer |

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
"focus play next time" flag, `sidePanelOpen` and the icons' focus node. Only
focus memory resets when the video changes; the play flag survives, since H7
may set it for the new item before the panel binds. The panel holds the chrome while the right
panel is open via `setContentStripVisible(true)`, like Plezy's content strip,
and is invisible and inert while a play-next or still-watching prompt is open;
the skip button then sits where it does with the panel hidden.

Back with focus on the skip button and the panel up hides the button for that
marker showing; with focus in the panel, Back hides the panel and, as in Plezy,
the button with it (R22). Keys handled on the skip button restart the panel's
auto-hide. The button is pinned at its design spot in the player's stack (the parent of Plezy's slot, so ancestor scales such as Apple TV's `FormFactorScale` apply to it), not offset from Plezy's slot, which moves on its own rebuilds; it never slides when it reappears, and only its own 200 ms tween moves it. Plezy's slot is a repaint boundary, so when it moves the button is not repainted by itself: after each frame the button checks the slot's place and, when it moved or the chrome controller notified, repaints every frame for 300 ms (Plezy's 200 ms slot motion); nothing is scheduled while the slot is still. The pause indicator goes 5 minutes after the pause began or the panel
last hid on that pause, so opening and hiding the panel brings it back (R18).

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
| Settings, subtitle and audio items: visibility, values and callbacks | `lib/widgets/video_controls/sheets/video_settings_sheet.dart`, `track_sheet.dart` | `tv_player_side_panel.dart` |
| Play-next card content inside the prompt shell (`tvContent`) | `player_prompt_overlays.dart` | `TvUpNextCard` in `tv_player_overlays.dart` |
| Skip-button label and icon: "Next episode" for credits ending within 1000 ms of the end with a next episode, else skip credits / intro; auto-skip remaining-seconds suffix | `lib/widgets/video_controls/widgets/skip_marker_button.dart` | `TvSkipButton._button` in `tv_player_overlays.dart` |
| Audio/subtitle sync: 50 ms step, apply → `recordApplied` → `ScopedPlayerPrefs.write` | `lib/widgets/video_controls/widgets/sync_offset_control.dart` | `_syncStepMs` and sync apply in `tv_player_side_panel.dart` |
| Sleep timer durations | `lib/widgets/video_controls/widgets/sleep_timer_content.dart` | `_sleepMinutes` in `tv_player_side_panel.dart` |

The upstream workflow warns when the merge changes
`desktop_video_controls.dart`, `markers.dart`, `player_prompt_overlays.dart`,
`build.dart`, `navigation.dart`, `video_controls.dart`, the two sheets, `skip_marker_button.dart`,
`sync_offset_control.dart`, `sleep_timer_content.dart` or `stepped_seek.dart`; use this table
as the checklist.

## Post-play screen (S14)

When a movie or episode ends on TV and leaving the player is allowed (R1), the
player is replaced by `TvPostPlayScreen` (`lib/plezytv/tv_ui/postplay/`): the
next episode or rewatch, "Your rating" stars (`TvRatingStars` in
`components/`, tokens `player.postplay` in `TvTokens`), the season's episodes
and one "similar" row. Rating save repeats Plezy's `rating_bottom_sheet.dart`:
`rate()` with the value, `rate(-1)` to clear, offered only with
`capabilities.numericUserRating`; saves run one after another. A leaving
press (Back, the card buttons, a launch, a row episode or a similar poster)
cancels the debounce and starts saving an unsaved value (or resends it once
after a failed save in flight) without waiting for the server: the screen
changes as soon as the old player is gone. Each save is held in
`TvPendingRatings` (`tv_card_registry.dart`) by the item's global key until it
completes; an S7/S8 card that becomes the top route while a save for its item
(the movie, or the series that ended) is held rereads once more when it
finishes, success or failure, and marks `watchStateChanged` if anything
changed. The card is usable meanwhile. Disposing the screen sends only a
value that no save is already sending. From the leaving press on, a failed
save shows no message (Plezy's messenger would show it over the next screen);
it is logged. Ratings appear as soon as the item
loads; a failed related-hubs request only leaves "Similar" out. For a series
that ended, focus may move once to the stars after loading if no key was
pressed yet (any key-down counts, seen through `HardwareKeyboard`).

R1: TV, not Live TV, not offline, not Watch Together, movie or episode, the
completion latch set, no play-next or still-watching prompt, next item not
loading, adjacency not failed, not ended by the end-of-video sleep timer, and a
normal launch: no queue, or the unshuffled queue of the item's own show or
season. Playlists, collections, library folders and shuffle keep Plezy's exit
(`tvPostPlayAllowed`, `tvNormalLaunch` in `tv_postplay_exit.dart`).

| Hook | File, place | Lookup | Fallback |
|---|---|---|---|
| H8 | `lib/screens/video_player/parts/playback_prompts.dart`, `_onVideoCompleted`: one added line after the live/transition/resolving filters, one changed line in the `exit` branch | `TvUi.playerVideoCompleted` records an end by the sleep timer (C3); `TvUi.playerExitAtEnd` takes the `exit` branch to post-play when R1 holds. It relies on the H9 layer being mounted (it holds the end binding); without it Plezy's `_handleBackButton` runs | Plezy's exit |
| H9 | `lib/screens/video_player/parts/build.dart`, one line next to H7 in the overlay stack | `TvUi.playerPostPlayExit`: `TvPostPlayExitLayer` with a `TvPlayerEndProbe` of functions read at event time (latch, prompts, next status, Watch Together, offline, `_routeExitOperation`, `_handleBackButton`) | no layer |

**Early Back handler (C4).** While the H9 layer is mounted it registers
`FocusManager.instance.addEarlyKeyEventHandler`, the only place that can stop
the focus-tree walk before Plezy's Back chain in `video_controls.dart` and the
player screen. On Back down it decides ownership for the whole press: its own
when the player is the current route, the S9 panel is hidden, no sheet or side
panel is open, the skip button is not shown (`TvSkipButton` marks itself in
`TvPlayerSession`) and R1 holds. It then swallows both down and up, acts in
Plezy's phase (`handleBackKeyAction` in `lib/focus/key_event_utils.dart`: up on
Android, down on Apple TV), calls `BackKeyCoordinator.markHandled()` and goes
to post-play. Other presses pass to Plezy unchanged; unmatched ups and ups
suppressed by `BackKeyUpSuppressor` are ignored. Home is not intercepted.

Contracts:

- **C1** `TvPostPlayArgs { watched, next, playerRemoved }` →
  `TvUi.postPlayRoute`, an opaque route that appears without an entrance
  transition (a route is see-through while it enters, and Plezy may remove the
  player under it within a frame) and fades out when left. `playerRemoved` is the future of
  Plezy's accepted exit; an error counts as removed.
- **C2** `TvUi.exitToPostPlay`: if an exit is already pending, nothing; else it
  calls Plezy's exit (`_handleBackButton`) and, only if that set
  `_routeExitOperation`, pushes the post-play route over the player. Plezy then
  stops, reports and removes only the player route (`navigator.removeRoute`)
  within its navigation budget (up to 1 s). Until then route-creating actions
  and Back on the screen wait for `playerRemoved`. Back on the screen goes
  through `handleBackKeyAction` / `BackKeyCoordinator.consumeIfHandled`.
- **C3** The sleep-timer flag lives in `TvPlayerSession` for the current item;
  any other fresh end or a new item clears it.
- **C4** the early Back handler above.
- **C5** `TvCardRegistry` (`lib/plezytv/tv_ui/tv_card_registry.dart`): S7/S8
  cards register their route and item. After `playerRemoved`, if the route
  below post-play is this item's card, post-play pops (S7 switches to the
  watched episode's season); otherwise it is replaced by the card via
  `TvUi.showDetailRoute`. Cards that launch playback defer focus and reread
  watch state and rating when on top again (R10), since `removeRoute` returns
  `null` to Plezy's result callbacks; a rating save still held in
  `TvPendingRatings` adds one more reread when it finishes.

Accepted limitations: Back from a gamepad or the companion
(`KeyEventSimulator`) walks the focus tree directly and does not reach the
early handler, so it keeps Plezy's exit (R1). Apple TV's Siri Remote Play/Pause
uses the native `play_pause` channel, as for H7, so on the post-play screen
it does not start the next episode (the fork targets Android TV); on Android TV
Play/Pause starts the next episode and does nothing on the movie screen. The upstream workflow warns when the merge
changes `playback_prompts.dart`, `build.dart`, `video_player_screen.dart`,
`key_event_utils.dart`, `playback_state_provider.dart` or
`rating_bottom_sheet.dart`.

## Settings backup (S4)

`TvSettings.backupSection` replaces Plezy's backup section on TV with export
and confirmed import tiles. Non-TV retains Plezy's file picker workflow.
`SettingsTransferService` writes `plezytv-settings.json` in the external app
storage directory, replacing the previous export. It combines Plezy's portable
settings with Show downloads and the search keyboard layout; library settings
are restored under the active profile. Import refreshes settings listeners,
library providers and Plezy's stored runtime effects without a restart.

## Вёрстка

Все размеры — design px холста 1920×1080 через `TvTheme.px` (S24 R1–R3).
Видимый левый край неактивного контента — x = 200 от края экрана:
внутри оболочки отступ равен `px(TvTokens.space.contentLeft) −
MainScreenFocusScope.foregroundLeftOf(context)`, вне оболочки — 200.
Кольца фокуса и сдвинутые подложки кнопок/вкладок могут выходить левее.
Верхнее поле — 54, правое поле статичного контента — 96; горизонтальные
ряды продолжаются за правый край.

Между секциями — `space.sectionGap` = 48 от низа подписи до следующего
заголовка. От заголовка ряда до карточки — `rowHeaderToCards` = 16 плюс
`cardFocusReserve` = 24 сверху под рост в фокусе. Промежутки шапки:
название → метаданные 12, метаданные → оценки 12, оценки → описание 16,
описание → кнопки 32.

`space.cardGap` = 28. Постер, квадрат и персона растут в фокусе в 1.05 раза,
эпизод — в 1.03 раза, от нижнего края вверх и в стороны. Кольцо толщиной 4
с отступом 3 учитывается в границах отрисовки: оно не заходит на соседнюю
карточку, заголовок или неподвижные подписи. Статусы остаются в углах и
у нижнего края карточки. Компактные шапки деталей должны иметь непрозрачный
фон `bg.base` на всю высоту (переход экранов выполняется в S24 T3).

Hero главной (S24 T2) начинается под верхним полем 54 и занимает 340,
после прокрутки — 200. Логотип ограничен 560×120, описание — двумя
строками. Метаданные фильма: год, длительность, возрастной рейтинг и до
трёх жанров; сериала: год, число сезонов, возрастной рейтинг и до трёх жанров;
эпизода: номер и название, длительность либо остаток. Недостающие описание
и жанры берутся из полных метаданных. При их загрузке место строки оценок
зарезервировано; кэшированные оценки появляются сразу.

Фоновый арт 1300×780 расположен справа сверху (x 620–1920). Горизонтальная
маска линейно раскрывает его от x 1000 до 1500, вертикальная скрывает от
y 360 до 640. Сам арт имеет непрозрачность 0.6 поверх `bg.base`; без арта
сохраняется тонированный фон. Запрос Plex для арта передаёт обе размерности
1280×720, для тонировки — 64×64 (транскодер требует высоту).

### Detail layout (S24 T3)

`TvRatings` displays at most three scores: IMDb, RT critics, RT audience, then
other attributed sources in their incoming order, with bare scores last. This
also applies to post-play; score values still come from Plezy.

Movie, show and catalog details share `TvActionRow`: a text primary action,
64×64 icon actions and 24 design-pixel gaps. Focus captions paint centered below
the icon without consuming layout space. The movie compact header uses opaque
`bg.base`. Season episode dates use `TvStrings.date` in the application locale
with an abbreviated month (`16 Sep 2026`).

### Shell and Home layout (S24 T4)

Menu rows use 64 design pixels when they fit, shrinking evenly to a minimum
of 48, including the divider in the available height. Beyond that, Settings
stays below the scroll viewport; the selected section is revealed on collapse
and focused items scroll into view on expansion. The last item retains Down.

Home and search episode cards show the series title above `S1 E3 · episode
title`; remaining time is represented by the progress bar. Home applies this
also to episodes in poster hubs. Season, player queue and post-play captions
retain their existing format. Home uses the 340/200 hero and the 48 section gap.

### Movie, show and catalog layout (S24 T5)

Detail text columns are limited to 900 design pixels. Movie and catalog genres
are plain metadata text; movie director and edition follow metadata, then scores,
technical labels, up to four summary lines and actions. Sections use the shared
48 pixel gap.

On Show, a series with exactly one season displays that season's episode rail,
using the same cards, paging, context menu and playback as its retained season
tab. Up returns to actions and restores the header; Down visits Cast and the
remaining rails in order. Multiple seasons use standard 216×324 posters.
Season tabs and rail titles use the raw season title, falling back to the
localized season number when empty or equal to the series title.

### Search, library, Watchlist and settings layout (S24 T6)

Search uses the shared 54 top and 96 right fields. The RU and EN digits key
fills the last two and three keyboard cells respectively. Focusing a result
reveals its whole horizontal row, including captions.

Library and Watchlist headers show the item count beside the title and
`Sort: <field>` on the sort button. Poster grids retain 228 pixel cards with
32 pixel gaps; whole columns fit before `letters.x - cardGap` (six posters,
or three 400 pixel episode cards). The library alphabet starts at x 1776.

The shell wraps upstream settings in `TvSettingsSection`: its group edges
start at x 200, its width is capped at 1200 and its app bar uses `bg.base`,
including when scrolled. The wrapper compensates for upstream SettingsGroup's
16 logical-pixel margin; recheck that margin on upstream changes. Settings
items, routes and nested pages remain owned by upstream.

### Acceptance refinements (S24 T7)

The compact Home hero contains only its logo/title and one metadata line; its
logo is capped at 80 design pixels. Scores and description appear in the full
hero only. Movie, show and catalog detail artwork fades linearly with page
scroll from full strength at 0 to zero at 300 design pixels; the tint remains.
Show uses the movie's opaque 150 pixel compact header and collapse threshold,
keeping focused rail headings below it. Show metadata stays on one line with
ellipsis and at most three genres.

Detail rail heights include artwork, the 20 pixel caption gap and the two
rounded text line boxes, so the next section starts exactly 48 pixels after
the caption. Search episode captions append the server name only when several
servers are connected. Collapsed menu rebuilds retain their scroll offset;
a changed current section is revealed with only the necessary movement.

### Detail scrolling and artwork layers (S24 T8)

Every focused detail rail heading aligns 24 design pixels below the compact
header, including the last rail. Movie and show pages reserve trailing viewport
space so the scroll extent permits that alignment. Movie reviews and the technical
information block use the same 48 pixel section gap, including when reviews or
related rails arrive later. Catalog details currently have no lower rails.

Artwork scroll opacity is derived from the clamped 0–300 pixel range. Only a
changed opacity notifies its layer; the masks and image remain inside a retained
repaint boundary. The tint does not fade with page scroll.
