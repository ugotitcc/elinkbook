import 'dart:async';

import 'package:elinkbook/library/book_update_models.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/support/book_update_resolver.dart';
import 'package:elinkbook/screens/widgets/book_update_summary_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_book_import_service.dart';
import '../../support/pump_localized_widget.dart';

Book _makeBook({
  required String id,
  String title = '測試書',
  String? coverPath,
}) {
  return Book(
    id: id,
    title: title,
    format: BookFileFormat.epub,
    source: BookSource.local,
    filePath: '/test/path/$id.epub',
    coverPath: coverPath,
    createTime: DateTime(2026, 1, 1),
    lastReadTime: DateTime(2026, 1, 1),
  );
}

BookUpdateCandidate _makeCandidate({
  String sourceUri = 'file:///test/new.epub',
  String? displayName = 'new.epub',
  BookFileFormat format = BookFileFormat.epub,
  UpdateConfidence confidence = UpdateConfidence.high,
  List<Book>? candidateBooks,
  Set<String> unreadableCandidateBookIds = const {},
  String? stagedPath = '/test/staging/staged.epub',
}) {
  return BookUpdateCandidate(
    sourceUri: sourceUri,
    displayName: displayName,
    format: format,
    confidence: confidence,
    candidateBooks: candidateBooks ?? [_makeBook(id: 'b1', title: '書庫既有書')],
    unreadableCandidateBookIds: unreadableCandidateBookIds,
    stagedPath: stagedPath,
  );
}

