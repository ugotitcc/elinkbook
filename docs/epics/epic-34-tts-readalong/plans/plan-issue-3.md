# Issue 3：同步高亮跟隨（Read-along）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 朗讀進行中，畫面即時高亮目前朗讀的句子，直排/橫排皆正確跟隨；朗讀段切換或播放結束時正確清除前一個高亮，無殘留；高亮全程是暫態 UI 狀態，不寫入 `highlights`/`notes` 資料表（ADR 0026）。

**Architecture:** 重用既有 `Overlayer.add()`/`remove()`（`view.addAnnotation()`/`view.deleteAnnotation()` pipeline），不新建平行的高亮渲染機制、不修改任何 vendored `foliate-js` 檔案。`main.js` 新增 `window.showTtsHighlight(cfi, vertical)`/`window.clearTtsHighlight()` 兩個橋接函式，刻意使用 view.js 既有但本應用程式劃線/備註功能目前未使用到的 `foliate-note:` 前綴（`NOTE_PREFIX`）組成 annotation value，讓 Overlayer 內部 Map 的 key（`"foliate-note:" + cfi`）天然與劃線/備註直接以裸 cfi 當 key 的既有 key 空間分開，不需要新增任何欄位或修改任何 vendored 邏輯即可達成 ADR 0026「使用獨立 annotation key」的要求。`TtsController`（純 Dart，格式無關）新增可選的 `onHighlightSegment` callback，在朗讀段開始/切換時帶入該段的 `TtsSegmentCfi`、在播放自然結束或合成失敗重設回 idle 時帶入 `null`——完全不知道 `FoliateReaderView` 或 WebView 存在，比照既有 `loadSegments` 的解耦模式。`ReaderScreen` 是唯一知道「`FoliateReaderView` 怎麼呼叫」與「目前實際生效的排版方向是什麼」的地方，在 `onHighlightSegment` 回呼內轉呼叫新增的 `FoliateReaderView.showTtsHighlight()`/`clearTtsHighlight()` 靜態 helper。

**Tech Stack:** 沿用 Issue 2 既有的 `TtsController`/`FoliateReaderView`/`main.js` JS↔Dart bridge，無新增套件依賴。

**Spec:** `docs/epics/epic-34-tts-readalong/issues.md`「Issue 3」；`docs/epics/epic-34-tts-readalong/spec.md`「Implementation Decisions」高亮渲染段落；`docs/adr/0026-tts-highlight-ephemeral-not-persisted.md`。

## Global Constraints

- 不修改任何 vendored `foliate-js` 檔案（`view.js`／`overlayer.js`／`epubcfi.js`／`epub.js` 等）——`main.js` 是本專案自有整合層（見 CLAUDE.md），可以直接編輯。
- 高亮渲染須重用既有 `Overlayer.add()`/`remove()`（`view.addAnnotation()`/`view.deleteAnnotation()` pipeline），不得新建平行的 SVG/CustomPaint 疊加機制。
- TTS 高亮不得寫入 `highlights`/`notes` 資料表，`TtsController`／新增的 `onHighlightSegment` 回呼鏈路全程不得引用 `highlightsRepository`/`notesRepository`（ADR 0026）。
- 直排/橫排跟隨沿用既有 `Overlayer.highlight()` 的 `vertical`/`writingMode` 參數，不需要另外處理矩形轉向邏輯（`issues.md` Issue 3 設計要點）。
- 朗讀段切換時（非每次音訊 tick）才更新高亮——`TtsController` 現有架構天然滿足這一點：每個朗讀段各自合成為獨立音訊檔、依序播放（見 `tts_controller.dart` 既有 class doc），`onHighlightSegment` 只在段落開始/切換/結束時觸發，不對音訊播放位置做逐 tick 輪詢。
- 不新增 Mini Player 視覺（Issue 6 範圍）、不做 E-Ink 安全視窗（Issue 8 範圍）、不做「手動導覽觸發自動暫停時清除高亮」（Issue 4 範圍——本 Issue 驗收標準只涵蓋「播放結束/朗讀段切換」兩種清除時機，`TtsController.pause()` 本身不清除高亮）。
- 新增/修改的 Dart 檔案沿用既有扁平結構（`app/lib/reader/`，不建子目錄）；測試沿用既有檔案位置（`app/test/reader/tts_controller_test.dart`／`app/test/reader/foliate_reader_view_test.dart`／`app/test/screens/reader_screen_test.dart`，皆為既有檔案新增測試，不新建檔案）。

