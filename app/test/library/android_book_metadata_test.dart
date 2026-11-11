// Android 圖書詮釋資料派送單元測試（epic-66 Issue 12 Task 3）。

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/android_book_metadata.dart';
import 'package:elinkbook/library/library_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('extractAndroidBookMetadata 派送與例外處理', () {
    test('epub 走 foliate 且原生從未呼叫（不分大小寫）', () async {
      var foliateCalled = false;
      var nativeCalled = false;

      final result = await extractAndroidBookMetadata(
        'content://book/2',
        'EPUB',
        foliateReader: (uri) async {
          foliateCalled = true;
          expect(uri, 'content://book/2');
          return {'title': 'Foliate 書名', 'author': '作者 A'};
        },
        nativeReader: (uri, format) async {
          nativeCalled = true;
          return {'title': '原生書名'};
        },
      );

      expect(foliateCalled, isTrue);
      expect(nativeCalled, isFalse);
      expect(result?['title'], 'Foliate 書名');
      expect(result?['author'], '作者 A');
    });

    test('pdf 走原生通道，foliate 從未呼叫', () async {
      var foliateCalled = false;
      var nativeCalled = false;

      final result = await extractAndroidBookMetadata(
        'content://book/4',
        'pdf',
        foliateReader: (uri) async {
          foliateCalled = true;
          return {'title': 'Foliate 書名'};
        },
        nativeReader: (uri, format) async {
          nativeCalled = true;
          return {'title': 'PDF 封面'};
        },
      );

      expect(foliateCalled, isFalse);
      expect(nativeCalled, isTrue);
      expect(result?['title'], 'PDF 封面');
    });

    test('epub 探針丟 StateError 時包成 PlatformException（code 為 extraction_failed，不退回、不吞掉）', () async {
      var nativeCalled = false;

      await expectLater(
        () => extractAndroidBookMetadata(
          'content://book/5',
          'epub',
          foliateReader: (uri) async => throw StateError('foliate 失敗'),
          nativeReader: (uri, format) async {
            nativeCalled = true;
            return {'title': '原生書名'};
          },
        ),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'extraction_failed')
              .having((e) => e.message, 'message', contains('foliate 失敗')),
        ),
      );
      expect(nativeCalled, isFalse);
    });

    test('探針丟 TimeoutException 同樣被包裝為 extraction_failed', () async {
      await expectLater(
        () => extractAndroidBookMetadata(
          'content://book/timeout',
          'epub',
          foliateReader: (uri) async =>
              throw TimeoutException('probe timeout'),
        ),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'extraction_failed')
              .having((e) => e.message, 'message', contains('probe timeout')),
        ),
      );
    });

    test('探針丟 PlatformException 時原樣往外拋', () async {
      await expectLater(
        () => extractAndroidBookMetadata(
          'content://book/platform',
          'epub',
          foliateReader: (uri) async => throw PlatformException(
            code: 'custom_code',
            message: '自訂錯誤',
          ),
        ),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'custom_code')
              .having((e) => e.message, 'message', '自訂錯誤'),
        ),
      );
    });

    test('epub 經過 runSerialized', () async {
      final firstStarted = Completer<void>();
      final firstBlocker = Completer<void>();
      var firstRunning = false;
      var secondStartedWhileFirstRunning = false;

      final future1 = extractAndroidBookMetadata(
        'book1.epub',
        'epub',
        foliateReader: (uri) async {
          firstRunning = true;
          firstStarted.complete();
          await firstBlocker.future;
          firstRunning = false;
          return {'title': '書 1'};
        },
      );

      await firstStarted.future;

      final future2 = extractAndroidBookMetadata(
        'book2.epub',
        'epub',
        foliateReader: (uri) async {
          if (firstRunning) {
            secondStartedWhileFirstRunning = true;
          }
          return {'title': '書 2'};
        },
      );

      // 解開第一個任務
      firstBlocker.complete();

      final res1 = await future1;
      final res2 = await future2;

      expect(res1?['title'], '書 1');
      expect(res2?['title'], '書 2');
      expect(secondStartedWhileFirstRunning, isFalse);
    });

    test('預設原生呼叫引數為 uri 與 format', () async {
      MethodCall? interceptedCall;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kBookMetadataChannel, (call) async {
        interceptedCall = call;
        if (call.method == 'extractMetadata') {
          return <String, Object?>{
            'title': '通道回傳書名',
            'author': '通道回傳作者',
          };
        }
        return null;
      });

      try {
        final result = await extractAndroidBookMetadata(
          'content://sample/book.pdf',
          'pdf',
        );

        expect(interceptedCall, isNotNull);
        expect(interceptedCall!.method, 'extractMetadata');
        final args = interceptedCall!.arguments as Map<dynamic, dynamic>;
        expect(args['uri'], 'content://sample/book.pdf');
        expect(args['format'], 'pdf');
        expect(args.containsKey('path'), isFalse);
        expect(result?['title'], '通道回傳書名');
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(kBookMetadataChannel, null);
      }
    });
  });

  group('detectAndroidEpubLayout', () {
    test('detectAndroidEpubLayout 回傳探針的 isFixedLayout（true 與缺欄位預設 false）', () async {
      final fixed = await detectAndroidEpubLayout(
        'content://book/fxl.epub',
        foliateReader: (uri) async {
          expect(uri, 'content://book/fxl.epub');
          return {'isFixedLayout': true};
        },
      );
      expect(fixed, isTrue);

      final reflowable = await detectAndroidEpubLayout(
        'content://book/reflowable.epub',
        foliateReader: (uri) async => {'title': '無版面欄位'},
      );
      expect(reflowable, isFalse);
    });

    test('探針丟 StateError 時包成 PlatformException（code 為 detection_failed）', () async {
      await expectLater(
        () => detectAndroidEpubLayout(
          'content://book/broken.epub',
          foliateReader: (uri) async => throw StateError('探針損毀'),
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'detection_failed',
          ),
        ),
      );
    });

    test('經過 runSerialized', () async {
      final firstStarted = Completer<void>();
      final firstBlocker = Completer<void>();
      var firstRunning = false;
      var secondStartedWhileFirstRunning = false;

      final future1 = detectAndroidEpubLayout(
        'book1.epub',
        foliateReader: (uri) async {
          firstRunning = true;
          firstStarted.complete();
          await firstBlocker.future;
          firstRunning = false;
          return {'isFixedLayout': true};
        },
      );

      await firstStarted.future;

      final future2 = detectAndroidEpubLayout(
        'book2.epub',
        foliateReader: (uri) async {
          if (firstRunning) {
            secondStartedWhileFirstRunning = true;
          }
          return {'isFixedLayout': false};
        },
      );

      firstBlocker.complete();

      final res1 = await future1;
      final res2 = await future2;

      expect(res1, isTrue);
      expect(res2, isFalse);
      expect(secondStartedWhileFirstRunning, isFalse);
    });
  });
}
