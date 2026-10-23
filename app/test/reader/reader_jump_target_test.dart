// app/test/reader/reader_jump_target_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/foliate_reader_surface.dart';
import 'package:elinkbook/reader/pdf_reader_surface.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';
import 'package:elinkbook/reader/reader_surface.dart';

import '../support/fake_reader_surface.dart';

void main() {
  group('ReaderJumpTarget.fromContentLocator', () {
    test('Foliate 格式：locator 本身即為 CFI 字串，原樣帶入 cfi 欄位', () {
      final target = ReaderJumpTarget.fromContentLocator(
        format: BookFileFormat.epub,
        locator: 'epubcfi(/6/2!/4/2)',
      );

      expect(target, isNotNull);
      expect(target!.cfi, 'epubcfi(/6/2!/4/2)');
      expect(target.pdfPageIndex, isNull);
      expect(target.pdfRect, isNull);
    });

    test('KF8(AZW3)/TXT/MD 皆比照 EPUB，locator 原樣帶入 cfi 欄位', () {
      for (final format in [
        BookFileFormat.azw3,
        BookFileFormat.txt,
        BookFileFormat.md,
      ]) {
        final target = ReaderJumpTarget.fromContentLocator(
          format: format,
          locator: 'epubcfi(/6/4)',
        );
        expect(target?.cfi, 'epubcfi(/6/4)', reason: '格式 $format 應原樣帶入');
      }
    });

    test('PDF 格式：解析 {"page":int,"rect":{...}} JSON 字串', () {
      final target = ReaderJumpTarget.fromContentLocator(
        format: BookFileFormat.pdf,
        locator:
            '{"page":3,"rect":{"left":0.1,"top":0.2,"right":0.5,"bottom":0.3}}',
      );

      expect(target, isNotNull);
      expect(target!.pdfPageIndex, 3);
      expect(
        target.pdfRect,
        const PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3),
      );
      expect(target.cfi, isNull);
    });

    test('PDF 格式但 locator 不是合法 JSON 時回傳 null，呼叫端應退回一般開書路徑', () {
      final target = ReaderJumpTarget.fromContentLocator(
        format: BookFileFormat.pdf,
        locator: '不是 JSON',
      );

      expect(target, isNull);
    });

    test(
        'PDF 格式但 locator 缺少（或壞掉的）rect 欄位時，優雅降級為只有頁碼、沒有暫態高亮座標'
        '（審查修正 M-2，推翻原計畫「整筆回傳 null」設計）', () {
      final missingRect = ReaderJumpTarget.fromContentLocator(
        format: BookFileFormat.pdf,
        locator: '{"page":3}',
      );
      expect(missingRect, isNotNull);
      expect(missingRect!.pdfPageIndex, 3);
      expect(missingRect.pdfRect, isNull);

      final malformedRect = ReaderJumpTarget.fromContentLocator(
        format: BookFileFormat.pdf,
        locator: '{"page":3,"rect":"不是物件"}',
      );
      expect(malformedRect, isNotNull);
      expect(malformedRect!.pdfPageIndex, 3);
      expect(malformedRect.pdfRect, isNull);
    });

    test('PDF 格式但 locator 缺少 page 欄位時回傳 null（沒有頁碼就沒有任何可跳轉的目標）', () {
      final target = ReaderJumpTarget.fromContentLocator(
        format: BookFileFormat.pdf,
        locator: '{"rect":{"left":0.1,"top":0.2,"right":0.5,"bottom":0.3}}',
      );

      expect(target, isNull);
    });
  });

  // applyTo() 現在只委派給 ReaderSurface（epic-54 Issue 23）：格式分派搬進
  // adapter。這裡用「未掛載」的真實 adapter，聚焦驗證 applyTo() 與 adapter
  // 組合起來的回傳值語意；View 的副作用是否真的觸發，由 View 自己的測試與
  // reader_screen_test.dart 把關。

  group('applyTo：PDF 格式', () {
    test('pdfPageIndex 為 null 時，不論 shouldNavigate 為何皆回傳 false', () {
      const target = ReaderJumpTarget(
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      );

      expect(
        target.applyTo(
          surface: PdfReaderSurface(),
          shouldNavigate: false,
        ),
        isFalse,
      );
      expect(
        target.applyTo(
          surface: PdfReaderSurface(),
          shouldNavigate: true,
        ),
        isFalse,
      );
    });

    test('pdfPageIndex 存在、pdfRect 為 null 時回傳 false（只跳頁不顯示高亮）',
        () {
      const target = ReaderJumpTarget(pdfPageIndex: 3);

      expect(
        target.applyTo(
          surface: PdfReaderSurface(),
          shouldNavigate: false,
        ),
        isFalse,
      );
      expect(
        target.applyTo(
          surface: PdfReaderSurface(),
          shouldNavigate: true,
        ),
        isFalse,
      );
    });

    test('pdfPageIndex／pdfRect 皆存在時回傳 true', () {
      const target = ReaderJumpTarget(
        pdfPageIndex: 3,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      );

      expect(
        target.applyTo(
          surface: PdfReaderSurface(),
          shouldNavigate: false,
        ),
        isTrue,
      );
      expect(
        target.applyTo(
          surface: PdfReaderSurface(),
          shouldNavigate: true,
        ),
        isTrue,
      );
    });
  });

  group('applyTo：Foliate 格式', () {
    test('cfi 為 null 時，不論 shouldNavigate 為何皆回傳 false', () {
      const target = ReaderJumpTarget();

      expect(
        target.applyTo(
          surface: FoliateReaderSurface(),
          shouldNavigate: false,
        ),
        isFalse,
      );
      expect(
        target.applyTo(
          surface: FoliateReaderSurface(),
          shouldNavigate: true,
        ),
        isFalse,
      );
    });

    test('cfi 存在時回傳 true（各 Foliate 格式共用同一個 adapter；格式分派由 ReaderScreen 建立 surface 時負責）', () {
      const target = ReaderJumpTarget(cfi: 'epubcfi(/6/4!/4/2)');

      expect(
        target.applyTo(
          surface: FoliateReaderSurface(),
          shouldNavigate: false,
        ),
        isTrue,
      );
    });
  });

  group('applyTo：指令序列（FakeReaderSurface）', () {
    const target = ReaderJumpTarget(
      pdfPageIndex: 3,
      pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
    );

    test('shouldNavigate 為 true：先導覽、再疊暫態高亮，回傳 surface 的高亮結果', () {
      final surface = FakeReaderSurface.pdf(showsTransientHighlight: true);

      final shown = target.applyTo(surface: surface, shouldNavigate: true);

      expect(surface.calls, ['jumpTo', 'showTransientHighlight']);
      expect(shown, isTrue);
    });

    test('shouldNavigate 為 false：只疊暫態高亮、不導覽', () {
      final surface = FakeReaderSurface.pdf(showsTransientHighlight: false);

      final shown = target.applyTo(surface: surface, shouldNavigate: false);

      expect(surface.calls, ['showTransientHighlight']);
      expect(shown, isFalse);
    });
  });

  group('applyTo：不支援的格式', () {
    test('NoopReaderSurface（BookFormat.unknown）不論 shouldNavigate 為何皆回傳 false', () {
      const target = ReaderJumpTarget(
        cfi: 'epubcfi(/6/4!/4/2)',
        pdfPageIndex: 3,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      );

      expect(
        target.applyTo(
          surface: const NoopReaderSurface(),
          shouldNavigate: false,
        ),
        isFalse,
      );
      expect(
        target.applyTo(
          surface: const NoopReaderSurface(),
          shouldNavigate: true,
        ),
        isFalse,
      );
    });
  });
}
