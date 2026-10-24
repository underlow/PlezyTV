import 'dart:async';
import 'package:flutter/material.dart';
import '../tv_focusable.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

@immutable
class TvTab {
  const TvTab({required this.label, this.disabled = false});
  final String label;
  final bool disabled;
}

/// Controlled selection. Place at contentLeft; the block offsets itself by -24.
class TvTabs extends StatefulWidget {
  const TvTabs({super.key, required this.tabs, required this.selectedIndex, required this.onSelected});
  final List<TvTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  @override
  State<TvTabs> createState() => TvTabsState();
}

class TvTabsState extends State<TvTabs> {
  int? get focusedIndex => _focusedIndex;

  /// Explicit entry from a screen's grid/header, retaining controlled selection.
  void requestFocus() {
    final index = widget.selectedIndex;
    if (index >= 0 && index < _nodes.length && !widget.tabs[index].disabled) {
      _nodes[index].requestFocus();
    }
  }

  final _scope = FocusScopeNode(debugLabel: 'TV tabs');
  final List<FocusNode> _nodes = [];
  Timer? _timer;
  int? _focusedIndex;

  @override
  void initState() {
    super.initState();
    _syncNodes();
  }

  void _syncNodes() {
    while (_nodes.length < widget.tabs.length) {
      _nodes.add(FocusNode());
    }
    while (_nodes.length > widget.tabs.length) {
      _nodes.removeLast().dispose();
    }
  }

  @override
  void didUpdateWidget(TvTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncNodes();
    if (_focusedIndex != null && (_focusedIndex! >= widget.tabs.length || widget.tabs[_focusedIndex!].disabled)) {
      _timer?.cancel();
      _focusedIndex = null;
    }
  }

  void _select(int index) {
    _timer?.cancel();
    if (!widget.tabs[index].disabled) widget.onSelected(index);
  }

  void _focus(int index, bool focused) {
    if (!focused) {
      if (_focusedIndex == index) {
        _timer?.cancel();
        _focusedIndex = null;
      }
      return;
    }
    _focusedIndex = index;
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: TvTokens.motion.heroDebounce), () {
      if (mounted && _nodes[index].hasFocus) _select(index);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final node in _nodes) {
      node.dispose();
    }
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    return Transform.translate(
      offset: Offset(-px(TvTokens.size.tab.padX), 0),
      child: FocusScope(
        node: _scope,
        onFocusChange: (inside) {
          if (!inside) return;
          final selected = widget.selectedIndex;
          if (selected >= 0 && selected < _nodes.length && !widget.tabs[selected].disabled) {
            _nodes[selected].requestFocus();
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < widget.tabs.length; index++)
              TvFocusable(
                kind: TvFocusKind.fill,
                focusedScale: TvTokens.focus.buttonScale,
                focusNode: _nodes[index],
                disabled: widget.tabs[index].disabled,
                semanticLabel: widget.tabs[index].label,
                checked: index == widget.selectedIndex,
                onFocusChange: (focused) => _focus(index, focused),
                onSelect: () => _select(index),
                builder: (context, state) => Container(
                  height: px(TvTokens.size.tab.h),
                  padding: EdgeInsets.symmetric(horizontal: px(TvTokens.size.tab.padX)),
                  decoration: BoxDecoration(
                    color: state.pressed
                        ? TvTokens.color.text.secondary
                        : state.focused
                        ? TvTokens.color.focus.fill
                        : null,
                    borderRadius: BorderRadius.circular(px(TvTokens.radius.button)),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        widget.tabs[index].label,
                        style: theme.label.copyWith(
                          color: state.focused
                              ? TvTokens.color.text.onFocus
                              : index == widget.selectedIndex
                              ? TvTokens.color.text.primary
                              : TvTokens.color.text.secondary,
                        ),
                      ),
                      if (index == widget.selectedIndex)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: px(TvTokens.size.tab.underline),
                            color: TvTokens.color.accent.normal,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
