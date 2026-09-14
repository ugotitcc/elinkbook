// app/test/reader/reader_jump_target_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/reader/book_format.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/pdf_reader_view.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_jump_target.dart';

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

  // applyTo() 底層的 PdfReaderView/FoliateReaderView 靜態 helper 對「key
  // 尚未掛載任何 State」的情況皆為靜默忽略（見兩者各自文件註解），不拋
  // 例外——這裡刻意使用未掛載的空白 GlobalKey，讓測試只聚焦驗證 applyTo()
  // 自己的分派與回傳值邏輯，不需要真正渲染 PdfReaderView/FoliateReaderView
  // （那部分的副作用是否真的觸發，由 reader_screen_test.dart 既有的全螢幕
  // 整合測試把關，見本計畫 Global Constraints 的邊界權衡說明）。
  final pdfKey = GlobalKey<State<PdfReaderView>>();
  final foliateKey = GlobalKey<State<FoliateReaderView>>();

  group('applyTo：PDF 格式', () {
    test('pdfPageIndex 為 null 時，不論 shouldNavigate 為何皆回傳 false', () {
      const target = ReaderJumpTarget(
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      );

      expect(
        target.applyTo(
          format: BookFormat.pdf,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: false,
        ),
        isFalse,
      );
      expect(
        target.applyTo(
          format: BookFormat.pdf,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
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
          format: BookFormat.pdf,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: false,
        ),
        isFalse,
      );
      expect(
        target.applyTo(
          format: BookFormat.pdf,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
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
          format: BookFormat.pdf,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: false,
        ),
        isTrue,
      );
      expect(
        target.applyTo(
          format: BookFormat.pdf,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
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
          format: BookFormat.epub,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: false,
        ),
        isFalse,
      );
      expect(
        target.applyTo(
          format: BookFormat.epub,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: true,
        ),
        isFalse,
      );
    });

    test('cfi 存在時，所有 Foliate 格式（epub/azw3/cbz/txt/md）皆回傳 true'
        '（防止實作誤寫成 format == BookFormat.epub 而非 isFoliateFormat(format)）',
        () {
      const target = ReaderJumpTarget(cfi: 'epubcfi(/6/4!/4/2)');

      for (final format in [
        BookFormat.epub,
        BookFormat.azw3,
        BookFormat.cbz,
        BookFormat.txt,
        BookFormat.md,
      ]) {
        expect(
          target.applyTo(
            format: format,
            pdfKey: pdfKey,
            foliateKey: foliateKey,
            shouldNavigate: false,
          ),
          isTrue,
          reason: '格式 $format 應被視為 Foliate 格式',
        );
      }
    });
  });

  group('applyTo：不支援的格式', () {
    test('BookFormat.unknown 不論 shouldNavigate 為何皆回傳 false', () {
      const target = ReaderJumpTarget(
        cfi: 'epubcfi(/6/4!/4/2)',
        pdfPageIndex: 3,
        pdfRect: PercentRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
      );

      expect(
        target.applyTo(
          format: BookFormat.unknown,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: false,
        ),
        isFalse,
      );
      expect(
        target.applyTo(
          format: BookFormat.unknown,
          pdfKey: pdfKey,
          foliateKey: foliateKey,
          shouldNavigate: true,
        ),
        isFalse,
      );
    });
  });
}
