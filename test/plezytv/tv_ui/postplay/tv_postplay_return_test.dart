import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_tabs.dart';
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_controller.dart';
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_screen.dart';
import 'package:plezy/plezytv/tv_ui/postplay/tv_postplay_controller.dart';
import 'package:plezy/plezytv/tv_ui/postplay/tv_postplay_logic.dart';
import 'package:plezy/plezytv/tv_ui/postplay/tv_postplay_screen.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_controller.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_screen.dart';
import 'package:plezy/plezytv/tv_ui/tv_card_registry.dart';

import '../show/fake_media_server_client.dart';
import '../tv_theme_test_helper.dart';
import 'tv_postplay_screen_test.dart' show PostPlayClient, episode, movie;

/// S14 T5 (R8, C5; A2, A20, A36): home → card? → player → post-play, with
/// the player removed under the post-play route once [removed] completes.
class _Stand {
  /// Card routes asked for: item and `initialSeasonId`.
  final details = <(MediaItem, String?)>[];
  Route<dynamic>? card;
  late TvPostPlayRoute postPlay;
}

Future<_Stand> _pump(
  WidgetTester tester, {
  required MediaItem watched,
  MediaItem? next,
  Route<dynamic>? card,
  TvCardEntry? entry,
  required Future<void> removed,
}) async {
  final stand = _Stand()..card = card;
  final controller = TvPostPlayController(client: PostPlayClient(numeric: false), watched: watched, next: next);
  addTearDown(controller.dispose);
  unawaited(controller.load());
  await pumpTvWidget(tester, const Text('home'));
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  if (card != null) {
    unawaited(nav.push(card));
    if (entry != null) TvCardRegistry.register(card, entry);
    await tester.pumpAndSettle();
  }
  final player = MaterialPageRoute<void>(builder: (_) => const Text('player'));
  unawaited(nav.push(player));
  await tester.pumpAndSettle();
  stand.postPlay = TvPostPlayRoute(
    builder: (_) => TvPostPlayScreen(
      args: TvPostPlayArgs(watched: watched, next: next, playerRemoved: removed),
      controller: controller,
      detailRoute: ({required metadata, initialSeasonId}) {
        stand.details.add((metadata, initialSeasonId));
        return MaterialPageRoute<void>(builder: (_) => Text('new card ${metadata.id}'));
      },
    ),
  );
  unawaited(nav.push(stand.postPlay));
  await tester.pumpAndSettle();
  unawaited(removed.then((_) => nav.removeRoute(player)));
  return stand;
}

Route<void> _stubCard(String label) => MaterialPageRoute<void>(builder: (_) => Text(label));

