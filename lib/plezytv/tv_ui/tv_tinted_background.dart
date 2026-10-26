import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/device_performance.dart';
import 'tv_theme.dart';
import 'tv_tokens.dart';
import 'tv_tint_service.dart';

typedef TvBackgroundTimer = Timer Function(Duration duration, void Function() callback);

Color tvBackgroundTop(Color? tint) =>
    Color.lerp(TvTokens.color.bg.base, tint ?? TvTokens.color.bg.base, TvTokens.color.bg.tintStrength)!;

class TvPlainBackground extends StatelessWidget {
  const TvPlainBackground({super.key, this.child});
  final Widget? child;
  @override
  Widget build(BuildContext context) => _BackgroundLook(tint: const Color(0xFF182331), child: child);
}

/// Decorative, opt-in background. All dimensions are TV design pixels.
class TvTintedBackground extends StatefulWidget {
  const TvTintedBackground({
    super.key,
    required this.source,
    this.service,
    this.showBackdrop = true,
    this.scrollController,
    this.timer = Timer.new,
    this.child,
  });
  final TvArtworkSource source;
  final TvTintService? service;
  final bool showBackdrop;
  final ScrollController? scrollController;
  final TvBackgroundTimer timer;
  final Widget? child;

  @override
  State<TvTintedBackground> createState() => _TvTintedBackgroundState();
}

