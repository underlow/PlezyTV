import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plezy/plezytv/update/update_service.dart';
import 'package:plezy/plezytv/update/startup_trigger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cache;
  late SharedPreferences prefs;
  late DateTime now;
  late int requests;
  late List<String> logs;
  setUp(() async {
    cache = await Directory.systemTemp.createTemp('plezytv-update-test');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 10, 23);
    requests = 0;
    logs = [];
  });
  tearDown(() async {
    await cache.delete(recursive: true);
  });
  String release({String tag = 'v0.3.0', List<String> abis = const ['armeabi-v7a', 'arm64-v8a']}) => jsonEncode({
    'tag_name': tag,
    'assets': [
      for (final abi in abis)
        {
          'name': 'plezytv-$tag-$abi.apk',
          'browser_download_url': 'https://github.com/underlow/PlezyTV/releases/download/$tag/plezytv-$tag-$abi.apk',
          'size': 3,
        },
    ],
  });
  UpdateService service({
    String version = '0.2.0',
    String abi = 'armeabi-v7a',
    String? body,
    int status = 200,
    Future<http.Response> Function(http.Request)? handler,
  }) => UpdateService(
    version: version,
    preferences: prefs,
    abi: () async => abi,
    cache: cache,
    now: () => now,
    log: logs.add,
    clientFactory: () => MockClient((request) async {
      requests++;
      expect(request.headers.keys.map((key) => key.toLowerCase()), isNot(contains('authorization')));
      expect(request.url.userInfo, isEmpty);
      return handler != null ? handler(request) : http.Response(body ?? release(), status);
    }),
  );
  test('strict semantic version ordering and invalid release tags', () async {
    expect(ReleaseVersion.parse('0.10.0')!.compareTo(ReleaseVersion.parse('0.9.99')!), greaterThan(0));
    for (final tag in ['v0.3.0-beta', '0.3.0', 'v01.3.0', 'v0.3', 'v0.3.0+1']) {
      expect(await service(body: release(tag: tag)).check(automatic: false), isNull);
    }
    expect(logs, hasLength(5));
  });
  test('A8 A23 newer release selects installed ABI with anonymous latest request', () async {
    for (final abi in ['armeabi-v7a', 'arm64-v8a']) {
      final result = await service(
        abi: abi,
        handler: (request) async {
          expect(request.url.toString(), 'https://api.github.com/repos/underlow/PlezyTV/releases/latest');
          return http.Response(release(), 200);
        },
      ).check(automatic: false);
      expect(result!.version, '0.3.0');
      expect(result.url.path, endsWith('$abi.apk'));
    }
  });
  test('A11 equal/older versions have no update', () async {
    expect(await service(version: '0.3.0').check(automatic: false), isNull);
    expect(await service(version: '1.0.0').check(automatic: false), isNull);
  });
  test('A12 untagged builds perform no HTTP or ABI lookup', () async {
    expect(await service(version: '').check(automatic: false), isNull);
    expect(await service(version: '').check(automatic: true), isNull);
    expect(requests, 0);
    expect(prefs.getInt(UpdateService.lastCheckKey), isNull);
  });
  test('A13 installed v7a never selects arm64-only asset', () async {
    await expectLater(
      service(body: release(abis: ['arm64-v8a'])).check(automatic: false),
      throwsA(isA<HttpException>()),
    );
  });
  test('A20 cooldown persists between starts; manual ignores cooldown and skip', () async {
    final first = service();
    final update = (await first.check(automatic: true))!;
    await first.skip(update);
    expect(await service().check(automatic: true), isNull);
    expect(requests, 1);
    expect((await service().check(automatic: false))!.version, '0.3.0');
    now = now.add(const Duration(hours: 6));
    expect(await service().check(automatic: true), isNull);
    expect(requests, 3);
  });
  test('A22 failed automatic request is silent, logged once and consumes cooldown', () async {
    final updater = service(handler: (_) async => throw const SocketException('offline'));
    expect(await updater.check(automatic: true), isNull);
    expect(logs, hasLength(1));
    expect(await service().check(automatic: true), isNull);
    expect(requests, 1);
    await expectLater(updater.check(automatic: false), throwsA(isA<SocketException>()));
  });
  test('HTTP failure is reported manually', () async {
    await expectLater(service(status: 403).check(automatic: false), throwsA(isA<HttpException>()));
  });
  test('APK success, reuse, next-start cleanup preserves unrelated cache', () async {
    final updater = service(handler: (_) async => http.Response('apk', 200));
    final update = UpdateRelease('0.3.0', Uri.https('github.com', '/apk'), 3);
    await File('${cache.path}/unrelated').writeAsString('keep');
    final progress = <double?>[];
    final file = await updater.download(update, progress.add);
    expect(await file.readAsString(), 'apk');
    expect(progress.last, 1);
    expect((await updater.download(update, progress.add)).path, file.path);
    expect(requests, 1);
    await service().cleanup();
    expect(await file.exists(), isFalse);
    expect(await File('${cache.path}/unrelated').exists(), isTrue);
  });
  test('A10 interrupted download deletes partial and old APK', () async {
    await File('${cache.path}/plezytv-update-old.apk').writeAsString('old');
    final updater = service(handler: (_) async => http.Response('ap', 200));
    await expectLater(
      updater.download(UpdateRelease('0.3.0', Uri.https('github.com', '/apk'), 3), (_) {}),
      throwsA(isA<HttpException>()),
    );
    expect(await cache.list().toList(), isEmpty);
  });
  test('A21 cancel deletes partial', () async {
    final updater = service(handler: (_) async => http.Response('apk', 200));
    await expectLater(
      updater.download(UpdateRelease('0.3.0', Uri.https('github.com', '/apk'), 3), (_) => updater.cancel()),
      throwsA(isA<HttpException>()),
    );
    expect(await cache.list().toList(), isEmpty);
  });
  testWidgets('startup readiness timer stops after one fire; disabled never polls', (tester) async {
    var ready = false;
    var fired = 0;
    var polls = 0;
    final disabled = UpdateStartupTrigger(
      enabled: false,
      isReady: () {
        polls++;
        return true;
      },
      fire: () => fired++,
    );
    expect(disabled.watching, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(polls, 0);
    final trigger = UpdateStartupTrigger(
      enabled: true,
      isReady: () {
        polls++;
        return ready;
      },
      fire: () => fired++,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(fired, 0);
    ready = true;
    await tester.pump(const Duration(seconds: 1));
    expect(fired, 1);
    expect(trigger.watching, isFalse);
    final stoppedPolls = polls;
    await tester.pump(const Duration(hours: 12));
    expect(fired, 1);
    expect(polls, stoppedPolls);
  });
}
