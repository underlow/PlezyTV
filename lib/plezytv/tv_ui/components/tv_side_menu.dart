import 'package:flutter/material.dart';

import '../../../services/device_performance.dart';
import '../tv_focusable.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

@immutable
class TvSideMenuItem {
  const TvSideMenuItem({
    this.key,
    required this.icon,
    required this.label,
    this.onSelect,
    this.focusNode,
    this.disabled = false,
  });

  /// Stable identity across rebuilds. Labels must be unique when no key is supplied.
  final LocalKey? key;
  final IconData icon;
  final String label;
  final VoidCallback? onSelect;
  final FocusNode? focusNode;
  final bool disabled;
}

/// Overlays the caller's content with a rail, expanding when focus enters it.
/// The caller owns selection, navigation and the optional divider before an item.
class TvSideMenu extends StatefulWidget {
  const TvSideMenu({
    super.key,
    required this.items,
    this.currentIndex,
    required this.child,
    this.dividerBeforeIndex,
    this.focusNode,
  }) : assert(currentIndex == null || (currentIndex >= 0 && currentIndex < items.length)),
       assert(dividerBeforeIndex == null || (dividerBeforeIndex >= 0 && dividerBeforeIndex < items.length));
  final List<TvSideMenuItem> items;
  final int? currentIndex;
  final int? dividerBeforeIndex;
  final Widget child;

  /// Optional entry target: requesting focus selects the current or first enabled item.
  final FocusNode? focusNode;

  @override
  State<TvSideMenu> createState() => _TvSideMenuState();
}

class _TvSideMenuState extends State<TvSideMenu> {
  bool _expanded = false;
  final _nodes = <LocalKey, FocusNode>{};

