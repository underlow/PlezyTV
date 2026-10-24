import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/providers/download_provider.dart';
import 'package:plezy/models/download_models.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_actions.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_controller.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/watch_actions.dart';
import 'package:plezy/utils/watch_state_notifier.dart';
import '../tv_theme_test_helper.dart';
import 'tv_show_screen_test.dart' show fixture;

class Source implements CatalogSource {
  @override
  final WatchlistChangeNotifier watchlistChanges = WatchlistChangeNotifier();
  bool member = false;
  @override
  CatalogSourceId get id => CatalogSourceId.trakt;
  @override
  bool? isOnWatchlist(MediaKind kind, CatalogItemIds ids) => member;
  @override
  Future<void> ensureWatchlistLoaded() async {}
  @override
  Future<void> addToWatchlist(MediaKind kind, CatalogItemIds ids) async {
    member = true;
    watchlistChanges.notify();
  }

  @override
  Future<void> removeFromWatchlist(MediaKind kind, CatalogItemIds ids) async {
    member = false;
    watchlistChanges.notify();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Downloads extends ChangeNotifier implements DownloadProvider {
  DownloadProgress? progress;
  MediaItem? episode;
  bool rule = false;
  bool queueing = false;
  @override
  DownloadProgress? getProgress(String key) => progress;
  @override
  bool isDownloaded(String key) => progress?.status == DownloadStatus.completed;
  @override
  bool isQueueing(String key) => queueing;
  @override
  bool hasSyncRule(String key) => rule;
  @override
  String syncRuleKeyForClient(MediaServerClient client, String id, {ServerId? serverId}) => 'rule';
  @override
  Map<String, DownloadProgress> get downloads => episode == null
      ? {}
      : {episode!.globalKey: DownloadProgress(globalKey: episode!.globalKey, status: DownloadStatus.paused)};
  @override
  MediaItem? getMetadata(String key) => episode;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('A5 omits unavailable trailer/list, renders available trailer and source membership', (tester) async {
    final client = fixture();
    final c = TvShowController(client: client, metadata: client.show);
    addTearDown(c.dispose);
    await c.load();
    final played = <MediaItem>[];
    await pumpTvWidget(
      tester,
      TvShowActions(
        controller: c,
        primary: TvButton(label: 'Watch'),
        playExtra: (item) async {
          played.add(item);
        },
      ),
    );
    expect(find.byIcon(Icons.theaters), findsNothing);
    expect(find.byIcon(Icons.bookmark_add), findsNothing);
    expect(find.byIcon(Icons.shuffle), findsOneWidget);
    final source = Source();
    addTearDown(source.watchlistChanges.dispose);
    c.watchlistCandidates = [(source: source, ids: const CatalogItemIds(imdb: 'tt1'))];
    c.extras = [
      client.show.copyWith(id: 'trailer', kind: MediaKind.clip, raw: {'ExtraType': 'Trailer'}),
    ];
    c.applyWatchEvent(
      WatchStateEvent(
        itemId: c.show.id,
        serverId: ServerId('server'),
        parentChain: [],
        changeType: WatchStateChangeType.unwatched,
        isNowWatched: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.theaters), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_add), findsOneWidget);
    final trailer = tester
        .widgetList<TvIconButton>(find.byType(TvIconButton))
        .firstWhere((b) => b.icon == Icons.theaters);
    trailer.onSelect!();
    await tester.pumpAndSettle();
    expect(played.single.id, c.trailer!.id);
    final list = tester
        .widgetList<TvIconButton>(find.byType(TvIconButton))
        .firstWhere((b) => b.icon == Icons.bookmark_add);
    list.onSelect!();
    await tester.pumpAndSettle();
    expect(source.member, true);
    expect(find.byIcon(Icons.bookmark_added), findsOneWidget);
  });

  testWidgets('A12 watched action marks whole show, refreshes badges and changes primary to rewatch', (tester) async {
    final client = fixture()..onDeck = null;
    final c = TvShowController(client: client, metadata: client.show);
    addTearDown(c.dispose);
    await c.load();
    MediaItem? marked;
    bool? value;
    await pumpTvWidget(
      tester,
      TvShowActions(
        controller: c,
        primary: TvButton(label: 'Watch'),
        playExtra: (_) async {},
        markWatched: (item, watched) async {
          marked = item;
          value = watched;
          client.show = client.show.withWatchedFlag(watched);
          client.seasons = client.seasons.map((s) => s.withWatchedFlag(watched)).toList();
          client.episodes = client.episodes.map(
            (k, v) => MapEntry(k, v.map((e) => e.withWatchedFlag(watched)).toList()),
          );
          return WatchMarkOutcome.marked;
        },
      ),
    );
    final watched = tester.widgetList<TvIconButton>(find.byType(TvIconButton)).firstWhere((b) => b.icon == Icons.check);
    watched.onSelect!();
    await tester.pumpAndSettle();
    expect(marked!.id, client.show.id);
    expect(value, true);
    expect(c.watchStateChanged, true);
    expect(c.primaryAction!.restart, true);
    expect(c.primaryAction!.label, 'Rewatch');
    expect(c.seasons.every((s) => s.isWatched), true);
    expect(c.episodesFor('Season 1').every((e) => e.isWatched), true);
    expect(find.byIcon(Icons.remove_done), findsOneWidget);
  });
  testWidgets('D3 download states and sync rules stay enabled for Downloads management', (tester) async {
    final client = fixture();
    final c = TvShowController(client: client, metadata: client.show);
    final downloads = Downloads();
    addTearDown(c.dispose);
    addTearDown(downloads.dispose);
    await c.load();
    await pumpTvWidget(
      tester,
      ChangeNotifierProvider<DownloadProvider>.value(
        value: downloads,
        child: TvShowActions(
          controller: c,
          primary: TvButton(label: 'Watch'),
          playExtra: (_) async {},
        ),
      ),
    );
    for (final state in [
      (DownloadStatus.queued, Icons.schedule),
      (DownloadStatus.downloading, Icons.downloading),
      (DownloadStatus.paused, Icons.pause_circle_outline),
      (DownloadStatus.failed, Icons.error_outline),
      (DownloadStatus.cancelled, Icons.cancel_outlined),
      (DownloadStatus.partial, Icons.download_for_offline_outlined),
      (DownloadStatus.completed, Icons.download_done),
    ]) {
      downloads.progress = DownloadProgress(globalKey: c.show.globalKey, status: state.$1);
      downloads.notifyListeners();
      await tester.pumpAndSettle();
      final button = tester.widgetList<TvIconButton>(find.byType(TvIconButton)).firstWhere((b) => b.icon == state.$2);
      expect(button.disabled, false);
      expect(button.caption, state.$1 == DownloadStatus.completed ? t.downloads.downloadNow : t.navigation.downloads);
    }
    downloads.progress = null;
    downloads.episode = client.episodes['Season 1']!.first.copyWith(grandparentId: c.show.id);
    downloads.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
    downloads.rule = true;
    downloads.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.sync), findsOneWidget);
  });
}