Future<void> _enter(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(TvCardRegistry.resetForTesting);

  testWidgets('A36: this movie card underneath — Back to movie pops without a new route', (tester) async {
    final removed = Completer<void>();
    final card = _stubCard('movie card');
    final s = await _pump(
      tester,
      watched: movie(userRating: 4),
      card: card,
      entry: TvCardEntry(itemKey: movie().globalKey),
      removed: removed.future,
    );
    await _enter(tester);
    expect(s.postPlay.isActive, isTrue, reason: 'waits for playerRemoved');
    removed.complete();
    await tester.pumpAndSettle();
    expect(s.details, isEmpty);
    expect(s.postPlay.isActive, isFalse);
    expect(card.isCurrent, isTrue);
    expect(find.text('movie card'), findsOneWidget);
  });

  testWidgets('A2: another movie card underneath — replaces the screen with a card', (tester) async {
    final removed = Completer<void>()..complete();
    final card = _stubCard('other');
    final s = await _pump(
      tester,
      watched: movie(userRating: 4),
      card: card,
      entry: TvCardEntry(itemKey: movie(id: 'other').globalKey),
      removed: removed.future,
    );
    await _enter(tester);
    expect(s.details.single.$1.id, 'm');
    expect(s.postPlay.isActive, isFalse, reason: 'replaced by the card');
    expect(find.text('new card m'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(card.isCurrent, isTrue, reason: 'Back from the card goes where the player came from');
  });

  testWidgets('A2: not a card underneath — replaces the screen with a card', (tester) async {
    final removed = Completer<void>()..complete();
    final s = await _pump(tester, watched: movie(userRating: 4), removed: removed.future);
    await _enter(tester);
    expect(s.details.single.$1.id, 'm');
    expect(s.details.single.$2, isNull);
    expect(s.postPlay.isActive, isFalse);
    expect(find.text('new card m'), findsOneWidget);
  });

  testWidgets('another series underneath: the series card opens on the watched season', (tester) async {
    final removed = Completer<void>()..complete();
    final s = await _pump(tester, watched: episode(2, 1), next: episode(2, 2), removed: removed.future);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _enter(tester);
    expect(s.details.single.$1.id, 'show');
    expect(s.details.single.$2, 's2');
    expect(s.postPlay.isActive, isFalse);
  });

  testWidgets('A36: real S8 underneath — Back to movie returns to it without a new route', (tester) async {
    final client = FakeShowClient()..show = movie(userRating: 4);
    final c = TvMovieController(
      client: client,
      metadata: client.show,
      versionPreference: (_) async => null,
      watchEvents: const Stream.empty(),
    );
    addTearDown(c.dispose);
    final card = MaterialPageRoute<bool>(
      builder: (_) => TvMovieScreen(metadata: client.show, controller: c),
    );
    final s = await _pump(tester, watched: movie(userRating: 4), card: card, removed: Future.value());
    await _enter(tester);
    expect(s.details, isEmpty);
    expect(card.isCurrent, isTrue);
    expect(find.byType(TvMovieScreen), findsOneWidget);
  });

  testWidgets('the check runs after playerRemoved: before, the player is underneath', (tester) async {
    final removed = Completer<void>();
    final card = _stubCard('movie card');
    final s = await _pump(
      tester,
      watched: movie(userRating: 4),
      card: card,
      entry: TvCardEntry(itemKey: movie().globalKey),
      removed: removed.future,
    );
    expect(TvCardRegistry.of(s.postPlay.previous), isNull, reason: 'player still below');
    await _enter(tester);
    removed.complete();
    await tester.pumpAndSettle();
    expect(s.details, isEmpty);
    expect(card.isCurrent, isTrue);
  });

  testWidgets('series card underneath — pops and switches to the watched season', (tester) async {
    final removed = Completer<void>()..complete();
    final card = _stubCard('show card');
    final s0 = <String>[];
    final s = await _pump(
      tester,
      watched: episode(2, 1),
      next: episode(2, 2),
      card: card,
      entry: TvCardEntry(itemKey: 'server:show', showSeason: s0.add),
      removed: removed.future,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _enter(tester);
    expect(s.details, isEmpty);
    expect(s0, ['s2']);
    expect(card.isCurrent, isTrue);
  });

  testWidgets('A20: real S7 underneath returns on the watched season without a duplicate', (tester) async {
    MediaItem m(String id, MediaKind kind, {int? number}) =>
        MediaItem(id: id, backend: MediaBackend.jellyfin, kind: kind, title: id, serverId: 'server', index: number);
    final client = FakeShowClient()
      ..show = m('show', MediaKind.show).copyWith(leafCount: 3)
      ..seasons = [
        m('s1', MediaKind.season, number: 1).copyWith(leafCount: 2),
        m('s2', MediaKind.season, number: 2).copyWith(leafCount: 1),
      ]
      ..episodes = {
        's1': [m('e1-1', MediaKind.episode, number: 1), m('e1-2', MediaKind.episode, number: 2)],
        's2': [m('e2-1', MediaKind.episode, number: 1)],
      };
    final c = TvShowController(client: client, metadata: client.show);
    addTearDown(c.dispose);
    final card = MaterialPageRoute<bool>(
      builder: (_) => TvShowScreen(metadata: client.show, controller: c),
    );
    final s = await _pump(tester, watched: episode(2, 1), next: episode(2, 2), card: card, removed: Future.value());
    expect(tester.widget<TvTabs>(find.byType(TvTabs, skipOffstage: false)).selectedIndex, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _enter(tester);
    expect(s.details, isEmpty);
    expect(card.isCurrent, isTrue);
    expect(find.byType(TvShowScreen), findsOneWidget);
    expect(tester.widget<TvTabs>(find.byType(TvTabs)).selectedIndex, 2);
  });
}
