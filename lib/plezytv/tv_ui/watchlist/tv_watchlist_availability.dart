import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../media/media_item.dart';
import '../../../media/media_item_merge.dart';
import '../../../models/catalog/catalog_item.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../services/catalog/catalog_library_matcher.dart';
import '../../../services/data_aggregation_service.dart';

/// Whether a watchlist item has a copy on the user's servers.
sealed class TvAvailability {
  const TvAvailability();

  /// Never checked yet, or its first check is running.
  static const TvAvailability pending = TvAvailabilityPending._();
  static const TvAvailability notFound = TvAvailabilityNotFound._();
  static const TvAvailability unchecked = TvAvailabilityUnchecked._();
  const factory TvAvailability.found(List<MediaItem> copies, {bool complete}) = TvAvailabilityFound;
}

final class TvAvailabilityPending extends TvAvailability {
  const TvAvailabilityPending._();
}

/// Every expected server answered and none holds a copy.
final class TvAvailabilityNotFound extends TvAvailability {
  const TvAvailabilityNotFound._();
}

/// No copy known and some server did not answer (or the check failed).
final class TvAvailabilityUnchecked extends TvAvailability {
  const TvAvailabilityUnchecked._();
}

/// At least one copy; [complete] is false while some server has not answered.
final class TvAvailabilityFound extends TvAvailability {
  final List<MediaItem> copies;
  final bool complete;
  const TvAvailabilityFound(this.copies, {this.complete = true});
}

class _Job {
  final String key;
  final CatalogItem item;
  final bool refresh;
  _Job(this.key, this.item, this.refresh);
}

class _Known {
  final TvAvailability status;
  final DateTime at;
  _Known(this.status, this.at);
}

/// Background library-presence checks for the watchlist screen (S10, C2).
///
/// One per mounted screen, shared by every source: keys carry the source.
class TvWatchlistAvailability extends ChangeNotifier {
  /// Concurrent queued checks; each fans out to every server.
  static const int maxConcurrent = 3;

  /// A `notFound` older than this is re-asked when the section opens (R8).
  static const Duration notFoundRecheckAge = Duration(minutes: 10);

  final CatalogLibraryMatcher _matcher;
  final MultiServerProvider _multiServer;
  final DateTime Function() _now;

  final Map<String, _Known> _known = {};

  /// Queued checks in run order, keyed by item key.
  final LinkedHashMap<String, _Job> _queue = LinkedHashMap();

  /// Running queued checks: key → the generation they started with.
  final Map<String, int> _inFlight = {};
  final Map<String, int> _generation = {};

  /// Running card checks: key → the generation they started with.
  final Map<String, int> _cardChecks = {};

  /// Checks running when the expected servers changed: queued again after
  /// they finish, whatever they answer (R8).
  final Set<String> _recheckAlways = {};

  /// Checks running when a server came online: queued again once with
  /// `refreshIncomplete` if they finish incomplete (R8).
  final Set<String> _recheckIfIncomplete = {};

  /// Last prioritized keys, kept across [setItems] (visible range first).
  List<String> _priority = const [];
  final Map<String, ValueNotifier<TvAvailability>> _watchers = {};
  Map<String, CatalogItem> _items = {};
  Set<String> _expected = {};
  Set<String> _online = {};
  int _foundRevision = 0;
  bool _disposed = false;

  TvWatchlistAvailability(this._matcher, this._multiServer, {DateTime Function()? now}) : _now = now ?? DateTime.now {
    _expected = _multiServer.expectedServerIds.toSet();
    _online = _multiServer.onlineServerIds.toSet();
    _multiServer.addListener(_onServersChanged);
  }

  static final Expando<String> _keys = Expando('TvWatchlistAvailability.key');

  /// Item identity; computed once per item instance.
  static String keyOf(CatalogItem item) => _keys[item] ??= '${item.source.name}/${item.entryIdentityKey}';

  TvAvailability statusOf(CatalogItem item) => _known[keyOf(item)]?.status ?? TvAvailability.pending;

