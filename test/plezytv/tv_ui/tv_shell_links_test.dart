import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plezy/main.dart' show rootNavigatorKey;
import 'package:plezy/screens/media_detail_screen.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/providers/offline_mode_provider.dart';
import 'package:plezy/providers/companion_remote_provider.dart';
import 'package:plezy/models/companion_remote/remote_command.dart';
import 'package:plezy/services/companion_remote/companion_remote_receiver.dart';
import 'package:plezy/plezytv/screen_links/screen_link_router.dart';
import 'package:plezy/plezytv/update/updater.dart';
import 'package:plezy/plezytv/update/update_service.dart';
import 'package:plezy/plezytv/update/startup_trigger.dart';
import 'package:plezy/plezytv/tv_ui/tv_shell.dart';

import 'package:flutter/material.dart';
import 'package:plezy/media/ids.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/mixins/refreshable.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/navigation/profile_navigation_scope.dart';
import 'package:plezy/plezytv/tv_ui/shell/tv_shell_session_controller.dart';
import 'package:plezy/plezytv/tv_ui/tv_settings.dart';
import 'package:plezy/providers/hidden_libraries_provider.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/settings_service.dart';

import '../../test_helpers/prefs.dart';

class _Libraries extends ChangeNotifier implements LibrariesProvider {
  @override
  List<MediaLibrary> libraries = [];
  @override
  LibrariesLoadState loadState = LibrariesLoadState.loaded;
  @override
  bool get isLoading => loadState == LibrariesLoadState.loading;
  int refreshes = 0;
  @override
  Future<void> refresh() async {
    refreshes++;
  }

