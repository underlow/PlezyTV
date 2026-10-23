import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/plezytv/tv_ui/tv_theme.dart';
import 'package:plezy/services/device_performance.dart';

Future<void> pumpTvWidget(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1920, 1080),
  bool reduced = false,
  ThemeData? appTheme,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final highlightStrategy = FocusManager.instance.highlightStrategy;
  DevicePerformance.debugReset();
  DevicePerformance.debugReset(autoReduced: reduced);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    DevicePerformance.debugReset();
    FocusManager.instance.highlightStrategy = highlightStrategy;
  });
  Widget host(Widget content) => InputModeTracker(
    child: MaterialApp(
      theme: appTheme,
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: textScaler),
        child: TvTheme(child: content),
      ),
    ),
  );
  // Establish keyboard mode before mounting the component under test.
  await tester.pumpWidget(host(const SizedBox.shrink()));
  InputModeTracker.reportNonPointerInput();
  await tester.pump();
  await tester.pumpWidget(host(child));
}
