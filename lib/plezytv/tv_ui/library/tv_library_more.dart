import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../media/media_backend.dart';
import '../../../media/media_library.dart';
import '../../../media/media_server_client.dart';
import '../../../profiles/active_profile_provider.dart';
import '../../../providers/hidden_libraries_provider.dart';
import '../../../providers/libraries_provider.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../services/plex_client.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/media_context_menu.dart' show isAdminActionAllowedForMediaItem;
import '../components/tv_right_panel.dart';
import '../components/tv_settings_item.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';

// Mirrors library_management_sheet.dart's private action definitions and messages.
// The client belongs to this screen's library; never resolve a fallback server.
Future<void> showTvLibraryMore(
  BuildContext context,
  FocusNode anchor,
  MediaLibrary library,
  MediaServerClient client, {
  @visibleForTesting bool? canAdminister,
}) async {
  final servers = context.read<MultiServerProvider?>();
  final profile = context.read<ActiveProfileProvider?>()?.active;
  final allowed =
      canAdminister ??
      isAdminActionAllowedForMediaItem(
        isOwnerOrAdmin:
            library.serverId != null && (servers?.serverManager.isOwnerOrAdmin(ServerId(library.serverId!)) ?? false),
        itemBackend: library.backend,
        activeProfile: profile,
      );
  final actions =
      <
        ({
          String id,
          String title,
          String message,
          String progress,
          String success,
          String Function(Object) failure,
          Future<void> Function() run,
        })
      >[
        if (library.backend == MediaBackend.plex) ...[
          (
            id: 'scan',
            title: t.libraries.scanLibraryFiles,
            message: t.libraries.scanLibraryConfirm(title: library.title),
            progress: t.messages.libraryScanning(title: library.title),
            success: t.messages.libraryScanStarted(title: library.title),
            failure: (e) => t.messages.libraryScanFailed(error: e.toString()),
            run: () => (client as PlexClient).scanLibrary(library.id),
          ),
          (
            id: 'analyze',
            title: t.libraries.analyze,
            message: t.libraries.analyzeLibraryConfirm(title: library.title),
            progress: t.libraries.analyzing(title: library.title),
            success: t.libraries.analysisStarted(title: library.title),
            failure: (e) => t.libraries.failedToAnalyze(error: e),
            run: () => (client as PlexClient).analyzeLibrary(library.id),
          ),
        ],
        (
          id: 'refresh',
          title: t.libraries.refreshMetadata,
          message: t.libraries.refreshMetadataConfirm(title: library.title),
          progress: t.messages.metadataRefreshing(title: library.title),
          success: t.messages.metadataRefreshStarted(title: library.title),
          failure: (e) => t.messages.metadataRefreshFailed(error: e.toString()),
          run: () => client.refreshLibraryMetadata(library.id),
        ),
        if (library.backend == MediaBackend.plex)
          (
            id: 'trash',
            title: t.libraries.emptyTrash,
            message: t.libraries.emptyTrashConfirm(title: library.title),
            progress: t.libraries.emptyingTrash(title: library.title),
            success: t.libraries.trashEmptied(title: library.title),
            failure: (e) => t.libraries.failedToEmptyTrash(error: e),
            run: () => (client as PlexClient).emptyLibraryTrash(library.id),
          ),
      ];
  String? confirmed;
  await TvRightPanel.show(
    context: context,
    anchor: anchor,
    root: TvRightPanelPage(
      title: TvStrings.moreLibraries,
      itemsBuilder: (panelContext) => [
        if (allowed)
          for (final action in actions)
            _item(
              action.id,
              action.title,
              () => TvRightPanel.of(panelContext).push(
                TvRightPanelPage(
                  title: switch (action.id) {
                    'scan' => t.libraries.scanLibrary,
                    'analyze' => t.libraries.analyzeLibrary,
                    _ => action.title,
                  },
                  itemsBuilder: (confirmationContext) => [
                    Text(action.message, style: TvTheme.of(confirmationContext).body),
                    _item('cancel', t.common.cancel, () => TvRightPanel.of(confirmationContext).back()),
                    _item('confirm', t.common.confirm, () {
                      confirmed = action.id;
                      TvRightPanel.of(confirmationContext).close();
                    }),
                  ],
                ),
              ),
            ),
        _item(
          'manage',
          t.libraries.manageLibraries,
          () => TvRightPanel.of(panelContext).push(tvLibraryManagementPage(context)),
          kind: TvSettingsItemKind.page,
        ),
      ],
    ),
  );
  if (confirmed == null || !context.mounted) return;
  final action = actions.firstWhere((a) => a.id == confirmed);
  try {
    showAppSnackBar(context, action.progress, duration: const Duration(seconds: 2));
    await action.run();
    if (context.mounted) showSuccessSnackBar(context, action.success);
  } catch (error) {
    if (context.mounted) showErrorSnackBar(context, action.failure(error));
  }
}

Widget _item(String id, String title, VoidCallback onSelect, {TvSettingsItemKind kind = TvSettingsItemKind.action}) =>
    TvSettingsItem(key: ValueKey(id), title: title, description: '', value: '', kind: kind, onSelect: onSelect);

/// Public root for the all-hidden entry point supplied by T8.
TvRightPanelPage tvLibraryManagementPage(BuildContext context) {
  final libraries = context.read<LibrariesProvider>();
  final hidden = context.read<HiddenLibrariesProvider>();
  Future<void> save(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      if (context.mounted) showErrorSnackBar(context, error.toString());
    }
  }

  void move(String key, int delta) {
    final rows = libraries.libraries.toList();
    final index = rows.indexWhere((l) => l.globalKey == key);
    if (index < 0 || index + delta < 0 || index + delta >= rows.length) return;
    rows.insert(index + delta, rows.removeAt(index));
    save(() => libraries.updateLibraryOrder(rows));
  }

  return TvRightPanelPage(
    title: t.libraries.manageLibraries,
    changes: Listenable.merge([libraries, hidden]),
    itemsBuilder: (_) => [
      Text(TvStrings.libraryReorderHint, style: TvTheme.of(context).caption),
      for (final (index, library) in libraries.libraries.indexed)
        TvSettingsItem(
          key: ValueKey('order:${library.globalKey}'),
          icon: Icons.reorder,
          title: library.title,
          description: hidden.hiddenLibraryKeys.contains(library.globalKey)
              ? t.libraries.showLibrary
              : t.libraries.hideLibrary,
          selected: hidden.hiddenLibraryKeys.contains(library.globalKey),
          value: '${index + 1}',
          kind: TvSettingsItemKind.reorder,
          onMoveUp: index == 0 ? null : () => move(library.globalKey, -1),
          onMoveDown: index == libraries.libraries.length - 1 ? null : () => move(library.globalKey, 1),
          onSelect: () => save(
            () => hidden.hiddenLibraryKeys.contains(library.globalKey)
                ? hidden.unhideLibrary(library.globalKey)
                : hidden.hideLibrary(library.globalKey),
          ),
        ),
    ],
  );
}
