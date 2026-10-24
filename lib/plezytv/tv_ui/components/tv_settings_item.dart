import 'package:flutter/material.dart';

import '../tv_focusable.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

enum TvSettingsItemKind { standard, singleChoice, multipleChoice, toggle, page, action, reorder }

class TvSettingsItem extends StatelessWidget {
  const TvSettingsItem({
    super.key,
    this.icon,
    required this.title,
    required this.description,
    required this.value,
    this.disabledReason,
    this.focusNode,
    this.onSelect,
    this.onLongPress,
    this.autofocus = false,
    this.kind = TvSettingsItemKind.standard,
    this.selected = false,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onMoveUp,
    this.onMoveDown,
  });

  final IconData? icon;
  final String title, description, value;

  /// A reason disables activation while leaving the item focusable.
  final String? disabledReason;
  final FocusNode? focusNode;
  final VoidCallback? onSelect, onLongPress;
  final bool autofocus;
  final TvSettingsItemKind kind;
  final bool selected;

  /// Reorder rows use Left to move up and Right to move down. Callers supply
  /// localized instructions in [description] and omit callbacks at boundaries.
  final VoidCallback? onMoveUp, onMoveDown;
  final VoidCallback? onNavigateUp, onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final panel = kind != TvSettingsItemKind.standard;
    final choice = kind == TvSettingsItemKind.singleChoice || kind == TvSettingsItemKind.multipleChoice;
    final checked =
        choice || kind == TvSettingsItemKind.toggle || (kind == TvSettingsItemKind.reorder && onSelect != null);
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
        onLongPress: onLongPress,
        checked: checked ? selected : null,
        autoScroll: panel,
        onNavigateUp: onNavigateUp,
        onNavigateDown: onNavigateDown,
        onNavigateLeft: kind == TvSettingsItemKind.reorder ? () => onMoveUp?.call() : null,
        onNavigateRight: kind == TvSettingsItemKind.reorder ? () => onMoveDown?.call() : null,
        semanticLabel: '$title, ${disabledReason ?? description}',
        semanticValue: value,
        builder: (context, state) => SizedBox(
          height: px(TvTokens.size.settingsItem.h),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: px(24)),
            child: Row(
              children: [
                SizedBox(
                  width: px(panel ? TvTokens.size.rightPanel.iconSize : TvTokens.size.settingsItem.iconSize),
                  child: choice
                      ? (selected ? Icon(Icons.check, size: px(28), color: TvTokens.color.accent.normal) : null)
                      : (icon == null
                            ? null
                            : Icon(
                                icon,
                                size: px(panel ? 28 : TvTokens.size.settingsItem.iconSize),
                                color: TvTokens.color.text.primary,
                              )),
                ),
                SizedBox(width: px(24)),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: selected && checked ? theme.body.copyWith(fontWeight: FontWeight.w600) : theme.body,
                      ),
                      if ((disabledReason ?? description).isNotEmpty)
                        Text(
                          disabledReason ?? description,
                          maxLines: panel ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.caption.copyWith(
                            color: panel ? TvTokens.color.text.tertiary : TvTokens.color.text.secondary,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: px(24)),
                if (value.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: px(panel ? 180 : 360)),
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.body.copyWith(color: TvTokens.color.text.secondary),
                      textAlign: TextAlign.right,
                    ),
                  ),
                SizedBox(width: px(16)),
                if (kind == TvSettingsItemKind.standard || kind == TvSettingsItemKind.page)
                  Icon(Icons.chevron_right, size: px(24), color: TvTokens.color.text.secondary),
                if (kind == TvSettingsItemKind.toggle || (kind == TvSettingsItemKind.reorder && onSelect != null))
                  Icon(
                    selected ? Icons.toggle_on : Icons.toggle_off,
                    size: px(48),
                    color: selected ? TvTokens.color.accent.normal : TvTokens.color.text.secondary,
                  ),
                if (kind == TvSettingsItemKind.reorder) ...[
                  Icon(
                    Icons.arrow_upward,
                    size: px(24),
                    color: onMoveUp == null ? TvTokens.color.text.tertiary : TvTokens.color.text.secondary,
                  ),
                  Icon(
                    Icons.arrow_downward,
                    size: px(24),
                    color: onMoveDown == null ? TvTokens.color.text.tertiary : TvTokens.color.text.secondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
