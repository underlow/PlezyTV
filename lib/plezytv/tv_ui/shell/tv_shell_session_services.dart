import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../connection/connection_registry.dart';
import '../../../i18n/strings.g.dart';
import '../../../profiles/active_profile_binder.dart';
import '../../../profiles/active_profile_provider.dart';
import '../../../profiles/plex_home_service.dart';
import '../../../providers/account_preferences_controller.dart';
import '../../../providers/companion_remote_provider.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/hidden_libraries_provider.dart';
import '../../../providers/libraries_provider.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../providers/offline_mode_provider.dart';
import '../../../providers/playback_state_provider.dart';
import '../../../providers/seerr_account_provider.dart';
import '../../../screens/profile/profile_switch_screen.dart';
import '../../../screens/profile/profile_teardown.dart';
import '../../../screens/video_player_screen.dart';
import '../../../services/companion_remote/companion_remote_host_controller.dart';
import '../../../services/offline_watch_sync_service.dart';
import '../../../services/deep_links/deep_link_launcher.dart';
import '../../../services/update_service.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/update_dialog.dart';
import '../../../utils/video_player_navigation.dart';
import '../../../watch_together/watch_together.dart';
import 'tv_shell_session_controller.dart';

/// Production adapters for the session controller. The shell creates this once
/// and calls start after its first frame; section navigation stays in the shell.
TvShellSessionController createTvShellSessionController(
  BuildContext context, {
  required bool isOfflineMode,
  required bool initialPromptHandled,
  required void Function(TvShellContentIntent) onContentIntent,
}) {
  late final TvShellSessionController controller;
  bool alive() => context.mounted && !controller.isDisposed;
  void checkCurrent() {
    if (!alive()) throw StateError('TV shell session disposed');
  }

  controller = TvShellSessionController(
    activeProfile: context.read<ActiveProfileProvider>(),
    binder: context.read<ActiveProfileBinder>(),
    multiServer: context.read<MultiServerProvider>(),
    offlineMode: context.read<OfflineModeProvider>(),
    plexHome: context.read<PlexHomeService>(),
    preferences: context.read<AccountPreferencesController>(),
    libraries: context.read<LibrariesProvider>(),
    hiddenLibraries: context.read<HiddenLibrariesProvider>(),
    playbackState: context.read<PlaybackStateProvider>(),
    downloads: context.read<DownloadProvider>(),
    watchSync: context.read<OfflineWatchSyncService>(),
    onContentIntent: onContentIntent,
    hasConnections: () async => (await context.read<ConnectionRegistry>().list()).isNotEmpty,
    settleSession: () => settleSessionAfterRemoval(SessionTeardownScope.of(context)),
    pushProfileSelection: () async {
      if (!alive()) return;
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute<void>(builder: (_) => const ProfileSwitchScreen(requireSelection: true)));
    },
    refreshSeerrUser: () async => context.read<SeerrAccountProvider?>()?.refreshUser(),
    hasActiveVideoPlayback: () => VideoPlayerScreenState.activeGlobalKey != null,
    hasActiveCompanionSession: () => context.read<CompanionRemoteProvider>().isInSession,
    isMobilePlatform: Platform.isAndroid || Platform.isIOS,
    isRemoteHost: PlatformDetector.shouldActAsRemoteHost(context),
    startCompanionHost: () async {
      await startCompanionRemoteHost(context, checkCurrent: checkCurrent);
    },
    checkForUpdates: () async {
      if (UpdateService.useNativeUpdater) {
        if (alive()) await UpdateService.checkForUpdatesNative(inBackground: true);
        return;
      }
      final info = await UpdateService.checkForUpdatesOnStartup();
      if (context.mounted && alive() && info != null && info['hasUpdate'] == true) {
        await showUpdateAvailableDialog(
          context,
          info,
          title: t.update.available,
          dismissLabel: t.common.later,
          showSkipVersion: true,
        );
      }
    },
    launchDeepLink: (link, {required isOffline}) async {
      if (alive()) await launchDeepLink(context, link, isOffline: isOffline);
    },
    watchTogether: context.read<WatchTogetherProvider?>(),
    openWatchTogether: (copy) => navigateToWatchTogetherPlayback(context, copy),
    isOfflineMode: isOfflineMode,
    initialPromptHandled: initialPromptHandled,
  );
  return controller;
}
