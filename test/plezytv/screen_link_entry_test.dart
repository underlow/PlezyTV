import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/screen_links/screen_link_router.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/services/deep_links/deep_link_service.dart';

class _Host implements DeepLinkProfileHost {
  @override
  List<Profile> get profiles => const [];

  @override
  String? get activeProfileId => null;

  @override
  Future<bool> switchTo(Profile profile) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/plezytv_screen_entry');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> reports, launched;
  late DeepLinkService service;

  setUp(() {
    reports = [];
    launched = [];
    service = DeepLinkService.forTesting(channel, report: reports.add)..host = _Host();
  });

  tearDown(() {
    ScreenLinkRouter.instance.queue.dispose();
    channel.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(channel, null);
  });

  void attach() =>
      service.attach(DeepLinkSession(profileId: null, launch: (link) async => launched.add(link.toUri().toString())));

  test('screen and settings links go to the fork router, not the session', () async {
    attach();
    for (final source in [
      'plezytv://screen/settings',
      'plezytv://screen/home',
      'plezytv://settings/import',
      'plezytv://settings/export',
    ]) {
      service.receive(source);
    }
    await pumpEventQueue();
    expect(launched, isEmpty);
    expect(reports, isEmpty);
  });

  test('a cold screen link is claimed before any session exists', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => 'plezytv://screen/settings');
    await service.fetchInitialLink();
    attach();
    await pumpEventQueue();
    expect(launched, isEmpty);
    expect(reports, isEmpty);
  });

  test('playback links reach the session; original Plezy links are not ours', () async {
    attach();
    service.receive('plezytv://play?content_id=plezy_server_42');
    await pumpEventQueue();
    service.receive('plezytv://live?channel=4.1');
    await pumpEventQueue();
    service.receive('plezy://play?content_id=original');
    await pumpEventQueue();
    expect(launched, ['plezytv://play?server=server&id=42', 'plezytv://live?channel=4.1']);
    expect(reports, hasLength(1));
  });
}
