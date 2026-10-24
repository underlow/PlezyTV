import 'package:flutter/material.dart';
import '../../../media/media_item.dart';

/// T1 route host; replaced by the T2 screen implementation.
class TvShowScreen extends StatelessWidget {
  const TvShowScreen({
    super.key,
    required this.metadata,
    this.initialSeasonIndex,
    this.initialSeasonId,
    this.initialEpisodeId,
  });
  final MediaItem metadata;
  final int? initialSeasonIndex;
  final String? initialSeasonId;
  final String? initialEpisodeId;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: Text(metadata.displayTitle)),
  );
}