  void _handleEntryFocus() {
    if (widget.focusNode?.hasPrimaryFocus ?? false) _focusEntry();
  }

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_handleEntryFocus);
    _showCurrent();
  }

  LocalKey _key(TvSideMenuItem item) => item.key ?? ValueKey(item.label);
  FocusNode _node(TvSideMenuItem item) => item.focusNode ?? _nodes.putIfAbsent(_key(item), () => FocusNode());

  void _focusEntry() {
    final current = widget.currentIndex;
    final candidates = [if (current != null) widget.items[current], ...widget.items];
    for (final item in candidates) {
      if (!item.disabled) {
        _node(item).requestFocus();
        return;
      }
    }
  }

  @override
  void didUpdateWidget(TvSideMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleEntryFocus);
      widget.focusNode?.addListener(_handleEntryFocus);
    }
    final oldCurrent = oldWidget.currentIndex == null ? null : _key(oldWidget.items[oldWidget.currentIndex!]);
    final current = widget.currentIndex == null ? null : _key(widget.items[widget.currentIndex!]);
    if (current != oldCurrent) _showCurrent();
    final keys = widget.items.map(_key).toSet();
    assert(keys.length == widget.items.length, 'Menu item keys must be unique');
    final removedFocus = oldWidget.items.any((item) => !keys.contains(_key(item)) && _node(item).hasFocus);
    // Dispose after the old focus widgets have detached their listeners.
    final removed = _nodes.keys.where((key) => !keys.contains(key)).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final key in removed) {
        _nodes.remove(key)?.dispose();
      }
      if (removedFocus) {
        _focusEntry();
      } else {
        for (final item in widget.items) {
          if (_node(item).hasFocus) _showFocused(_key(item));
        }
      }
    });
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_handleEntryFocus);
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _showCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _expanded || widget.currentIndex == null) return;
      final context = _node(widget.items[widget.currentIndex!]).context;
      if (context != null) {
        final scrollable = Scrollable.maybeOf(context);
        if (scrollable == null) return;
        final viewport = scrollable.context.findRenderObject()! as RenderBox;
        final box = context.findRenderObject()! as RenderBox;
        final above = box.localToGlobal(Offset.zero, ancestor: viewport).dy < 0;
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: above
              ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
              : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  void _showFocused(LocalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final item = widget.items.where((item) => _key(item) == key).firstOrNull;
      final context = item == null ? null : _node(item).context;
      if (context == null || !_node(item!).hasFocus) return;
      final scrollable = Scrollable.maybeOf(context);
      if (scrollable == null) return;
      final viewport = scrollable.context.findRenderObject()! as RenderBox;
      final itemBox = context.findRenderObject()! as RenderBox;
      final above = itemBox.localToGlobal(Offset.zero, ancestor: viewport).dy < 0;
      Scrollable.ensureVisible(
        context,
        duration: Duration(milliseconds: DevicePerformance.isReduced ? 0 : TvTokens.motion.sidebarExpand),
        alignmentPolicy: above
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final sizes = TvTokens.size.sidebar;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_expanded) Positioned.fill(child: ColoredBox(color: TvTokens.color.surface.scrim)),
        Align(
          alignment: Alignment.centerLeft,
          child: Focus(
            focusNode: widget.focusNode,
            canRequestFocus: widget.focusNode != null,
            onFocusChange: (value) {
              setState(() => _expanded = value);
              if (!value && widget.currentIndex != null) _showCurrent();
            },
            child: AnimatedContainer(
              duration: Duration(milliseconds: DevicePerformance.isReduced ? 0 : TvTokens.motion.sidebarExpand),
              curve: Curves.easeOutCubic,
              width: px(_expanded ? sizes.expandedW : sizes.collapsedW),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(color: _expanded ? TvTokens.color.surface.level1 : Colors.transparent),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: px(sizes.expandedW),
                maxWidth: px(sizes.expandedW),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final dividerHeight = widget.dividerBeforeIndex == null ? 0.0 : px(33);
                    final itemHeight = widget.items.isEmpty
                        ? px(sizes.itemH)
                        : ((constraints.maxHeight - dividerHeight) / widget.items.length).clamp(
                            px(sizes.minItemH),
                            px(sizes.itemH),
                          );
                    final overflow = itemHeight * widget.items.length + dividerHeight > constraints.maxHeight;
                    Widget item(int i) => SizedBox(
                      key: _key(widget.items[i]),
                      height: itemHeight,
                      child: Stack(
                        children: [
                          if (widget.currentIndex == i)
                            Positioned(
                              left: 0,
                              top: (itemHeight - px(sizes.currentMarker[1])) / 2,
                              child: SizedBox(
                                width: px(sizes.currentMarker[0]),
                                height: px(sizes.currentMarker[1]),
                                child: ColoredBox(color: TvTokens.color.accent.normal),
                              ),
                            ),
                          // Keyed: the marker coming or going must not
                          // recreate the item and drop its focus visual.
                          Positioned(
                            key: const ValueKey('item'),
                            left: px(sizes.padLeft),
                            top: 0,
                            bottom: 0,
                            width: px(_expanded ? sizes.expandedW - sizes.padLeft * 2 : sizes.itemW),
                            child: _item(context, widget.items[i]),
                          ),
                        ],
                      ),
                    );
                    Widget divider() => Padding(
                      padding: EdgeInsets.symmetric(horizontal: px(32), vertical: px(16)),
                      child: Divider(height: px(1), thickness: px(1), color: TvTokens.color.surface.level3),
                    );
                    // The shell places Settings last. Keep it outside the scroll
                    // viewport when the minimum row height cannot fit the list.
                    final pinLast = overflow && widget.items.isNotEmpty;
                    final count = widget.items.length - (pinLast ? 1 : 0);
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < count; i++) ...[
                                  if (widget.dividerBeforeIndex == i) divider(),
                                  item(i),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (pinLast) ...[if (widget.dividerBeforeIndex == count) divider(), item(count)],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _item(BuildContext context, TvSideMenuItem item) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final sizes = TvTokens.size.sidebar;
    final enabled = widget.items.where((item) => !item.disabled);
    return TvFocusable(
      kind: TvFocusKind.fill,
      focusedScale: 1,
      disabled: item.disabled,
      focusNode: _node(item),
      // Keep vertical traversal inside the rail at its enabled endpoints.
      onNavigateUp: item == enabled.firstOrNull ? () {} : null,
      onNavigateDown: item == enabled.lastOrNull ? () {} : null,
      onFocusChange: (focused) {
        if (focused) _showFocused(_key(item));
      },
      semanticLabel: item.label,
      onSelect: item.onSelect,
      builder: (context, state) => Container(
        decoration: BoxDecoration(
          color: state.pressed
              ? TvTokens.color.text.secondary
              : state.focused
              ? TvTokens.color.focus.fill
              : Colors.transparent,
          borderRadius: BorderRadius.circular(px(TvTokens.radius.button)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: px(sizes.itemW),
              child: Center(
                child: Icon(
                  item.icon,
                  size: px(sizes.iconSize),
                  color: state.focused ? TvTokens.color.text.onFocus : TvTokens.color.text.primary,
                ),
              ),
            ),
            if (_expanded)
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.label.copyWith(
                    color: state.focused ? TvTokens.color.text.onFocus : TvTokens.color.text.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
