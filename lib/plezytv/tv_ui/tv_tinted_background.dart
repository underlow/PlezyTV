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
    this.timer = Timer.new,
    this.child,
  });
  final TvArtworkSource source;
  final TvTintService? service;
  final bool showBackdrop;
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
            _previous = _target;
            _releaseOldImages();
          });
        }
      });
  Widget _previous = const _BackgroundLook();
  _BackgroundLook _target = const _BackgroundLook();
  final _images = <ui.Image>[];
  Timer? _debounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _request(first: true);
  }

  @override
  void didUpdateWidget(TvTintedBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.cacheKey == widget.source.cacheKey &&
        oldWidget.service == widget.service &&
        oldWidget.showBackdrop == widget.showBackdrop) {
      return;
    }
    _debounce?.cancel();
    _generation++;
    _debounce = widget.timer(Duration(milliseconds: TvTokens.motion.heroDebounce), () => _request());
  }

  Future<void> _request({bool first = false}) async {
    final generation = ++_generation;
    final source = widget.source;
    final service = widget.service ?? TvTintService.shared;
    ui.Image? readyBackdrop;
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
          readyBackdrop = image;
          if (tintApplied && image != null) _images.add(image);
          if (tintApplied) {
            setState(() {
              _target = _BackgroundLook(tint: readyTint, backdrop: image);
              if (_fade.isCompleted) _previous = _target;
            });
          }
        }),
      );
    }
    final tint = await service.tintFor(source);
    if (!mounted || generation != _generation) {
      readyBackdrop?.dispose();
      return;
    }
    if (readyBackdrop != null) _images.add(readyBackdrop!);
    readyTint = tint;
    tintApplied = true;
    final next = _BackgroundLook(tint: tint, backdrop: readyBackdrop);
    setState(() {
      if (first || DevicePerformance.isReduced) {
        _fade.stop();
        _previous = _target = next;
        _releaseOldImages();
        _fade.value = 1;
      } else {
        // Freeze the actual composited look at this instant. No color or
        // geometry interpolation; only the new layer's opacity animates.
        _previous = _currentLook();
        _fade.stop();
        _target = next;
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

  void _releaseOldImages() {
    for (final image in _images.where((image) => image != _target.backdrop)) {
      image.dispose();
    }
    _images.removeWhere((image) => image != _target.backdrop);
  }

  Widget _currentLook() => _fade.value == 1
      ? _target
      : Stack(
          fit: StackFit.expand,
          children: [
            _previous,
            Opacity(opacity: _fade.value, child: _target),
          ],
        );

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _fade.dispose();
    for (final image in _images) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      AnimatedBuilder(animation: _fade, builder: (context, _) => _currentLook()),
      ?widget.child,
    ],
  );
}

class _BackgroundLook extends StatelessWidget {
  const _BackgroundLook({this.tint, this.backdrop, this.child});
  final Color? tint;
  final ui.Image? backdrop;
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
              width: theme.px(1300),
              height: theme.px(780),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .55, 1],
                  colors: [Colors.white, Colors.white, Colors.transparent],
                ).createShader(rect),
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    stops: [0, .55, 1],
                    colors: [Colors.transparent, Colors.white, Colors.white],
                  ).createShader(rect),
                  child: RawImage(image: backdrop, fit: BoxFit.cover),
                ),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: theme.px(1100),
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [base, base.withValues(alpha: 0)])),
              ),
            ),
          ],
          ?child,
        ],
      ),
    );
  }
}
