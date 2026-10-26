import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/screen_links/screen_link_router.dart';
import 'package:plezy/services/system_shelf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/plezytv_screen_entry');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    ScreenLinkRouter.instance.queue.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('warm screen link is claimed even before shelf consumer exists', () async {
    final service = SystemShelfService.forTesting(channel: channel);
    expect(
      await service.handleMethodCallForTesting(
        const MethodCall('onWatchNextTap', {'contentId': 'plezytv://screen/settings'}),
      ),
      isTrue,
    );
    final taps = <String>[];
    service.onShelfItemTap = taps.add;
    for (final source in ['plezytv://screen/home', 'plezytv://settings/import', 'plezytv://settings/export']) {
      expect(await service.handleMethodCallForTesting(MethodCall('onWatchNextTap', {'contentId': source})), isTrue);
    }
    expect(taps, isEmpty);
  });

  test('cold screen is consumed and existing links pass through byte-for-byte', () async {
    final service = SystemShelfService.forTesting(channel: channel);
    for (final source in [
      'plezytv://screen/settings',
      'plezytv://settings/import',
      'plezytv://settings/export',
      'plezytv://play?content_id=plezy_server_42',
      'plezytv://live?channel=4.1',
      'plezy_server_42',
      'plezy://play?content_id=original',
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => source);
      expect(
        await service.getInitialDeepLink(),
        (source.contains('://screen/') || source.contains('://settings/')) ? isNull : source,
      );
    }
  });

  test('warm legacy links and shelf IDs reach the original consumer unchanged', () async {
    final service = SystemShelfService.forTesting(channel: channel);
    final taps = <String>[];
    service.onShelfItemTap = taps.add;
    const sources = [
      'plezytv://play?content_id=plezy_server_42',
      'plezytv://live?channel=4.1',
      'plezy_server_42',
      'plezy://play?content_id=original',
    ];
    for (final source in sources) {
      expect(await service.handleMethodCallForTesting(MethodCall('onWatchNextTap', {'contentId': source})), isTrue);
    }
    expect(taps, sources);
  });
}
