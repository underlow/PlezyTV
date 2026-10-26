import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plezy/plezytv/settings_transfer/settings_transfer_service.dart';
import 'package:plezy/plezytv/tv_ui/tv_settings.dart';
import 'package:plezy/plezytv/tv_ui/tv_settings_backup.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/settings_export_service.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/services/settings_service.dart';

import '../../test_helpers/prefs.dart';

class _Transfer extends SettingsTransferService {
  final File file;
  const _Transfer(this.file);
  @override
  Future<File> settingsFile() async => file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetSharedPreferencesForTest);

  test('closed portable export round trips TV and Plezy settings under a different user', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setBool(TvSettings.showDownloads.key, true);
    await prefs.setString(TvSettings.searchKeyboardLayout.key, 'en');
    await prefs.setInt('seek_time_small', 42);
    await prefs.setString('user_alice_hidden_libraries', '["server:movies"]');
    await prefs.setString('plex_token', 'secret');
    await prefs.setString('server_url', 'http://private');
    await prefs.setString('search_history', 'private');
    await prefs.setString('custom_download_path', '/private');
    final data = SettingsTransferService.buildExportMap(prefs, currentUserUuid: 'alice');
    expect((data['prefs'] as Map).keys.toSet(), {
      TvSettings.showDownloads.key,
      TvSettings.searchKeyboardLayout.key,
      'seek_time_small',
      'hidden_libraries',
    });
    await prefs.clear();
    final result = await SettingsTransferService.applyImportMap(data, prefs, currentUserUuid: 'bob');
    expect(result.keysImported, 4);
    expect(result.keysSkipped, 0);
    expect(prefs.getBool(TvSettings.showDownloads.key), true);
    expect(prefs.getString(TvSettings.searchKeyboardLayout.key), 'en');
    expect(prefs.getInt('seek_time_small'), 42);
    expect(prefs.getString('user_bob_hidden_libraries'), '["server:movies"]');
    expect(prefs.containsKey('user_alice_hidden_libraries'), false);
  });

  test('Plezy files are accepted and invalid TV entries are skipped', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final data = {
      'formatVersion': 1,
      'prefs': <String, dynamic>{
        'seek_time_small': {'type': 'int', 'value': 35},
      },
    };
    expect((await SettingsTransferService.applyImportMap(data, prefs, currentUserUuid: 'bob')).keysImported, 1);
    (data['prefs'] as Map)[TvSettings.showDownloads.key] = {'type': 'bool', 'value': 'true'};
    (data['prefs'] as Map)[TvSettings.searchKeyboardLayout.key] = {'type': 'int', 'value': 5};
    final result = await SettingsTransferService.applyImportMap(data, prefs, currentUserUuid: 'bob');
    expect(result.keysImported, 1);
    expect(result.keysSkipped, 2);
    expect(prefs.containsKey(TvSettings.showDownloads.key), false);
    expect(prefs.containsKey(TvSettings.searchKeyboardLayout.key), false);
  });

  test('invalid file and no user fail before writes; export replaces the fixed file', () async {
    final dir = await Directory.systemTemp.createTemp('s4-transfer-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/${SettingsTransferService.fileName}');
    final service = _Transfer(file);
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setInt('seek_time_small', 42);
    await SettingsService.getInstance();
    final storage = await StorageService.getInstance();
    await storage.setActiveProfileId('local-bob');
    Future<void> unchangedAfterFailure() async {
      final before = {for (final key in prefs.keys) key: prefs.get(key)};
      await expectLater(service.importFromFile(), throwsA(isA<SettingsExportException>()));
      expect({for (final key in prefs.keys) key: prefs.get(key)}, before);
    }

    await unchangedAfterFailure();
    for (final text in [
      '{bad',
      '[]',
      '{"formatVersion":2,"prefs":{"seek_time_small":{"type":"int","value":12}}}',
      '{"formatVersion":1,"prefs":null}',
    ]) {
      await file.writeAsString(text);
      await unchangedAfterFailure();
    }
    PackageInfo.setMockInitialValues(
      appName: 'PlezyTV',
      packageName: 'com.underlow.plezytv',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    expect(await service.exportToFile(), file.path);
    await prefs.setInt('seek_time_small', 30);
    expect(await service.exportToFile(), file.path);
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(data['prefs']['seek_time_small']['value'], 30);
    expect(dir.listSync(), hasLength(1));
    await prefs.setInt('seek_time_small', 20);
    expect((await service.importFromFile()).keysImported, 3);
    expect(prefs.getInt('seek_time_small'), 30);
    await storage.clearActiveProfileId();
    await unchangedAfterFailure();
    // The pure boundary also rejects missing scope, before any preference write.
    final before = {for (final key in prefs.keys) key: prefs.get(key)};
    await expectLater(
      SettingsTransferService.applyImportMap(data, prefs, currentUserUuid: null),
      throwsA(isA<NoUserSignedInException>()),
    );
    expect({for (final key in prefs.keys) key: prefs.get(key)}, before);
    expect(
      () => SettingsTransferService.buildExportMap(prefs, currentUserUuid: null),
      throwsA(isA<NoUserSignedInException>()),
    );
  });

  testWidgets('backup transport respects platform, force-TV and original Plezy visibility', (tester) async {
    addTearDown(TvUi.resetForTesting);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TvDetectionService.debugReset();
      PlatformDetector.debugSetIsDesktopOSOverride(null);
    });
    final detection = await TvDetectionService.getInstance(forceTv: true);
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final desktop = [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux].contains(platform);
      PlatformDetector.debugSetIsDesktopOSOverride(desktop);
      TvDetectionService.debugSetAppleTVOverride(null);
      detection.setForceTv(true);
      expect(TvUi.enabled, isTrue);
      expect(TvSettings.backupSection(context), platform == TargetPlatform.android ? isA<TvSettingsBackup>() : isNull);
      expect(TvSettings.showsBackup, platform == TargetPlatform.android || desktop);
      detection.setForceTv(false);
      expect(TvSettings.backupSection(context), isNull);
      expect(TvSettings.showsBackup, isTrue);
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    PlatformDetector.debugSetIsDesktopOSOverride(false);
    TvDetectionService.debugSetAppleTVOverride(true);
    expect(TvSettings.backupSection(context), isNull);
    expect(TvSettings.showsBackup, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TvUi.enabledForTesting = () => false;
    expect(TvSettings.backupSection(context), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
