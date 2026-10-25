import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tv_theme.dart';
import '../tv_focusable.dart';
import '../tv_tokens.dart';
import 'tv_paged_source.dart';

/// Fixed-slot, lazy grid. Builders receive visual focus and decode images at
/// card size; this widget owns focus, traversal and scrolling.
class TvPagedGrid<T> extends StatefulWidget {
  const TvPagedGrid({
    super.key,
    required this.source,
    required this.itemBuilder,
    required this.columns,
    required this.cellWidth,
    required this.cellHeight,
    this.gap = 32,
    this.decorateFocus = true,
    this.onUp,
    this.onLeft,
    this.onRight,
    this.onItemFocused,
    this.onSelect,
    this.onLongPress,
    this.onVisibleRangeChanged,
    this.onPlayPause,
    this.keyOf,
  }) : assert(columns > 0),
       assert(cellWidth > 0),
       assert(cellHeight > 0);
  final TvPagedSource<T> source;
  final Widget Function(BuildContext, int, T?, bool focused) itemBuilder;

  /// False when the item builder paints focus around its artwork only.
  final bool decorateFocus;
  final int columns;
  final double cellWidth, cellHeight, gap;
  final VoidCallback? onUp, onLeft, onRight;
  final ValueChanged<int>? onItemFocused, onSelect, onLongPress;

  /// First and last visible indices, reported after scrolling and resizing.
  final ValueChanged<(int, int)>? onVisibleRangeChanged;

  /// Physical Play/Pause (`mediaPlayPause`, `mediaPlay`) on a loaded item.
  final ValueChanged<int>? onPlayPause;

  /// Identity used to keep focus on the same item across
  /// [TvPagedSource.replaceAll] with `keepFocus: true`.
  final Object? Function(T item)? keyOf;
  @override
  State<TvPagedGrid<T>> createState() => TvPagedGridState<T>();
}

class TvPagedGridState<T> extends State<TvPagedGrid<T>> {
  final _scroll = ScrollController();
  final _nodes = <int, FocusNode>{};
  int focusedIndex = 0, _transition = 0;
  int? _pending;
  bool get isJumping => _pending != null;
  Object? _focusedKey;
  (int, int)? _reportedRange;
  @override
  void initState() {
    super.initState();
    widget.source.addListener(_structure);
    _scroll.addListener(_reportRange);
  }

  double get _extent => TvTheme.of(context).px(widget.cellHeight + widget.gap);

  void _reportRange() {
    final callback = widget.onVisibleRangeChanged;
    if (callback == null || !mounted || !_scroll.hasClients) return;
    final count = widget.source.totalCount ?? 0;
    if (count == 0) return;
    final position = _scroll.position;
    if (!position.hasViewportDimension) return;
    final extent = _extent, offset = position.pixels;
    final firstRow = (offset / extent).floor().clamp(0, count);
    final lastRow = ((offset + position.viewportDimension) / extent).ceil() - 1;
    final first = (firstRow * widget.columns).clamp(0, count - 1);
    final last = ((lastRow + 1) * widget.columns - 1).clamp(first, count - 1);
    final range = (first, last);
    if (range == _reportedRange) return;
    _reportedRange = range;
    callback(range);
  }

  void _rememberKey(int index) {
    final item = widget.source[index], keyOf = widget.keyOf;
    _focusedKey = item == null || keyOf == null ? null : keyOf(item);
  }

  bool get _hasFocus => _nodes.values.any((node) => node.hasFocus);

