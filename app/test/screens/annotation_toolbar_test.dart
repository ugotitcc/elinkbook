import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/screens/annotation_toolbar.dart';
import '../support/wcag_contrast.dart';

Future<void> _pumpToolbar(
  WidgetTester tester, {
  required AppTheme theme,
  required bool isEinkMode,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: resolveThemeData(theme: theme, isEinkMode: isEinkMode),
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (_) {},
          onNotePressed: () {},
          onClosePressed: () {},
          onCopyPressed: () {},
          isEinkMode: isEinkMode,
        ),
      ),
    ),
  );
}

/// 工具列最外層的 `Material`（有 `RoundedRectangleBorder` 的那個）外框。
BorderSide _toolbarBorder(WidgetTester tester) {
  final material = tester.widget<Material>(
    find
        .descendant(
          of: find.byType(AnnotationToolbar),
          matching: find.byType(Material),
        )
        .first,
  );
  return (material.shape! as RoundedRectangleBorder).side;
}

void main() {
  group('螢光筆色塊辨識度', () {
    // 色塊本身很淡時（米色主題、E-Ink 灰階），要靠外框讓使用者看得到；
    // 非文字元件的 WCAG 對比標準是 3:1。
    for (final theme in [AppTheme.sepia, AppTheme.light]) {
      testWidgets('${theme.name}：三個色塊都有外框，外框對工具列底色對比 ≥ 3',
          (tester) async {
        await _pumpToolbar(tester, theme: theme, isEinkMode: false);

        final surface = Theme.of(tester.element(find.byType(AnnotationToolbar)))
            .colorScheme
            .surface;
        for (final name in ['yellow', 'pink', 'blue']) {
          final swatch = find.descendant(
            of: find.byKey(Key('annotation_toolbar_highlighter_$name')),
            matching: find.byType(DecoratedBox),
          );
          expect(swatch, findsOneWidget, reason: '$name 色塊要有外框裝飾');
          final decoration =
              tester.widget<DecoratedBox>(swatch).decoration as BoxDecoration;
          final border = decoration.border! as Border;
          expect(
            contrastRatio(border.top.color, surface),
            greaterThanOrEqualTo(3),
            reason: '$name 色塊外框要看得清楚',
          );
        }
      });
    }
  });

  group('外框（Issue 6b Task 9）', () {
    testWidgets('深色（非 E-Ink）有 1.5 寬、對底色對比 ≥ 4.5 的淺灰外框', (tester) async {
      await _pumpToolbar(tester, theme: AppTheme.dark, isEinkMode: false);

      final side = _toolbarBorder(tester);
      final scheme = Theme.of(tester.element(find.byType(AnnotationToolbar)))
          .colorScheme;
      expect(side.width, 1.5);
      // 深色的 `outline` 與 `surface` 幾乎同色，外框看不見；改用高對比灰色。
      expect(side.color, scheme.onSurfaceVariant);
      expect(
        contrastRatio(side.color, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('E-Ink 維持 outline 外框顏色', (tester) async {
      await _pumpToolbar(tester, theme: AppTheme.light, isEinkMode: true);

      final scheme = Theme.of(tester.element(find.byType(AnnotationToolbar)))
          .colorScheme;
      expect(_toolbarBorder(tester).color, scheme.outline);
    });

    testWidgets('E-Ink 維持 1.5 寬的 outline 外框', (tester) async {
      await _pumpToolbar(tester, theme: AppTheme.light, isEinkMode: true);

      expect(_toolbarBorder(tester).width, 1.5);
    });

    testWidgets('淺色且非 E-Ink 沒有外框', (tester) async {
      await _pumpToolbar(tester, theme: AppTheme.light, isEinkMode: false);

      expect(_toolbarBorder(tester), BorderSide.none);
    });
  });

  testWidgets('顯示螢光筆三色、底線、備註、關閉共 6 個按鈕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (_) {},
            onNotePressed: () {},
            onClosePressed: () {},
            onCopyPressed: () {},
            isEinkMode: false,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('annotation_toolbar_highlighter_yellow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('annotation_toolbar_highlighter_pink')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('annotation_toolbar_highlighter_blue')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('annotation_toolbar_underline')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('annotation_toolbar_note')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_close')), findsOneWidget);
    expect(
      find.byKey(const Key('annotation_toolbar_copy')),
      findsOneWidget,
      reason: '雙列版面第二列應永遠顯示複製按鈕（epic-27 Issue 11）',
    );
  });

  testWidgets('點擊黃色螢光筆按鈕觸發 onStyleSelected(highlighterYellow)', (tester) async {
    HighlightStyle? selected;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (style) => selected = style,
            onNotePressed: () {},
            onClosePressed: () {},
            onCopyPressed: () {},
            isEinkMode: false,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('annotation_toolbar_highlighter_yellow')),
    );
    expect(selected, HighlightStyle.highlighterYellow);
  });

  testWidgets('點擊粉色螢光筆按鈕觸發 onStyleSelected(highlighterPink)', (tester) async {
    HighlightStyle? selected;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (style) => selected = style,
            onNotePressed: () {},
            onClosePressed: () {},
            onCopyPressed: () {},
            isEinkMode: false,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('annotation_toolbar_highlighter_pink')),
    );
    expect(selected, HighlightStyle.highlighterPink);
  });

  testWidgets('點擊藍色螢光筆按鈕觸發 onStyleSelected(highlighterBlue)', (tester) async {
    HighlightStyle? selected;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (style) => selected = style,
            onNotePressed: () {},
            onClosePressed: () {},
            onCopyPressed: () {},
            isEinkMode: false,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('annotation_toolbar_highlighter_blue')),
    );
    expect(selected, HighlightStyle.highlighterBlue);
  });

  testWidgets('點擊底線按鈕觸發 onStyleSelected(underline)', (tester) async {
    HighlightStyle? selected;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (style) => selected = style,
            onNotePressed: () {},
            onClosePressed: () {},
            onCopyPressed: () {},
            isEinkMode: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('annotation_toolbar_underline')));
    expect(selected, HighlightStyle.underline);
  });

  testWidgets('點擊備註按鈕觸發 onNotePressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (_) {},
            onNotePressed: () => pressed = true,
            onClosePressed: () {},
            onCopyPressed: () {},
            isEinkMode: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('annotation_toolbar_note')));
    expect(pressed, isTrue);
  });

  testWidgets('點擊關閉按鈕觸發 onClosePressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (_) {},
            onNotePressed: () {},
            onClosePressed: () => pressed = true,
            onCopyPressed: () {},
            isEinkMode: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('annotation_toolbar_close')));
    expect(pressed, isTrue);
  });

  testWidgets('點擊複製按鈕觸發 onCopyPressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (_) {},
            onNotePressed: () {},
            onClosePressed: () {},
            onCopyPressed: () => pressed = true,
            isEinkMode: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('annotation_toolbar_copy')));
    expect(pressed, isTrue);
  });

  testWidgets('onDeletePressed 為 null 時不顯示刪除按鈕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (_) {},
            onNotePressed: () {},
            onClosePressed: () {},
            onCopyPressed: () {},
            isEinkMode: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('annotation_toolbar_delete')), findsNothing);
  });

  testWidgets('onDeletePressed 非 null 時顯示刪除按鈕，tooltip 對應 deleteButtonLabel', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (_) {},
            onNotePressed: () {},
            onClosePressed: () {},
            onCopyPressed: () {},
            isEinkMode: false,
            onDeletePressed: () => pressed = true,
            deleteButtonLabel: '刪除畫線',
          ),
        ),
      ),
    );

    final finder = find.byKey(const Key('annotation_toolbar_delete'));
    expect(finder, findsOneWidget);
    final button = tester.widget<IconButton>(finder);
    expect(button.tooltip, '刪除畫線');

    await tester.tap(finder);
    expect(pressed, isTrue);
  });

  testWidgets('hasExistingNote 為 true 時，備註按鈕 tooltip 顯示「編輯備註」；'
      'false 時顯示「新增備註」', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (_) {},
            onNotePressed: () {},
            onClosePressed: () {},
            onCopyPressed: () {},
            isEinkMode: false,
            hasExistingNote: true,
          ),
        ),
      ),
    );
    var button = tester.widget<IconButton>(
      find.byKey(const Key('annotation_toolbar_note')),
    );
    expect(button.tooltip, '編輯備註');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (_) {},
            onNotePressed: () {},
            onClosePressed: () {},
            onCopyPressed: () {},
            isEinkMode: false,
          ),
        ),
      ),
    );
    button = tester.widget<IconButton>(
      find.byKey(const Key('annotation_toolbar_note')),
    );
    expect(button.tooltip, '新增備註');
  });

  group('E-Ink 感知（DESIGN.md §5：E-Ink 模式陰影強制為 none，改用邊框）', () {
    testWidgets('isEinkMode: false 時維持陰影，不加邊框', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: Scaffold(
            body: AnnotationToolbar(
              onStyleSelected: (_) {},
              onNotePressed: () {},
              onClosePressed: () {},
              onCopyPressed: () {},
              isEinkMode: false,
            ),
          ),
        ),
      );

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AnnotationToolbar),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.elevation, 4);
      final shape = material.shape as RoundedRectangleBorder;
      expect(shape.side, BorderSide.none);
    });

    testWidgets('isEinkMode: true 時陰影歸零，改用 outline 邊框', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
          theme: buildEinkThemeData(),
          home: Scaffold(
            body: AnnotationToolbar(
              onStyleSelected: (_) {},
              onNotePressed: () {},
              onClosePressed: () {},
              onCopyPressed: () {},
              isEinkMode: true,
            ),
          ),
        ),
      );

      final context = tester.element(find.byType(AnnotationToolbar));
      final colorScheme = Theme.of(context).colorScheme;
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AnnotationToolbar),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.elevation, 0);
      final shape = material.shape as RoundedRectangleBorder;
      expect(shape.side.color, colorScheme.outline);
      expect(shape.side.width, 1.5);
    });
  });
  testWidgets('英文介面下底線/關閉/複製/備註 tooltip 正確以英文渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (_) {},
            onNotePressed: () {},
            onClosePressed: () {},
            onCopyPressed: () {},
            isEinkMode: false,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Underline'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(find.byTooltip('Add note'), findsOneWidget);
  });

  testWidgets('onLookupPressed 為 null 時不顯示查字典按鈕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (_) {},
            onNotePressed: () {},
            onClosePressed: () {},
            onCopyPressed: () {},
            isEinkMode: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('annotation_toolbar_lookup')), findsNothing);
  });

  testWidgets('onLookupPressed 非 null：顯示按鈕，點擊觸發一次 callback', (tester) async {
    var pressedCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
        home: Scaffold(
          body: AnnotationToolbar(
            onStyleSelected: (_) {},
            onNotePressed: () {},
            onClosePressed: () {},
            onCopyPressed: () {},
            isEinkMode: false,
            onLookupPressed: () => pressedCount++,
          ),
        ),
      ),
    );

    final finder = find.byKey(const Key('annotation_toolbar_lookup'));
    expect(finder, findsOneWidget);
    await tester.tap(finder);
    expect(pressedCount, 1);
  });

  testWidgets('查字典按鈕的 tooltip 隨語言切換', (tester) async {
    Widget toolbar(Locale locale) => MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
          home: Scaffold(
            body: AnnotationToolbar(
              onStyleSelected: (_) {},
              onNotePressed: () {},
              onClosePressed: () {},
              onCopyPressed: () {},
              isEinkMode: false,
              onLookupPressed: () {},
            ),
          ),
        );

    await tester.pumpWidget(toolbar(const Locale('zh', 'TW')));
    expect(find.byTooltip('查字典'), findsOneWidget);

    await tester.pumpWidget(toolbar(const Locale('en')));
    expect(find.byTooltip('Look up'), findsOneWidget);
  });
}
