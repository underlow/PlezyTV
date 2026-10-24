import 'package:flutter/material.dart';

import '../tv_theme.dart';
import '../tv_tokens.dart';

/// Fixed-height settings rows with focus traversal through unbuilt items.
class TvSettingsList extends StatefulWidget {
  const TvSettingsList({super.key, required this.itemCount, required this.itemBuilder});
  final int itemCount;
  final Widget Function(BuildContext, int, FocusNode, VoidCallback, VoidCallback) itemBuilder;

  @override
  State<TvSettingsList> createState() => _TvSettingsListState();
}

class _TvSettingsListState extends State<TvSettingsList> {
  final _scroll = ScrollController();
  final _nodes = <int, FocusNode>{};
  int _transition = 0;

  void _move(int index) {
    if (index < 0 || index >= widget.itemCount) return;
    final transition = ++_transition;
    final height = TvTheme.of(context).px(TvTokens.size.settingsItem.h);
    final top = index * height;
    final position = _scroll.position;
    final offset = top < position.pixels
        ? top
        : top + height > position.pixels + position.viewportDimension
        ? top + height - position.viewportDimension
        : position.pixels;
    _scroll.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
    void focus(Duration _) {
      if (!mounted || transition != _transition) return;
      final node = _nodes[index];
      if (node?.context != null) {
        node!.requestFocus();
      } else {
        WidgetsBinding.instance.addPostFrameCallback(focus);
        WidgetsBinding.instance.scheduleFrame();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(focus);
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: _scroll,
    itemExtent: TvTheme.of(context).px(TvTokens.size.settingsItem.h),
    itemCount: widget.itemCount,
    itemBuilder: (context, index) => _SettingsSlot(
      key: ValueKey(index),
      register: (node) => _nodes[index] = node,
      unregister: () => _nodes.remove(index),
      builder: (context, node) =>
          widget.itemBuilder(context, index, node, () => _move(index - 1), () => _move(index + 1)),
    ),
  );

  @override
  void dispose() {
    _transition++;
    _scroll.dispose();
    super.dispose();
  }
}

class _SettingsSlot extends StatefulWidget {
  const _SettingsSlot({super.key, required this.register, required this.unregister, required this.builder});
  final ValueChanged<FocusNode> register;
  final VoidCallback unregister;
  final Widget Function(BuildContext, FocusNode) builder;
  @override
  State<_SettingsSlot> createState() => _SettingsSlotState();
}

class _SettingsSlotState extends State<_SettingsSlot> with AutomaticKeepAliveClientMixin {
  final _node = FocusNode();
  @override
  bool get wantKeepAlive => _node.hasFocus;
  @override
  void initState() {
    super.initState();
    widget.register(_node);
    _node.addListener(updateKeepAlive);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.builder(context, _node);
  }

  @override
  void dispose() {
    widget.unregister();
    _node.dispose();
    super.dispose();
  }
}