  void emit() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Hidden extends ChangeNotifier implements HiddenLibrariesProvider {
  @override
  Set<String> hiddenLibraryKeys = {};
  void emit() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Servers extends ChangeNotifier implements MultiServerProvider {
  @override
  bool hasLiveTv = false;
  @override
  bool get hasConnectedServers => true;
  @override
  List<String> get onlineServerIds => ['s1'];
  @override
  List<String> get expectedServerIds => ['s1'];
  @override
  MediaServerClient? getClientForServer(ServerId id) => _Client();
  @override
  int totalServerCount = 1;
  @override
  List<({String displayName, ServerId serverId})> get authErrorServers => [];
  @override
  List<({String displayName, ServerId serverId})> get accessDeniedServers => [];
  void emit() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session extends ChangeNotifier implements TvShellSessionController {
  @override
  bool isOffline = false;
  void offline(bool value) {
    isOffline = value;
    notifyListeners();
  }

  @override
  bool get isReconnecting => false;
  @override
  Future<void> start() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Probe extends StatefulWidget {
  const _Probe({required super.key, required this.tab});
  final NavigationTabId tab;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with LibraryLoadable, SearchInputFocusable {
  final loads = <String>[];
  String? query;
  @override
  void loadLibraryByKey(String key) => loads.add(key);
  @override
  void focusSearchInput() {}
  @override
  void submitSearchQuery(String value) => query = value;
  @override
  Widget build(BuildContext context) => Text(widget.tab.name);
}

const home = TvShellSection.tab(NavigationTabId.discover);
const search = TvShellSection.tab(NavigationTabId.search);
const movies = MediaLibrary(id: '1', backend: MediaBackend.plex, title: 'Movies', serverId: 's1', serverName: 'One');
const series = MediaLibrary(id: '2', backend: MediaBackend.plex, title: 'Series', serverId: 's1');

class _Offline extends ChangeNotifier implements OfflineModeProvider {
  @override
  bool get isOffline => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Companion extends ChangeNotifier implements CompanionRemoteProvider {
  @override
  CommandReceivedCallback? onCommandReceived;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements MediaServerClient {
  @override
  Future<List<MediaLibrary>> fetchLibraries() async => [movies, series];
  @override
  Future<MediaItem?> fetchItem(String id) async => id == '123'
      ? MediaItem(id: '123', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Movie', serverId: 's1')
      : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Update extends UpdateService {
  _Update(SharedPreferences prefs)
    : super(
        version: '0.2.0',
        preferences: prefs,
        abi: () async => 'armeabi-v7a',
        cache: Directory.systemTemp,
        log: (_) {},
      );
  final gate = Completer<UpdateRelease?>();
  final checks = <bool>[];
  @override
  Future<UpdateRelease?> check({required bool automatic}) {
    checks.add(automatic);
    return gate.future;
  }
}

class _Routes extends NavigatorObserver {
  Route<dynamic>? last;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => last = route;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final receiver = CompanionRemoteReceiver.instance;
  final router = ScreenLinkRouter.instance;
  late _Companion companion;
  late _Session session;
  late _Routes routes;
  final probes = <NavigationTabId, GlobalKey>{};
  TvSectionShellState shell(WidgetTester tester) => tester.state(find.byType(TvSectionShell));
  _ProbeState probe(NavigationTabId tab) => probes[tab]!.currentState as _ProbeState;
  Future<void> mount(WidgetTester tester) async {
    await SettingsService.getInstance();
    final libraries = _Libraries()..libraries = [movies, series];
    final hidden = _Hidden()..hiddenLibraryKeys = {movies.globalKey, series.globalKey};
    final servers = _Servers();
    final offline = _Offline();
    companion = _Companion();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      libraries.dispose();
      hidden.dispose();
      servers.dispose();
      offline.dispose();
      companion.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
          ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
          ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
          ChangeNotifierProvider<OfflineModeProvider>.value(value: offline),
          ChangeNotifierProvider<CompanionRemoteProvider>.value(value: companion),
        ],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          navigatorObservers: [routes],
          home: const TvShell(isOfflineMode: false, initialPromptHandled: true),
        ),
      ),
    );
    profileNavigationRegistry.attachNavigator(rootNavigatorKey);
    await tester.pumpAndSettle();
  }

  Future<void> link(WidgetTester tester, String target) async {
    expect(router.claim('plezytv://screen/$target'), isTrue);
    await tester.pump();
    await tester.pumpAndSettle();
  }

  setUp(() {
    resetSharedPreferencesForTest();
    probes.clear();
    routes = _Routes();
    TvSectionShell.sessionControllerFactoryForTesting = (_, _) => session = _Session();
    TvSectionShell.sectionBuilderForTesting = (_, tab, key) {
      probes[tab] = key;
      return _Probe(key: key, tab: tab);
    };
  });
  tearDown(() {
    router.queue.dispose();
    router.updaterOverride = null;
    profileNavigationRegistry.detachNavigator(rootNavigatorKey);
    TvSectionShell.sectionBuilderForTesting = null;
    TvSectionShell.sessionControllerFactoryForTesting = null;
  });
  testWidgets('real live shell makes queued router ready; links use sections even with N1 off', (tester) async {
    expect(router.queue.isReady(), isFalse);
    router.claim('plezytv://screen/settings');
    await mount(tester);
    expect(receiver.navigationOwner, same(shell(tester)));
    expect(router.queue.isReady(), isTrue);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(shell(tester).currentSection.tab, NavigationTabId.settings);
    for (final entry in {
      'home': NavigationTabId.discover,
      'libraries': NavigationTabId.libraries,
      'downloads': NavigationTabId.downloads,
      'search': NavigationTabId.search,
      'settings': NavigationTabId.settings,
    }.entries) {
      await link(tester, entry.key);
      expect(shell(tester).currentSection, TvShellSection.tab(entry.value));
    }
    expect(SettingsService.instance.read(TvSettings.showDownloads), isFalse);
    await link(tester, 'library?id=1&server=s1');
    expect(shell(tester).currentSection, TvShellSection.library(movies.globalKey));
    expect(probe(NavigationTabId.libraries).loads, [movies.globalKey]);
    await link(tester, 'search?q=the%20matrix');
    expect(probe(NavigationTabId.search).query, 'the matrix');
    // A missing item is resolved without disturbing the current section.
    await link(tester, 'item?id=999&server=s1');
    expect(shell(tester).currentSection, search);
    router.claim('plezytv://screen/item?id=123&server=s1');
    // Drain resolution without painting the upstream details page: inspect the
    // real pushed route, then remove it before unrelated details services start.
    await tester.idle();
    final route = routes.last! as MaterialPageRoute<dynamic>;
    final page = route.builder(rootNavigatorKey.currentContext!) as MediaDetailScreen;
    expect(page.metadata.id, '123');
    expect(page.metadata.serverId, 's1');
    rootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
  });
  testWidgets('companion commands enter through provider; offline availability and disposal', (tester) async {
    await mount(tester);
    Future<void> command(RemoteCommandType type, [Map<String, dynamic>? data]) async {
      companion.onCommandReceived!(RemoteCommand(type: type, data: data));
      await tester.pumpAndSettle();
    }

    for (final entry in {
      RemoteCommandType.tabLibraries: NavigationTabId.libraries,
      RemoteCommandType.tabDownloads: NavigationTabId.downloads,
      RemoteCommandType.tabSettings: NavigationTabId.settings,
      RemoteCommandType.tabSearch: NavigationTabId.search,
      RemoteCommandType.tabDiscover: NavigationTabId.discover,
    }.entries) {
      await command(entry.key);
      expect(shell(tester).currentSection.tab, entry.value);
    }
    await command(RemoteCommandType.tabNext);
    expect(shell(tester).currentSection.tab, NavigationTabId.libraries);
    await command(RemoteCommandType.tabPrevious);
    expect(shell(tester).currentSection, home);
    await command(RemoteCommandType.search, {'query': '  matrix  '});
    expect(probe(NavigationTabId.search).query, 'matrix');
    session.offline(true);
    await tester.pumpAndSettle();
    await command(RemoteCommandType.home);
    expect(shell(tester).currentSection, const TvShellSection.noConnection());
    await command(RemoteCommandType.tabLibraries);
    expect(shell(tester).currentSection, const TvShellSection.noConnection());
    await command(RemoteCommandType.tabDownloads);
    expect(shell(tester).currentSection.tab, NavigationTabId.downloads);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(companion.onCommandReceived, isNull);
    expect(receiver.navigationOwner, isNull);
    expect([
      receiver.onHome,
      receiver.onTabNext,
      receiver.onTabPrevious,
      receiver.onTabDiscover,
      receiver.onTabLibraries,
      receiver.onTabSearch,
      receiver.onTabDownloads,
      receiver.onTabSettings,
      receiver.onSearchAction,
    ], everyElement(isNull));
    expect(router.queue.isReady(), isFalse);
  });
  testWidgets('update link checks through real ready shell; startup trigger observes same readiness', (tester) async {
    final service = _Update(await SharedPreferences.getInstance());
    final updater = PlezyTvUpdater(service: () async => service, enabledForChecks: () => true);
    router.updaterOverride = updater;
    var ready = 0;
    final trigger = UpdateStartupTrigger(
      enabled: true,
      isReady: router.queue.isReady,
      fire: () {
        ready++;
        updater.check(() => (receiver.navigationOwner as State).context, automatic: true);
      },
    );
    addTearDown(trigger.dispose);
    await tester.pump(const Duration(seconds: 1));
    expect(service.checks, isEmpty);
    await mount(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(ready, 1);
    expect(service.checks, [true]);
    service.gate.complete(null);
    await tester.pump();
    await link(tester, 'update');
    expect(service.checks, [true, false]);
    expect(find.byType(AlertDialog), findsOneWidget);
    rootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(ready, 1);
  });
}