---

### Task 1：`main.js`——朗讀高亮 JS 橋接（key 空間隔離＋vertical 覆寫）

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`
- Test: `app/test/reader/foliate_reader_view_test.dart`（既有檔案，新增 group）

**Interfaces:**
- Consumes：既有 `view.addAnnotation()`/`view.deleteAnnotation()`（`window.setDecorations()` 已示範用法，見第 402-411 行）、既有 `draw-annotation` 事件監聽器（第 762-775 行）
- Produces：`window.showTtsHighlight(cfi, vertical)`／`window.clearTtsHighlight()` 兩個全域函式——供 Task 3 的 `FoliateReaderView.showTtsHighlight`/`clearTtsHighlight` 靜態 helper（透過 `InAppWebViewController.evaluateJavascript`）呼叫

- [ ] **Step 1：新增 `window.showTtsHighlight`/`window.clearTtsHighlight`**

在 `app/android/app/src/main/assets/foliate/main.js` 找到以下既有的 `window.setDecorations` 函式（第 402-411 行）：

```javascript
window.setDecorations = function (decorations) {
  for (const cfi of decorationIdByCfi.keys()) {
    view.deleteAnnotation({ value: cfi })
  }
  decorationIdByCfi = new Map()
  for (const { id, cfi, color, isUnderline } of decorations) {
    decorationIdByCfi.set(cfi, id)
    view.addAnnotation({ value: cfi, color, isUnderline })
  }
}
```

緊接其後（在下一段 `/** 主動清除目前的原生文字選取狀態...` 註解之前）新增：

```javascript
/**
 * 朗讀高亮（epic-34-tts-readalong Issue 3，ADR 0026「TTS 朗讀高亮採暫態
 * UI 狀態，不寫入 highlights/notes 資料表」）：使用 view.js 既有但本應用
 * 程式劃線/備註功能（window.setDecorations()，見上方）目前未使用到的
 * `foliate-note:` 前綴（NOTE_PREFIX，見 view.js 第 8、410-427 行），組成
 * annotation value，讓 Overlayer 內部 Map 的 key（"foliate-note:" + cfi）
 * 天然與劃線/備註直接以裸 cfi 當 key 的既有 key 空間分開——同一句子若剛好
 * 也被使用者手動劃線，兩者互不覆蓋、互不干擾（view.js addAnnotation()
 * 對於帶 NOTE_PREFIX 的 value，仍會 resolveNavigation() 去掉前綴後的 cfi
 * 算出 Range，並透過既有 draw-annotation 事件把繪製決定權交還給下方監聽器，
 * 與劃線/備註走的是同一段程式碼路徑，只是 Map key 不同——不需要修改任何
 * vendored 檔案）。全程只有一個 TTS 高亮存在，故 currentTtsAnnotationValue
 * 直接記錄「目前這個」的完整 prefixed value，供 clearTtsHighlight() 精確
 * 刪除；show 新的之前先刪除舊的，呼叫端不需要自行先呼叫 clear 再呼叫 show。
 */
const TTS_HIGHLIGHT_COLOR = 'rgba(251, 146, 60, 0.45)'
let currentTtsAnnotationValue = null

window.showTtsHighlight = function (cfi, vertical) {
  if (currentTtsAnnotationValue) {
    view.deleteAnnotation({ value: currentTtsAnnotationValue })
  }
  currentTtsAnnotationValue = 'foliate-note:' + cfi
  view.addAnnotation({
    value: currentTtsAnnotationValue,
    color: TTS_HIGHLIGHT_COLOR,
    isUnderline: false,
    vertical,
  })
}

