import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/providers/download_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/offline_watch_sync_service.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_screen.dart';
import 'package:plezy/screens/media_detail_screen.dart';
import 'package:plezy/utils/video_player_navigation.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/multi_server_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';

import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/media_navigation_helper.dart';
import '../test_helpers/media_items.dart';

void main() {
  group('card activation routes', () {
    setUp(() {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
    });
    tearDown(() {
      TvUi.resetForTesting();
      SettingsService.resetForTesting();
    });

    for (final scenario in [
      (
        name: 'TV ordinary episode ignores Play preference',
        tv: true,
        offline: false,
        direct: false,
        kind: MediaKind.episode,
        episode: EpisodeAction.play,
        resume: ContinueWatchingAction.play,
        plays: false,
      ),
      (
        name: 'TV Continue plays despite episode details preference',
        tv: true,
        offline: false,
        direct: true,
        kind: MediaKind.episode,
        episode: EpisodeAction.details,
        resume: ContinueWatchingAction.play,
        plays: true,
      ),
      (
        name: 'TV Continue opens details despite episode Play preference',
        tv: true,
        offline: false,
        direct: true,
        kind: MediaKind.episode,
        episode: EpisodeAction.play,
        resume: ContinueWatchingAction.details,
        plays: false,
      ),
      (
        name: 'TV downloaded episode still plays',
        tv: true,
        offline: true,
        direct: false,
        kind: MediaKind.episode,
        episode: EpisodeAction.play,
        resume: ContinueWatchingAction.details,
        plays: true,
      ),
      (
        name: 'TV clip still plays',
        tv: true,
        offline: false,
        direct: false,
        kind: MediaKind.clip,
        episode: EpisodeAction.details,
        resume: ContinueWatchingAction.details,
        plays: true,
      ),
      (
        name: 'phone episode Play preference',
        tv: false,
        offline: false,
        direct: false,
        kind: MediaKind.episode,
        episode: EpisodeAction.play,
        resume: ContinueWatchingAction.details,
        plays: true,
      ),
      (
        name: 'phone episode details preference',
        tv: false,
        offline: false,
        direct: false,
        kind: MediaKind.episode,
        episode: EpisodeAction.details,
        resume: ContinueWatchingAction.play,
        plays: false,
      ),
    ]) {
      testWidgets(scenario.name, (tester) async {
        TvUi.enabledForTesting = () => scenario.tv;
        final settings = await SettingsService.getInstance();
        await settings.write(SettingsService.episodeAction, scenario.episode);
        await settings.write(SettingsService.continueWatchingAction, scenario.resume);
        final servers = testMultiServer();
        final downloads = _NoDownloads();
        final offlineWatch = _OfflineWatch();
        addTearDown(downloads.dispose);
        addTearDown(offlineWatch.dispose);
        final observer = _ActivationObserver();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: servers.provider),
              ChangeNotifierProvider<DownloadProvider>.value(value: downloads),
              ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineWatch),
            ],
            child: MaterialApp(
              navigatorObservers: [observer],
              home: const Scaffold(body: Text('Browse')),
            ),
          ),
        );
        final context = tester.element(find.text('Browse'));
        final result = await navigateToMediaItem(
          context,
          testMediaItem(
            id: 'episode',
            backend: MediaBackend.plex,
            kind: scenario.kind,
            serverId: 'server',
            grandparentId: 'show',
            parentId: 'season',
            parentIndex: 2,
          ),
          isOffline: scenario.offline,
          playDirectly: scenario.direct,
        );
        expect(result, MediaNavigationResult.navigated);
        final route = observer.activation!;
        if (scenario.plays) {
          expect(route.settings.name, kVideoPlayerRouteName);
        } else {
          final page = (route as PageRoute).buildPage(
            context,
            const AlwaysStoppedAnimation<double>(1),
            const AlwaysStoppedAnimation<double>(0),
          );
          if (scenario.tv) {
            expect(page, isA<TvShowScreen>());
            expect((page as TvShowScreen).initialEpisodeId, 'episode');
            expect(page.initialSeasonId, 'season');
          } else {
            expect((route as MaterialPageRoute).builder(context), isA<MediaDetailScreen>());
          }
        }
        await tester.pumpAndSettle();
        expect(find.text('Browse'), findsOneWidget);
      });
    }
  });
  test('episode detail target opens parent show and focuses season episode', () {
    final episode = testMediaItem(
      id: 'episode-1',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      title: 'Episode 1',
      parentId: 'season-2',
      parentIndex: 2,
      grandparentId: 'show-1',
      grandparentTitle: 'The Show',
      serverId: 'server-1',
    );

    final target = mediaDetailNavigationTargetFor(episode);

    expect(target.metadata.id, 'show-1');
    expect(target.metadata.kind, MediaKind.show);
    expect(target.initialSeasonId, 'season-2');
    expect(target.initialSeasonIndex, 2);
    expect(target.initialEpisodeId, 'episode-1');
  });

  test('season detail target opens parent show and focuses season', () {
    final season = testMediaItem(
      id: 'season-3',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 3',
      index: 3,
      parentId: 'show-1',
      parentTitle: 'The Show',
      serverId: 'server-1',
    );

    final target = mediaDetailNavigationTargetFor(season);

    expect(target.metadata.id, 'show-1');
    expect(target.metadata.kind, MediaKind.show);
    expect(target.initialSeasonId, 'season-3');
    expect(target.initialSeasonIndex, 3);
    expect(target.initialEpisodeId, isNull);
  });

  test('movie detail target keeps the movie itself', () {
    final movie = testMediaItem(id: 'movie-1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Movie');

    final target = mediaDetailNavigationTargetFor(movie);

    expect(target.metadata, same(movie));
    expect(target.initialSeasonId, isNull);
    expect(target.initialEpisodeId, isNull);
  });

  group('episode activation details decision', () {
    test('normal activation uses the episode action setting', () {
      expect(
        shouldOpenEpisodeDetailsForActivation(
          playDirectly: false,
          continueWatchingAction: ContinueWatchingAction.details,
          episodeAction: EpisodeAction.play,
        ),
        isFalse,
      );

      expect(
        shouldOpenEpisodeDetailsForActivation(
          playDirectly: false,
          continueWatchingAction: ContinueWatchingAction.play,
          episodeAction: EpisodeAction.details,
        ),
        isTrue,
      );
    });

    test('play-direct activation uses only the continue watching action setting', () {
      expect(
        shouldOpenEpisodeDetailsForActivation(
          playDirectly: true,
          continueWatchingAction: ContinueWatchingAction.play,
          episodeAction: EpisodeAction.details,
        ),
        isFalse,
      );

      expect(
        shouldOpenEpisodeDetailsForActivation(
          playDirectly: true,
          continueWatchingAction: ContinueWatchingAction.details,
          episodeAction: EpisodeAction.play,
        ),
        isTrue,
      );
    });
  });
}

// Observe real route selection without mounting the player or fetching details.
class _ActivationObserver extends NavigatorObserver {
  Route<dynamic>? activation;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return;
    activation = route;
    scheduleMicrotask(() => navigator!.removeRoute(route));
  }
}

class _NoDownloads extends ChangeNotifier implements DownloadProvider {
  @override
  Future<DownloadedMediaItem?> getCompletedDownload(String key) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OfflineWatch extends ChangeNotifier implements OfflineWatchSyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
