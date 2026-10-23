import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/models/plex/plex_home_user.dart';
import 'package:plezy/navigation/profile_session_screen.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/profiles/plex_home_service.dart';
import 'package:plezy/profiles/profile_connection_registry.dart';
import 'package:plezy/profiles/profile_registry.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/offline_watch_sync_service.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/services/system_shelf_service.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/io_fakes.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/plezytv/tv_ui/tv_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SystemShelfService().debugReset();
  });
  tearDown(() {
    TvUi.resetForTesting();
    TvSectionShell.sectionBuilderForTesting = null;
    TvSectionShell.sessionControllerFactoryForTesting = null;
  });

  for (final tv in [false, true]) {
    testWidgets('explicit profile builder wins on TV=$tv', (tester) async {
      TvUi.enabledForTesting = () => tv;
      final graph = await _SessionGraph.create();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await graph.dispose();
      });
      await graph.pump(
        tester,
        httpClientFactory: () => FakeHttpClient(200, const <int>[]),
        profileShellBuilder: (_) => const Text('explicit home'),
      );
      await tester.pumpAndSettle();
      expect(find.text('explicit home'), findsOneWidget);
      expect(find.byType(TvShell), findsNothing);
    });
  }

  for (final tv in [false, true]) {
    for (final offline in [false, true]) {
      testWidgets('profile route selects home TV=$tv offline=$offline', (tester) async {
        var reads = 0;
        TvUi.enabledForTesting = () {
          reads++;
          return tv;
        };
        final graph = await _SessionGraph.create();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await graph.dispose();
        });
        Widget? selected;
        TvUi.profileHomeBuilderForTesting = (replacement) {
          selected = replacement;
          return const _HomeProbe();
        };
        await graph.pump(tester, httpClientFactory: () => FakeHttpClient(200, const <int>[]), isOfflineMode: offline);
        await tester.pumpAndSettle();
        final navigator = tester.widgetList<Navigator>(find.byType(Navigator)).last;
        final context = tester.element(find.byType(ProfileSessionScreen));
        final route = navigator.onGenerateRoute!(const RouteSettings(name: '/')) as MaterialPageRoute<void>;
        route.builder(context);
        expect(reads, 1);
        if (tv) {
          expect(selected, isA<TvShell>());
          final shell = selected as TvShell;
          final home = shell.build(context) as TvSectionShell;
          expect(home.isOfflineMode, offline);
          expect(home.initialPromptHandled, isTrue);
        } else {
          expect(selected, isNull, reason: 'non-TV must choose the unchanged upstream fallback');
          expect(find.byType(TvShell), findsNothing);
        }
        TvUi.enabledForTesting = () {
          reads++;
          return !tv;
        };
        final selectedType = selected.runtimeType;
        route.builder(context);
        expect(selected.runtimeType, selectedType);
        expect(reads, 1, reason: 'route rebuild must use the session snapshot');
      });
    }
  }

  testWidgets('TV shell forwards both flags and preserves child state across override changes', (tester) async {
    TvSectionShell? home;
    TvUi.enabledForTesting = () => true;
    final graph = await _SessionGraph.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await graph.dispose();
    });
    TvSectionShell.sessionControllerFactoryForTesting = (_, _) => null;
    TvSectionShell.sectionBuilderForTesting = (_, _, key) => _HomeProbe(key: key);
    await graph.pump(
      tester,
      httpClientFactory: () => FakeHttpClient(200, const <int>[]),
      isOfflineMode: true,
      initialPromptHandled: false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(TvShell), findsOneWidget);
    home = tester.widget<TvSectionShell>(find.byType(TvSectionShell));
    final state = tester.state(find.byType(TvSectionShell));
    expect(home.isOfflineMode, isTrue);
    expect(home.initialPromptHandled, isFalse);
    TvUi.enabledForTesting = () => false;
    await graph.pump(tester, httpClientFactory: () => FakeHttpClient(200, const <int>[]), isOfflineMode: true);
    await tester.pumpAndSettle();
    expect(find.byType(TvShell), findsOneWidget);
    expect(tester.state(find.byType(TvSectionShell)), same(state));
    home = tester.widget<TvSectionShell>(find.byType(TvSectionShell));
    expect(home.initialPromptHandled, isTrue);
  });

  testWidgets('lookup reads injectable detection once unless passed a snapshot', (tester) async {
    var reads = 0;
    TvUi.enabledForTesting = () {
      reads++;
      return false;
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(TvUi.profileHome(context, isOfflineMode: false, initialPromptHandled: false), isNull);
            expect(reads, 1);
            expect(
              TvUi.profileHome(context, enabled: true, isOfflineMode: false, initialPromptHandled: false),
              isA<TvShell>(),
            );
            expect(reads, 1);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}

class _HomeProbe extends StatefulWidget {
  const _HomeProbe({super.key});
  @override
  State<_HomeProbe> createState() => _HomeProbeState();
}

class _HomeProbeState extends State<_HomeProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _SessionGraph {
  _SessionGraph._({
    required this.db,
    required this.profileRegistry,
    required this.connectionRegistry,
    required this.profileConnectionRegistry,
    required this.storage,
    required this.plexHome,
    required this.activeProfile,
    required this.serverManager,
    required this.multiServer,
    required this.offlineWatch,
  });

  final AppDatabase db;
  final ProfileRegistry profileRegistry;
  final ConnectionRegistry connectionRegistry;
  final ProfileConnectionRegistry profileConnectionRegistry;
  final StorageService storage;
  final _FakePlexHomeService plexHome;
  final ActiveProfileProvider activeProfile;
  final MultiServerManager serverManager;
  final MultiServerProvider multiServer;
  final OfflineWatchSyncService offlineWatch;

  static Future<_SessionGraph> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final profileRegistry = ProfileRegistry(db);
    final connectionRegistry = ConnectionRegistry(db);
    final profileConnectionRegistry = ProfileConnectionRegistry(db);
    final storage = await StorageService.getInstance();
    final plexHome = _FakePlexHomeService(
      connections: connectionRegistry,
      profileConnections: profileConnectionRegistry,
      storage: storage,
    );
    final serverManager = MultiServerManager();
    return _SessionGraph._(
      db: db,
      profileRegistry: profileRegistry,
      connectionRegistry: connectionRegistry,
      profileConnectionRegistry: profileConnectionRegistry,
      storage: storage,
      plexHome: plexHome,
      activeProfile: ActiveProfileProvider(
        registry: profileRegistry,
        plexHome: plexHome,
        connections: connectionRegistry,
        profileConnections: profileConnectionRegistry,
        storage: storage,
      ),
      serverManager: serverManager,
      multiServer: testMultiServerProvider(serverManager),
      // The session tree instantiates MusicPlaybackServiceImpl (the mini-player
      // overlay watches it), which needs the database + offline watch service.
      offlineWatch: OfflineWatchSyncService(database: db, serverManager: serverManager),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required FakeHttpClient Function() httpClientFactory,
    WidgetBuilder? profileShellBuilder,
    bool isOfflineMode = false,
    bool initialPromptHandled = true,
    GlobalKey<NavigatorState>? navigatorKey,
  }) => tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storage),
        Provider<AppDatabase>.value(value: db),
        Provider<ConnectionRegistry>.value(value: connectionRegistry),
        Provider<ProfileConnectionRegistry>.value(value: profileConnectionRegistry),
        Provider<PlexHomeService>.value(value: plexHome),
        ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfile),
        ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
        ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineWatch),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: ProfileSessionScreen.forTesting(
          initialPromptHandled: initialPromptHandled,
          isOfflineMode: isOfflineMode,
          httpClientFactory: httpClientFactory,
          profileShellBuilder: profileShellBuilder,
        ),
      ),
    ),
  );

  Future<void> dispose() async {
    await activeProfile.resetForTesting();
    activeProfile.dispose();
    multiServer.dispose();
    serverManager.dispose();
    await plexHome.dispose();
    offlineWatch.dispose();
    await db.close();
  }
}

class _FakePlexHomeService extends PlexHomeService {
  _FakePlexHomeService({required super.connections, required super.profileConnections, required StorageService storage})
    : super(storage: storage, plexHomeUserFetcher: (_) async => const []);

  @override
  Map<String, List<PlexHomeUser>> get current => const {};

  @override
  Stream<Map<String, List<PlexHomeUser>>> get stream => Stream.value(const {});

  @override
  Future<void> start() async {}

  @override
  Future<void> reloadFromStorage() async {}

  @override
  Future<void> dispose() async {}
}
