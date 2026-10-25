import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../media/media_hub.dart';
import '../../../media/media_item.dart';
import '../../../media/media_server_client.dart';
import '../../../utils/app_logger.dart';
import '../tv_card_registry.dart';
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

  /// The value the last queued save sends.
  int? _savingValue;

  /// The value [leave] handed off; dispose does not send it again, whether
  /// that save succeeded or failed. Only until the user is back on the
  /// screen ([resume]) or rates again.
  int? _leftValue;
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
    _leftValue = null;
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
    _leftValue = null;
    return _save(report: true, force: true);
  }

  /// Saves run one after another, so the server ends with the latest value.
  /// [retry] (leaving) sends [rating] only if it is still unsaved once the
  /// saves before it have finished.
  Future<void> _save({required bool report, bool force = false, bool retry = false}) {
    final c = client;
    if (c == null) return Future.value();
    final value = rating;
    final previous = _saving;
    if (!force && !retry && value == (_savingValue ?? _saved)) return previous ?? Future.value();
    if (retry && previous == null && value == _saved) return Future.value();
    Future<void> run() async {
      if (retry && value == _saved) return;
      await _send(c, value, report: report);
    }

    final save = previous == null ? run() : previous.then((_) => run());
    _saving = save;
    _savingValue = value;
    TvPendingRatings.track(subject.globalKey, save);
    unawaited(
      save.whenComplete(() {
        if (!identical(_saving, save)) return;
        _saving = null;
        _savingValue = null;
      }),
    );
    return save;
  }

  Future<void> _send(MediaServerClient c, int value, {required bool report}) async {
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

  /// Leaving the screen: sends an unsaved value silently and does not wait
  /// for the server (R6). The save is held in [TvPendingRatings] so the
  /// card of [subject] rereads when it finishes (R10). Returns that save.
  Future<void> leave() {
    _timer?.cancel();
    _timer = null;
    _leftValue = rating;
    return _save(report: false, retry: true);
  }

  /// The screen is on top again after [leave] (back from a card opened over
  /// it): leaving it later sends a still unsaved value again.
  void resume() => _leftValue = null;

  @override
  void dispose() {
    // A value already being sent, or handed off by [leave], is not sent twice.
    final pending = rating != (_savingValue ?? _saved) && rating != _leftValue;
    _timer?.cancel();
    _timer = null;
    _disposed = true;
    // Leaving the screen saves an unsaved value silently, like closing Plezy's sheet.
    if (pending) unawaited(_save(report: false));
    super.dispose();
  }
}
