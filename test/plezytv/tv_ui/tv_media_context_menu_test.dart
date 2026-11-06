import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_controller.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_screen.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/offline_mode_provider.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/media_context_menu.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/profile_stack.dart';
import 'show/fake_media_server_client.dart';
import 'tv_theme_test_helper.dart';

MediaItem item(String id, MediaKind kind, {String server = 'server', String? show}) => MediaItem(
  id: id,
  kind: kind,
  backend: MediaBackend.jellyfin,
  title: id,
  serverId: server,
  parentId: kind == MediaKind.season ? show : 'season',
).copyWith(grandparentId: kind == MediaKind.episode ? show : null);

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
    // Disable downloads on this host; menu TV/phone policy is selected separately.
    TvDetectionService.debugSetAppleTVOverride(true);
  });
  tearDown(() {
    TvUi.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  Future<void> mount(WidgetTester tester, Widget child) async {
    final manager = MultiServerManager();
    final servers = testMultiServerProvider(manager);
    final offline = OfflineModeProvider(manager);
    final profiles = await ProfileStack.create(withStorage: false);
    addTearDown(() async {
      await profiles.dispose();
      offline.dispose();
      servers.dispose();
      manager.dispose();
    });
    await pumpTvWidget(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
          ChangeNotifierProvider<OfflineModeProvider>.value(value: offline),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: profiles.active),
        ],
        child: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, Finder menu) async {
    final state = tester.state<MediaContextMenuState>(menu);
    state.showContextMenu(state.context);
    await tester.pumpAndSettle();
  }

  for (final tv in [true, false]) {
    for (final kind in [MediaKind.movie, MediaKind.show, MediaKind.season, MediaKind.episode]) {
      testWidgets('R1 ordinary $kind menu TV=$tv', (tester) async {
        TvUi.enabledForTesting = () => tv;
        await mount(
          tester,
          Scaffold(
            body: MediaContextMenu(
              item: item('card', kind, show: 'show'),
              child: const Text('card'),
            ),
          ),
        );
        await open(tester, find.byType(MediaContextMenu));
        expect(find.text(t.mediaMenu.viewDetails), tv ? findsOneWidget : findsNothing);
        expect(
          find.text(t.mediaMenu.goToSeries),
          !tv && (kind == MediaKind.episode || kind == MediaKind.season) ? findsOneWidget : findsNothing,
        );
      });
    }
    testWidgets('R1 Continue retains details and playback actions TV=$tv', (tester) async {
      TvUi.enabledForTesting = () => tv;
      await mount(
        tester,
        Scaffold(
          body: MediaContextMenu(
            item: item('episode', MediaKind.episode, show: 'show').copyWith(durationMs: 3600000, viewOffsetMs: 60000),
            isInContinueWatching: true,
            child: const Text('card'),
          ),
        ),
      );
      await open(tester, find.byType(MediaContextMenu));
      expect(find.text(t.mediaMenu.viewDetails), findsOneWidget);
      expect(find.text(t.mediaMenu.goToSeries), findsNothing);
      expect(find.text(t.mediaMenu.playFromBeginning), findsOneWidget);
    });
  }

  testWidgets('R2 own page hides details only for its server-qualified family', (tester) async {
    TvUi.enabledForTesting = () => true;
    final show = item('show', MediaKind.show);
    final cards = [
      show,
      item('season', MediaKind.season, show: 'show'),
      item('own', MediaKind.episode, show: 'show'),
      item('other', MediaKind.episode, show: 'other-show'),
      item('remote', MediaKind.episode, show: 'show', server: 'other-server'),
    ];
    final client = FakeShowClient()
      ..show = show
      ..relatedHubs = [MediaHub(id: 'related', title: 'Related', type: 'episode', items: cards)];
    final controller = TvShowController(client: client, metadata: show);
    addTearDown(controller.dispose);
    await mount(tester, TvShowScreen(metadata: show, controller: controller));
    for (var i = 0; i < cards.length; i++) {
      final menu = find.byWidgetPredicate((w) => w is MediaContextMenu && identical(w.item, cards[i])).last;
      await tester.ensureVisible(menu);
      await open(tester, menu);
      expect(
        find.text(t.mediaMenu.viewDetails),
        i < 3 ? findsNothing : findsOneWidget,
        reason: 'card ${cards[i].id} on ${cards[i].serverId}',
      );
      expect(find.text(t.mediaMenu.goToSeries), findsNothing);
      Navigator.of(tester.element(find.text(t.mediaMenu.rate))).pop();
      await tester.pumpAndSettle();
    }
  });
}
