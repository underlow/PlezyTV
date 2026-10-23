import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../focus/card_focus_scope.dart';
import '../../focus/dpad_navigator.dart';
import '../../focus/focusable_wrapper.dart';
import '../../services/device_performance.dart';
import 'tv_theme.dart';
import 'tv_tokens.dart';

enum TvFocusKind { ring, fill, outline }

enum TvDisabledFocus { skip, focusable }

@immutable
class TvFocusState {
  const TvFocusState({required this.focused, required this.pressed, required this.disabled});

  /// Visible keyboard/D-pad focus. Disabled controls never show focus chrome.
  final bool focused;
  final bool pressed;
  final bool disabled;
}

/// TV focus visuals around one visual surface. Keep captions outside this widget
/// when only the artwork should scale. All dimensional arguments are design px.
/// Input, traversal, semantics and activation belong to Plezy. TV screens and
/// rows own scrolling; upstream auto-scroll is off by default.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.builder,
    this.kind = TvFocusKind.ring,
    this.focusedScale,
    this.scaleAlignment = Alignment.center,
    this.radius,
    this.disabled = false,
    this.disabledFocus = TvDisabledFocus.skip,
    this.canRequestFocus = true,
    this.focusNode,
    this.autofocus = false,
    this.onSelect,
    this.onLongPress,
    this.onFocusChange,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
    this.autoScroll = false,
    this.scrollAlignment = 0.5,
    this.useComfortableZone = false,
    this.semanticLabel,
    this.semanticValue,
    this.checked,
    this.excludeChildSemantics = true,
    this.descendantsAreFocusable = false,
  });

  final Widget Function(BuildContext context, TvFocusState state) builder;
  final TvFocusKind kind;
  final double? focusedScale;
  final Alignment scaleAlignment;
  final double? radius;
  final bool disabled;
  final TvDisabledFocus disabledFocus;
  final bool canRequestFocus;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onSelect, onLongPress, onNavigateUp, onNavigateDown, onNavigateLeft, onNavigateRight, onBack;
  final ValueChanged<bool>? onFocusChange;
  final bool autoScroll, useComfortableZone;
  final double scrollAlignment;
  final String? semanticLabel, semanticValue;
  final bool? checked;
  final bool excludeChildSemantics, descendantsAreFocusable;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_observeKey);
  }

  // Observe only: always let the upstream controller handle the event, including
  // suppressed key-up after a long press. Never dispatch activation here.
  bool _observeKey(KeyEvent event) {
    if (event.logicalKey.isSelectKey) {
      final pressed = event is! KeyUpEvent && _focused && !widget.disabled;
      if (_pressed != pressed) setState(() => _pressed = pressed);
    }
    return false;
  }

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.disabled) _pressed = false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_observeKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusableWrapper(
    focusNode: widget.focusNode,
    autofocus: widget.autofocus,
    canRequestFocus: widget.canRequestFocus && (!widget.disabled || widget.disabledFocus == TvDisabledFocus.focusable),
    disableScale: true,
    delegateFocusBorder: true,
    // This upstream path activates on release and preserves long-press suppression.
    enableLongPress: true,
    onSelect: widget.disabled ? null : widget.onSelect,
    onLongPress: widget.disabled ? null : widget.onLongPress,
    onFocusChange: (focused) {
      setState(() {
        _focused = focused;
        if (!focused) _pressed = false;
      });
      widget.onFocusChange?.call(focused);
    },
    onNavigateUp: widget.onNavigateUp,
    onNavigateDown: widget.onNavigateDown,
    onNavigateLeft: widget.onNavigateLeft,
    onNavigateRight: widget.onNavigateRight,
    onBack: widget.onBack,
    autoScroll: widget.autoScroll,
    scrollAlignment: widget.scrollAlignment,
    useComfortableZone: widget.useComfortableZone,
    semanticLabel: widget.semanticLabel,
    semanticValue: widget.semanticValue,
    checked: widget.checked,
    excludeChildSemantics: widget.excludeChildSemantics,
    descendantsAreFocusable: widget.descendantsAreFocusable,
    child: Builder(
      builder: (context) {
        final focused = !widget.disabled && (CardFocusScope.maybeOf(context) ?? false);
        final pressed = focused && _pressed;
        return _TvFocusVisual(
          state: TvFocusState(focused: focused, pressed: pressed, disabled: widget.disabled),
          kind: widget.kind,
          focusedScale: widget.focusedScale ?? TvTokens.focus.cardScale,
          alignment: widget.scaleAlignment,
          radius: widget.radius,
          builder: widget.builder,
        );
      },
    ),
  );
}

