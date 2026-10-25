import 'package:flutter/foundation.dart';

class TvPage<T> {
  const TvPage(this.items, this.totalCount);
  final List<T> items;
  final int totalCount;
}

/// Sparse cache; structural and per-page notifications are independent.
class TvPagedSource<T> extends ChangeNotifier {
  TvPagedSource({required this.loadPage, this.pageSize = 60}) : assert(pageSize > 0);
  final Future<TvPage<T>> Function(int offset, int limit) loadPage;
  final int pageSize;
  int? totalCount;
  int generation = 0;
  bool _disposed = false;
  final _items = <int, T>{};
  final _loaded = <int>{}, _stale = <int>{};
  final _pending = <int, Future<void>>{};
  final _signals = <int, ChangeNotifier>{};
  final errors = <int, Object>{};
  T? operator [](int index) => _items[index];
  Listenable pageListenable(int index) => _signals.putIfAbsent(index ~/ pageSize, ChangeNotifier.new);
  void _emit(int page) => _signals[page]?.notifyListeners();

  Future<void> requestIndex(int index) {
    if (_disposed || index < 0 || (totalCount != null && index >= totalCount!)) return Future.value();
    final page = index ~/ pageSize;
    if (_pending[page] case final task?) return task;
    if (_loaded.contains(page) && !_stale.contains(page)) return Future.value();
    return _pending[page] = _load(page, generation);
  }

  Future<void> _load(int page, int epoch) async {
    try {
      final result = await Future.sync(() => loadPage(page * pageSize, pageSize));
      if (_disposed || epoch != generation) return;
      final changed = totalCount != result.totalCount;
      totalCount = result.totalCount;
      final start = page * pageSize;
      _items.removeWhere((i, _) => i >= totalCount! || (i >= start && i < start + pageSize));
      for (var i = 0; i < result.items.length && start + i < totalCount!; i++) {
        _items[start + i] = result.items[i];
      }
      _loaded.add(page);
      _stale.remove(page);
      errors.remove(page);
      _emit(page);
      if (changed) notifyListeners();
    } catch (error) {
      if (!_disposed && epoch == generation) {
        errors[page] = error;
        _emit(page);
      }
    } finally {
      if (epoch == generation) _pending.removeWhere((key, _) => key == page);
    }
  }

  void reset({bool keepCache = false}) {
    generation++;
    _pending.clear();
    errors.clear();
    final pages = _loaded.toSet();
    if (keepCache) {
      _stale.addAll(pages);
    } else {
      totalCount = null;
      _items.clear();
      _loaded.clear();
      _stale.clear();
    }
    for (final page in pages) {
      _emit(page);
    }
    notifyListeners();
  }

  /// Non-null only while listeners handle the structural notification sent by
  /// [replaceAll]; tells the grid whether to keep focus on the same item.
  bool? get replacingKeepFocus => _replacingKeepFocus;
  bool? _replacingKeepFocus;

  /// Synchronously replace all content with an in-memory list: every page is
  /// loaded, no page reloads, a single structural notification.
  void replaceAll(List<T> items, {required bool keepFocus}) {
    if (_disposed) return;
    generation++;
    _pending.clear();
    errors.clear();
    _stale.clear();
    _items
      ..clear()
      ..addAll(items.asMap());
    totalCount = items.length;
    _loaded
      ..clear()
      ..addAll([for (var p = 0; p * pageSize < items.length; p++) p]);
    for (final page in _signals.keys.toList()) {
      _emit(page);
    }
    _replacingKeepFocus = keepFocus;
    try {
      notifyListeners();
    } finally {
      _replacingKeepFocus = null;
    }
  }

  bool needsReload(int index) => _stale.contains(index ~/ pageSize) && !errors.containsKey(index ~/ pageSize);

  void markStale(int index) {
    _stale.add(index ~/ pageSize);
    _emit(index ~/ pageSize);
  }

  void update(int index, T item) {
    if (!_items.containsKey(index)) return;
    _items[index] = item;
    _emit(index ~/ pageSize);
  }

  void removeAt(int index) {
    if (totalCount == null || index < 0 || index >= totalCount!) return;
    generation++;
    _pending.clear();
    errors.clear();
    final old = Map<int, T>.of(_items);
    _items.clear();
    for (final entry in old.entries) {
      if (entry.key != index) _items[entry.key > index ? entry.key - 1 : entry.key] = entry.value;
    }
    totalCount = totalCount! - 1;
    _stale.addAll(_loaded.where((p) => p >= index ~/ pageSize));
    for (final page in _signals.keys.toList()) {
      if (page >= index ~/ pageSize) _emit(page);
    }
    notifyListeners();
  }

  /// Refresh locally around the old index; never walk intervening pages.
  Future<int> refresh({required int anchorIndex, required Object Function(T) idOf}) async {
    final item = this[anchorIndex], page = anchorIndex ~/ pageSize;
    final id = item == null ? null : idOf(item);
    reset(keepCache: true);
    final epoch = generation;
    await Future.wait([
      for (var p = page - 1; p <= page + 1; p++)
        if (p >= 0) requestIndex(p * pageSize),
    ]);
    if (_disposed || epoch != generation) return anchorIndex;
    if (id != null) {
      for (final entry in _items.entries) {
        if (!_stale.contains(entry.key ~/ pageSize) && idOf(entry.value) == id) return entry.key;
      }
    }
    return anchorIndex.clamp(0, (totalCount ?? 0) > 0 ? totalCount! - 1 : 0);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final signal in _signals.values) {
      signal.dispose();
    }
    super.dispose();
  }
}
