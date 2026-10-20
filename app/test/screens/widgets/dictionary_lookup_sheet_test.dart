import 'dart:async';

import 'package:elinkbook/dictionary/dictionary_service.dart';
import 'package:elinkbook/dictionary/lookup_text_normalizer.dart';
import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/models/lookup_request.dart';
import 'package:elinkbook/dictionary/models/lookup_result.dart';
import 'package:elinkbook/screens/widgets/dictionary_lookup_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_dictionary_service.dart';
import '../../support/pump_localized_widget.dart';

const _failedMessage =
    '這本字典查詢失敗。請稍後再試，或到字典設定確認這本字典。';

DictionaryEntry _entry(
  String headword, {
  String? pronunciation,
  String? partOfSpeech,
  String body = '釋義內容',
}) =>
    DictionaryEntry(
      sourceId: 'src',
      headword: headword,
      pronunciation: pronunciation,
      partOfSpeech: partOfSpeech,
      body: body,
      bodyKind: EntryBodyKind.plainText,
    );

ProviderOutcome _outcome(
  String id, {
  String? name,
  OutcomeStatus status = OutcomeStatus.found,
  List<DictionaryEntry> entries = const [],
  String? attribution,
}) =>
    ProviderOutcome(
      providerId: id,
      displayName: name ?? '字典 $id',
      status: status,
      entries: entries,
      attribution: attribution,
    );

LookupCompleted _completed(
  List<ProviderOutcome> outcomes, {
  bool hasEnabledDictionary = true,
}) =>
    LookupCompleted(
      result: LookupResult(
        request: const LookupRequest('詞'),
        outcomes: outcomes,
      ),
      hasEnabledDictionary: hasEnabledDictionary,
    );

/// 比照 `EBSheetShell` 的環境：內容放在 `Flexible` 內，只給上限不給固定高度，
/// 面板才能依內容縮短、內容過長時由內部的 `ListView` 滾動。
Future<void> _pumpSheet(
  WidgetTester tester, {
  required Future<DictionaryLookupResponse> response,
  bool isEinkMode = false,
  VoidCallback? onOpenSettings,
  bool settle = true,
}) async {
  await pumpLocalizedWidget(
    tester,
    Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: DictionaryLookupSheet(
                selectedText: '詞',
                response: response,
                isEinkMode: isEinkMode,
                onOpenSettings: onOpenSettings,
              ),
            ),
          ],
        ),
      ),
    ),
    isEinkMode: isEinkMode,
  );
  if (settle) await tester.pump();
}

Set<String> _selectedSegments(WidgetTester tester) => tester
    .widget<SegmentedButton<String>>(
      find.byKey(const Key('dictionary_lookup_segments')),
    )
    .selected;

