# Issue 4：手動導覽自動暫停與恢復播放 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 朗讀中使用者手動翻頁/捲動/跳章時自動暫停並清除舊高亮；不論是「手動導覽後恢復播放」還是「從未開始朗讀、直接按下播放鍵」，朗讀都必須從畫面目前實際顯示的位置開始，不再固定從章節第一句開始（2026-08-27 Issue 3 真機驗收發現後者屬同一根因，已併入本 Issue 範圍）。

**Architecture:** 新增一個 JS↔Dart 反向查找橋接：`main.js` 新增 `window.lookupTtsSegmentIndex(visibleCfi, segmentCfis)`，重用 `epubcfi.js` 既有匯出的 `compare()`（CFI 排序比較）依「畫面目前可視位置」在已知朗讀段清單中找出對應或緊隨其後的第一個索引——不重新實作 CFI 解析/排序邏輯，也不新建 `TtsTimeline` 類別（`spec.md` 原文提及的 `TtsTimeline` 是 Phase 1 MVP 已捨棄的設計，見 `tts_controller.dart` 既有 class doc「Phase 1 MVP 簡化」段落；本計畫延續同一個已拍板的簡化決策，直接把反向查找收斂為 `TtsController` 的一個可選 callback，不算新的偏離）。`TtsController` 新增可選建構參數 `lookupStartIndex`，`play()` 從 `idle` 狀態播放時改用它決定起始段落（未提供則退回既有的第 0 段行為，向後相容）；新增 `handleExternalPositionChange()`，供 `ReaderScreen` 在既有 `onLocatorChanged` 回呼內無條件呼叫——`TtsController` 目前架構下從未主動觸發任何導覽（只疊加高亮，不移動畫面），故每一次 `onLocatorChanged` 事件必然是使用者手動導覽，不需要額外判斷「是否為 TTS 自身觸發」。`handleExternalPositionChange()` 把狀態完全重設回 `idle`（而非停在 `paused`）並清空段落清單／清除高亮，讓「手動導覽後恢復播放」與「首次播放」自然共用同一段 `lookupStartIndex` 起始邏輯，不需要另外維護一個「暫停原因」旗標。

**Tech Stack:** 沿用既有 `TtsController`/`FoliateReaderView`/`main.js` JS↔Dart bridge，無新增套件依賴；新增對 vendored `epubcfi.js` 既有匯出函式 `compare()` 的 import（未修改 `epubcfi.js` 本身，符合 ADR 0011）。

**Spec:** `docs/epics/epic-34-tts-readalong/issues.md`「Issue 4」（含 2026-08-27 追加範圍段落）；`docs/epics/epic-34-tts-readalong/spec.md`「Implementation Decisions」`TtsTimeline` 反向查找決策（本計畫以 `TtsController` 直接吸收該能力，見上方 Architecture 說明的既定簡化）；`docs/epics/epic-34-tts-readalong/epic.md` 2026-08-27 開發記錄（真機驗收發現的根因分析）。

## Global Constraints

- `TtsController` 保持格式無關、完全不知道 `FoliateReaderView`／WebView 存在——所有 JS 橋接呼叫（`lookupTtsSegmentIndex`）一律由 `ReaderScreen` 透過注入的 callback 完成，不得讓 `TtsController` 直接依賴 `FoliateReaderView`（比照既有 `loadSegments`／`onHighlightSegment` 的既有解耦模式）。
- 不修改任何 vendored `foliate-js` 檔案（`view.js`／`overlayer.js`／`epubcfi.js`／`epub.js` 等）——只 `import` `epubcfi.js` 既有匯出的 `compare()`，不編輯該檔案內容；`main.js` 是本專案自有整合層，可以直接編輯。
- 手動導覽觸發時須清除舊高亮（審查 `review-issues.md` Important #1，`onHighlightSegment?.call(null)`），不留殘影——重用 Issue 3 已建立的 `onHighlightSegment` 回呼，不新建平行的高亮清除機制。
- 不做上一句/下一句/語速調整（Issue 5 範圍）、不做背景播放/`audio_service`（Issue 7 範圍）、不做 Mini Player 視覺（Issue 6 範圍）。
- 新增/修改的 Dart 檔案沿用既有扁平結構（`app/lib/reader/`，不建子目錄）；測試沿用既有檔案位置（`app/test/reader/tts_controller_test.dart`／`app/test/reader/foliate_reader_view_test.dart`／`app/test/screens/reader_screen_test.dart`，皆為既有檔案新增測試，不新建檔案）。

---