  /// Notifies only when [item]'s own status changes (poster badges).
  ValueListenable<TvAvailability> watch(CatalogItem item) {
    final key = keyOf(item);
    return _watchers[key] ??= ValueNotifier(_known[key]?.status ?? TvAvailability.pending);
  }

  /// Bumped when an item becomes or stops being [TvAvailabilityFound]; the
  /// «Есть на сервере» tab rebuilds only then.
  int get foundRevision => _foundRevision;

  /// Whether any item is queued or being checked (R9).
  bool get checking => _queue.isNotEmpty || _inFlight.isNotEmpty;

  /// Replaces the full list. Known results are kept; unknown items are
  /// queued; the last prioritized items stay at the front.
  void setItems(List<CatalogItem> items) {
    if (_disposed) return;
    final wasChecking = checking;
    _items = {for (final item in items) keyOf(item): item};
    final previous = Map.of(_queue);
    _queue.clear();
    void add(String key, CatalogItem item) {
      if (_queue.containsKey(key)) return;
      final existing = previous[key];
      if (existing != null) {
        _queue[key] = _Job(key, item, existing.refresh);
      } else if (!_known.containsKey(key) && !_inFlight.containsKey(key) && !_cardChecks.containsKey(key)) {
        _queue[key] = _Job(key, item, false);
      }
    }

    for (final key in _priority) {
      if (_items[key] case final item?) add(key, item);
    }
    for (final MapEntry(:key, :value) in _items.entries) {
      add(key, value);
    }
    _pump();
    if (wasChecking != checking) notifyListeners();
  }

  /// Moves [items] that are still queued to the front, in the given order.
  void prioritize(Iterable<CatalogItem> items) {
    if (_disposed) return;
    _priority = [for (final item in items) keyOf(item)];
    final front = <String, _Job>{};
    for (final key in _priority) {
      final job = _queue.remove(key);
      if (job != null) front[key] = job;
    }
    if (front.isEmpty) return;
    final rest = Map.of(_queue);
    _queue
      ..clear()
      ..addAll(front)
      ..addAll(rest);
  }

  /// Re-asks `notFound` results older than [notFoundRecheckAge] (R8).
  void sectionOpened() {
    if (_disposed) return;
    final now = _now();
    _enqueueWhere(
      (known) =>
          known != null && known.status is TvAvailabilityNotFound && now.difference(known.at) >= notFoundRecheckAge,
      refresh: false,
    );
  }

  /// Profile reset: forget every result, the queue and running checks.
  void reset() {
    if (_disposed) return;
    for (final key in _inFlight.keys) {
      _bump(key);
    }
    for (final key in _cardChecks.keys) {
      _bump(key);
    }
    _inFlight.clear();
    _cardChecks.clear();
    _queue.clear();
    _recheckAlways.clear();
    _recheckIfIncomplete.clear();
    _priority = const [];
    _items = {};
    final hadFound = _known.values.any((known) => known.status is TvAvailabilityFound);
    _known.clear();
    for (final watcher in _watchers.values) {
      watcher.value = TvAvailability.pending;
    }
    if (hadFound) _foundRevision++;
    notifyListeners();
  }

  /// Card check: the known result, or a check outside the queue. [enriched]
  /// is checked too and its copies merge in; [retry] re-asks servers that
  /// did not answer last time.
  Future<TvAvailability> check(CatalogItem item, {CatalogItem? enriched, bool retry = false}) async {
    final key = keyOf(item);
    final known = _known[key];
    if (!retry && enriched == null && known != null) return known.status;
    final generation = _bump(key);
    _cardChecks[key] = generation;
    // A replaced refresh job's requirement carries over (R8).
    final refresh = retry || (_queue.remove(key)?.refresh ?? false);
    final forms = [item, ?enriched];
    final waves = await Future.wait(forms.map((form) => _match(form, refresh)));
    var copies = <MediaItem>[];
    var complete = true;
    for (final wave in waves) {
      if (wave == null) {
        complete = false;
        continue;
      }
      copies = mergeLibraryCopies(copies, wave.items);
      complete = complete && _isComplete(wave);
    }
    final status = _statusFrom(copies, complete);
    if (_cardChecks[key] == generation) _cardChecks.remove(key);
    if (!_disposed && _generation[key] == generation) {
      _record(key, status);
      _recheckIfNeeded(key, status);
      _pump();
      notifyListeners();
    }
    return status;
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    _multiServer.removeListener(_onServersChanged);
    for (final watcher in _watchers.values) {
      watcher.dispose();
    }
    super.dispose();
  }