void main() {
  group('載入與選取無效', () {
    testWidgets('等待中顯示載入指示', (tester) async {
      final completer = Completer<DictionaryLookupResponse>();
      await _pumpSheet(tester, response: completer.future, settle: false);
      await tester.pump();

      expect(
        find.byKey(const Key('dictionary_lookup_loading')),
        findsOneWidget,
      );
    });

    testWidgets('LookupRejected(invalidSelection) 顯示含標點提示', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          const LookupRejected(SelectionProblem.invalidSelection),
        ),
      );

      expect(
        find.byKey(const Key('dictionary_lookup_rejected')),
        findsOneWidget,
      );
      expect(find.text('選取內容含有標點，請重新選取'), findsOneWidget);
    });

    testWidgets('LookupRejected(tooLong) 顯示太長提示', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(const LookupRejected(SelectionProblem.tooLong)),
      );

      expect(
        find.byKey(const Key('dictionary_lookup_rejected')),
        findsOneWidget,
      );
      expect(find.text('選取範圍太長，請縮短後再查'), findsOneWidget);
    });
  });

  group('沒有結果的兩種情況', () {
    testWidgets('outcomes 為空且 hasEnabledDictionary=false 顯示尚未匯入字典',
        (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(_completed([], hasEnabledDictionary: false)),
      );

      expect(
        find.byKey(const Key('dictionary_lookup_empty_no_dictionary')),
        findsOneWidget,
      );
      expect(find.text('尚未匯入字典'), findsOneWidget);
      expect(find.text('沒有適用於這段文字的字典'), findsNothing);
    });

    testWidgets('outcomes 為空但 hasEnabledDictionary=true 顯示沒有適用字典',
        (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(_completed([], hasEnabledDictionary: true)),
      );

      expect(
        find.byKey(const Key('dictionary_lookup_empty_no_match')),
        findsOneWidget,
      );
      expect(find.text('沒有適用於這段文字的字典'), findsOneWidget);
      expect(find.text('尚未匯入字典'), findsNothing);
    });
  });

  group('單一 provider', () {
    testWidgets('不顯示分段選擇器', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([
            _outcome('a', entries: [_entry('詞條甲')]),
          ]),
        ),
      );

      expect(find.byKey(const Key('dictionary_lookup_segments')), findsNothing);
      expect(find.text('詞條甲'), findsOneWidget);
    });

    testWidgets('notFound 顯示查無此詞', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([_outcome('a', status: OutcomeStatus.notFound)]),
        ),
      );

      expect(find.byKey(const Key('dictionary_lookup_not_found')), findsOneWidget);
      expect(find.text('查無此詞'), findsOneWidget);
    });

    testWidgets('skipped 顯示線上查詢已關閉', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([_outcome('a', status: OutcomeStatus.skipped)]),
        ),
      );

      expect(find.byKey(const Key('dictionary_lookup_skipped')), findsOneWidget);
      expect(find.text('線上查詢已關閉'), findsOneWidget);
    });

    testWidgets('failed 顯示失敗訊息', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([_outcome('a', status: OutcomeStatus.failed)]),
        ),
      );

      expect(find.byKey(const Key('dictionary_lookup_failed')), findsOneWidget);
      expect(find.text(_failedMessage), findsOneWidget);
    });
  });

  group('多個 provider 的分段', () {
    testWidgets('預設選中第一個 found 的分段', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([
            _outcome('a', name: '甲典', status: OutcomeStatus.notFound),
            _outcome('b', name: '乙典', entries: [_entry('乙的詞條')]),
          ]),
        ),
      );

      expect(_selectedSegments(tester), {'b'});
      expect(find.text('乙的詞條'), findsOneWidget);
    });

    testWidgets('都沒有 found 時選第一個', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([
            _outcome('a', name: '甲典', status: OutcomeStatus.notFound),
            _outcome('b', name: '乙典', status: OutcomeStatus.skipped),
          ]),
        ),
      );

      expect(_selectedSegments(tester), {'a'});
      expect(find.text('查無此詞'), findsOneWidget);
    });

    testWidgets('點另一個分段會切換內容', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([
            _outcome('a', name: '甲典', entries: [_entry('甲的詞條')]),
            _outcome('b', name: '乙典', entries: [_entry('乙的詞條')]),
          ]),
        ),
      );

      expect(find.text('甲的詞條'), findsOneWidget);
      expect(find.text('乙的詞條'), findsNothing);

      await tester.tap(find.text('乙典'));
      await tester.pump();

      expect(find.text('乙的詞條'), findsOneWidget);
      expect(find.text('甲的詞條'), findsNothing);
    });

    testWidgets('每個分段標籤都帶狀態後綴（包含未選中的）', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([
            _outcome('a', name: '甲典', entries: [_entry('甲詞')]),
            _outcome('b', name: '乙典', status: OutcomeStatus.notFound),
            _outcome('c', name: '丙典', status: OutcomeStatus.skipped),
            _outcome('d', name: '丁典', status: OutcomeStatus.failed),
          ]),
        ),
      );

      expect(find.text('甲典'), findsWidgets);
      expect(find.text('乙典（無）'), findsOneWidget);
      expect(find.text('丙典（略過）'), findsOneWidget);
      expect(find.text('丁典（失敗）'), findsOneWidget);
    });

    testWidgets('底部顯示來源名稱與 attribution', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([
            _outcome(
              'a',
              name: '萌典',
              entries: [_entry('詞條甲')],
              attribution: 'CC BY-ND 3.0 TW',
            ),
          ]),
        ),
      );

      expect(find.textContaining('萌典'), findsWidgets);
      expect(find.textContaining('CC BY-ND 3.0 TW'), findsOneWidget);
    });
  });

  group('詞條內容', () {
    testWidgets('拼音 pin1 yin1 顯示為 pīn yīn', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([
            _outcome(
              'a',
              entries: [
                _entry('拼音', pronunciation: 'pin1 yin1', partOfSpeech: '名詞'),
              ],
            ),
          ]),
        ),
      );

      expect(find.text('拼音'), findsWidgets);
      expect(find.text('pīn yīn'), findsOneWidget);
      expect(find.text('名詞'), findsOneWidget);
    });

    testWidgets('沒有拼音的詞條不顯示拼音列', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([
            _outcome('a', entries: [_entry('無拼音')]),
          ]),
        ),
      );

      expect(find.text('無拼音'), findsWidgets);
      expect(find.text('pīn yīn'), findsNothing);
    });

    testWidgets('詞條依序帶 dictionary_lookup_entry_<index> Key', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([
            _outcome(
              'a',
              entries: [_entry('一'), _entry('二')],
            ),
          ]),
        ),
      );

      expect(find.byKey(const Key('dictionary_lookup_entry_0')), findsOneWidget);
      expect(find.byKey(const Key('dictionary_lookup_entry_1')), findsOneWidget);
    });
  });

  group('E-Ink', () {
    testWidgets('等待中顯示查詢中文字，不出現 CircularProgressIndicator',
        (tester) async {
      final completer = Completer<DictionaryLookupResponse>();
      await _pumpSheet(
        tester,
        response: completer.future,
        isEinkMode: true,
        settle: false,
      );
      await tester.pump();

      expect(find.text('查詢中…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('一般模式等待中出現 CircularProgressIndicator', (tester) async {
      final completer = Completer<DictionaryLookupResponse>();
      await _pumpSheet(tester, response: completer.future, settle: false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('查詢中…'), findsNothing);
    });

    testWidgets('選中分段有加粗邊框，且頁面沒有 AnimatedXxx', (tester) async {
      await _pumpSheet(
        tester,
        isEinkMode: true,
        response: Future.value(
          _completed([
            _outcome('a', name: '甲典', entries: [_entry('甲詞')]),
            _outcome('b', name: '乙典', entries: [_entry('乙詞')]),
          ]),
        ),
      );

      final segmented = tester.widget<SegmentedButton<String>>(
        find.byKey(const Key('dictionary_lookup_segments')),
      );
      final side = segmented.style!.side!.resolve({WidgetState.selected});
      expect(side, isNotNull);
      expect(side!.width, 2);

      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(find.byType(AnimatedContainer), findsNothing);
    });
  });

  group('錯誤與版面', () {
    testWidgets('response 丟出例外時顯示失敗訊息', (tester) async {
      final completer = Completer<DictionaryLookupResponse>();
      await _pumpSheet(tester, response: completer.future, settle: false);
      await tester.pump();

      completer.completeError(StateError('壞掉'));
      await tester.pump();

      expect(find.byKey(const Key('dictionary_lookup_failed')), findsOneWidget);
      expect(find.text(_failedMessage), findsOneWidget);
    });

    testWidgets('短內容時面板不撐滿，長內容可捲動且不丟 RenderFlex 例外',
        (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([
            _outcome('a', entries: [_entry('短')]),
          ]),
        ),
      );

      final screenHeight = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      expect(
        tester.getSize(find.byType(DictionaryLookupSheet)).height,
        lessThan(screenHeight),
      );

      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([
            _outcome(
              'a',
              entries: [
                for (var i = 0; i < 80; i++) _entry('長詞條 $i', body: '釋義 $i'),
              ],
            ),
          ]),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('字典設定入口', () {
    testWidgets('onOpenSettings 為 null 時不顯示連結', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(_completed([], hasEnabledDictionary: false)),
      );

      expect(find.text('前往字典設定'), findsNothing);
    });

    testWidgets('onOpenSettings 非 null 時顯示且可觸發', (tester) async {
      var tapped = 0;
      await _pumpSheet(
        tester,
        onOpenSettings: () => tapped++,
        response: Future.value(_completed([], hasEnabledDictionary: false)),
      );

      final link = find.text('前往字典設定');
      expect(link, findsOneWidget);
      await tester.tap(link);
      expect(tapped, 1);
    });
  });

  group('show()', () {
    testWidgets('只呼叫一次 service.lookup', (tester) async {
      final service = FakeDictionaryService(
        response: _completed([
          _outcome('a', entries: [_entry('詞條甲')]),
        ]),
      );

      await pumpLocalizedWidget(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => DictionaryLookupSheet.show(
              context,
              selectedText: '詞',
              service: service,
              isEinkMode: false,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(service.calls, ['詞']);
      expect(find.byType(DictionaryLookupSheet), findsOneWidget);
      expect(find.text('詞條甲'), findsOneWidget);
    });
  });
}
