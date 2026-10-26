import '../../../navigation/main_screen_scope.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_version.dart';
import '../../../models/catalog/catalog_item.dart';
import '../../../services/catalog/catalog_library_matcher.dart';
import '../../../services/catalog/catalog_source.dart';
import '../../../services/catalog/library_watchlist_candidates.dart';
import '../../../services/device_performance.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/content_utils.dart';
import '../../../utils/formatters.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/optimized_media_image.dart';
import '../components/tv_button.dart';
import '../components/tv_action_row.dart';
import '../components/tv_chip.dart';
import '../components/tv_ratings.dart';
import '../components/tv_right_panel.dart';
import '../components/tv_settings_item.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tint_service.dart';
import '../tv_tinted_background.dart';
import '../tv_tokens.dart';
import 'tv_watchlist_availability.dart';

/// Arguments of the watchlist catalog card (S10, C4).
class TvCatalogItemArgs {
  const TvCatalogItemArgs({
    required this.item,
    required this.source,
    required this.availability,
    required this.onRemoved,
    required this.onRestored,
  });

  final CatalogItem item;
  final CatalogSource source;
  final TvWatchlistAvailability availability;
  final void Function(CatalogItem) onRemoved;
  final void Function(CatalogItem) onRestored;
}

PageRoute<void> tvCatalogItemRoute(TvCatalogItemArgs args) =>
    MaterialPageRoute<void>(builder: (_) => TvCatalogItemScreen(args: args));

/// Test seam for the copy navigation; production uses [navigateToMediaItemDetails].
@visibleForTesting
Future<void> Function(BuildContext context, MediaItem copy)? tvOpenCopyForTesting;

/// Opens a library copy found for a watchlist item: one copy goes straight to
/// its detail screen, several first show a copy picker labelled as Plezy does
/// (library, server, quality).
Future<void> openWatchlistCopy(BuildContext context, List<MediaItem> copies) async {
  if (copies.isEmpty) return;
  Future<void> open(BuildContext context, MediaItem copy) async {
    final hook = tvOpenCopyForTesting;
    if (hook != null) return hook(context, copy);
    await navigateToMediaItemDetails(context, copy);
  }

  if (copies.length == 1) return open(context, copies.single);
  MediaItem? chosen;
  final anchor = FocusManager.instance.primaryFocus ?? FocusNode();
  await TvRightPanel.show(
    context: context,
    anchor: anchor,
    root: TvRightPanelPage(
      title: TvStrings.catalogChooseCopy,
      itemsBuilder: (panelContext) => [
        for (final copy in copies)
          TvSettingsItem(
            key: ValueKey('copy:${copy.globalKey}'),
            title: watchlistCopyTitle(copy),
            description: watchlistCopyDetails(copy) ?? '',
            value: '',
            kind: TvSettingsItemKind.page,
            onSelect: () {
              chosen = copy;
              TvRightPanel.of(panelContext).close();
            },
          ),
      ],
    ),
  );
  final copy = chosen;
  if (copy != null && context.mounted) await open(context, copy);
}

/// Plezy's copy-row title: library name, else server name, else product name.
String watchlistCopyTitle(MediaItem copy) =>
    copy.libraryTitle ?? copy.serverName ?? copy.backend.dialect?.productName ?? 'Plex';

/// Plezy's copy-row subtitle: best-version quality and, when the title is the
/// library, the server name.
String? watchlistCopyDetails(MediaItem copy) {
  MediaVersion? best;
  for (final version in copy.mediaVersions ?? const <MediaVersion>[]) {
    if (version.resolutionHeight == null) continue;
    if (best == null || version.resolutionHeight! > best.resolutionHeight!) best = version;
  }
  final details = [?best?.displayLabel, ?(copy.libraryTitle == null ? null : copy.serverName)];
  return details.isEmpty ? null : details.join(' • ');
}

/// TV catalog card for watchlist items (S10, R12).
class TvCatalogItemScreen extends StatefulWidget {
  const TvCatalogItemScreen({super.key, required this.args});

  final TvCatalogItemArgs args;

  @override
  State<TvCatalogItemScreen> createState() => _TvCatalogItemScreenState();
}

class _TvCatalogItemScreenState extends State<TvCatalogItemScreen> {
  final _openNode = FocusNode(debugLabel: 'catalog_open');
  final _listNode = FocusNode(debugLabel: 'catalog_watchlist');
  final _trailerNode = FocusNode(debugLabel: 'catalog_trailer');

  late CatalogItem _item = widget.args.item;

  /// The detail form, kept only when it adds lookup ids or titles.
  CatalogItem? _enriched;
  late TvAvailability _status;
  bool _checking = false;
  bool _onList = true;
  bool _mutating = false;
  bool _initialFocusDone = false;
  bool _initialized = false;

