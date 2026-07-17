import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/screens/annotation_toolbar.dart';

void main() {
  testWidgets('顯示螢光筆三色、底線、備註共 5 個按鈕', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(onStyleSelected: (_) {}, onNotePressed: () {}),
      ),
    ));

    expect(find.byKey(const Key('annotation_toolbar_highlighter_yellow')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_highlighter_pink')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_highlighter_blue')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_underline')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_note')), findsOneWidget);
  });

  testWidgets('點擊黃色螢光筆按鈕觸發 onStyleSelected(highlighterYellow)', (tester) async {
    HighlightStyle? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (style) => selected = style,
          onNotePressed: () {},
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('annotation_toolbar_highlighter_yellow')));
    expect(selected, HighlightStyle.highlighterYellow);
  });

  testWidgets('點擊底線按鈕觸發 onStyleSelected(underline)', (tester) async {
    HighlightStyle? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (style) => selected = style,
          onNotePressed: () {},
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('annotation_toolbar_underline')));
    expect(selected, HighlightStyle.underline);
  });

  testWidgets('點擊備註按鈕觸發 onNotePressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(onStyleSelected: (_) {}, onNotePressed: () => pressed = true),
      ),
    ));

    await tester.tap(find.byKey(const Key('annotation_toolbar_note')));
    expect(pressed, isTrue);
  });
}
