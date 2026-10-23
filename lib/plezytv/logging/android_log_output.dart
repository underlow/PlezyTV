import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

/// Tests and other platforms retain the logger package's console output.
LogOutput plezyTvLogOutput() {
  if (kIsWeb || !Platform.isAndroid || Platform.environment.containsKey('FLUTTER_TEST')) {
    return ConsoleOutput();
  }
  final android = AndroidLogOutput();
  return kDebugMode ? MultiOutput([android, ConsoleOutput()]) : android;
}

/// Sends bounded batches asynchronously, with at most one call in flight.
/// Input is already redacted by MemoryAwareLogPrinter.
class AndroidLogOutput extends LogOutput {
  AndroidLogOutput({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('com.underlow.plezytv/logs');

  static const maxChunkBytes = 3900;
  static const maxBatchLines = 64;
  final MethodChannel _channel;
  final Queue<Map<String, Object>> _pending = Queue();
  Future<void>? _flushing;

  @override
  void output(OutputEvent event) {
    final priority = event.level.value >= Level.error.value
        ? 6
        : event.level.value >= Level.warning.value
        ? 5
        : event.level.value >= Level.info.value
        ? 4
        : 3;
    for (final line in event.lines) {
      for (final chunk in _chunks(line)) {
        _pending.add({'priority': priority, 'message': chunk});
      }
    }
    _flushing ??= Future<void>.microtask(_flush);
  }

  Future<void> _flush() async {
    try {
      while (_pending.isNotEmpty) {
        final batch = <Map<String, Object>>[];
        while (_pending.isNotEmpty && batch.length < maxBatchLines) {
          batch.add(_pending.removeFirst());
        }
        try {
          await _channel.invokeMethod<void>('write', batch);
        } on PlatformException {
          // Logging must never break the app or recursively log a failure.
        } on MissingPluginException {
          // Engine shutdown or a channel not yet available.
        }
      }
    } finally {
      _flushing = null;
    }
  }

  // Logcat limits bytes, not UTF-16 characters. Keep Unicode scalars intact.
  static Iterable<String> _chunks(String line) sync* {
    var buffer = StringBuffer();
    var bytes = 0;
    for (final rune in line.runes) {
      final size = rune <= 0x7f
          ? 1
          : rune <= 0x7ff
          ? 2
          : rune <= 0xffff
          ? 3
          : 4;
      if (bytes + size > maxChunkBytes) {
        yield buffer.toString();
        buffer = StringBuffer();
        bytes = 0;
      }
      buffer.writeCharCode(rune);
      bytes += size;
    }
    if (bytes > 0 || line.isEmpty) yield buffer.toString();
  }

  @override
  Future<void> destroy() async {
    await _flushing;
  }
}
