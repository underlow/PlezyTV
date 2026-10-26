import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/search/tv_search_history.dart';
import 'package:plezy/plezytv/tv_ui/tv_settings.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/storage_service.dart';

import '../../../test_helpers/prefs.dart';

void main() {
  setUp(resetSharedPreferencesForTest);

  test('add: newest first, trimmed, empty ignored', () {
    var h = <String>[];
    h = TvSearchHistory.add(h, ' дюна ');
    h = TvSearchHistory.add(h, 'матрица');
    h = TvSearchHistory.add(h, '   ');
    expect(h, ['матрица', 'дюна']);
  });

  test('add: case-insensitive repeat moves up in the latest spelling', () {
    final h = TvSearchHistory.add(['матрица', 'Дюна'], 'дюна');
    expect(h, ['дюна', 'матрица']);
  });

  test('add: at most 10 entries', () {
    var h = <String>[];
    for (var i = 0; i < 12; i++) {
      h = TvSearchHistory.add(h, 'q$i');
    }
    expect(h.length, 10);
    expect(h.first, 'q11');
    expect(h.last, 'q2');
  });

  test('storage store is scoped to the active profile', () async {
    final storage = await StorageService.getInstance();
    final store = TvStorageSearchHistory(storage);
    await storage.setActiveProfileId('a');
    await store.save(['дюна']);
    await storage.setActiveProfileId('b');
    expect(await store.load(), isEmpty);
    await store.save(['матрица']);
    expect(await store.load(), ['матрица']);
    await storage.setActiveProfileId('a');
    expect(await store.load(), ['дюна']);
  });

  test('memory store round-trips', () async {
    final store = TvMemorySearchHistory();
    await store.save(['a']);
    expect(await store.load(), ['a']);
  });

  test('keyboard layout pref defaults to ru', () async {
    final settings = await SettingsService.getInstance();
    expect(settings.read(TvSettings.searchKeyboardLayout), 'ru');
    await settings.write(TvSettings.searchKeyboardLayout, 'en');
    expect(settings.read(TvSettings.searchKeyboardLayout), 'en');
  });
}
