import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/support/book_import_picker_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';

import '../../support/fake_book_import_service.dart';

Book _testBook(String id) {
  final now = DateTime(2026, 1, 1);
  return Book(
    id: id,
    title: '書 $id',
    format: BookFileFormat.epub,
    filePath: 'content://example/$id',
    source: BookSource.local,
    createTime: now,
    lastReadTime: now,
  );
}

void main() {
  const filePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
  );
  const folderPickerChannel = MethodChannel('elinkbook/folder_picker');

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, null);
  });

  group('pickAndImportFiles', () {
    test('使用者取消選擇時回傳 null，不呼叫 importFiles', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async => null);
      final importService = FakeBookImportService();

      final result = await pickAndImportFiles(importService);

      expect(result, isNull);
      expect(importService.lastImportCall, isNull);
    });

    test('檔案清單為空時回傳 null，不呼叫 importFiles', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async => []);
      final importService = FakeBookImportService();

      final result = await pickAndImportFiles(importService);

      expect(result, isNull);
      expect(importService.lastImportCall, isNull);
    });

    test('選取檔案但全部 identifier 為 null 時回傳 null，不呼叫 importFiles', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async {
            if (call.method == 'custom') {
              return [
                {
                  'name': 'invalid.epub',
                  'path': '/tmp/invalid.epub',
                  'size': 100,
                  'identifier': null,
                },
              ];
            }
            return null;
          });
      final importService = FakeBookImportService();

      final result = await pickAndImportFiles(importService);

      expect(result, isNull);
      expect(importService.lastImportCall, isNull);
    });

    test('選取檔案成功時過濾掉 null identifier 並保持 displayName 與 uri 對應', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async {
            if (call.method == 'custom') {
              return [
                {
                  'name': 'book1.epub',
                  'path': '/tmp/book1.epub',
                  'size': 100,
                  'identifier': 'content://example/book1.epub',
                },
                {
                  'name': 'null_id.pdf',
                  'path': '/tmp/null_id.pdf',
                  'size': 100,
                  'identifier': null,
                },
                {
                  'name': 'book2.epub',
                  'path': '/tmp/book2.epub',
                  'size': 200,
                  'identifier': 'content://example/book2.epub',
                },
              ];
            }
            return null;
          });
      final importService = FakeBookImportService();

      final result = await pickAndImportFiles(importService);

      expect(result, isNotNull);
      expect(importService.lastImportCall, isNotNull);
      expect(importService.lastImportCall!.uris, [
        'content://example/book1.epub',
        'content://example/book2.epub',
      ]);
    });

    test('平台例外（PlatformException）不外拋，優雅回傳 null（審查報告 I-2 回歸測試）', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async {
            throw PlatformException(code: 'read_external_storage_denied');
          });
      final importService = FakeBookImportService();

      final result = await pickAndImportFiles(importService);

      expect(result, isNull);
    });
  });

  group('pickAndImportFolder', () {
    test('使用者取消選擇資料夾時回傳 null，且不呼叫 confirmAutoGroup', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(folderPickerChannel, (call) async => null);
      final importService = FakeBookImportService();
      var confirmCalled = false;

      final result = await pickAndImportFolder(
        importService,
        confirmAutoGroup: () async {
          confirmCalled = true;
          return true;
        },
      );

      expect(result, isNull);
      expect(confirmCalled, isFalse);
      expect(importService.lastImportFolderUri, isNull);
    });

    test('取消自動分類確認對話框時回傳 null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(folderPickerChannel, (call) async {
            if (call.method == 'pickFolder') return 'content://example/folder';
            return null;
          });
      final importService = FakeBookImportService();

      final result = await pickAndImportFolder(
        importService,
        confirmAutoGroup: () async => null,
      );

      expect(result, isNull);
      expect(importService.lastImportFolderUri, isNull);
    });

    test('確認自動分類後呼叫 importFolder(autoGroupByFolderName: true)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(folderPickerChannel, (call) async {
            if (call.method == 'pickFolder') return 'content://example/folder';
            return null;
          });
      final importService = FakeBookImportService();

      final result = await pickAndImportFolder(
        importService,
        confirmAutoGroup: () async => true,
      );

      expect(result, isNotNull);
      expect(importService.lastImportFolderUri, 'content://example/folder');
      expect(importService.lastAutoGroupByFolderName, isTrue);
    });

    test('取消勾選自動分類後呼叫 importFolder(autoGroupByFolderName: false)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(folderPickerChannel, (call) async {
            if (call.method == 'pickFolder') return 'content://example/folder';
            return null;
          });
      final importService = FakeBookImportService();

      final result = await pickAndImportFolder(
        importService,
        confirmAutoGroup: () async => false,
      );

      expect(result, isNotNull);
      expect(importService.lastImportFolderUri, 'content://example/folder');
      expect(importService.lastAutoGroupByFolderName, isFalse);
    });

    test('MethodChannel 拋例外不外拋，優雅回傳 null（審查報告 I-2 回歸測試）', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(folderPickerChannel, (call) async {
            throw PlatformException(code: 'pick_folder_failed');
          });
      final importService = FakeBookImportService();

      final result = await pickAndImportFolder(
        importService,
        confirmAutoGroup: () async => true,
      );

      expect(result, isNull);
    });
  });

  group('confirmAutoGroupByFolderName', () {
    testWidgets('預設勾選，點擊匯入回傳 true', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await confirmAutoGroupByFolderName(context);
                },
                child: const Text('打開對話框'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打開對話框'));
      await tester.pumpAndSettle();

      expect(find.text('匯入資料夾'), findsOneWidget);
      expect(find.text('依資料夾名稱自動建立分類'), findsOneWidget);

      await tester.tap(find.byKey(const Key('library_import_folder_confirm')));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('取消勾選後點擊匯入回傳 false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await confirmAutoGroupByFolderName(context);
                },
                child: const Text('打開對話框'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打開對話框'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('library_import_folder_auto_group_checkbox')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('library_import_folder_confirm')));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('點擊取消回傳 null', (tester) async {
      bool? result = true;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await confirmAutoGroupByFolderName(context);
                },
                child: const Text('打開對話框'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打開對話框'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });

  group('showImportResultSnackBar', () {
    testWidgets('failure 不為 null：只顯示資料夾讀取失敗訊息（epic-54 Issue 3）', (tester) async {
      for (final failure in ImportFailure.values) {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showImportResultSnackBar(
                    context,
                    ImportResult(
                      importedBooks: const [],
                      failure: failure,
                    ),
                  ),
                  child: const Text('Show SnackBar'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show SnackBar'));
        await tester.pump();

        expect(find.text('無法讀取這個資料夾，請確認已授權存取後再試一次'), findsOneWidget,
            reason: '$failure');
        expect(find.textContaining('已匯入'), findsNothing);
        expect(find.textContaining('已跳過'), findsNothing);

        ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
            .clearSnackBars();
        await tester.pumpAndSettle();
      }
    });

    // 「failure 為 null 且兩者皆為 0 不顯示」不另加測試：既有的
    // 『兩者皆為 0 時不顯示任何 SnackBar』傳入的 ImportResult 預設 failure 即為
    // null，已涵蓋（計畫審查 I-4）。
    testWidgets('兩者皆為 0 時不顯示任何 SnackBar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showImportResultSnackBar(
                    context,
                    const ImportResult(
                      importedBooks: [],
                      skippedDuplicateCount: 0,
                    ),
                  );
                },
                child: const Text('Show SnackBar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show SnackBar'));
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('僅有成功匯入時顯示「已匯入 N 本書」', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showImportResultSnackBar(
                    context,
                    ImportResult(
                      importedBooks: [_testBook('1'), _testBook('2')],
                      skippedDuplicateCount: 0,
                    ),
                  );
                },
                child: const Text('Show SnackBar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show SnackBar'));
      await tester.pump();

      expect(find.text('已匯入 2 本書'), findsOneWidget);
    });

    testWidgets('有成功且有跳過時顯示合併訊息', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showImportResultSnackBar(
                    context,
                    ImportResult(
                      importedBooks: [_testBook('1')],
                      skippedDuplicateCount: 3,
                    ),
                  );
                },
                child: const Text('Show SnackBar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show SnackBar'));
      await tester.pump();

      expect(find.text('已匯入 1 本，3 本已存在，已跳過'), findsOneWidget);
    });

    testWidgets('僅有跳過時顯示「N 本已存在，已跳過」', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showImportResultSnackBar(
                    context,
                    const ImportResult(
                      importedBooks: [],
                      skippedDuplicateCount: 5,
                    ),
                  );
                },
                child: const Text('Show SnackBar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show SnackBar'));
      await tester.pump();

      expect(find.text('5 本已存在，已跳過'), findsOneWidget);
    });
  });

  group('英文介面下的在地化驗證', () {
    testWidgets('confirmAutoGroupByFolderName 顯示英文標題與按鈕', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await confirmAutoGroupByFolderName(context);
                },
                child: const Text('open dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Import Folder'), findsOneWidget);
      expect(
        find.text('Automatically create category by folder name'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('library_import_folder_confirm')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('showImportResultSnackBar 匯入/跳過本數各自為 1 與多本時單複數皆正確', (
      tester,
    ) async {
      Future<void> pumpAndShow(ImportResult result) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showImportResultSnackBar(context, result),
                  child: const Text('Show SnackBar'),
                ),
              ),
            ),
          ),
        );
        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold)),
        ).clearSnackBars();
        await tester.pump();
        await tester.tap(find.text('Show SnackBar'));
        await tester.pump();
      }

      await pumpAndShow(
        ImportResult(importedBooks: [_testBook('1')], skippedDuplicateCount: 0),
      );
      expect(find.text('Imported 1 book'), findsOneWidget);

      await pumpAndShow(
        ImportResult(
          importedBooks: [_testBook('1'), _testBook('2')],
          skippedDuplicateCount: 0,
        ),
      );
      expect(find.text('Imported 2 books'), findsOneWidget);

      await pumpAndShow(
        const ImportResult(importedBooks: [], skippedDuplicateCount: 1),
      );
      expect(find.text('1 already exists and was skipped'), findsOneWidget);

      await pumpAndShow(
        ImportResult(importedBooks: [_testBook('1')], skippedDuplicateCount: 3),
      );
      expect(
        find.text('Imported 1 book, 3 already exist and were skipped'),
        findsOneWidget,
      );
    });
  });
}
