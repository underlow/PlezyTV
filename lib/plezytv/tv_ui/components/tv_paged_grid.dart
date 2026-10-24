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
  @override
  State<TvPagedGrid<T>> createState() => TvPagedGridState<T>();
}

class TvPagedGridState<T> extends State<TvPagedGrid<T>> {
  final _scroll = ScrollController();
  final _nodes = <int, FocusNode>{};
  int focusedIndex = 0, _transition = 0;
  int? _pending;
  bool get isJumping => _pending != null;
  @override
  void initState() {
    super.initState();
    widget.source.addListener(_structure);
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
    if (widget.source.totalCount == null) {
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
      final extent = TvTheme.of(context).px(widget.cellHeight + widget.gap);
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
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: px(widget.columns * widget.cellWidth + (widget.columns - 1) * widget.gap),
        child: GridView.builder(
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
              widget.onItemFocused?.call(index);
            },
            onSelect: () => widget.onSelect?.call(index),
            onLongPress: () => widget.onLongPress?.call(index),
            builder: widget.itemBuilder,
            decorateFocus: widget.decorateFocus,
          ),
        ),
      ),
    );
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
