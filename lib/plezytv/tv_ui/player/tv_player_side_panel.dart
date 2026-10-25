import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/media_version.dart';
import '../../../media/playback_rate.dart';
import '../../../models/transcode_quality_preset.dart';
import '../../../mpv/mpv.dart';
import '../../../services/playback_subtitle_resolver.dart';
import '../../../services/player_sync_offsets.dart';
import '../../../services/scoped_player_prefs.dart';
import '../../../services/settings_service.dart';
import '../../../services/sleep_timer_service.dart';
import '../../../services/track_selection_service.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/formatters.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/quality_preset_labels.dart';
import '../../../utils/track_label_builder.dart';
import '../../../watch_together/providers/watch_together_provider.dart';
import '../../../widgets/overlay_sheet.dart';
import '../../../widgets/video_controls/helpers/track_filter_helper.dart';
import '../../../widgets/video_controls/models/track_controls_state.dart';
import '../../../widgets/video_controls/sheets/subtitle_search_sheet.dart';
import '../../../widgets/video_controls/sheets/version_quality_sheet.dart';
import '../../../widgets/video_controls/sheets/video_settings_sheet.dart';
import '../components/tv_settings_item.dart';
import '../tv_focusable.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

/// Screens of the right panel (S9 design §3).
enum TvPlayerSidePage { settings, subtitles, audio, quality, speed, aspect, sleepTimer, audioOutput }

/// One choice on a page: Plezy's value and the Plezy action behind it.
class _Option {
  const _Option({required this.id, required this.title, this.description = '', required this.selected, this.onSelect});

  final String id;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback? onSelect;
}

/// A focusable row of a page (or a divider when [build] is null).
class _Row {
  const _Row(this.id, this.build, {this.selected = false});
  const _Row.divider() : id = '', build = null, selected = false;

  final String id;
  final bool selected;
  final Widget Function(FocusNode node, VoidCallback up, VoidCallback down)? build;
}

class _Frame {
  _Frame(this.page);
  final TvPlayerSidePage page;

  /// The row that opened the page above (R16: focus returns to it).
  String? returnId;
}

/// The TV player's right panel (R11–R16): a stack of pages drawn inside the
/// player panel, not a route, so Play/Pause and the chrome stay Plezy's. Values
/// and actions come from Plezy ([TrackControlsState], [SleepTimerService],
/// [PlayerSyncOffsets], [SettingsService]); «More» and subtitle search open
/// Plezy's sheets through [OverlaySheetController].
class TvPlayerSidePanel extends StatefulWidget {
  const TvPlayerSidePanel({
    super.key,
    required this.root,
    required this.player,
    required this.trackControlsState,
    required this.isOfflinePlayback,
    required this.onClose,
  });

  final TvPlayerSidePage root;
  final Player player;
  final TrackControlsState trackControlsState;
  final bool isOfflinePlayback;

  /// Back on the root page.
  final VoidCallback onClose;

  @override
  State<TvPlayerSidePanel> createState() => TvPlayerSidePanelState();
}

class TvPlayerSidePanelState extends State<TvPlayerSidePanel> {
  static const _syncStepMs = 50; // Plezy's SyncOffsetControl tap step.
  static const _speeds = <double>[
    0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, //
    3.0, 3.5, 4.0, 4.5, 5.0, 6.0, 7.0, maximumPlaybackRate,
  ];
  static const _sleepMinutes = [5, 10, 15, 30, 45, 60, 90, 120];

  final _stack = <_Frame>[];
  final _nodes = <String, FocusNode>{};
  String? _lastFocused;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _sleepTimer = SleepTimerService();
  late PlayerSyncOffsets _offsets;
  final _pendingSync = <String, int>{};
  Future<void> _syncWrites = Future.value();
  bool _sheetOpen = false;

  TrackControlsState get _state => widget.trackControlsState;
  Player get _player => widget.player;
  TvPlayerSidePage get page => _stack.last.page;