### Task 1：`main.js`／`FoliateReaderView`——朗讀段反向查找橋接

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`
- Modify: `app/lib/reader/foliate_reader_view.dart`
- Test: `app/test/reader/foliate_reader_view_test.dart`（既有檔案，新增 group）

**Interfaces:**
- Consumes：`epubcfi.js` 既有匯出的 `compare(a, b)`（CFI 排序比較，`a`／`b` 可為 CFI 字串，回傳 `-1`/`0`/`1`，見 `epubcfi.js` 第 163-186 行）；既有 `_evaluate()`／`Completer`／`addJavaScriptHandler` 橋接慣例（`_requestTtsSegments` 已示範用法）
- Produces：`window.lookupTtsSegmentIndex(visibleCfi, segmentCfis)` 全域函式；`static Future<int> FoliateReaderView.lookupSegmentByCfi(GlobalKey<State<FoliateReaderView>> key, String visibleCfi, List<String> segmentCfis)`——供 Task 2／Task 3 使用

- [x] **Step 1：`main.js` 匯入 `compare()` 並新增 `window.lookupTtsSegmentIndex`**

在 `app/android/app/src/main/assets/foliate/main.js` 檔案最頂部，找到既有的 import 區塊：

```javascript
import { makeBook } from './view.js'
import { Overlayer } from './overlayer.js'
```

整段取代為：

```javascript
import { makeBook } from './view.js'
import { Overlayer } from './overlayer.js'
import { compare as compareCfi } from './epubcfi.js'
```

找到既有的 `window.clearTtsHighlight` 函式（第 444-448 行）：

```javascript
window.clearTtsHighlight = function () {
  if (!currentTtsAnnotationValue) return
  view.deleteAnnotation({ value: currentTtsAnnotationValue })
  currentTtsAnnotationValue = null
}
```

緊接其後（在下一段 `/** 主動清除目前的原生文字選取狀態...` 註解之前）新增：

```javascript
/**
 * 依「畫面目前可視位置」cfi 反查對應或緊隨其後的第一個朗讀段索引
 * （epic-34-tts-readalong Issue 4，2026-08-27 Issue 3 真機驗收追加範圍：
 * 首次播放與手動導覽後恢復播放皆須從畫面目前位置開始，見 issues.md
 * Issue 4「來源」欄位）。[segmentCfis] 為 Dart 端目前持有、已依文件順序
 * 排序的朗讀段 cfi 陣列（[window.buildTtsSegments()] 既有輸出順序），
 * 本函式直接重用 epubcfi.js 既有匯出的 compareCfi()（CFI 排序比較），不
 * 重新實作 CFI 解析/排序邏輯（未修改 epubcfi.js 本身，符合 ADR 0011）。
 *
 * 找不到「cfi 大於等於 visibleCfi」的段落時（使用者目前位置已在本章節
 * 最後一段之後），回傳最後一段索引，而非固定回傳 0 或 -1；[segmentCfis]
 * 為空陣列時回傳 -1（呼叫端 Dart 端不應該在段落清單為空時呼叫本函式，
 * 這裡僅作防禦，Dart 端靜態 helper 收到 -1 時會自行 clamp 回 0）。
 */
window.lookupTtsSegmentIndex = function (visibleCfi, segmentCfis) {
  try {
    let index = -1
    if (segmentCfis.length > 0) {
      index = segmentCfis.findIndex((cfi) => compareCfi(cfi, visibleCfi) >= 0)
      if (index === -1) index = segmentCfis.length - 1
    }
    window.flutter_inappwebview.callHandler('onTtsSegmentIndexReady', index)
  } catch (e) {
    window.flutter_inappwebview.callHandler('onTtsSegmentIndexReady', -1)
  }
}
```

- [x] **Step 2：`FoliateReaderView` 新增靜態 helper 與內部橋接管線**

在 `app/lib/reader/foliate_reader_view.dart` 找到以下既有的 `loadTtsSegments` 靜態方法：

```dart
  static Future<List<TtsSegmentCfi>> loadTtsSegments(
    GlobalKey<State<FoliateReaderView>> key,
    int sectionIndex,
  ) async {
    final state = key.currentState;
    if (state is! _FoliateReaderViewState) return const [];
    return state._requestTtsSegments(sectionIndex);
  }
```

緊接其後（在下一段 `static void setDecorations(...)` 之前）新增：

```dart
  /// 依「畫面目前可視位置」cfi 反查對應或緊隨其後的第一個朗讀段索引
  /// （epic-34-tts-readalong Issue 4）。[segmentCfis] 為呼叫端
  /// （[TtsController] 透過 [ReaderScreen] 注入的 `lookupStartIndex`
  /// callback）目前持有、已依文件順序排序的朗讀段 cfi 清單。WebView 尚未
  /// 就緒／JS 端回傳 -1（無法判斷順序，例如 [segmentCfis] 為空）／5 秒
  /// 逾時，皆安全退回 `0`（從第一段開始），不拋出例外——比照
  /// [loadTtsSegments] 逾時時退回空清單的既有優雅退回慣例。
  static Future<int> lookupSegmentByCfi(
    GlobalKey<State<FoliateReaderView>> key,
    String visibleCfi,
    List<String> segmentCfis,
  ) async {
    final state = key.currentState;
    if (state is! _FoliateReaderViewState) return 0;
    final index = await state._requestTtsSegmentIndex(visibleCfi, segmentCfis);
    return index < 0 ? 0 : index;
  }
```

在 `_FoliateReaderViewState` 類別內，找到既有的 `Completer<List<TtsSegmentCfi>>? _pendingTtsSegments;` 欄位，緊接其後新增：

```dart
  Completer<int>? _pendingTtsSegmentIndex;
```

找到既有的 `_requestTtsSegments()` 方法：

```dart
  Future<List<TtsSegmentCfi>> _requestTtsSegments(int sectionIndex) {
    if (_controller == null) return Future.value(const []);
    final completer = Completer<List<TtsSegmentCfi>>();
    _pendingTtsSegments = completer;
    _evaluate('window.buildTtsSegments($sectionIndex)');
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _pendingTtsSegments = null;
        return const [];
      },
    );
  }
