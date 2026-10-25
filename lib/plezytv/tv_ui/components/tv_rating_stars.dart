import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../widgets/app_icon.dart';
import '../tv_focusable.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

/// «Ваша оценка»: one focusable row of five stars on Plezy's 0–10 scale
/// (half-star steps), drawn without per-star pads (S14 R6 deviation from §6.8).
///
/// ←/→ change the value by 1 within 0..10 and report it through [onChanged];
/// OK reports [onSubmit] with the current value. ↑/↓ are not consumed.
class TvRatingStars extends StatelessWidget {
  const TvRatingStars({
    super.key,
    required this.value,
    required this.onChanged,
    this.onSubmit,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
  });

  /// Rating in half-star units, 0..10.
  final int value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onSubmit;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;

  static const max = 10;

  void _step(int delta) {
    final next = (value.clamp(0, max) + delta).clamp(0, max);
    if (next != value) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    final size = px(TvTokens.player.postplay.star);
    final current = value.clamp(0, max);
    return TvFocusable(
      kind: TvFocusKind.ring,
      focusedScale: TvTokens.focus.buttonScale,
      radius: TvTokens.player.postplay.starRadius.toDouble(),
      focusNode: focusNode,
      autofocus: autofocus,
      onSelect: () => onSubmit?.call(current),
      onNavigateLeft: () => _step(-1),
      onNavigateRight: () => _step(1),
      semanticLabel: semanticLabel,
      semanticValue: '${current / 2}',
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final threshold = (i + 1) * 2;
          final filled = current >= threshold;
          final half = current == threshold - 1;
          return SizedBox(
            key: ValueKey('tv-rating-star-$i'),
            width: size,
            height: size,
            child: Center(
              child: AppIcon(
                half ? Symbols.star_half_rounded : Symbols.star_rounded,
                fill: filled || half ? 1 : 0,
                color: filled || half ? TvTokens.color.accent.normal : TvTokens.color.text.tertiary,
                size: size * 0.75,
              ),
            ),
          );
        }),
      ),
    );
  }
}
