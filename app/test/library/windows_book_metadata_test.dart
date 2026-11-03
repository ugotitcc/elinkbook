// Windows 圖書詮釋資料提取分派與序列化單元測試（epic-66 Issue 2 Task 4）。
//
// 驗證 extractWindowsBookMetadata() 與 runSerialized() 的分派、錯誤包裝與序列化邏輯。

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:elinkbook/library/windows_book_metadata.dart';

void main() {
  group('extractWindowsBookMetadata 分派與錯誤處理', () {
    test('format 為 epub 時呼叫 epubReader 並原樣回傳其結果', () async {
      var called = false;
      final expectedMap = <String, Object?>{
        'title': '測試書名',
        'author': '測試作者',
        'identifier': 'urn:uuid:test',
        'isFixedLayout': false,
        'coverBytes': Uint8List.fromList([1, 2, 3]),
      };

      final result = await extractWindowsBookMetadata(
        r'C:\books\sample.epub',
        'epub',
        epubReader: (path) async {
          called = true;
          expect(path, r'C:\books\sample.epub');
          return expectedMap;
        },
      );

      expect(called, isTrue);
      expect(result, equals(expectedMap));
    });

    test('format 為 pdf 時回傳包含 title/author 為 null 及 coverBytes 的 map', () async {
      var called = false;
      final dummyPng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

      final result = await extractWindowsBookMetadata(
        r'C:\books\sample.pdf',
        'pdf',
        pdfRenderer: (path) async {
          called = true;
          expect(path, r'C:\books\sample.pdf');
          return dummyPng;
        },
      );

      expect(called, isTrue);
      expect(result, {
        'title': null,
        'author': null,
        'coverBytes': dummyPng,
      });
    });

    test('format 為 pdf 且 pdfRenderer 回傳 null 時丟出 PlatformException(code: extraction_failed)', () async {
      expect(
        () => extractWindowsBookMetadata(
          r'C:\books\empty.pdf',
          'pdf',
          pdfRenderer: (_) async => null,
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'extraction_failed',
          ),
        ),
      );
    });

    test('format 為 txt、cbz 時回傳 null，且兩個注入函式都未被呼叫', () async {
      var epubCalled = false;
      var pdfCalled = false;

      final txtResult = await extractWindowsBookMetadata(
        r'C:\books\test.txt',
        'txt',
        epubReader: (_) async {
          epubCalled = true;
          return {};
        },
        pdfRenderer: (_) async {
          pdfCalled = true;
          return Uint8List(0);
        },
      );
      expect(txtResult, isNull);
      expect(epubCalled, isFalse);
      expect(pdfCalled, isFalse);

      final cbzResult = await extractWindowsBookMetadata(
        r'C:\books\test.cbz',
        'cbz',
        epubReader: (_) async {
          epubCalled = true;
          return {};
        },
        pdfRenderer: (_) async {
          pdfCalled = true;
          return Uint8List(0);
        },
      );
      expect(cbzResult, isNull);
      expect(epubCalled, isFalse);
      expect(pdfCalled, isFalse);
    });

    test('epubReader 丟 StateError、pdfRenderer 丟 Exception 時被包成 PlatformException', () async {
      expect(
        () => extractWindowsBookMetadata(
          r'C:\books\corrupt.epub',
          'epub',
          epubReader: (_) async => throw StateError('corrupted epub'),
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'extraction_failed',
          ),
        ),
      );

      expect(
        () => extractWindowsBookMetadata(
          r'C:\books\corrupt.pdf',
          'pdf',
          pdfRenderer: (_) async => throw Exception('corrupted pdf'),
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'extraction_failed',
          ),
        ),
      );
    });

    test('uri 含 :// 時丟 PlatformException（Windows 只收本機路徑）', () async {
      expect(
        () => extractWindowsBookMetadata(
          'content://media/external/file/1234',
          'epub',
          epubReader: (_) async => {},
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'extraction_failed',
          ),
        ),
      );

      expect(
        () => extractWindowsBookMetadata(
          'file:///C:/books/test.pdf',
          'pdf',
          pdfRenderer: (_) async => Uint8List(0),
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'extraction_failed',
          ),
        ),
      );
    });
  });

  group('runSerialized 序列化調度', () {
    test('同時啟動兩個任務時依序執行，前一個失敗不影響下一個', () async {
      final task1Started = Completer<void>();
      final task1CanFinish = Completer<void>();
      var task2Started = false;

      final future1 = runSerialized(() async {
        task1Started.complete();
        await task1CanFinish.future;
        throw StateError('task1 failed');
      });

      final future2 = runSerialized(() async {
        task2Started = true;
        return 'task2 ok';
      });

      await task1Started.future;
      expect(task2Started, isFalse, reason: 'task1 尚未完成前，task2 不應開始');

      task1CanFinish.complete();

      await expectLater(future1, throwsA(isA<StateError>()));
      final result2 = await future2;
      expect(result2, 'task2 ok');
      expect(task2Started, isTrue);
    });

    test('同時呼叫兩次 extractWindowsBookMetadata 時，第二個 epubReader 在第一個完成前不開始', () async {
      final epub1Started = Completer<void>();
      final epub1CanFinish = Completer<void>();
      var epub2Started = false;

      final f1 = extractWindowsBookMetadata(
        r'C:\books\a.epub',
        'epub',
        epubReader: (_) async {
          epub1Started.complete();
          await epub1CanFinish.future;
          return {'title': 'a'};
        },
      );

      final f2 = extractWindowsBookMetadata(
        r'C:\books\b.epub',
        'epub',
        epubReader: (_) async {
          epub2Started = true;
          return {'title': 'b'};
        },
      );

      await epub1Started.future;
      expect(epub2Started, isFalse, reason: '第一次解析未完成時，第二次解析不應開始');

      epub1CanFinish.complete();

      final res1 = await f1;
      final res2 = await f2;
      expect(res1?['title'], 'a');
      expect(res2?['title'], 'b');
      expect(epub2Started, isTrue);
    });
  });
}
