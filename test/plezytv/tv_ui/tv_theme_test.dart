import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/plezytv/tv_ui/tv_strings.dart';
import 'package:plezy/plezytv/tv_ui/tv_theme.dart';
import 'package:plezy/services/device_performance.dart';
import 'package:plezy/theme/mono_tokens.dart';
import 'package:plezy/utils/formatters.dart';

import '../../test_helpers/theme.dart';
import 'tv_theme_test_helper.dart';

void main() {
  for (final size in [const Size(960, 540), const Size(1280, 1080), const Size(1920, 1080)]) {
    testWidgets('A2 scale at $size ignores system text scale', (tester) async {
      final expected = size.width == 960
          ? 0.5
          : size.width == 1280
          ? 2 / 3
          : 1.0;
      await pumpTvWidget(
        tester,
        Builder(
          builder: (context) {
            final tv = TvTheme.of(context);
            expect(tv.scale, closeTo(expected, 0.000001));
            expect(tv.title.fontSize, closeTo(28 * expected, 0.000001));
            expect(MediaQuery.textScalerOf(context), TextScaler.noScaling);
            expect(InputModeTracker.isKeyboardMode(context), isTrue);
            return Align(
              child: SizedBox(key: const Key('poster'), width: tv.px(216), height: tv.px(324)),
            );
          },
        ),
        size: size,
        textScaler: TextScaler.linear(1.3),
      );
      expect(tester.getSize(find.byKey(const Key('poster'))), Size(216 * expected, 324 * expected));
    });
  }

  testWidgets('A3 styles, upstream compatibility and theme isolation', (tester) async {
    final outside = ThemeData(extensions: const [testMonoTokens]);
    await tester.pumpWidget(
      MaterialApp(
        theme: outside,
        home: Builder(
          builder: (context) {
            final before = Theme.of(context);
            return Column(
              children: [
                TvTheme(
                  child: Builder(
                    builder: (context) {
                      final tv = TvTheme.of(context);
                      final styles = [
                        tv.display,
                        tv.headline,
                        tv.title,
                        tv.bodyLarge,
                        tv.body,
                        tv.label,
                        tv.caption,
                        tv.badge,
                      ];
                      const sizes = [56, 40, 28, 24, 22, 22, 18, 16];
                      const heights = [64, 48, 36, 34, 30, 28, 24, 20];
                      const weights = [800, 700, 700, 400, 500, 600, 500, 700];
                      // Default test surface is 800×600: min(800/1920, 600/1080).
                      for (var i = 0; i < styles.length; i++) {
                        expect(styles[i].fontFamily, 'Manrope');
                        expect(styles[i].fontFamilyFallback, ['Inter', 'Roboto']);
                        expect(styles[i].fontSize, closeTo(sizes[i] * 800 / 1920, 0.000001));
                        expect(styles[i].height, heights[i] / sizes[i]);
                        expect(styles[i].fontWeight, FontWeight.values[weights[i] ~/ 100 - 1]);
                        expect(styles[i].fontVariations, [FontVariation('wght', weights[i].toDouble())]);
                      }
                      expect(Theme.of(context).textTheme.titleLarge!.fontFamily, 'Manrope');
                      expect(Theme.of(context).textTheme.titleLarge!.fontSize, tv.title.fontSize);
                      expect(tokens(context), same(testMonoTokens));
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                Builder(
                  builder: (context) {
                    expect(Theme.of(context), same(before));
                    expect(Theme.of(context).textTheme, before.textTheme);
                    return const SizedBox.shrink();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme supplies MonoTokens when the parent has none; helper toggles tier', (tester) async {
    await pumpTvWidget(
      tester,
      Builder(
        builder: (context) {
          expect(tokens(context), isA<MonoTokens>());
          expect(DevicePerformance.isReduced, isTrue);
          return const SizedBox.shrink();
        },
      ),
      reduced: true,
    );
    expect(tester.takeException(), isNull);
  });

  test('English component templates reuse Plezy formatting', () {
    expect(TvStrings.left(4800000), '${formatDurationTextual(4800000)} left');
    expect(TvStrings.unwatched(1), '1 unwatched');
    expect(TvStrings.unwatched(12), '12 unwatched');
    expect(TvStrings.episode(season: 1, episode: 3, title: 'Title'), 'S1 E3 · Title');
  });
}
