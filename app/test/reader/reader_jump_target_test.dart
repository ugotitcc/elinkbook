// app/test/reader/reader_jump_target_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/library_enums.dart';
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
}