window.clearTtsHighlight = function () {
  if (!currentTtsAnnotationValue) return
  view.deleteAnnotation({ value: currentTtsAnnotationValue })
  currentTtsAnnotationValue = null
}
```

- [ ] **Step 2：`draw-annotation` 監聽器接受 `annotation.vertical` 顯式覆寫**

找到以下既有的 `draw-annotation` 監聽器（第 762-775 行）：

```javascript
    view.addEventListener('draw-annotation', (e) => {
      const { draw, annotation } = e.detail
      if (annotation.isUnderline) {
        draw(Overlayer.underline, {
          color: annotation.color,
          writingMode: currentWritingMode === 'vertical' ? 'vertical-rl' : 'horizontal-tb',
        })
      } else {
        draw(Overlayer.highlight, {
          color: annotation.color,
          vertical: currentWritingMode === 'vertical',
        })
      }
    })
```

整段取代為：

```javascript
    view.addEventListener('draw-annotation', (e) => {
      const { draw, annotation } = e.detail
      // epic-34-tts-readalong Issue 3：annotation.vertical 由
      // window.showTtsHighlight() 明確傳入（見上方），讓朗讀高亮的直排/
      // 橫排判斷不依賴 currentWritingMode 的更新時機（理論上兩者恆一致，
      // 這裡是額外的顯式保險，也讓 Dart 端呼叫參數本身可被觀察/測試）。
      // 劃線/備註既有呼叫（window.setDecorations()）從未設定這個欄位，
      // ??（nullish coalescing，非 ||）確保只有 undefined 才落回
      // currentWritingMode——若誤用 ||，annotation.vertical 為合法值
      // false（橫排）時會被誤判為「未設定」而錯誤退回 currentWritingMode。
      const isVertical = annotation.vertical ?? (currentWritingMode === 'vertical')
      if (annotation.isUnderline) {
        draw(Overlayer.underline, {
          color: annotation.color,
          writingMode: isVertical ? 'vertical-rl' : 'horizontal-tb',
        })
      } else {
        draw(Overlayer.highlight, {
          color: annotation.color,
          vertical: isVertical,
        })
      }
    })
```

- [ ] **Step 3：main.js regression guard 測試**

在 `app/test/reader/foliate_reader_view_test.dart` 找到既有的 `group('main.js 選取範圍 hit-test 既有標記＋回傳文字 regression guard...')`（比照該 group 讀取 `mainJsSource` 的既有寫法，見檔案內 `setUpAll` 用法），在它結尾的 `});` 之後、`group('mounted guard / dispose race'...)` 之前，新增：

```dart
  group('main.js 朗讀高亮 regression guard（epic-34-tts-readalong Issue 3，ADR 0026）', () {
    late String mainJsSource;

    setUpAll(() {
      mainJsSource = File('android/app/src/main/assets/foliate/main.js')
          .readAsStringSync();
    });

    test('window.showTtsHighlight 使用 foliate-note: 前綴，與劃線/備註直接以 cfi 當 key 的既有 key 空間分開',
        () {
      expect(mainJsSource.contains('window.showTtsHighlight = function'), isTrue,
          reason: 'main.js 內找不到 window.showTtsHighlight——朗讀高亮橋接'
              '函式缺失。');
      expect(mainJsSource.contains("'foliate-note:' + cfi"), isTrue,
          reason: '朗讀高亮必須使用 foliate-note: 前綴組成 annotation '
              'value，讓 Overlayer 內部 Map 的 key 與劃線/備註直接以 cfi '
              '當 key 的既有 key 空間分開（ADR 0026「使用獨立 annotation '
              'key」），否則同一句子若剛好也被使用者手動劃線，會互相覆蓋。');
      expect(mainJsSource.contains('view.addAnnotation({'), isTrue);
    });

    test('window.clearTtsHighlight 存在且呼叫 view.deleteAnnotation', () {
      final showFnIndex =
          mainJsSource.indexOf('window.showTtsHighlight = function');
      final clearFnIndex =
          mainJsSource.indexOf('window.clearTtsHighlight = function');
      expect(clearFnIndex, greaterThanOrEqualTo(0),
          reason: 'main.js 內找不到 window.clearTtsHighlight——朗讀高亮'
              '清除橋接函式缺失，播放結束/朗讀段切換時高亮會無法清除、'
              '留下殘影。');
      final deleteCallIndex =
          mainJsSource.indexOf('view.deleteAnnotation(', clearFnIndex);
      expect(deleteCallIndex, greaterThanOrEqualTo(0),
          reason: 'window.clearTtsHighlight 內找不到 view.deleteAnnotation '
              '呼叫。');
      expect(showFnIndex, greaterThanOrEqualTo(0));
    });

    test('draw-annotation 監聽器含 annotation.vertical 覆寫，用 ?? 而非 ||（避免 vertical:false 被誤判為未設定）',
        () {
      expect(
        mainJsSource.contains(
          "annotation.vertical ?? (currentWritingMode === 'vertical')",
        ),
        isTrue,
        reason: 'draw-annotation 監聽器必須讓 annotation.vertical（朗讀'
            '高亮由 Dart 端明確傳入）優先於 currentWritingMode（劃線/'
            '備註既有推斷依據），且必須用 ??（nullish coalescing）而非 '
            '||——若誤用 ||，annotation.vertical 為合法值 false（橫排）'
            '時會被誤判為「未設定」而錯誤退回 currentWritingMode，橫排'
            '書籍的朗讀高亮可能在某些情境下被畫成直排樣式。',
      );
    });
  });

