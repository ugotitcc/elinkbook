import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/screens/annotation_toolbar.dart';

void main() {
  testWidgets('顯示螢光筆三色、底線、備註、關閉共 6 個按鈕', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
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
}
