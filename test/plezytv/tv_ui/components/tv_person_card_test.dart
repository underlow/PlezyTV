import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_person_card.dart';
import 'package:plezy/widgets/optimized_media_image.dart';

import '../tv_theme_test_helper.dart';

void main() {
  Future<FocusNode> pumpCard(WidgetTester tester, {String? caption, VoidCallback? onSelect}) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await pumpTvWidget(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: TvPersonCard(
          client: null,
          imagePath: null,
          name: 'Jane Doe',
          caption: caption,
          focusNode: node,
          onSelect: onSelect,
        ),
      ),
    );
    await tester.pump();
    return node;
  }

  testWidgets('photo is a 200x200 circle and the name sits 20px below it, as in the S7/S8 cast rows', (tester) async {
    await pumpCard(tester, caption: 'Hero');
    // Previous S7/S8 cast rows: OptimizedMediaImage width/height px(200), SizedBox(height: px(20)).
    final photo = find.byType(OptimizedMediaImage);
    expect(tester.getSize(photo), const Size(200, 200));
    expect(find.ancestor(of: photo, matching: find.byType(ClipOval)), findsOneWidget);
    final photoRect = tester.getRect(photo);
    final nameRect = tester.getRect(find.text('Jane Doe'));
    expect(nameRect.top, photoRect.bottom + 20);
    expect(nameRect.left, photoRect.left);
    final captionRect = tester.getRect(find.text('Hero'));
    expect(captionRect.top, nameRect.bottom);
    expect(captionRect.left, photoRect.left);
  });

  testWidgets('caption is hidden when null', (tester) async {
    await pumpCard(tester);
    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('OK fires onSelect', (tester) async {
    var selected = 0;
    final node = await pumpCard(tester, caption: 'Hero', onSelect: () => selected++);
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selected, 1);
  });
}