```

緊接其後（在下一段 `Future<void> _onWebViewCreated(...)` 之前）新增：

```dart
  Future<int> _requestTtsSegmentIndex(
    String visibleCfi,
    List<String> segmentCfis,
  ) {
    if (_controller == null) return Future.value(0);
    final completer = Completer<int>();
    _pendingTtsSegmentIndex = completer;
    _evaluate(
      'window.lookupTtsSegmentIndex(${jsonEncode(visibleCfi)}, ${jsonEncode(segmentCfis)})',
    );
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _pendingTtsSegmentIndex = null;
        return 0;
      },
    );
  }
```

在 `_onWebViewCreated()` 內，找到既有的 `onTtsSegmentsReady` handler 註冊區塊：

```dart
    controller.addJavaScriptHandler(
      handlerName: 'onTtsSegmentsReady',
      callback: (args) {
        final completer = _pendingTtsSegments;
        _pendingTtsSegments = null;
        final json = args.length > 1 ? args[1] as String : '[]';
        completer?.complete(parseTtsSegments(json));
      },
    );
```

緊接其後（在下一段 `onSelectionChanged` handler 註冊之前）新增：

```dart
    controller.addJavaScriptHandler(
      handlerName: 'onTtsSegmentIndexReady',
      callback: (args) {
        final completer = _pendingTtsSegmentIndex;
        _pendingTtsSegmentIndex = null;
        final index = args.isNotEmpty ? (args[0] as num).toInt() : 0;
        completer?.complete(index);
      },
    );
```

- [x] **Step 3：main.js regression guard 測試**

在 `app/test/reader/foliate_reader_view_test.dart` 找到 Issue 3 新增的 `group('main.js 朗讀高亮 regression guard（epic-34-tts-readalong Issue 3，ADR 0026）', ...)` 結尾的 `});`，在它之後、`group('mounted guard / dispose race'...)` 之前，新增：

```dart
  group('main.js 朗讀段反向查找 regression guard（epic-34-tts-readalong Issue 4）', () {
    late String mainJsSource;

    setUpAll(() {
      mainJsSource = File('android/app/src/main/assets/foliate/main.js')
          .readAsStringSync();
    });

    test('main.js 匯入 epubcfi.js 既有 compare()，不重新實作 CFI 排序邏輯', () {
      expect(
        mainJsSource
            .contains("import { compare as compareCfi } from './epubcfi.js'"),
        isTrue,
        reason: 'main.js 必須重用 epubcfi.js 既有匯出的 compare()（CFI 排序'
            '比較），不得重新實作一套 CFI 解析/排序邏輯（風險高、容易與 '
            'epubcfi.js 本身的判斷不一致，違反 ADR 0011「不修改任何 '
            'vendored 檔案」的精神——重新實作等於繞過既有正確實作）。',
      );
    });

    test('window.lookupTtsSegmentIndex 使用 compareCfi 尋找第一個 cfi >= visibleCfi 的段落，找不到時退回最後一段',
        () {
      expect(
        mainJsSource.contains('window.lookupTtsSegmentIndex = function'),
        isTrue,
        reason: 'main.js 內找不到 window.lookupTtsSegmentIndex——朗讀段反向'
            '查找橋接函式缺失。',
      );
      expect(
        mainJsSource.contains(
          'segmentCfis.findIndex((cfi) => compareCfi(cfi, visibleCfi) >= 0)',
        ),
        isTrue,
      );
      expect(
        mainJsSource.contains('index = segmentCfis.length - 1'),
        isTrue,
        reason: '找不到「cfi 大於等於 visibleCfi」的段落時（使用者目前位置'
            '已在本章節最後一段之後），須退回最後一段索引，而非固定回傳 '
            '0 或 -1，否則使用者在章節結尾按播放會被拉回章節開頭。',
      );
    });
  });

