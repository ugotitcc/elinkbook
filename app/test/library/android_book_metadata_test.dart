// Android 圖書詮釋資料派送單元測試（epic-66 Issue 12 Task 3）。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/android_book_metadata.dart';
import 'package:elinkbook/library/library_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('extractAndroidBookMetadata 派送與退路', () {
    test('kAndroidMetadataFoliateFirst 預設值為 true', () {
      expect(kAndroidMetadataFoliateFirst, isTrue);
    });

    test('未帶 foliateFirst 參數時預設走 foliateReader，Readium 從未呼叫', () async {
      var foliateCalled = false;
      var readiumCalled = false;

      final result = await extractAndroidBookMetadata(
        'content://book/default',
        'epub',
        foliateReader: (uri) async {
          foliateCalled = true;
          return {'title': '預設 Foliate 書名'};
        },
        readiumReader: (uri, format) async {
          readiumCalled = true;
          return {'title': 'Readium 書名'};
        },
      );

      expect(foliateCalled, isTrue);
      expect(readiumCalled, isFalse);
      expect(result?['title'], '預設 Foliate 書名');
    });

    test('foliateFirst 為 false 時只呼叫 Readium，foliate 從未呼叫', () async {
      var foliateCalled = false;
      var readiumCalled = false;

      final result = await extractAndroidBookMetadata(
        'content://book/1',
        'epub',
        foliateFirst: false,
        foliateReader: (uri) async {
          foliateCalled = true;
          return {'title': 'Foliate 書名'};
        },
        readiumReader: (uri, format) async {
          readiumCalled = true;
          return {'title': 'Readium 書名'};
        },
      );

      expect(foliateCalled, isFalse);
      expect(readiumCalled, isTrue);
      expect(result?['title'], 'Readium 書名');
    });

    test('foliateFirst 為 true 且為 epub、foliate 成功時回傳其結果，Readium 從未呼叫', () async {
      var foliateCalled = false;
      var readiumCalled = false;

      final result = await extractAndroidBookMetadata(
        'content://book/2',
        'epub',
        foliateFirst: true,
        foliateReader: (uri) async {
          foliateCalled = true;
          return {'title': 'Foliate 書名', 'author': '作者 A'};
        },
        readiumReader: (uri, format) async {
          readiumCalled = true;
          return {'title': 'Readium 書名'};
        },
      );

      expect(foliateCalled, isTrue);
      expect(readiumCalled, isFalse);
      expect(result?['title'], 'Foliate 書名');
      expect(result?['author'], '作者 A');
    });

    test('foliateFirst 為 true 但 foliate 丟例外時退回 Readium 並記錄日誌', () async {
      var foliateCalled = false;
      var readiumCalled = false;
      final logs = <String>[];

      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      try {
        final result = await extractAndroidBookMetadata(
          'content://book/3',
          'epub',
          foliateFirst: true,
          foliateReader: (uri) async {
            foliateCalled = true;
            throw StateError('探針解析崩潰');
          },
          readiumReader: (uri, format) async {
            readiumCalled = true;
            return {'title': 'Readium 備用書名'};
          },
        );

        expect(foliateCalled, isTrue);
        expect(readiumCalled, isTrue);
        expect(result?['title'], 'Readium 備用書名');
        expect(logs.any((l) => l.contains('foliate-js metadata 提取失敗，退回 Readium')), isTrue);
      } finally {
        debugPrint = originalDebugPrint;
      }
    });

    test('foliateFirst 為 true 但格式為 pdf 時只呼叫 Readium', () async {
      var foliateCalled = false;
      var readiumCalled = false;

      final result = await extractAndroidBookMetadata(
        'content://book/4',
        'pdf',
        foliateFirst: true,
        foliateReader: (uri) async {
          foliateCalled = true;
          return {'title': 'Foliate 書名'};
        },
        readiumReader: (uri, format) async {
          readiumCalled = true;
          return {'title': 'PDF 封面'};
        },
      );

      expect(foliateCalled, isFalse);
      expect(readiumCalled, isTrue);
      expect(result?['title'], 'PDF 封面');
    });

    test('兩邊都失敗時把 Readium 的例外往外拋而不吞掉', () async {
      expect(
        () => extractAndroidBookMetadata(
          'content://book/5',
          'epub',
          foliateFirst: true,
          foliateReader: (uri) async => throw StateError('foliate 失敗'),
          readiumReader: (uri, format) async => throw PlatformException(
            code: 'readium_failed',
            message: 'Readium 解析也失敗',
          ),
        ),
        throwsA(isA<PlatformException>()),
      );
    });

    test('兩次並行呼叫 foliate 路徑時依序執行', () async {
      final firstStarted = Completer<void>();
      final firstBlocker = Completer<void>();
      var firstRunning = false;
      var secondStartedWhileFirstRunning = false;

      final future1 = extractAndroidBookMetadata(
        'book1.epub',
        'epub',
        foliateFirst: true,
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
        foliateFirst: true,
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

    test('預設 Readium 呼叫原生通道時引數為 uri 與 format', () async {
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
          'content://sample/book.epub',
          'epub',
          foliateFirst: false, // 走預設 readiumReader
        );

        expect(interceptedCall, isNotNull);
        expect(interceptedCall!.method, 'extractMetadata');
        final args = interceptedCall!.arguments as Map<dynamic, dynamic>;
        expect(args['uri'], 'content://sample/book.epub');
        expect(args['format'], 'epub');
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