  void _replaced(bool keepFocus) {
    final count = widget.source.totalCount ?? 0;
    final hadFocus = _hasFocus;
    final oldIndex = focusedIndex;
    _transition++;
    _pending = null;
    if (!keepFocus || count == 0) {
      focusedIndex = 0;
      _focusedKey = null;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      if (hadFocus && count > 0) {
        jumpTo(0, waitForLoad: false);
      }
      return;
    }
    var target = -1;
    final key = _focusedKey, keyOf = widget.keyOf;
    if (key != null && keyOf != null) {
      for (var i = 0; i < count; i++) {
        final item = widget.source[i];
        if (item != null && keyOf(item) == key) {
          target = i;
          break;
        }
      }
    }
    if (target < 0) target = oldIndex.clamp(0, count - 1);
    final rowDelta = target ~/ widget.columns - oldIndex ~/ widget.columns;
    final scrollTo = _scroll.hasClients ? _scroll.offset + rowDelta * _extent : 0.0;
    focusedIndex = target;
    _rememberKey(target);
    final epoch = _transition;
    void apply(Duration _) {
      if (!mounted || epoch != _transition) return;
      if (_scroll.hasClients) {
        _scroll.jumpTo(scrollTo.clamp(0.0, _scroll.position.maxScrollExtent));
      }
      if (!hadFocus) return;
      final node = _nodes[target];
      if (node?.context == null) {
        WidgetsBinding.instance.addPostFrameCallback(apply);
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
      if (!node!.hasFocus) node.requestFocus();
    }

    WidgetsBinding.instance.addPostFrameCallback(apply);
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void didUpdateWidget(covariant TvPagedGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      oldWidget.source.removeListener(_structure);
      widget.source.addListener(_structure);
      _transition++;
      _pending = null;
      focusedIndex = 0;
    }
  }

  void _structure() {
    if (!mounted) return;
    if (widget.source.replacingKeepFocus case final keepFocus?) {
      _replaced(keepFocus);
    } else if (widget.source.totalCount == null) {
      _transition++;
      _pending = null;
      focusedIndex = 0;
    }
    setState(() {});
  }

  void requestFocus() => jumpTo(focusedIndex, waitForLoad: false);

  /// Retain the old focused slot until the destination attaches and loads.
  Future<void> jumpTo(int index, {bool waitForLoad = true}) async {
    final count = widget.source.totalCount ?? 0;
    if (count == 0) return;
    final target = index.clamp(0, count - 1), epoch = ++_transition;
    _pending = target;
    if (_scroll.hasClients) {
      final extent = _extent;
      _scroll.jumpTo((target ~/ widget.columns * extent).clamp(0.0, _scroll.position.maxScrollExtent));
    }
    final loading = widget.source.requestIndex(target);
    if (waitForLoad) await loading;
    if (!mounted || epoch != _transition) return;
    if (waitForLoad && widget.source[target] == null) {
      _pending = null;
      return;
    }
    void apply(Duration _) {
      if (!mounted || epoch != _transition) return;
      final node = _nodes[target];
      if (node?.context == null) {
        WidgetsBinding.instance.addPostFrameCallback(apply);
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
      node!.requestFocus();
      _pending = null;
      focusedIndex = target;
    }

    WidgetsBinding.instance.addPostFrameCallback(apply);
    WidgetsBinding.instance.scheduleFrame();
  }

  KeyEventResult _key(int index, LogicalKeyboardKey key) {
    if (![
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ].contains(key)) {
      return KeyEventResult.ignored;
    }
    if (isJumping) return KeyEventResult.handled;
    final column = index % widget.columns;
    if (key == LogicalKeyboardKey.arrowUp && index < widget.columns) {
      widget.onUp?.call();
    } else if (key == LogicalKeyboardKey.arrowLeft && column == 0) {
      widget.onLeft?.call();
    } else if (key == LogicalKeyboardKey.arrowRight &&
        (column == widget.columns - 1 || index == widget.source.totalCount! - 1)) {
      widget.onRight?.call();
    } else {
      final delta = key == LogicalKeyboardKey.arrowUp
          ? -widget.columns
          : key == LogicalKeyboardKey.arrowDown
          ? widget.columns
          : key == LogicalKeyboardKey.arrowLeft
          ? -1
          : 1;
      jumpTo(index + delta, waitForLoad: false);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    if (widget.onVisibleRangeChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportRange());
    }
    Widget grid = Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: px(widget.columns * widget.cellWidth + (widget.columns - 1) * widget.gap),
        child: ClipRect(
          clipper: _GridFocusClip(px(24)),
          child: GridView.builder(
            clipBehavior: Clip.none,
            controller: _scroll,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.columns,
              mainAxisExtent: px(widget.cellHeight),
              mainAxisSpacing: px(widget.gap),
              crossAxisSpacing: px(widget.gap),
            ),
            itemCount: widget.source.totalCount ?? 0,
            itemBuilder: (context, index) => _GridSlot<T>(
              key: ValueKey((widget.source, index)),
              source: widget.source,
              index: index,
              register: (node) => _nodes[index] = node,
              unregister: () => _nodes.remove(index),
              onKey: (event) => _key(index, event),
              onFocus: () {
                focusedIndex = index;
                _rememberKey(index);
                widget.onItemFocused?.call(index);
              },
              onSelect: () => widget.onSelect?.call(index),
              onLongPress: () => widget.onLongPress?.call(index),
              builder: widget.itemBuilder,
              decorateFocus: widget.decorateFocus,
            ),
          ),
        ),
      ),
    );
    if (widget.onPlayPause != null) {
      grid = Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent ||
              (event.logicalKey != LogicalKeyboardKey.mediaPlayPause &&
                  event.logicalKey != LogicalKeyboardKey.mediaPlay)) {
            return KeyEventResult.ignored;
          }
          final index = focusedIndex;
          if (!_hasFocus || widget.source[index] == null) return KeyEventResult.ignored;
          widget.onPlayPause!(index);
          return KeyEventResult.handled;
        },
        child: grid,
      );
    }
    return grid;
  }

  @override
  void dispose() {
    _transition++;
    widget.source.removeListener(_structure);
    _scroll.dispose();
    super.dispose();
  }
}

