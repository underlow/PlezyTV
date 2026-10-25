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