  TvWatchlistAvailability get _availability => widget.args.availability;

  @override
  void initState() {
    super.initState();
    final args = widget.args;
    _onList = args.source.isOnWatchlist(args.item.kind, args.item.ids) ?? true;
    _status = _availability.statusOf(args.item);
    _check();
    _initialized = true;
    unawaited(_loadDetail());
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusInitial());
  }

  @override
  void dispose() {
    _openNode.dispose();
    _listNode.dispose();
    _trailerNode.dispose();
    super.dispose();
  }

  /// A known copy stays usable while an enriched re-check runs.
  bool get _pending => _status is TvAvailabilityPending || (_checking && _status is! TvAvailabilityFound);

  bool get _openActive => !_pending && _status is! TvAvailabilityNotFound;

  int _checkSeq = 0;

  bool get _hasTrailer => _item.trailerUrl?.trim().isNotEmpty ?? false;

  void _focusInitial() {
    if (!mounted || _initialFocusDone) return;
    _initialFocusDone = true;
    (_openActive ? _openNode : _listNode).requestFocus();
  }

  void _check({CatalogItem? enriched, bool retry = false}) {
    final known = _status;
    final reuse = !retry && enriched == null && known is! TvAvailabilityPending;
    if (reuse) return;
    // Only the newest check may show a result or end «checking» (R12).
    final seq = ++_checkSeq;
    if (_initialized) {
      setState(() => _checking = true);
    } else {
      _checking = true;
    }
    _availability
        .check(widget.args.item, enriched: enriched, retry: retry)
        .then(
          (status) {
            if (!mounted || seq != _checkSeq) return;
            setState(() {
              _status = status;
              _checking = false;
            });
          },
          onError: (Object e) {
            appLogger.d('Watchlist catalog check failed', error: e);
            if (mounted && seq == _checkSeq) {
              setState(() {
                _status = TvAvailability.unchecked;
                _checking = false;
              });
            }
          },
        );
  }

  Future<void> _loadDetail() async {
    try {
      final detail = await widget.args.source.fetchDetail(widget.args.item);
      if (!mounted) return;
      final original = widget.args.item;
      setState(() {
        _item = detail.item;
      });
      // As Plezy: ask again when enrichment adds id forms or title candidates.
      final gainedIds = !original.ids.allKeys.toSet().containsAll(detail.item.ids.allKeys);
      final gainedTitles = !CatalogLibraryMatcher.lookupTitles(
        original,
      ).toSet().containsAll(CatalogLibraryMatcher.lookupTitles(detail.item));
      if (gainedIds || gainedTitles) {
        _enriched = detail.item;
        _check(enriched: detail.item);
      }
    } catch (e) {
      appLogger.d('Watchlist catalog detail load failed', error: e);
    }
  }

  Future<void> _onOpen() async {
    final status = _status;
    if (status is TvAvailabilityFound) {
      await openWatchlistCopy(context, status.copies);
    } else if (status is TvAvailabilityUnchecked) {
      _check(enriched: _enriched, retry: true);
    }
  }

  Future<void> _toggleList() async {
    if (_mutating) return;
    final args = widget.args;
    final add = !_onList;
    _mutating = true;
    try {
      final ran = await mutateWatchlistMembership(args.item.kind, (source: args.source, ids: args.item.ids), add: add);
      if (!ran || !mounted) return;
      setState(() => _onList = add);
      add ? args.onRestored(args.item) : args.onRemoved(args.item);
    } catch (_) {
      if (mounted) showErrorSnackBar(context, t.explore.watchlistUpdateFailed);
    } finally {
      _mutating = false;
    }
  }

  Future<void> _openTrailer() async {
    final uri = Uri.tryParse(_item.trailerUrl?.trim() ?? '');
    if (uri == null || !uri.hasScheme) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) appLogger.d('Catalog trailer could not be opened');
    } catch (e) {
      appLogger.d('Catalog trailer failed to open', error: e);
    }
  }

  List<FocusNode> get _activeNodes => [if (_openActive) _openNode, _listNode, if (_hasTrailer) _trailerNode];

  VoidCallback _step(FocusNode from, int delta) => () {
    final nodes = _activeNodes;
    final index = nodes.indexOf(from);
    final target = index < 0 ? (delta > 0 ? 0 : nodes.length - 1) : index + delta;
    if (target >= 0 && target < nodes.length) nodes[target].requestFocus();
  };

  @override
  Widget build(BuildContext context) => TvTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final theme = TvTheme.of(context), px = theme.px;
    return Scaffold(
      body: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) => handleBackKeyAction(event, () => Navigator.of(context).maybePop()),
        child: TvTintedBackground(
          source: TvArtworkSource(item: _item.toMediaItem()),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                left: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)).clamp(
                  0.0,
                  double.infinity,
                ),
                top: px(72),
                right: px(96),
                bottom: px(48),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context),
                  SizedBox(height: px(48)),
                  _actions(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _metaLine(CatalogItem item) {
    final seasons = item.serverState?.totalSeasons;
    return [
      if (item.year != null) '${item.year}',
      if (item.kind == MediaKind.show && seasons != null) TvStrings.seasons(seasons),
      if (item.kind != MediaKind.show && (item.runtimeMinutes ?? 0) > 0)
        formatDurationTextual(Duration(minutes: item.runtimeMinutes!).inMilliseconds),
      if (formatContentRating(item.certification).isNotEmpty) formatContentRating(item.certification),
    ].join(' · ');
  }

  Widget _header(BuildContext context) {
    final theme = TvTheme.of(context), px = theme.px;
    final item = _item;
    final media = item.toMediaItem();
    final meta = _metaLine(item);
    final genres = item.genres?.where((g) => g.trim().isNotEmpty).toList() ?? const <String>[];
    final summary = item.overview?.trim();
    final parts = <(double, Widget)>[
      (
        0,
        ClearLogoImage(
          client: null,
          logoPath: item.logoUrl,
          fallbackWidth: px(900),
          width: px(560),
          height: px(120),
          alignment: Alignment.centerLeft,
          fallbackBuilder: (_) => Text(
            item.title,
            key: const ValueKey('catalog-title'),
            style: theme.display,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      if (meta.isNotEmpty) (24, Text(meta, key: const ValueKey('catalog-meta'), style: theme.body)),
      if (genres.isNotEmpty)
        (
          20,
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final genre in genres)
                  Padding(
                    padding: EdgeInsets.only(right: px(12)),
                    child: TvChip.genre(label: genre),
                  ),
              ],
            ),
          ),
        ),
      (20, TvRatings(item: media)),
      if (summary != null && summary.isNotEmpty)
        (
          24,
          SizedBox(
            width: px(900),
            child: Text(
              summary,
              key: const ValueKey('catalog-summary'),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyLarge,
            ),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (gap, child) in parts) ...[if (gap > 0) SizedBox(height: px(gap)), child],
      ],
    );
  }

  Widget _actions(BuildContext context) {
    final px = TvTheme.of(context).px;
    final status = _status;
    final pending = _pending;
    final active = _openActive;
    // A disabled Open is skipped by traversal but keeps focus it already holds.
    _openNode.skipTraversal = !active;
    final openLabel = pending
        ? TvStrings.catalogOpen
        : switch (status) {
            TvAvailabilityNotFound() => TvStrings.catalogNotOnServer,
            TvAvailabilityUnchecked() => TvStrings.catalogCouldNotCheck,
            _ => TvStrings.catalogOpen,
          };
    final reduced = DevicePerformance.isReduced;
    final indicator = SizedBox(
      key: const ValueKey('catalog-open-progress'),
      width: px(TvTokens.size.button.iconSize),
      height: px(TvTokens.size.button.iconSize),
      child: reduced
          ? Icon(Icons.hourglass_empty, size: px(TvTokens.size.button.iconSize), color: TvTokens.color.disabled.text)
          : CircularProgressIndicator(strokeWidth: px(3), color: TvTokens.color.disabled.text),
    );
    return TvActionRow(
      buttons: [
        Stack(
          alignment: Alignment.centerLeft,
          children: [
            TvButton(
              key: const ValueKey('catalog-open'),
              label: openLabel,
              icon: pending ? null : Icons.play_arrow,
              disabled: !active,
              focusNode: _openNode,
              minWidth: 360,
              onSelect: () => unawaited(_onOpen()),
              onNavigateRight: _step(_openNode, 1),
              onNavigateLeft: () {},
            ),
            if (pending)
              Positioned(
                left: px(TvTokens.size.button.padX),
                child: ExcludeSemantics(child: indicator),
              ),
          ],
        ),
        TvIconButton(
          key: const ValueKey('catalog-watchlist'),
          caption: _onList ? t.explore.removeFromWatchlist : t.explore.addToWatchlist,
          icon: _onList ? Icons.bookmark_remove : Icons.bookmark_add,
          focusNode: _listNode,
          onSelect: () => unawaited(_toggleList()),
          onNavigateLeft: _step(_listNode, -1),
          onNavigateRight: _step(_listNode, 1),
        ),
        if (_hasTrailer)
          TvIconButton(
            key: const ValueKey('catalog-trailer'),
            caption: t.explore.detail.watchTrailer,
            icon: Icons.movie_outlined,
            focusNode: _trailerNode,
            onSelect: () => unawaited(_openTrailer()),
            onNavigateLeft: _step(_trailerNode, -1),
            onNavigateRight: () {},
          ),
      ],
    );
  }
}
