import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../navigation/profile_navigation_scope.dart';
import '../../utils/app_logger.dart';
import '../../utils/dialogs.dart';
import '../../main.dart' show rootNavigatorKey;
import 'player_guard.dart';
import '../../widgets/dialog_action_button.dart';
import '../../widgets/setting_tile.dart';
import 'update_service.dart';
import 'update_strings.dart';

class PlezyTvUpdater {
  static const version = String.fromEnvironment('PLEZYTV_VERSION');
  static bool get enabled => Platform.isAndroid && ReleaseVersion.parse(version) != null;
  static final instance = PlezyTvUpdater();
  static const channel = MethodChannel('com.underlow.plezytv/update');
  PlezyTvUpdater({Future<UpdateService> Function()? service, this.enabledForChecks, bool Function()? playerActive})
    : _serviceFactory = service,
      _player = playerActive;
  final Future<UpdateService> Function()? _serviceFactory;
  final bool Function()? enabledForChecks;
  final bool Function()? _player;
  Future<UpdateService>? _service;
  bool _busy = false;
  bool _started = false;
  Future<UpdateService> _getService() => _service ??=
      _serviceFactory?.call() ??
      () async {
        final service = UpdateService(
          version: version,
          preferences: await SharedPreferences.getInstance(),
          abi: () async => (await channel.invokeMethod<String>('abi'))!,
          cache: await getTemporaryDirectory(),
          log: appLogger.w,
        );
        await service.cleanup();
        return service;
      }();

  /// Called only after the screen-link router observes its main-screen readiness.
  void ready(BuildContext? Function() context) {
    if (!enabled || _started) return;
    _started = true;
    unawaited(check(context, automatic: true));
  }

  static bool _playerActive() =>
      hasActiveUpdatePlayer(rootNavigatorKey.currentState) ||
      hasActiveUpdatePlayer(profileNavigationRegistry.navigator);

  /// Release the screen-link queue immediately; newer links cancel pending UI.
  void checkFromLink(BuildContext? Function() context, bool Function() isCurrent) {
    unawaited(check(context, automatic: false, isCurrent: isCurrent));
  }

  Future<void> check(BuildContext? Function() context, {required bool automatic, bool Function()? isCurrent}) async {
    bool current() => isCurrent?.call() ?? true;
    if (!(enabledForChecks?.call() ?? enabled) || !current()) return;
    if (automatic && _busy) return;
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!current()) return;
    _busy = true;
    try {
      final service = await _getService();
      final release = await service.check(automatic: automatic);
      if (release == null && automatic) return;
      // Readiness can disappear during a request (profile switch/sign-out).
      while (current() && ((automatic && context() == null) || (_player?.call() ?? _playerActive()))) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!current()) return;
      final owner = context();
      if (owner == null || !owner.mounted) return;
      if (release == null) {
        await _message(owner, UpdateStrings(owner).latest);
      } else {
        await showScopedDialog<void>(
          context: owner,
          barrierDismissible: false,
          builder: (_) => PlezyTvUpdateDialog(service: service, release: release, automatic: automatic),
        );
      }
    } catch (error) {
      if (automatic) {
        appLogger.w('PlezyTV update failed: $error');
      } else {
        final owner = context();
        if (current() && owner != null && owner.mounted) {
          await _message(owner, '${UpdateStrings(owner).failed}: $error');
        }
      }
    } finally {
      _busy = false;
    }
  }

  static Future<void> _message(BuildContext context, String message) => showScopedDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [DialogActionButton(label: 'OK', autofocus: true, onPressed: () => Navigator.pop(context))],
    ),
  );

  static Widget settingsTile(BuildContext context) => SettingNavigationTile(
    icon: Icons.system_update,
    title: UpdateStrings(context).check,
    subtitle: 'PlezyTV $version',
    onTap: () => instance.check(() => context.mounted ? context : null, automatic: false),
  );
}

class PlezyTvUpdateDialog extends StatefulWidget {
  const PlezyTvUpdateDialog({super.key, required this.service, required this.release, required this.automatic});
  final UpdateService service;
  final UpdateRelease release;
  final bool automatic;
  @override
  State<PlezyTvUpdateDialog> createState() => PlezyTvUpdateDialogState();
}

class PlezyTvUpdateDialogState extends State<PlezyTvUpdateDialog> with WidgetsBindingObserver {
  final _installFocus = FocusNode();
  bool _downloading = false;
  double? _progress;
  String? _message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_downloading) _installFocus.requestFocus();
  }

  @override
  void dispose() {
    widget.service.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _installFocus.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    setState(() {
      _downloading = true;
      _message = null;
    });
    try {
      final file = await widget.service.download(widget.release, (progress) {
        if (mounted) setState(() => _progress = progress);
      });
      if (!mounted) return;
      setState(() => _progress = 1);
      if (await PlezyTvUpdater.channel.invokeMethod<bool>('canInstall') != true) {
        if (!mounted) return;
        setState(() => _message = UpdateStrings(context).permission);
        // Explain before leaving the app; keep this update dialog and APK alive.
        await PlezyTvUpdater._message(context, UpdateStrings(context).permission);
        if (!mounted) return;
        await PlezyTvUpdater.channel.invokeMethod<void>('openPermission');
      } else {
        await PlezyTvUpdater.channel.invokeMethod<void>('install', file.path);
      }
    } catch (error) {
      if (mounted) setState(() => _message = '${UpdateStrings(context).failed}: $error');
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
        _installFocus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = UpdateStrings(context);
    return PopScope(
      canPop: !_downloading,
      child: AlertDialog(
        title: Text('PlezyTV ${widget.release.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${strings.current}: ${widget.service.version}'),
            if (_message != null) Text(_message!),
            if (_downloading) ...[
              LinearProgressIndicator(value: _progress),
              Text(_progress == null ? '…' : '${(_progress! * 100).round()}%'),
            ],
          ],
        ),
        actions: _downloading
            ? [DialogActionButton(label: strings.cancel, autofocus: true, onPressed: widget.service.cancel)]
            : [
                DialogActionButton(
                  label: strings.install,
                  focusNode: _installFocus,
                  autofocus: true,
                  isPrimary: true,
                  onPressed: _install,
                ),
                DialogActionButton(label: strings.later, onPressed: () => Navigator.pop(context)),
                if (widget.automatic)
                  DialogActionButton(
                    label: strings.skip,
                    onPressed: () async {
                      try {
                        await widget.service.skip(widget.release);
                        if (context.mounted) Navigator.pop(context);
                      } catch (error) {
                        if (mounted) setState(() => _message = '${strings.failed}: $error');
                      }
                    },
                  ),
              ],
      ),
    );
  }
}
