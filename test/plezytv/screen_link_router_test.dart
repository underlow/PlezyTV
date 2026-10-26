import 'package:plezy/plezytv/settings_transfer/settings_transfer_service.dart';
import 'package:plezy/services/settings_export_service.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/storage_service.dart';
import '../test_helpers/prefs.dart';
import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plezy/plezytv/update/updater.dart';
import 'package:plezy/plezytv/update/update_service.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:plezy/screens/profile/profile_switch_screen.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
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
  _Client(this.libraries, this.fetchGate, this.fetched);
  final void Function() fetched;
  final Future<void>? fetchGate;
  final List<MediaLibrary> libraries;
  @override
  Future<List<MediaLibrary>> fetchLibraries() async {
    fetched();
    await fetchGate;
    return libraries;
  }

  @override
  Future<MediaItem?> fetchItem(String id) async {
    fetched();
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Servers extends ChangeNotifier implements MultiServerProvider {
  final calls = <String, int>{};
  bool connected = false;
  List<String> online = ['a', 'b'];
  Future<void>? fetchGate;
  @override
  List<String> get expectedServerIds => ['a', 'b'];
  @override
  bool get hasConnectedServers => connected;
  @override
  List<String> get onlineServerIds => connected ? online : [];
  @override
  MediaServerClient? getClientForServer(ServerId serverId) =>
      _Client(serverId == ServerId('b') ? [_library] : [], fetchGate, () {
        calls.update(serverId.value, (n) => n + 1, ifAbsent: () => 1);
      });
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Libraries extends ChangeNotifier implements LibrariesProvider {
  @override
  bool get isLoading => false;
  LibrariesLoadState state = LibrariesLoadState.loaded;
  @override
  LibrariesLoadState get loadState => state;
  List<MediaLibrary> visible = [_library];
  Future<void>? mergeGate;
  @override
  Future<void> syncToOnlineServers(Set<String> ids) async {
    await mergeGate;
  }

  @override
  List<MediaLibrary> get libraries => visible;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Keep the real picker widget type while avoiding unrelated profile UI dependencies.
class _Picker extends ProfileSwitchScreen {
  const _Picker() : super(requireSelection: true);
  @override
  State<ProfileSwitchScreen> createState() => _PickerState();
}

class _PickerState extends State<ProfileSwitchScreen> {
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('picker'));
}

class _Profile extends ChangeNotifier implements ActiveProfileProvider {
  bool binding = false;
  @override
  bool get isBinding => binding;
  @override
  bool get isInitialized => true;
  @override
  String? get activeId => 'profile';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Owner extends StatefulWidget {
  const _Owner({super.key, this.selectLibrary});
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
    router.updaterOverride = null;
    router.transferOverride = null;
    receiver.navigationOwner = null;
    receiver.onHome = null;
    receiver.onTabLibraries = null;
    receiver.onTabSearch = null;
    receiver.onSearchAction = null;
    receiver.onTabDownloads = null;
    receiver.onTabSettings = null;
    profileNavigationRegistry.detachNavigator(rootNavigatorKey);
  });

  Future<void> mount(WidgetTester tester, _Servers servers, _Libraries libraries, List<String> selected) async {
    final offline = _OfflineMode();
    addTearDown(offline.dispose);
    addTearDown(servers.dispose);
    addTearDown(libraries.dispose);
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
  }

  testWidgets('settings import waits for profile and reports applied key count', (tester) async {
    await mount(tester, _Servers(), _Libraries(), []);
    final transfer = _SuccessfulTransfer();
    router.transferOverride = transfer;
    rootNavigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const _Picker()));
    await tester.pumpAndSettle();
    router.claim('plezytv://settings/import');
    await tester.pump(const Duration(seconds: 1));
    expect(transfer.calls, 0);
    rootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
    expect(transfer.calls, 1);
    expect(MemoryLogOutput.getLogs().any((e) => e.message.contains('Settings import: 3 keys imported')), true);
    expect(find.textContaining('Settings import: 3 keys imported'), findsOneWidget);
  });

  testWidgets('settings export calls transport and reports key count and path', (tester) async {
    await mount(tester, _Servers(), _Libraries(), []);
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('s4-export-link-')))!;
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/plezytv-settings.json');
    router.transferOverride = _ExportTransfer(file);
    MemoryLogOutput.clearLogs();
    await tester.runAsync(() async {
      router.claim('plezytv://settings/export');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(MemoryLogOutput.getLogs().any((e) => e.message == 'Settings export: 2 keys, ${file.path}'), true);
    expect(find.text('Settings export: 2 keys, ${file.path}'), findsOneWidget);
  });

  testWidgets('invalid settings file reports cause and leaves preferences unchanged', (tester) async {
    resetSharedPreferencesForTest();
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setInt('seek_time_small', 42);
    await SettingsService.getInstance();
    await (await StorageService.getInstance()).setActiveProfileId('local-bob');
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('s4-link-')))!;
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/plezytv-settings.json');
    await tester.runAsync(() => file.writeAsString('{bad'));
    final before = {for (final key in prefs.keys) key: prefs.get(key)};
    await mount(tester, _Servers(), _Libraries(), []);
    router.transferOverride = _FileTransfer(file);
    MemoryLogOutput.clearLogs();
    await tester.runAsync(() async {
      router.claim('plezytv://settings/import');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect({for (final key in prefs.keys) key: prefs.get(key)}, before);
    expect(MemoryLogOutput.getLogs().any((e) => e.message.contains('Settings import failed:')), true);
    expect(find.textContaining('Settings import failed:'), findsOneWidget);
  });

  testWidgets('explicit missing item ignores unrelated offline server and warns once', (tester) async {
    final servers = _Servers()
      ..connected = true
      ..online = ['a'];
    await mount(tester, servers, _Libraries(), []);
    MemoryLogOutput.clearLogs();
    router.claim('plezytv://screen/item?id=999999&server=a');
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(servers.calls, {'a': 1});
    expect(
      MemoryLogOutput.getLogs().where((e) => e.message.contains('Screen link') && e.message.contains('not found')),
      hasLength(1),
    );
  });

  testWidgets('implicit lookup remembers answers while offline candidate waits', (tester) async {
    final servers = _Servers()
      ..connected = true
      ..online = ['a'];
    await mount(tester, servers, _Libraries(), []);
    MemoryLogOutput.clearLogs();
    router.claim('plezytv://screen/item?id=999999');
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(servers.calls, {'a': 1});
    expect(MemoryLogOutput.getLogs().where((e) => e.message.contains('Screen link')), isEmpty);
    servers.online = ['a', 'b'];
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(seconds: 1));
    expect(servers.calls, {'a': 1, 'b': 1});
    expect(
      MemoryLogOutput.getLogs().where((e) => e.message.contains('Screen link') && e.message.contains('not found')),
      hasLength(1),
    );
  });

  testWidgets('late server library waits for delta merge with isLoading false', (tester) async {
    final servers = _Servers()
      ..connected = true
      ..online = ['a'];
    final libraries = _Libraries()..visible = [];
    final gate = Completer<void>();
    libraries.mergeGate = gate.future;
    final selected = <String>[];
    await mount(tester, servers, libraries, selected);
    router.claim('plezytv://screen/library?id=42&server=b');
    await tester.pump();
    servers.online = ['a', 'b'];
    await tester.pump(const Duration(milliseconds: 250));
    expect(libraries.isLoading, isFalse);
    expect(selected, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(servers.calls, {'b': 1});
    libraries.visible = [_library];
    gate.complete();
    await tester.pump();
    expect(selected, [_library.globalKey]);
  });

  testWidgets('real update handler releases queue during held check', (tester) async {
    await mount(tester, _Servers(), _Libraries(), []);
    SharedPreferences.setMockInitialValues({});
    final service = _HeldUpdate(await SharedPreferences.getInstance());
    router.updaterOverride = PlezyTvUpdater(service: () async => service, enabledForChecks: () => true);
    var settings = 0;
    receiver.onTabSettings = () => settings++;
    router.claim('plezytv://screen/update');
    await tester.pump();
    expect(service.started, isTrue);
    router.claim('plezytv://screen/settings');
    await tester.pump();
    expect(settings, 1);
    service.gate.complete(null);
    await tester.pump();
    expect(find.byType(PlezyTvUpdateDialog), findsNothing);
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
    libraries.state = LibrariesLoadState.initial;
    servers.online = ['a'];
    await tester.pump(const Duration(milliseconds: 250));
    expect(selected, isEmpty);
    libraries.state = LibrariesLoadState.loaded;
    await tester.pump(const Duration(milliseconds: 250));
    expect(selected, isEmpty);
    router.claim('plezytv://screen/library?id=42&server=b');
    await tester.pump();
    expect(selected, isEmpty);
    servers.online = ['a', 'b'];
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

  testWidgets('binding keeps warm tab links pending until profile settles', (tester) async {
    final offline = _OfflineMode();
    addTearDown(offline.dispose);
    final profile = _Profile()..binding = true;
    addTearDown(profile.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: profile),
          ChangeNotifierProvider<OfflineModeProvider>.value(value: offline),
        ],
        child: MaterialApp(navigatorKey: rootNavigatorKey, home: const _Owner()),
      ),
    );
    profileNavigationRegistry.attachNavigator(rootNavigatorKey);
    var calls = 0;
    receiver.onHome = () {};
    receiver.onTabSettings = () => calls++;
    rootNavigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const _Picker()));
    await tester.pumpAndSettle();
    router.claim('plezytv://screen/settings');
    await tester.pump();
    expect(find.text('picker'), findsOneWidget);
    expect(calls, 0);
    profile.binding = false;
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, 0);
    expect(find.text('picker'), findsOneWidget);
    rootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('old owner fetch failure retries for replacement owner', (tester) async {
    final offline = _OfflineMode();
    final servers = _Servers()..connected = true;
    final libraries = _Libraries();
    addTearDown(offline.dispose);
    addTearDown(servers.dispose);
    addTearDown(libraries.dispose);
    final gate = Completer<void>();
    servers.fetchGate = gate.future;
    final selected = <String>[];
    Widget app(int owner) => MultiProvider(
      providers: [
        ChangeNotifierProvider<OfflineModeProvider>.value(value: offline),
        ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
        ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
      ],
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: _Owner(key: ValueKey(owner), selectLibrary: selected.add),
      ),
    );
    await tester.pumpWidget(app(1));
    profileNavigationRegistry.attachNavigator(rootNavigatorKey);
    receiver.onHome = () {};
    receiver.onTabSettings = () {};
    router.claim('plezytv://screen/library?id=42&server=b');
    await tester.pump();
    await tester.pumpWidget(app(2));
    servers.fetchGate = null;
    gate.completeError(StateError('old profile disconnected'));
    await tester.pump();
    expect(selected, isEmpty);
    await tester.pump(const Duration(milliseconds: 250));
    expect(selected, [_library.globalKey]);
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

class _HeldUpdate extends UpdateService {
  _HeldUpdate(SharedPreferences prefs)
    : super(
        version: '0.2.0',
        preferences: prefs,
        abi: () async => 'armeabi-v7a',
        cache: Directory.systemTemp,
        log: (_) {},
      );
  final gate = Completer<UpdateRelease?>();
  bool started = false;
  @override
  Future<UpdateRelease?> check({required bool automatic}) {
    started = true;
    return gate.future;
  }
}

class _SuccessfulTransfer extends SettingsTransferService {
  int calls = 0;
  @override
  Future<ImportResult> importAndApply(BuildContext context) async {
    calls++;
    return const ImportResult(keysImported: 3, keysSkipped: 1);
  }
}

class _FileTransfer extends SettingsTransferService {
  final File file;
  _FileTransfer(this.file);
  @override
  Future<File> settingsFile() async => file;
}

class _ExportTransfer extends SettingsTransferService {
  final File file;
  _ExportTransfer(this.file);
  @override
  Future<String> exportToFile() async {
    await file.writeAsString('{"prefs":{"a":{},"b":{}}}');
    return file.path;
  }
}
