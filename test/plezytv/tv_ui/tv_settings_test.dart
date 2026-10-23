import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/tv_settings.dart';
import 'package:plezy/plezytv/tv_ui/tv_strings.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/widgets/focusable_list_tile.dart';

import '../../test_helpers/prefs.dart';

void main() {
  setUp(resetSharedPreferencesForTest);
  tearDown(TvUi.resetForTesting);

  test('show downloads defaults off and writes notify listeners', () async {
    final settings = await SettingsService.getInstance();
    final values = <bool>[];
    final listenable = settings.listenable(TvSettings.showDownloads);
    void changed() => values.add(listenable.value);
    listenable.addListener(changed);
    addTearDown(() => listenable.removeListener(changed));

    expect(settings.read(TvSettings.showDownloads), isFalse);
    await settings.write(TvSettings.showDownloads, true);
    expect(settings.read(TvSettings.showDownloads), isTrue);
    expect(settings.prefs.getBool('plezytv_show_downloads'), isTrue);
    await settings.write(TvSettings.showDownloads, false);
    expect(settings.read(TvSettings.showDownloads), isFalse);
    expect(values, [true, false]);
  });

  testWidgets('TV tile toggles the preference and follows live changes', (tester) async {
    final settings = await SettingsService.getInstance();
    TvUi.enabledForTesting = () => true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: (context) => TvSettings.settingsTile(context)!)),
      ),
    );
    expect(find.text(TvStrings.showDownloads), findsOneWidget);
    expect(tester.widget<FocusableSwitchListTile>(find.byType(FocusableSwitchListTile)).value, isFalse);
    await tester.tap(find.text(TvStrings.showDownloads));
    await tester.pumpAndSettle();
    expect(settings.read(TvSettings.showDownloads), isTrue);
    await settings.write(TvSettings.showDownloads, false);
    await tester.pumpAndSettle();
    expect(tester.widget<FocusableSwitchListTile>(find.byType(FocusableSwitchListTile)).value, isFalse);
  });

  testWidgets('no tile outside TV', (tester) async {
    TvUi.enabledForTesting = () => false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(TvSettings.settingsTile(context), isNull);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(find.text(TvStrings.showDownloads), findsNothing);
  });
}
