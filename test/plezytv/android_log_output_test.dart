import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart' hide ProductionFilter;
import 'package:plezy/plezytv/logging/android_log_output.dart';
import 'package:plezy/utils/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/plezytv/logs');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<List<dynamic>> batches;
  late AndroidLogOutput output;

  setUp(() {
    batches = [];
    output = AndroidLogOutput(channel: channel);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'write');
      batches.add(call.arguments as List<dynamic>);
      return null;
    });
  });

  tearDown(() async {
    await output.destroy();
    messenger.setMockMethodCallHandler(channel, null);
    MemoryLogOutput.clearLogs();
  });

  void emit(Level level, List<String> lines) => output.output(OutputEvent(LogEvent(level, 'event'), lines));

  test('coalesces events and preserves line order and Android priorities', () async {
    emit(Level.debug, ['debug', 'second']);
    emit(Level.info, ['info']);
    emit(Level.warning, ['warning']);
    emit(Level.error, ['error']);
    emit(Level.fatal, ['fatal']);
    emit(Level.trace, ['trace']);
    expect(batches, isEmpty);
    await output.destroy();
    expect(batches, hasLength(1));
    expect(batches.single.map((line) => line['message']), [
      'debug',
      'second',
      'info',
      'warning',
      'error',
      'fatal',
      'trace',
    ]);
    expect(batches.single.map((line) => line['priority']), [3, 3, 4, 5, 6, 6, 3]);
  });

  test('bounds batches and serializes calls including logs added in flight', () async {
    final gate = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      batches.add(call.arguments as List<dynamic>);
      if (batches.length == 1) await gate.future;
      return null;
    });
    emit(Level.info, List.generate(130, (index) => '$index'));
    await Future<void>.delayed(Duration.zero);
    emit(Level.warning, ['last']);
    await Future<void>.delayed(Duration.zero);
    expect(batches, hasLength(1));
    gate.complete();
    await output.destroy();
    expect(batches.map((batch) => batch.length), [64, 64, 3]);
    expect(batches.expand((batch) => batch).map((line) => line['message']), [
      ...List.generate(130, (index) => '$index'),
      'last',
    ]);
  });

  test('chunks ASCII and Unicode losslessly below logcat byte limit', () async {
    for (final text in ['a' * 10000, '😀Ж界' * 2000, '']) {
      emit(Level.error, [text]);
      await output.destroy();
      final chunks = batches.expand((batch) => batch).map((line) => line['message'] as String).toList();
      expect(chunks.join(), text);
      for (final chunk in chunks) {
        expect(utf8.encode(chunk).length, lessThanOrEqualTo(AndroidLogOutput.maxChunkBytes));
        expect(chunk, isNot(contains('\uFFFD')));
      }
      batches.clear();
    }
  });

  test('channel failure does not escape and subsequent logs still work', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'unavailable'));
    emit(Level.info, ['dropped']);
    await output.destroy();
    messenger.setMockMethodCallHandler(channel, (call) async {
      batches.add(call.arguments as List<dynamic>);
      return null;
    });
    emit(Level.info, ['next']);
    await output.destroy();
    expect(batches.single.single['message'], 'next');
  });

  test('printer redaction, memory storage and filtering precede native output', () async {
    final filter = ProductionFilter()..setLevel(Level.info);
    final logger = Logger(filter: filter, printer: MemoryAwareLogPrinter(SimplePrinter()), output: output);
    logger.d('hidden');
    logger.w('Authorization: Bearer secret-token');
    await output.destroy();
    expect(batches.single, hasLength(1));
    expect(batches.single.single['priority'], 5);
    expect(batches.single.single['message'], isNot(contains('secret-token')));
    expect(MemoryLogOutput.getLogs(), hasLength(1));
    expect(MemoryLogOutput.getLogs().single.message, isNot(contains('secret-token')));
  });

  test('test environment keeps console output', () {
    expect(plezyTvLogOutput(), isA<ConsoleOutput>());
  });
}
