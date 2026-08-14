# Epic 27 Issue 2 — 開書逾時時間由固定 12 秒延長為 30 秒 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將 `ReaderScreen` 開書逾時哨兵（`_openBookTimeoutTimer`）的固定等待時間從 12 秒延長為 30 秒，緩解 Mobiscribe WAVE 等慢速裝置在開啟大型 EPUB 時被提早誤判逾時、需要反覆重試才能成功開書的問題。

**Architecture:** 純數值調整，不涉及任何新介面/型別/架構異動。`_openBookTimeoutTimer`（`app/lib/screens/reader_screen.dart:372`）是 `initState()` 內排程的單次 `Timer`，逾時觸發 `_handleOpenBookTimeout()`（`app/lib/screens/reader_screen.dart:1349-1356`）把 `_state` 從 `_RenderState.loading` 切為 `_RenderState.error`；`_handlePageRendered()`／`_handleError()` 皆會在觸發時取消此計時器（不在本次改動範圍內）。本計畫只改 `Duration(seconds: 12)` → `Duration(seconds: 30)` 這一個常數，以及緊鄰的說明註解與兩則既有單元測試的對應數值。逾時錯誤文案（`app/lib/screens/reader_screen.dart:1354`）維持不變——`issues.md` Issue 2 明確載明文案調整非本 Issue 強制要求，依 YAGNI 不做超出範圍的變更。

**Tech Stack:** Flutter/Dart，無新增依賴。

**Spec:** `docs/epics/epic-27-reader-device-compat/issues.md`「Issue 2」、`docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md`「Issue 2」（根因診斷與使用者確認的 30 秒目標值）。

## Global Constraints

- 只修改 `app/lib/screens/reader_screen.dart`（`_openBookTimeoutTimer` 的 `Duration` 常數＋緊鄰的說明註解）與 `app/test/screens/reader_screen_test.dart`（兩則既有逾時測試的數值與描述文字）這兩個檔案，不觸碰逾時錯誤文案（`_errorMessage = '開書逾時，可能是系統 WebView 版本過舊或檔案異常';`）或任何其他邏輯。
- 目標值 30 秒為使用者於 2026-08-13 診斷對話中確認的最終值（見 `reviews/bugfix-repro.md`「Issue 2」末段），不是實作者自行估算，不可另行調整。
- 每完成 Task 就跑一次 `flutter analyze`，維持乾淨。

---

### Task 1：`_openBookTimeoutTimer` 逾時值 12 秒 → 30 秒

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:361-372`（`_openBookTimeoutTimer` 欄位宣告與其上方文件註解）、`app/lib/screens/reader_screen.dart:389-392`（`Timer` 建構呼叫）
- Test: `app/test/screens/reader_screen_test.dart:4981-5008`（「開書逾時...自動切換為錯誤畫面」）、`app/test/screens/reader_screen_test.dart:5010-5038`（「逾時計時器不應覆蓋既有成功狀態」）

**Interfaces:**
- Consumes: 既有 `_RenderState`（`_ReaderScreenState` 私有列舉欄位 `_state`）、既有 `Key('reader_loading_indicator')`／`Key('reader_error_text')`（測試觀察用固定 Key，見 `CLAUDE.md`「`ReaderScreen`」小節）。
- Produces: 無新增對外介面——`_openBookTimeoutTimer` 的排程時長由 12 秒改為 30 秒，`_handleOpenBookTimeout()` 簽章與行為邏輯本身不變。

- [ ] **Step 1：修改「開書逾時自動切換錯誤畫面」測試——先驗證 30 秒邊界，讓測試在目前 12 秒實作下失敗**

編輯 `app/test/screens/reader_screen_test.dart`，找到（約第 4981-5008 行）：

```dart
  testWidgets(
      '開書逾時（epic-18-reader-device-qa Issue 33）：12 秒內未收到 onPageRendered，'
      '自動切換為錯誤畫面，不會永遠停在載入指示器', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_open_timeout',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 刻意不呼叫 onPageRendered，模擬「原生端/WebView 從未回報成功」的
    // 卡住情境（真機使用回報：iReader Ocean 4 Plus 開啟書籍時畫面永遠
    // 停在轉圈圈，5 個推測根因皆未經真機診斷資料驗證）。
    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    await tester.pump(const Duration(seconds: 12));

    expect(find.byKey(const Key('reader_error_text')), findsOneWidget,
        reason: '逾時後應切換為可見的錯誤畫面，而非讓使用者永遠面對轉圈圈');
    expect(find.byKey(const Key('reader_loading_indicator')), findsNothing);
  });
