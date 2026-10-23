import 'package:flutter/material.dart';

import 'shell/tv_section_shell.dart';

export 'shell/tv_section_shell.dart';
export 'shell/tv_shell_section.dart';

/// Profile home on TV, with fork-owned navigation and upstream sections.
class TvShell extends StatelessWidget {
  const TvShell({super.key, required this.isOfflineMode, required this.initialPromptHandled});

  final bool isOfflineMode;
  final bool initialPromptHandled;

  @override
  Widget build(BuildContext context) {
    return TvSectionShell(isOfflineMode: isOfflineMode, initialPromptHandled: initialPromptHandled);
  }
}
