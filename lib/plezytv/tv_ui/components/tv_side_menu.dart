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

  void _showFocused(LocalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final item = widget.items.where((item) => _key(item) == key).firstOrNull;
      final context = item == null ? null : _node(item).context;
      if (context == null || !_node(item!).hasFocus) return;
      final scrollable = Scrollable.of(context);
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
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < widget.items.length; i++) ...[
                            if (widget.dividerBeforeIndex == i)
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: px(32), vertical: px(16)),
                                child: Divider(height: px(1), thickness: px(1), color: TvTokens.color.surface.level3),
                              ),
                            SizedBox(
                              key: _key(widget.items[i]),
                              height: px(sizes.itemH),
                              child: Stack(
                                children: [
                                  if (widget.currentIndex == i)
                                    Positioned(
                                      left: 0,
                                      top: px((sizes.itemH - sizes.currentMarker[1]) / 2),
                                      child: SizedBox(
                                        width: px(sizes.currentMarker[0]),
                                        height: px(sizes.currentMarker[1]),
                                        child: ColoredBox(color: TvTokens.color.accent.normal),
                                      ),
                                    ),
                                  Positioned(
                                    left: px(sizes.padLeft),
                                    top: 0,
                                    bottom: 0,
                                    width: px(_expanded ? sizes.expandedW - sizes.padLeft * 2 : sizes.itemW),
                                    child: _item(context, widget.items[i]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
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
    return TvFocusable(
      kind: TvFocusKind.fill,
      focusedScale: 1,
      disabled: item.disabled,
      focusNode: _node(item),
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
