import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../media/media_hub.dart';
import '../../../media/media_item.dart';
import '../../../media/media_server_client.dart';
import '../../../utils/app_logger.dart';
import 'tv_postplay_logic.dart';

/// Data and rating state of the post-play screen. The screen owns focus and
/// navigation; this owns loading and Plezy's rating logic (R6, R9).
class TvPostPlayController extends ChangeNotifier {
  TvPostPlayController({
    required this.client,
    required this.watched,
    this.next,
    this.autoSaveDelay = const Duration(milliseconds: 600),
  }) : variant = tvPostPlayVariant(watched, next) {
    subject = switch (variant) {
      TvPostPlayVariant.movie => watched,
      TvPostPlayVariant.episode || TvPostPlayVariant.showEnded => tvPostPlayShowOf(watched),
    };
    if (variant == TvPostPlayVariant.movie) {
      rating = _saved = tvPostPlayRatingUnits(watched.userRating);
      ratingKnown = true;
    }
  }

  final MediaServerClient? client;
  final MediaItem watched;
  final MediaItem? next;
  final TvPostPlayVariant variant;
  final Duration autoSaveDelay;

  /// The movie, or the series (episode variants); player data until loaded.
  late MediaItem subject;

  /// Server metadata for [subject] has arrived.
  bool subjectLoaded = false;

  /// Rows and ratings are still loading (skeletons).
  bool loading = true;

  /// Loading failed: rows and ratings stay hidden (R9).
  bool failed = false;

  /// Episodes of [next]'s season after it.
  List<MediaItem> seasonRest = const [];
  MediaHub? similar;

  /// Current "Your rating" value in half-star units, 0..10.
  int rating = 0;
  int _saved = 0;

  /// The starting value is known (from the player for a movie, after the
  /// series loads for the ended variant).
  bool ratingKnown = false;

  /// Reports a failed save that the user should see.
  void Function(Object error)? onRateError;

  Timer? _timer;
  bool _disposed = false;

  bool get ratingSupported => client?.capabilities.numericUserRating ?? false;

  /// "Your rating" is shown (R4–R6).
  bool get showsRating => variant != TvPostPlayVariant.episode && ratingSupported && ratingKnown && !failed;

  bool get _dirty => rating != _saved;

  Future<void> load() async {
    final c = client;
    try {
      if (c == null) throw StateError('Server unavailable');
      switch (variant) {
        case TvPostPlayVariant.episode:
          final n = next!;
          final seasonId = n.parentId;
          if (seasonId != null) {
            final page = await c.fetchChildrenPage(seasonId, start: 0, size: 500);
            seasonRest = tvPostPlayEpisodesAfter(page.items, n);
          }
        case TvPostPlayVariant.movie:
        case TvPostPlayVariant.showEnded:
          final id = subject.id;
          if (id.isEmpty) throw StateError('Unknown item');
          final result = await c.fetchItemWithOnDeck(id);
          if (_disposed) return;
          final item = result.item;
          if (item == null) throw StateError('Item missing');
          subject = item.copyWith(
            serverId: subject.serverId ?? item.serverId,
            serverName: subject.serverName ?? item.serverName,
          );
          subjectLoaded = true;
          if (!_dirty && _timer == null) rating = _saved = tvPostPlayRatingUnits(item.userRating);
          ratingKnown = true;
          final hubs = await c.fetchRelatedHubs(id);
          similar = tvPostPlaySimilarHub(hubs);
      }
    } catch (error) {
      failed = true;
      if (variant == TvPostPlayVariant.movie) similar = null;
    }
    if (_disposed) return;
    loading = false;
    notifyListeners();
  }

  /// ←/→ on the stars: keep the value and autosave after the delay.
  void setRating(int value) {
    final clamped = value.clamp(0, 10);
    if (clamped == rating) return;
    rating = clamped;
    _timer?.cancel();
    _timer = Timer(autoSaveDelay, () {
      _timer = null;
      unawaited(_save(report: true));
    });
    notifyListeners();
  }

  /// OK on the stars: save now.
  Future<void> submit() {
    _timer?.cancel();
    _timer = null;
    return _save(report: true, force: true);
  }

  Future<void> _save({required bool report, bool force = false}) async {
    final c = client;
    if (c == null || (!force && !_dirty)) return;
    final value = rating;
    try {
      await c.rate(subject, value > 0 ? value.toDouble() : -1);
      _saved = value;
    } catch (error) {
      if (report && !_disposed) {
        onRateError?.call(error);
      } else {
        appLogger.w('Failed to save rating after leaving post-play', error: error);
      }
    }
  }

  @override
  void dispose() {
    final pending = _timer != null || _dirty;
    _timer?.cancel();
    _timer = null;
    _disposed = true;
    // Leaving the screen saves an unsaved value silently, like closing Plezy's sheet.
    if (pending) unawaited(_save(report: false));
    super.dispose();
  }
}