```

- [ ] **Step 4：跑測試**

```
flutter test test/reader/foliate_reader_view_test.dart
```

Expected：全數 PASS（含新增的 3 個 regression guard 測試）。

```
flutter analyze
```

Expected：`No issues found!`

不需要重新執行 `node app/tool/check_foliate_es_compat.js`——本次新增的 JS 語法（`??` nullish coalescing、模板字串、`Map`）在 `main.js` 既有程式碼中已大量使用（例如第 465/469/473/496/700/717/732/735/736 行皆已使用 `??`），不是本次新引入的相容性風險面，該掃描腳本的既有觸發時機本就是「升級 vendored 版本後才跑」（見 `app/tool/README.md`），非本 Issue 範圍。

- [ ] **Step 5：Commit**

```
git add app/android/app/src/main/assets/foliate/main.js app/test/reader/foliate_reader_view_test.dart
git commit -m "feat(epic-34): main.js 朗讀高亮橋接——key 空間隔離＋vertical 覆寫（Issue 3 Task 1）"
```

---

### Task 2：`TtsController` 新增 `onHighlightSegment` 高亮回呼（TDD）

**Files:**
- Modify: `app/lib/reader/tts_controller.dart`
- Test: `app/test/reader/tts_controller_test.dart`（既有檔案，新增測試案例）

**Interfaces:**
- Consumes：既有 `TtsSegmentCfi`（`tts_segment_cfi.dart`）
- Produces：`TtsController` 建構子新增可選具名參數 `void Function(TtsSegmentCfi? segment)? onHighlightSegment`——供 Task 3 的 `ReaderScreen._ttsControllerOrNull` 使用

- [ ] **Step 1：寫失敗測試**

在 `app/test/reader/tts_controller_test.dart` 檔案結尾（最後一個 `test()` 之後、`}` 之前）新增：

```dart
  test('play() 開始播放時，onHighlightSegment 收到目前段落（epic-34-tts-readalong Issue 3）',
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

    expect(highlighted, [segments[0]]);
  });

  test('自動接續下一段時，onHighlightSegment 依序收到新段落（不需呼叫端自行先清除舊值）',
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
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(highlighted, [segments[0], segments[1]]);
  });

  test('最後一段播放完畢回到 idle 時，onHighlightSegment 收到 null（清除高亮）', () async {
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
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(highlighted, [segments[0], segments[1], null]);
  });

  test('play() 合成失敗重設回 idle 時，onHighlightSegment 最後收到 null', () async {
    final highlighted = <TtsSegmentCfi?>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    provider.nextSynthesizeError = const TtsSynthesisException('模擬引擎失敗');
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: highlighted.add,
    );

    await controller.play();

    expect(highlighted, [segments[0], null]);
  });

  test('不提供 onHighlightSegment 時，play()/自動接續/播放結束皆不拋出例外（可選 callback）',
      () async {
    final controller = buildController();
    await controller.play();
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, TtsPlaybackStatus.idle);
  });
