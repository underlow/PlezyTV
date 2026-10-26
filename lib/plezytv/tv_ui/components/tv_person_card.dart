import 'package:flutter/material.dart';

import '../../../media/media_server_client.dart';
import '../../../widgets/optimized_media_image.dart';
import '../tv_focusable.dart';
import '../tv_theme.dart';

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
  });

  static const double photoSize = 200;
  static const double captionGap = 20;

  final MediaServerClient? client;
  final String? imagePath;
  final String name;
  final String? caption;
  final FocusNode? focusNode;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TvFocusable(
          focusNode: focusNode,
          semanticLabel: name,
          onSelect: onSelect,
          builder: (_, _) => ClipOval(
            child: OptimizedMediaImage(
              client: client,
              imagePath: imagePath,
              width: px(photoSize),
              height: px(photoSize),
              fallbackIcon: Icons.person,
            ),
          ),
        ),
        SizedBox(height: px(captionGap)),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.body),
        if (caption != null) Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.caption),
      ],
    );
  }
}