```

- [x] **Step 4：跑測試**

```
flutter test test/reader/foliate_reader_view_test.dart
```

Expected：全數 PASS（含新增的 2 個 regression guard 測試）。

```
flutter analyze
```

Expected：`No issues found!`

**注意（測試涵蓋範圍的誠實邊界）**：上面兩則測試只驗證 `main.js` 原始碼字串包含正確的邏輯片段（比照 Issue 3 Task 1 既有慣例），不驗證 `compareCfi()`／`findIndex()` 在真實瀏覽器環境下對真實 CFI 字串的排序結果是否正確——`flutter_test` 環境無 JS 執行能力，`window.lookupTtsSegmentIndex()` 的實際反向查找正確性須真機手動驗證（見本計畫「測試策略總結」）。

- [x] **Step 5：Commit**

```
git add app/android/app/src/main/assets/foliate/main.js app/lib/reader/foliate_reader_view.dart app/test/reader/foliate_reader_view_test.dart
git commit -m "feat(epic-34): main.js/FoliateReaderView 新增朗讀段反向查找橋接（Issue 4 Task 1）"
```

---

### Task 2：`TtsController`——反向查找起始段落＋手動導覽重置（TDD）

**Files:**
- Modify: `app/lib/reader/tts_controller.dart`
- Test: `app/test/reader/tts_controller_test.dart`（既有檔案，新增測試案例）

**Interfaces:**
- Consumes：既有 `TtsSegmentCfi`（`tts_segment_cfi.dart`）
- Produces：`TtsController` 建構子新增可選具名參數 `Future<int> Function(List<TtsSegmentCfi> segments)? lookupStartIndex`；新增公開方法 `void handleExternalPositionChange()`——皆供 Task 3 的 `ReaderScreen` 使用

- [x] **Step 1：寫失敗測試**

在 `app/test/reader/tts_controller_test.dart` 檔案結尾（最後一個 `test()` 之後、`}` 之前）新增：

```dart
  test('play() 從 idle 開始時，若提供 lookupStartIndex，使用其回傳值作為起始段落（epic-34-tts-readalong Issue 4）',
      () async {
    var lookupCalledWith = const <TtsSegmentCfi>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      lookupStartIndex: (segs) async {
        lookupCalledWith = segs;
        return 1;
      },
    );

    await controller.play();

    expect(lookupCalledWith, segments);
    expect(controller.currentIndex, 1);
    expect(provider.synthesizedTexts, ['第二句。']);
  });

  test('lookupStartIndex 回傳超出範圍的索引時，安全 clamp 回第 0 段', () async {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      lookupStartIndex: (segs) async => 99,
    );

    await controller.play();

    expect(controller.currentIndex, 0);
    expect(provider.synthesizedTexts, ['第一句。']);
  });

  test('lookupStartIndex 回傳負數（找不到對應段落）時，安全 clamp 回第 0 段', () async {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      lookupStartIndex: (segs) async => -1,
    );

    await controller.play();

    expect(controller.currentIndex, 0);
    expect(provider.synthesizedTexts, ['第一句。']);
  });

  test('handleExternalPositionChange() 於 idle 狀態下呼叫為 no-op，不觸發 notifyListeners',
      () {
    final highlighted = <TtsSegmentCfi?>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: highlighted.add,
    );
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    controller.handleExternalPositionChange();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(notifyCount, 0);
    expect(highlighted, isEmpty);
    expect(player.callLog, isEmpty);
  });

  test('handleExternalPositionChange() 於 playing 狀態下呼叫，重設為 idle 並清空段落/清除高亮/暫停播放器',
      () async {
    final highlighted = <TtsSegmentCfi?>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: highlighted.add,
    );
    await controller.play();
    expect(controller.status, TtsPlaybackStatus.playing);

    controller.handleExternalPositionChange();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
    expect(controller.segments, isEmpty);
    expect(highlighted.last, isNull);
    expect(player.callLog.last, 'pause');
  });

  test('handleExternalPositionChange() 於 paused 狀態下呼叫，同樣重設為 idle', () async {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
    );
    await controller.play();
    controller.pause();
    expect(controller.status, TtsPlaybackStatus.paused);

    controller.handleExternalPositionChange();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.segments, isEmpty);
  });

  test('handleExternalPositionChange() 重設後再次 play()，重新呼叫 loadSegments() 並套用 lookupStartIndex（與首次播放共用同一路徑）',
      () async {
    var loadSegmentsCallCount = 0;
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async {
        loadSegmentsCallCount++;
        return segments;
      },
      lookupStartIndex: (segs) async => 1,
    );

    await controller.play();
    expect(loadSegmentsCallCount, 1);
    expect(controller.currentIndex, 1);

    controller.handleExternalPositionChange();
    await controller.play();

    expect(loadSegmentsCallCount, 2);
    expect(controller.currentIndex, 1);
  });

  test('handleExternalPositionChange() 於 dispose() 後呼叫不拋出例外、不觸發 notifyListeners（審查 review-plan-issue-4.md Important #1）',
      () async {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
    );
    await controller.play();
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);
    controller.dispose();

    expect(() => controller.handleExternalPositionChange(), returnsNormally);
    expect(notifyCount, 0);
  });
```

- [x] **Step 2：跑測試確認失敗**

```
flutter test test/reader/tts_controller_test.dart
```

Expected：FAIL（`TtsController` 建構子尚未接受 `lookupStartIndex` 具名參數、`handleExternalPositionChange` 方法不存在，編譯錯誤）。

- [x] **Step 3：實作**

在 `app/lib/reader/tts_controller.dart` 找到以下既有欄位/建構子：

```dart
  /// 朗讀段切換時呼叫（epic-34-tts-readalong Issue 3，spec.md「高亮渲染」／
  /// ADR 0026）：帶入即將開始朗讀的 [TtsSegmentCfi]，或在播放結束/合成失敗
  /// 導致重設回 idle 時帶入 `null` 通知呼叫端清除高亮。呼叫端
  /// （[ReaderScreen]）注入實際呼叫 `FoliateReaderView.showTtsHighlight()`/
  /// `clearTtsHighlight()` 的邏輯——本類別完全不知道 `FoliateReaderView`
  /// 或高亮如何渲染，只負責在正確時機通知「現在該顯示哪一段」，比照
  /// [loadSegments] 既有的解耦模式。切換到新段落時呼叫端不需要自行先清除
  /// 舊高亮再顯示新高亮——`window.showTtsHighlight()`（main.js）內部已處理
  /// 「顯示新的之前先清除舊的」，呼叫端只需忠實轉發每次收到的值。
  final void Function(TtsSegmentCfi? segment)? onHighlightSegment;

  TtsController({
    required this.provider,
    required this.player,
    required this.loadSegments,
    this.onHighlightSegment,
  }) {
    _completedSub = player.completedStream.listen((_) => _handleSegmentCompleted());
  }
