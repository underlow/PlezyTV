import 'dart:async';
import 'screen_link.dart';

/// One process-local pending request. A newer request invalidates async work
/// from an older one, including work belonging to a previous profile.
class ScreenLinkNotReady implements Exception {
  const ScreenLinkNotReady();
}

class ScreenLinkQueue {
  ScreenLinkQueue({required this.isReady, required this.dispatch, required this.warn});
  final bool Function() isReady;
  final Future<void> Function(ScreenLink, bool Function() isCurrent) dispatch;
  final void Function(String link, String reason) warn;
  ScreenLink? _pending;
  Timer? _timer;
  int _generation = 0;
  bool _busy = false;

  bool claim(String source) {
    if (!ScreenLink.claims(source)) return false;
    _generation++;
    _pending = null;
    try {
      _pending = ScreenLink.parse(source);
    } catch (error) {
      warn(source, error is FormatException ? error.message.toString() : '$error');
    }
    if (_pending != null) {
      _timer ??= Timer.periodic(const Duration(milliseconds: 250), (_) => flush());
      unawaited(flush());
    } else {
      _timer?.cancel();
      _timer = null;
    }
    return true;
  }

  Future<void> flush() async {
    if (_busy || _pending == null || !isReady()) return;
    final link = _pending!;
    final generation = _generation;
    _pending = null;
    _busy = true;
    try {
      await dispatch(link, () => generation == _generation);
    } on ScreenLinkNotReady {
      if (generation == _generation) _pending = link;
    } catch (error) {
      if (generation == _generation) warn(link.source, '$error');
    } finally {
      _busy = false;
      if (_pending == null) {
        _timer?.cancel();
        _timer = null;
      }
    }
  }

  void dispose() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}
