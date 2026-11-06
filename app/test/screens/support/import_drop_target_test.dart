import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/library/book_import_service.dart';
import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/support/import_drop_target.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_book_import_service.dart';

Book _testBook(String id) {
  final now = DateTime(2026, 1, 1);
  return Book(
    id: id,
    title: '書 $id',
    format: BookFileFormat.epub,
    filePath: 'C:/books/$id.epub',
    source: BookSource.local,
    createTime: now,
    lastReadTime: now,
  );
}

BookUpdateCandidate _testCandidate(String id) {
  return BookUpdateCandidate(
    sourceUri: 'C:/books/$id.epub',
    displayName: '$id.epub',
    format: BookFileFormat.epub,
    confidence: UpdateConfidence.high,
    candidateBooks: [_testBook(id)],
  );
}

void _testWindowsWidgets(
  String description,
  Future<void> Function(WidgetTester tester) callback,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await callback(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('import_drop_target_test');
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget buildApp({
    required BookImportService importService,
    bool enabled = true,
    bool isEinkMode = false,
    VoidCallback? onImportCompleted,
  }) {
    return MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ImportDropTarget(
          importService: importService,
          isEinkMode: isEinkMode,
          enabled: enabled,
          onImportCompleted: onImportCompleted,
          child: const Text('內層畫面'),
        ),
      ),
    );
  }

  testWidgets('非 Windows 不掛載 DropTarget', (tester) async {
    final service = FakeBookImportService();
    await tester.pumpWidget(buildApp(importService: service));

    expect(find.byType(DropTarget), findsNothing);
    expect(find.text('內層畫面'), findsOneWidget);
  });

  _testWindowsWidgets('enabled 為 false 時 DropTarget.enable 為 false', (tester) async {
    final service = FakeBookImportService();
    await tester.pumpWidget(buildApp(importService: service, enabled: false));

    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    expect(dropTarget.enable, isFalse);
  });

  _testWindowsWidgets('拖曳經過顯示遮罩，離開後消失', (tester) async {
    final service = FakeBookImportService();
    await tester.pumpWidget(buildApp(importService: service));

    final l10n = AppLocalizations.of(tester.element(find.text('內層畫面')))!;
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

    expect(find.byKey(const Key('import_drop_overlay')), findsNothing);

    dropTarget.onDragEntered?.call(
      DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero),
    );
    await tester.pump();

    expect(find.byKey(const Key('import_drop_overlay')), findsOneWidget);
    expect(find.text(l10n.importDropOverlayText), findsOneWidget);

    dropTarget.onDragExited?.call(
      DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero),
    );
    await tester.pump();

    expect(find.byKey(const Key('import_drop_overlay')), findsNothing);
  });

  _testWindowsWidgets('拖入書檔：呼叫 importFiles 並顯示匯入結果提示', (tester) async {
    final file = File(p.join(tempDir.path, 'book.epub'))..writeAsBytesSync([1]);
    final service = FakeBookImportService()
      ..importFilesResult = ImportResult(importedBooks: [_testBook('1')]);

    await tester.pumpWidget(buildApp(importService: service));
    final l10n = AppLocalizations.of(tester.element(find.text('內層畫面')))!;
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemFile(file.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();

    expect(service.lastImportCall, isNotNull);
    expect(service.lastImportCall!.uris, [file.path]);
    expect(find.text(l10n.libraryImportResultImportedOnlyMessage(1)), findsOneWidget);
  });

  _testWindowsWidgets('匯入進行中再拖入：不再呼叫 importFiles，顯示 importDropBusyMessage', (tester) async {
    final file1 = File(p.join(tempDir.path, 'a.epub'))..writeAsBytesSync([1]);
    final file2 = File(p.join(tempDir.path, 'b.epub'))..writeAsBytesSync([2]);
    final completer = Completer<ImportResult>();
    final service = FakeBookImportService()..pendingCompleter = completer;

    await tester.pumpWidget(buildApp(importService: service));
    final l10n = AppLocalizations.of(tester.element(find.text('內層畫面')))!;
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemFile(file1.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pump();
    expect(service.lastImportCall!.uris, [file1.path]);

    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemFile(file2.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pump();

    expect(service.lastImportCall!.uris, [file1.path]);
    expect(find.text(l10n.importDropBusyMessage), findsOneWidget);

    completer.complete(const ImportResult());
    await tester.pumpAndSettle();
  });

  _testWindowsWidgets('匯入進行中拖曳經過：不顯示遮罩，放開仍顯示 importDropBusyMessage', (tester) async {
    final file1 = File(p.join(tempDir.path, 'a.epub'))..writeAsBytesSync([1]);
    final file2 = File(p.join(tempDir.path, 'b.epub'))..writeAsBytesSync([2]);
    final completer = Completer<ImportResult>();
    final service = FakeBookImportService()..pendingCompleter = completer;

    await tester.pumpWidget(buildApp(importService: service));
    final l10n = AppLocalizations.of(tester.element(find.text('內層畫面')))!;
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemFile(file1.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pump();

    dropTarget.onDragEntered?.call(
      DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero),
    );
    await tester.pump();

    expect(find.byKey(const Key('import_drop_overlay')), findsNothing);

    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemFile(file2.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pump();

    expect(find.text(l10n.importDropBusyMessage), findsOneWidget);

    completer.complete(const ImportResult());
    await tester.pumpAndSettle();
  });

  _testWindowsWidgets('匯入有新書時呼叫 onImportCompleted；沒有新書與更新候選時不呼叫；匯入失敗（failure）時不呼叫', (tester) async {
    final file = File(p.join(tempDir.path, 'a.epub'))..writeAsBytesSync([1]);
    final dir = Directory(p.join(tempDir.path, 'folder'))..createSync();
    final service = FakeBookImportService();
    var completedCalls = 0;

    await tester.pumpWidget(
      buildApp(
        importService: service,
        onImportCompleted: () => completedCalls++,
      ),
    );
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

    // 1. 有新書 -> 呼叫
    service.importFilesResult = ImportResult(importedBooks: [_testBook('1')]);
    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemFile(file.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();
    expect(completedCalls, 1);

    // 2. 沒有新書與更新候選（僅跳過重複） -> 不呼叫
    service.importFilesResult = const ImportResult(skippedDuplicateCount: 1);
    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemFile(file.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();
    expect(completedCalls, 1);

    // 3. 匯入失敗（failure） -> 不呼叫
    service.importFolderResult = const ImportResult(
      failure: ImportFailure.folderListingFailed,
    );
    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemFile(dir.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_folder_confirm')));
    await tester.pumpAndSettle();
    expect(completedCalls, 1);
  });

  _testWindowsWidgets('拖入的 files 為空：不呼叫任何匯入、不顯示任何 SnackBar', (tester) async {
    final service = FakeBookImportService();
    await tester.pumpWidget(buildApp(importService: service));
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: const [],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();

    expect(service.lastImportCall, isNull);
    expect(service.importFolderCalls, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  _testWindowsWidgets('拖入資料夾：跳出確認框，按確認後呼叫 importFolder；按取消則不呼叫', (tester) async {
    final dir = Directory(p.join(tempDir.path, '書櫃'))..createSync();
    final service = FakeBookImportService();
    await tester.pumpWidget(buildApp(importService: service));
    final l10n = AppLocalizations.of(tester.element(find.text('內層畫面')))!;
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

    // 按取消
    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemFile(dir.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(service.importFolderCalls, isEmpty);

    // 按確認
    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemFile(dir.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_folder_confirm')));
    await tester.pumpAndSettle();
    expect(service.importFolderCalls, [dir.path]);
  });

  _testWindowsWidgets('匯入未完成時卸載 widget：不丟例外', (tester) async {
    final file = File(p.join(tempDir.path, 'a.epub'))..writeAsBytesSync([1]);
    final completer = Completer<ImportResult>();
    final service = FakeBookImportService()..pendingCompleter = completer;

    await tester.pumpWidget(buildApp(importService: service));
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemFile(file.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    completer.complete(ImportResult(importedBooks: [_testBook('1')]));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  _testWindowsWidgets('匯入結果含更新候選但已卸載：呼叫 discardUpdateCandidates', (tester) async {
    final file = File(p.join(tempDir.path, 'a.epub'))..writeAsBytesSync([1]);
    final completer = Completer<ImportResult>();
    final service = FakeBookImportService()..pendingCompleter = completer;
    final candidate = _testCandidate('cand1');

    await tester.pumpWidget(buildApp(importService: service));
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

    dropTarget.onDragDone?.call(
      DropDoneDetails(
        files: [DropItemFile(file.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    completer.complete(ImportResult(updateCandidates: [candidate]));
    await tester.pump();

    expect(service.discardedCandidates, [candidate]);
  });
}
