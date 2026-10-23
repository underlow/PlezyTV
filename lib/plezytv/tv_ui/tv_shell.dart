import 'package:flutter/material.dart';

import '../../screens/main_screen.dart';

export 'shell/tv_section_shell.dart';
export 'shell/tv_shell_section.dart';

/// Profile home on TV. Later stages replace the upstream home here.
class TvShell extends StatelessWidget {
  const TvShell({super.key, required this.isOfflineMode, required this.initialPromptHandled});

  final bool isOfflineMode;
  final bool initialPromptHandled;

  /// Allows shell tests to inspect the real home configuration without starting
  /// the upstream home’s playback, platform and network services.
  @visibleForTesting
  static Widget Function(MainScreen home)? mainScreenBuilderForTesting;

  @override
  Widget build(BuildContext context) {
    final home = MainScreen(isOfflineMode: isOfflineMode, initialPromptHandled: initialPromptHandled);
    return mainScreenBuilderForTesting?.call(home) ?? home;
  }
}
