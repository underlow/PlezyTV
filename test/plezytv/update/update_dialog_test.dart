import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plezy/plezytv/update/update_service.dart';
import 'package:plezy/plezytv/update/updater.dart';
import 'package:plezy/plezytv/update/player_guard.dart';
import 'package:plezy/plezytv/screen_links/screen_link.dart';
import 'package:plezy/plezytv/screen_links/screen_link_queue.dart';
import 'package:plezy/utils/video_player_navigation.dart' show VideoPlayerRoute;
import 'package:plezy/widgets/dialog_action_button.dart';
import 'package:plezy/main.dart' show rootNavigatorKey;

class DialogService extends UpdateService {
  DialogService(SharedPreferences prefs)
    : super(
        version: '0.2.0',
        preferences: prefs,
        abi: () async => 'armeabi-v7a',
        cache: Directory.systemTemp,
        log: (_) {},
      );
  @override
  Future<UpdateRelease?> check({required bool automatic}) async =>
      UpdateRelease('0.3.0', Uri.https('github.com', '/apk'), 3);
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
  testWidgets('automatic dialog waits through playback and appears after playback ends', (tester) async {
    BuildContext? owner;
    final updater = PlezyTvUpdater(service: () async => service, enabledForChecks: () => true);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: Builder(
          builder: (context) {
            owner = context;
            return const Scaffold(body: Text('home'));
          },
        ),
      ),
    );
    unawaited(
      VideoPlayerRoute(builder: (_) => const Scaffold(body: Text('Video'))).push(rootNavigatorKey.currentState!),
    );
    await tester.pumpAndSettle();
    final check = updater.check(() => owner, automatic: true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(PlezyTvUpdateDialog), findsNothing);
    rootNavigatorKey.currentState!.pop();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(PlezyTvUpdateDialog), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    await check;
  });

  testWidgets('superseded manual check never displays after playback', (tester) async {
    BuildContext? owner;
    var playing = true;
    final updater = PlezyTvUpdater(
      service: () async => service,
      enabledForChecks: () => true,
      playerActive: () => playing,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            owner = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final actions = <ScreenTarget>[];
    final queue = ScreenLinkQueue(
      isReady: () => true,
      dispatch: (link, isCurrent) async {
        if (link.target == ScreenTarget.update) {
          updater.checkFromLink(() => owner, isCurrent);
        } else {
          actions.add(link.target);
        }
      },
      warn: (_, reason) => fail(reason),
    );
    addTearDown(queue.dispose);
    queue.claim('plezytv://screen/update');
    await tester.pump();
    queue.claim('plezytv://screen/settings');
    await tester.pump();
    expect(actions, [ScreenTarget.settings]);
    playing = false;
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PlezyTvUpdateDialog), findsNothing);
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