```

- [ ] **Step 2：跑測試確認失敗**

```
flutter test test/reader/tts_controller_test.dart
```

Expected：FAIL（`TtsController` 建構子尚未接受 `onHighlightSegment` 具名參數，編譯錯誤）。

- [ ] **Step 3：實作 `onHighlightSegment`**

在 `app/lib/reader/tts_controller.dart` 找到以下既有欄位/建構子（第 26-37 行）：

```dart
class TtsController extends ChangeNotifier {
  final TtsProvider provider;
  final TtsAudioPlayer player;
  final Future<List<TtsSegmentCfi>> Function() loadSegments;

  TtsController({
    required this.provider,
    required this.player,
    required this.loadSegments,
  }) {
    _completedSub = player.completedStream.listen((_) => _handleSegmentCompleted());
  }
```

整段取代為：

```dart
class TtsController extends ChangeNotifier {
  final TtsProvider provider;
  final TtsAudioPlayer player;
  final Future<List<TtsSegmentCfi>> Function() loadSegments;

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

找到以下既有的 `paused` 狀態恢復播放分支（`play()` 內）：

```dart
    if (_status == TtsPlaybackStatus.paused) {
      _status = TtsPlaybackStatus.playing;
      notifyListeners();
      try {
        await player.play();
      } catch (_) {
        if (_disposed) return;
        _status = TtsPlaybackStatus.idle;
        _currentIndex = -1;
        _segments = const [];
        notifyListeners();
      }
      return;
    }
```

整段取代為：

```dart
    if (_status == TtsPlaybackStatus.paused) {
      _status = TtsPlaybackStatus.playing;
      notifyListeners();
      try {
        await player.play();
      } catch (_) {
        if (_disposed) return;
        _status = TtsPlaybackStatus.idle;
        _currentIndex = -1;
        _segments = const [];
        onHighlightSegment?.call(null);
        notifyListeners();
      }
      return;
    }
```

找到以下既有的 `_playCurrentSegment()` 方法：

```dart
  Future<void> _playCurrentSegment() async {
    final segment = _segments[_currentIndex];
    try {
      _status = TtsPlaybackStatus.playing;
      notifyListeners();
      final result = await provider.synthesize(
        segment.text,
        voice: TtsVoice.systemDefault,
      );
      if (_disposed) return;
      await player.loadFile(result.audioFilePath);
      if (_disposed || _status != TtsPlaybackStatus.playing) return;
      await player.play();
    } catch (_) {
      if (_disposed) return;
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      notifyListeners();
    }
  }
```

整段取代為：

```dart
  Future<void> _playCurrentSegment() async {
    final segment = _segments[_currentIndex];
    try {
      _status = TtsPlaybackStatus.playing;
      onHighlightSegment?.call(segment);
      notifyListeners();
      final result = await provider.synthesize(
        segment.text,
        voice: TtsVoice.systemDefault,
      );
      if (_disposed) return;
      await player.loadFile(result.audioFilePath);
      if (_disposed || _status != TtsPlaybackStatus.playing) return;
      await player.play();
    } catch (_) {
      if (_disposed) return;
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      onHighlightSegment?.call(null);
      notifyListeners();
    }
  }
```

找到以下既有的 `_handleSegmentCompleted()` 方法：

```dart
  Future<void> _handleSegmentCompleted() async {
    if (_disposed) return;
    if (_status != TtsPlaybackStatus.playing) return;
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _segments.length) {
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      notifyListeners();
      return;
    }
    _currentIndex = nextIndex;
    await _playCurrentSegment();
  }
```

整段取代為：

```dart
  Future<void> _handleSegmentCompleted() async {
    if (_disposed) return;
    if (_status != TtsPlaybackStatus.playing) return;
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _segments.length) {
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      onHighlightSegment?.call(null);
      notifyListeners();
      return;
    }
    _currentIndex = nextIndex;
    await _playCurrentSegment();
  }
```

- [ ] **Step 4：跑測試確認通過**

```
flutter test test/reader/tts_controller_test.dart
```

Expected：全數 PASS（既有 17 個測試零回歸＋新增 5 個高亮回呼測試，共 22 個）。

```
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 5：Commit**

```
git add app/lib/reader/tts_controller.dart app/test/reader/tts_controller_test.dart
git commit -m "feat(epic-34): TtsController 新增 onHighlightSegment 高亮回呼（Issue 3 Task 2，TDD）"
```

---

### Task 3：`FoliateReaderView` 高亮靜態 helper＋`ReaderScreen` 接線

**Files:**
- Modify: `app/lib/reader/foliate_reader_view.dart`
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`（既有檔案，新增測試案例）

**Interfaces:**
- Consumes：Task 1 的 `window.showTtsHighlight`/`window.clearTtsHighlight`；Task 2 的 `TtsController.onHighlightSegment`；既有 `ReaderScreen._resolved`（目前實際生效的排版方向，含使用者手動切換結果）、`WritingMode`
- Produces：`FoliateReaderView.showTtsHighlight(key, cfi, {required bool vertical})`／`FoliateReaderView.clearTtsHighlight(key)` 靜態方法；`ReaderScreen._ttsControllerOrNull` 內部接線（無新增公開 API）

- [ ] **Step 1：`FoliateReaderView` 新增靜態 helper**

在 `app/lib/reader/foliate_reader_view.dart` 找到以下既有的 `setDecorations` 靜態方法：

```dart
  static void setDecorations(
    GlobalKey<State<FoliateReaderView>> key,
    List<EpubDecoration> decorations,
  ) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      final entries = buildDecorationEntries(decorations);
      state._evaluate('window.setDecorations(${jsonEncode(entries)})');
    }
  }

  /// 主動清除 WebView 原生文字選取狀態（epic-25 Issue 3，見 main.js
  /// window.clearSelection 註解）。
  static void clearSelection(GlobalKey<State<FoliateReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.clearSelection()');
    }
  }
```

整段取代為：

```dart
  static void setDecorations(
    GlobalKey<State<FoliateReaderView>> key,
    List<EpubDecoration> decorations,
  ) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      final entries = buildDecorationEntries(decorations);
      state._evaluate('window.setDecorations(${jsonEncode(entries)})');
    }
  }

  /// 顯示朗讀高亮（epic-34-tts-readalong Issue 3，ADR 0026）：呼叫 main.js
  /// window.showTtsHighlight()，使用與劃線/備註分開的獨立 annotation key
  /// 空間（見 main.js 該函式註解），不寫入任何資料表。[vertical] 由呼叫端
  /// （[ReaderScreen]）依目前實際生效的排版方向傳入，供 main.js
  /// draw-annotation 監聽器決定 Overlayer.highlight() 的 vertical 參數，
  /// 直排/橫排皆正確跟隨。
  static void showTtsHighlight(
    GlobalKey<State<FoliateReaderView>> key,
    String cfi, {
    required bool vertical,
  }) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate(
        'window.showTtsHighlight(${jsonEncode(cfi)}, $vertical)',
      );
    }
  }

  /// 清除目前的朗讀高亮（epic-34-tts-readalong Issue 3）。朗讀段切換時不
  /// 需要呼叫端先呼叫這個方法再呼叫 [showTtsHighlight]——main.js
  /// window.showTtsHighlight() 內部已處理「顯示新的之前先清除舊的」，本
  /// 方法只在播放結束（不再有下一段可顯示）時由 [ReaderScreen] 呼叫。
  static void clearTtsHighlight(GlobalKey<State<FoliateReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.clearTtsHighlight()');
    }
  }

  /// 主動清除 WebView 原生文字選取狀態（epic-25 Issue 3，見 main.js
  /// window.clearSelection 註解）。
  static void clearSelection(GlobalKey<State<FoliateReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateReaderViewState) {
      state._evaluate('window.clearSelection()');
    }
  }
```

- [ ] **Step 2：`ReaderScreen` 接線**

在 `app/lib/screens/reader_screen.dart` 頂部 import 區塊，緊接 `import '../reader/tts_provider.dart';` 之後新增：

```dart
import '../reader/tts_segment_cfi.dart';
```

（`onHighlightSegment` 回呼參數 `segment` 的型別 `TtsSegmentCfi` 靠型別推導取得，不寫這行 import 一樣能編譯過——比照既有 `loadSegments` closure 回傳 `Future<List<TtsSegmentCfi>>` 也未顯式 import 的既有先例。這裡加上是為了讓「這段程式碼依賴 `TtsSegmentCfi`」這件事對讀者顯式可見，純粹可讀性考量，見 `reviews/review-plan-issue-3.md` Important #1。）

在 `app/lib/screens/reader_screen.dart` 找到以下既有的 `_ttsControllerOrNull` getter：

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
    );
  }