class _TvTintedBackgroundState extends State<TvTintedBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _fade =
      AnimationController(
        vsync: this,
        duration: Duration(milliseconds: TvTokens.motion.bgTintCrossfade),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _previous = [(_target, 1)];
            _releaseOldImages();
          });
        }
      });
  List<(_BackgroundLook, double)> _previous = [(const _BackgroundLook(), 1)];
  _BackgroundLook _target = const _BackgroundLook();
  final _images = <ui.Image>[];
  ui.Image? _pendingBackdrop;
  Timer? _debounce;
  int _generation = 0;
  final _backdropOpacity = ValueNotifier<double>(1);
  double _scale = 1;

  void _updateBackdropOpacity() {
    final page = widget.scrollController;
    final offset = page != null && page.hasClients ? page.offset / _scale : 0.0;
    _backdropOpacity.value = (1 - offset / TvTokens.detail.collapseAt).clamp(0.0, 1.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scale = TvTheme.of(context).scale;
    _updateBackdropOpacity();
  }

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_updateBackdropOpacity);
    _request(first: true);
  }

  @override
  void didUpdateWidget(TvTintedBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_updateBackdropOpacity);
      widget.scrollController?.addListener(_updateBackdropOpacity);
      _updateBackdropOpacity();
    }
    if (oldWidget.source.cacheKey == widget.source.cacheKey &&
        oldWidget.service == widget.service &&
        oldWidget.showBackdrop == widget.showBackdrop) {
      return;
    }
    _debounce?.cancel();
    _generation++;
    _releasePendingBackdrop();
    _debounce = widget.timer(Duration(milliseconds: TvTokens.motion.heroDebounce), () => _request());
  }

  Future<void> _request({bool first = false}) async {
    final generation = ++_generation;
    final source = widget.source;
    final service = widget.service ?? TvTintService.shared;
    Color? readyTint;
    var tintApplied = false;
    // Do not let a slow backdrop delay the tint transition. A decoded backdrop
    // joins the same target layer, retaining that layer's current opacity.
    if (widget.showBackdrop) {
      unawaited(
        _backdrop(service, source).then((image) {
          if (!mounted || generation != _generation) {
            image?.dispose();
            return;
          }
          if (tintApplied) {
            if (image != null) _images.add(image);
          } else {
            _pendingBackdrop = image;
          }
          if (tintApplied) {
            setState(() {
              _target = _BackgroundLook(tint: readyTint, backdrop: image, backdropOpacity: _backdropOpacity);
              if (_fade.isCompleted) _previous = [(_target, 1)];
            });
          }
        }),
      );
    }
    final tint = await service.tintFor(source);
    if (!mounted || generation != _generation) {
      return;
    }
    final readyBackdrop = _pendingBackdrop;
    _pendingBackdrop = null;
    if (readyBackdrop != null) _images.add(readyBackdrop);
    readyTint = tint;
    tintApplied = true;
    final next = _BackgroundLook(tint: tint, backdrop: readyBackdrop, backdropOpacity: _backdropOpacity);
    setState(() {
      if (first || DevicePerformance.isReduced) {
        _fade.stop();
        _target = next;
        _previous = [(next, 1)];
        _releaseOldImages();
        _fade.value = 1;
      } else {
        // Keep a flat snapshot of the two newest looks. The first interruption
        // is exact; further interruptions approximate the oldest contribution
        // by making the retained bottom look opaque, bounding layers and images.
        _previous = _fade.value == 1 ? [(_target, 1)] : [..._previous, (_target, _fade.value)];
        if (_previous.length > 2) {
          _previous = [(_previous[_previous.length - 2].$1, 1), _previous.last];
        }
        _fade.stop();
        _target = next;
        _releaseOldImages();
        _fade.forward(from: 0);
      }
    });
  }

  Future<ui.Image?> _backdrop(TvTintService service, TvArtworkSource source) async {
    try {
      final bytes = await service.fetch(source, true, 1280);
      return bytes == null ? null : await service.decode(bytes, 1280);
    } catch (_) {
      return null;
    }
  }

  void _releasePendingBackdrop() {
    _pendingBackdrop?.dispose();
    _pendingBackdrop = null;
  }

  void _releaseOldImages() {
    final retained = {_target.backdrop, ..._previous.map((look) => look.$1.backdrop)};
    for (final image in _images.where((image) => !retained.contains(image))) {
      image.dispose();
    }
    _images.removeWhere((image) => !retained.contains(image));
  }

  Widget _currentLook() {
    final previous = [
      for (final (look, opacity) in _previous)
        if (opacity == 1) look else Opacity(opacity: opacity, child: look),
    ];
    return AnimatedBuilder(
      animation: _fade,
      child: _target,
      builder: (context, child) => _fade.value == 1
          ? child!
          : Stack(
              fit: StackFit.expand,
              children: [
                ...previous,
                Opacity(opacity: _fade.value, child: child),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _generation++;
    widget.scrollController?.removeListener(_updateBackdropOpacity);
    _backdropOpacity.dispose();
    _releasePendingBackdrop();
    _debounce?.cancel();
    _fade.dispose();
    for (final image in _images) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [_currentLook(), ?widget.child]);
}

class _BackgroundLook extends StatelessWidget {
  const _BackgroundLook({this.tint, this.backdrop, this.child, this.backdropOpacity});
  final Color? tint;
  final ui.Image? backdrop;
  final ValueNotifier<double>? backdropOpacity;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final base = TvTokens.color.bg.base;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .85, 1],
          colors: [tvBackgroundTop(tint), base, base],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdrop != null) ...[
            Positioned(
              top: 0,
              right: 0,
              width: theme.px(TvTokens.backdrop.width),
              height: theme.px(TvTokens.backdrop.height),
              child: ValueListenableBuilder<double>(
                valueListenable: backdropOpacity ?? const AlwaysStoppedAnimation(1.0),
                builder: (context, value, child) =>
                    FadeTransition(opacity: AlwaysStoppedAnimation(value), child: child),
                child: RepaintBoundary(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [
                        0,
                        TvTokens.backdrop.fadeOutStart / TvTokens.backdrop.height,
                        TvTokens.backdrop.fadeOutEnd / TvTokens.backdrop.height,
                        1,
                      ],
                      colors: [Colors.white, Colors.white, Colors.transparent, Colors.transparent],
                    ).createShader(rect),
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => LinearGradient(
                        stops: [
                          0,
                          (TvTokens.backdrop.fadeInStart - TvTokens.backdrop.left) / TvTokens.backdrop.width,
                          (TvTokens.backdrop.fadeInEnd - TvTokens.backdrop.left) / TvTokens.backdrop.width,
                          1,
                        ],
                        colors: [Colors.transparent, Colors.transparent, Colors.white, Colors.white],
                      ).createShader(rect),
                      child: ColoredBox(
                        color: base,
                        child: RawImage(
                          image: backdrop,
                          fit: BoxFit.cover,
                          opacity: AlwaysStoppedAnimation(TvTokens.backdrop.opacity),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          ?child,
        ],
      ),
    );
  }
}
