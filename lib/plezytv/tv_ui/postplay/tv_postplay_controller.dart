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

  /// The rows (season episodes, "Similar") are still loading (skeletons).
  bool loading = true;

  /// [subject]'s metadata (ratings, "Your rating") is still loading. The
  /// rows may still be loading after it arrived.
  late bool subjectLoading = variant != TvPostPlayVariant.episode;

  /// The screen's own data did not load: the season row (episode variant) or
  /// [subject] with its ratings and rows (R9). A failed related-hubs request
  /// only leaves "Similar" empty.
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
  Future<void>? _saving;
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
          if (!_dirty && _timer == null && _saving == null) rating = _saved = tvPostPlayRatingUnits(item.userRating);
          ratingKnown = true;
          // Ratings do not wait for the rows.
          subjectLoading = false;
          notifyListeners();
          try {
            similar = tvPostPlaySimilarHub(await c.fetchRelatedHubs(id));
          } catch (error) {
            // Like S8: no related hubs is an empty "Similar", not a failure.
            appLogger.w('Post-play related hubs failed', error: error);
          }
      }
    } catch (error) {
      failed = true;
    }
    if (_disposed) return;
    subjectLoading = false;
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

  Future<void> _save({required bool report, bool force = false}) {
    final c = client;
    if (c == null || (!force && !_dirty)) return Future.value();
    final save = _send(c, report: report);
    _saving = save;
    unawaited(
      save.whenComplete(() {
        if (identical(_saving, save)) _saving = null;
      }),
    );
    return save;
  }

  Future<void> _send(MediaServerClient c, {required bool report}) async {
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

  /// Before leaving the screen: waits for a save in flight and saves an
  /// unsaved value silently, so the next screen reads the new rating (R6,
  /// R10). Bounded by [timeout] so a hanging server cannot hold navigation.
  Future<void> flush({Duration timeout = const Duration(seconds: 3)}) async {
    _timer?.cancel();
    _timer = null;
    Future<void> run() async {
      final inFlight = _saving;
      if (inFlight != null) await inFlight;
      if (_dirty) await _save(report: false);
    }

    try {
      await run().timeout(timeout);
    } on TimeoutException {
      appLogger.w('Post-play rating save still pending when leaving');
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
