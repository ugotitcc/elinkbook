// 書籍格式能力（Book Format Capabilities）測試。
//
// 這個 module 取代過去散在 6 份的副檔名／MIME 判斷，以及兩個平行 enum
// （`BookFormat`／`BookFileFormat`）。
import 'package:elinkbook/library/book_file_format.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectBookFileFormat（副檔名）', () {
    test('六種格式皆可辨識，不分大小寫', () {
      expect(detectBookFileFormat('a.epub'), BookFileFormat.epub);
      expect(detectBookFileFormat('a.PDF'), BookFileFormat.pdf);
      expect(detectBookFileFormat('a.txt'), BookFileFormat.txt);
      expect(detectBookFileFormat('a.Azw3'), BookFileFormat.azw3);
      expect(detectBookFileFormat('a.cbz'), BookFileFormat.cbz);
      expect(detectBookFileFormat('a.md'), BookFileFormat.md);
    });

    test('只看最後一段路徑，並先做 percent-decode（content:// 常見）', () {
      expect(detectBookFileFormat('content://x/tree/doc%2Fmy%20book.epub'),
          BookFileFormat.epub);
      expect(detectBookFileFormat(r'C:\books\novel.txt'), BookFileFormat.txt);
      expect(detectBookFileFormat('file:///path/to/comic.cbz'),
          BookFileFormat.cbz);
    });

    test('含不合法 percent 序列的原始檔名不拋例外', () {
      expect(detectBookFileFormat('100%.epub'), BookFileFormat.epub);
    });

    test('不支援／無副檔名／空字串回 null；.mdx 不誤判為 md', () {
      expect(detectBookFileFormat('a.mobi'), isNull);
      expect(detectBookFileFormat('a.mdx'), isNull);
      expect(detectBookFileFormat('content://opaque/12345'), isNull);
      expect(detectBookFileFormat(''), isNull);
    });
  });

  group('detectImportFileFormat（epic-67 Issue 3）', () {
    test('displayName 優先、URI 退路、兩者皆無法辨識回 null', () {
      // displayName 優先
      expect(detectImportFileFormat('content://opaque/12345', 'mybook.epub'),
          BookFileFormat.epub);
      expect(detectImportFileFormat('content://opaque/book.pdf', 'override.azw3'),
          BookFileFormat.azw3);

      // URI 退路
      expect(detectImportFileFormat('content://storage/doc.pdf', null),
          BookFileFormat.pdf);
      expect(detectImportFileFormat('/storage/emulated/0/novel.txt', null),
          BookFileFormat.txt);
      expect(detectImportFileFormat('file:///path/to/comic.cbz', ''),
          BookFileFormat.cbz);
      expect(detectImportFileFormat('/notes/readme.md', null), BookFileFormat.md);

      // 兩者皆無法辨識
      expect(detectImportFileFormat('content://opaque/12345', null), isNull);
      expect(detectImportFileFormat('content://opaque/12345', 'no_extension'),
          isNull);
      expect(
          detectImportFileFormat('content://opaque/unknown.xyz', 'test.unknown'),
          isNull);
    });
  });

  group('detectBookFileFormatByNameAndMime（雲端／OPDS）', () {
    test('副檔名優先於 MIME：notes.md＋text/plain 是 md，不是 txt', () {
      expect(
          detectBookFileFormatByNameAndMime('notes.md', 'text/plain'),
          BookFileFormat.md);
      expect(
          detectBookFileFormatByNameAndMime('a.epub', 'text/plain'),
          BookFileFormat.epub);
    });

    test('副檔名認不出才看 MIME：epub／pdf／txt', () {
      expect(detectBookFileFormatByNameAndMime('book', 'application/epub+zip'),
          BookFileFormat.epub);
      expect(detectBookFileFormatByNameAndMime('book', 'application/pdf'),
          BookFileFormat.pdf);
      expect(detectBookFileFormatByNameAndMime('book', 'text/plain'),
          BookFileFormat.txt);
    });

    test('OPDS 常見的 azw3／cbz／md MIME 也認得', () {
      expect(
          detectBookFileFormatByNameAndMime('x', 'application/x-mobipocket-ebook'),
          BookFileFormat.azw3);
      expect(
          detectBookFileFormatByNameAndMime('x', 'application/vnd.amazon.ebook'),
          BookFileFormat.azw3);
      expect(
          detectBookFileFormatByNameAndMime('x', 'application/vnd.comicbook+zip'),
          BookFileFormat.cbz);
      expect(detectBookFileFormatByNameAndMime('x', 'application/x-cbz'),
          BookFileFormat.cbz);
      expect(detectBookFileFormatByNameAndMime('x', 'text/markdown'),
          BookFileFormat.md);
    });

    test('Drive 的 .txt 即使 MIME 是 octet-stream 也判為 txt', () {
      expect(
          detectBookFileFormatByNameAndMime(
              'novel.txt', 'application/octet-stream'),
          BookFileFormat.txt);
    });

    test('MIME 為 null、或兩者都認不出時回 null', () {
      expect(detectBookFileFormatByNameAndMime('book.epub', null),
          BookFileFormat.epub);
      expect(detectBookFileFormatByNameAndMime('photo.jpg', 'image/jpeg'),
          isNull);
      expect(detectBookFileFormatByNameAndMime('notes.mdx', null), isNull);
    });
  });

  group('能力', () {
    test('engine：只有 PDF 走 pdf 引擎，其餘走 foliate', () {
      for (final f in BookFileFormat.values) {
        expect(f.engine,
            f == BookFileFormat.pdf ? BookEngine.pdf : BookEngine.foliate,
            reason: '$f');
      }
    });

    test('locatorKind：PDF 用頁碼，其餘用 CFI', () {
      for (final f in BookFileFormat.values) {
        expect(f.locatorKind,
            f == BookFileFormat.pdf ? LocatorKind.pdfPage : LocatorKind.cfi,
            reason: '$f');
      }
    });

    test('keepsOriginalSource：epub／pdf／azw3 為 true；txt／md／cbz 匯入時已合成或重建，為 false', () {
      expect(BookFileFormat.epub.keepsOriginalSource, isTrue);
      expect(BookFileFormat.pdf.keepsOriginalSource, isTrue);
      expect(BookFileFormat.azw3.keepsOriginalSource, isTrue);
      expect(BookFileFormat.txt.keepsOriginalSource, isFalse);
      expect(BookFileFormat.md.keepsOriginalSource, isFalse);
      expect(BookFileFormat.cbz.keepsOriginalSource, isFalse);
    });

    test('synthesizesEpub：只有 txt 與 md', () {
      expect(BookFileFormat.values.where((f) => f.synthesizesEpub).toSet(),
          {BookFileFormat.txt, BookFileFormat.md});
    });

    test('nullable 版 usesFoliate／isPdf：null（不支援）兩者皆 false', () {
      const BookFileFormat? none = null;
      expect(none.usesFoliate, isFalse);
      expect(none.isPdf, isFalse);
      expect(BookFileFormat.epub.usesFoliate, isTrue);
      expect(BookFileFormat.cbz.usesFoliate, isTrue);
      expect(BookFileFormat.pdf.usesFoliate, isFalse);
      expect(BookFileFormat.pdf.isPdf, isTrue);
    });
  });

  group('一致性：新增格式漏掉任何一處都會在這裡失敗', () {
    test('副檔名來回一致：detect(x.<fileExtension>) == 該格式', () {
      for (final f in BookFileFormat.values) {
        expect(detectBookFileFormat('x.${f.fileExtension}'), f, reason: '$f');
      }
    });

    test('kSupportedBookExtensions 恰為全部格式的副檔名', () {
      expect(kSupportedBookExtensions.toSet(),
          BookFileFormat.values.map((f) => f.fileExtension).toSet());
      expect(kSupportedBookExtensions.length, BookFileFormat.values.length,
          reason: '不重複');
    });

    test('持久化名稱不可改：fileExtension 與 enum 名稱一致（資料庫以 name 儲存）', () {
      for (final f in BookFileFormat.values) {
        expect(f.fileExtension, f.name);
      }
    });
  });
}