```

- [ ] **Step 3：寫 widget test**

在 `app/test/screens/reader_screen_test.dart` 找到既有的 `group('TTS 語音朗讀（epic-34-tts-readalong Issue 2）', ...)` 結尾的 `});`（緊接在 `CBZ 格式提供 ttsProvider 時，TTS 按鈕顯示但為停用狀態` 測試之後），在它之後新增一個新的 group：

```dart
  group('同步高亮跟隨（epic-34-tts-readalong Issue 3）', () {
    // 誠實測試邊界（比照既有 setDecorations 測試慣例，見本檔案「流式
    // EPUB 開書後...透過 FoliateReaderView.setDecorations 送給原生端」
    // 測試的既有註解）：flutter_test 環境下 FoliateReaderView 的
    // _controller 恆為 null，FoliateReaderView.showTtsHighlight()/
    // clearTtsHighlight() 實際送出的 JS 呼叫參數（含 cfi／vertical 旗標）
    // 無法在這層直接攔截斷言——同一個既有限制也適用於 setDecorations。
    // 這裡驗證的是「直排書籍下這段 wiring 不崩潰」這個結構性保證；
    // 「onHighlightSegment 在正確時機被呼叫、帶正確的段落」由
    // tts_controller_test.dart（純 Dart，見 Task 2）完整涵蓋；main.js
    // 端 key 空間隔離／vertical 覆寫邏輯由 foliate_reader_view_test.dart
    // 的 main.js regression guard（見 Task 1）涵蓋；真實 JS 高亮渲染
    // 正確性（含直排/橫排實際跟隨、朗讀段切換時無殘影）須真機手動驗證
    // （見本計畫「測試策略總結」）。
    testWidgets(
        '提供 ttsProvider 且書本為直排（vertical）時，ReaderScreen 正常建構、'
        'TTS 按鈕存在且可點擊，不崩潰', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts_vertical',
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
          writingMode: WritingMode.vertical,
        ),
      );
      await tester.pump();
      await tester.pump();

      final buttonFinder =
          find.byKey(const Key('reader_tts_play_pause_button'));
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'TTS 播放按鈕點擊後，highlightsRepository/notesRepository 內容不受影響'
        '（ADR 0026：朗讀高亮不寫入劃線/備註資料表）', (tester) async {
      final highlightsRepo = FakeHighlightsRepository();
      final notesRepo = FakeNotesRepository();
      final ttsProvider = FakeTtsProvider();
      const bookId = 'b_tts_adr0026';

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: bookId,
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

      await tester.tap(find.byKey(const Key('reader_tts_play_pause_button')));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(await highlightsRepo.listByBook(bookId), isEmpty);
      expect(await notesRepo.listByBook(bookId), isEmpty);
    });
  });
