import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../media/media_library.dart';
import '../../../mixins/refreshable.dart';
import '../../../mixins/tab_visibility_aware.dart';
import '../../../providers/hidden_libraries_provider.dart';
import '../../../providers/libraries_provider.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../screens/libraries/libraries_screen.dart';
import '../../../services/storage_service.dart';
import '../components/tv_button.dart';
import '../components/tv_right_panel.dart';
import '../tv_theme.dart';
import 'tv_library_controller.dart';
import 'tv_library_preferences.dart';
import 'tv_library_query.dart';
import 'tv_library_screen.dart';
import 'tv_library_more.dart';

/// Stable shell section; the active child and its controller live for one selection.
class TvLibrariesSwitch extends StatefulWidget {
  const TvLibrariesSwitch({super.key, required this.onLibrarySelected});
  final ValueChanged<String> onLibrarySelected;
  @override
  State<TvLibrariesSwitch> createState() => TvLibrariesSwitchState();
}

class TvLibrariesSwitchState extends State<TvLibrariesSwitch>
    with LibraryLoadable, Refreshable, ManualRefreshable, FullRefreshable, TabVisibilityAware, FocusableTab {
  GlobalKey _child = GlobalKey();
  final _manage = FocusNode(debugLabel: 'Manage hidden libraries');
  StorageService? _storage;
  MediaLibrary? _library;
  TvLibraryController? _controller;
  String? _requested;
  bool _ready = false, _visible = true, _scheduled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final storage = await StorageService.getInstance();
    if (!mounted) return;
    await context.read<HiddenLibrariesProvider>().ensureInitialized();
    if (!mounted) return;
    setState(() {
      _storage = storage;
      _ready = true;
    });
    _resolve();
  }

  void _forward<T>(void Function(T) call) {
    final child = _child.currentState;
    if (child is T) call(child as T);
  }

  void selectDefault() => loadLibraryByKey('');

  @override
  void loadLibraryByKey(String libraryGlobalKey) {
    _requested = libraryGlobalKey;
    _resolve();
  }

  void _resolve() {
    if (!mounted || !_ready) return;
    final libraries = context.read<LibrariesProvider>();
    // Do not consume an explicit selection before the provider's first load.
    // ignore: invalid_use_of_visible_for_testing_member
    if (libraries.isLoading || libraries.loadState == LibrariesLoadState.initial) return;
    final all = libraries.libraries;
    final hidden = context.read<HiddenLibrariesProvider>().hiddenLibraryKeys;
    final visible = all.where((l) => !hidden.contains(l.globalKey));
    MediaLibrary? byKey(String? key) => all.where((l) => l.globalKey == key).firstOrNull;
    final saved = visible.where((l) => l.globalKey == _storage!.getSelectedLibraryKey()).firstOrNull;
    final requested = _requested != null;
    final selected =
        byKey(_requested) ?? (_requested == null ? byKey(_library?.globalKey) : null) ?? saved ?? visible.firstOrNull;
    _requested = null;
    final client = selected?.serverId == null
        ? null
        : context.read<MultiServerProvider>().getClientForServer(ServerId(selected!.serverId!));
    if (selected?.globalKey == _library?.globalKey &&
        (selected == null || isTvVideoLibrary(selected) == isTvVideoLibrary(_library!)) &&
        identical(_controller?.client, selected != null && isTvVideoLibrary(selected) ? client : null)) {
      if (requested && selected != null) widget.onLibrarySelected(selected.globalKey);
      return;
    }
    final old = _controller;
    setState(() {
      _library = selected;
      _child = GlobalKey(
        debugLabel: '${selected != null && isTvVideoLibrary(selected) ? 'video' : 'plezy'}:${selected?.globalKey}',
      );
      _controller = selected != null && isTvVideoLibrary(selected) && client != null
          ? TvLibraryController(
              library: selected,
              client: client,
              store: TvStorageLibraryPreferences(_storage!),
              librariesProvider: libraries,
            )
          : null;
    });
    // The old screen removes its listener during this frame's unmount.
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    if (selected != null) {
      unawaited(_storage!.saveSelectedLibraryKey(selected.globalKey));
      widget.onLibrarySelected(selected.globalKey);
      final childKey = _child;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || childKey != _child) return;
        if (!isTvVideoLibrary(selected)) _forward<LibraryLoadable>((s) => s.loadLibraryByKey(selected.globalKey));
        _forward<TabVisibilityAware>((s) => _visible ? s.onTabShown() : s.onTabHidden());
      });
    }
  }

  @override
  void refresh() {
    _resolve();
    _forward<Refreshable>((s) => s.refresh());
  }

  @override
  void manualRefresh() => _forward<ManualRefreshable>((s) => s.manualRefresh());
  @override
  void fullRefresh() {
    _resolve();
    _forward<FullRefreshable>((s) => s.fullRefresh());
  }

  @override
  void primeRefresh() {
    _resolve();
    _forward<FullRefreshable>((s) => s.primeRefresh());
  }

  @override
  void onTabShown() {
    _visible = true;
    _forward<TabVisibilityAware>((s) => s.onTabShown());
  }

  @override
  void onTabHidden() {
    _visible = false;
    _forward<TabVisibilityAware>((s) => s.onTabHidden());
  }

  @override
  void focusActiveTabIfReady() {
    if (_library == null) {
      _manage.requestFocus();
    } else {
      _forward<FocusableTab>((s) => s.focusActiveTabIfReady());
    }
  }

  Future<void> _manageLibraries() async {
    await TvRightPanel.show(context: context, anchor: _manage, root: tvLibraryManagementPage(context));
    // Unhiding may have replaced the empty state's invoking button.
    if (mounted && _library != null) focusActiveTabIfReady();
  }

  @override
  Widget build(BuildContext context) {
    final libraries = context.watch<LibrariesProvider>();
    context.watch<HiddenLibrariesProvider>();
    context.watch<MultiServerProvider>();
    if (!_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted) _resolve();
      });
    }
    // ignore: invalid_use_of_visible_for_testing_member
    final initializing = libraries.loadState == LibrariesLoadState.initial;
    if (!_ready || libraries.isLoading || initializing) return const SizedBox.expand();
    if (_library == null) {
      final allHidden = libraries.libraries.isNotEmpty;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              allHidden ? t.libraries.allLibrariesHidden : t.libraries.noLibrariesFound,
              style: TvTheme.of(context).headline,
            ),
            if (allHidden)
              TvButton(
                focusNode: _manage,
                autofocus: true,
                label: t.libraries.manageLibraries,
                onSelect: () => unawaited(_manageLibraries()),
              ),
          ],
        ),
      );
    }
    if (_controller case final controller?) return TvLibraryScreen(key: _child, controller: controller);
    if (isTvVideoLibrary(_library!)) return const SizedBox.expand();
    return LibrariesScreen(key: _child, onLibrarySelected: loadLibraryByKey);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _manage.dispose();
    super.dispose();
  }
}
