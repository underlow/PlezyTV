import 'package:flutter/material.dart';

import '../../services/settings_service.dart';
import '../../widgets/setting_tile.dart';
import 'tv_strings.dart';
import 'tv_ui.dart';

/// PlezyTV preferences stored by the shared settings service.
abstract final class TvSettings {
  /// Controls only the future TV menu entry, never download availability.
  /// Read with SettingsService.instance.read(showDownloads), and subscribe with
  /// SettingsService.instance.listenable(showDownloads).
  static const showDownloads = BoolPref('plezytv_show_downloads', defaultValue: false);

  /// S11 search keyboard layout, per device: `ru`, `en` or `digits`.
  static const searchKeyboardLayout = StringPref('plezytv_search_keyboard_layout', defaultValue: 'ru');

  static Widget? settingsTile(BuildContext context) => TvUi.enabled
      ? const SettingSwitchTile(pref: showDownloads, icon: Icons.download_outlined, title: TvStrings.showDownloads)
      : null;
}