```

改為：

```dart
  testWidgets(
      '開書逾時（epic-18-reader-device-qa Issue 33，epic-27-reader-device-compat '
      'Issue 2 調整為 30 秒）：30 秒內未收到 onPageRendered，'
      '自動切換為錯誤畫面，不會永遠停在載入指示器', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_open_timeout',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    // 刻意不呼叫 onPageRendered，模擬「原生端/WebView 從未回報成功」的
    // 卡住情境（真機使用回報：iReader Ocean 4 Plus 開啟書籍時畫面永遠
    // 停在轉圈圈，5 個推測根因皆未經真機診斷資料驗證）。
    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // epic-27-reader-device-compat Issue 2：先推進 29 秒並斷言「仍是載入
    // 中」，確認逾時值真的是 30 秒（而不只是某個大於舊值 12 秒的時間點
    // 剛好也能通過）——若實作仍是舊的 12 秒，這裡會提早看到錯誤畫面而
    // 斷言失敗。
    await tester.pump(const Duration(seconds: 29));

    expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget,
        reason: '30 秒內尚未逾時，應維持載入中，不應提早顯示錯誤畫面');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('reader_error_text')), findsOneWidget,
        reason: '滿 30 秒後應切換為可見的錯誤畫面，而非讓使用者永遠面對轉圈圈');
    expect(find.byKey(const Key('reader_loading_indicator')), findsNothing);
  });
```

- [ ] **Step 2：修改「逾時計時器不應覆蓋既有成功狀態」測試的推進時長**

編輯 `app/test/screens/reader_screen_test.dart`，找到（約第 5010-5038 行）測試「`開書逾時計時器：onPageRendered 在逾時前已觸發時，逾時計時器不應覆蓋既有的成功狀態`」內：

```dart
    // 逾時計時器理應在 onPageRendered 觸發當下就被取消；即使沒有取消，
    // 逾時處理本身也必須判斷「已經不是 loading 狀態才動作」，兩者皆可
    // 避免這裡誤把已成功渲染的畫面覆蓋回錯誤狀態。
    await tester.pump(const Duration(seconds: 12));
```

改為：

```dart
    // 逾時計時器理應在 onPageRendered 觸發當下就被取消；即使沒有取消，
    // 逾時處理本身也必須判斷「已經不是 loading 狀態才動作」，兩者皆可
    // 避免這裡誤把已成功渲染的畫面覆蓋回錯誤狀態。
    // epic-27-reader-device-compat Issue 2：逾時值調整為 30 秒，此處同步
    // 更新推進時長；本測試驗證的是「已成功渲染不受逾時計時器覆蓋」，
    // 與逾時值本身大小無關，故不需要像 Step 1 那樣拆成兩段推進。
    await tester.pump(const Duration(seconds: 30));
