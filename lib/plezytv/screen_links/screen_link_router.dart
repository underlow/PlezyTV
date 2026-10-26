import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../services/settings_export_service.dart';
import '../settings_transfer/settings_transfer_service.dart';
import '../../media/library_query.dart';
import '../../media/media_filter.dart';
import '../../services/plex_client.dart';
import '../tv_ui/library/tv_library_query.dart';
import '../tv_ui/library/tv_library_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show rootNavigatorKey;
import '../../media/ids.dart';
import '../../profiles/active_profile_provider.dart';
import '../../screens/profile/profile_switch_screen.dart';
import '../../media/media_kind.dart';
import '../../media/media_item.dart';
import '../../navigation/navigation_tabs.dart';
import '../../navigation/main_screen_scope.dart';
import '../../navigation/profile_navigation_scope.dart';
import '../../providers/libraries_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/offline_mode_provider.dart';
import '../../services/companion_remote/companion_remote_receiver.dart';
import '../../utils/app_logger.dart';
import '../../utils/media_navigation_helper.dart';
import '../update/updater.dart';
import '../update/startup_trigger.dart';
import 'screen_link.dart';
import 'screen_link_queue.dart';

typedef ScreenLinkHandler = FutureOr<void> Function(ScreenLink link, bool Function() isCurrent);

class ScreenLinkRouter {
  ScreenLinkRouter._() {
    queue = ScreenLinkQueue(
      isReady: _isReady,
      dispatch: (link, isCurrent) async => await handlers[link.target]!(link, isCurrent),
      warn: (link, reason) => appLogger.w('Screen link $link: $reason'),
    );
    handlers = {
      ScreenTarget.settingsExport: _transfer,
      ScreenTarget.settingsImport: _transfer,
      ScreenTarget.home: (link, current) => _tab(link, _receiver.onHome),
      ScreenTarget.libraries: (link, current) => _tab(link, _receiver.onTabLibraries, NavigationTabId.libraries),
      ScreenTarget.search: (link, current) => _tab(
        link,
        link.query == null ? _receiver.onTabSearch : () => _receiver.onSearchAction?.call(link.query),
        NavigationTabId.search,
      ),
      ScreenTarget.downloads: (link, current) => _tab(link, _receiver.onTabDownloads, NavigationTabId.downloads),
      ScreenTarget.settings: (link, current) => _tab(link, _receiver.onTabSettings, NavigationTabId.settings),
      ScreenTarget.library: _resolve,
      ScreenTarget.libraryFilter: _resolve,
      ScreenTarget.item: _resolve,
      ScreenTarget.update: (link, current) {
        (updaterOverride ?? PlezyTvUpdater.instance).checkFromLink(() => _context, current);
      },
    };
    startUpdates();
  }

  @visibleForTesting
  PlezyTvUpdater? updaterOverride;

  @visibleForTesting
  SettingsTransferService? transferOverride;

