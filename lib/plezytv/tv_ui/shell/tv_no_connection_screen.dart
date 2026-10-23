import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../navigation/main_screen_scope.dart';
import '../components/tv_button.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

/// Offline root, based on 09-state-error-server without an invented sync time.
class TvNoConnectionScreen extends StatelessWidget {
  const TvNoConnectionScreen({
    super.key,
    required this.retryFocus,
    required this.reconnecting,
    required this.onRetry,
    required this.onSettings,
  });

  final FocusNode retryFocus;
  final bool reconnecting;
  final VoidCallback onRetry, onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    return Focus(
      onKeyEvent: (_, event) {
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft && retryFocus.hasFocus) {
          if (event is KeyDownEvent) MainScreenFocusScope.focusSidebarOf(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Align(
        alignment: const Alignment(0, -0.2),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: px(64)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: px(96),
                height: px(96),
                decoration: BoxDecoration(
                  color: TvTokens.color.surface.level2,
                  borderRadius: BorderRadius.circular(px(24)),
                ),
                child: Icon(Icons.cloud_off, size: px(48), color: TvTokens.color.text.secondary),
              ),
              SizedBox(height: px(32)),
              Text(TvStrings.noConnection, style: theme.headline, textAlign: TextAlign.center),
              SizedBox(height: px(16)),
              Text(
                TvStrings.noConnectionHelp,
                style: theme.bodyLarge.copyWith(color: TvTokens.color.text.secondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: px(40)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TvButton(
                    label: reconnecting ? TvStrings.connecting : TvStrings.retry,
                    icon: Icons.refresh,
                    focusNode: retryFocus,
                    disabled: reconnecting,
                    onSelect: onRetry,
                  ),
                  SizedBox(width: px(16)),
                  TvButton(
                    label: TvStrings.connectionSettings,
                    icon: Icons.dns,
                    variant: TvButtonVariant.secondary,
                    onSelect: onSettings,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