  void _record(String key, TvAvailability status) {
    final wasFound = _known[key]?.status is TvAvailabilityFound;
    _known[key] = _Known(status, _now());
    if (wasFound != status is TvAvailabilityFound) _foundRevision++;
    _watchers[key]?.value = status;
  }

  static bool _incomplete(TvAvailability status) =>
      status is TvAvailabilityUnchecked || (status is TvAvailabilityFound && !status.complete);

  void _onServersChanged() {
    if (_disposed) return;
    final expected = _multiServer.expectedServerIds.toSet();
    final online = _multiServer.onlineServerIds.toSet();
    final expectedChanged = !setEquals(expected, _expected);
    final cameOnline = online.difference(_online).isNotEmpty;
    _expected = expected;
    _online = online;
    if (expectedChanged) {
      // Every item: copies of a removed server disappear when the new
      // result replaces the old one, which stays visible meanwhile.
      _recheckAlways.addAll([..._inFlight.keys, ..._cardChecks.keys]);
      _enqueueWhere((_) => true, refresh: true);
    } else if (cameOnline) {
      _recheckIfIncomplete.addAll([..._inFlight.keys, ..._cardChecks.keys]);
      _enqueueWhere((known) => known != null && _incomplete(known.status), refresh: true);
    }
  }

  void _enqueueWhere(bool Function(_Known?) test, {required bool refresh}) {
    final wasChecking = checking;
    for (final MapEntry(:key, :value) in _items.entries) {
      if (_queue.containsKey(key) || _inFlight.containsKey(key) || _cardChecks.containsKey(key) || !test(_known[key])) {
        continue;
      }
      _queue[key] = _Job(key, value, refresh);
    }
    _pump();
    if (wasChecking != checking) notifyListeners();
  }

  int _bump(String key) => _generation[key] = (_generation[key] ?? 0) + 1;

  void _pump() {
    while (!_disposed && _inFlight.length < maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.remove(_queue.keys.first)!;
      final generation = _bump(job.key);
      _inFlight[job.key] = generation;
      unawaited(_run(job, generation));
    }
  }

  Future<void> _run(_Job job, int generation) async {
    final key = job.key;
    final wave = await _match(job.item, job.refresh);
    if (_disposed) return;
    if (_inFlight[key] == generation) _inFlight.remove(key);
    if (_generation[key] != generation) {
      // Superseded by a card check or a reset; free the slot. Re-check
      // flags stay for the newer check, which consumes them (R8).
      _pump();
      notifyListeners();
      return;
    }
    final status = wave == null ? TvAvailability.unchecked : _statusFrom(wave.items, _isComplete(wave));
    _record(key, status);
    _recheckIfNeeded(key, status);
    _pump();
    notifyListeners();
  }

  /// Consumes [key]'s re-check flags for a finished current check.
  void _recheckIfNeeded(String key, TvAvailability status) {
    final always = _recheckAlways.remove(key);
    final ifIncomplete = _recheckIfIncomplete.remove(key);
    final item = _items[key];
    if (item != null && !_queue.containsKey(key) && (always || (ifIncomplete && _incomplete(status)))) {
      _queue[key] = _Job(key, item, true);
    }
  }

  Future<LibraryLookupResult?> _match(CatalogItem item, bool refresh) async {
    try {
      return await _matcher.match(item, refreshIncomplete: refresh);
    } catch (_) {
      return null;
    }
  }

  static bool _isComplete(LibraryLookupResult wave) =>
      wave.failedServerIds.isEmpty && wave.cancelledServerIds.isEmpty && wave.unqueriedServerIds.isEmpty;

  static TvAvailability _statusFrom(List<MediaItem> copies, bool complete) {
    if (copies.isNotEmpty) return TvAvailability.found(copies, complete: complete);
    return complete ? TvAvailability.notFound : TvAvailability.unchecked;
  }
}
