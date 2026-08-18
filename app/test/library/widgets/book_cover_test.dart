import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/widgets/book_cover.dart';

Book _book({required bool isDownloaded}) {
  return Book(
    id: 'b1',
    title: '測試書',
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
      home: BookCover(book: _book(isDownloaded: false)),
    ));

    expect(find.byKey(const Key('book_cover_cloud_badge')), findsOneWidget);
  });

  testWidgets('isDownloaded 為 true 時不顯示雲朵角標', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: BookCover(book: _book(isDownloaded: true)),
    ));

    expect(find.byKey(const Key('book_cover_cloud_badge')), findsNothing);
  });
}
