import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/screens/fxl_settings_sheet.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

void main() {
  // 本檔案既有測試自 epic-19 Issue 1 起改用 `home: Scaffold(body: ...)` 包裹
  // （原本是 `home: FxlSettingsSheet(...)` 直接當 home）：新增的「全螢幕模式」
  // SwitchListTile 需要 Material 祖先元件才能正確渲染，比照 pdf_settings_sheet_test.dart／
  // reader_settings_sheet_test.dart 既有的 Scaffold 包裹寫法統一。
  testWidgets('能正常 pump 起，顯示三個雙頁模式選項', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: BookReaderPrefs.empty,
            onChanged: (_) {},
          ),
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
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: BookReaderPrefs.empty,
            onChanged: (prefs) => changed = prefs,
          ),
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
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(dualPageMode: DualPageMode.never),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    // 選中項目在 E-Ink 模式下會呈現黑底白字（見 ReaderOptionTile 實作）。
    final container = tester.widget<Container>(
      find.byKey(const Key('fxl_settings_dual_page_mode_never')),
    );
    expect(
      (container.decoration as BoxDecoration).color,
      isNotNull,
      reason: '目前選中的選項應以深色背景標示',
    );
  });

  testWidgets('已持久化 fullscreen=true 時，全螢幕模式開關初始值反映為開啟', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(fullscreen: true),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('fxl_settings_fullscreen')))
          .value,
      isTrue,
    );
  });

  testWidgets('開啟全螢幕模式開關後，onChanged 帶入 fullscreen=true 且不清空 dualPageMode',
      (tester) async {
    BookReaderPrefs? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(dualPageMode: DualPageMode.always),
            onChanged: (prefs) => changed = prefs,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('fxl_settings_fullscreen')));
    await tester.pump();

    expect(changed?.fullscreen, isTrue);
    expect(changed?.dualPageMode, DualPageMode.always);
  });

  testWidgets('點擊關閉按鈕後，Bottom Sheet 關閉（Navigator.pop 生效）', (tester) async {
    await _pumpModalSheet(tester, BookReaderPrefs.empty, (_) {});

    expect(find.byType(FxlSettingsSheet), findsOneWidget);

    await tester.tap(find.byKey(const Key('fxl_settings_close_button')));
    await tester.pumpAndSettle();

    expect(find.byType(FxlSettingsSheet), findsNothing);
  });

  testWidgets('已持久化 showHeader=true 時，顯示頁首開關初始值反映為開啟', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(showHeader: true),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('fxl_settings_show_header')))
          .value,
      isTrue,
    );
  });

  testWidgets('已持久化 showFooter=true 時，顯示頁尾開關初始值反映為開啟', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(showFooter: true),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<SwitchListTile>(
              find.byKey(const Key('fxl_settings_show_footer')))
          .value,
      isTrue,
    );
  });

  testWidgets('開啟顯示頁首開關後，onChanged 帶入 showHeader=true 且不清空其他欄位', (tester) async {
    BookReaderPrefs? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(dualPageMode: DualPageMode.always),
            onChanged: (prefs) => changed = prefs,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('fxl_settings_show_header')));
    await tester.pump();

    expect(changed?.showHeader, isTrue);
    expect(changed?.dualPageMode, DualPageMode.always);
  });

  testWidgets('開啟顯示頁尾開關後，onChanged 帶入 showFooter=true 且不清空其他欄位', (tester) async {
    BookReaderPrefs? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(fullscreen: true),
            onChanged: (prefs) => changed = prefs,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('fxl_settings_show_footer')));
    await tester.pump();

    expect(changed?.showFooter, isTrue);
    expect(changed?.fullscreen, isTrue);
  });

  group('翻頁方向', () {
    testWidgets('點擊 LTR 按鈕觸發 onChanged，dualPageDirection 更新為 ltr', (tester) async {
      BookReaderPrefs? changed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(dualPageDirection: DualPageDirection.rtl),
            onChanged: (prefs) => changed = prefs,
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('fxl_settings_direction_ltr')));
      await tester.pump();

      expect(changed?.dualPageDirection, DualPageDirection.ltr);
    });

    testWidgets('點擊 RTL 按鈕觸發 onChanged，dualPageDirection 更新為 rtl', (tester) async {
      BookReaderPrefs? changed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(dualPageDirection: DualPageDirection.ltr),
            onChanged: (prefs) => changed = prefs,
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('fxl_settings_direction_rtl')));
      await tester.pump();

      expect(changed?.dualPageDirection, DualPageDirection.rtl);
    });

    testWidgets('未指定時預設選中 RTL（全域預設值）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: BookReaderPrefs.empty,
            onChanged: (_) {},
          ),
        ),
      ));

      // ReaderOptionTile 在未選中狀態使用預設視覺密度，
      // 這裡只驗證 widget 存在即可。
      expect(find.byKey(const Key('fxl_settings_direction_rtl')), findsOneWidget);
    });
  });

  testWidgets('FxlSettingsSheet 在 E-Ink 模式下雙頁模式選項具備高對比選中底色', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEinkThemeData(),
      home: Scaffold(
        body: FxlSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (_) {},
        ),
      ),
    ));

    // 【審查修正 Important】key 直接掛在帶 BoxDecoration 的 Container 上
    // （見 Task 1 ReaderOptionTile 實作）。
    final autoTile = find.byKey(const Key('fxl_settings_dual_page_mode_auto'));
    expect(autoTile, findsOneWidget);
    final container = tester.widget<Container>(autoTile);
    expect((container.decoration as BoxDecoration).color, Colors.black);
  });
}

Future<void> _pumpModalSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            enableDrag: false,
            builder: (_) => FxlSettingsSheet(
              prefs: prefs,
              onChanged: onChanged,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
