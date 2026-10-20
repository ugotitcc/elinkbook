import 'dart:async';

import 'package:elinkbook/dictionary/dictionary_service.dart';
import 'package:elinkbook/dictionary/lookup_text_normalizer.dart';
import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/models/lookup_request.dart';
import 'package:elinkbook/dictionary/models/lookup_result.dart';
import 'package:elinkbook/screens/widgets/dictionary_lookup_sheet.dart';
import 'package:elinkbook/screens/widgets/eb_sheet_shell.dart';
import 'package:elinkbook/screens/widgets/mdx_entry_view.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_dictionary_service.dart';
import '../../support/pump_localized_widget.dart';

/// 捕捉 Navigator 實際推入的 Route，用來檢查面板的遮罩顏色
/// （比照 `eb_sheet_shell_test.dart` 的既有手法）。
class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
  }
}

const _failedMessage =
    '這本字典查詢失敗。請稍後再試，或到字典設定確認這本字典。';

DictionaryEntry _entry(
  String headword, {
  String? pronunciation,
  String? partOfSpeech,
  String body = '釋義內容',
  EntryBodyKind bodyKind = EntryBodyKind.plainText,
}) =>
    DictionaryEntry(
      sourceId: 'src',
      headword: headword,
      pronunciation: pronunciation,
      partOfSpeech: partOfSpeech,
      body: body,
      bodyKind: bodyKind,
    );

/// 假的 MDX 詞條顯示元件：記下建構參數，畫面上只放一個可辨識的 Key。
class _FakeMdxEntryView extends StatelessWidget {
  const _FakeMdxEntryView();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(key: Key('fake_mdx_view'), child: Text('MDX 詞條'));
}

/// 收集每次建構 [MdxEntryViewConfig] 的參數，測試再用 `last` 觸發連結。
class _MdxRecorder {
  final List<MdxEntryViewConfig> configs = [];

  MdxEntryViewConfig get last => configs.last;

  Widget build(BuildContext context, MdxEntryViewConfig config) {
    configs.add(config);
    return const _FakeMdxEntryView();
  }
}

/// 建立 HTML 詞條（內容由 WebView 顯示）。
DictionaryEntry _htmlEntry(String headword, {String body = '<p>HTML 釋義</p>'}) =>
    _entry(headword, body: body, bodyKind: EntryBodyKind.html);

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
  MdxEntryViewBuilder? mdxEntryViewBuilder,
  Future<List<DictionaryEntry>> Function(String sourceId, String word)?
      lookupInSource,
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
                mdxEntryViewBuilder: mdxEntryViewBuilder,
                lookupInSource: lookupInSource,
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

