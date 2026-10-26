import 'package:flutter/material.dart';

import '../../services/settings_export_service.dart';
import '../../utils/dialogs.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_section.dart';
import '../settings_transfer/settings_transfer_service.dart';
import 'tv_strings.dart';

class TvSettingsBackup extends StatefulWidget {
  const TvSettingsBackup({super.key});

  @override
  State<TvSettingsBackup> createState() => _TvSettingsBackupState();
}

class _TvSettingsBackupState extends State<TvSettingsBackup> {
  bool _busy = false;

  Future<void> _run({required bool importing}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (importing) {
        final confirmed = await showConfirmDialog(
          context,
          title: TvStrings.transferImport,
          message: TvStrings.transferConfirm,
          confirmText: TvStrings.transferImport,
        );
        if (!mounted || !confirmed) return;
        final result = await const SettingsTransferService().importAndApply(context);
        if (mounted) showSuccessSnackBar(context, TvStrings.transferImported(result.keysImported));
      } else {
        final path = await const SettingsTransferService().exportToFile();
        if (mounted) showSuccessSnackBar(context, TvStrings.transferExported(path));
      }
    } on NoUserSignedInException {
      if (mounted) showErrorSnackBar(context, TvStrings.transferNoUser);
    } on InvalidExportFileException {
      if (mounted) showErrorSnackBar(context, TvStrings.transferInvalidFile);
    } on SettingsExportException catch (error) {
      if (mounted) showErrorSnackBar(context, error.message);
    } catch (_) {
      if (mounted) showErrorSnackBar(context, TvStrings.transferFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsGroup(
    title: TvStrings.transferBackup,
    children: [
      SettingNavigationTile(icon: Icons.upload, title: TvStrings.transferExport, onTap: () => _run(importing: false)),
      SettingNavigationTile(icon: Icons.download, title: TvStrings.transferImport, onTap: () => _run(importing: true)),
    ],
  );
}
