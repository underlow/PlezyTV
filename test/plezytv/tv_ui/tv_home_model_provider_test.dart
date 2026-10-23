import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/media/library_change_event.dart';
import 'package:plezy/providers/discover_provider.dart';
import 'package:plezy/providers/hidden_libraries_provider.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/media_items.dart';

import 'package:plezy/plezytv/tv_ui/home/tv_home_model.dart';

// Same aggregation boundary as test/providers/discover_provider_test.dart;
// loading, notifications and coordinator timing come from the real provider.
class _FakeAggregationService extends DataAggregationService {
  _FakeAggregationService(super.serverManager);

  List<MediaItem> Function() onDeckResult = () => [];
  Future<void>? onDeckGate;
  Completer<void>? onDeckStarted;

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async {
    onDeckStarted?.complete();
    await onDeckGate;
    final items = onDeckResult();
    return (
      items: items,
      observedItems: [for (final item in items) (item: item, clientScope: null)],
      succeededServerIds: const {'server_1'},
      cancelledServerIds: const <String>{},
      failedServerIds: const <String>{},
    );
  }

  @override
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async => (
    hubs: <MediaHub>[],
    observedItems: <({MediaItem item, String? clientScope})>[],
    succeededServerIds: const {'server_1'},
    cancelledServerIds: const <String>{},
    failedServerIds: const <String>{},
  );
}

class _FakeClient implements MediaServerClient {
  final _PushChannel channel = _PushChannel();

  @override
  final Object authenticationSessionId = Object();

  @override
  LibraryEventChannel createLibraryEventChannel() => channel;

  @override
  ServerId get serverId => ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PushChannel implements LibraryEventChannel {
  final _events = StreamController<LibraryChangeEvent>.broadcast();

  @override
  Stream<LibraryChangeEvent> get events => _events.stream;

  @override
  void start() {}

  @override
  void stop() {}

  @override
  void dispose() => unawaited(_events.close());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MultiServerManager manager;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;
  late DiscoverProvider provider;
  late _FakeAggregationService aggregation;
  late TvHomeModelBuilder builder;
  late List<TvHomeModel> models;
  late List<bool> providerBusy;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    manager = MultiServerManager()..debugRegisterClientForTesting(_FakeClient());
    aggregation = _FakeAggregationService(manager);
    multiServer = MultiServerProvider(manager, aggregation);
    hiddenLibraries = HiddenLibrariesProvider();
    await hiddenLibraries.ensureInitialized();
    libraries = LibrariesProvider();
    provider = DiscoverProvider(
      multiServer,
      hiddenLibraries,
      libraries,
      profileId: 'home-test',
      isProfileBinding: () => false,
      syncSystemShelf: (_, _) async {},
      syncServerSources: (_, _) async {},
    );
    builder = TvHomeModelBuilder();
    models = [];
    providerBusy = [];
    provider.addListener(() {
      models.add(builder.build(provider));
      providerBusy.add(provider.isLoadInFlight);
    });
  });
  tearDown(() {
    provider.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
    manager.dispose();
  });

  Future<void> coldError() async {
    aggregation.onDeckResult = () => throw Exception('first failure');
    await provider.load();
    expect(models.first.state, TvHomeState.loading);
    expect(models.last.state, TvHomeState.error);
    expect(models.last.errorMessage, contains('first failure'));
    // The last real notification precedes coordinator drain completion.
    expect(providerBusy.last, isTrue);
    expect(models.last.isLoadInFlight, isFalse);
    expect(provider.isLoadInFlight, isFalse);
  }

  Future<void> retry({String? error, bool content = false, bool fromError = true}) async {
    final oldMessage = models.last.errorMessage;
    final start = models.length;
    final gate = Completer<void>();
    aggregation.onDeckStarted = Completer<void>();
    aggregation.onDeckGate = gate.future;
    aggregation.onDeckResult = () {
      if (error != null) throw Exception(error);
      return content ? [testMediaItem(serverId: 'server_1')] : [];
    };
    final pass = provider.load();
    await aggregation.onDeckStarted!.future;
    final pending = models.last;
    expect(models.length, greaterThan(start));
    expect(provider.errorMessage, isNull);
    expect(provider.isLoading, isTrue);
    expect(provider.isLoadInFlight, isTrue);
    expect(pending.state, fromError ? TvHomeState.error : TvHomeState.empty);
    expect(pending.errorMessage, oldMessage);
    expect(pending.isLoadInFlight, isTrue);
    gate.complete();
    await pass;
    expect(
      models.last.state,
      content
          ? TvHomeState.content
          : error != null
          ? TvHomeState.error
          : TvHomeState.empty,
    );
    expect(models.last.isLoadInFlight, isFalse);
    expect(providerBusy.last, isTrue);
    if (error != null) expect(models.last.errorMessage, contains(error));
    if (error == null) expect(models.last.errorMessage, isNull);
  }

  test('cold error -> retry retains error -> new error replaces message', () async {
    await coldError();
    await retry(error: 'second failure');
  });
  test('error -> retry -> empty -> refresh -> content', () async {
    await coldError();
    await retry();
    await retry(content: true, fromError: false);
  });
  test('error -> retry -> content', () async {
    await coldError();
    await retry(content: true);
  });
  test('cold empty settles with enabled refresh -> content', () async {
    await provider.load();
    expect(models.last.state, TvHomeState.empty);
    expect(providerBusy.last, isTrue);
    expect(models.last.isLoadInFlight, isFalse);
    await retry(content: true, fromError: false);
  });
}
