import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/screens/fxl_settings_sheet.dart';

void main() {
  testWidgets('能正常 pump 起，顯示三個雙頁模式選項', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FxlSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.byKey(const Key('fxl_settings_dual_page_mode_auto')), findsOneWidget);
    expect(find.byKey(const Key('fxl_settings_dual_page_mode_always')), findsOneWidget);
    expect(find.byKey(const Key('fxl_settings_dual_page_mode_never')), findsOneWidget);
  });

  testWidgets('點擊「永遠雙頁」觸發 onChanged', (tester) async {
    BookReaderPrefs? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: FxlSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (prefs) => changed = prefs,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('fxl_settings_dual_page_mode_always')));
    await tester.pump();

    expect(changed?.dualPageMode, DualPageMode.always);
  });

  testWidgets('已有持久化 dualPageMode 時，初始狀態正確反映', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FxlSettingsSheet(
          prefs: const BookReaderPrefs(dualPageMode: DualPageMode.never),
          onChanged: (_) {},
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('fxl_settings_dual_page_mode_never')),
    );
    expect(button.color, isNotNull, reason: '目前選中的選項應以主題色標示');
  });
}