class _GridSlot<T> extends StatefulWidget {
  const _GridSlot({
    super.key,
    required this.source,
    required this.index,
    required this.register,
    required this.unregister,
    required this.onKey,
    required this.onFocus,
    required this.onSelect,
    required this.onLongPress,
    required this.builder,
    required this.decorateFocus,
  });
  final TvPagedSource<T> source;
  final bool decorateFocus;
  final int index;
  final ValueChanged<FocusNode> register;
  final VoidCallback unregister, onFocus, onSelect, onLongPress;
  final KeyEventResult Function(LogicalKeyboardKey) onKey;
  final Widget Function(BuildContext, int, T?, bool) builder;
  @override
  State<_GridSlot<T>> createState() => _GridSlotState<T>();
}

class _GridSlotState<T> extends State<_GridSlot<T>> with AutomaticKeepAliveClientMixin {
  late final FocusNode node = FocusNode(debugLabel: 'TV grid ${widget.index}');
  @override
  bool get wantKeepAlive => node.hasFocus;
  @override
  void initState() {
    super.initState();
    widget.register(node);
    node.addListener(_focus);
    widget.source.requestIndex(widget.index);
  }

  @override
  void didUpdateWidget(covariant _GridSlot<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.source.requestIndex(widget.index);
  }

  void _focus() {
    updateKeepAlive();
    setState(() {});
    if (node.hasFocus) widget.onFocus();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    void navigate(LogicalKeyboardKey key) => widget.onKey(key);
    return ListenableBuilder(
      listenable: widget.source.pageListenable(widget.index),
      builder: (context, _) {
        if (widget.source.needsReload(widget.index)) widget.source.requestIndex(widget.index);
        return TvFocusable(
          decorateFocus: widget.decorateFocus || widget.source[widget.index] == null,
          focusNode: node,
          onNavigateUp: () => navigate(LogicalKeyboardKey.arrowUp),
          onNavigateDown: () => navigate(LogicalKeyboardKey.arrowDown),
          onNavigateLeft: () => navigate(LogicalKeyboardKey.arrowLeft),
          onNavigateRight: () => navigate(LogicalKeyboardKey.arrowRight),
          onSelect: widget.source[widget.index] == null ? null : widget.onSelect,
          onLongPress: widget.source[widget.index] == null ? null : widget.onLongPress,
          builder: (context, state) => widget.source[widget.index] == null
              ? ColoredBox(color: TvTokens.color.bg.skeleton)
              : widget.builder(context, widget.index, widget.source[widget.index], state.focused),
        );
      },
    );
  }

  @override
  void dispose() {
    widget.unregister();
    node.dispose();
    super.dispose();
  }
}

// Preserve the focused artwork's scale/ring at every edge while still clipping
// scrolled rows before they can paint over the tab row or screen header.
class _GridFocusClip extends CustomClipper<Rect> {
  const _GridFocusClip(this.margin);
  final double margin;
  @override
  Rect getClip(Size size) => (Offset.zero & size).inflate(margin);
  @override
  bool shouldReclip(_GridFocusClip oldClipper) => oldClipper.margin != margin;
}