```

整段取代為：

```dart
  /// 朗讀段切換時呼叫（epic-34-tts-readalong Issue 3，spec.md「高亮渲染」／
  /// ADR 0026）：帶入即將開始朗讀的 [TtsSegmentCfi]，或在播放結束/合成失敗
  /// 導致重設回 idle 時帶入 `null` 通知呼叫端清除高亮。呼叫端
  /// （[ReaderScreen]）注入實際呼叫 `FoliateReaderView.showTtsHighlight()`/
  /// `clearTtsHighlight()` 的邏輯——本類別完全不知道 `FoliateReaderView`
  /// 或高亮如何渲染，只負責在正確時機通知「現在該顯示哪一段」，比照
  /// [loadSegments] 既有的解耦模式。切換到新段落時呼叫端不需要自行先清除
  /// 舊高亮再顯示新高亮——`window.showTtsHighlight()`（main.js）內部已處理
  /// 「顯示新的之前先清除舊的」，呼叫端只需忠實轉發每次收到的值。
  final void Function(TtsSegmentCfi? segment)? onHighlightSegment;

  /// 依「畫面目前可視位置」決定 [play] 從 `idle` 開始播放時的起始段落索引
  /// （epic-34-tts-readalong Issue 4，2026-08-27 Issue 3 真機驗收追加範圍：
  /// 首次播放與手動導覽後恢復播放皆須套用，見 [handleExternalPositionChange]
  /// 文件註解）。呼叫端（[ReaderScreen]）注入實際呼叫
  /// `FoliateReaderView.lookupSegmentByCfi()` 的邏輯——本類別完全不知道
  /// `FoliateReaderView` 存在，比照 [loadSegments]／[onHighlightSegment]
  /// 既有的解耦模式。回傳值超出 [segments] 範圍（含負數）時，[play] 會
  /// 安全 clamp 回 `0`；未提供本參數時退回既有的「固定從第 0 段開始」
  /// 行為，向後相容既有呼叫端。
  final Future<int> Function(List<TtsSegmentCfi> segments)? lookupStartIndex;

  TtsController({
    required this.provider,
    required this.player,
    required this.loadSegments,
    this.onHighlightSegment,
    this.lookupStartIndex,
  }) {
    _completedSub = player.completedStream.listen((_) => _handleSegmentCompleted());
  }
```

找到以下既有的 `play()` 內 idle 分支（`// idle：第一次播放...` 之後的完整程式碼）：

```dart
    // idle：第一次播放，先載入目前章節的朗讀段。
    _isLoadingSegments = true;
    List<TtsSegmentCfi> loaded;
    try {
      loaded = await loadSegments();
    } finally {
      _isLoadingSegments = false;
    }
    if (_disposed) return;
    if (loaded.isEmpty) return; // 沒有可朗讀的內容，維持 idle。
    _segments = loaded;
    _currentIndex = 0;
    await _playCurrentSegment();
  }
```

整段取代為：

```dart
    // idle：第一次播放（或手動導覽觸發重置後的播放，見
    // handleExternalPositionChange），先載入目前章節的朗讀段。
    _isLoadingSegments = true;
    List<TtsSegmentCfi> loaded;
    try {
      loaded = await loadSegments();
    } finally {
      _isLoadingSegments = false;
    }
    if (_disposed) return;
    if (loaded.isEmpty) return; // 沒有可朗讀的內容，維持 idle。
    _segments = loaded;
    // 起始段落改由 lookupStartIndex 依「畫面目前可視位置」決定
    // （epic-34-tts-readalong Issue 4），不再固定從第 0 段開始——這個
    // 分支同時涵蓋「使用者從未開始朗讀，直接按下播放鍵」與「手動導覽
    // 觸發自動暫停（見 handleExternalPositionChange）後再次按下播放鍵」
    // 兩種情境，因為後者也會先把狀態重設回 idle，兩者共用同一段程式碼
    // 路徑。未提供 lookupStartIndex 時（例如尚未接上 ReaderScreen 的
    // 測試情境）退回既有的「從第 0 段開始」行為，向後相容。
    final startIndex =
        lookupStartIndex == null ? 0 : await lookupStartIndex!(loaded);
    if (_disposed) return;
    _currentIndex =
        (startIndex >= 0 && startIndex < _segments.length) ? startIndex : 0;
    await _playCurrentSegment();
  }
```

在 `pause()` 方法之後（`_playCurrentSegment()` 方法之前）新增：

