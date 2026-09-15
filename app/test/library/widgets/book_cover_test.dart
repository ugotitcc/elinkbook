import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/widgets/book_cover.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';

Book _book({required bool isDownloaded, String title = '測試書'}) {
  return Book(
    id: 'b1',
    title: title,
    format: BookFileFormat.epub,
    filePath: '/books/b1.epub',
    source: BookSource.calibreOpds,
    isDownloaded: isDownloaded,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  testWidgets('isDownloaded 為 false 時疊加雲朵角標', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: BookCover(book: _book(isDownloaded: false)),
    ));

    expect(find.byKey(const Key('book_cover_cloud_badge')), findsOneWidget);
  });

  testWidgets('isDownloaded 為 true 時不顯示雲朵角標', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: BookCover(book: _book(isDownloaded: true)),
    ));

    expect(find.byKey(const Key('book_cover_cloud_badge')), findsNothing);
  });

  testWidgets('沒有封面圖時顯示依格式圖示與書名', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: BookCover(book: _book(isDownloaded: true)),
    ));

    expect(find.byIcon(Icons.menu_book), findsOneWidget);
    expect(find.text('測試書'), findsOneWidget);
  });

  testWidgets(
      'E-Ink 模式開啟時，沒有封面圖的 BookCover 確實透傳 CoverPlaceholder 的外框'
      '（審查修正 I3：Task 1 只單元測試過 CoverPlaceholder 本身的外框邏輯，'
      'BookCover 作為對外生產元件的整合行為原本完全沒有測試保護，見'
      'reviews/review-plan-issue-9.md）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: true),
      home: BookCover(book: _book(isDownloaded: true)),
    ));

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.border, isNotNull);
  });

  testWidgets(
      'textConversion: toTraditional 時，CoverPlaceholder 書名縮略套用簡繁轉換（epic-42-text-conversion Issue 3）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: BookCover(
        book: _book(isDownloaded: true, title: '国电脑'),
        textConversion: TextConversionMode.toTraditional,
      ),
    ));

    expect(find.text('國電腦'), findsOneWidget);
    expect(find.text('国电脑'), findsNothing);
  });
}