/// 把面板放進真的 [EBSheetShell]（高度上限為螢幕 85%），用來驗證 HTML 詞條
/// 以 `Expanded` 撐滿剩餘高度、切回純文字後縮回。
Future<void> _pumpSheetInShell(
  WidgetTester tester, {
  required Future<DictionaryLookupResponse> response,
  MdxEntryViewBuilder? mdxEntryViewBuilder,
  Future<List<DictionaryEntry>> Function(String sourceId, String word)?
      lookupInSource,
}) async {
  await pumpLocalizedWidget(
    tester,
    Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: EBSheetShell(
          title: '查字典',
          child: DictionaryLookupSheet(
            selectedText: '詞',
            response: response,
            isEinkMode: false,
            mdxEntryViewBuilder: mdxEntryViewBuilder,
            lookupInSource: lookupInSource,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 把面板放上真的 modal route（`EBSheetShell.show`），才能用
/// `handlePopRoute()` 驗證系統返回與 `PopScope` 的互動。
Future<void> _pumpSheetOnModalRoute(
  WidgetTester tester, {
  required Future<DictionaryLookupResponse> response,
  MdxEntryViewBuilder? mdxEntryViewBuilder,
  Future<List<DictionaryEntry>> Function(String sourceId, String word)?
      lookupInSource,
}) async {
  await pumpLocalizedWidget(
    tester,
    Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => EBSheetShell.show<void>(
            context,
            title: '查字典',
            builder: (context) => DictionaryLookupSheet(
              selectedText: '詞',
              response: response,
              isEinkMode: false,
              mdxEntryViewBuilder: mdxEntryViewBuilder,
              lookupInSource: lookupInSource,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
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
    testWidgets('面板顯示這次查詢的詞', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([
            _outcome('a', entries: [_entry('詞條甲')]),
          ]),
        ),
      );

      expect(
        find.byKey(const Key('dictionary_lookup_query_word')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dictionary_lookup_query_word')))
            .data,
        '詞',
      );
    });

    testWidgets('查無此詞時仍顯示查詢的詞', (tester) async {
      await _pumpSheet(
        tester,
        response: Future.value(
          _completed([_outcome('a', status: OutcomeStatus.notFound)]),
        ),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('dictionary_lookup_query_word')))
            .data,
        '詞',
      );
      expect(find.text('查無此詞'), findsOneWidget);
    });

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

    testWidgets('選中分段有加粗邊框，未選中的沒有，且頁面沒有 AnimatedXxx', (tester) async {
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

      final selected = tester.widget<Container>(
        find.byKey(const Key('dictionary_lookup_segment_selected_a')),
      );
      final border = (selected.decoration! as BoxDecoration).border! as Border;
      expect(border.top.width, 2);
      expect(border.left.width, 2);
      expect(
        find.byKey(const Key('dictionary_lookup_segment_selected_b')),
        findsNothing,
      );

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
    Future<_RecordingNavigatorObserver> openSheet(
      WidgetTester tester, {
      bool isEinkMode = false,
      AppTheme theme = AppTheme.light,
    }) async {
      final observer = _RecordingNavigatorObserver();
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
              isEinkMode: isEinkMode,
            ),
            child: const Text('open'),
          ),
        ),
        isEinkMode: isEinkMode,
        theme: theme,
        navigatorObservers: [observer],
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return observer;
    }

    testWidgets('E-Ink 模式遮罩透明，不把書頁壓黑', (tester) async {
      final observer = await openSheet(tester, isEinkMode: true);

      expect(observer.lastPushedRoute, isA<ModalBottomSheetRoute<void>>());
      final route = observer.lastPushedRoute! as ModalBottomSheetRoute<void>;
      expect(route.barrierColor, Colors.transparent);
    });

    testWidgets('深色主題遮罩透明，不把書頁壓黑', (tester) async {
      final observer = await openSheet(tester, theme: AppTheme.dark);

      final route = observer.lastPushedRoute! as ModalBottomSheetRoute<void>;
      expect(route.barrierColor, Colors.transparent);
    });

    testWidgets('一般模式維持預設遮罩', (tester) async {
      final observer = await openSheet(tester);

      final route = observer.lastPushedRoute! as ModalBottomSheetRoute<void>;
      expect(route.barrierColor, Colors.black54);
    });

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

  group('MDX 詞條顯示', () {
    LookupCompleted twoSegments() => _completed([
          _outcome('a', name: '乙典', entries: [_entry('純文字詞條')]),
          _outcome(
            'mdx',
            name: 'MDX 典',
            entries: [_htmlEntry('詞', body: '<p>原始 HTML</p>')],
          ),
        ]);

    testWidgets('選中 MDX 分段時只放一個 WebView 元件，切走後移除', (tester) async {
      final recorder = _MdxRecorder();
      await _pumpSheet(
        tester,
        mdxEntryViewBuilder: recorder.build,
        response: Future.value(twoSegments()),
      );

      // 預設選中第一個 found 的純文字分段。
      expect(find.byKey(const Key('fake_mdx_view')), findsNothing);

      await tester.tap(find.text('MDX 典'));
      await tester.pump();

      expect(find.byKey(const Key('fake_mdx_view')), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      expect(find.text('純文字詞條'), findsNothing);
      expect(recorder.last.sourceId, 'mdx');
      expect(recorder.last.html, contains('原始 HTML'));

      await tester.tap(find.text('乙典'));
      await tester.pump();

      expect(find.byKey(const Key('fake_mdx_view')), findsNothing);
      expect(find.text('純文字詞條'), findsOneWidget);
    });

    testWidgets('HTML 詞條撐滿面板高度，切回純文字分段後縮回', (tester) async {
      final recorder = _MdxRecorder();
      await _pumpSheetInShell(
        tester,
        mdxEntryViewBuilder: recorder.build,
        response: Future.value(twoSegments()),
      );

      await tester.tap(find.text('MDX 典'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final shellHeight = tester.getSize(find.byType(EBSheetShell)).height;
      expect(
        shellHeight,
        moreOrLessEquals(screenHeight * 0.85, epsilon: 1),
      );
      final htmlHeight =
          tester.getSize(find.byType(DictionaryLookupSheet)).height;
      // 面板扣掉外殼標題列後幾乎填滿 85% 的高度。
      expect(htmlHeight, greaterThan(shellHeight * 0.7));

      await tester.tap(find.text('乙典'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final plainHeight =
          tester.getSize(find.byType(DictionaryLookupSheet)).height;
      expect(plainHeight, lessThan(htmlHeight));
      expect(plainHeight, lessThan(screenHeight * 0.5));
    });

    testWidgets('詞條連結查得到時顯示新詞條，返回鈕可逐層回退', (tester) async {
      final recorder = _MdxRecorder();
      final calls = <({String sourceId, String word})>[];
      var results = <DictionaryEntry>[_htmlEntry('天地', body: '<p>第二層</p>')];

      await _pumpSheet(
        tester,
        mdxEntryViewBuilder: recorder.build,
        lookupInSource: (sourceId, word) async {
          calls.add((sourceId: sourceId, word: word));
          return results;
        },
        response: Future.value(
          _completed([
            _outcome(
              'mdx',
              name: 'MDX 典',
              entries: [_htmlEntry('詞', body: '<p>第一層</p>')],
            ),
          ]),
        ),
      );

      expect(find.byKey(const Key('dictionary_lookup_back')), findsNothing);
      expect(recorder.last.html, contains('第一層'));

      recorder.last.onEntryLink('天地');
      await tester.pumpAndSettle();

      expect(calls, [(sourceId: 'mdx', word: '天地')]);
      expect(find.byKey(const Key('dictionary_lookup_back')), findsOneWidget);
      expect(_queryWord(tester), '天地');
      expect(recorder.last.html, contains('第二層'));

      // 第二層：再點一次連結，堆疊變成兩層。
      results = [_htmlEntry('第三', body: '<p>第三層</p>')];
      recorder.last.onEntryLink('第三');
      await tester.pumpAndSettle();

      expect(_queryWord(tester), '第三');

      await tester.tap(find.byKey(const Key('dictionary_lookup_back')));
      await tester.pump();

      expect(_queryWord(tester), '天地');
      expect(recorder.last.html, contains('第二層'));
      expect(find.byKey(const Key('dictionary_lookup_back')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dictionary_lookup_back')));
      await tester.pump();

      expect(_queryWord(tester), '詞');
      expect(recorder.last.html, contains('第一層'));
      expect(find.byKey(const Key('dictionary_lookup_back')), findsNothing);
    });

    testWidgets('連結查無詞條時顯示提示、不推入堆疊', (tester) async {
      final recorder = _MdxRecorder();
      await _pumpSheet(
        tester,
        mdxEntryViewBuilder: recorder.build,
        lookupInSource: (sourceId, word) async => const [],
        response: Future.value(
          _completed([
            _outcome('mdx', name: 'MDX 典', entries: [_htmlEntry('詞')]),
          ]),
        ),
      );

      recorder.last.onEntryLink('查無');
      await tester.pumpAndSettle();

      expect(find.text('找不到這個詞條'), findsOneWidget);
      expect(find.byKey(const Key('dictionary_lookup_back')), findsNothing);
      expect(find.byKey(const Key('fake_mdx_view')), findsOneWidget);
    });

    testWidgets('切換分段會清空返回堆疊與提示', (tester) async {
      final recorder = _MdxRecorder();
      await _pumpSheet(
        tester,
        mdxEntryViewBuilder: recorder.build,
        lookupInSource: (sourceId, word) async => [_htmlEntry('天地')],
        response: Future.value(twoSegments()),
      );

      await tester.tap(find.text('MDX 典'));
      await tester.pump();
      recorder.last.onEntryLink('天地');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary_lookup_back')), findsOneWidget);

      await tester.tap(find.text('乙典'));
      await tester.pump();
      await tester.tap(find.text('MDX 典'));
      await tester.pump();

      expect(find.byKey(const Key('dictionary_lookup_back')), findsNothing);
      expect(find.text('找不到這個詞條'), findsNothing);
      expect(_queryWord(tester), '詞');
    });

    testWidgets('系統返回先回退詞條，堆疊空了才關閉面板', (tester) async {
      final recorder = _MdxRecorder();
      await _pumpSheetOnModalRoute(
        tester,
        mdxEntryViewBuilder: recorder.build,
        lookupInSource: (sourceId, word) async => [_htmlEntry('天地')],
        response: Future.value(
          _completed([
            _outcome('mdx', name: 'MDX 典', entries: [_htmlEntry('詞')]),
          ]),
        ),
      );

      recorder.last.onEntryLink('天地');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictionary_lookup_back')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(DictionaryLookupSheet), findsOneWidget);
      expect(_queryWord(tester), '詞');
      expect(find.byKey(const Key('dictionary_lookup_back')), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(DictionaryLookupSheet), findsNothing);
    });

    testWidgets('E-Ink 模式的 MDX 詞條沒有動畫元件', (tester) async {
      final recorder = _MdxRecorder();
      await _pumpSheet(
        tester,
        isEinkMode: true,
        mdxEntryViewBuilder: recorder.build,
        response: Future.value(
          _completed([
            _outcome('mdx', name: 'MDX 典', entries: [_htmlEntry('詞')]),
          ]),
        ),
      );

      expect(find.byKey(const Key('fake_mdx_view')), findsOneWidget);
      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(find.byType(AnimatedContainer), findsNothing);
      expect(find.byType(AnimatedOpacity), findsNothing);
    });
  });
}

String? _queryWord(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('dictionary_lookup_query_word')))
    .data;
