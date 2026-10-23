import 'package:flutter/material.dart';

import '../../../services/device_performance.dart';
import '../tv_focusable.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

@immutable
class TvSideMenuItem {
  const TvSideMenuItem({required this.icon, required this.label, this.onSelect, this.focusNode, this.disabled = false});
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
    required this.currentIndex,
    required this.child,
    this.dividerBeforeIndex,
  }) : assert(currentIndex >= 0 && currentIndex < items.length),
       assert(dividerBeforeIndex == null || (dividerBeforeIndex >= 0 && dividerBeforeIndex < items.length));
  final List<TvSideMenuItem> items;
  final int currentIndex;
  final int? dividerBeforeIndex;
  final Widget child;

  @override
  State<TvSideMenu> createState() => _TvSideMenuState();
}

class _TvSideMenuState extends State<TvSideMenu> {
  bool _expanded = false;

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
            canRequestFocus: false,
            onFocusChange: (value) => setState(() => _expanded = value),
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
      focusNode: item.focusNode,
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