```dart
  /// 偵測到非 TTS 自身觸發的畫面位置變化時呼叫（epic-34-tts-readalong
  /// Issue 4，`issues.md`「手動導覽觸發暫停時須清除舊高亮」）——呼叫端
  /// （[ReaderScreen]）在既有 relocate 類事件（`onLocatorChanged`）內
  /// 無條件呼叫本方法即可，不需要自行判斷「是否為 TTS 自身觸發」：
  /// [TtsController] 在目前架構下從未呼叫任何導覽方法（只呼叫
  /// [onHighlightSegment] 疊加高亮，不移動畫面），故每一次
  /// `onLocatorChanged` 事件必然是使用者手動導覽（翻頁/捲動/跳章/開書）。
  ///
  /// 完全重設回 [TtsPlaybackStatus.idle]（而非停在 [TtsPlaybackStatus.paused]）
  /// ——不只是暫停播放，是刻意清空 [_segments]／[_currentIndex]：手動導覽
  /// 後使用者可能已經跳到不同章節，舊的朗讀段清單已經不適用，下一次呼叫
  /// [play] 時必須重新呼叫 [loadSegments] 取得目前章節的朗讀段。這也讓
  /// 「首次播放」與「手動導覽後恢復播放」共用完全同一段起始邏輯（見
  /// [play] 內 `lookupStartIndex` 呼叫處），不需要另外維護一個「暫停原因」
  /// 的旗標。狀態本來就是 idle（尚未播放過，或已經自然播放完畢）時為
  /// no-op，避免每次翻頁都觸發不必要的 [notifyListeners]。
  ///
  /// [_disposed] 防護（審查 `review-plan-issue-4.md` Important #1）：
  /// `ReaderScreen` 銷毀過程中，WebView 的 JS 橋接回呼（`onLocatorChanged`）
  /// 可能在 `_ttsController?.dispose()` 已執行、但 `ReaderScreen` 自身尚未
  /// 完全 unmount 之間的窄縫觸發，若在此時仍呼叫 [notifyListeners]，
  /// `ChangeNotifier` 會拋出「used after being disposed」例外導致崩潰——
  /// 比照本類別其餘會呼叫 [notifyListeners] 的方法（[_playCurrentSegment]／
  /// [_handleSegmentCompleted]）皆已有的既有防護慣例。
  void handleExternalPositionChange() {
    if (_disposed) return;
    if (_status == TtsPlaybackStatus.idle) return;
    _status = TtsPlaybackStatus.idle;
    _currentIndex = -1;
    _segments = const [];
    // 同 pause()：player.pause() 若非同步才失敗，同步 try/catch 攔不到，
    // 改用 catchError 承接（比照既有 pause() 的既有修法）。
    try {
      player.pause().catchError((_) {});
    } catch (_) {}
    onHighlightSegment?.call(null);
    notifyListeners();
  }
```

- [x] **Step 4：跑測試確認通過**

```
flutter test test/reader/tts_controller_test.dart
```

Expected：全數 PASS（既有 22 個測試零回歸＋新增 8 個測試，共 30 個）。

```
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 5：Commit**

```
git add app/lib/reader/tts_controller.dart app/test/reader/tts_controller_test.dart
git commit -m "feat(epic-34): TtsController 新增反向查找起始段落與手動導覽重置（Issue 4 Task 2，TDD）"
```

---

### Task 3：`ReaderScreen` 接線——`lookupStartIndex` 注入＋`onLocatorChanged` 觸發重置

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`（既有檔案，新增測試案例）

**Interfaces:**
- Consumes：Task 1 的 `FoliateReaderView.lookupSegmentByCfi`；Task 2 的 `TtsController.lookupStartIndex`／`handleExternalPositionChange()`；既有 `extractCfi()`（`foliate_bridge_codec.dart`）、既有 `_epubPositionInfo`／`onLocatorChanged`
- Produces：`ReaderScreen` 內部接線（無新增公開 API）

- [x] **Step 1：`_ttsControllerOrNull` 新增 `lookupStartIndex` 注入**

在 `app/lib/screens/reader_screen.dart` 找到以下既有的 `_ttsControllerOrNull` getter（Issue 3 已新增 `onHighlightSegment`）：

```dart
  TtsController? get _ttsControllerOrNull {
    final provider = widget.ttsProvider;
    if (provider == null) return null;
    return _ttsController ??= TtsController(
      provider: provider,
      player: JustAudioTtsPlayer(),
      loadSegments: () async {
        final chapterIndex =
            extractChapterIndex(_epubPositionInfo?.locatorJson) ?? 0;
        return FoliateReaderView.loadTtsSegments(
          _foliateEpubReaderViewKey,
          chapterIndex,
        );
      },
      // 朗讀同步高亮（epic-34-tts-readalong Issue 3，ADR 0026）：只呼叫
      // 既有 Overlayer 管線，不引用 highlightsRepository/notesRepository。
      // vertical 旗標讀取 _resolved（目前實際生效的排版方向，含使用者
      // 手動切換的結果，非僅書本 CSS 宣告的 _autoDetectedWritingMode），
      // 比照本檔案既有頁首/頁尾直排判斷寫法（_resolved?.writingMode ==
      // WritingMode.vertical）。
      onHighlightSegment: (segment) {
        if (segment == null) {
          FoliateReaderView.clearTtsHighlight(_foliateEpubReaderViewKey);
        } else {
          FoliateReaderView.showTtsHighlight(
            _foliateEpubReaderViewKey,
            segment.cfi,
            vertical: _resolved?.writingMode == WritingMode.vertical,
          );
        }
      },
    );
  }
```

整段取代為：

