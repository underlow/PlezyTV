import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/hidden_libraries_provider.dart';
import '../../providers/libraries_provider.dart';
import '../../services/settings_export_service.dart';
import '../../services/settings_mutation_service.dart';
import '../../services/settings_service.dart';
import '../../services/storage_service.dart';
import '../tv_ui/tv_settings.dart';
import '../tv_ui/tv_strings.dart';

/// Fixed-file transport shared by the TV settings and settings links.
class SettingsTransferService {
  static const fileName = 'plezytv-settings.json';

  const SettingsTransferService();

  static String _requireUser(String? uuid) {
    if (uuid == null || uuid.isEmpty) throw const NoUserSignedInException();
    return uuid;
  }

  static Map<String, dynamic> buildExportMap(
    SharedPreferencesWithCache prefs, {
    required String? currentUserUuid,
    String appVersion = '',
  }) {
    final data = SettingsExportService.buildExportMap(
      prefs,
      currentUserUuid: _requireUser(currentUserUuid),
      appVersion: appVersion,
    );
    final entries = data['prefs'] as Map<String, dynamic>;
    entries[TvSettings.showDownloads.key] = {
      'type': 'bool',
      'value': prefs.getBool(TvSettings.showDownloads.key) ?? TvSettings.showDownloads.defaultValue,
    };
    entries[TvSettings.searchKeyboardLayout.key] = {
      'type': 'string',
      'value': prefs.getString(TvSettings.searchKeyboardLayout.key) ?? TvSettings.searchKeyboardLayout.defaultValue,
    };
    return data;
  }

  static Future<ImportResult> applyImportMap(
    Map<String, dynamic> data,
    SharedPreferencesWithCache prefs, {
    required String? currentUserUuid,
  }) async {
    final uuid = _requireUser(currentUserUuid);
    if (data['formatVersion'] != SettingsExportService.formatVersion || data['formatVersion'] is! int) {
      throw const InvalidExportFileException(TvStrings.transferInvalidFile);
    }
    final result = await SettingsExportService.applyImportMap(data, prefs, currentUserUuid: uuid);
    final entries = data['prefs'] as Map;
    var imported = 0;
    final downloads = entries[TvSettings.showDownloads.key];
    if (downloads is Map && downloads['type'] == 'bool' && downloads['value'] is bool) {
      await prefs.setBool(TvSettings.showDownloads.key, downloads['value'] as bool);
      imported++;
    }
    final layout = entries[TvSettings.searchKeyboardLayout.key];
    if (layout is Map && layout['type'] == 'string' && layout['value'] is String) {
      await prefs.setString(TvSettings.searchKeyboardLayout.key, layout['value'] as String);
      imported++;
    }
    return ImportResult(keysImported: result.keysImported + imported, keysSkipped: result.keysSkipped - imported);
  }

  Future<File> settingsFile() async {
    final directory = await getExternalStorageDirectory();
    if (directory == null) throw const SettingsExportException(TvStrings.transferStorageUnavailable);
    return File('${directory.path}/$fileName');
  }

  Future<String> exportToFile() async {
    final uuid = _requireUser((await StorageService.getInstance()).activeUserScope());
    final settings = await SettingsService.getInstance();
    final info = await PackageInfo.fromPlatform();
    final data = buildExportMap(settings.prefs, currentUserUuid: uuid, appVersion: info.version);
    final file = await settingsFile();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);
    return file.path;
  }

  Future<ImportResult> importFromFile() async {
    final uuid = _requireUser((await StorageService.getInstance()).activeUserScope());
    final settings = await SettingsService.getInstance();
    final file = await settingsFile();
    if (!await file.exists()) throw const SettingsExportException(TvStrings.transferFileMissing);
    final Object? data;
    try {
      data = jsonDecode(await file.readAsString());
    } on FormatException {
      throw const InvalidExportFileException(TvStrings.transferInvalidFile);
    }
    if (data is! Map<String, dynamic>) throw const InvalidExportFileException(TvStrings.transferInvalidFile);
    return applyImportMap(data, settings.prefs, currentUserUuid: uuid);
  }

  /// Matches Plezy's bulk-import refresh sequence, including root effects.
  Future<ImportResult> importAndApply(BuildContext context) async {
    final previous = SettingsMutationService.captureRootConfiguration();
    final result = await importFromFile();
    SettingsService.instance.refreshListenables();
    if (!context.mounted) return result;
    final hidden = context.read<HiddenLibrariesProvider>();
    final libraries = context.read<LibrariesProvider>();
    await hidden.refresh();
    unawaited(libraries.refresh());
    if (!context.mounted) return result;
    final failures = await const SettingsMutationService().applyStoredEffects(
      context,
      previousRootConfiguration: previous,
    );
    if (failures.isNotEmpty) throw SettingsExportException(failures.first.display);
    return result;
  }
}