```

- [ ] **Step 3：執行測試確認 Step 1 的新斷言失敗（Step 2 因與逾時值大小無關，預期仍為 PASS）**

執行：`cd app && flutter test test/screens/reader_screen_test.dart --plain-name "開書逾時"`

預期：「開書逾時（epic-18-reader-device-qa Issue 33，epic-27-reader-device-compat Issue 2 調整為 30 秒）」FAIL 於 `reader_loading_indicator` 的 `findsOneWidget` 斷言（`推進 29 秒` 後，目前 12 秒的實作已提早觸發逾時，錯誤畫面已出現，載入指示器已消失）；「開書逾時計時器：...不應覆蓋既有的成功狀態」PASS（此測試的斷言與逾時值大小無關，見 Step 2 說明）。

- [ ] **Step 4：修改 `_openBookTimeoutTimer` 實作，12 秒 → 30 秒，同步更新說明註解**

編輯 `app/lib/screens/reader_screen.dart`，找到（約第 361-372 行）：

```dart
  /// 開書載入逾時哨兵（epic-18-reader-device-qa Issue 33，真機使用回報：
  /// iReader Ocean 4 Plus 開啟書籍時畫面永遠停在載入指示器，5 個推測根因
  /// 皆無真機診斷資料佐證）。單次 Timer，_handlePageRendered()／
  /// _handleError() 觸發時皆會取消（不論成功或失敗都不需要再等）；
  /// 12 秒後若仍是 loading 狀態，代表底層渲染引擎（PdfRenderer／
  /// FoliateEpubReaderView 的 WebView）從未回報任何結果，主動切換為錯誤
  /// 畫面，避免使用者永遠面對轉圈圈、投訴無門（見上方 Issue 33 的
  /// _globalErrorCaptureJs 診斷能力補強說明——這是「連 JS 例外都沒有拋出」
  /// 這種更極端情況的最後一道防線）。12 秒取自本 Issue 的原始分析報告
  /// 建議值，非嚴謹量測結果，未來若真機回報大型書籍在正常情況下也需要
  /// 較長時間才能完成首頁繪製，可再調整。
  Timer? _openBookTimeoutTimer;
```

改為：

```dart
  /// 開書載入逾時哨兵（epic-18-reader-device-qa Issue 33，真機使用回報：
  /// iReader Ocean 4 Plus 開啟書籍時畫面永遠停在載入指示器，5 個推測根因
  /// 皆無真機診斷資料佐證）。單次 Timer，_handlePageRendered()／
  /// _handleError() 觸發時皆會取消（不論成功或失敗都不需要再等）；
  /// 30 秒後若仍是 loading 狀態，代表底層渲染引擎（PdfRenderer／
  /// FoliateEpubReaderView 的 WebView）從未回報任何結果，主動切換為錯誤
  /// 畫面，避免使用者永遠面對轉圈圈、投訴無門（見上方 Issue 33 的
  /// _globalErrorCaptureJs 診斷能力補強說明——這是「連 JS 例外都沒有拋出」
  /// 這種更極端情況的最後一道防線）。原始值為 12 秒（epic-18-reader-device-qa
  /// Issue 33 的原始分析報告建議值，非嚴謹量測結果）；
  /// epic-27-reader-device-compat Issue 2 依 Mobiscribe WAVE 真機回報
  /// 「慢速裝置＋大型 EPUB 組合下 12 秒容易誤判逾時、需反覆重試才能開書
  /// 成功」調整為 30 秒（2026-08-13 使用者於診斷對話中確認此目標值，完整
  /// 診斷見 docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md）。
  Timer? _openBookTimeoutTimer;
```

接著找到（約第 389-392 行）：

```dart
    _openBookTimeoutTimer = Timer(
      const Duration(seconds: 12),
      _handleOpenBookTimeout,
    );
```

改為：

```dart
    _openBookTimeoutTimer = Timer(
      const Duration(seconds: 30),
      _handleOpenBookTimeout,
    );
```

- [ ] **Step 5：執行測試確認通過**

執行：`cd app && flutter test test/screens/reader_screen_test.dart --plain-name "開書逾時"`

預期：兩則測試皆 PASS。

- [ ] **Step 6：執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`

預期：`flutter analyze` 顯示 "No issues found!"；`flutter test` 全數 PASS，零回歸（本次改動只觸及 `_openBookTimeoutTimer` 的排程時長與其註解，不影響其他邏輯路徑，理論上只有 `reader_screen_test.dart` 的兩則逾時測試會受影響，已於 Step 1-5 處理）。

- [ ] **Step 7：Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "fix(epic-27): Issue 2——開書逾時由 12 秒延長為 30 秒，緩解慢速裝置誤判"
```

---

## 完成後的驗證（對照 `issues.md` Issue 2 驗收標準）

- [ ] 開書 30 秒內未完成才顯示逾時錯誤畫面（Step 1 新增的 29 秒／30 秒邊界斷言已涵蓋）
- [ ] `reader_screen_test.dart` 相關測試更新為新數值並通過
- [ ] `flutter analyze`：全專案 "No issues found!"
- [ ] `flutter test`：全專案通過，零回歸