```dart
  TtsController? get _ttsControllerOrNull {
    final provider = widget.ttsProvider;
    if (provider == null) return null;
    return _ttsController ??= TtsController(
      provider: provider,
      player: JustAudioTtsPlayer(),
      loadSegments: () async {
        final chapterIndex =
            extractChapterIndex(_epubPositionInfo?.locatorJson) ?? 0;
        return FoliateReaderView.loadTtsSegments(
          _foliateEpubReaderViewKey,
          chapterIndex,
        );
      },
      // 朗讀同步高亮（epic-34-tts-readalong Issue 3，ADR 0026）：只呼叫
      // 既有 Overlayer 管線，不引用 highlightsRepository/notesRepository。
      // vertical 旗標讀取 _resolved（目前實際生效的排版方向，含使用者
      // 手動切換的結果，非僅書本 CSS 宣告的 _autoDetectedWritingMode），
      // 比照本檔案既有頁首/頁尾直排判斷寫法（_resolved?.writingMode ==
      // WritingMode.vertical）。
      onHighlightSegment: (segment) {
        if (segment == null) {
          FoliateReaderView.clearTtsHighlight(_foliateEpubReaderViewKey);
        } else {
          FoliateReaderView.showTtsHighlight(
            _foliateEpubReaderViewKey,
            segment.cfi,
            vertical: _resolved?.writingMode == WritingMode.vertical,
          );
        }
      },
      // 反向查找起始段落（epic-34-tts-readalong Issue 4，2026-08-27
      // Issue 3 真機驗收追加範圍）：從 _epubPositionInfo 讀取畫面目前可視
      // 位置的 cfi（與 loadSegments 內的 extractChapterIndex 同一份
      // _epubPositionInfo，同一次 play() 呼叫序列內不會中途改變），找不到
      // （例如尚未收到任何 onLocatorChanged 事件）時回傳 0，交由
      // TtsController 既有的「從第 0 段開始」向後相容行為處理。
      lookupStartIndex: (segs) async {
        final visibleCfi = extractCfi(_epubPositionInfo?.locatorJson);
        if (visibleCfi == null) return 0;
        return FoliateReaderView.lookupSegmentByCfi(
          _foliateEpubReaderViewKey,
          visibleCfi,
          segs.map((s) => s.cfi).toList(),
        );
      },
    );
  }
```

- [x] **Step 2：`onLocatorChanged` 觸發手動導覽重置**

在 `app/lib/screens/reader_screen.dart` 找到以下既有的 `onLocatorChanged` 回呼（`_buildNativeView` 內 `FoliateReaderView(...)` 建構參數之一）：

```dart
          onLocatorChanged: (info) {
            if (!mounted) return;
            setState(() => _epubPositionInfo = info);
          },
```

整段取代為：

```dart
          onLocatorChanged: (info) {
            if (!mounted) return;
            setState(() => _epubPositionInfo = info);
            // 手動導覽自動暫停並清除舊高亮（epic-34-tts-readalong
            // Issue 4）：直接用既有的 nullable _ttsController 欄位（不用
            // _ttsControllerOrNull getter）——尚未曾建構過 TtsController
            // 時（TTS 從未被使用）保持 null，避免每次翻頁都意外觸發
            // lazy 建構；一旦已建構過，無條件呼叫即可，TtsController 自己
            // 在 idle 狀態下呼叫本方法是 no-op（見 handleExternalPositionChange
            // 文件註解，本檔案不需要自行判斷目前是否正在播放）。
            _ttsController?.handleExternalPositionChange();
          },
```

- [x] **Step 3：寫 widget test**

在 `app/test/screens/reader_screen_test.dart` 找到 Issue 3 新增的 `group('同步高亮跟隨（epic-34-tts-readalong Issue 3）', ...)` 結尾的 `});`，在它之後新增一個新的 group：

```dart
  group('手動導覽自動暫停與恢復播放（epic-34-tts-readalong Issue 4）', () {
    // 誠實測試邊界（比照 Issue 3 Task 3 既有慣例）：flutter_test 環境下
    // FoliateReaderView 的 _controller 恆為 null，TtsController.play() 的
    // loadSegments() 因此恆回傳空清單，永遠不會真正進入 playing 狀態——
    // 這裡驗證的是「onLocatorChanged 觸發手動導覽重置這段 wiring 不崩潰」
    // 這個結構性保證；handleExternalPositionChange() 實際重設狀態/清除
    // 高亮/清空段落的行為，由 tts_controller_test.dart（純 Dart，見
    // Task 2）完整涵蓋；真實「翻頁時朗讀自動暫停、恢復播放從新位置開始」
    // 的端到端正確性須真機手動驗證（見本計畫「測試策略總結」）。
    testWidgets(
        '提供 ttsProvider 時，onLocatorChanged 觸發（模擬手動翻頁）不崩潰，'
        '按播放鍵仍可正常運作', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_manual_nav',
            prefsManager: prefsManager,
            highlightsRepository: highlightsRepo,
            notesRepository: notesRepo,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final foliateView =
          tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
      foliateView.onPageRendered();
      foliateView.onLayoutResolved?.call(
        const EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: WritingMode.horizontal,
        ),
      );
      await tester.pump();
      await tester.pump();

      final buttonFinder =
          find.byKey(const Key('reader_tts_play_pause_button'));
      await tester.tap(buttonFinder);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 模擬手動翻頁：main.js 端 onLocatorChanged 事件（比照既有
      // foliate_bridge_codec_test.dart／reader_screen_test.dart 對這個
      // callback 的既有觸發方式，直接呼叫 widget 建構時傳入的 closure）。
      foliateView.onLocatorChanged?.call(
        const EpubPositionInfo(
          locatorJson: '{"cfi":"epubcfi(/6/6!/4/2,/1:0,/1:5)","index":1,"fraction":0.3}',
          progression: 0.3,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 翻頁後按鈕仍可正常點擊（未卡在任何非預期狀態）。
      await tester.tap(buttonFinder);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
```

若 `EpubPositionInfo` 的建構參數與上方寫法不符（例如欄位名稱、是否為必要參數），比照本檔案其他既有直接建構 `EpubPositionInfo(...)` 的測試案例（搜尋 `EpubPositionInfo(`）調整，不要憑空假設欄位。

- [x] **Step 4：跑測試確認全數通過、零回歸**

```
flutter test test/screens/reader_screen_test.dart
```

Expected：全數 PASS（含新增的 1 個測試，既有測試零回歸）。

