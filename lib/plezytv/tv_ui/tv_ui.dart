import 'package:flutter/material.dart';

import '../../utils/platform_detector.dart';
import 'tv_shell.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../utils/layout_constants.dart';
import 'movie/tv_movie_screen.dart';
import 'show/tv_show_screen.dart';

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

  static PageRoute<bool>? showDetailRoute({
    required MediaItem metadata,
    bool isOffline = false,
    bool? enabled,
    int? initialSeasonIndex,
    String? initialSeasonId,
    String? initialEpisodeId,
  }) {
    if (!(enabled ?? TvUi.enabled) || isOffline) return null;
    final Widget Function() page;
    switch (metadata.kind) {
      case MediaKind.show:
        page = () => TvShowScreen(
          metadata: metadata,
          initialSeasonIndex: initialSeasonIndex,
          initialSeasonId: initialSeasonId,
          initialEpisodeId: initialEpisodeId,
        );
      case MediaKind.movie:
        page = () => TvMovieScreen(metadata: metadata);
      default:
        return null;
    }
    return PageRouteBuilder<bool>(
      opaque: true,
      pageBuilder: (_, _, _) => page(),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
        child: child,
      ),
      transitionDuration: AppDurations.animMedium,
      reverseTransitionDuration: AppDurations.animMedium,
    );
  }

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
