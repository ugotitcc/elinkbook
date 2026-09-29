import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/stats/reading_stats_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_reading_stats_repository.dart';
import 'reader_screen_stats_harness.dart';

void main() {
  registerReaderStatsTestEnvironment();

  testWidgets('僅注入 repository：開書後翻頁再進背景，repository 出現當日該書紀錄',
      (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(tester, readingStatsRepository: repository);

    reportLocator(tester, 1); // 開書後第一次回報（初始定位）：不算活動
    await tester.pump(const Duration(seconds: 10));
    reportLocator(tester, 2); // 翻頁：回溯採計開書後的 10 秒
    await tester.pump(const Duration(seconds: 20));
    moveAppToBackground(tester);
    await tester.pump();

    final stats = await repository.getBookStatsForDate(statsToday());
    expect(stats, hasLength(1));
    expect(stats.single.bookId, kStatsTestBookId);
    expect(stats.single.bookTitle, kStatsTestBookTitle);
    expect(stats.single.readingSeconds, 30);

    await disposeStatsReader(tester);
  });

  testWidgets('開書後立即退出，不產生時數', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(tester, readingStatsRepository: repository);

    await tester.pump(const Duration(seconds: 60));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 0);
  });

  testWidgets('開書後第一次位置回報（初始定位）不算閱讀活動', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(tester, readingStatsRepository: repository);

    reportLocator(tester, 1);
    await tester.pump(const Duration(seconds: 60));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 0);
  });

  // 上一頁與下一頁各測一次：兩個方向各自有一行轉送，合在一起測會互相掩護。
  for (final action in [ZoneAction.nextPage, ZoneAction.previousPage]) {
    testWidgets('熱區 ${action.name} 算閱讀活動（回溯開書後 10 秒，再加翻頁後 20 秒）',
        (tester) async {
      final repository = FakeReadingStatsRepository();
      final key = GlobalKey<State<ReaderScreen>>();
      await pumpStatsReader(
        tester,
        readingStatsRepository: repository,
        readerKey: key,
      );

      await tester.pump(const Duration(seconds: 10));
      ReaderScreen.triggerZoneAction(key, action);
      await tester.pump(const Duration(seconds: 20));
      await disposeStatsReader(tester);

      expect(await repository.getTotalReadingSeconds(), 30);
    });
  }

  testWidgets('點擊叫出工具列（menu 熱區）不算閱讀活動', (tester) async {
    final repository = FakeReadingStatsRepository();
    final key = GlobalKey<State<ReaderScreen>>();
    await pumpStatsReader(
      tester,
      readingStatsRepository: repository,
      readerKey: key,
    );

    await tester.pump(const Duration(seconds: 30));
    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump(const Duration(seconds: 30));
    ReaderScreen.triggerZoneAction(key, ZoneAction.menu);
    await tester.pump(const Duration(seconds: 30));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 0);
  });

  testWidgets('Foliate 長按選取（劃線）算閱讀活動', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(tester, readingStatsRepository: repository);

    await tester.pump(const Duration(seconds: 10));
    tester
        .widget<FoliateReaderView>(find.byType(FoliateReaderView))
        .onSelectionChanged
        ?.call(
          const EpubSelectionInfo(
            locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
            progression: 0.1,
            rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
          ),
        );
    await tester.pump(const Duration(seconds: 20));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 30);
  });

  testWidgets('PDF：開書後第一次頁碼回報不算，之後的翻頁算閱讀活動', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(
      tester,
      filePath: 'test/fixtures/sample_multi_page.pdf',
      readingStatsRepository: repository,
    );
    final pdfView = tester.widget<PdfReaderView>(find.byType(PdfReaderView));

    pdfView.onPageChanged
        ?.call(const PdfPageInfo(pageIndex: 0, totalPages: 5)); // 初始定位
    await tester.pump(const Duration(seconds: 10));
    pdfView.onPageChanged
        ?.call(const PdfPageInfo(pageIndex: 1, totalPages: 5)); // 翻頁：回溯 10 秒
    await tester.pump(const Duration(seconds: 20));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 30);
  });

  testWidgets('PDF 長按框選算閱讀活動', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(
      tester,
      filePath: 'test/fixtures/sample_multi_page.pdf',
      readingStatsRepository: repository,
    );

    await tester.pump(const Duration(seconds: 10));
    tester
        .widget<PdfReaderView>(find.byType(PdfReaderView))
        .onSelectionRectComputed
        ?.call(
          const PdfSelectionInfo(
            pageIndex: 0,
            rect: PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
            widgetRect:
                PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
          ),
        );
    await tester.pump(const Duration(seconds: 20));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 30);
  });

  testWidgets('PDF 零面積長按（未命中既有標註）是無效操作，不算閱讀活動', (tester) async {
    final repository = FakeReadingStatsRepository();
    await pumpStatsReader(
      tester,
      filePath: 'test/fixtures/sample_multi_page.pdf',
      readingStatsRepository: repository,
    );

    await tester.pump(const Duration(seconds: 10));
    tester
        .widget<PdfReaderView>(find.byType(PdfReaderView))
        .onSelectionRectComputed
        ?.call(
          const PdfSelectionInfo(
            pageIndex: 0,
            rect: PercentRect(left: 0.3, top: 0.2, right: 0.3, bottom: 0.2),
            widgetRect:
                PercentRect(left: 0.3, top: 0.2, right: 0.3, bottom: 0.2),
          ),
        );
    await tester.pump(const Duration(seconds: 20));
    await disposeStatsReader(tester);

    expect(await repository.getTotalReadingSeconds(), 0);
  });

  testWidgets('寫入失敗不影響閱讀：不崩潰、不顯示錯誤，離開時也安全', (tester) async {
    final repository = FakeReadingStatsRepository()
      ..addReadingSecondsError = StateError('database is locked');
    await pumpStatsReader(tester, readingStatsRepository: repository);

    reportLocator(tester, 1);
    await tester.pump(const Duration(seconds: 10));
    reportLocator(tester, 2);
    await tester.pump(const Duration(seconds: 40)); // 跨過 30 秒定時寫入（失敗）
    moveAppToBackground(tester);
    await tester.pump();
    moveAppToForeground(tester);
    await tester.pump();

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
    expect(tester.takeException(), isNull);

    await disposeStatsReader(tester);
    expect(tester.takeException(), isNull);
    expect(await repository.getTotalReadingSeconds(), 0);
  });

  testWidgets('同時注入 tracker 與 repository：以 tracker 為準，repository 不被寫入',
      (tester) async {
    final repository = FakeReadingStatsRepository();
    final flushed = <int>[];
    final tracker = ReadingStatsTracker(
      bookId: kStatsTestBookId,
      bookTitle: kStatsTestBookTitle,
      onFlush: (date, bookId, bookTitle, seconds) async => flushed.add(seconds),
    );
    await pumpStatsReader(
      tester,
      readingStatsRepository: repository,
      readingStatsTracker: tracker,
    );

    reportLocator(tester, 1);
    await tester.pump(const Duration(seconds: 10));
    reportLocator(tester, 2);
    await tester.pump(const Duration(seconds: 20));
    await disposeStatsReader(tester);

    expect(flushed.fold<int>(0, (sum, s) => sum + s), 30);
    expect(await repository.getTotalReadingSeconds(), 0);
  });
}