```
flutter test
```

Expected：全專案測試全數通過，零回歸。

```
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 5：Commit**

```
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-34): ReaderScreen 接線——反向查找起始段落＋手動導覽重置（Issue 4 Task 3）"
```

---

## 測試策略總結（Self-Review 用，非額外步驟）

- **純 Dart 單元測試**（Task 2）：`TtsController.lookupStartIndex` 在 `play()` 從 idle 開始時正確套用、超出範圍/負數皆安全 clamp 回 0；`handleExternalPositionChange()` 在 idle/playing/paused 三種狀態下的正確行為（idle no-op、playing/paused 皆重設回 idle 並清空段落/清除高亮/暫停播放器）；重設後再次播放會重新呼叫 `loadSegments()` 並套用 `lookupStartIndex`，證明「首次播放」與「手動導覽後恢復播放」確實共用同一段程式碼路徑。
- **main.js regression guard**（Task 1，`foliate_reader_view_test.dart` 新增 group）：驗證 `main.js` 匯入 `epubcfi.js` 既有 `compare()`（不重新實作 CFI 排序）、`window.lookupTtsSegmentIndex` 的搜尋與「找不到時退回最後一段」邏輯確實存在於原始碼中——不驗證真實 CFI 字串的排序正確性（`flutter_test` 無 JS 執行環境）。
- **`ReaderScreen` widget test**（Task 3）：驗證 UI 接線層級在「模擬手動翻頁」情境下不崩潰、播放按鈕仍可正常操作。
- **無法自動化、須真機手動驗證的部分**（比照 Issue 2／Issue 3「測試策略總結」既有慣例，合併前建議至少手動跑一次）：
  1. 開一本已捲動到章節中段的 EPUB（例如透過書籤/上次閱讀進度跳轉到中間），直接按下播放鍵，確認朗讀從畫面目前顯示的句子開始，而非章節第一句（2026-08-27 真機驗收原始重現情境）。
  2. 朗讀中手動翻頁/捲動/跳章，確認播放自動暫停、畫面舊高亮同步清除、無殘留。
  3. 手動導覽後按下播放鍵，確認朗讀從畫面新位置對應的段落開始，不回跳到手動導覽前的舊音訊位置。
  4. 朗讀中手動翻到很遠的頁面又翻回原頁面（不按播放），確認沒有殘留過期高亮（Issue 3 遺留的邊界情況，本 Issue 的 `handleExternalPositionChange()` 已一併涵蓋）。
  5. 使用者純粹按下暫停鍵（未做任何手動導覽）後再按播放，確認行為維持 Issue 2 既有的「簡單恢復，不重新查找」——`handleExternalPositionChange()` 只在偵測到 `onLocatorChanged` 事件時觸發，純粹按暫停鍵不會經過這個路徑。
  6.（程式審查 `review-issue-4-code.md` Important #1 追加，已有自動化測試涵蓋，這裡是額外的真機體感確認）連續快速點兩下播放鍵，確認不會聽到同一句話被念兩次、也不會卡在奇怪狀態。**2026-08-28 真機驗證通過。**
  7.（程式審查 `review-issue-4-code.md` Important #2 追加，已有自動化測試涵蓋）按下播放鍵後、朗讀真正開始出聲之前的極短空檔立刻手動翻頁，確認朗讀不會念出翻頁前那個舊位置的內容。**2026-08-28 真機驗證通過。**

---

## Self-Review 檢查結果

- **Spec coverage**：`issues.md` Issue 4（含 2026-08-27 追加範圍）設計要點與驗收標準逐條對應——`TtsController` 訂閱位置變化事件並自動暫停（Task 3 `onLocatorChanged` 接線＋`handleExternalPositionChange()`）、反向查找介面（Task 1 `lookupTtsSegmentIndex`／Task 2 `lookupStartIndex`，以 `TtsController` 直接吸收取代文件原文的 `TtsTimeline`，理由見 Architecture 段落）、播放鍵恢復邏輯改用反向查找（Task 2 `play()` idle 分支）、手動導覽觸發暫停時清除舊高亮（Task 2 `handleExternalPositionChange()` 呼叫 `onHighlightSegment?.call(null)`）、首次播放同樣套用反向查找（Task 2 `handleExternalPositionChange()` 統一重設回 idle，與首次播放共用同一路徑）、`flutter analyze`/`flutter test` 全數通過（每個 Task 皆有驗證步驟）。無缺口。
- **Placeholder scan**：全文搜尋未發現「TBD」/「之後補」/「處理錯誤」等空話；所有程式碼步驟皆有完整程式碼區塊與精確的既有程式碼比對錨點。
- **Type consistency**：`TtsController.lookupStartIndex` 簽章（Task 2 定義 `Future<int> Function(List<TtsSegmentCfi> segments)?`）與 Task 3 `ReaderScreen` 呼叫端（`lookupStartIndex: (segs) async { ... }`，回傳 `int`）一致；`FoliateReaderView.lookupSegmentByCfi(key, visibleCfi, segmentCfis)` 簽章（Task 1 定義）與 Task 3 呼叫端一致；`window.lookupTtsSegmentIndex(visibleCfi, segmentCfis)`（Task 1 JS 定義）與 Task 1 `_evaluate()` 呼叫的 JS 字串一致；`handleExternalPositionChange()`（Task 2 定義，無參數、無回傳值）與 Task 3 `onLocatorChanged` 呼叫端一致。
