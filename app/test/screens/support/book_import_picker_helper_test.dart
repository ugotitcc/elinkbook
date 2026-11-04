import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/book_update_models.dart';
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

    // epic-66 Issue 1 Task 8：過濾條件改為 `identifier ?? path`（Windows 的
    // file_picker 不回傳 identifier，見 PlatformFile.identifier 文件），因此
    // 「可過濾」的定義變成兩者皆為 null。
    test('選取檔案但 identifier 與 path 都是 null 時回傳 null，不呼叫 importFiles', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async {
            if (call.method == 'custom') {
              return [
                {
                  'name': 'invalid.epub',
                  'path': null,
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

    test('選檔器：identifier 為 null 時改用 path（epic-66 Issue 1 Task 8）', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async {
            if (call.method == 'custom') {
              return [
                {
                  'name': 'a.epub',
                  'path': 'C:/books/a.epub',
                  'size': 1,
                  'identifier': null,
                },
              ];
            }
            return null;
          });
      final importService = FakeBookImportService();

      final result = await pickAndImportFiles(importService);

      expect(result, isNotNull);
      expect(importService.lastImportCall, isNotNull);
      expect(importService.lastImportCall!.uris, ['C:/books/a.epub']);
      expect(importService.lastImportCall!.displayNames, ['a.epub']);
    });

    test('選檔器：兩者都有時優先用 identifier（Android 行為不變）', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async {
            if (call.method == 'custom') {
              return [
                {
                  'name': 'a.epub',
                  'path': '/data/user/0/app/cache/a.epub',
                  'size': 1,
                  'identifier': 'content://example/a.epub',
                },
              ];
            }
            return null;
          });
      final importService = FakeBookImportService();

      final result = await pickAndImportFiles(importService);

      expect(result, isNotNull);
      expect(importService.lastImportCall!.uris, ['content://example/a.epub']);
    });

    test('選取檔案成功時過濾掉無可用 URI 的檔案並保持 displayName 與 uri 對應', () async {
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
                  // epic-66 Issue 1 Task 8：identifier 為 null 但有 path 的
                  // 檔案改走 path（Windows 情境），仍須參與逐一對應。
                  'name': 'null_id.pdf',
                  'path': 'C:/books/null_id.pdf',
                  'size': 100,
                  'identifier': null,
                },
                {
                  'name': 'unusable.epub',
                  'path': null,
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
        'C:/books/null_id.pdf',
        'content://example/book2.epub',
      ]);
      expect(importService.lastImportCall!.displayNames, [
        'book1.epub',
        'null_id.pdf',
        'book2.epub',
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

  // epic-66 Issue 1 Task 8：單檔選擇器（book_import_picker_helper.dart:148）
  // 同樣改取 `identifier ?? path`。
  group('pickSingleBookFileViaFilePicker', () {
    test('單檔選取：identifier 為 null 時改用 path', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async {
            if (call.method == 'custom') {
              return [
                {
                  'name': 'a.epub',
                  'path': 'C:/books/a.epub',
                  'size': 1,
                  'identifier': null,
                },
              ];
            }
            return null;
          });

      final result = await pickSingleBookFileViaFilePicker(['epub']);

      expect(result, isNotNull);
      expect(result!.uri, 'C:/books/a.epub');
      expect(result.displayName, 'a.epub');
    });

    test('單檔選取：identifier 與 path 都是 null 時回傳 null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, (call) async {
            if (call.method == 'custom') {
              return [
                {
                  'name': 'a.epub',
                  'path': null,
                  'size': 1,
                  'identifier': null,
                },
              ];
            }
            return null;
          });

      final result = await pickSingleBookFileViaFilePicker(['epub']);

      expect(result, isNull);
    });
  });

  group('handleImportUpdateCandidates', () {
    BookUpdateCandidate makeCandidate({
      String sourceUri = 'file:///test/new.epub',
      String? displayName = 'new.epub',
      String? targetBookId = 'b1',
    }) {
      return BookUpdateCandidate(
        sourceUri: sourceUri,
        displayName: displayName,
        format: BookFileFormat.epub,
        confidence: UpdateConfidence.high,
        candidateBooks: [_testBook(targetBookId ?? 'b1')],
      );
    }

    testWidgets('無候選：不彈出任何對話框且 discardedCandidates 為空', (tester) async {
      final importService = FakeBookImportService();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => handleImportUpdateCandidates(
                  context,
                  importService,
                  const ImportResult(importedBooks: []),
                ),
                child: const Text('Handle'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Handle'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('book_update_apply')), findsNothing);
      expect(importService.discardedCandidates, isEmpty);
    });

    testWidgets('有候選且已掛載：彈出清單，按套用後顯示已更新 1 本 SnackBar', (tester) async {
      final importService = FakeBookImportService();
      final candidate = makeCandidate();
      importService.replaceResultsByBookId['b1'] = BookReplaceSuccess(_testBook('b1'));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => handleImportUpdateCandidates(
                  context,
                  importService,
                  ImportResult(
                    importedBooks: const [],
                    updateCandidates: [candidate],
                  ),
                ),
                child: const Text('Handle'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Handle'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('book_update_apply')), findsOneWidget);

      await tester.tap(find.byKey(const Key('book_update_apply')));
      await tester.pumpAndSettle();

      expect(find.text('已更新 1 本'), findsOneWidget);
    });

    testWidgets('並存：改選並存後套用顯示已並存 1 本；分別取代與並存顯示合併訊息', (tester) async {
      final importService = FakeBookImportService();
      final c0 = makeCandidate(sourceUri: 'file:///c0.epub', targetBookId: 'b0');
      final c1 = makeCandidate(sourceUri: 'file:///c1.epub', targetBookId: 'b1');
      importService.replaceResultsByBookId['b0'] = BookReplaceSuccess(_testBook('b0'));
      importService.importCandidateResult = _testBook('b1_coexist');

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => handleImportUpdateCandidates(
                  context,
                  importService,
                  ImportResult(
                    importedBooks: const [],
                    updateCandidates: [c0, c1],
                  ),
                ),
                child: const Text('Handle'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Handle'));
      await tester.pumpAndSettle();

      // 改選第 1 列為並存
      await tester.ensureVisible(find.byKey(const Key('book_update_option_coexist_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book_update_option_coexist_1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_update_apply')));
      await tester.pumpAndSettle();

      expect(find.text('已更新 1 本，已並存 1 本'), findsOneWidget);
    });

    testWidgets('部分失敗（審查 I-3）：2 筆取代成功、1 筆失敗顯示成功加失敗訊息', (tester) async {
      final importService = FakeBookImportService();
      final c0 = makeCandidate(sourceUri: 'file:///c0.epub', targetBookId: 'b0');
      final c1 = makeCandidate(sourceUri: 'file:///c1.epub', targetBookId: 'b1');
      final c2 = makeCandidate(sourceUri: 'file:///c2.epub', targetBookId: 'b2');

      importService.replaceResultsByBookId['b0'] = BookReplaceSuccess(_testBook('b0'));
      importService.replaceResultsByBookId['b1'] = BookReplaceSuccess(_testBook('b1'));
      importService.replaceResultsByBookId['b2'] =
          const BookReplaceFailure(BookReplaceFailureReason.writeFailed);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => handleImportUpdateCandidates(
                  context,
                  importService,
                  ImportResult(
                    importedBooks: const [],
                    updateCandidates: [c0, c1, c2],
                  ),
                ),
                child: const Text('Handle'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Handle'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_update_apply')));
      await tester.pumpAndSettle();

      expect(
        find.text('已更新 2 本；1 本更新失敗，書籍沒有任何變動'),
        findsOneWidget,
      );
    });

    testWidgets('全部失敗：只顯示失敗訊息', (tester) async {
      final importService = FakeBookImportService();
      final c0 = makeCandidate(sourceUri: 'file:///c0.epub', targetBookId: 'b0');

      importService.replaceResultsByBookId['b0'] =
          const BookReplaceFailure(BookReplaceFailureReason.writeFailed);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => handleImportUpdateCandidates(
                  context,
                  importService,
                  ImportResult(
                    importedBooks: const [],
                    updateCandidates: [c0],
                  ),
                ),
                child: const Text('Handle'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Handle'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_update_apply')));
      await tester.pumpAndSettle();

      expect(
        find.text('1 本更新失敗，書籍沒有任何變動'),
        findsOneWidget,
      );
    });

    testWidgets('isEinkMode: true 時對話框無過場動畫', (tester) async {
      final importService = FakeBookImportService();
      final candidate = makeCandidate();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => handleImportUpdateCandidates(
                  context,
                  importService,
                  ImportResult(
                    importedBooks: const [],
                    updateCandidates: [candidate],
                  ),
                  isEinkMode: true,
                ),
                child: const Text('Handle'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Handle'));
      await tester.pump(); // 一次 pump 即可找到

      expect(find.byKey(const Key('book_update_apply')), findsOneWidget);
    });

    testWidgets('全部跳過：不顯示任何 SnackBar', (tester) async {
      final importService = FakeBookImportService();
      final candidate = makeCandidate();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => handleImportUpdateCandidates(
                  context,
                  importService,
                  ImportResult(
                    importedBooks: const [],
                    updateCandidates: [candidate],
                  ),
                ),
                child: const Text('Handle'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Handle'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_update_skip_all')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_update_apply')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('卸載防護（Review Focus 1）：mounted == false 時不彈出對話框且丟棄候選', (tester) async {
      final importService = FakeBookImportService();
      final candidate = makeCandidate();
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedContext = context;
                return const Text('Mounted Widget');
              },
            ),
          ),
        ),
      );

      // 把 widget pump 掉，使 capturedContext.mounted 變為 false
      await tester.pumpWidget(const SizedBox());

      await handleImportUpdateCandidates(
        capturedContext,
        importService,
        ImportResult(
          importedBooks: const [],
          updateCandidates: [candidate],
        ),
      );

      expect(find.byKey(const Key('book_update_apply')), findsNothing);
      expect(importService.discardedCandidates, [candidate]);
    });
  });
}
