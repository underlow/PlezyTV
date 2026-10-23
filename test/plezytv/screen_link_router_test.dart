import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plezy/main.dart' show rootNavigatorKey;
import 'package:plezy/navigation/profile_navigation_scope.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/plezytv/screen_links/screen_link_router.dart';
import 'package:plezy/providers/offline_mode_provider.dart';
import 'package:plezy/services/companion_remote/companion_remote_receiver.dart';

class _OfflineMode extends ChangeNotifier implements OfflineModeProvider {
  bool offline = false;
  @override
  bool get isOffline => offline;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _library = MediaLibrary(id: '42', backend: MediaBackend.plex, title: 'Movies', serverId: 'b');

class _Client implements MediaServerClient {
  _Client(this.libraries);
  final List<MediaLibrary> libraries;
  @override
  Future<List<MediaLibrary>> fetchLibraries() async => libraries;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Servers extends ChangeNotifier implements MultiServerProvider {
  bool connected = false;
  @override
  bool get hasConnectedServers => connected;
  @override
  List<String> get onlineServerIds => connected ? ['a', 'b'] : [];
  @override
  MediaServerClient? getClientForServer(ServerId serverId) => _Client(serverId == ServerId('b') ? [_library] : []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Libraries extends ChangeNotifier implements LibrariesProvider {
  @override
  bool get isLoading => false;
  @override
  List<MediaLibrary> get libraries => [_library];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Owner extends StatefulWidget {
  const _Owner({this.selectLibrary});
  final void Function(String)? selectLibrary;
  @override
  State<_Owner> createState() => _OwnerState();
}

class _OwnerState extends State<_Owner> {
  @override
  void initState() {
    super.initState();
    CompanionRemoteReceiver.instance.navigationOwner = this;
  }

  @override
  Widget build(BuildContext context) => MainScreenFocusScope(
    focusSidebar: () {},
    sideNavigationWidth: 0,
    selectLibrary: widget.selectLibrary,
    child: const Scaffold(body: Text('main')),
  );
}

void main() {
  final receiver = CompanionRemoteReceiver.instance;
  final router = ScreenLinkRouter.instance;
  tearDown(() {
    router.queue.dispose();
    receiver.navigationOwner = null;
    receiver.onHome = null;
    receiver.onTabLibraries = null;
    receiver.onTabSearch = null;
    receiver.onSearchAction = null;
    receiver.onTabDownloads = null;
    receiver.onTabSettings = null;
    profileNavigationRegistry.detachNavigator(rootNavigatorKey);
  });

  testWidgets('real target table routes tabs and query through registered callbacks', (tester) async {
    final offline = _OfflineMode();
    addTearDown(offline.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<OfflineModeProvider>.value(
        value: offline,
        child: MaterialApp(navigatorKey: rootNavigatorKey, home: const _Owner()),
      ),
    );
    profileNavigationRegistry.attachNavigator(rootNavigatorKey);
    final actions = <String>[];
    receiver.onHome = () => actions.add('home');
    receiver.onTabLibraries = () => actions.add('libraries');
    receiver.onTabSearch = () => actions.add('search');
    receiver.onSearchAction = (q) => actions.add('search:$q');
    receiver.onTabDownloads = () => actions.add('downloads');
    receiver.onTabSettings = () => actions.add('settings');
    for (final target in ['home', 'libraries', 'search', 'search?q=the%20matrix', 'downloads', 'settings']) {
      expect(router.claim('plezytv://screen/$target'), isTrue);
      await tester.pump();
    }
    expect(actions, ['home', 'libraries', 'search', 'search:the matrix', 'downloads', 'settings']);

    // Invalid and unavailable targets do not dismiss an existing detail route.
    rootNavigatorKey.currentState!.push<void>(MaterialPageRoute(builder: (_) => const Text('detail')));
    await tester.pumpAndSettle();
    for (final target in ['foo', 'update', 'library', 'item']) {
      router.claim('plezytv://screen/$target');
      await tester.pump();
      expect(find.text('detail'), findsOneWidget);
    }
    offline.offline = true;
    router.claim('plezytv://screen/libraries');
    await tester.pump();
    expect(find.text('detail'), findsOneWidget);
    expect(actions.length, 6);

    router.claim('plezytv://screen/settings');
    await tester.pumpAndSettle();
    expect(find.text('main'), findsOneWidget);
    expect(actions.last, 'settings');
  });

  testWidgets('library waits for connection then uses normal screen selection on first resolving server', (
    tester,
  ) async {
    final offline = _OfflineMode();
    final servers = _Servers();
    final libraries = _Libraries();
    addTearDown(offline.dispose);
    addTearDown(servers.dispose);
    addTearDown(libraries.dispose);
    final selected = <String>[];
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<OfflineModeProvider>.value(value: offline),
          ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
          ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
        ],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: _Owner(selectLibrary: selected.add),
        ),
      ),
    );
    profileNavigationRegistry.attachNavigator(rootNavigatorKey);
    receiver.onHome = () {};
    receiver.onTabSettings = () {};
    router.claim('plezytv://screen/library?id=42');
    await tester.pump();
    expect(selected, isEmpty);
    servers.connected = true;
    await tester.pump(const Duration(milliseconds: 250));
    expect(selected, [_library.globalKey]);
    expect(find.text('main'), findsOneWidget);
    router.claim('plezytv://screen/library?id=42&server=bogus');
    await tester.pump();
    router.claim('plezytv://screen/library?id=999999');
    await tester.pump();
    expect(selected, [_library.globalKey]);
    expect(find.text('main'), findsOneWidget);
  });

  testWidgets('pending latest link survives six minutes before callbacks register', (tester) async {
    final offline = _OfflineMode();
    addTearDown(offline.dispose);
    router.claim('plezytv://screen/home');
    router.claim('plezytv://screen/settings');
    await tester.pump(const Duration(minutes: 6));
    await tester.pumpWidget(
      ChangeNotifierProvider<OfflineModeProvider>.value(
        value: offline,
        child: MaterialApp(navigatorKey: rootNavigatorKey, home: const _Owner()),
      ),
    );
    profileNavigationRegistry.attachNavigator(rootNavigatorKey);
    final actions = <String>[];
    receiver.onHome = () => actions.add('home');
    receiver.onTabSettings = () => actions.add('settings');
    await tester.pump(const Duration(milliseconds: 250));
    expect(actions, ['settings']);
  });
}
