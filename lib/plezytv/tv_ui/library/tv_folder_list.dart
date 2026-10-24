import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../focus/key_event_utils.dart';
import '../../../focus/dpad_navigator.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../widgets/media_context_menu.dart';
import '../components/tv_settings_item.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_library_controller.dart';

class TvFolderList extends StatefulWidget {
  const TvFolderList({
    super.key,
    required this.controller,
    required this.openItem,
    required this.onUp,
    required this.onLeft,
  });
  final TvLibraryController controller;
  final Future<void> Function(MediaItem) openItem;
  final VoidCallback onUp, onLeft;
  @override
  State<TvFolderList> createState() => TvFolderListState();
}

class TvFolderListState extends State<TvFolderList> {
  final _menus = <String, GlobalKey<MediaContextMenuState>>{};
  final _nodes = <int, FocusNode>{};
  void _menu(MediaItem item) {
    final state = _menus[item.globalKey]?.currentState;
    state?.showContextMenu(state.context);
  }

  final _scope = FocusScopeNode();
  final _scroll = ScrollController();
  TvFolderLevel? _level;
  TvLibraryController get c => widget.controller;
  void requestFocus() {
    final level = c.folders.lastOrNull;
    if (level == null || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final index = level.focusedIndex.clamp(0, level.items.isEmpty ? 0 : level.items.length - 1);
    if (_scroll.hasClients) {
      _scroll.jumpTo(
        (index * TvTheme.of(context).px(TvTokens.size.settingsItem.h)).clamp(0, _scroll.position.maxScrollExtent),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes[index]?.requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    final level = c.folders.lastOrNull;
    if (level == null) return const SizedBox.expand();
    if (_level != level) {
      final restore = _level != null;
      _level = level;
      if (restore) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) requestFocus();
        });
      }
    }
    if (_scope.hasFocus && !_nodes.entries.any((e) => e.key == level.focusedIndex && e.value.hasFocus)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) requestFocus();
      });
    }
    final px = TvTheme.of(context).px;
    return FocusScope(
      node: _scope,
      onKeyEvent: (_, event) {
        if (event.logicalKey.isContextMenuKey && level.items.isNotEmpty) {
          if (event is KeyDownEvent) _menu(level.items[level.focusedIndex]);
          return KeyEventResult.handled;
        }
        if (event.logicalKey.isBackKey && (c.folders.length > 1 || level.focusedIndex > 0)) {
          return handleBackKeyAction(event, () {
            if (!c.popFolder()) level.focusedIndex = 0;
            requestFocus();
          });
        }
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp && level.focusedIndex == 0) {
            widget.onUp();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onLeft();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: level.error != null
          ? Center(
              child: TvSettingsItem(
                icon: Icons.refresh,
                title: TvStrings.retry,
                description: TvStrings.noConnection,
                value: '',
                focusNode: _nodes.putIfAbsent(0, () => FocusNode()),
                onSelect: () => unawaited(c.loadFolder(level)),
              ),
            )
          : level.items.isEmpty
          ? Center(
              child: Focus(
                focusNode: _nodes.putIfAbsent(0, () => FocusNode(debugLabel: 'Folder empty')),
                child: Text(
                  level.loading ? TvStrings.connecting : TvStrings.folderEmpty,
                  style: TvTheme.of(context).body,
                ),
              ),
            )
          : ListView.builder(
              controller: _scroll,
              itemExtent: px(TvTokens.size.settingsItem.h),
              itemCount: level.items.length,
              itemBuilder: (context, index) {
                final item = level.items[index];
                return MediaContextMenu(
                  key: _menus.putIfAbsent(item.globalKey, () => GlobalKey<MediaContextMenuState>()),
                  item: item,
                  onRefresh: (_) => unawaited(c.refresh()),
                  child: Focus(
                    canRequestFocus: false,
                    onFocusChange: (focused) {
                      if (focused) level.focusedIndex = index;
                    },
                    child: TvSettingsItem(
                      key: ValueKey(item.globalKey),
                      kind: TvSettingsItemKind.page,
                      onLongPress: () => _menu(item),
                      focusNode: _nodes.putIfAbsent(index, () => FocusNode(debugLabel: 'Folder row $index')),
                      icon: item.kind == MediaKind.folder ? Icons.folder : Icons.movie,
                      title: item.title ?? '',
                      description: '',
                      value: '',
                      onSelect: () async {
                        if (item.kind == MediaKind.folder) {
                          await c.openFolder(item);
                        } else {
                          await widget.openItem(item);
                        }
                        if (mounted) requestFocus();
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  void dispose() {
    _scope.dispose();
    _scroll.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }
}
