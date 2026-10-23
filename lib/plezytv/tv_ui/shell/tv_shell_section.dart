import 'package:flutter/foundation.dart';

import '../../../navigation/navigation_tabs.dart';

/// Shared identity for menu selection, remote navigation and reconnect snapshots.
/// Libraries share one mounted screen, but each library is a distinct section.
@immutable
class TvShellSection {
  const TvShellSection.tab(this.tab) : libraryGlobalKey = null, isNoConnection = false;
  const TvShellSection.noConnection() : tab = NavigationTabId.discover, libraryGlobalKey = null, isNoConnection = true;
  const TvShellSection.library(String globalKey)
    : tab = NavigationTabId.libraries,
      libraryGlobalKey = globalKey,
      isNoConnection = false;

  // The offline root has no upstream tab; discover is only its stack placeholder.
  final bool isNoConnection;
  final NavigationTabId tab;
  final String? libraryGlobalKey;

  @override
  bool operator ==(Object other) =>
      other is TvShellSection &&
      isNoConnection == other.isNoConnection &&
      tab == other.tab &&
      libraryGlobalKey == other.libraryGlobalKey;

  @override
  int get hashCode => Object.hash(isNoConnection, tab, libraryGlobalKey);
}
