import 'dart:async';

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
  final CatalogItem item;
  final bool refresh;
  _Job(this.item, this.refresh);
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
  final List<_Job> _queue = [];
  final Set<String> _inFlight = {};
  final Map<String, int> _generation = {};
  Map<String, CatalogItem> _items = {};
  Set<String> _expected = {};
  Set<String> _online = {};
  bool _disposed = false;

  TvWatchlistAvailability(this._matcher, this._multiServer, {DateTime Function()? now}) : _now = now ?? DateTime.now {
    _expected = _multiServer.expectedServerIds.toSet();
    _online = _multiServer.onlineServerIds.toSet();
    _multiServer.addListener(_onServersChanged);
  }

  static String keyOf(CatalogItem item) => '${item.source.name}/${item.entryIdentityKey}';

  TvAvailability statusOf(CatalogItem item) => _known[keyOf(item)]?.status ?? TvAvailability.pending;

  /// Whether any item is queued or being checked (R9).
  bool get checking => _queue.isNotEmpty || _inFlight.isNotEmpty;

  /// Replaces the full list. Known results are kept; unknown items are queued.
  void setItems(List<CatalogItem> items) {
    if (_disposed) return;
    final wasChecking = checking;
    _items = {for (final item in items) keyOf(item): item};
    final queued = {for (final job in _queue) keyOf(job.item): job};
    _queue.clear();
    for (final MapEntry(:key, :value) in _items.entries) {
      final existing = queued[key];
      if (existing != null) {
        _queue.add(_Job(value, existing.refresh));
      } else if (!_known.containsKey(key) && !_inFlight.contains(key)) {
        _queue.add(_Job(value, false));
      }
    }
    _pump();
    if (wasChecking != checking) notifyListeners();
  }

  /// Moves [items] that are still queued to the front, in the given order.
  void prioritize(Iterable<CatalogItem> items) {
    if (_disposed) return;
    final front = <_Job>[];
    for (final item in items) {
      final key = keyOf(item);
      final index = _queue.indexWhere((job) => keyOf(job.item) == key);
      if (index >= 0) front.add(_queue.removeAt(index));
    }
    _queue.insertAll(0, front);
  }

  /// Re-asks `notFound` results older than [notFoundRecheckAge] (R8).
  void sectionOpened() {
    if (_disposed) return;
    final now = _now();
    _enqueueWhere(
      (known) => known.status is TvAvailabilityNotFound && now.difference(known.at) >= notFoundRecheckAge,
      refresh: false,
    );
  }

  /// Card check: the known result, or a check outside the queue. [enriched]
  /// is checked too and its copies merge in; [retry] re-asks servers that
  /// did not answer last time.
  Future<TvAvailability> check(CatalogItem item, {CatalogItem? enriched, bool retry = false}) async {
    final key = keyOf(item);
    final known = _known[key];
    if (!retry && enriched == null && known != null) return known.status;
    final generation = _bump(key);
    _queue.removeWhere((job) => keyOf(job.item) == key);
    final forms = [item, ?enriched];
    final waves = await Future.wait(forms.map((form) => _match(form, retry)));
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
    if (!_disposed && _generation[key] == generation) {
      _known[key] = _Known(status, _now());
      notifyListeners();
    }
    return status;
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    _multiServer.removeListener(_onServersChanged);
    super.dispose();
  }

  void _onServersChanged() {
    if (_disposed) return;
    final expected = _multiServer.expectedServerIds.toSet();
    final online = _multiServer.onlineServerIds.toSet();
    final changed = !setEquals(expected, _expected) || online.difference(_online).isNotEmpty;
    _expected = expected;
    _online = online;
    if (!changed) return;
    _enqueueWhere(
      (known) =>
          known.status is TvAvailabilityUnchecked ||
          (known.status is TvAvailabilityFound && !(known.status as TvAvailabilityFound).complete),
      refresh: true,
    );
  }

  void _enqueueWhere(bool Function(_Known) test, {required bool refresh}) {
    final wasChecking = checking;
    final queued = {for (final job in _queue) keyOf(job.item)};
    for (final MapEntry(:key, :value) in _items.entries) {
      final known = _known[key];
      if (known == null || !test(known) || queued.contains(key) || _inFlight.contains(key)) continue;
      _queue.add(_Job(value, refresh));
    }
    _pump();
    if (wasChecking != checking) notifyListeners();
  }

  int _bump(String key) => _generation[key] = (_generation[key] ?? 0) + 1;

  void _pump() {
    while (!_disposed && _inFlight.length < maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      final key = keyOf(job.item);
      _inFlight.add(key);
      unawaited(_run(job, key, _bump(key)));
    }
  }

  Future<void> _run(_Job job, String key, int generation) async {
    final wave = await _match(job.item, job.refresh);
    if (_disposed) return;
    _inFlight.remove(key);
    if (_generation[key] == generation) {
      _known[key] = _Known(
        wave == null ? TvAvailability.unchecked : _statusFrom(wave.items, _isComplete(wave)),
        _now(),
      );
    }
    _pump();
    notifyListeners();
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
