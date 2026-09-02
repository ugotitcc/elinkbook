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
          ),
        ),
      ),
    );
    button = tester.widget<IconButton>(
      find.byKey(const Key('annotation_toolbar_note')),
    );
    expect(button.tooltip, '新增備註');
  });
}
