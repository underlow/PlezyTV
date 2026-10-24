import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_alpha_column.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';
import '../tv_theme_test_helper.dart';

void main() {
  testWidgets('skips empty letters; freezes external highlight until leaving', (tester) async {
    final key = GlobalKey<TvAlphaColumnState>();
    var highlight = 'A';
    String? selected;
    var left = false;
    late StateSetter update;
    await pumpTvWidget(
      tester,
      StatefulBuilder(
        builder: (context, set) {
          update = set;
          return TvAlphaColumn(
            key: key,
            letters: const [TvAlphaLetter('A'), TvAlphaLetter('B', empty: true), TvAlphaLetter('C')],
            highlighted: highlight,
            onSelect: (s) => selected = s,
            onLeft: () => left = true,
          );
        },
      ),
    );
    key.currentState!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV letter C');
    update(() => highlight = 'C');
    await tester.pump();
    expect(tester.widget<Text>(find.text('A')).style!.color, TvTokens.color.accent.normal);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, 'C');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV letter A');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(left, isTrue);
  });
}
