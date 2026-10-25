import 'dart:async';

import 'package:flutter/widgets.dart';

/// A TV detail card (S7/S8) registered on its route (S14 C5).
class TvCardEntry {
  const TvCardEntry({required this.itemKey, this.showSeason});

  /// The card item's global key (`serverId:id`).
  final String itemKey;

  /// S7 only: switches the card to [seasonId] for when it is on top again.
  final void Function(String seasonId)? showSeason;
}

/// Maps routes to the TV detail card they show (S14 C5).
abstract final class TvCardRegistry {
  static Expando<TvCardEntry> _entries = Expando<TvCardEntry>('TV cards');

  static void register(Route<dynamic> route, TvCardEntry entry) => _entries[route] = entry;

  /// Removes [entry] if it is still the one registered for [route].
  static void unregister(Route<dynamic> route, TvCardEntry entry) {
    if (identical(_entries[route], entry)) _entries[route] = null;
  }

  static TvCardEntry? of(Route<dynamic>? route) => route == null ? null : _entries[route];

  @visibleForTesting
  static void resetForTesting() => _entries = Expando<TvCardEntry>('TV cards');
}

/// "Your rating" saves from the post-play screen still running, by the item's
/// global key (S14 R6, R10). Leaving post-play does not wait for the server;
/// the card of that item rereads once the save has finished.
abstract final class TvPendingRatings {
  static final _saves = <String, Future<void>>{};

  /// The latest save for [itemKey] still running; never completes with an error.
  static Future<void>? of(String itemKey) => _saves[itemKey];

  /// Holds [save] for [itemKey] until it completes (success or failure).
  static void track(String itemKey, Future<void> save) {
    final tracked = save.then<void>((_) {}, onError: (Object _) {});
    _saves[itemKey] = tracked;
    unawaited(
      tracked.whenComplete(() {
        if (identical(_saves[itemKey], tracked)) _saves.remove(itemKey);
      }),
    );
  }

  /// Calls [reread] once no save for [itemKey] is running any more, if one is
  /// running now; [isCurrent] tells whether the caller still wants it. Saves
  /// queued meanwhile are waited for too. Returns the awaited save, or null.
  static Future<void>? whenSaved(String itemKey, {required bool Function() isCurrent, required VoidCallback reread}) {
    final save = of(itemKey);
    if (save == null) return null;
    unawaited(
      save.then((_) {
        if (!isCurrent()) return;
        if (whenSaved(itemKey, isCurrent: isCurrent, reread: reread) == null) reread();
      }),
    );
    return save;
  }

  @visibleForTesting
  static int get pendingCount => _saves.length;

  @visibleForTesting
  static void resetForTesting() => _saves.clear();
}
