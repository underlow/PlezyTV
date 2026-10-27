import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/home/tv_home_ready.dart';

void main() {
  testWidgets('readiness waits for every visible first poster to paint', (tester) async {
    final first = GlobalKey(), second = GlobalKey();
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff112233), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    Future<void> draw(bool loaded) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            SizedBox(
              key: first,
              width: 100,
              height: 100,
              child: RawImage(image: image),
            ),
            SizedBox(
              key: second,
              width: 100,
              height: 100,
              child: RawImage(image: loaded ? image : null),
            ),
          ],
        ),
      ),
    );
    const viewport = Rect.fromLTWH(0, 0, 800, 600);
    await draw(false);
    expect(tvHomeReadyRows(viewport, [first.currentContext, second.currentContext]), isNull);
    await draw(true);
    expect(tvHomeReadyRows(viewport, [first.currentContext, second.currentContext]), 2);
    expect(tvHomeReadyRows(const Rect.fromLTWH(0, 0, 800, 99), [first.currentContext, second.currentContext]), 1);
    await tester.pumpWidget(const SizedBox());
    image.dispose();
    picture.dispose();
  });
}
