import 'package:flutter/foundation.dart';

import '../../../navigation/navigation_tabs.dart';

/// Shared identity for menu selection, remote navigation and reconnect snapshots.
/// Libraries share one mounted screen, but each library is a distinct section.
@immutable
class TvShellSection {
  const TvShellSection.tab(NavigationTabId this.tab)
    : libraryGlobalKey = null,
      isNoConnection = false,
      isWatchlist = false;
  const TvShellSection.noConnection() : tab = null, libraryGlobalKey = null, isNoConnection = true, isWatchlist = false;
  const TvShellSection.library(String globalKey)
    : tab = NavigationTabId.libraries,
      libraryGlobalKey = globalKey,
      isNoConnection = false,
      isWatchlist = false;

  /// The fork-owned «Список» (S10); it has no upstream tab.
  const TvShellSection.watchlist() : tab = null, libraryGlobalKey = null, isNoConnection = false, isWatchlist = true;

  /// Mounted-screen slot of the watchlist (tabs use their [NavigationTabId]).
  static const Object watchlistSlot = #watchlist;

  final bool isNoConnection;
  final bool isWatchlist;

  /// Upstream tab; null for the offline root and the watchlist.
  final NavigationTabId? tab;
  final String? libraryGlobalKey;

  /// Mounted screen identity: a [NavigationTabId], [watchlistSlot], or null offline.
  Object? get slot => isWatchlist ? watchlistSlot : tab;

  @override
  bool operator ==(Object other) =>
      other is TvShellSection &&
      isNoConnection == other.isNoConnection &&
      isWatchlist == other.isWatchlist &&
      tab == other.tab &&
      libraryGlobalKey == other.libraryGlobalKey;

  @override
  int get hashCode => Object.hash(isNoConnection, isWatchlist, tab, libraryGlobalKey);
}
