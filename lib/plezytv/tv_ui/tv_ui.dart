import 'package:flutter/material.dart';

import '../../utils/platform_detector.dart';
import 'tv_shell.dart';

/// Typed replacement lookups for upstream screen factories.
abstract final class TvUi {
  static bool Function() _enabled = PlatformDetector.isTV;

  static bool get enabled => _enabled();

  @visibleForTesting
  static set enabledForTesting(bool Function() value) => _enabled = value;

  @visibleForTesting
  static void resetForTesting() {
    _enabled = PlatformDetector.isTV;
    profileHomeBuilderForTesting = null;
  }

  /// Intercepts the selected replacement, including null (upstream fallback),
  /// so navigator tests can avoid mounting the full upstream home.
  @visibleForTesting
  static Widget? Function(Widget? replacement)? profileHomeBuilderForTesting;

  /// Pass a captured [enabled] value when the choice belongs to a session.
  static Widget? profileHome(
    BuildContext context, {
    bool? enabled,
    required bool isOfflineMode,
    required bool initialPromptHandled,
  }) {
    final replacement = (enabled ?? TvUi.enabled)
        ? TvShell(isOfflineMode: isOfflineMode, initialPromptHandled: initialPromptHandled)
        : null;
    final builder = profileHomeBuilderForTesting;
    return builder == null ? replacement : builder(replacement);
  }
}
