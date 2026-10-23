import 'package:flutter/foundation.dart';

import '../../../navigation/navigation_tabs.dart';

/// Shared identity for menu selection, remote navigation and reconnect snapshots.
/// Libraries share one mounted screen, but each library is a distinct section.
@immutable
class TvShellSection {
  const TvShellSection.tab(this.tab) : libraryGlobalKey = null;
  const TvShellSection.library(String globalKey) : tab = NavigationTabId.libraries, libraryGlobalKey = globalKey;

  final NavigationTabId tab;
  final String? libraryGlobalKey;

  @override
  bool operator ==(Object other) =>
      other is TvShellSection && tab == other.tab && libraryGlobalKey == other.libraryGlobalKey;

  @override
  int get hashCode => Object.hash(tab, libraryGlobalKey);
}
