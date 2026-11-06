import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_server_client.dart';
import '../../../models/download_models.dart';
import '../../../providers/download_provider.dart';
import '../../../screens/downloads/downloads_screen.dart';
import '../../../utils/dialogs.dart';
import '../../../utils/download_utils.dart';
import '../../../utils/error_message_utils.dart';
import '../../../utils/snackbar_helper.dart';
import '../components/tv_button.dart';

/// Download or manage the supplied show or episode using Plezy's download flow.
class TvDownloadAction extends StatefulWidget {
  const TvDownloadAction({super.key, required this.item, required this.client, this.disabled = false});
  final MediaItem item;
  final MediaServerClient client;
  final bool disabled;
  @override
  State<TvDownloadAction> createState() => _TvDownloadActionState();
}

class _TvDownloadActionState extends State<TvDownloadAction> {
  bool _busy = false;
  Future<void> _download(DownloadProvider provider, bool manage, bool downloaded) async {
    if (manage) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()));
      return;
    }
    await queueDownloadWithFeedback(
      context,
      metadata: widget.item,
      client: widget.client,
      downloadProvider: provider,
      onDelete: !downloaded
          ? null
          : () async {
              final confirmed = await showDeleteConfirmation(
                context,
                title: t.downloads.deleteDownload,
                message: t.downloads.deleteConfirm(title: widget.item.displayTitle),
              );
              if (confirmed && mounted) {
                await provider.deleteDownload(widget.item.globalKey);
                if (mounted) showSuccessSnackBar(context, t.downloads.downloadDeleted);
              }
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadProvider?>();
    var progress = downloads?.getProgress(widget.item.globalKey);
    // Plezy's show aggregate omits all-paused/all-cancelled leaves. Keep
    // those owned downloads manageable rather than offering a fresh queue.
    if (widget.item.kind == MediaKind.show && progress == null && downloads != null) {
      for (final entry in downloads.downloads.entries) {
        final item = downloads.getMetadata(entry.key);
        if (item?.serverId == widget.item.serverId && item?.grandparentId == widget.item.id) {
          progress = entry.value;
          break;
        }
      }
    }
    final downloaded = downloads?.isDownloaded(widget.item.globalKey) ?? false;
    final rule =
        downloads?.hasSyncRule(
          downloads.syncRuleKeyForClient(
            widget.client,
            widget.item.id,
            serverId: widget.item.serverId == null ? null : ServerId(widget.item.serverId!),
          ),
        ) ??
        false;
    final queueing = downloads?.isQueueing(widget.item.globalKey) ?? false;
    final manage = rule || (progress != null && progress.status != DownloadStatus.completed) || queueing;
    final icon = rule
        ? Icons.sync
        : queueing
        ? Icons.hourglass_top
        : switch (progress?.status) {
            DownloadStatus.queued => Icons.schedule,
            DownloadStatus.downloading => Icons.downloading,
            DownloadStatus.paused => Icons.pause_circle_outline,
            DownloadStatus.failed => Icons.error_outline,
            DownloadStatus.cancelled => Icons.cancel_outlined,
            DownloadStatus.partial => Icons.download_for_offline_outlined,
            DownloadStatus.completed => Icons.download_done,
            null => downloaded ? Icons.download_done : Icons.download,
          };

    return TvIconButton(
      icon: icon,
      caption: manage ? t.navigation.downloads : t.downloads.downloadNow,
      disabled: widget.disabled || _busy || downloads == null,
      onSelect: () async {
        if (_busy || downloads == null) return;
        setState(() => _busy = true);
        try {
          await _download(downloads, manage, downloaded);
        } catch (error) {
          if (context.mounted) showErrorSnackBar(context, t.messages.errorLoading(error: localizedErrorReason(error)));
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      },
    );
  }
}
