import 'package:flutter/material.dart';
import '../tv_focusable.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

class TvChip extends StatelessWidget {
  const TvChip.genre({
    super.key,
    required this.label,
    this.focusable = false,
    this.disabled = false,
    this.onSelect,
    this.focusNode,
  }) : technical = false;
  const TvChip.technical({super.key, required this.label})
    : technical = true,
      focusable = false,
      disabled = false,
      onSelect = null,
      focusNode = null;
  final String label;
  final bool technical, focusable, disabled;
  final VoidCallback? onSelect;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    Widget surface(bool focused, bool pressed) => Container(
      height: px(TvTokens.size.chip.h),
      padding: EdgeInsets.symmetric(horizontal: px(TvTokens.size.chip.padX)),
      decoration: BoxDecoration(
        color: technical
            ? null
            : pressed
            ? TvTokens.color.text.secondary
            : focused
            ? TvTokens.color.focus.fill
            : TvTokens.color.surface.level2,
        border: technical ? Border.all(color: TvTokens.color.text.tertiary, width: px(1.5)) : null,
        borderRadius: BorderRadius.circular(px(TvTokens.radius.chip)),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: theme.badge.copyWith(
          color: technical
              ? TvTokens.color.text.tertiary
              : focused
              ? TvTokens.color.text.onFocus
              : TvTokens.color.text.secondary,
        ),
      ),
    );
    if (!focusable) return IntrinsicWidth(child: surface(false, false));
    return TvFocusable(
      kind: TvFocusKind.fill,
      radius: TvTokens.radius.chip.toDouble(),
      focusedScale: TvTokens.focus.buttonScale,
      disabled: disabled,
      focusNode: focusNode,
      onSelect: onSelect,
      semanticLabel: label,
      builder: (context, state) => IntrinsicWidth(child: surface(state.focused, state.pressed)),
    );
  }
}
