import "dart:async";

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plezy/providers/discover_provider.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_all_card.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_hero.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_horizontal_row.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_skeletons.dart';
import 'package:plezy/plezytv/tv_ui/home/tv_home_screen.dart';
import 'package:plezy/plezytv/tv_ui/tv_strings.dart';
import 'package:plezy/plezytv/tv_ui/tv_tint_service.dart';
import 'package:plezy/plezytv/tv_ui/tv_tinted_background.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/screens/hub_detail_screen.dart';
import 'package:plezy/widgets/optimized_media_image.dart';
import '../../test_helpers/media_items.dart';
import '../../test_helpers/prefs.dart';
import 'tv_theme_test_helper.dart';

class _Discover extends ChangeNotifier implements DiscoverProvider {
  @override
  List<MediaItem> onDeck = [];
  @override
  List<MediaHub> hubs = [];
  @override
  bool isLoading = false, areHubsLoading = false, isLoadInFlight = false, hasMoreContinueWatching = false;
  @override
  String? errorMessage;
  int loads = 0, staleChecks = 0, continueRefreshes = 0, manualRefreshes = 0, allLoads = 0;
  bool stale = false;
  @override
  Future<void> load() async {
    loads++;
  }

  @override
  bool refreshIfStale() {
    staleChecks++;
    return stale;
  }

  @override
  Future<void> refreshContinueWatching() async {
    continueRefreshes++;
  }

  @override
  Future<DiscoverRefreshOutcome> refreshNow() async {
    manualRefreshes++;
    isLoading = areHubsLoading = isLoadInFlight = true;
    errorMessage = null;
    emit();
    return DiscoverRefreshOutcome.refreshed;
  }

  @override
  Future<List<MediaItem>> loadAllContinueWatching() async {
    allLoads++;
    return onDeck;
  }

  void emit() => notifyListeners();
  void ready() {
    isLoading = areHubsLoading = isLoadInFlight = false;
    emit();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<MediaItem> items(String prefix, [int count = 12]) => [
  for (var i = 0; i < count; i++)
    testMediaItem(
      id: '$prefix$i',
      title: '$prefix$i',
      serverId: 'server',
      kind: prefix == 'episode' ? MediaKind.episode : MediaKind.movie,
      parentIndex: 1,
      index: i + 1,
      durationMs: 3600000,
      viewOffsetMs: 600000,
      summary: 'Summary $prefix$i',
    ),
];
MediaHub hub(String id, [int count = 12]) =>
    MediaHub(id: id, title: id, type: 'movie', items: items(id, count), size: count);

void main() {
  late _Discover provider;
  late FocusNode menu;
  late GlobalKey<TvHomeScreenState> home;
  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
    provider = _Discover();
    menu = FocusNode(debugLabel: 'test menu');
    home = GlobalKey<TvHomeScreenState>();
  });
  tearDown(() {
    menu.dispose();
    provider.dispose();
  });

