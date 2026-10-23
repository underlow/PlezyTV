import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show rootNavigatorKey;
import '../../media/ids.dart';
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
      ScreenTarget.item: _resolve,
      ScreenTarget.update: (link, current) => throw StateError('update unavailable'),
    };
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

  bool _isReady() =>
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
    final provider = context.read<MultiServerProvider>();
    if (!provider.hasConnectedServers) throw const ScreenLinkNotReady();
    _ensureVisible(NavigationTabId.libraries);
    final loadedLibraries = link.target == ScreenTarget.library ? context.read<LibrariesProvider>() : null;
    if (loadedLibraries != null && loadedLibraries.isLoading) {
      throw const ScreenLinkNotReady();
    }
    final ids = provider.onlineServerIds;
    if (link.server != null && !ids.contains(link.server)) throw StateError('unknown server ${link.server}');
    final candidates = link.server == null ? ids : [link.server!];
    Object? lastError;
    for (final id in candidates) {
      final client = provider.getClientForServer(ServerId(id));
      if (client == null) continue;
      try {
        if (link.target == ScreenTarget.library) {
          final libraries = await client.fetchLibraries();
          final library = libraries.where((value) => value.id == link.id).firstOrNull;
          if (!context.mounted) throw const ScreenLinkNotReady();
          if (!isCurrent()) return;
          if (!identical(owner, _receiver.navigationOwner)) throw const ScreenLinkNotReady();
          if (library == null) continue;
          // Use the main screen’s public sidebar selection contract. The
          // scope is below MainScreen’s State context, so locate that scope
          // within this owner only (never another profile or navigator).
          final select = _librarySelector(context);
          if (select == null) throw StateError('library selection unavailable');
          if (!loadedLibraries!.libraries.any((value) => value.globalKey == library.globalKey)) {
            throw StateError('library ${link.id} unavailable in active profile');
          }
          _showMain();
          select(library.globalKey);
          return;
        }
        final item = await client.fetchItem(link.id!);
        if (!context.mounted) throw const ScreenLinkNotReady();
        if (!isCurrent()) return;
        if (!identical(owner, _receiver.navigationOwner)) throw const ScreenLinkNotReady();
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
        lastError = error;
      }
    }
    throw StateError('${link.target.name} ${link.id} not found${lastError == null ? '' : ': $lastError'}');
  }
}
