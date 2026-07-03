import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reader_screen.dart';

void main() {
  testWidgets('EPUB 路徑顯示 EPUB 佔位畫面', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(filePath: 'test/fixtures/sample.epub'),
      ),
    );

    expect(find.text('閱讀器'), findsOneWidget);
    expect(find.text('EPUB 佔位畫面（尚未接上 Readium 原生渲染）'), findsOneWidget);
  });

  testWidgets('PDF 路徑顯示 PDF 佔位畫面', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(filePath: 'test/fixtures/sample.pdf'),
      ),
    );

    expect(find.text('PDF 佔位畫面（尚未接上 PdfRenderer 原生渲染）'), findsOneWidget);
  });

  testWidgets('不支援格式顯示明確錯誤訊息', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(filePath: 'test/fixtures/sample.txt'),
      ),
    );

    expect(find.text('不支援的檔案格式'), findsOneWidget);
  });
}