  Future<void> pump(WidgetTester tester, {bool reduced = true}) async {
    await pumpTvWidget(
      tester,
      ChangeNotifierProvider<DiscoverProvider>.value(
        value: provider,
        child: MainScreenFocusScope(
          focusSidebar: menu.requestFocus,
          sideNavigationWidth: 0,
          child: Stack(
            children: [
              Focus(focusNode: menu, child: const SizedBox()),
              TvHomeScreen(key: home),
            ],
          ),
        ),
      ),
      reduced: reduced,
      appTheme: monoTheme(MonoPalette.dark),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  TvHorizontalRowState row(WidgetTester tester, int index) =>
      tester.state<TvHorizontalRowState>(find.byType(TvHorizontalRow).at(index));
  TvHero hero(WidgetTester tester) => tester.widget<TvHero>(find.byType(TvHero));
  void content() {
    provider.onDeck = items('episode');
    provider.hubs = [hub('movies'), hub('shows'), hub('more')];
  }

  testWidgets('A1/A2/A3: first card, hero, vertical row memory and compact geometry', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    expect(hero(tester).item!.id, 'episode0');
    expect(row(tester, 0).focusInside.value, isTrue);
    expect(hero(tester).hideSpoilers, SettingsService.instance.read(SettingsService.hideSpoilers));
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(row(tester, 0).focusInside.value, isTrue);
    await key(tester, LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 4; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(hero(tester).item!.id, 'movies4');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(hero(tester).compact, isTrue);
    expect(tester.getTopLeft(find.byType(TvHorizontalRow).at(2)).dy, 420);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(hero(tester).compact, isFalse);
    expect(hero(tester).item!.id, 'movies4');
    expect(row(tester, 1).focusedIndex, 4);
    expect(tester.getTopLeft(find.byType(TvHorizontalRow).at(1)).dy, 600);
  });

  testWidgets('R1: hide-spoilers preference updates the hero', (tester) async {
    content();
    await SettingsService.instance.write(SettingsService.hideSpoilers, true);
    await pump(tester);
    await tester.pumpAndSettle();
    expect(hero(tester).hideSpoilers, isTrue);
    await SettingsService.instance.write(SettingsService.hideSpoilers, false);
    await tester.pumpAndSettle();
    expect(hero(tester).hideSpoilers, isFalse);
  });

  testWidgets('A4: text follows rapid focus before backdrop debounce', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    for (var i = 1; i <= 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(hero(tester).item!.id, 'episode$i');
    }
    expect(tester.widget<TvTintedBackground>(find.byType(TvTintedBackground)).source.item.id, 'episode3');
  });

  testWidgets('A4: existing background requests final artwork only after 300ms', (tester) async {
    final source = ValueNotifier(TvArtworkSource(item: items('episode')[0]));
    final requested = <String>[];
    final service = TvTintService(
      fetch: (source, backdrop, width) async {
        requested.add(source.item.id);
        return null;
      },
    );
    await pumpTvWidget(
      tester,
      ValueListenableBuilder<TvArtworkSource>(
        valueListenable: source,
        builder: (_, value, _) => TvTintedBackground(source: value, service: service),
      ),
    );
    await tester.pumpAndSettle();
    requested.clear();
    for (var i = 1; i <= 3; i++) {
      source.value = TvArtworkSource(item: items('episode')[i]);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 299));
    expect(requested, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(requested, ['episode3', 'episode3']); // tint and backdrop
    await tester.pumpWidget(const SizedBox.shrink());
    source.dispose();
  });

  testWidgets('R10: horizontal focus updates hero without rebuilding rail/card builders', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    final rails = tester.widgetList<TvHorizontalRow>(find.byType(TvHorizontalRow)).toList();
    final cards = tester.widgetList<TvEpisode>(find.byType(TvEpisode)).toList();
    var railBuilds = 0, cardBuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is TvHorizontalRow) railBuilds++;
      if (element.widget is TvEpisode || element.widget is TvPoster) cardBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(hero(tester).item!.id, 'episode1');
    expect(tester.widgetList<TvHorizontalRow>(find.byType(TvHorizontalRow)).toList(), orderedEquals(rails));
    expect(tester.widgetList<TvEpisode>(find.byType(TvEpisode)).toList(), orderedEquals(cards));
    expect(cards.length, lessThan(12));
    expect(railBuilds, 0);
    expect(cardBuilds, 0);
    final image = tester.widget<OptimizedMediaImage>(
      find.descendant(of: find.byType(TvEpisode).first, matching: find.byType(OptimizedMediaImage)),
    );
    expect(image.width, 400);
    expect(image.height, 225);
  });

  testWidgets('A8/A9b: 300ms skeleton, phased readiness and automatic focus transfer', (tester) async {
    provider.isLoading = provider.areHubsLoading = provider.isLoadInFlight = true;
    await pump(tester);
    expect(menu.hasFocus, isTrue);
    expect(find.byType(TvHeroSkeleton), findsNothing);
    await tester.pump(const Duration(milliseconds: 299));
    expect(find.byType(TvHeroSkeleton), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(TvHeroSkeleton), findsOneWidget);
    // Provider holds early hub responses privately until onDeck completes.
    final earlyHubs = [hub('early')];
    provider.emit();
    await tester.pump();
    expect(find.byType(TvHorizontalRow), findsNothing);
    provider.onDeck = items('episode');
    provider.isLoading = false;
    provider.hubs = [];
    provider.emit();
    await tester.pumpAndSettle();
    expect(row(tester, 0).focusInside.value, isTrue);
    expect(find.byType(TvRowSkeleton), findsOneWidget);
    provider.hubs = earlyHubs;
    provider.ready();
    await tester.pumpAndSettle();
    expect(find.byType(TvRowSkeleton), findsNothing);
    expect(find.byType(TvHorizontalRow), findsNWidgets(2));
  });

  testWidgets('fast load never paints skeleton', (tester) async {
    provider.isLoading = provider.areHubsLoading = true;
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 100));
    content();
    provider.ready();
    await tester.pumpAndSettle();
    expect(find.byType(TvHeroSkeleton), findsNothing);
    expect(row(tester, 0).focusInside.value, isTrue);
  });

  for (final error in [false, true]) {
    testWidgets('A10/A10b/A10d/A11: terminal=$error, retry ownership and disabling', (tester) async {
      provider.errorMessage = error ? 'Server failed' : null;
      await pump(tester);
      await tester.pumpAndSettle();
      final button = tester.widget<TvButton>(find.byType(TvButton));
      expect(button.focusNode!.hasFocus, isTrue);
      expect(button.label, error ? TvStrings.retry : TvStrings.refresh);
      await key(tester, LogicalKeyboardKey.enter);
      expect(provider.manualRefreshes, 1);
      expect(tester.widget<TvButton>(find.byType(TvButton)).disabled, isTrue);
      expect(find.text(TvStrings.connecting), findsOneWidget);
      await key(tester, LogicalKeyboardKey.enter);
      expect(provider.manualRefreshes, 1);
      provider.errorMessage = error ? 'Server failed again' : null;
      provider.ready();
      await tester.pumpAndSettle();
      expect(tester.widget<TvButton>(find.byType(TvButton)).focusNode!.hasFocus, isTrue);
      await key(tester, LogicalKeyboardKey.enter);
      content();
      provider.ready();
      await tester.pumpAndSettle();
      expect(row(tester, 0).focusInside.value, isTrue);
      expect(hero(tester).item!.id, 'episode0');
    });
  }

  for (final escape in ['menu', 'route', 'section', 'retry-menu']) {
    testWidgets('R6/A17: arriving data preserves user focus in $escape', (tester) async {
      if (escape == 'retry-menu') {
        provider.errorMessage = 'Failed';
      } else {
        provider.isLoading = provider.areHubsLoading = true;
      }
      await pump(tester);
      await tester.pumpAndSettle();
      FocusNode? dialog;
      if (escape == 'route') {
        dialog = FocusNode();
        unawaited(
          showDialog<void>(
            context: home.currentContext!,
            builder: (_) => AlertDialog(
              content: TextButton(focusNode: dialog, autofocus: true, onPressed: () {}, child: const Text('dialog')),
            ),
          ),
        );
        await tester.pumpAndSettle();
      } else if (escape == 'section') {
        home.currentState!.onTabHidden();
        menu.requestFocus();
        await tester.pump();
      } else {
        if (escape == 'retry-menu') {
          await key(tester, LogicalKeyboardKey.enter);
          await key(tester, LogicalKeyboardKey.arrowLeft);
        } else {
          await key(tester, LogicalKeyboardKey.arrowUp);
        }
      }
      content();
      provider.ready();
      await tester.pumpAndSettle();
      expect(escape == 'route' ? dialog!.hasFocus : menu.hasFocus, isTrue);
      if (dialog != null) {
        Navigator.of(home.currentContext!).pop();
        await tester.pumpAndSettle();
        dialog.dispose();
      }
    });
  }

  testWidgets('A12/A18: refresh hooks, reorder/removal, removed row fallback', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    final state = home.currentState!;
    state.refresh();
    expect(provider.continueRefreshes, 1);
    provider.stale = true;
    state.refresh();
    expect(provider.continueRefreshes, 1);
    state.onTabHidden();
    state.onTabShown();
    expect(provider.staleChecks, 3);
    provider.isLoadInFlight = true;
    state.primeRefresh();
    expect(provider.loads, 1);
    provider.isLoadInFlight = false;
    state.primeRefresh();
    expect(provider.loads, 2);
    state.fullRefresh();
    expect(provider.loads, 3);
    provider.onDeck = [provider.onDeck[3], ...provider.onDeck.take(3), ...provider.onDeck.skip(4)];
    provider.emit();
    await tester.pumpAndSettle();
    expect(hero(tester).item!.id, 'episode3');
    expect(row(tester, 0).focusedIndex, 0);
    provider.onDeck = provider.onDeck.skip(1).toList();
    provider.emit();
    await tester.pumpAndSettle();
    expect(hero(tester).item!.id, 'episode0');
    provider.onDeck = [];
    provider.emit();
    await tester.pumpAndSettle();
    expect(row(tester, 0).focusInside.value, isTrue);
    expect(hero(tester).item!.id, 'movies0');
  });

  testWidgets('R9: disappearing lower rail falls back to first card, not remembered column', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    await key(tester, LogicalKeyboardKey.arrowDown);
    provider.hubs = provider.hubs.skip(1).toList();
    provider.emit();
    await tester.pumpAndSettle();
    expect(row(tester, 0).focusInside.value, isTrue);
    expect(row(tester, 0).focusedIndex, 0);
    expect(hero(tester).item!.id, 'episode0');
  });

  testWidgets('A19: Back to row start then shell; left escapes first card', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(row(tester, 0).focusedIndex, 8);
    await key(tester, LogicalKeyboardKey.escape);
    expect(row(tester, 0).focusedIndex, 0);
    expect(row(tester, 0).focusInside.value, isTrue);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(menu.hasFocus, isTrue);
    home.currentState!.focusActiveTabIfReady();
    await tester.pumpAndSettle();
    expect(row(tester, 0).focusedIndex, 0);
  });

  testWidgets('A16: 25-item Continue Watching opens All and restores focus', (tester) async {
    content();
    provider.onDeck = items('episode', 25);
    provider.hasMoreContinueWatching = true;
    await pump(tester);
    await tester.pumpAndSettle();
    for (var i = 0; i < 25; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(find.byType(TvAllCard), findsOneWidget);
    expect(row(tester, 0).focusedIndex, 25);
    await key(tester, LogicalKeyboardKey.enter);
    final detail = tester.widget<HubDetailScreen>(find.byType(HubDetailScreen));
    expect(detail.hub.id, 'continue_watching');
    expect(detail.isInContinueWatching, isTrue);
    expect(detail.usesContinueWatchingAction, isTrue);
    expect(detail.loadItems, isNotNull);
    expect(provider.allLoads, 1);
    Navigator.of(tester.element(find.byType(HubDetailScreen))).pop();
    await tester.pumpAndSettle();
    expect(row(tester, 0).focusedIndex, 25);
    expect(row(tester, 0).focusInside.value, isTrue);
  });
  testWidgets('A16: hub All opens the original unfiltered Plezy hub', (tester) async {
    final original = MediaHub(
      id: 'mixed',
      title: 'Mixed',
      type: 'mixed',
      more: true,
      size: 3,
      items: [
        testMediaItem(id: 'video'),
        testMediaItem(id: 'audio', kind: MediaKind.album),
      ],
    );
    provider.hubs = [original];
    await pump(tester);
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byType(TvAllCard), findsOneWidget);
    await key(tester, LogicalKeyboardKey.enter);
    final detail = tester.widget<HubDetailScreen>(find.byType(HubDetailScreen));
    expect(detail.hub, same(original));
    expect(detail.hub.items.length, 2);
    expect(detail.loadItems, isNull);
    expect(detail.isInContinueWatching, isFalse);
    expect(detail.usesContinueWatchingAction, isFalse);
  });
}
