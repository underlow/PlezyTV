import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_side_menu.dart';
import 'package:plezy/plezytv/tv_ui/shell/tv_section_shell.dart';
import 'package:plezy/plezytv/tv_ui/shell/tv_shell_section.dart';
import 'package:plezy/plezytv/tv_ui/tv_strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/plezytv/tv_ui/shell/tv_shell_session_controller.dart';
import 'package:plezy/profiles/active_profile_binder.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/profiles/plex_home_service.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/providers/account_preferences_controller.dart';
import 'package:plezy/providers/download_provider.dart';
import 'package:plezy/providers/hidden_libraries_provider.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/offline_mode_provider.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import 'package:plezy/screens/main_screen.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/offline_watch_sync_service.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/system_shelf_service.dart';
import 'package:plezy/watch_together/watch_together.dart';

import '../../test_helpers/prefs.dart';

class _Active extends ChangeNotifier implements ActiveProfileProvider {
  @override
  bool isBinding = false;
  @override
  Profile? active;
  @override
  String? get activeId => active?.id;
  @override
  List<Profile> profiles = [];
  @override
  bool get hasMultipleProfiles => profiles.length > 1;
  @override
  Future<void> initialize() async {}
  void emit() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Binder implements ActiveProfileBinder {
  int starts = 0, rebinds = 0;
  @override
  void start({bool allowInitialPinPrompt = true}) => starts++;
  @override
  Future<void> rebindActive() async {
    rebinds++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manager implements MultiServerManager {
  final events = StreamController<Map<String, bool>>.broadcast(sync: true);
  Future<void> close() => events.close();
  final clients = <String, MediaServerClient>{};
  Future<void> Function()? reconnect;
  Completer<void>? healthGate;
  int healthChecks = 0;
  @override
  Stream<Map<String, bool>> get statusStream => events.stream;
  @override
  Map<String, MediaServerClient> get onlineClients => clients;
  @override
  List<String> get onlineServerIds => clients.keys.toList();
  @override
  List<String> get offlineServerIds => ['offline'];
  @override
  List<String> get serverIds => ['known'];
  @override
  Future<void> checkServerHealth() async {
    healthChecks++;
    await healthGate?.future;
  }

  @override
  Future<void> reconnectOfflineServers({bool forceRediscovery = false}) async {
    expect(forceRediscovery, isTrue);
    await reconnect?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Aggregation implements DataAggregationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Servers extends ChangeNotifier implements MultiServerProvider {
  _Servers(this.serverManager);
  @override
  final _Manager serverManager;
  @override
  bool hasConnectedServers = true;
  @override
  bool get hasLiveTv => false;
  @override
  int get totalServerCount => 1;
  @override
  List<({String displayName, ServerId serverId})> get authErrorServers => [];
  @override
  List<({String displayName, ServerId serverId})> get accessDeniedServers => [];
  @override
  DataAggregationService get aggregationService => _Aggregation();
  void emit() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Offline extends ChangeNotifier implements OfflineModeProvider {
  @override
  bool isOffline = false;
  void emit() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home implements PlexHomeService {
  int starts = 0;
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Preferences implements AccountPreferencesController {
  int loads = 0;
  @override
  Future<void> ensureActiveLoaded() async {
    loads++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Libraries extends ChangeNotifier implements LibrariesProvider {
  _Libraries(this.log);
  @override
  List<MediaLibrary> get libraries => [];
  @override
  LibrariesLoadState get loadState => LibrariesLoadState.loaded;
  final List<String> log;
  Completer<void>? gate;
  @override
  void initialize(DataAggregationService service) {
    log.add('initialize');
  }

  @override
  Future<void> loadLibraries() async {
    log.add('load');
    await gate?.future;
    log.add('loaded');
  }

  @override
  Future<void> refresh() async {
    log.add('librariesRefresh');
  }

  @override
  void clear() {
    log.add('clearLibraries');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Hidden extends ChangeNotifier implements HiddenLibrariesProvider {
  @override
  Set<String> get hiddenLibraryKeys => {};
  @override
  Future<void> refresh() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Playback implements PlaybackStateProvider {
  @override
  void clearShuffle() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Downloads implements DownloadProvider {
  int resumes = 0, metadataRefreshes = 0;
  final collections = <Set<String>>[];
  @override
  Future<void> ensureInitialized() async {}
  @override
  Future<void> refreshMetadataFromCache() async {
    metadataRefreshes++;
  }

  @override
  void resumeQueuedDownloads(MediaServerClient client) {
    resumes++;
  }

  @override
  Future<void> syncDownloadCollections(MultiServerManager manager, Iterable<String> ids) async {
    collections.add(ids.toSet());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements OfflineWatchSyncService {
  @override
  void onServersConnected() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements MediaServerClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Shelf implements SystemShelfService {
  @override
  ValueChanged<String>? onShelfItemTap;
  int coldReads = 0;
  @override
  Future<String?> getInitialDeepLink() async {
    coldReads++;
    return 'cold';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Watch implements WatchTogetherProvider {
  @override
  Future<bool> Function(WatchCopy)? navigatorOpener;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile profile(String id) => Profile.local(id: id, displayName: id, createdAt: DateTime(2026));

class _Harness {
  final active = _Active(), binder = _Binder(), manager = _Manager(), offline = _Offline();
  final home = _Home(), preferences = _Preferences(), downloads = _Downloads();
  final shelf = _Shelf(), watch = _Watch();
  final log = <String>[];
  late final libraries = _Libraries(log);
  late final servers = _Servers(manager);
  late TvShellSessionController controller;
  bool video = false, companion = false;
  int pickers = 0, seerr = 0, hostStarts = 0, updates = 0;
  DateTime now = DateTime(2026);

  TvShellSessionController create({bool offlineStart = false, bool handled = true}) {
    manager.clients['a'] = _Client();
    controller = TvShellSessionController(
      activeProfile: active,
      binder: binder,
      multiServer: servers,
      offlineMode: offline,
      plexHome: home,
      preferences: preferences,
      libraries: libraries,
      hiddenLibraries: _Hidden(),
      playbackState: _Playback(),
      downloads: downloads,
      watchSync: _Sync(),
      onContentIntent: (intent) => log.add(intent.name),
      hasConnections: () async => false,
      settleSession: () async {},
      pushProfileSelection: () async {
        pickers++;
      },
      refreshSeerrUser: () async {
        seerr++;
      },
      hasActiveVideoPlayback: () => video,
      hasActiveCompanionSession: () => companion,
      isMobilePlatform: true,
      isRemoteHost: true,
      startCompanionHost: () async {
        hostStarts++;
      },
      checkForUpdates: () async {
        updates++;
      },
      supportsShelf: true,
      launchLiveTv: (link) async {
        log.add('live:${link.channel}');
      },
      openShelfContent: (id) async {
        log.add('shelf:$id');
      },
      watchTogether: watch,
      openWatchTogether: (_) async => true,
      systemShelf: shelf,
      clearVolatileCache: () async {
        log.add('clearCache');
      },
      isOfflineMode: offlineStart,
      initialPromptHandled: handled,
      contentResumeGate: ContentRefreshResumeGate(now: () => now),
    );
    addTearDown(() async {
      if (!controller.isDisposed) controller.dispose();
      servers.dispose();
      active.dispose();
      offline.dispose();
      await manager.close();
    });
    return controller;
  }

  void backgroundAndResume({bool stale = false}) {
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    if (stale) now = now.add(const Duration(minutes: 6));
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
  }
}

Future<void> flush(WidgetTester tester) => tester.pump();

void main() {
  setUp(resetSharedPreferencesForTest);

  testWidgets('already-offline provider starts at No connection despite online launch flag', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.startupSection, NavigationTabId.downloads);
    final h = _Harness();
    h.offline.isOffline = true;
    h.servers.hasConnectedServers = false;
    final c = h.create(offlineStart: false);
    final hidden = _Hidden();
    final shell = GlobalKey<TvSectionShellState>();
    TvSectionShell.sessionControllerFactoryForTesting = (_, _) => c;
    TvSectionShell.sectionBuilderForTesting = (_, tab, key) => SizedBox(key: key);
    addTearDown(() {
      TvSectionShell.sessionControllerFactoryForTesting = null;
      TvSectionShell.sectionBuilderForTesting = null;
      hidden.dispose();
      h.libraries.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibrariesProvider>.value(value: h.libraries),
          ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
          ChangeNotifierProvider<MultiServerProvider>.value(value: h.servers),
        ],
        child: MaterialApp(home: TvSectionShell(key: shell, isOfflineMode: false, initialPromptHandled: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, const TvShellSection.noConnection());
    expect(find.text(TvStrings.noConnection), findsOneWidget);
    final retry = tester.widget<TvButton>(find.widgetWithText(TvButton, TvStrings.retry));
    expect(retry.focusNode!.hasFocus, isTrue);
    expect(tester.widget<TvSideMenu>(find.byType(TvSideMenu)).items.map((item) => item.label), [t.common.settings]);
    expect(h.home.starts, 0);
    expect(h.preferences.loads, 0);
    expect(h.downloads.resumes, 0);
    expect(h.hostStarts, 0);
    expect(h.updates, 0);
    expect(h.shelf.coldReads, 1);
    expect(h.shelf.onShelfItemTap, isNotNull);
    expect(h.watch.navigatorOpener, isNotNull);

    h.servers.hasConnectedServers = true;
    h.offline.isOffline = false;
    h.offline.emit();
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, const TvShellSection.tab(NavigationTabId.downloads));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settled binding primes once, libraries finish before initial intent', (tester) async {
    final h = _Harness();
    final c = h.create();
    h.active.isBinding = true;
    h.libraries.gate = Completer<void>();
    await c.start();
    expect(h.log, isNot(contains('load')));
    h.active.isBinding = false;
    h.active.emit();
    await flush(tester);
    expect(h.log, contains('load'));
    expect(h.log, isNot(contains('initialLoad')));
    h.libraries.gate!.complete();
    await flush(tester);
    expect(h.log.indexOf('loaded'), lessThan(h.log.indexOf('initialLoad')));
    h.active.emit();
    await c.start();
    await flush(tester);
    expect(h.log.where((e) => e == 'initialLoad'), hasLength(1));
  });

  testWidgets('binding timeout primes provisionally then once on real settle', (tester) async {
    final h = _Harness();
    final c = h.create();
    h.active.isBinding = true;
    await c.start();
    await tester.pump(const Duration(seconds: 15));
    expect(h.log.where((e) => e == 'initialLoad'), hasLength(1));
    h.active.isBinding = false;
    h.active.emit();
    await flush(tester);
    expect(h.log.where((e) => e == 'initialLoad'), hasLength(2));
    h.active.emit();
    await tester.pump(const Duration(seconds: 30));
    expect(h.log.where((e) => e == 'initialLoad'), hasLength(2));
  });

  testWidgets('each newly online server resumes downloads including reconnects', (tester) async {
    final h = _Harness();
    final c = h.create();
    await c.start();
    await flush(tester);
    expect(h.downloads.resumes, 1);
    h.manager.events.add({});
    await flush(tester);
    expect(h.downloads.resumes, 1);
    h.manager.clients['b'] = _Client();
    h.manager.events.add({});
    await flush(tester);
    expect(h.downloads.collections.last, {'b'});
    h.manager.clients.remove('b');
    h.manager.events.add({});
    await flush(tester);
    h.manager.clients['b'] = _Client();
    h.manager.events.add({});
    await flush(tester);
    expect(h.downloads.resumes, 3);
  });

  testWidgets('initialPromptHandled also suppresses late profile arrival', (tester) async {
    final h = _Harness();
    final c = h.create();
    await c.start();
    h.active.profiles = [profile('a'), profile('b')];
    h.active.emit();
    await flush(tester);
    expect(h.pickers, 0);
  });

  testWidgets('late profiles prompt when initial prompt was not handled', (tester) async {
    final h = _Harness();
    final c = h.create(handled: false);
    await c.start();
    h.active.profiles = [profile('a'), profile('b')];
    h.active.emit();
    await flush(tester);
    expect(h.pickers, 1);
  });

  testWidgets('same-profile rebind clears libraries before full reset', (tester) async {
    final h = _Harness();
    h.active.active = profile('a');
    final c = h.create();
    await c.start();
    await flush(tester);
    h.log.clear();
    h.active.isBinding = true;
    h.active.emit();
    h.active.isBinding = false;
    h.active.emit();
    await flush(tester);
    expect(h.log, ['clearCache', 'clearLibraries', 'initialize', 'librariesRefresh', 'fullReset']);
    h.log.clear();
    h.active.active = profile('b');
    h.active.emit();
    await flush(tester);
    expect(h.log, isEmpty); // ID change remounts the session, as upstream policy specifies.
  });

  testWidgets('stale resume emits refresh, not initial load; video suppresses refresh', (tester) async {
    final h = _Harness();
    final c = h.create();
    await c.start();
    await flush(tester);
    h.log.clear();
    h.backgroundAndResume(stale: true);
    await flush(tester);
    expect(h.log, ['refreshAfterResume']);
    expect(h.seerr, 1);
    h.log.clear();
    h.video = true;
    h.backgroundAndResume(stale: true);
    await flush(tester);
    expect(h.log, isEmpty);
    expect(h.seerr, 2);
  });

  testWidgets('resume prompt uses setting, multiple profiles, playback and companion guards', (tester) async {
    final h = _Harness();
    h.active.profiles = [profile('a'), profile('b')];
    final c = h.create();
    await c.start();
    final prefs = await SettingsService.getInstance();
    await prefs.write(SettingsService.requireProfileSelectionOnOpen, true);
    h.backgroundAndResume();
    await flush(tester);
    expect(h.pickers, 1);
    h.video = true;
    h.backgroundAndResume();
    await flush(tester);
    expect(h.pickers, 1);
    h.video = false;
    h.companion = true;
    h.backgroundAndResume();
    await flush(tester);
    expect(h.pickers, 1);
    h.companion = false;
    h.active.profiles = [profile('a')];
    h.backgroundAndResume();
    await flush(tester);
    expect(h.pickers, 1);
    h.active.profiles = [profile('a'), profile('b')];
    await prefs.write(SettingsService.requireProfileSelectionOnOpen, false);
    h.backgroundAndResume();
    await flush(tester);
    expect(h.pickers, 1);
    c.didChangeAppLifecycleState(AppLifecycleState.inactive);
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await flush(tester);
    expect(h.pickers, 1);
  });

  testWidgets('shelf registers and reads cold link; watch opener ownership cleans up', (tester) async {
    final h = _Harness();
    final c = h.create();
    await c.start();
    await flush(tester);
    expect(h.shelf.coldReads, 1);
    expect(h.log, contains('shelf:cold'));
    h.shelf.onShelfItemTap!('warm');
    await flush(tester);
    expect(h.log, contains('shelf:warm'));
    h.shelf.onShelfItemTap!('plezytv://live?channel=4.1');
    await flush(tester);
    expect(h.log, contains('live:4.1'));
    expect(h.log, isNot(contains('shelf:plezytv://live?channel=4.1')));
    expect(h.watch.navigatorOpener, isNotNull);
    c.dispose();
    expect(h.watch.navigatorOpener, isNull);
    expect(h.shelf.onShelfItemTap, isNull);
  });

  testWidgets('dispose preserves replacement callbacks and cancels delayed prime', (tester) async {
    final h = _Harness();
    final c = h.create();
    h.active.isBinding = true;
    await c.start();
    Future<bool> replacement(WatchCopy _) async => false;
    void shelfReplacement(String _) {}
    h.watch.navigatorOpener = replacement;
    h.shelf.onShelfItemTap = shelfReplacement;
    c.dispose();
    h.log.clear();
    await tester.pump(const Duration(seconds: 20));
    expect(h.log, isEmpty);
    expect(h.watch.navigatorOpener, replacement);
    expect(h.shelf.onShelfItemTap, shelfReplacement);
    expect(await c.retry(), isNull);
  });

  testWidgets('offline startup skips network priming, links, watch, companion and updates', (tester) async {
    final h = _Harness();
    final c = h.create(offlineStart: true);
    h.servers.hasConnectedServers = false;
    h.manager.clients.clear();
    await c.start();
    await tester.pump(const Duration(seconds: 20));
    expect(c.isOffline, isTrue);
    expect(h.home.starts, 0);
    expect(h.preferences.loads, 0);
    expect(h.log, isEmpty);
    expect(h.downloads.resumes, 0);
    expect(h.shelf.coldReads, 0);
    expect(h.shelf.onShelfItemTap, isNull);
    expect(h.watch.navigatorOpener, isNull);
    expect(h.hostStarts, 0);
    expect(h.updates, 0);
    expect(h.binder.starts, 1); // Idempotent binder monitoring still starts upstream.
  });

  testWidgets('retry joins no duplicate work, reports failure, then transitions online', (tester) async {
    final h = _Harness();
    final c = h.create(offlineStart: true);
    h.servers.hasConnectedServers = false;
    h.manager.clients.clear();
    await c.start();
    h.manager.healthGate = Completer<void>();
    final first = c.retry();
    expect(c.isReconnecting, isTrue);
    expect(await c.retry(), isNull);
    expect(h.manager.healthChecks, 1);
    h.manager.healthGate!.complete();
    expect(await first, isFalse);
    expect(c.isReconnecting, isFalse);
    h.manager.reconnect = () async {
      h.servers.hasConnectedServers = true;
      h.manager.clients['a'] = _Client();
    };
    expect(await c.retry(), isTrue);
    await flush(tester);
    expect(c.isOffline, isFalse);
    expect(h.home.starts, 1);
    expect(h.log, contains('initialLoad'));
  });

  testWidgets('configured companion and update startup only execute once', (tester) async {
    final prefs = await SettingsService.getInstance();
    await prefs.write(SettingsService.enableCompanionRemoteServer, true);
    await prefs.write(SettingsService.autoCheckUpdatesOnStartup, true);
    final h = _Harness();
    final c = h.create();
    await c.start();
    await c.start();
    await flush(tester);
    expect(h.hostStarts, 1);
    expect(h.updates, 1);
  });
  testWidgets('disabled startup settings do not start companion or updater', (tester) async {
    final prefs = await SettingsService.getInstance();
    await prefs.write(SettingsService.enableCompanionRemoteServer, false);
    await prefs.write(SettingsService.autoCheckUpdatesOnStartup, false);
    final h = _Harness();
    await h.create().start();
    await flush(tester);
    expect(h.hostStarts, 0);
    expect(h.updates, 0);
  });

  testWidgets('retry rebinds a profile hidden by a stale visibility filter', (tester) async {
    final h = _Harness();
    h.active.active = profile('a');
    final c = h.create(offlineStart: true);
    h.servers.hasConnectedServers = false;
    await c.start();
    expect(await c.retry(), isFalse);
    expect(h.binder.rebinds, 1);
  });

  testWidgets('failed retry errors reset busy state; disposal ignores its completion', (tester) async {
    final h = _Harness();
    final c = h.create(offlineStart: true);
    h.servers.hasConnectedServers = false;
    await c.start();
    h.manager.reconnect = () async {
      throw StateError('unreachable');
    };
    expect(await c.retry(), isFalse);
    expect(c.isReconnecting, isFalse);
    h.manager.healthGate = Completer<void>();
    final retry = c.retry();
    c.dispose();
    h.manager.healthGate!.complete();
    expect(await retry, isNull);
  });

  testWidgets('in-flight library completion cannot emit intents after disposal', (tester) async {
    final h = _Harness();
    final c = h.create();
    h.libraries.gate = Completer<void>();
    await c.start();
    c.dispose();
    h.log.clear();
    h.libraries.gate!.complete();
    await flush(tester);
    expect(h.log, ['loaded']);
    expect(h.downloads.metadataRefreshes, 0);
  });
  testWidgets('visible server arrival ends optimistic offline startup without retry', (tester) async {
    final h = _Harness();
    final c = h.create(offlineStart: true);
    h.servers.hasConnectedServers = false;
    h.manager.clients.clear();
    await c.start();
    expect(c.isOffline, isTrue);
    h.servers.hasConnectedServers = true;
    h.manager.clients['a'] = _Client();
    h.servers.emit();
    await flush(tester);
    expect(c.isOffline, isFalse);
    expect(h.log, contains('initialLoad'));
  });
}
