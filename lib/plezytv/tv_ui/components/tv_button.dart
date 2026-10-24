import 'package:flutter/material.dart';

import '../tv_focusable.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

enum TvButtonVariant { primary, secondary, smallSecondary }

class TvButton extends StatelessWidget {
  TvButton({
    super.key,
    required this.label,
    this.icon,
    this.variant = TvButtonVariant.primary,
    this.disabled = false,
    this.onSelect,
    this.focusNode,
    this.autofocus = false,
  }) : assert(label.trim().isNotEmpty);

  final String label;
  final IconData? icon;
  final TvButtonVariant variant;
  final bool disabled, autofocus;
  final VoidCallback? onSelect;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final small = variant == TvButtonVariant.smallSecondary;
    final primary = variant == TvButtonVariant.primary;
    return TvFocusable(
      kind: TvFocusKind.fill,
      focusedScale: TvTokens.focus.buttonScale,
      disabled: disabled,
      disabledFocus: TvDisabledFocus.focusable,
      focusNode: focusNode,
      autofocus: autofocus,
      onSelect: onSelect,
      semanticLabel: label,
      builder: (context, state) {
        final foreground = state.disabled
            ? TvTokens.color.disabled.text
            : state.focused
            ? (primary && state.pressed ? TvTokens.color.text.onAccent : TvTokens.color.text.onFocus)
            : primary
            ? TvTokens.color.text.onAccent
            : TvTokens.color.text.primary;
        return Container(
          height: px(small ? TvTokens.size.buttonSmall.h : TvTokens.size.button.h),
          constraints: BoxConstraints(minWidth: px(TvTokens.size.button.minW)),
          padding: EdgeInsets.symmetric(
            horizontal: px(small ? TvTokens.size.buttonSmall.padX : TvTokens.size.button.padX),
          ),
          decoration: BoxDecoration(
            color: state.disabled
                ? TvTokens.color.disabled.fill
                : state.pressed
                ? (primary ? TvTokens.color.accent.pressed : TvTokens.color.text.secondary)
                : state.focused
                ? TvTokens.color.focus.fill
                : primary
                ? TvTokens.color.accent.normal
                : TvTokens.color.surface.level3,
            borderRadius: BorderRadius.circular(px(TvTokens.radius.button)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: px(TvTokens.size.button.iconSize), color: foreground),
                SizedBox(width: px(TvTokens.size.button.iconGap)),
              ],
              Text(label, style: theme.label.copyWith(color: foreground)),
            ],
          ),
        );
      },
    );
  }
}

class TvIconButton extends StatefulWidget {
  const TvIconButton({
    super.key,
    required this.icon,
    required this.caption,
    this.disabled = false,
    this.onSelect,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onNavigateUp,
    this.onNavigateDown,
  });
  final IconData icon;
  final String caption;
  final bool disabled, autofocus;
  final VoidCallback? onSelect;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback? onNavigateLeft, onNavigateRight, onNavigateUp, onNavigateDown;
  @override
  State<TvIconButton> createState() => _TvIconButtonState();
}

class _TvIconButtonState extends State<TvIconButton> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TvFocusable(
          kind: TvFocusKind.fill,
          radius: TvTokens.radius.iconButton.toDouble(),
          focusedScale: TvTokens.focus.buttonScale,
          disabled: widget.disabled,
          disabledFocus: TvDisabledFocus.focusable,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          onSelect: widget.onSelect,
          semanticLabel: widget.caption,
          onFocusChange: (value) {
            setState(() => _focused = value);
            widget.onFocusChange?.call(value);
          },
          onNavigateLeft: widget.onNavigateLeft,
          onNavigateRight: widget.onNavigateRight,
          onNavigateUp: widget.onNavigateUp,
          onNavigateDown: widget.onNavigateDown,
          builder: (context, state) => Container(
            width: px(TvTokens.size.iconButton.w),
            height: px(TvTokens.size.iconButton.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(px(TvTokens.radius.iconButton)),
              color: state.disabled
                  ? TvTokens.color.disabled.fill
                  : state.pressed
                  ? TvTokens.color.text.secondary
                  : state.focused
                  ? TvTokens.color.focus.fill
                  : TvTokens.color.surface.level3,
            ),
            child: Icon(
              widget.icon,
              size: px(TvTokens.size.iconButton.iconSize),
              color: state.disabled
                  ? TvTokens.color.disabled.text
                  : state.focused
                  ? TvTokens.color.text.onFocus
                  : TvTokens.color.text.primary,
            ),
          ),
        ),
        SizedBox(height: px(10)),
        Visibility(
          visible: _focused,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Opacity(
            opacity: widget.disabled ? TvTokens.focus.disabledOpacity : 1,
            child: Text(widget.caption, style: theme.caption),
          ),
        ),
      ],
    );
  }
}
