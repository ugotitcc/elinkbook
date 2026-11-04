import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/support/manual_book_update_flow.dart';

import '../../support/fake_book_import_service.dart';
import '../../support/pump_localized_widget.dart';

Book _sampleBook({
  String id = 'b1',
  String title = '原書名',
  BookFileFormat format = BookFileFormat.epub,
  String? coverPath = '/data/covers/old.jpg',
}) =>
    Book(
      id: id,
      title: title,
      format: format,
      filePath: '/data/imported/$id.${format.name}',
      source: BookSource.local,
      coverPath: coverPath,
      createTime: DateTime(2026, 1, 1),
      lastReadTime: DateTime(2026, 1, 1),
    );

class _TestHost extends StatelessWidget {
  final Future<ManualBookUpdateOutcome> Function(BuildContext) runner;
  final ValueChanged<ManualBookUpdateOutcome>? onResult;

  const _TestHost({required this.runner, this.onResult});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('trigger'),
            onPressed: () async {
              final r = await runner(context);
              onResult?.call(r);
            },
            child: const Text('trigger'),
          ),
        ),
      );
}

void main() {
  group('runManualBookUpdate', () {
    testWidgets('取消選檔：回 cancelled、沒有 SnackBar、未呼叫 replaceBook', (tester) async {
      final service = FakeBookImportService();
      ManualBookUpdateOutcome? result;

      await pumpLocalizedWidget(
        tester,
        _TestHost(
          runner: (context) => runManualBookUpdate(
            context,
            book: _sampleBook(),
            importService: service,
            pickFile: (exts) async => null,
          ),
          onResult: (r) => result = r,
        ),
      );

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      expect(result, ManualBookUpdateOutcome.cancelled);
      expect(find.byType(SnackBar), findsNothing);
      expect(service.replaceCalls, isEmpty);
    });

    testWidgets('格式不符（EPUB 書選到 .pdf）：回 formatMismatch、出現格式不符 SnackBar、不彈確認、未呼叫 replaceBook', (tester) async {
      final service = FakeBookImportService();
      ManualBookUpdateOutcome? result;

      await pumpLocalizedWidget(
        tester,
        _TestHost(
          runner: (context) => runManualBookUpdate(
            context,
            book: _sampleBook(format: BookFileFormat.epub),
            importService: service,
            pickFile: (exts) async => (uri: 'content://provider/other.pdf', displayName: 'other.pdf'),
          ),
          onResult: (r) => result = r,
        ),
      );

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      expect(result, ManualBookUpdateOutcome.formatMismatch);
      expect(find.text('選取的檔案格式與此書不同，無法更新'), findsOneWidget);
      expect(find.byKey(const Key('book_manual_update_dialog')), findsNothing);
      expect(service.replaceCalls, isEmpty);
    });

    testWidgets('副檔名無法辨識（無 displayName 的不透明 URI）視為格式不符', (tester) async {
      final service = FakeBookImportService();
      ManualBookUpdateOutcome? result;

      await pumpLocalizedWidget(
        tester,
        _TestHost(
          runner: (context) => runManualBookUpdate(
            context,
            book: _sampleBook(),
            importService: service,
            pickFile: (exts) async => (uri: 'content://provider/opaque_id', displayName: null),
          ),
          onResult: (r) => result = r,
        ),
      );

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      expect(result, ManualBookUpdateOutcome.formatMismatch);
      expect(find.text('選取的檔案格式與此書不同，無法更新'), findsOneWidget);
      expect(find.byKey(const Key('book_manual_update_dialog')), findsNothing);
    });

    testWidgets('displayName 優先於 URI 判斷格式（URI 無副檔名、displayName 為 .epub → 通過並彈對話框）', (tester) async {
      final service = FakeBookImportService();
      ManualBookUpdateOutcome? result;

      await pumpLocalizedWidget(
        tester,
        _TestHost(
          runner: (context) => runManualBookUpdate(
            context,
            book: _sampleBook(format: BookFileFormat.epub),
            importService: service,
            pickFile: (exts) async => (uri: 'content://provider/opaque_id', displayName: 'new.epub'),
          ),
          onResult: (r) => result = r,
        ),
      );

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('book_manual_update_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('book_manual_update_cancel')));
      await tester.pumpAndSettle();

      expect(result, ManualBookUpdateOutcome.cancelled);
    });

    testWidgets('確認對話框內含新檔名與書名與偏移提示；按取消回 cancelled、未呼叫 replaceBook', (tester) async {
      final service = FakeBookImportService();
      ManualBookUpdateOutcome? result;

      await pumpLocalizedWidget(
        tester,
        _TestHost(
          runner: (context) => runManualBookUpdate(
            context,
            book: _sampleBook(title: '三國演義'),
            importService: service,
            pickFile: (exts) async => (uri: 'file:///path/three_kingdoms_v2.epub', displayName: 'three_kingdoms_v2.epub'),
          ),
          onResult: (r) => result = r,
        ),
      );

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('book_manual_update_dialog')), findsOneWidget);
      expect(find.textContaining('three_kingdoms_v2.epub'), findsOneWidget);
      expect(find.textContaining('三國演義'), findsOneWidget);
      expect(find.byKey(const Key('book_manual_update_notice')), findsOneWidget);

      await tester.tap(find.byKey(const Key('book_manual_update_cancel')));
      await tester.pumpAndSettle();

      expect(result, ManualBookUpdateOutcome.cancelled);
      expect(service.replaceCalls, isEmpty);
    });

    testWidgets('確認後成功：replaceBook 呼叫正確、回 replaced、顯示已更新 1 本、evict 舊新封面（去重）', (tester) async {
      final service = FakeBookImportService()
        ..replaceResult = BookReplaceSuccess(
          _sampleBook(id: 'b1', title: '原書名', coverPath: '/data/covers/new.jpg'),
        );
      final evictedCovers = <String>[];
      ManualBookUpdateOutcome? result;

      await pumpLocalizedWidget(
        tester,
        _TestHost(
          runner: (context) => runManualBookUpdate(
            context,
            book: _sampleBook(coverPath: '/data/covers/old.jpg'),
            importService: service,
            pickFile: (exts) async => (uri: 'file:///new.epub', displayName: 'new.epub'),
            onCoverChanged: (path) => evictedCovers.add(path),
          ),
          onResult: (r) => result = r,
        ),
      );

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('book_manual_update_confirm')));
      await tester.pumpAndSettle();

      expect(result, ManualBookUpdateOutcome.replaced);
      expect(service.replaceCalls, hasLength(1));
      expect(service.replaceCalls.first.$1, 'b1');
      expect(service.replaceCalls.first.$2, 'file:///new.epub');
      expect(service.lastReplaceDisplayName, 'new.epub');
      expect(service.lastReplaceCandidate, isNull);

      expect(find.text('已更新 1 本'), findsOneWidget);
      expect(evictedCovers, ['/data/covers/old.jpg', '/data/covers/new.jpg']);
    });

    testWidgets('新舊封面路徑相同時只 evict 一次；新封面為 null 時只 evict 舊封面', (tester) async {
      final service = FakeBookImportService()
        ..replaceResult = BookReplaceSuccess(
          _sampleBook(id: 'b1', coverPath: '/data/covers/same.jpg'),
        );
      final evicted = <String>[];

      await pumpLocalizedWidget(
        tester,
        _TestHost(
          runner: (context) => runManualBookUpdate(
            context,
            book: _sampleBook(coverPath: '/data/covers/same.jpg'),
            importService: service,
            pickFile: (exts) async => (uri: 'file:///new.epub', displayName: 'new.epub'),
            onCoverChanged: (path) => evicted.add(path),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book_manual_update_confirm')));
      await tester.pumpAndSettle();

      expect(evicted, ['/data/covers/same.jpg']);
    });

    testWidgets('不比對書名作者識別碼：新檔書名與原書完全不同仍成功', (tester) async {
      final service = FakeBookImportService()
        ..replaceResult = BookReplaceSuccess(
          _sampleBook(id: 'b1', title: '全新的書名'),
        );
      ManualBookUpdateOutcome? result;

      await pumpLocalizedWidget(
        tester,
        _TestHost(
          runner: (context) => runManualBookUpdate(
            context,
            book: _sampleBook(title: '舊書名'),
            importService: service,
            pickFile: (exts) async => (uri: 'file:///new.epub', displayName: 'new.epub'),
          ),
          onResult: (r) => result = r,
        ),
      );

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book_manual_update_confirm')));
      await tester.pumpAndSettle();

      expect(result, ManualBookUpdateOutcome.replaced);
      expect(find.text('已更新 1 本'), findsOneWidget);
    });

    for (final reason in BookReplaceFailureReason.values) {
      testWidgets('取代失敗（$reason）：回 failed、顯示更新失敗 SnackBar、未 evict', (tester) async {
        final service = FakeBookImportService()
          ..replaceResult = BookReplaceFailure(reason);
        final evicted = <String>[];
        ManualBookUpdateOutcome? result;

        await pumpLocalizedWidget(
          tester,
          _TestHost(
            runner: (context) => runManualBookUpdate(
              context,
              book: _sampleBook(),
              importService: service,
              pickFile: (exts) async => (uri: 'file:///new.epub', displayName: 'new.epub'),
              onCoverChanged: (path) => evicted.add(path),
            ),
            onResult: (r) => result = r,
          ),
        );

        await tester.tap(find.byKey(const Key('trigger')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('book_manual_update_confirm')));
        await tester.pumpAndSettle();

        expect(result, ManualBookUpdateOutcome.failed);
        expect(find.text('1 本更新失敗，書籍沒有任何變動'), findsOneWidget);
        expect(evicted, isEmpty);
      });
    }

    testWidgets('replaceBook 拋例外：同失敗處理，不拋出', (tester) async {
      final service = FakeBookImportService()..replaceThrows = StateError('boom');
      ManualBookUpdateOutcome? result;

      await pumpLocalizedWidget(
        tester,
        _TestHost(
          runner: (context) => runManualBookUpdate(
            context,
            book: _sampleBook(),
            importService: service,
            pickFile: (exts) async => (uri: 'file:///new.epub', displayName: 'new.epub'),
          ),
          onResult: (r) => result = r,
        ),
      );

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book_manual_update_confirm')));
      await tester.pumpAndSettle();

      expect(result, ManualBookUpdateOutcome.failed);
      expect(find.text('1 本更新失敗，書籍沒有任何變動'), findsOneWidget);
    });

    testWidgets('更新中（replaceBook 以 Completer 擱置）：對話框仍在、取消與更新按鈕皆停用、顯示處理中文字、返回鍵無法關閉；Completer 完成後才關閉', (tester) async {
      final completer = Completer<BookReplaceResult>();
      final service = FakeBookImportService()..replaceCompleter = completer;
      ManualBookUpdateOutcome? result;

      await pumpLocalizedWidget(
        tester,
        _TestHost(
          runner: (context) => runManualBookUpdate(
            context,
            book: _sampleBook(),
            importService: service,
            pickFile: (exts) async => (uri: 'file:///new.epub', displayName: 'new.epub'),
          ),
          onResult: (r) => result = r,
        ),
      );

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      // 按下確認，進入更新中
      await tester.tap(find.byKey(const Key('book_manual_update_confirm')));
      await tester.pump();

      // 對話框仍在
      expect(find.byKey(const Key('book_manual_update_dialog')), findsOneWidget);
      // 處理中文字
      expect(find.byKey(const Key('book_manual_update_applying')), findsOneWidget);
      // 按鈕停用
      final cancelBtn = tester.widget<TextButton>(find.byKey(const Key('book_manual_update_cancel')));
      expect(cancelBtn.onPressed, isNull);
      final confirmBtn = tester.widget<TextButton>(find.byKey(const Key('book_manual_update_confirm')));
      expect(confirmBtn.onPressed, isNull);

      // 返回鍵無法關閉
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const Key('book_manual_update_dialog')), findsOneWidget);

      // 完成 replaceBook
      completer.complete(BookReplaceSuccess(_sampleBook()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('book_manual_update_dialog')), findsNothing);
      expect(result, ManualBookUpdateOutcome.replaced);
    });

    testWidgets('E-Ink 模式（isEinkMode:true）：對話框無過場動畫', (tester) async {
      final service = FakeBookImportService();
      ManualBookUpdateOutcome? result;

      await pumpLocalizedWidget(
        tester,
        _TestHost(
          runner: (context) => runManualBookUpdate(
            context,
            book: _sampleBook(),
            importService: service,
            pickFile: (exts) async => (uri: 'file:///new.epub', displayName: 'new.epub'),
            isEinkMode: true,
          ),
          onResult: (r) => result = r,
        ),
      );

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('book_manual_update_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('book_manual_update_cancel')));
      await tester.pumpAndSettle();

      expect(result, ManualBookUpdateOutcome.cancelled);
    });
  });
}
