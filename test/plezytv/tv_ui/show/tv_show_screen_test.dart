import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_hero.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_tabs.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_controller.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_screen.dart';
import '../tv_theme_test_helper.dart';
import 'fake_media_server_client.dart';

MediaItem media(String id, MediaKind kind, {int? number, int? watched, int? offset}) => MediaItem(
  id: id,
  backend: MediaBackend.jellyfin,
  kind: kind,
  title: id,
  serverId: 'server',
  index: number,
  durationMs: 3600000,
).copyWith(parentIndex: 1, viewCount: watched, viewOffsetMs: offset);

FakeShowClient fixture() => FakeShowClient()
  ..show = media('The show', MediaKind.show)
  ..onDeck = media('e3', MediaKind.episode, number: 3, offset: 1500000)
  ..seasons = [media('Season 1', MediaKind.season, number: 1), media('Season 2', MediaKind.season, number: 2)]
  ..episodes = {
    'Season 1': [
      media('e1', MediaKind.episode, number: 1, watched: 1),
      media('e2', MediaKind.episode, number: 2, watched: 1),
      media('e3', MediaKind.episode, number: 3),
      media('e4', MediaKind.episode, number: 4),
    ],
    'Season 2': [media('second', MediaKind.episode, number: 1)],
  };

Future<TvShowController> mount(
  WidgetTester tester,
  FakeShowClient client, {
  String? seasonId,
  String? episodeId,
  Future<void> Function(BuildContext, MediaItem, bool)? play,
  int pageSize = 50,
}) async {
  final c = TvShowController(client: client, metadata: client.show, pageSize: pageSize);
  addTearDown(c.dispose);
  await pumpTvWidget(
    tester,
    TvShowScreen(
      metadata: client.show,
      controller: c,
      initialSeasonId: seasonId,
      initialEpisodeId: episodeId,
      playEpisode: play,
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

TvTabs tabs(WidgetTester tester) => tester.widget<TvTabs>(find.byType(TvTabs));
String focusedEpisode(WidgetTester tester) =>
    tester.widgetList<TvEpisode>(find.byType(TvEpisode)).firstWhere((e) => e.focusNode!.hasFocus).item.id;

void main() {
  testWidgets('A3 primary resumes on-deck with remaining time and initial focus', (tester) async {
    MediaItem? played;
    bool? restarted;
    await mount(
      tester,
      fixture(),
      play: (_, e, restart) async {
        played = e;
        restarted = restart;
      },
    );
    final button = tester.widget<TvButton>(find.byType(TvButton).first);
    expect(button.label, contains('Continue S1 E3'));
    expect(button.label, contains('35'));
    expect(button.focusNode!.hasFocus, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(played!.id, 'e3');
    expect(restarted, false);
  });

  testWidgets('A6 season poster enters at first unwatched; Up and Down remember episode', (tester) async {
    await mount(tester, fixture());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tabs(tester).selectedIndex, 1);
    expect(focusedEpisode(tester), 'e3');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedEpisode(tester), 'e4');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedEpisode(tester), 'e4');
  });

  testWidgets('A7 tabs debounce content for 300ms; A9 Back returns to main action', (tester) async {
    await mount(tester, fixture());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));
    expect(tabs(tester).selectedIndex, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(tabs(tester).selectedIndex, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tabs(tester).selectedIndex, 0);
    expect(tester.widget<TvButton>(find.byType(TvButton).first).focusNode!.hasFocus, true);
  });

  testWidgets('A10 explicit episode beyond page one is revealed; A11 playback advances after completion', (
    tester,
  ) async {
    final client = fixture();
    await mount(
      tester,
      client,
      seasonId: 'Season 1',
      episodeId: 'e3',
      pageSize: 1,
      play: (_, episode, restart) async {
        client.episodes['Season 1'] = [
          for (final e in client.episodes['Season 1']!)
            if (e.id == episode.id) e.copyWith(viewCount: 1, viewOffsetMs: 0) else e,
        ];
        client.onDeck = client.episodes['Season 1']!.last;
      },
    );
    expect(tabs(tester).selectedIndex, 1);
    expect(focusedEpisode(tester), 'e3');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(focusedEpisode(tester), 'e4');
    expect(
      tester.widgetList<TvEpisode>(find.byType(TvEpisode)).firstWhere((e) => e.item.id == 'e3').item.isWatched,
      true,
    );
  });

  testWidgets('A13 flattened series has Episodes tab and no season posters', (tester) async {
    final client = fixture()..seasons = [media('Season 1', MediaKind.season, number: 1)];
    client.episodes[client.show.id] = client.episodes['Season 1']!;
    await mount(tester, client);
    expect(tabs(tester).tabs.map((t) => t.label), ['Show', 'Episodes']);
    expect(find.byType(TvPoster), findsNothing);
  });

  testWidgets('H2 static skeleton appears only after 300ms; A14 retry recovers with primary focus', (tester) async {
    final client = fixture();
    final pending = Completer<({MediaItem? item, MediaItem? onDeckEpisode})>();
    client.onFetch = () => pending.future;
    final c = TvShowController(client: client, metadata: client.show);
    addTearDown(c.dispose);
    await pumpTvWidget(tester, TvShowScreen(metadata: client.show, controller: c));
    await tester.pump(const Duration(milliseconds: 299));
    expect(find.byType(TvHeroSkeleton), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(TvHeroSkeleton), findsOneWidget);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    final retry = tester.widget<TvButton>(find.byType(TvButton));
    expect(retry.label, 'Retry');
    expect(retry.focusNode!.hasFocus, true);
    client.onFetch = null;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(TvTabs), findsOneWidget);
    expect(tester.widget<TvButton>(find.byType(TvButton).first).focusNode!.hasFocus, true);
  });
  testWidgets('A9 second Back pops with watch-state result', (tester) async {
    final client = fixture();
    final c = TvShowController(client: client, metadata: client.show);
    addTearDown(c.dispose);
    bool? result;
    await pumpTvWidget(
      tester,
      Builder(
        builder: (context) => TextButton(
          child: const Text('Open show'),
          onPressed: () async {
            result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => TvShowScreen(metadata: client.show, controller: c, initialSeasonId: 'Season 1'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open show'));
    await tester.pumpAndSettle();
    c.watchStateChanged = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tabs(tester).selectedIndex, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TvShowScreen), findsNothing);
    expect(result, true);
  });

  testWidgets('Down while season page is pending enters episodes when ready', (tester) async {
    final client = fixture();
    final pending = Completer<LibraryPage<MediaItem>>();
    client.onPage = (key, start, size) async {
      if (key == 'Season 2') return pending.future;
      final items = client.episodes[key]!;
      return LibraryPage(items: items, totalCount: items.length);
    };
    await mount(tester, client);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(tabs(tester).selectedIndex, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    pending.complete(LibraryPage(items: client.episodes['Season 2']!, totalCount: 1));
    await tester.pumpAndSettle();
    expect(focusedEpisode(tester), 'second');
  });

  testWidgets('long season tab strip reveals the focused tab', (tester) async {
    final client = fixture()..seasons = [for (var i = 1; i <= 15; i++) media('Season $i', MediaKind.season, number: i)];
    await mount(tester, client);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    for (var i = 0; i < 15; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(tabs(tester).selectedIndex, 15);
    final box = FocusManager.instance.primaryFocus!.context!.findRenderObject()! as RenderBox;
    expect(box.localToGlobal(Offset(box.size.width, 0)).dx, lessThanOrEqualTo(1920));
  });
}