```

- [ ] **Step 4：跑測試確認全數通過、零回歸**

```
flutter test test/screens/reader_screen_test.dart
```

Expected：全數 PASS（含新增的 2 個測試，既有測試零回歸）。

```
flutter test
```

Expected：全專案測試全數通過，零回歸。

```
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 5：Commit**

```
git add app/lib/reader/foliate_reader_view.dart app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-34): FoliateReaderView 高亮 helper＋ReaderScreen 接線（Issue 3 Task 3）"
```

---

## 測試策略總結（Self-Review 用，非額外步驟）

- **純 Dart 單元測試**（Task 2）：`TtsController.onHighlightSegment` 在朗讀段開始/自動接續/播放結束/合成失敗四種時機皆帶正確的 `TtsSegmentCfi?` 值，含不提供 callback 時的向後相容性。
- **main.js regression guard**（Task 1，`foliate_reader_view_test.dart` 新增 group）：以既有「讀取原始碼字串斷言」慣例（比照 epic-27 Issue 9/10/11 先例）驗證 `foliate-note:` key 空間隔離、`clearTtsHighlight` 呼叫 `deleteAnnotation`、`draw-annotation` 監聽器的 `??` 覆寫邏輯確實存在於原始碼中——不驗證真實瀏覽器渲染行為（`flutter_test` 無 JS 執行環境）。
- **`ReaderScreen` widget test**（Task 3）：驗證 UI 接線層級在直排書籍下不崩潰、TTS 按鈕可操作；額外新增 ADR 0026「不寫入資料表」的自動化迴歸防護（`highlightsRepository`/`notesRepository` 內容於 TTS 播放按鈕互動後保持不變）。
- **無法自動化、須真機手動驗證的部分**（比照 Issue 2「測試策略總結」既有慣例，合併前建議至少手動跑一次）：
  1. 開一本橫排 EPUB，按下播放，確認畫面即時高亮目前朗讀句，位置正確跟隨。
  2. 開一本直排（`vertical-rl`）EPUB，重複驗證 1，確認高亮方向與位置在直排模式下同樣正確跟隨。
  3. 朗讀段切換與播放自然結束時，確認前一個高亮正確消失，無殘留。
  4. 對朗讀中即將念到的句子先手動劃線，播放經過該句時確認 TTS 高亮與手動劃線同時可見、互不覆蓋；播放結束後手動劃線仍完整保留（`foliate-note:` key 空間隔離的真實驗證）。
  5. 對含 `<em>`/`<ruby>` 跨標籤句子的章節（Issue 2 已建立的測試樣本對應書籍）朗讀，確認高亮確實框住整句範圍，不只是 CFI 字串能還原。

