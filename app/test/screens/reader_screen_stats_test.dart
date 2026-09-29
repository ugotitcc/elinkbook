import 'package:elinkbook/screens/book_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_library_repository.dart';
import '../support/fake_reading_stats_repository.dart';
import '../support/fake_search_repository.dart';
import 'reader_screen_stats_harness.dart';

void main() {
  registerReaderStatsTestEnvironment();

  testWidgets(
      '閱讀器→單書搜尋：推入的 BookSearchScreen 帶著同一個 readingStatsRepository'
      '（「閱讀器→單書搜尋→閱讀器」不遺失統計 repository）', (tester) async {
    final statsRepository = FakeReadingStatsRepository();

    // 比照 reader_screen_test.dart 既有的單書搜尋接線測試：不標記渲染完成。
    await pumpStatsReader(
      tester,
      readingStatsRepository: statsRepository,
      searchRepository: FakeSearchRepository(),
      libraryRepository: FakeLibraryRepository(),
      markRendered: false,
    );

    await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
    await tester.pumpAndSettle();

    final pushed =
        tester.widget<BookSearchScreen>(find.byType(BookSearchScreen));
    expect(pushed.readerFeatureRepositories.readingStatsRepository,
        same(statsRepository));

    await disposeStatsReader(tester);
  });

  testWidgets('閱讀器沒有 readingStatsRepository 時，單書搜尋 bundle 的欄位為 null',
      (tester) async {
    await pumpStatsReader(
      tester,
      searchRepository: FakeSearchRepository(),
      libraryRepository: FakeLibraryRepository(),
      markRendered: false,
    );

    await tester.tap(find.byKey(const Key('reader_chrome_search_button')));
    await tester.pumpAndSettle();

    final pushed =
        tester.widget<BookSearchScreen>(find.byType(BookSearchScreen));
    expect(pushed.readerFeatureRepositories.readingStatsRepository, isNull);

    await disposeStatsReader(tester);
  });
}
