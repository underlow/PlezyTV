import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/shell/tv_settings_section.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';
import 'package:plezy/widgets/settings_section.dart';
import 'tv_theme_test_helper.dart';

void main() {
  testWidgets('settings groups start at 200 and use a flat base app bar', (tester) async {
    late ThemeData theme;
    await pumpTvWidget(
      tester,
      TvSettingsSection(
        child: Builder(
          builder: (context) {
            theme = Theme.of(context);
            return const Scaffold(
              body: SettingsGroup(
                children: [SizedBox(key: ValueKey('item'), height: 88, width: double.infinity)],
              ),
            );
          },
        ),
      ),
    );
    final item = tester.getRect(find.byKey(const ValueKey('item')));
    expect(item.left, 200);
    expect(item.width, lessThanOrEqualTo(1200));
    expect(theme.scaffoldBackgroundColor, TvTokens.color.bg.base);
    expect(theme.appBarTheme.backgroundColor, TvTokens.color.bg.base);
    expect(theme.appBarTheme.scrolledUnderElevation, 0);
  });
}
