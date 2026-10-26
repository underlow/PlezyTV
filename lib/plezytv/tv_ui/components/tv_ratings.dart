import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../widgets/app_icon.dart';
import '../../../media/media_item.dart';
import '../../../media/media_rating.dart';
import '../../../utils/rating_utils.dart';
import '../../../widgets/media_rating_badge.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

/// Preserves Plezy's complete rating list, including duplicates and bare scores.
class TvRatings extends StatelessWidget {
  const TvRatings({super.key, required this.item, this.fallbackItem, this.ratings});
  final MediaItem item;
  final MediaItem? fallbackItem;

  /// Explicit merged list, when the caller also has community scores.
  final List<MediaRatingSource>? ratings;

  Color? _plateColor(MediaRatingSource rating) {
    final info = ratingInfoForSource(rating.source, rating.value);
    return switch (rating.source) {
      'imdb' => TvTokens.color.rating.imdb,
      'tmdb' => TvTokens.color.rating.tmdb,
      // Compare Plezy's resolved mark, rather than duplicating its threshold.
      'rottenTomatoes' || 'rottenTomatoesCritic' =>
        info?.assetPath == ratingInfoForSource(rating.source, 10)?.assetPath
            ? TvTokens.color.rating.rtFresh
            : TvTokens.color.rating.rtRotten,
      'audience' || 'rottenTomatoesAudience' => TvTokens.color.rating.audience,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final ratings = this.ratings ?? mediaRatingsFor(item, fallbackItem: fallbackItem);
    if (ratings.isEmpty) return const SizedBox.shrink();
    final theme = TvTheme.of(context);
    final px = theme.px;
    return Semantics(
      label: ratingsSemanticLabel(ratings),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < ratings.length; index++) ...[
            if (index > 0) SizedBox(width: px(24)),
            Builder(
              builder: (context) {
                final rating = ratings[index];
                final info = ratingInfoForSource(rating.source, rating.value);
                final color = _plateColor(rating);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: px(24),
                      padding: EdgeInsets.symmetric(horizontal: px(4)),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color ?? TvTokens.color.surface.level3,
                        borderRadius: BorderRadius.circular(px(TvTokens.radius.xs)),
                      ),
                      child: info != null
                          ? SvgPicture.asset(
                              info.assetPath,
                              height: px(16),
                              width: px(16 * info.iconAspect),
                              theme: SvgTheme(
                                currentColor: color == null
                                    ? TvTokens.color.text.secondary
                                    : TvTokens.color.text.onFocus,
                              ),
                            )
                          : AppIcon(
                              rating.source == 'audience' ? Symbols.people_rounded : Symbols.star_rounded,
                              fill: 1,
                              size: px(16),
                              color: color == null ? TvTokens.color.text.secondary : TvTokens.color.text.onFocus,
                            ),
                    ),
                    SizedBox(width: px(8)),
                    Text(
                      mediaRatingLabel(rating),
                      style: theme.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontVariations: const [FontVariation('wght', 600)],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
