import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_page_turn_animation.dart';
import 'package:elinkbook/reader/pdf_page_turn_mode.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: BookReaderPrefs.empty,
            onChanged: (_) {},
            isEinkMode: false,
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: BookReaderPrefs.empty,
            onChanged: (prefs) => changed = prefs,
            isEinkMode: false,
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(dualPageMode: DualPageMode.never),
            onChanged: (_) {},
            isEinkMode: false,
          ),
        ),
      ),
    );

    // 【審查修正 Minor：見 reviews/review-issue-5-8.md Issue 6 Minor #2】
    // 原本斷言 isNotNull——但 ReaderOptionTile 不論選中與否，
    // BoxDecoration.color 恆為非 null（選中是 primary，未選中
    // 是 surface），改造後這個斷言不論選中邏輯對不對都會通過，等同於
    // 失去鑑別力。改為精確比對選中/未選中應有的背景色，並確認兩者不同。
    // 【視覺還原修正】選中態背景色由 primaryContainer 改為 primary（見
    // reader_option_tile.dart、docs/research/uiux/VISUAL_ANALYSIS.md）。
    final theme = Theme.of(tester.element(find.byType(FxlSettingsSheet)));
    final selectedContainer = tester.widget<Container>(
      find.byKey(const Key('fxl_settings_dual_page_mode_never')),
    );
    final unselectedContainer = tester.widget<Container>(
      find.byKey(const Key('fxl_settings_dual_page_mode_auto')),
    );
    expect(
      (selectedContainer.decoration as BoxDecoration).color,
      theme.colorScheme.primary,
      reason: '目前選中的選項應以 primary 背景標示',
    );
    expect(
      (unselectedContainer.decoration as BoxDecoration).color,
      theme.colorScheme.surface,
      reason: '未選中的選項應以 surface 背景標示',
    );
  });

  testWidgets('已持久化 fullscreen=true 時，全螢幕模式開關初始值反映為開啟', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(fullscreen: true),
            onChanged: (_) {},
            isEinkMode: false,
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(dualPageMode: DualPageMode.always),
            onChanged: (prefs) => changed = prefs,
            isEinkMode: false,
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(showHeader: true),
            onChanged: (_) {},
            isEinkMode: false,
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(showFooter: true),
            onChanged: (_) {},
            isEinkMode: false,
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(dualPageMode: DualPageMode.always),
            onChanged: (prefs) => changed = prefs,
            isEinkMode: false,
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(fullscreen: true),
            onChanged: (prefs) => changed = prefs,
            isEinkMode: false,
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(dualPageDirection: DualPageDirection.rtl),
            onChanged: (prefs) => changed = prefs,
            isEinkMode: false,
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
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(dualPageDirection: DualPageDirection.ltr),
            onChanged: (prefs) => changed = prefs,
            isEinkMode: false,
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('fxl_settings_direction_rtl')));
      await tester.pump();

      expect(changed?.dualPageDirection, DualPageDirection.rtl);
    });

    testWidgets('未指定時預設選中 RTL（全域預設值）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: BookReaderPrefs.empty,
            onChanged: (_) {},
            isEinkMode: false,
          ),
        ),
      ));

      // 【審查修正 Minor：見 reviews/review-issue-5-8.md Issue 6 Minor #2】
      // 原本改成 findsOneWidget 只驗證元件存在，完全放棄了測試名稱宣稱
      // 的「預設選中 RTL」這件事。改為精確比對 rtl（選中）與 ltr（未
      // 選中）的背景色，真正鑑別選中狀態。
      final theme = Theme.of(tester.element(find.byType(FxlSettingsSheet)));
      final rtlContainer = tester.widget<Container>(
        find.byKey(const Key('fxl_settings_direction_rtl')),
      );
      final ltrContainer = tester.widget<Container>(
        find.byKey(const Key('fxl_settings_direction_ltr')),
      );
      expect(
        (rtlContainer.decoration as BoxDecoration).color,
        theme.colorScheme.primary,
        reason: 'RTL 為全域預設值，應以 primary 背景標示選中',
      );
      expect(
        (ltrContainer.decoration as BoxDecoration).color,
        theme.colorScheme.surface,
        reason: 'LTR 未選中，應以 surface 背景標示',
      );
    });
  });

  testWidgets('FxlSettingsSheet 在 E-Ink 模式下雙頁模式選項具備高對比選中底色', (tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      theme: buildEinkThemeData(),
      home: Scaffold(
        body: FxlSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (_) {},
          isEinkMode: true,
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

  testWidgets(
      '雙頁模式群組改用 EBOptionChipGroup 後，3 個選項皆顯示 spec.md 選項標籤'
      '對照表定義的短標籤（epic-39-layout-settings-redesign Issue 6）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: FxlSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (_) {},
          isEinkMode: false,
        ),
      ),
    ));

    for (final item in [
      ('auto', '自動'),
      ('always', '雙頁'),
      ('never', '單頁'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('fxl_settings_dual_page_mode_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'fxl_settings_dual_page_mode_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets(
      '翻頁方向群組改用 EBOptionChipGroup 後，2 個選項皆顯示短標籤'
      '（epic-39-layout-settings-redesign Issue 6）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: FxlSettingsSheet(
          prefs: BookReaderPrefs.empty,
          onChanged: (_) {},
          isEinkMode: false,
        ),
      ),
    ));

    for (final item in [
      ('ltr', '左翻'),
      ('rtl', '右翻'),
    ]) {
      final (suffix, label) = item;
      expect(
        find.descendant(
          of: find.byKey(Key('fxl_settings_direction_$suffix')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'fxl_settings_direction_$suffix 應顯示標籤「$label」',
      );
    }
  });

  testWidgets('showTextConversion: true 時顯示簡繁轉換覆寫選項', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: BookReaderPrefs.empty,
            onChanged: (_) {},
            isEinkMode: false,
            showTextConversion: true,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('fxl_settings_text_conversion_global')),
      findsOneWidget,
    );
  });

  testWidgets('showTextConversion: false 時不顯示簡繁轉換覆寫選項（CBZ）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: BookReaderPrefs.empty,
            onChanged: (_) {},
            isEinkMode: false,
            showTextConversion: false,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('fxl_settings_text_conversion_global')),
      findsNothing,
    );
  });

  testWidgets('省略 showTextConversion 參數時，預設顯示簡繁轉換覆寫選項（向後相容）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: BookReaderPrefs.empty,
            onChanged: (_) {},
            isEinkMode: false,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('fxl_settings_text_conversion_global')),
      findsOneWidget,
    );
  });

  testWidgets('已持久化 pdfPageTurnMode／pdfPageTurnAnimation 時，調整雙頁模式不會清空這兩個欄位（回歸檢查）',
      (tester) async {
    BookReaderPrefs? changed;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(
              pdfPageTurnMode: PdfPageTurnMode.scroll,
              pdfPageTurnAnimation: PdfPageTurnAnimation.none,
            ),
            onChanged: (prefs) => changed = prefs,
            isEinkMode: false,
          ),
        ),
      ),
    );
    await tester
        .tap(find.byKey(const Key('fxl_settings_dual_page_mode_always')));
    await tester.pump();
    expect(changed?.dualPageMode, DualPageMode.always);
    expect(changed?.pdfPageTurnMode, PdfPageTurnMode.scroll,
        reason: '關鍵斷言：整列重建時不可把翻頁模式清成 null');
    expect(changed?.pdfPageTurnAnimation, PdfPageTurnAnimation.none);
  });
  testWidgets('點擊「轉換為繁體」圖示後，onChanged 帶入 TextConversionMode.toTraditional，其餘欄位維持原值',
      (tester) async {
    BookReaderPrefs? changed;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(dualPageMode: DualPageMode.always),
            onChanged: (prefs) => changed = prefs,
            isEinkMode: false,
            showTextConversion: true,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('fxl_settings_text_conversion_traditional')),
    );
    await tester.pump();

    expect(changed?.textConversionOverride, TextConversionMode.toTraditional);
    expect(changed?.dualPageMode, DualPageMode.always);
  });

  testWidgets(
      'textConversionOverride 初始為 toSimplified 時，點擊「使用全域預設」圖示後，'
      'onChanged 帶入 null，其餘欄位不受影響', (tester) async {
    BookReaderPrefs? changed;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: const BookReaderPrefs(
              dualPageMode: DualPageMode.never,
              textConversionOverride: TextConversionMode.toSimplified,
            ),
            onChanged: (prefs) => changed = prefs,
            isEinkMode: false,
            showTextConversion: true,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('fxl_settings_text_conversion_global')),
    );
    await tester.pump();

    expect(changed?.textConversionOverride, isNull);
    expect(changed?.dualPageMode, DualPageMode.never);
  });

  testWidgets('英文介面下雙頁模式/翻頁方向/全螢幕開關文字正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FxlSettingsSheet(
            prefs: BookReaderPrefs.empty,
            onChanged: (_) {},
            isEinkMode: false,
          ),
        ),
      ),
    );

    expect(find.text('Dual-page mode'), findsOneWidget);
    expect(find.text('Fullscreen mode'), findsOneWidget);
  });
}

Future<void> _pumpModalSheet(
  WidgetTester tester,
  BookReaderPrefs prefs,
  ValueChanged<BookReaderPrefs> onChanged,
) async {
  await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
              isEinkMode: false,
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