  Future<void> _transfer(ScreenLink link, bool Function() isCurrent) async {
    final context = _context!;
    final service = transferOverride ?? const SettingsTransferService();
    final action = link.target == ScreenTarget.settingsExport ? 'export' : 'import';
    String message;
    try {
      if (action == 'export') {
        final path = await service.exportToFile();
        final data = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
        message = 'Settings export: ${(data['prefs'] as Map).length} keys, $path';
      } else {
        final result = await service.importAndApply(context);
        message = 'Settings import: ${result.keysImported} keys imported, ${result.keysSkipped} skipped';
      }
      appLogger.i(message);
    } catch (error) {
      message = 'Settings $action failed: ${error is SettingsExportException ? error.message : error}';
      appLogger.w(message);
    }
    final currentContext = _context;
    if (isCurrent() && currentContext != null && currentContext.mounted) {
      ScaffoldMessenger.maybeOf(currentContext)?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  final _resolutions = Expando<_Resolution>();
  UpdateStartupTrigger? _updateTrigger;
  void startUpdates() {
    _updateTrigger ??= UpdateStartupTrigger(
      enabled: PlezyTvUpdater.enabled,
      isReady: _isReady,
      fire: () => PlezyTvUpdater.instance.ready(() => _isReady() ? _context : null),
    );
  }

  static final instance = ScreenLinkRouter._();
  late final ScreenLinkQueue queue;

  /// Stable target table: later fork screens/updater can replace a handler.
  late final Map<ScreenTarget, ScreenLinkHandler> handlers;
  CompanionRemoteReceiver get _receiver => CompanionRemoteReceiver.instance;
  BuildContext? get _context {
    final owner = _receiver.navigationOwner;
    return owner is State && owner.mounted ? owner.context : null;
  }

  bool _profileReady() {
    final context = _context;
    if (context == null) return false;
    final profile = context.read<ActiveProfileProvider?>();
    if (profile != null && (!profile.isInitialized || profile.activeId == null || profile.isBinding)) return false;
    var picker = false;
    void visit(Element element) {
      if (element.widget is ProfileSwitchScreen) picker = true;
      element.visitChildren(visit);
    }

    rootNavigatorKey.currentContext?.visitChildElements(visit);
    return !picker;
  }

  bool _isReady() =>
      _profileReady() &&
      rootNavigatorKey.currentState != null &&
      profileNavigationRegistry.navigator != null &&
      _context != null &&
      _receiver.onHome != null &&
      _receiver.onTabSettings != null;

  bool claim(String source) => queue.claim(source);

  void _ensureVisible(NavigationTabId tab) {
    final context = _context!;
    final offline = context.read<OfflineModeProvider>().isOffline;
    if (!NavigationTab.getVisibleTabs(isOffline: offline).any((value) => value.id == tab)) {
      throw StateError('target tab ${tab.name} not visible');
    }
  }

  void _showMain() {
    // Dismiss details/player routes before invoking callbacks on the main tab.
    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    profileNavigationRegistry.navigator?.popUntil((route) => route.isFirst);
  }

  void _tab(ScreenLink link, VoidCallback? callback, [NavigationTabId? tab]) {
    if (tab != null) _ensureVisible(tab);
    if (callback == null) throw StateError('target ${link.target.name} unavailable');
    _showMain();
    callback();
  }

  void Function(String)? _librarySelector(BuildContext context) {
    void Function(String)? select;
    void visit(Element element) {
      if (select != null) return;
      final widget = element.widget;
      if (widget is MainScreenFocusScope) {
        select = widget.selectLibrary;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return select;
  }

  void _openItem(ScreenLink link, MediaItem item) {
    final context = profileNavigationRegistry.navigator!.overlay!.context;
    unawaited(
      navigateToMediaItemDetails(context, item).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) => appLogger.w('Screen link ${link.source}: $error'),
      ),
    );
  }

  Future<void> _resolve(ScreenLink link, bool Function() isCurrent) async {
    final context = _context!;
    final owner = _receiver.navigationOwner;
    final profile = context.read<ActiveProfileProvider?>();
    final profileId = profile?.activeId;
    bool ownsRequest() =>
        context.mounted && identical(owner, _receiver.navigationOwner) && profileId == profile?.activeId && _isReady();
    final provider = context.read<MultiServerProvider>();
    if (!provider.hasConnectedServers) throw const ScreenLinkNotReady();
    _ensureVisible(NavigationTabId.libraries);
    final loadedLibraries = (link.target == ScreenTarget.library || link.target == ScreenTarget.libraryFilter)
        ? context.read<LibrariesProvider>()
        : null;
    if (loadedLibraries != null &&
        (loadedLibraries.isLoading ||
            // The provider exposes its initial state only through this getter.
            // ignore: invalid_use_of_visible_for_testing_member
            loadedLibraries.loadState == LibrariesLoadState.initial)) {
      throw const ScreenLinkNotReady();
    }
    final ids = provider.onlineServerIds;
    if (link.server != null && !ids.contains(link.server)) {
      if (provider.expectedServerIds.contains(link.server)) throw const ScreenLinkNotReady();
      throw StateError('unknown server ${link.server}');
    }
    var resolution = _resolutions[link];
    if (resolution == null ||
        !identical(resolution.owner, owner) ||
        resolution.profileId != profileId ||
        !identical(resolution.provider, provider)) {
      resolution = _Resolution(owner, profileId, provider);
      _resolutions[link] = resolution;
    }
    final candidates = link.server == null ? {...ids, ...provider.expectedServerIds} : {link.server!};
    Object? lastError;
    for (final id in candidates) {
      if (resolution.answered.contains(id) || !ids.contains(id)) continue;
      final client = provider.getClientForServer(ServerId(id));
      if (client == null) continue;
      try {
        if (link.target == ScreenTarget.library || link.target == ScreenTarget.libraryFilter) {
          final libraries = await client.fetchLibraries();
          final library = libraries.where((value) => value.id == link.id).firstOrNull;
          if (!context.mounted) throw const ScreenLinkNotReady();
          if (!isCurrent()) return;
          if (!ownsRequest()) throw const ScreenLinkNotReady();
          if (loadedLibraries!.isLoading) throw const ScreenLinkNotReady();
          if (library == null) {
            resolution.answered.add(id);
            continue;
          }
          if (link.target == ScreenTarget.libraryFilter) {
            if (!isTvVideoLibrary(library)) throw StateError('not a video library');
            final filters = await client.fetchLibraryFiltersWithValues(library.id, libraryKind: library.kind);
            if (!isCurrent()) return;
            if (!ownsRequest()) throw const ScreenLinkNotReady();
            final field = filters.filters.where((f) => f.filter == link.field).firstOrNull;
            if (field == null) throw StateError('unknown filter field ${link.field}');
            final values =
                filters.cachedValues[field.filter] ??
                (client is PlexClient && field.key.isNotEmpty
                    ? await client.getFilterValues(field.key)
                    : <MediaFilterValue>[]);
            if (!isCurrent()) return;
            if (!ownsRequest()) throw const ScreenLinkNotReady();
            final valueId = libraryFilterValueId(link.value!, field.filter);
            if (!values.any((v) => libraryFilterValueId(v.key, field.filter) == valueId)) {
              throw StateError('unknown filter value ${link.value}');
            }
            unawaited(
              profileNavigationRegistry.navigator!.push<void>(
                MaterialPageRoute(
                  builder: (_) => TvLibraryScreen.filtered(
                    library: library,
                    client: client,
                    filter: LibraryFilter(field: field.filter, values: [valueId]),
                  ),
                ),
              ),
            );
            return;
          }
          if (!loadedLibraries.libraries.any((value) => value.globalKey == library.globalKey)) {
            // Delta loads keep isLoading false. Join the provider’s coalesced
            // merge before deciding that a server library is unavailable.
            await loadedLibraries.syncToOnlineServers({id});
            if (!context.mounted) throw const ScreenLinkNotReady();
            if (!isCurrent()) return;
            if (!ownsRequest()) throw const ScreenLinkNotReady();
          }
          // Use the main screen’s public sidebar selection contract. The
          // scope is below MainScreen’s State context, so locate that scope
          // within this owner only (never another profile or navigator).
          if (!context.mounted) throw const ScreenLinkNotReady();
          final select = _librarySelector(context);
          if (select == null) throw StateError('library selection unavailable');
          if (!loadedLibraries.libraries.any((value) => value.globalKey == library.globalKey)) {
            throw StateError('library ${link.id} unavailable in active profile');
          }
          _showMain();
          select(library.globalKey);
          return;
        }
        final item = await client.fetchItem(link.id!);
        if (!context.mounted) throw const ScreenLinkNotReady();
        if (!isCurrent()) return;
        if (!ownsRequest()) throw const ScreenLinkNotReady();
        resolution.answered.add(id);
        if (item == null) continue;
        if (!const [MediaKind.movie, MediaKind.show, MediaKind.season, MediaKind.episode].contains(item.kind)) {
          throw StateError('unsupported item kind ${item.kind.name}');
        }
        _showMain();
        _openItem(link, item);
        return;
      } on ScreenLinkNotReady {
        rethrow;
      } catch (error) {
        if (!isCurrent()) return;
        if (!ownsRequest()) {
          throw const ScreenLinkNotReady();
        }
        resolution.answered.add(id);
        lastError = error;
      }
    }
    if (candidates.any((id) => !resolution!.answered.contains(id))) throw const ScreenLinkNotReady();
    if (link.target == ScreenTarget.library && lastError == null) {
      _tab(link, _receiver.onTabLibraries, NavigationTabId.libraries);
      return;
    }
    throw StateError('${link.target.name} ${link.id} not found${lastError == null ? '' : ': $lastError'}');
  }
}

// Answers belong to one pending link and profile owner, not to the timer tick.
// Expando releases them when the queue releases the link.
class _Resolution {
  _Resolution(this.owner, this.profileId, this.provider);
  final Object? owner;
  final String? profileId;
  final MultiServerProvider provider;
  final answered = <String>{};
}
