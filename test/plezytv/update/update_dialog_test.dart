import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plezy/plezytv/update/update_service.dart';
import 'package:plezy/plezytv/update/updater.dart';
import 'package:plezy/plezytv/update/player_guard.dart';
import 'package:plezy/utils/video_player_navigation.dart' show VideoPlayerRoute;
import 'package:plezy/widgets/dialog_action_button.dart';

class DialogService extends UpdateService {
  DialogService(SharedPreferences prefs)
    : super(
        version: '0.2.0',
        preferences: prefs,
        abi: () async => 'armeabi-v7a',
        cache: Directory.systemTemp,
        log: (_) {},
      );
  Completer<File>? pending;
  bool holdDownload = false;
  bool cancelled = false;
  @override
  Future<File> download(UpdateRelease release, void Function(double?) progress) async {
    if (!holdDownload) return File('/cache/plezytv-update-0.3.0.apk');
    pending = Completer<File>();
    progress(0.5);
    return pending!.future;
  }

  @override
  void cancel() {
    cancelled = true;
    if (pending?.isCompleted == false) pending!.completeError(const HttpException('Download cancelled'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DialogService service;
  final release = UpdateRelease('0.3.0', Uri.https('github.com', '/apk'), 3);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = DialogService(await SharedPreferences.getInstance());
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      PlezyTvUpdater.channel,
      null,
    );
  });
  Future<void> show(WidgetTester tester, {bool automatic = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlezyTvUpdateDialog(service: service, release: release, automatic: automatic),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('A8 R14 automatic dialog shows versions, Install focused, remote moves to Later', (tester) async {
    await show(tester);
    expect(find.text('PlezyTV 0.3.0'), findsOneWidget);
    expect(find.text('Current version: 0.2.0'), findsOneWidget);
    expect(find.text('Skip this version'), findsOneWidget);
    final install = tester.widget<DialogActionButton>(find.widgetWithText(DialogActionButton, 'Install'));
    expect(install.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(install.focusNode!.hasFocus, isFalse);
  });
  testWidgets('manual dialog has Install/Later only', (tester) async {
    await show(tester, automatic: false);
    expect(find.text('Install'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Skip this version'), findsNothing);
  });
  testWidgets('A9 permission explanation, package settings, return and installer retry', (tester) async {
    var allowed = false;
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(PlezyTvUpdater.channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'canInstall') return allowed;
      return null;
    });
    await show(tester);
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allow installing apps'), findsWidgets);
    expect(calls.map((call) => call.method), ['canInstall']);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method), ['canInstall', 'openPermission']);
    allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final install = tester.widget<DialogActionButton>(find.widgetWithText(DialogActionButton, 'Install'));
    expect(install.focusNode!.hasFocus, isTrue);
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'install');
    expect(calls.last.arguments, endsWith('.apk'));
    expect(find.byType(PlezyTvUpdateDialog), findsOneWidget);
  });
  testWidgets('player guard includes covered active route and clears after playback ends', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    expect(hasActiveUpdatePlayer(navigator.currentState), isFalse);
    unawaited(VideoPlayerRoute(builder: (_) => const Scaffold(body: Text('Video'))).push(navigator.currentState!));
    await tester.pumpAndSettle();
    expect(hasActiveUpdatePlayer(navigator.currentState), isTrue);
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Cover'))));
    await tester.pumpAndSettle();
    expect(hasActiveUpdatePlayer(navigator.currentState), isTrue);
    navigator.currentState!.popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    expect(hasActiveUpdatePlayer(navigator.currentState), isFalse);
  });
  testWidgets('A21 progress and cancel keep dialog usable', (tester) async {
    service.holdDownload = true;
    await show(tester);
    await tester.tap(find.text('Install'));
    await tester.pump();
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.cancelled, isTrue);
    expect(find.text('Install'), findsOneWidget);
  });
}