Future<Future<BookUpdateApplyResult>> _openDialog(
  WidgetTester tester, {
  FakeBookImportService? service,
  required List<BookUpdateCandidate> candidates,
  bool isEinkMode = false,
  bool discardOnCancel = true,
  Future<BookUpdateApplyResult> Function(Map<BookUpdateCandidate, BookUpdateChoice> choices)? applier,
}) async {
  late Future<BookUpdateApplyResult> result;
  await pumpLocalizedWidget(
    tester,
    Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => result = showBookUpdateSummaryDialog(
          context,
          importService: service,
          candidates: candidates,
          isEinkMode: isEinkMode,
          discardOnCancel: discardOnCancel,
          applier: applier,
        ),
        child: const Text('open'),
      ),
    ),
    isEinkMode: isEinkMode,
  );
  await tester.tap(find.text('open'));
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBookImportService service;

  setUp(() {
    service = FakeBookImportService();
  });

  testWidgets('顯示每本的選項與信心：兩筆候選各顯示高信心與疑似、預設選取取代', (tester) async {
    final c0 = _makeCandidate(
      sourceUri: 'file:///c0.epub',
      displayName: '第一本.epub',
      confidence: UpdateConfidence.high,
    );
    final c1 = _makeCandidate(
      sourceUri: 'file:///c1.epub',
      displayName: '第二本.epub',
      confidence: UpdateConfidence.suspected,
    );

    await _openDialog(tester, service: service, candidates: [c0, c1]);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_update_confidence_0')), findsOneWidget);
    expect(find.byKey(const Key('book_update_confidence_1')), findsOneWidget);
    expect(find.textContaining('高信心'), findsOneWidget);
    expect(find.textContaining('疑似'), findsOneWidget);

    expect(find.byKey(const Key('book_update_option_replace_0_b1')), findsOneWidget);
    expect(find.byKey(const Key('book_update_option_coexist_0')), findsOneWidget);
    expect(find.byKey(const Key('book_update_option_skip_0')), findsOneWidget);

    final group = tester.widget<RadioGroup<BookUpdateChoice>>(
      find.byKey(const Key('book_update_row_0')),
    );
    expect(group.groupValue, const ReplaceChoice('b1'));
  });

  testWidgets('多候選：候選清單含多本書，改選第二本後套用呼叫正確的 bookId', (tester) async {
    final b1 = _makeBook(id: 'b1', title: '版本一');
    final b2 = _makeBook(id: 'b2', title: '版本二');
    final candidate = _makeCandidate(candidateBooks: [b1, b2]);
    service.replaceResultsByBookId['b2'] = BookReplaceSuccess(b2);

    final resultFuture = await _openDialog(tester, service: service, candidates: [candidate]);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_update_option_replace_0_b1')), findsOneWidget);
    expect(find.byKey(const Key('book_update_option_replace_0_b2')), findsOneWidget);

    // 點擊選擇版本二
    await tester.tap(find.byKey(const Key('book_update_option_replace_0_b2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_update_apply')));
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(result.replaced, 1);
    expect(service.replaceCalls, [('b2', candidate.sourceUri)]);
  });

  testWidgets('全部跳過：按全部跳過後每列變為跳過，套用後丟棄所有暫存且不呼叫取代', (tester) async {
    final c0 = _makeCandidate(sourceUri: 'file:///c0.epub');
    final c1 = _makeCandidate(sourceUri: 'file:///c1.epub');

    final resultFuture = await _openDialog(tester, service: service, candidates: [c0, c1]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_update_skip_all')));
    await tester.pumpAndSettle();

    final group0 = tester.widget<RadioGroup<BookUpdateChoice>>(
      find.byKey(const Key('book_update_row_0')),
    );
    final group1 = tester.widget<RadioGroup<BookUpdateChoice>>(
      find.byKey(const Key('book_update_row_1')),
    );
    expect(group0.groupValue, const SkipChoice());
    expect(group1.groupValue, const SkipChoice());

    await tester.tap(find.byKey(const Key('book_update_apply')));
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(result.skipped, 2);
    expect(service.replaceCalls, isEmpty);
    expect(service.discardedCandidates, containsAll([c0, c1]));
  });

  testWidgets('全部取代：先全部跳過再按全部取代，每列回到第一本取代', (tester) async {
    final c0 = _makeCandidate(sourceUri: 'file:///c0.epub');
    final c1 = _makeCandidate(sourceUri: 'file:///c1.epub');
    service.replaceResultsByBookId['b1'] = BookReplaceSuccess(_makeBook(id: 'b1'));

    final resultFuture = await _openDialog(tester, service: service, candidates: [c0, c1]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_update_skip_all')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_update_replace_all')));
    await tester.pumpAndSettle();

    final group0AfterReplace = tester.widget<RadioGroup<BookUpdateChoice>>(
      find.byKey(const Key('book_update_row_0')),
    );
    expect(group0AfterReplace.groupValue, const ReplaceChoice('b1'));

    await tester.tap(find.byKey(const Key('book_update_apply')));
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(result.replaced, 2);
    expect(service.replaceCalls.length, 2);
  });

  testWidgets('偏移提示：預設選取代時可見，全選跳過時消失，選回取代時再次出現', (tester) async {
    final candidate = _makeCandidate();

    await _openDialog(tester, service: service, candidates: [candidate]);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_update_replace_notice')), findsOneWidget);

    await tester.tap(find.byKey(const Key('book_update_skip_all')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_update_replace_notice')), findsNothing);

    await tester.tap(find.byKey(const Key('book_update_replace_all')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_update_replace_notice')), findsOneWidget);
  });

  testWidgets('舊檔無法存取提示：候選包含 unreadableCandidateBookIds 且選取取代該書時顯示', (tester) async {
    final candidate = _makeCandidate(
      unreadableCandidateBookIds: {'b1'},
    );

    await _openDialog(tester, service: service, candidates: [candidate]);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_update_unreadable_0')), findsOneWidget);

    // 改選並存後隱藏
    await tester.tap(find.byKey(const Key('book_update_option_coexist_0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_update_unreadable_0')), findsNothing);
  });

  testWidgets('取消與系統返回都丟棄暫存檔並關閉對話框', (tester) async {
    // 1. 取消按鈕
    final c0 = _makeCandidate(sourceUri: 'file:///c0.epub');
    final resultFuture0 = await _openDialog(tester, service: service, candidates: [c0]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_update_cancel')));
    await tester.pumpAndSettle();

    final result0 = await resultFuture0;
    expect(result0.skipped, 1);
    expect(service.discardedCandidates, [c0]);

    // 2. 系統返回鍵
    service.discardedCandidates.clear();
    final c1 = _makeCandidate(sourceUri: 'file:///c1.epub');
    final resultFuture1 = await _openDialog(tester, service: service, candidates: [c1]);
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final result1 = await resultFuture1;
    expect(result1.skipped, 1);
    expect(service.discardedCandidates, [c1]);
  });

  testWidgets('套用中不可重入：連按套用與返回不會重複執行且顯示處理中', (tester) async {
    final candidate = _makeCandidate();
    final completer = Completer<BookReplaceResult>();
    service.replaceCompleter = completer;

    late Future<BookUpdateApplyResult> dialogResult;
    await pumpLocalizedWidget(
      tester,
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () {
            dialogResult = showBookUpdateSummaryDialog(
              context,
              importService: service,
              candidates: [candidate],
            );
          },
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    service.replaceCalls.clear();

    // 點擊套用發動非同步處理
    await tester.tap(find.byKey(const Key('book_update_apply')));
    await tester.pump(); // 停在非同步等待中

    expect(find.byKey(const Key('book_update_applying')), findsOneWidget);
    expect(service.replaceCalls.length, 1);

    // 套用中再次點擊套用與返回，不應增加呼叫次數
    await tester.tap(find.byKey(const Key('book_update_apply')));
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byKey(const Key('book_update_applying')), findsOneWidget);
    expect(service.replaceCalls.length, 1);

    // 完成套用
    completer.complete(BookReplaceSuccess(_makeBook(id: 'b1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_update_applying')), findsNothing);
    final result = await dialogResult;
    expect(result.replaced, 1);
  });

  testWidgets('點外部遮罩不關閉對話框', (tester) async {
    final candidate = _makeCandidate();
    await _openDialog(tester, service: service, candidates: [candidate]);
    await tester.pumpAndSettle();

    // 點擊對話框外左上角（0, 0）遮罩處
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_update_apply')), findsOneWidget);
    expect(service.discardedCandidates, isEmpty);
  });

  List<BookUpdateCandidate> longNameCandidates() => List.generate(
        50,
        (i) => _makeCandidate(
          sourceUri: 'file:///path/long_name_test_candidate_book_file_$i.epub',
          displayName:
              '這是一本非常長檔名用來測試排版是否溢位的書籍名稱展示長度超過八十個字元_檔案序號_$i.epub',
        ),
      );

  void useNarrowScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('大量候選（50 筆）窄螢幕：無 overflow，可捲到最後一列並點選其選項', (tester) async {
    useNarrowScreen(tester);
    final dialogResult = await _openDialog(
      tester,
      service: service,
      candidates: longNameCandidates(),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final lastSkip = find.byKey(const Key('book_update_option_skip_49'));
    await tester.scrollUntilVisible(
      lastSkip,
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(lastSkip);
    await tester.pumpAndSettle();
    await tester.tap(lastSkip);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 其餘 49 筆維持預設取代（服務預設回失敗），第 50 筆改為跳過
    await tester.tap(find.byKey(const Key('book_update_apply')));
    await tester.pumpAndSettle();
    final result = await dialogResult;
    expect(result.skipped, 1);
    expect(result.failed, 49);
    expect(service.replaceCalls.length, 49);
  });

  testWidgets('大量候選（50 筆）E-Ink 模式：無 overflow、無過場動畫', (tester) async {
    useNarrowScreen(tester);
    await _openDialog(
      tester,
      service: service,
      candidates: longNameCandidates(),
      isEinkMode: true,
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('book_update_row_0')), findsOneWidget);
    expect(find.byKey(const Key('book_update_apply')), findsOneWidget);
  });

  testWidgets("discardOnCancel 為 false 且取消（審查 I-1）：不丟棄暫存，回傳全為 0 之結果", (tester) async {
    final c0 = _makeCandidate(sourceUri: "file:///c0.epub");
    final resultFuture = await _openDialog(
      tester,
      service: service,
      candidates: [c0],
      discardOnCancel: false,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key("book_update_cancel")));
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(result, const BookUpdateApplyResult());
    expect(service.discardedCandidates, isEmpty);
  });

  testWidgets("自訂 applier：點套用呼叫 applier 而非預設流程，importService 為 null 不拋例外", (tester) async {
    final c0 = _makeCandidate(sourceUri: "file:///c0.epub");
    Map<BookUpdateCandidate, BookUpdateChoice>? appliedChoices;
    final resultFuture = await _openDialog(
      tester,
      service: null,
      candidates: [c0],
      applier: (choices) async {
        appliedChoices = choices;
        return const BookUpdateApplyResult(replaced: 1);
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key("book_update_apply")));
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(result.replaced, 1);
    expect(appliedChoices, isNotNull);
    expect(appliedChoices?[c0], const ReplaceChoice("b1"));
  });

  testWidgets("applier + discardOnCancel 為 true 時按取消：改走 applier 以全 SkipChoice 丟棄（審查 I-2）", (tester) async {
    final c0 = _makeCandidate(sourceUri: "file:///c0.epub");
    Map<BookUpdateCandidate, BookUpdateChoice>? appliedChoices;
    final resultFuture = await _openDialog(
      tester,
      service: null,
      candidates: [c0],
      discardOnCancel: true,
      applier: (choices) async {
        appliedChoices = choices;
        return const BookUpdateApplyResult(skipped: 1);
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key("book_update_cancel")));
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(tester.takeException(), isNull);
    expect(result.skipped, 1);
    expect(appliedChoices?[c0], const SkipChoice());
  });

  testWidgets("applier + discardOnCancel 為 true 且對話框被直接關閉（回 null）：保底走 applier 全跳過（審查 I-2）", (tester) async {
    final c0 = _makeCandidate(sourceUri: "file:///c0.epub");
    Map<BookUpdateCandidate, BookUpdateChoice>? appliedChoices;
    final resultFuture = await _openDialog(
      tester,
      service: null,
      candidates: [c0],
      discardOnCancel: true,
      applier: (choices) async {
        appliedChoices = choices;
        return const BookUpdateApplyResult(skipped: 1);
      },
    );
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(tester.takeException(), isNull);
    expect(result.skipped, 1);
    expect(appliedChoices?[c0], const SkipChoice());
  });

  testWidgets("僅 applier、discardOnCancel 為 false 且對話框被直接關閉（回 null）：不拋例外、不呼叫 applier、回傳全 0（審查 I-1）", (tester) async {
    final c0 = _makeCandidate(sourceUri: "file:///c0.epub");
    var applierCalls = 0;
    final resultFuture = await _openDialog(
      tester,
      service: null,
      candidates: [c0],
      discardOnCancel: false,
      applier: (choices) async {
        applierCalls++;
        return const BookUpdateApplyResult(replaced: 1);
      },
    );
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(tester.takeException(), isNull);
    expect(applierCalls, 0);
    expect(result, const BookUpdateApplyResult());
  });
}
