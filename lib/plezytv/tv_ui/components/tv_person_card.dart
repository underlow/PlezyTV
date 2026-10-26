import 'package:flutter/material.dart';

import '../../../focus/input_mode_tracker.dart';
import '../../../media/media_server_client.dart';
import '../../../widgets/optimized_media_image.dart';
import '../tv_focusable.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

/// Round person card shared by the "Cast" rows (S7/S8) and search results (S11).
///
/// A 200px circular photo, then the name and an optional caption below it.
class TvPersonCard extends StatelessWidget {
  const TvPersonCard({
    super.key,
    required this.client,
    required this.imagePath,
    required this.name,
    this.caption,
    this.focusNode,
    this.onSelect,
    this.externalFocus,
  });

  static const double photoSize = 200;
  static const double captionGap = 20;

  final MediaServerClient? client;
  final String? imagePath;
  final String name;
  final String? caption;
  final FocusNode? focusNode;
  final VoidCallback? onSelect;

  /// Visual-only mode for containers that already own focus (paged grids):
  /// no focus node of its own, the same ring and scale as the focusable card.
  final bool? externalFocus;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    Widget photo(BuildContext _, TvFocusState _) => ClipOval(
      child: OptimizedMediaImage(
        client: client,
        imagePath: imagePath,
        width: px(photoSize),
        height: px(photoSize),
        fallbackIcon: Icons.person,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (externalFocus != null)
          TvFocusVisual(
            state: TvFocusState(
              focused: externalFocus! && InputModeTracker.isKeyboardMode(context),
              pressed: false,
              disabled: false,
            ),
            kind: TvFocusKind.ring,
            focusedScale: TvTokens.focus.cardScale,
            alignment: Alignment.bottomCenter,
            radius: photoSize / 2,
            builder: photo,
          )
        else
          TvFocusable(
            focusNode: focusNode,
            scaleAlignment: Alignment.bottomCenter,
            semanticLabel: name,
            onSelect: onSelect,
            radius: photoSize / 2,
            builder: photo,
          ),
        SizedBox(height: px(captionGap)),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.body),
        if (caption != null) Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.caption),
      ],
    );
  }
}