---

## Self-Review 檢查結果

- **Spec coverage**：`issues.md` Issue 3 設計要點與驗收標準逐條對應——高亮重用既有 `Overlayer.add()`/`remove()` pipeline（Task 1）、獨立 annotation key 與劃線/備註分開（Task 1，`foliate-note:` 前綴）、不寫入任何資料表（Task 1 設計本身天然滿足＋Task 3 新增自動化迴歸測試）、朗讀段切換時（非每次 tick）更新（Task 2，`onHighlightSegment` 只在段落開始/切換/結束觸發）、播放結束/切換時清除前一個高亮（Task 2 四個呼叫點）、直排/橫排跟隨沿用既有 `vertical`/`writingMode` 參數（Task 1 Step 2＋Task 3 `_resolved?.writingMode` 判斷）、不修改任何 vendored 檔案（全程只編輯 `main.js`）、`flutter analyze`/`flutter test` 全數通過（每個 Task 皆有驗證步驟）。無缺口。
- **Placeholder scan**：全文搜尋未發現「TBD」/「之後補」/「處理錯誤」等空話；所有程式碼步驟皆有完整程式碼區塊與精確的既有程式碼比對錨點。
- **Type consistency**：`TtsController.onHighlightSegment` 簽章（Task 2 定義 `void Function(TtsSegmentCfi? segment)?`）與 Task 3 `ReaderScreen` 呼叫端（`(segment) { if (segment == null) ... else ... segment.cfi ... }`）一致；`FoliateReaderView.showTtsHighlight(key, cfi, {required bool vertical})`／`clearTtsHighlight(key)` 簽章（Task 3 Step 1 定義）與 Task 3 Step 2 `ReaderScreen` 呼叫端一致；`window.showTtsHighlight(cfi, vertical)`／`window.clearTtsHighlight()`（Task 1 JS 定義）與 Task 3 Step 1 `_evaluate()` 呼叫的 JS 字串一致。
