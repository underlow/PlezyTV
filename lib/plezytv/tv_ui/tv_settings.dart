import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../services/settings_service.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/setting_tile.dart';
import 'tv_strings.dart';
import 'tv_settings_backup.dart';
import 'tv_ui.dart';

/// PlezyTV preferences stored by the shared settings service.
abstract final class TvSettings {
  /// Controls only the future TV menu entry, never download availability.
  /// Read with SettingsService.instance.read(showDownloads), and subscribe with
  /// SettingsService.instance.listenable(showDownloads).
  static const showDownloads = BoolPref('plezytv_show_downloads', defaultValue: false);

  /// S11 search keyboard layout, per device: `ru`, `en` or `digits`.
  static const searchKeyboardLayout = StringPref('plezytv_search_keyboard_layout', defaultValue: 'ru');

  /// Android alone supports the external app-directory transport.
  static bool get usesFixedBackup => defaultTargetPlatform == TargetPlatform.android && TvUi.enabled;

  static bool get showsBackup => usesFixedBackup || !PlatformDetector.isTV() || PlatformDetector.isDesktopOS();

  static Widget? backupSection(BuildContext context) => usesFixedBackup ? const TvSettingsBackup() : null;

  static Widget? settingsTile(BuildContext context) => TvUi.enabled
      ? const SettingSwitchTile(pref: showDownloads, icon: Icons.download_outlined, title: TvStrings.showDownloads)
      : null;
}