  /// Whether one of Plezy's sheets opened from here is up.
  bool get sheetOpen => _sheetOpen;

  @override
  void initState() {
    super.initState();
    _stack.add(_Frame(widget.root));
    _offsets = PlayerSyncOffsets.of(_player)..addListener(_changed);
    _sleepTimer.addListener(_changed);
    _listen();
    _focusDefault();
  }

  @override
  void didUpdateWidget(TvPlayerSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, _player)) {
      _offsets.removeListener(_changed);
      _offsets = PlayerSyncOffsets.of(_player)..addListener(_changed);
      for (final s in _subscriptions) {
        s.cancel();
      }
      _subscriptions.clear();
      _listen();
    }
  }

  void _listen() {
    final streams = _player.streams;
    _subscriptions.addAll([
      streams.tracks.listen((_) => _changed()),
      streams.track.listen((_) => _changed()),
      streams.rate.listen((_) => _changed()),
      streams.audioDevice.listen((_) => _changed()),
      streams.audioDevices.listen((_) => _changed()),
    ]);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _offsets.removeListener(_changed);
    _sleepTimer.removeListener(_changed);
    for (final s in _subscriptions) {
      s.cancel();
    }
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  // ---- Stack and focus (R16) ----

  FocusNode _node(TvPlayerSidePage page, String id) {
    final key = '${page.name}/$id';
    return _nodes.putIfAbsent(key, () {
      final node = FocusNode(debugLabel: 'TvPlayerSide.$key');
      node.addListener(() {
        if (node.hasFocus) _lastFocused = key;
      });
      return node;
    });
  }

  void _push(TvPlayerSidePage next, String fromId) {
    setState(() {
      _stack.last.returnId = fromId;
      _stack.add(_Frame(next));
    });
    _focusDefault();
  }

  /// Back (and ← in a submenu): submenu → parent on the row it came from;
  /// the root page closes the panel.
  void back() {
    if (_stack.length == 1) return widget.onClose();
    setState(_stack.removeLast);
    final id = _stack.last.returnId;
    _focusLater(() => id == null ? null : _node(page, id));
  }

  /// Puts focus back where it was on the current page (after a sheet, or when
  /// the panel reclaims the remote).
  void refocus() {
    final key = _lastFocused;
    final node = key == null ? null : _nodes[key];
    if (key != null && key.startsWith('${page.name}/') && node?.context != null) {
      node!.requestFocus();
    } else {
      _focusDefault();
    }
  }

  /// Entering a page focuses the selected value, else the first row.
  void _focusDefault() {
    _focusLater(() {
      final rows = _rows(page).where((row) => row.build != null).toList();
      if (rows.isEmpty) return null;
      final row = rows.firstWhere((row) => row.selected, orElse: () => rows.first);
      return _node(page, row.id);
    });
  }

  void _focusLater(FocusNode? Function() target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _sheetOpen) return;
      final node = target();
      if (node?.context != null) {
        node!.requestFocus();
      } else if (node != null) {
        _focusDefault();
      }
    });
  }

  /// Opens one of Plezy's sheets; focus returns to [fromId] once every sheet
  /// it led to is closed (the settings sheet may replace itself with a sync bar).
  void _openSheet(String fromId, WidgetBuilder builder) {
    final controller = OverlaySheetController.maybeOf(context);
    if (controller == null) return;
    final from = page;
    _lastFocused = '${from.name}/$fromId';
    setState(() => _sheetOpen = true);
    void restore() {
      if (!mounted) return;
      setState(() => _sheetOpen = false);
      if (page == from) _focusLater(() => _node(from, fromId));
    }

    controller.show(builder: builder).whenComplete(() {
      if (!mounted) return;
      if (!controller.isOpen) return restore();
      void onCount() {
        if (controller.isOpen) return;
        OverlaySheetController.openSheetCount.removeListener(onCount);
        restore();
      }

      OverlaySheetController.openSheetCount.addListener(onCount);
    });
  }

  // ---- Plezy's values ----

  Tracks get _tracks => _player.state.tracks;
  TrackSelection get _selection => _player.state.track;

  List<_Option> _subtitleOptions() {
    final s = _state;
    final selection = _selection;
    if (s.canUseSourceSubtitles) {
      final choice = _effectiveSourceSubtitle(selection);
      return [
        _Option(
          id: 'off',
          title: t.common.off,
          selected: choice.isOff,
          onSelect: () => unawaited(s.onSwitchSubtitle!(const PlaybackSourceSubtitleChoice.off())),
        ),
        for (final (i, track) in s.sourceSubtitleTracks.indexed)
          _labelled(
            'source:${track.id}',
            track.labelForIndex(i),
            selected: !choice.isOff && track.id == choice.sourceStreamId,
            onSelect: () => unawaited(s.onSwitchSubtitle!(PlaybackSourceSubtitleChoice.source(track.id))),
          ),
      ];
    }
    final tracks = TrackFilterHelper.extractAndFilterTracks<SubtitleTrack>(_tracks, (t) => t?.subtitle ?? []);
    final current = selection.subtitle;
    final secondary = _player.supportsSecondarySubtitles ? selection.secondarySubtitle : null;
    final off = current == null || current.id == SubtitleTrack.off.id;
    void clearSecondary() {
      _player.selectSecondarySubtitleTrack(SubtitleTrack.off);
      s.onSecondarySubtitleTrackChanged?.call(SubtitleTrack.off);
    }

    // Server sidecars not yet loaded on a direct play (as Plezy's sheet).
    final attached = <int>{};
    for (final sidecar in s.sourceSubtitleSidecars) {
      final id = sidecar.sourceStreamId;
      final uri = sidecar.track.uri;
      if (id != null && uri != null && tracks.any((track) => track.isExternal && track.uri == uri)) attached.add(id);
    }
    final selectedSourceId = s.selectedSubtitleChoice?.sourceStreamId;
    final unloaded = s.directPlaySourceSidecars
        .where(
          (track) =>
              !attached.contains(track.id) &&
              track.id != selectedSourceId &&
              track.id != s.selectedSecondarySubtitleStreamId,
        )
        .toList();

    return [
      _Option(
        id: 'off',
        title: t.common.off,
        selected: off,
        onSelect: () {
          if (secondary != null) clearSecondary();
          _player.selectSubtitleTrack(SubtitleTrack.off);
          s.onSubtitleTrackChanged?.call(SubtitleTrack.off);
        },
      ),
      for (final (i, track) in tracks.indexed)
        _labelled(
          'track:${track.id}',
          TrackLabelBuilder.subtitleLabel(
            title: track.title,
            language: track.language,
            codec: track.codec,
            forced: track.isForced,
            index: i,
          ),
          selected: !off && track.id == current.id,
          onSelect: () {
            if (secondary != null && secondary.id == track.id) clearSecondary();
            _player.selectSubtitleTrack(track);
            s.onSubtitleTrackChanged?.call(track);
          },
        ),
      for (final (i, track) in unloaded.indexed)
        _labelled(
          'source:${track.id}',
          track.labelForIndex(tracks.length + i),
          selected: false,
          onSelect: () => unawaited(s.onSwitchSubtitle!(PlaybackSourceSubtitleChoice.source(track.id))),
        ),
    ];
  }

  /// As Plezy's track sheet: a source pick counts only once the engine
  /// confirms it, unless the server burns it in.
  PlaybackSourceSubtitleChoice _effectiveSourceSubtitle(TrackSelection selection) {
    const off = PlaybackSourceSubtitleChoice.off();
    final explicit = _state.selectedSubtitleChoice;
    if (explicit == null) return off;
    if (explicit.isOff) return explicit;
    if (!_state.sourceSubtitleTracks.any((track) => track.id == explicit.sourceStreamId)) return off;
    if (_state.burnsSelectedSubtitle) return explicit;
    final engine = selection.subtitle;
    return engine != null && engine.id != SubtitleTrack.off.id ? explicit : off;
  }

  List<_Option> _audioOptions() {
    final s = _state;
    final engineTracks = _tracks.audio;
    final useSource =
        (s.isTranscoding || s.sourceAudioTracks.any((track) => track.isExternal)) &&
        s.sourceAudioTracks.length > 1 &&
        s.onSwitchAudioStreamId != null;
    if (useSource) {
      int? selectedId = s.selectedAudioStreamId;
      if (selectedId == null || !s.sourceAudioTracks.any((track) => track.id == selectedId)) {
        selectedId = s.isTranscoding
            ? s.sourceAudioTracks.where((track) => track.selected).firstOrNull?.id
            : playingSourceAudioTrack(
                selectedMpvTrack: _selection.audio,
                mpvTracks: engineTracks,
                sourceTracks: s.sourceAudioTracks,
              )?.id;
      }
      return [
        for (final track in s.sourceAudioTracks)
          _labelled(
            'source:${track.id}',
            track.label,
            selected: track.id == selectedId,
            onSelect: () => unawaited(s.onSwitchAudioStreamId!(track.id)),
          ),
      ];
    }
    final tracks = TrackFilterHelper.extractAndFilterTracks<AudioTrack>(_tracks, (t) => t?.audio ?? []);
    final selectedId = _selection.audio?.id ?? '';
    return [
      for (final (i, track) in tracks.indexed)
        _labelled(
          'track:${track.id}',
          TrackLabelBuilder.audioLabel(
            title: track.title,
            language: track.language,
            codec: track.codec,
            codecProfile: track.codecProfile,
            channels: track.channelsCount,
            index: i,
          ),
          selected: track.id == selectedId,
          onSelect: () {
            _player.selectAudioTrack(track);
            s.onAudioTrackChanged?.call(track);
          },
        ),
    ];
  }

  static _Option _labelled(String id, TrackLabel label, {required bool selected, required VoidCallback onSelect}) =>
      _Option(id: id, title: label.primary, description: label.secondary ?? '', selected: selected, onSelect: onSelect);

  /// Plezy offers version/quality only with something to pick and a way to
  /// switch; never offline (R3).
  bool get _hasQuality =>
      !widget.isOfflinePlayback &&
      (_state.availableVersions.length > 1 || _state.serverSupportsTranscoding) &&
      (_state.onSwitchVersion != null || _state.onSwitchQualityPreset != null);

  bool get _showVersions => _state.availableVersions.length > 1;

  int? get _sourceBitrateKbps {
    final index = _state.selectedMediaIndex;
    if (index < 0 || index >= _state.availableVersions.length) return null;
    final bitrate = _state.availableVersions[index].bitrate;
    return bitrate != null && bitrate > 0 ? bitrate : null;
  }

  String _qualityValue() {
    final versions = _state.availableVersions;
    final index = _state.selectedMediaIndex;
    return [
      if (_showVersions)
        index >= 0 && index < versions.length ? versions[index].displayLabel : t.videoControls.versionColumnHeader,
      if (_state.serverSupportsTranscoding)
        qualityPresetLabel(_state.selectedQualityPreset, sourceBitrateKbps: _showVersions ? null : _sourceBitrateKbps),
    ].join(' / ');
  }

  String _qualityDescription() {
    if (!_state.isTranscoding) return TvStrings.playerDirectPlay;
    final kbps = _state.selectedQualityPreset.videoBitrateKbps;
    return TvStrings.playerTranscoding(kbps);
  }

  List<_Option> _qualityOptions() {
    final s = _state;
    final versions = <MediaVersion>[if (_showVersions) ...s.availableVersions];
    return [
      for (final (i, version) in versions.indexed)
        _Option(
          id: 'version:$i',
          title: version.displayLabel,
          selected: i == s.selectedMediaIndex,
          onSelect: s.onSwitchVersion == null ? null : () => s.onSwitchVersion!(i),
        ),
      if (s.serverSupportsTranscoding)
        for (final preset in TranscodeQualityPreset.displayOrder)
          _Option(
            id: 'quality:${preset.name}',
            title: qualityPresetLabel(preset, sourceBitrateKbps: _showVersions ? null : _sourceBitrateKbps),
            selected: preset == s.selectedQualityPreset,
            onSelect: s.onSwitchQualityPreset == null ? null : () => s.onSwitchQualityPreset!(preset),
          ),
    ];
  }

  /// The chosen rate, not a Watch Together drift nudge (as Plezy's sheet).
  double get _rate {
    final rate = _player.state.rate;
    try {
      final session = context.read<WatchTogetherProvider>();
      if (session.syncOwnsRate) return session.roomRate ?? rate;
    } catch (_) {
      // No Watch Together provider.
    }
    return rate;
  }

  bool get _hasSpeed => _state.canControl && !_state.isLive;

  List<_Option> _speedOptions() {
    final current = _rate;
    return [
      for (final speed in _speeds)
        _Option(
          id: 'speed:$speed',
          title: formatPlaybackRate(speed, normalAtOne: true),
          selected: (current - speed).abs() < 0.01,
          onSelect: () => unawaited(() async {
            await (_state.onRateRequested ?? _player.setRate)(speed);
            await ScopedPlayerPrefs.write(ScopedPlayerPrefs.playbackSpeed, _state.metadata, speed);
          }()),
        ),
    ];
  }

  static String _aspectLabel(int mode) => switch (mode) {
    1 => t.videoControls.fillScreen,
    2 => t.videoControls.stretch,
    _ => t.videoControls.letterbox,
  };

  List<_Option> _aspectOptions() {
    final current = _state.boxFitMode;
    return [
      for (var mode = 0; mode < 3; mode++)
        _Option(
          id: 'aspect:$mode',
          title: _aspectLabel(mode),
          selected: mode == current,
          // Plezy only cycles contain → cover → fill.
          onSelect: () {
            for (var i = 0; i < (mode - current + 3) % 3; i++) {
              _state.onCycleBoxFitMode?.call();
            }
          },
        ),
    ];
  }

  String _sleepValue() {
    if (!_sleepTimer.isActive) return t.common.off;
    if (_sleepTimer.isEndOfVideoMode) return t.videoControls.sleepTimerEndOfVideo;
    final remaining = _sleepTimer.remainingTime;
    if (remaining == null) return t.common.off;
    return t.videoSettings.sleepTimerActive(duration: formatDurationWithSeconds(remaining));
  }

  List<_Option> _sleepOptions() {
    final timer = _sleepTimer;
    final active = timer.isActive && !timer.isEndOfVideoMode ? timer.originalDuration?.inMinutes : null;
    return [
      _Option(id: 'off', title: t.common.off, selected: !timer.isActive, onSelect: timer.cancelTimer),
      _Option(
        id: 'end',
        title: t.videoControls.sleepTimerEndOfVideo,
        selected: timer.isEndOfVideoMode,
        onSelect: timer.armEndOfVideo,
      ),
      for (final minutes in _sleepMinutes)
        _Option(
          id: 'minutes:$minutes',
          title: formatDurationTextual(minutes * 60 * 1000),
          selected: minutes == active,
          onSelect: () => timer.startTimer(Duration(minutes: minutes)),
        ),
    ];
  }

  /// Plezy's settings sheet offers the output device on every non-mobile layout.
  bool get _hasAudioOutput => PlatformDetector.isDesktop(context);

  String _deviceLabel(AudioDevice device) => device.description.isEmpty ? device.name : device.description;

  List<_Option> _audioOutputOptions() {
    final current = _player.state.audioDevice;
    return [
      for (final device in _player.state.audioDevices)
        _Option(
          id: 'device:${device.name}',
          title: _deviceLabel(device),
          selected: device.name == current.name,
          onSelect: () => unawaited(() async {
            try {
              await _player.setAudioDevice(device);
              await SettingsService.instance.write(SettingsService.audioOutputDevice, device.name);
            } catch (error, stackTrace) {
              appLogger.w('Failed to set the audio output device', error: error, stackTrace: stackTrace);
            }
          }()),
        ),
    ];
  }

  int _syncValue(String property) =>
      _pendingSync[property] ?? (property == PlayerSyncOffsets.audioProperty ? _offsets.audioMs : _offsets.subtitleMs);

  /// ←/→ on the regulator: applied at once, Plezy's step, persisted at Plezy's
  /// scope; writes run in order.
  void _adjustSync(String property, int delta) {
    final target = (_syncValue(property) + delta).clamp(
      ScopedPlayerPrefs.minimumSyncOffsetMs,
      ScopedPlayerPrefs.maximumSyncOffsetMs,
    );
    setState(() => _pendingSync[property] = target);
    final player = _player;
    final metadata = _state.metadata;
    final pref = property == PlayerSyncOffsets.audioProperty
        ? ScopedPlayerPrefs.audioSyncOffset
        : ScopedPlayerPrefs.subtitleSyncOffset;
    _syncWrites = _syncWrites.then((_) async {
      try {
        await player.setProperty(property, (target / 1000.0).toString());
        PlayerSyncOffsets.of(player).recordApplied(property, target);
        await ScopedPlayerPrefs.write(pref, metadata, target);
      } catch (error, stackTrace) {
        appLogger.w('Failed to apply a sync offset', error: error, stackTrace: stackTrace);
      }
      if (mounted && _pendingSync[property] == target) setState(() => _pendingSync.remove(property));
    });
  }

  // ---- Pages ----

  String _title(TvPlayerSidePage page) => switch (page) {
    TvPlayerSidePage.settings => t.common.settings,
    TvPlayerSidePage.subtitles => t.videoControls.subtitlesLabel,
    TvPlayerSidePage.audio => t.videoControls.audioLabel,
    TvPlayerSidePage.quality => versionQualityPickerTitle(
      showVersions: _showVersions,
      showQuality: _state.serverSupportsTranscoding,
    ),
    TvPlayerSidePage.speed => t.videoSettings.playbackSpeed,
    TvPlayerSidePage.aspect => t.videoControls.aspectRatioButton,
    TvPlayerSidePage.sleepTimer => t.videoSettings.sleepTimer,
    TvPlayerSidePage.audioOutput => t.videoSettings.audioOutput,
  };

  _Row _choices(_Option option) => _Row(
    option.id,
    selected: option.selected,
    (node, up, down) => TvSettingsItem(
      key: ValueKey(option.id),
      focusNode: node,
      kind: TvSettingsItemKind.singleChoice,
      title: option.title,
      description: option.description,
      value: '',
      selected: option.selected,
      onSelect: option.onSelect,
      onNavigateUp: up,
      onNavigateDown: down,
    ),
  );

  _Row _entry(
    String id, {
    required IconData icon,
    required String title,
    String description = '',
    String value = '',
    required VoidCallback onSelect,
  }) => _Row(
    id,
    (node, up, down) => TvSettingsItem(
      key: ValueKey(id),
      focusNode: node,
      kind: TvSettingsItemKind.page,
      icon: icon,
      title: title,
      description: description,
      value: value,
      onSelect: onSelect,
      onNavigateUp: up,
      onNavigateDown: down,
    ),
  );

  _Row _sync(String property, String title) => _Row(
    'sync',
    (node, up, down) => _TvSyncItem(
      focusNode: node,
      title: title,
      value: formatSyncOffset(_syncValue(property).toDouble()),
      onLeft: () => _adjustSync(property, -_syncStepMs),
      onRight: () => _adjustSync(property, _syncStepMs),
      onUp: up,
      onDown: down,
    ),
  );

  String _selectedTitle(List<_Option> options) =>
      options.where((option) => option.selected).firstOrNull?.title ?? (options.isEmpty ? '' : t.common.off);

  List<_Row> _rows(TvPlayerSidePage page) {
    switch (page) {
      case TvPlayerSidePage.settings:
        final audio = _audioOptions().where((option) => option.selected).firstOrNull;
        final autoPlay = SettingsService.instance.read(SettingsService.autoPlayNextEpisode);
        return [
          if (_hasQuality)
            _entry(
              'quality',
              icon: Symbols.hd_rounded,
              title: _title(TvPlayerSidePage.quality),
              description: _qualityDescription(),
              value: _qualityValue(),
              onSelect: () => _push(TvPlayerSidePage.quality, 'quality'),
            ),
          _entry(
            'subtitles',
            icon: Symbols.subtitles_rounded,
            title: t.videoControls.subtitlesLabel,
            value: _selectedTitle(_subtitleOptions()),
            onSelect: () => _push(TvPlayerSidePage.subtitles, 'subtitles'),
          ),
          _entry(
            'audio',
            icon: Symbols.volume_up_rounded,
            title: t.videoControls.audioLabel,
            description: audio?.description ?? '',
            value: audio?.title ?? '',
            onSelect: () => _push(TvPlayerSidePage.audio, 'audio'),
          ),
          if (_hasSpeed)
            _entry(
              'speed',
              icon: Symbols.speed_rounded,
              title: t.videoSettings.playbackSpeed,
              value: formatPlaybackRate(_rate, normalAtOne: true),
              onSelect: () => _push(TvPlayerSidePage.speed, 'speed'),
            ),
          if (_state.onCycleBoxFitMode != null)
            _entry(
              'aspect',
              icon: Symbols.aspect_ratio_rounded,
              title: t.videoControls.aspectRatioButton,
              value: _aspectLabel(_state.boxFitMode),
              onSelect: () => _push(TvPlayerSidePage.aspect, 'aspect'),
            ),
          _entry(
            'sleepTimer',
            icon: Symbols.timer_rounded,
            title: t.videoSettings.sleepTimer,
            value: _sleepValue(),
            onSelect: () => _push(TvPlayerSidePage.sleepTimer, 'sleepTimer'),
          ),
          _Row(
            'autoPlay',
            (node, up, down) => TvSettingsItem(
              key: const ValueKey('autoPlay'),
              focusNode: node,
              kind: TvSettingsItemKind.toggle,
              icon: Symbols.playlist_play_rounded,
              title: t.videoControls.autoPlayNext,
              description: '',
              value: '',
              selected: autoPlay,
              onSelect: () => unawaited(() async {
                await SettingsService.instance.write(SettingsService.autoPlayNextEpisode, !autoPlay);
                _changed();
              }()),
              onNavigateUp: up,
              onNavigateDown: down,
            ),
          ),
          _entry(
            'more',
            icon: Symbols.more_horiz_rounded,
            title: TvStrings.playerMore,
            description: TvStrings.playerMoreDescription,
            onSelect: () => _openSheet('more', (_) => VideoSettingsSheet(player: _player, trackControlsState: _state)),
          ),
        ];
      case TvPlayerSidePage.subtitles:
        final s = _state;
        return [
          ..._subtitleOptions().map(_choices),
          const _Row.divider(),
          if (!widget.isOfflinePlayback && s.canSearchSubtitles)
            _entry(
              'search',
              icon: Symbols.search_rounded,
              title: t.videoControls.searchSubtitles,
              onSelect: () => _openSheet(
                'search',
                (_) => SubtitleSearchSheet(
                  ratingKey: s.ratingKey,
                  serverId: s.serverId!,
                  mediaTitle: s.mediaTitle,
                  onSubtitleDownloaded: s.onSubtitleDownloaded,
                ),
              ),
            ),
          _sync(PlayerSyncOffsets.subtitleProperty, t.videoSettings.subtitleSync),
        ];
      case TvPlayerSidePage.audio:
        return [
          ..._audioOptions().map(_choices),
          const _Row.divider(),
          _sync(PlayerSyncOffsets.audioProperty, t.videoSettings.audioSync),
          if (_hasAudioOutput)
            _entry(
              'audioOutput',
              icon: Symbols.speaker_rounded,
              title: t.videoSettings.audioOutput,
              value: _deviceLabel(_player.state.audioDevice),
              onSelect: () => _push(TvPlayerSidePage.audioOutput, 'audioOutput'),
            ),
        ];
      case TvPlayerSidePage.quality:
        return _qualityOptions().map(_choices).toList();
      case TvPlayerSidePage.speed:
        return _speedOptions().map(_choices).toList();
      case TvPlayerSidePage.aspect:
        return _aspectOptions().map(_choices).toList();
      case TvPlayerSidePage.sleepTimer:
        return _sleepOptions().map(_choices).toList();
      case TvPlayerSidePage.audioOutput:
        return _audioOutputOptions().map(_choices).toList();
    }
  }

  /// ← in a submenu is Back (the regulator handles its own ←/→ first).
  KeyEventResult _onPageKey(FocusNode _, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft || _stack.length == 1) return KeyEventResult.ignored;
    if (event is KeyDownEvent) back();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final panel = TvTokens.player.rightPanel;
    final current = page;
    final rows = _rows(current);
    final focusable = [
      for (final row in rows)
        if (row.build != null) row.id,
    ];
    void go(int index) {
      if (index < 0 || index >= focusable.length) return;
      _node(current, focusable[index]).requestFocus();
    }

    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: px(panel.w),
        height: double.infinity,
        child: ColoredBox(
          color: panel.bg,
          child: Padding(
            padding: EdgeInsets.fromLTRB(px(panel.padLeft), px(panel.padTop), px(panel.padRight), px(panel.padTop)),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onPageKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (_stack.length > 1)
                        Icon(Icons.chevron_left, size: px(32), color: TvTokens.color.text.secondary),
                      Expanded(
                        child: Text(_title(current), style: theme.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  SizedBox(height: px(24)),
                  Expanded(
                    child: SingleChildScrollView(
                      key: ValueKey(current),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final row in rows)
                            if (row.build == null)
                              Divider(height: px(17), thickness: 1, color: TvTokens.color.text.tertiary)
                            else
                              row.build!(
                                _node(current, row.id),
                                () => go(focusable.indexOf(row.id) - 1),
                                () => go(focusable.indexOf(row.id) + 1),
                              ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sync regulator (design-system 6.4): «‹ value ›», ←/→ change it in place.
class _TvSyncItem extends StatelessWidget {
  const _TvSyncItem({
    required this.focusNode,
    required this.title,
    required this.value,
    required this.onLeft,
    required this.onRight,
    required this.onUp,
    required this.onDown,
  });

  final FocusNode focusNode;
  final String title, value;
  final VoidCallback onLeft, onRight, onUp, onDown;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    return TvFocusable(
      kind: TvFocusKind.outline,
      radius: TvTokens.radius.button.toDouble(),
      focusNode: focusNode,
      autoScroll: true,
      semanticLabel: title,
      semanticValue: value,
      onNavigateLeft: onLeft,
      onNavigateRight: onRight,
      onNavigateUp: onUp,
      onNavigateDown: onDown,
      builder: (context, state) => SizedBox(
        height: px(TvTokens.player.rightPanel.itemMinH),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: px(24)),
          child: Row(
            children: [
              SizedBox(
                width: px(TvTokens.size.rightPanel.iconSize),
                child: Icon(Symbols.sync_rounded, size: px(28), color: TvTokens.color.text.primary),
              ),
              SizedBox(width: px(24)),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      TvStrings.playerSyncStep,
                      style: theme.caption.copyWith(color: TvTokens.color.text.tertiary),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, size: px(24), color: TvTokens.color.text.secondary),
              Text(value, style: theme.body.copyWith(fontWeight: FontWeight.w600)),
              Icon(Icons.chevron_right, size: px(24), color: TvTokens.color.text.secondary),
            ],
          ),
        ),
      ),
    );
  }
}
