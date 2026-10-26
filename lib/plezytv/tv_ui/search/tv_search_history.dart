import 'dart:convert';

import '../../../services/storage_service.dart';

/// Recent search queries (S11 R9): newest first, case-insensitive dedupe that
/// keeps the latest spelling, at most [limit] entries.
abstract final class TvSearchHistory {
  static const int limit = 10;

  static List<String> add(List<String> history, String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return List.of(history);
    final lower = trimmed.toLowerCase();
    return [trimmed, ...history.where((q) => q.toLowerCase() != lower)].take(limit).toList();
  }
}

abstract interface class TvSearchHistoryStore {
  Future<List<String>> load();
  Future<void> save(List<String> history);
}

/// Stored under the active profile's scope, re-read on every call (like S10).
class TvStorageSearchHistory implements TvSearchHistoryStore {
  TvStorageSearchHistory(this.storage);
  final StorageService storage;

  String get _key {
    final scope = storage.activeUserScope();
    return '${scope == null ? '' : 'user_${scope}_'}plezytv_search_history';
  }

  @override
  Future<List<String>> load() async {
    final raw = storage.prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final json = jsonDecode(raw);
      return json is List ? json.whereType<String>().take(TvSearchHistory.limit).toList() : const [];
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> save(List<String> history) => storage.prefs.setString(_key, jsonEncode(history));
}

class TvMemorySearchHistory implements TvSearchHistoryStore {
  TvMemorySearchHistory([List<String> value = const []]) : value = List.of(value);
  List<String> value;
  @override
  Future<List<String>> load() async => List.of(value);
  @override
  Future<void> save(List<String> history) async => value = List.of(history);
}
