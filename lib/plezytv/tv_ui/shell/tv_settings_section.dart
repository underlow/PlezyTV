import 'package:flutter/material.dart';

import '../../../navigation/main_screen_scope.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

/// Constrains the upstream settings page without changing its routes or items.
class TvSettingsSection extends StatelessWidget {
  const TvSettingsSection({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    final theme = Theme.of(context);
    // SettingsGroup owns a fixed 16 logical-pixel outer margin upstream.
    const groupMargin = 16.0;
    return ColoredBox(
      color: TvTokens.color.bg.base,
      child: Padding(
        padding: EdgeInsets.only(
          left: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context) - groupMargin).clamp(
            0.0,
            double.infinity,
          ),
          top: px(TvTokens.space.safeY),
          right: px(TvTokens.space.safeX),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: px(TvTokens.size.settingsItem.maxW),
            child: Theme(
              data: theme.copyWith(
                scaffoldBackgroundColor: TvTokens.color.bg.base,
                appBarTheme: theme.appBarTheme.copyWith(
                  backgroundColor: TvTokens.color.bg.base,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
