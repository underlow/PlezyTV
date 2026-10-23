import 'dart:async';

/// A process-start watcher: disabled builds allocate no timer; a ready main
/// screen consumes the trigger even when cooldown suppresses its request.
class UpdateStartupTrigger {
  UpdateStartupTrigger({
    required bool enabled,
    required bool Function() isReady,
    required void Function() fire,
    Duration interval = const Duration(seconds: 1),
  }) {
    if (!enabled) return;
    _timer = Timer.periodic(interval, (_) {
      if (!isReady()) return;
      dispose();
      fire();
    });
  }
  Timer? _timer;
  bool get watching => _timer?.isActive ?? false;
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
