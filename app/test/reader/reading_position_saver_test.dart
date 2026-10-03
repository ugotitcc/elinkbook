import 'package:elinkbook/reader/book_format.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/pdf_page_info.dart';
import 'package:elinkbook/reader/reading_position.dart';
import 'package:elinkbook/reader/reading_position_saver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_reader_prefs_manager.dart';

void main() {
  late FakeReaderPrefsManager prefs;

  ReadingPositionSaver buildSaver({
    bool hasJumpTarget = false,
    double? initialProgress,
  }) =>
      ReadingPositionSaver(
        bookId: 'b1',
        prefsManager: prefs,
        hasJumpTarget: hasJumpTarget,
        initialProgress: initialProgress,
      );

  setUp(() => prefs = FakeReaderPrefsManager());

  group('尚未收到任何回報', () {
    test('PDF 不儲存', () {
      buildSaver().save(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('Foliate 格式不儲存（逐一涵蓋五種格式）', () {
      for (final format in [
        BookFormat.epub,
        BookFormat.azw3,
        BookFormat.cbz,
        BookFormat.txt,
        BookFormat.md,
      ]) {
        buildSaver().save(format);
      }
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('unknown 格式即使有回報也不儲存', () {
      final saver = buildSaver();
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 1, totalPages: 4));
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{}', progression: 0.5));
      saver.save(BookFormat.unknown);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });
  });

  group('PDF', () {
    test('儲存頁碼，進度為 (頁碼+1)/總頁數', () {
      final saver = buildSaver();
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 3, totalPages: 10));
      saver.save(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls, hasLength(1));
      expect(prefs.savedReadingPositionCalls.single.key, 'b1');
      expect(
        prefs.savedReadingPositionCalls.single.value,
        const ReadingPosition(pdfPageIndex: 3, progress: 0.4),
      );
    });

    test('總頁數為 0 時進度為 0，不拋例外', () {
      final saver = buildSaver();
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 0, totalPages: 0));
      saver.save(BookFormat.pdf);
      expect(
        prefs.savedReadingPositionCalls.single.value,
        const ReadingPosition(pdfPageIndex: 0, progress: 0),
      );
    });

    test('以最新一次回報為準', () {
      final saver = buildSaver();
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 1, totalPages: 10));
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 5, totalPages: 10));
      saver.save(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls.single.value.pdfPageIndex, 5);
    });
  });

  group('Foliate 格式', () {
    test('有 progression 時儲存定位點與該進度', () {
      final saver = buildSaver(initialProgress: 0.1);
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{"cfi":"a"}', progression: 0.7));
      saver.save(BookFormat.epub);
      expect(
        prefs.savedReadingPositionCalls.single.value,
        const ReadingPosition(epubLocatorJson: '{"cfi":"a"}', progress: 0.7),
      );
    });

    test('progression 為 null 時沿用開書時的進度，不倒退成 0', () {
      final saver = buildSaver(initialProgress: 0.8);
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{"cfi":"b"}'));
      saver.save(BookFormat.cbz);
      expect(
        prefs.savedReadingPositionCalls.single.value,
        const ReadingPosition(epubLocatorJson: '{"cfi":"b"}', progress: 0.8),
      );
    });

    test('progression 為 null 且開書時也沒有進度，不儲存', () {
      final saver = buildSaver();
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{"cfi":"c"}'));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });
  });

  group('有跳轉目標（例如從搜尋結果開書）', () {
    test('PDF：只有開書後第一次回報就離開，不儲存，保留既有位置', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 2, totalPages: 5));
      saver.save(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('PDF：使用者翻頁後（第二次回報）才儲存', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 2, totalPages: 5));
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 3, totalPages: 5));
      saver.save(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls.single.value.pdfPageIndex, 3);
    });

    test('Foliate：只有第一次回報就離開，不儲存', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{"cfi":"j"}', progression: 0.2));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('Foliate：第二次回報後才儲存', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{"cfi":"j"}', progression: 0.2));
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{"cfi":"k"}', progression: 0.3));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls.single.value.epubLocatorJson, '{"cfi":"k"}');
    });

    test('PDF 與 Foliate 的「已重新定位」各自獨立', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 1, totalPages: 5));
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 2, totalPages: 5));
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: '{}', progression: 0.1));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });
  });

  group('有跳轉目標：Foliate 同位置重複回報（epic-54 Issue 9）', () {
    test('同位置重複回報（fraction 抖動）不算重新定位，離開不儲存', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"j","index":1,"fraction":0.20}', progression: 0.2));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"j","index":1,"fraction":0.21}', progression: 0.21));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"j","index":1,"fraction":0.20}', progression: 0.2));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('locatorJson 完全相同的重複回報也不算重新定位', () {
      final saver = buildSaver(hasJumpTarget: true);
      const info = EpubPositionInfo(locatorJson: 'opaque', progression: 0.2);
      saver.onEpubLocated(info);
      saver.onEpubLocated(info);
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('cfi 相同但 index 不同算已移動，儲存', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"j","index":1}', progression: 0.2));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"j","index":2}', progression: 0.3));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, hasLength(1));
    });

    test('重複回報夾雜真移動，儲存最後一筆的定位點與進度', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"j","index":1,"fraction":0.20}', progression: 0.2));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"k","index":1,"fraction":0.30}', progression: 0.3));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"k","index":1,"fraction":0.31}', progression: 0.31));
      saver.save(BookFormat.epub);
      expect(
        prefs.savedReadingPositionCalls.single.value,
        const ReadingPosition(
          epubLocatorJson: '{"cfi":"k","index":1,"fraction":0.31}',
          progress: 0.31,
        ),
      );
    });

    test('A→B→A 仍算已移動（旗標單向）', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"a","index":0}', progression: 0.1));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"b","index":0}', progression: 0.2));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"a","index":0}', progression: 0.1));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, hasLength(1));
    });

    test('locatorJson 無法解析時退回整段字串比較（不同才算移動）', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: 'p1', progression: 0.1));
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: 'p1', progression: 0.1));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);

      saver.onEpubLocated(const EpubPositionInfo(locatorJson: 'p2', progression: 0.2));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, hasLength(1));
    });
  });

  group('沒有跳轉目標（一般開書）', () {
    test('Foliate：第一次回報就可以儲存，不受重複回報規則影響', () {
      final saver = buildSaver();
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"a","index":0}', progression: 0.4));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, hasLength(1));
    });

    test('第一次回報就可以儲存', () {
      final saver = buildSaver();
      saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 0, totalPages: 5));
      saver.save(BookFormat.pdf);
      expect(prefs.savedReadingPositionCalls, hasLength(1));
    });
  });

  test('每次呼叫 save 都各自儲存一次', () {
    final saver = buildSaver();
    saver.onPdfPageChanged(const PdfPageInfo(pageIndex: 1, totalPages: 5));
    saver.save(BookFormat.pdf);
    saver.save(BookFormat.pdf);
    expect(prefs.savedReadingPositionCalls, hasLength(2));
  });
}
