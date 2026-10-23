import 'package:flutter/material.dart';

import '../tv_focusable.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_cards.dart';

/// A row terminator. The caller owns navigation to the complete list.
class TvAllCard extends StatelessWidget {
  const TvAllCard({
    super.key,
    this.episode = false,
    this.focusNode,
    this.autofocus = false,
    required this.onSelect,
    this.onFocusChange,
  });

  final bool episode, autofocus;
  final FocusNode? focusNode;
  final VoidCallback onSelect;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final size = episode
        ? Size(TvTokens.size.episode.w.toDouble(), TvTokens.size.episode.h.toDouble())
        : TvPosterSize.row.dimensions;
    return SizedBox(
      width: px(size.width),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TvFocusable(
            focusNode: focusNode,
            autofocus: autofocus,
            onSelect: onSelect,
            onFocusChange: onFocusChange,
            semanticLabel: TvStrings.all,
            scaleAlignment: Alignment.bottomCenter,
            focusedScale: episode ? TvTokens.focus.episodeScale : TvTokens.focus.cardScale,
            builder: (context, state) => Container(
              width: px(size.width),
              height: px(size.height),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: TvTokens.color.surface.level2,
                borderRadius: BorderRadius.circular(px(TvTokens.radius.card)),
              ),
              child: Text(TvStrings.all, style: theme.label),
            ),
          ),
          SizedBox(height: px(20 + TvTokens.type.body.lineHeight + TvTokens.type.caption.lineHeight)),
        ],
      ),
    );
  }
}
