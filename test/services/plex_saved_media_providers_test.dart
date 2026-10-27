import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/models/plex/plex_config.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/plex_client.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/utils/active_client_scope.dart';

import '../test_helpers/prefs.dart';

final server = ServerId('server');
PlexProfileScopeId scope(String profile) => PlexProfileScopeId(serverId: server, profileId: profile);
Map<String, dynamic> payload(List<String> names, {int time = 1, String hub = '/hubs'}) => {
  'MediaContainer': {
    'MediaProvider': [
      {
        'identifier': 'com.plexapp.plugins.library',
        'Feature': [
          {
            'type': 'content',
            'Directory': [
              {'hubKey': hub},
              for (var i = 0; i < names.length; i++)
                {'id': '${i + 1}', 'title': names[i], 'type': 'movie', 'updatedAt': time, 'scannedAt': time},
            ],
          },
        ],
      },
    ],
  },
};
http.Response response(Map<String, dynamic> data) =>
    http.Response(jsonEncode(data), 200, headers: {'content-type': 'application/json'});
Future<void> flush() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Aggregation implements DataAggregationService {
  _Aggregation(this.client);
  final PlexClient client;
  @override
  Future<LibraryAggregationResult> getMediaLibrariesFromAllServers({Set<String>? serverIds}) async => (
    libraries: await client.fetchLibraries(),
    succeededServerIds: {'server'},
    cancelledServerIds: <String>{},
    failedServerIds: <String>{},
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingStorage implements StorageService {
  @override
  Map<String, dynamic>? getMediaProviders(PlexProfileScopeId scope) => throw StateError('read failed');
  @override
  Future<void> saveMediaProviders(PlexProfileScopeId scope, Map<String, dynamic> response) async =>
      throw StateError('write failed');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(db.close);
  });

  Future<PlexClient> create(
    Future<http.Response> Function(http.Request) handler, {
    String profile = 'A',
    Future<StorageService> Function()? storage,
  }) async {
    final client = await PlexClient.create(
      PlexConfig(
        baseUrl: 'http://server:32400',
        token: profile,
        clientIdentifier: 'test',
        product: 'test',
        version: 'test',
      ),
      serverId: server,
      profileScopeId: scope(profile),
      seedTranscoderVideoSupport: true,
      storage: storage ?? StorageService.getInstance,
      httpClient: MockClient(handler),
    );
    addTearDown(client.close);
    return client;
  }

  testWidgets('A9 create uses saved sections without waiting for a ten second response', (tester) async {
    final storage = await StorageService.getInstance();
    await storage.saveMediaProviders(scope('A'), payload(['Saved', 'X']));
    PlexClient? client;
    unawaited(
      create(
        (_) => Future.delayed(const Duration(seconds: 10), () => response(payload(['Fresh']))),
      ).then((c) => client = c),
    );
    await tester.pump();
    expect(client, isNotNull);
    expect((await client!.fetchLibraries()).map((l) => l.title), ['Saved', 'X']);
    var notifications = 0;
    client!.mediaProvidersVersion.addListener(() => notifications++);
    await tester.pump(const Duration(seconds: 9));
    expect(notifications, 0);
    await tester.pump(const Duration(seconds: 1));
    expect((await client!.fetchLibraries()).map((l) => l.title), ['Fresh']);
    expect(notifications, 1);
    expect(storage.getMediaProviders(scope('A')), payload(['Fresh']));
  });

  test('A10 deleted section disappears from LibrariesProvider after refresh', () async {
    final storage = await StorageService.getInstance();
    await storage.saveMediaProviders(scope('A'), payload(['Keep', 'X']));
    final gate = Completer<http.Response>();
    final client = await create((_) => gate.future);
    final libraries = LibrariesProvider()..initialize(_Aggregation(client));
    addTearDown(libraries.dispose);
    await libraries.loadLibraries();
    expect(libraries.libraries.map((l) => l.title), ['Keep', 'X']);
    var notifications = 0;
    client.mediaProvidersVersion.addListener(() => notifications++);
    gate.complete(response(payload(['Keep'])));
    await flush();
    expect(notifications, 1);
    await libraries.refresh();
    expect(libraries.libraries.map((l) => l.title), ['Keep']);
  });

  test('A11 without saved sections create waits and persists the response', () async {
    final gate = Completer<http.Response>();
    var ready = false;
    final pending = create((_) => gate.future).then((c) {
      ready = true;
      return c;
    });
    await flush();
    expect(ready, isFalse);
    gate.complete(response(payload(['Fresh'])));
    final client = await pending;
    expect((await client.fetchLibraries()).single.title, 'Fresh');
    expect((await StorageService.getInstance()).getMediaProviders(scope('A')), payload(['Fresh']));
  });

  test('identical sections with changed timestamps do not notify', () async {
    final storage = await StorageService.getInstance();
    await storage.saveMediaProviders(scope('A'), payload(['Saved']));
    final gate = Completer<http.Response>();
    final client = await create((_) => gate.future);
    var count = 0;
    client.mediaProvidersVersion.addListener(() => count++);
    gate.complete(response(payload(['Saved'], time: 999)));
    await flush();
    expect(count, 0);
    expect(storage.getMediaProviders(scope('A')), payload(['Saved'], time: 999));
  });

  test('changed hub key notifies even with identical libraries', () async {
    final storage = await StorageService.getInstance();
    await storage.saveMediaProviders(scope('A'), payload(['Saved']));
    final gate = Completer<http.Response>();
    final client = await create((_) => gate.future);
    var count = 0;
    client.mediaProvidersVersion.addListener(() => count++);
    gate.complete(response(payload(['Saved'], hub: '/new-hubs')));
    await flush();
    expect(count, 1);
  });

  test('A12 saved sections are isolated by profile and server', () async {
    final storage = await StorageService.getInstance();
    await storage.saveMediaProviders(scope('A'), payload(['A']));
    await storage.saveMediaProviders(scope('B'), payload(['B']));
    final other = PlexProfileScopeId(serverId: ServerId('other'), profileId: 'A');
    expect(storage.getMediaProviders(other), isNull);
    final gate = Completer<http.Response>();
    final client = await create((_) => gate.future, profile: 'B');
    expect((await client.fetchLibraries()).single.title, 'B');
    gate.complete(response(payload(['B fresh'])));
    await flush();
    expect(storage.getMediaProviders(scope('A')), payload(['A']));
  });

  test('background HTTP error retains saved sections without notification', () async {
    final storage = await StorageService.getInstance();
    await storage.saveMediaProviders(scope('A'), payload(['Saved']));
    final gate = Completer<http.Response>();
    final client = await create((_) => gate.future);
    var count = 0;
    client.mediaProvidersVersion.addListener(() => count++);
    gate.complete(http.Response('failure', 500));
    await flush();
    expect((await client.fetchLibraries()).single.title, 'Saved');
    expect(count, 0);
    expect(storage.getMediaProviders(scope('A')), payload(['Saved']));
  });

  test('saved sections survive storage recreation, support deletion and clear on logout', () async {
    final first = await StorageService.getInstance();
    await first.saveMediaProviders(scope('A'), payload(['A']));
    await first.saveMediaProviders(scope('B'), payload(['B']));
    BaseSharedPreferencesService.resetForTesting();
    final second = await StorageService.getInstance();
    expect(identical(first, second), isFalse);
    expect(second.getMediaProviders(scope('A')), payload(['A']));
    await second.clearMediaProviders(scope('A'));
    expect(second.getMediaProviders(scope('A')), isNull);
    expect(second.getMediaProviders(scope('B')), payload(['B']));
    await second.clearMultiServerData();
    expect(second.getMediaProviders(scope('B')), isNull);
  });

  test('profile switch discards delayed old profile response without persisting it', () async {
    final storage = await StorageService.getInstance();
    await storage.saveMediaProviders(scope('A'), payload(['A saved']));
    final gate = Completer<http.Response>();
    final client = await create((request) async {
      if (request.url.path == '/') {
        return response({
          'MediaContainer': {'machineIdentifier': 'server'},
        });
      }
      if (request.headers['X-Plex-Token'] == 'B') return response(payload(['B fresh']));
      return gate.future;
    });
    expect(await client.applyProfileUpdate(newToken: 'B', newProfileScopeId: scope('B')), isTrue);
    var count = 0;
    client.mediaProvidersVersion.addListener(() => count++);
    gate.complete(response(payload(['A late'])));
    await flush();
    expect((await client.fetchLibraries()).single.title, 'B fresh');
    expect(storage.getMediaProviders(scope('A')), payload(['A saved']));
    expect(storage.getMediaProviders(scope('B')), payload(['B fresh']));
    expect(count, 0);
  });

  test('starting a profile update invalidates background response before the new scope commits', () async {
    final storage = await StorageService.getInstance();
    await storage.saveMediaProviders(scope('A'), payload(['A saved']));
    final background = Completer<http.Response>();
    final identity = Completer<http.Response>();
    final client = await create((request) async {
      if (request.url.path == '/') return identity.future;
      if (request.headers['X-Plex-Token'] == 'B') return response(payload(['B fresh']));
      return background.future;
    });
    final update = client.applyProfileUpdate(newToken: 'B', newProfileScopeId: scope('B'));
    var count = 0;
    client.mediaProvidersVersion.addListener(() => count++);
    background.complete(response(payload(['A late'])));
    await flush();
    expect(client.profileScopeId, scope('A'));
    expect((await client.fetchLibraries()).single.title, 'A saved');
    expect(storage.getMediaProviders(scope('A')), payload(['A saved']));
    expect(count, 0);
    identity.complete(
      response({
        'MediaContainer': {'machineIdentifier': 'server'},
      }),
    );
    expect(await update, isTrue);
    expect((await client.fetchLibraries()).single.title, 'B fresh');
  });

  test('response after close is ignored, not saved and does not notify', () async {
    final storage = await StorageService.getInstance();
    await storage.saveMediaProviders(scope('A'), payload(['Saved']));
    final gate = Completer<http.Response>();
    final client = await create((_) => gate.future);
    var count = 0;
    client.mediaProvidersVersion.addListener(() => count++);
    client.close();
    gate.complete(response(payload(['Late'])));
    await flush();
    expect((await client.fetchLibraries()).single.title, 'Saved');
    expect(count, 0);
    expect(storage.getMediaProviders(scope('A')), payload(['Saved']));
  });

  test('storage read and write errors do not break create', () async {
    final client = await create((_) async => response(payload(['Fresh'])), storage: () async => _FailingStorage());
    expect((await client.fetchLibraries()).single.title, 'Fresh');
  });

  test('unavailable storage does not break create', () async {
    final client = await create(
      (_) async => response(payload(['Fresh'])),
      storage: () async => throw StateError('unavailable'),
    );
    expect((await client.fetchLibraries()).single.title, 'Fresh');
  });
}