class _TvFocusVisual extends ImplicitlyAnimatedWidget {
  _TvFocusVisual({
    required this.state,
    required this.kind,
    required this.focusedScale,
    required this.alignment,
    required this.radius,
    required this.builder,
  }) : super(
         duration: Duration(
           milliseconds: DevicePerformance.isReduced
               ? 0
               : state.pressed
               ? TvTokens.motion.press
               : state.focused
               ? TvTokens.motion.focusIn
               : TvTokens.motion.focusOut,
         ),
         curve: Curves.easeOutCubic,
       );
  final TvFocusState state;
  final TvFocusKind kind;
  final double focusedScale;
  final Alignment alignment;
  final double? radius;
  final Widget Function(BuildContext, TvFocusState) builder;
  @override
  AnimatedWidgetBaseState<_TvFocusVisual> createState() => _TvFocusVisualState();
}

class _TvFocusVisualState extends AnimatedWidgetBaseState<_TvFocusVisual> {
  Tween<double>? _scale, _opacity;
  bool _wasPressed = false;
  @override
  void didUpdateWidget(_TvFocusVisual oldWidget) {
    // Both press and release use the press duration.
    _wasPressed = oldWidget.state.pressed;
    super.didUpdateWidget(oldWidget);
    if (_wasPressed && !widget.state.pressed && widget.state.focused && !DevicePerformance.isReduced) {
      controller.duration = Duration(milliseconds: TvTokens.motion.press);
      controller.forward(from: 0);
    }
  }

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    final focusScale = widget.kind == TvFocusKind.outline ? 1.0 : widget.focusedScale;
    _scale =
        visitor(
              _scale,
              widget.state.focused ? focusScale * (widget.state.pressed ? TvTokens.focus.pressedScale : 1) : 1.0,
              (value) => Tween<double>(begin: value as double),
            )
            as Tween<double>?;
    _opacity =
        visitor(
              _opacity,
              widget.state.disabled ? TvTokens.focus.disabledOpacity : 1.0,
              (value) => Tween<double>(begin: value as double),
            )
            as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    final radius = px(
      widget.radius ?? (widget.kind == TvFocusKind.ring ? TvTokens.radius.card : TvTokens.radius.button),
    );
    final focused = widget.state.focused;
    Widget child = widget.builder(context, widget.state);
    if (focused && widget.kind != TvFocusKind.ring) {
      child = DecoratedBox(
        decoration: BoxDecoration(
          color: widget.kind == TvFocusKind.fill
              ? TvTokens.color.focus.fill
              : widget.state.pressed
              ? TvTokens.color.surface.level2
              : TvTokens.color.surface.level3,
          borderRadius: BorderRadius.circular(radius),
          border: widget.kind == TvFocusKind.outline
              ? Border.all(color: TvTokens.color.focus.ring, width: px(TvTokens.size.focusRing.width))
              : null,
        ),
        child: child,
      );
    }
    if (focused && widget.kind == TvFocusKind.ring) {
      final gap = px(TvTokens.size.focusRing.offset);
      final width = px(TvTokens.size.focusRing.width);
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            left: -gap - width,
            top: -gap - width,
            right: -gap - width,
            bottom: -gap - width,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: TvTokens.color.focus.ring, width: width),
                  borderRadius: BorderRadius.circular(radius + gap + width),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Opacity(
      opacity: _opacity!.evaluate(animation),
      child: _PaintScale(scale: _scale!.evaluate(animation), alignment: widget.alignment, child: child),
    );
  }
}

// Match upstream paint-only scaling: layout, hit testing and semantics stay put.
class _PaintScale extends SingleChildRenderObjectWidget {
  const _PaintScale({required this.scale, required this.alignment, required super.child});
  final double scale;
  final Alignment alignment;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPaintScale(scale, alignment);
  @override
  void updateRenderObject(BuildContext context, _RenderPaintScale renderObject) {
    renderObject.update(scale, alignment);
  }
}

class _RenderPaintScale extends RenderProxyBox {
  _RenderPaintScale(this.scale, this.alignment);
  double scale;
  Alignment alignment;
  void update(double value, Alignment origin) {
    if (scale == value && alignment == origin) return;
    scale = value;
    alignment = origin;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = alignment.alongSize(size);
    final transform = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(origin.dx * (1 - scale), origin.dy * (1 - scale), 0);
    layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }
}
