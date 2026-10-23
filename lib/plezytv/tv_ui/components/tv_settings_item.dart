import 'package:flutter/material.dart';

import '../tv_focusable.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

class TvSettingsItem extends StatelessWidget {
  const TvSettingsItem({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    this.disabledReason,
    this.focusNode,
    this.onSelect,
    this.autofocus = false,
  });

  final IconData icon;
  final String title, description, value;

  /// A reason disables activation while leaving the item focusable.
  final String? disabledReason;
  final FocusNode? focusNode;
  final VoidCallback? onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: px(TvTokens.size.settingsItem.maxW)),
      child: TvFocusable(
        kind: TvFocusKind.outline,
        radius: TvTokens.radius.button.toDouble(),
        disabled: disabledReason != null,
        disabledFocus: TvDisabledFocus.focusable,
        focusNode: focusNode,
        autofocus: autofocus,
        onSelect: onSelect,
        semanticLabel: '$title, ${disabledReason ?? description}',
        semanticValue: value,
        builder: (context, state) => SizedBox(
          height: px(TvTokens.size.settingsItem.h),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: px(24)),
            child: Row(
              children: [
                Icon(icon, size: px(TvTokens.size.settingsItem.iconSize), color: TvTokens.color.text.primary),
                SizedBox(width: px(24)),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.body),
                      Text(
                        disabledReason ?? description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.caption.copyWith(color: TvTokens.color.text.secondary),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: px(24)),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.body.copyWith(color: TvTokens.color.text.secondary),
                  ),
                ),
                SizedBox(width: px(16)),
                Icon(Icons.chevron_right, size: px(24), color: TvTokens.color.text.secondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
