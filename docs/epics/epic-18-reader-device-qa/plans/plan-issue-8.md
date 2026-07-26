# Epic 18 Issue 8：流式 EPUB 真機無法畫線 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 診斷並修復流式 EPUB（`FoliateEpubReaderView`）在真實 Android 裝置上「長按選字後無法拖曳選取控點」導致無法建立劃線的問題。

**Architecture:** `foliate_epub_reader_view.dart` 的 `build()` 在 `AndroidView`（WebView）上疊了一層全螢幕 9 宮格 `GestureDetector`（3×3 導航熱區），其中每個格子都註冊了空的 `onHorizontalDragStart`/`onVerticalDragStart`（`foliate_epub_reader_view.dart:383-384`），刻意搶下 Flutter 手勢競技場的拖曳仲裁權，避免底下 WebView 的原生滑動翻頁手勢跟 tap 熱區打架（此機制記載於 `docs/archive/2026-07-24-epic-7-interaction/design.md:115`）。假設是：這個機制同時攔截了「拖曳選取控點調整劃線範圍」這個手勢，因為兩者在 Flutter 手勢競技場層級看起來都只是「一段拖曳位移」。本 Issue 先在真機上用 mutation test 方法論驗證這個假設，再依驗證結果選擇下列兩條修法路徑之一（Task 3A 或 Task 3B），不預先假設答案。

**Tech Stack:** Flutter（`GestureDetector`/`AndroidView`）、`flutter_test`（channel-level mock，比照既有 `foliate_epub_reader_view_test.dart` 慣例）、真機人工驗證（`flutter run -d <device-id>`）。

## Global Constraints

- 不修改 vendored `readest/foliate-js`（`view.js`／`paginator.js`／`overlayer.js`），比照 ADR 0011。本 Issue 全程只碰 `app/lib/reader/foliate_epub_reader_view.dart`（與必要時的測試檔）。
- `EpubReaderView`（FXL 路徑，`app/lib/reader/epub_reader_view.dart`）的同款 no-op drag handler **不在本 Issue 範圍**——FXL 依 decision #7 本就排除劃線功能，不受此問題影響，不需要也不應該一併修改，避免無謂變動已穩定的既有路徑。
- 既有 9 個 `Key('nav_zone_$index')` 的 tap 導覽行為（`foliate_epub_reader_view_test.dart:545-582`）必須全程保持通過，任何修法都不得讓 tap 熱區退化。
- 本 Issue 的核心驗證（長按選字＋拖曳控點是否真的生效）**無法**用 `flutter test`（純 Dart VM，`AndroidView` 被 mock 成空殼，見 `foliate_epub_reader_view_test.dart:18-45` 的 `_pumpFoliateEpubReaderView`）自動化覆蓋，必須用連接真機的 `flutter run -d <device-id>` 人工操作驗證（比照本 Epic Issue 5/6 既有的真機 mutation test 方法論）。
- Task 1/2 需要一台已連接、已授權 USB 偵錯的真實 Android 裝置（**非模擬器**——WebView 手勢轉發行為在模擬器與真機上可能不同，這正是本 Issue 的問題只在真機上被回報的原因）。若手上暫無裝置，先執行 `flutter devices` 確認至少一台裝置可用，再繼續。

---

## Task 1：真機重現現況（人工診斷，修法前的基準線）

**Files:** 無（本 Task 不變更任何程式碼，純粹建立「問題確實存在」的基準觀察）

**Interfaces:**
- Consumes: 無
- Produces: 「診斷紀錄」第 1 節的觀察結果，供 Task 2 比對

- [ ] **Step 1: 確認真機已連接**

Run: `flutter devices`
Expected: 至少列出一台實體 Android 裝置（非 `emulator-*`），記下其 device id（下文以 `<device-id>` 代稱，執行時請替換為實際值）。

- [ ] **Step 2: 在真機上執行目前（修復前）的 App**

```bash
cd app
flutter run -d <device-id>
```

Expected: App 成功安裝並啟動，顯示書架畫面。

- [ ] **Step 3: 開啟一本流式（reflowable）EPUB**

從書架點開任一本 EPUB。若該書是固定版面（FXL），版面設定按鈕會是右上角浮動圓鈕樣式；流式書籍目前仍是頂部 `AppBar` 樣式（Issue 7 完成前的現況）。若圖書庫內沒有可用的流式 EPUB，先透過既有匯入流程匯入一本（任何非固定版面的 `.epub` 檔皆可）。

- [ ] **Step 4: 長按書本內文任一段文字 2 秒以上**

Expected: Android 原生選取控點（handle，通常是兩個可拖曳的水滴狀圖示，分別位於選取範圍起訖處）出現，且 Flutter 端的 `AnnotationToolbar`（劃線顏色/底線/備註的浮動工具列）也隨之出現於選取範圍附近。

若這一步就沒有任何選取控點出現（長按完全沒反應），記錄此差異——代表問題比原始回報更早發生（連建立初始選取都不成功，不只是拖曳控點的問題），需要先回報給人類確認範圍是否需要擴大，暫停後續步驟。

- [ ] **Step 5: 嘗試拖曳其中一個選取控點，擴大或縮小選取範圍**

用手指按住任一個選取控點，緩慢拖曳。觀察：

- **若選取範圍確實隨手指拖曳而擴大/縮小** → 現象未重現。停止本次執行，回報給人類：可能是裝置/Android 版本/EPUB 內容差異導致，需要換一台裝置或另一本書重試，或重新確認原始回報的重現條件。
- **若拖曳控點時選取範圍完全沒有反應（維持長按當下的初始範圍不變）** → 現象重現成功，符合使用者原始回報。繼續 Step 6。

- [ ] **Step 6: 記錄觀察結果**

把 Step 4／Step 5 的實際觀察結果，填入本文件最下方「診斷紀錄」的「Task 1 基準觀察」小節（測試裝置型號/Android 版本、測試書籍、觀察到的實際現象）。

---

## Task 2：Mutation Test —— 暫時移除 no-op drag handler，真機比對

**Files:**
- Modify（暫時，本 Task 結束前依結果決定是否保留，**先不要 commit**）: `app/lib/reader/foliate_epub_reader_view.dart:379-386`

**Interfaces:**
- Consumes: Task 1 已確認現象重現
- Produces: 「診斷紀錄」第 2 節的比對結果，決定進入 Task 3A 或 Task 3B

- [ ] **Step 1: 找到並暫時移除兩行 no-op drag handler**

開啟 `app/lib/reader/foliate_epub_reader_view.dart`，找到 `build()` 內的這段（第 379-386 行）：

```dart
                      child: GestureDetector(
                        key: Key('nav_zone_$index'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onZoneAction?.call(action),
                        onHorizontalDragStart: (_) {},
                        onVerticalDragStart: (_) {},
                        child: Container(
```

暫時（不 commit）刪除 `onHorizontalDragStart: (_) {},` 與 `onVerticalDragStart: (_) {},` 這兩行，改為：

```dart
                      child: GestureDetector(
                        key: Key('nav_zone_$index'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onZoneAction?.call(action),
                        child: Container(
```

- [ ] **Step 2: 重新建置並完整重啟 App（非熱重載）**

```bash
flutter run -d <device-id>
```

熱重載（hot reload）可能不足以反映 `GestureDetector` 手勢註冊器的變化，本步驟需要完全重新啟動 App（若已在執行中，先按 `q` 結束再重新執行 `flutter run`，或直接按 `R` 觸發 hot restart）確保生效。

- [ ] **Step 3: 重複 Task 1 Step 3-5，確認畫線功能是否恢復**

同一本書、同一段文字，重新測試長按選字＋拖曳控點。記錄：拖曳控點時選取範圍是否恢復正常反應（隨手指移動擴大/縮小）。

- [ ] **Step 4: 測試 9 宮格 tap 熱區導覽是否仍正常**

點擊畫面左側／右側（依目前 `navZoneActions` 設定，預設對應上一頁/下一頁）確認正常換頁；點擊畫面中央（預設對應選單切換）確認能正常切換沉浸模式（AppBar/頁尾顯示或隱藏）。

- [ ] **Step 5: 測試是否出現非預期的滑動翻頁（regression 檢查）**

在畫面上快速做出**水平**與**垂直**方向的滑動手勢（類似滑手機相簿切換照片的動作，非長按選字，且手指起點/終點都刻意避開明顯的選取文字區域，模擬使用者單純想換頁或捲動時的手勢）。觀察：foliate-js 是否有自己內建的滑動翻頁/捲動行為被觸發（例如畫面內容意外往旁邊位移、翻到下一頁，而非停留在原地等待 tap 熱區判定）。

- [ ] **Step 6: 記錄兩項觀察結果**

把 Step 3／Step 4／Step 5 的觀察結果，填入本文件「診斷紀錄」的「Task 2 Mutation Test 結果」小節，並依下列規則決定下一步：

- **若「畫線恢復正常」且「無非預期滑動翻頁」** → 前往 **Task 3A**（直接永久移除）。
- **若「畫線恢復正常」但「出現非預期滑動翻頁/regression」** → 前往 **Task 3B**（改為條件式攔截）。
- **若「畫線仍未恢復」** → 代表根因假設有誤，暫停本計畫，回報人類——需要重新診斷（可能是 Android WebView 原生選取 UI 本身的問題，而非 Flutter 手勢競技場攔截，需要參考 `tmp/epic-18/reviews/anx_reader_foliate_js_highlighting_analysis.md` 進一步排查 `main.js` 的 `selectionchange` 監聽器或 Android WebView 設定）。

- [ ] **Step 7: 確認變更範圍，暫不 commit**

```bash
git diff app/lib/reader/foliate_epub_reader_view.dart
```

確認只有第 379-386 行區塊有變更。**不要 commit**——Task 3A 或 Task 3B 會依決策結果重新做一次乾淨的實作與 commit。

---

## Task 3A：最終修法——直接永久移除（若 Task 2 結果為「兩者皆正常」）

> 只有在「診斷紀錄」記錄「畫線恢復正常且無 regression」時才執行本 Task。否則跳至 Task 3B。

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart:379-386`
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 2 已確認「移除兩行後，畫線恢復且無 regression」
- Produces: `FoliateEpubReaderView` 的 9 宮格 `GestureDetector` 不再註冊 `onHorizontalDragStart`/`onVerticalDragStart`

- [ ] **Step 1: 若 Task 2 的暫時修改仍留在工作目錄，直接沿用；否則重新套用相同變更**

```bash
git diff app/lib/reader/foliate_epub_reader_view.dart
```

確認第 379-386 行的 `GestureDetector` 區塊已不含 `onHorizontalDragStart`/`onVerticalDragStart` 兩行（同 Task 2 Step 1 的變更內容）。若工作目錄是乾淨的（Task 2 結束後曾經 revert），重新手動套用同樣的刪除。

- [ ] **Step 2: 新增回歸測試，明確斷言這兩個 handler 不再註冊**

在 `app/test/reader/foliate_epub_reader_view_test.dart` 內，於既有的 `'3×3 導航熱區：9 個 Key(nav_zone_\$index) 皆存在，點擊觸發對應 onZoneAction'`（第 545-582 行）測試之後，新增：

```dart
  testWidgets(
      '9 宮格熱區的 GestureDetector 不攔截水平/垂直拖曳（讓長按選字後的拖曳手勢可傳遞至底下 WebView）',
      (tester) async {
    await _pumpFoliateEpubReaderView(
      tester,
      FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    );

    for (var index = 0; index < 9; index++) {
      final detector =
          tester.widget<GestureDetector>(find.byKey(Key('nav_zone_$index')));
      expect(detector.onHorizontalDragStart, isNull,
          reason: 'nav_zone_$index 不應攔截水平拖曳手勢（Issue 8：曾導致真機無法'
              '拖曳選取控點建立劃線）');
      expect(detector.onVerticalDragStart, isNull,
          reason: 'nav_zone_$index 不應攔截垂直拖曳手勢（同上）');
    }
  });
```

- [ ] **Step 3: 執行 `flutter analyze` 確保語法與型態檢查無誤**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: 執行既有與新增測試，確認全數通過**

Run: `flutter test app/test/reader/foliate_epub_reader_view_test.dart`
Expected: All tests pass!（含既有的 9 宮格 tap 測試與新增的拖曳斷言測試）

- [ ] **Step 5: 執行全專案測試套件，確認無回歸**

Run: `flutter test`
Expected: All tests pass!

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "fix(epic-18): 移除流式 EPUB 9 宮格熱區的 no-op drag handler，修復真機無法畫線問題"
```

前往 Task 4。

---

## Task 3B：最終修法——僅在無作用中選取範圍時攔截拖曳（若 Task 2 出現 regression）

> 只有在「診斷紀錄」記錄「移除兩行後出現非預期滑動翻頁 regression」時才執行本 Task。若已執行 Task 3A，跳過本 Task。

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`
- Test: `app/test/reader/foliate_epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 2 已確認「移除兩行會讓滑動翻頁 regression 出現」；既有 `_handleMethodCall` 的 `'onSelectionChanged'`（`foliate_epub_reader_view.dart:340-352`）／`'onSelectionCleared'`（`foliate_epub_reader_view.dart:353-354`）case
- Produces: `_FoliateEpubReaderViewState._hasActiveSelection`（`bool`，內部狀態，非 public API）：有作用中選取範圍時為 `true`，此時 9 宮格 `GestureDetector` 不攔截拖曳，讓拖曳選取控點的手勢能傳遞到底下 WebView；無作用中選取範圍時為 `false`，維持原本攔截拖曳、避免滑動翻頁誤觸的行為

- [ ] **Step 1: 若 Task 2 的暫時修改仍留在工作目錄，先還原**

```bash
git checkout -- app/lib/reader/foliate_epub_reader_view.dart
```

確認 `git diff app/lib/reader/foliate_epub_reader_view.dart` 無輸出（已還原成 Task 2 開始前的狀態）。

- [ ] **Step 2: 撰寫失敗測試——驗證 `_hasActiveSelection` 狀態切換 `GestureDetector` 的拖曳攔截**

在 `app/test/reader/foliate_epub_reader_view_test.dart` 內，於既有 `'原生端呼叫 onSelectionCleared 時觸發 widget.onSelectionCleared'`（第 841-881 行）測試之後，新增：

```dart
  testWidgets(
      '有作用中選取範圍時，9 宮格熱區不攔截拖曳；選取清除後恢復攔截',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    int channelId = -1;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        channelId = id;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/foliate_epub_reader_view_$id'),
          (call) async => null,
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();

    // 初始狀態（無選取）：所有格子都攔截拖曳，避免滑動翻頁誤觸。
    for (var index = 0; index < 9; index++) {
      final detector =
          tester.widget<GestureDetector>(find.byKey(Key('nav_zone_$index')));
      expect(detector.onHorizontalDragStart, isNotNull,
          reason: 'nav_zone_$index 初始無選取時應攔截水平拖曳');
      expect(detector.onVerticalDragStart, isNotNull,
          reason: 'nav_zone_$index 初始無選取時應攔截垂直拖曳');
    }

    // 模擬原生端回報選取範圍建立（長按選字後）。
    final channel = MethodChannel(
        'cc.ugotit.elinkbook/foliate_epub_reader_view_$channelId');
    await binaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('onSelectionChanged', {
          'locatorJson': '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}',
          'progression': 0.1,
          'leftPct': 0.1,
          'topPct': 0.2,
          'rightPct': 0.5,
          'bottomPct': 0.3,
        }),
      ),
      (_) {},
    );
    await tester.pump();

    // 有作用中選取範圍時：不攔截拖曳，讓拖曳選取控點的手勢能傳到底下 WebView。
    for (var index = 0; index < 9; index++) {
      final detector =
          tester.widget<GestureDetector>(find.byKey(Key('nav_zone_$index')));
      expect(detector.onHorizontalDragStart, isNull,
          reason: 'nav_zone_$index 有作用中選取範圍時不應攔截水平拖曳'
              '（Issue 8：曾導致真機無法拖曳選取控點建立劃線）');
      expect(detector.onVerticalDragStart, isNull,
          reason: 'nav_zone_$index 有作用中選取範圍時不應攔截垂直拖曳');
    }

    // 模擬選取清除（使用者點擊空白處取消選取）。
    await binaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('onSelectionCleared')),
      (_) {},
    );
    await tester.pump();

    // 選取清除後：恢復攔截拖曳。
    for (var index = 0; index < 9; index++) {
      final detector =
          tester.widget<GestureDetector>(find.byKey(Key('nav_zone_$index')));
      expect(detector.onHorizontalDragStart, isNotNull,
          reason: 'nav_zone_$index 選取清除後應恢復攔截水平拖曳');
      expect(detector.onVerticalDragStart, isNotNull,
          reason: 'nav_zone_$index 選取清除後應恢復攔截垂直拖曳');
    }
  });
```

- [ ] **Step 3: 執行測試確認失敗（因為 `_hasActiveSelection` 狀態尚未實作）**

Run: `flutter test app/test/reader/foliate_epub_reader_view_test.dart`
Expected: FAIL——新增的測試在「有作用中選取範圍時」與「選取清除後」兩段斷言會失敗，因為目前 `onHorizontalDragStart`/`onVerticalDragStart` 一律是固定的空 handler，不會因為選取狀態而變成 `null`。

- [ ] **Step 4: 實作 `_hasActiveSelection` 狀態追蹤**

修改 `app/lib/reader/foliate_epub_reader_view.dart` 的 `_FoliateEpubReaderViewState` 類別（第 233 行起），新增欄位：

```dart
class _FoliateEpubReaderViewState extends State<FoliateEpubReaderView> {
  MethodChannel? _channel;
  // Issue 8：是否有作用中的文字選取範圍。true 時 9 宮格熱區的
  // GestureDetector 不攔截拖曳手勢，讓「拖曳選取控點調整範圍」這個手勢
  // 能傳遞到底下 WebView；false 時維持既有攔截行為，避免滑動手勢被
  // foliate-js 內建的滑動翻頁誤判（見 docs/archive/2026-07-24-
  // epic-7-interaction/design.md:115 的原始設計意圖）。
  bool _hasActiveSelection = false;
```

修改 `_handleMethodCall`（第 313-360 行）的 `'onSelectionChanged'`／`'onSelectionCleared'` 兩個 case，加入 `setState`：

```dart
      case 'onSelectionChanged':
        final args = call.arguments as Map<Object?, Object?>;
        // 審查修正：拖曳選取控點期間，原生端會連續送出多次
        // onSelectionChanged（main.js:435 的 selectionchange 監聽器），
        // 加上狀態檢查避免已經是 true 時還重複觸發不必要的 rebuild。
        if (!_hasActiveSelection) {
          setState(() => _hasActiveSelection = true);
        }
        widget.onSelectionChanged?.call(EpubSelectionInfo(
          locatorJson: args['locatorJson'] as String,
          progression: (args['progression'] as num).toDouble(),
          rect: PercentRect(
            left: (args['leftPct'] as num).toDouble(),
            top: (args['topPct'] as num).toDouble(),
            right: (args['rightPct'] as num).toDouble(),
            bottom: (args['bottomPct'] as num).toDouble(),
          ),
        ));
        break;
      case 'onSelectionCleared':
        setState(() => _hasActiveSelection = false);
        widget.onSelectionCleared?.call();
        break;
```

修改 `build()`（第 362-409 行）內的 `GestureDetector`（第 379-386 行），依 `_hasActiveSelection` 條件式提供 `onHorizontalDragStart`/`onVerticalDragStart`：

```dart
                      child: GestureDetector(
                        key: Key('nav_zone_$index'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onZoneAction?.call(action),
                        onHorizontalDragStart:
                            _hasActiveSelection ? null : (_) {},
                        onVerticalDragStart:
                            _hasActiveSelection ? null : (_) {},
                        child: Container(
```

- [ ] **Step 5: 執行測試確認通過**

Run: `flutter test app/test/reader/foliate_epub_reader_view_test.dart`
Expected: All tests pass!

- [ ] **Step 6: 執行全專案測試套件，確認無回歸**

Run: `flutter test`
Expected: All tests pass!

- [ ] **Step 7: 執行 `flutter analyze` 確保語法與型態檢查無誤**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: 真機重新驗證（確認條件式邏輯在真實手勢下也成立）**

```bash
flutter run -d <device-id>
```

重複 Task 1 Step 3-5：長按選字→確認選取控點出現→拖曳控點確認選取範圍正常擴大/縮小→放開後確認 `AnnotationToolbar` 出現、選色成功建立劃線。接著點擊空白處取消選取，再重複 Task 2 Step 5 的滑動測試，確認滑動翻頁 regression 已消失（因為選取清除後 `_hasActiveSelection` 恢復 `false`，拖曳攔截機制重新生效）。

- [ ] **Step 9: Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "fix(epic-18): 流式 EPUB 9 宮格熱區改為有作用中選取範圍時才放行拖曳，修復真機無法畫線問題"
```

前往 Task 4。

---

## Task 4：最終真機完整回歸驗證

**Files:** 無（純驗證，不變更程式碼）

**Interfaces:**
- Consumes: Task 3A 或 Task 3B 已完成並 commit
- Produces: 「診斷紀錄」第 3 節的最終驗收結果

- [ ] **Step 1: 真機確認畫線功能完整流程**

`flutter run -d <device-id>`，開啟流式 EPUB，長按選字→拖曳控點調整範圍→放開→`AnnotationToolbar` 出現→選一個顏色建立劃線→確認畫面上出現對應顏色的高亮。再測試底線樣式與備註（若原有流程支援）。

- [ ] **Step 2: 真機確認既有換頁與沉浸模式功能未退化**

點擊畫面左右兩側確認翻頁正常；點擊中央確認沉浸模式（AppBar/頁尾顯示切換）正常；確認無非預期的滑動翻頁。

- [ ] **Step 3: 真機確認直排（vertical）書籍的畫線行為同樣正常**

切換至直排模式（或另開一本直排書），重複 Step 1 的畫線流程，確認直排下劃線位置/方向正確（比照既有 `Overlayer.highlight`/`underline` 的 `vertical`/`writingMode` 參數）。

- [ ] **Step 4: 記錄最終驗收結果**

把 Step 1-3 的驗收結果填入本文件「診斷紀錄」的「Task 4 最終驗收」小節，並在 `docs/epics/epic-18-reader-device-qa/issues.md` 的 Issue 8 條目更新 `Status` 與完成摘要（實際更新時機依人類指示，比照本 Epic 既有慣例——程式碼合併回 `main` 後才正式標記為完成，本 Task 完成的是「實作與真機驗證皆通過」，非「已合併」）。

---

## 診斷紀錄

> **本計劃已被 `spike/epic-18-issue-8-inappwebview` 分支上的 Spike 驗證取代。**
> 經過 8 種方案嘗試（見 `reviews/issue-8-selection-detection-report.md`），確認標準 Android WebView + Flutter PlatformView 架構下無法偵測原生文字選取。
> 因此改用 `flutter_inappwebview` 套件進行 Spike 驗證。
> 於 2026-07-26 完成 Task 1（真機選取手勢 adb 觸控模擬，印出 3 筆隨拖曳變化的 `CHANGED` 文字紀錄）與 Task 2（ES module 載入 `module-ok`），結論確定為 **GO ✅**。
> 詳見 `reviews/spike-flutter-inappwebview-selection.md`。

---

## Plan Self-Review Checklist

1. **Spec coverage**（對照 `issues.md` Issue 8 描述）：
   - 真機重現 → Task 1
   - Mutation test（暫時移除兩行，比對畫線恢復/regression）→ Task 2
   - 依結果決定修法（直接移除 vs 條件式攔截）→ Task 3A／3B（兩條路徑皆完整寫出，不預留空白）
   - 確認 tap 熱區導覽功能未退化 → Task 3A Step 2／3B Step 2、Task 4 Step 2
   - 參考 anx-reader 報告（若 Task 2 顯示移除後仍有問題時的備援方向）→ Task 2 Step 6 的分支說明中已引用
2. **Placeholder scan**：Task 3A／3B 皆為完整程式碼與測試，無 "TBD"/"依情況決定" 這類未定內容；「診斷紀錄」小節是刻意留待真機執行時填寫的觀察紀錄格式，不是程式碼或決策的佔位符。
3. **Type consistency**：`_hasActiveSelection`（`bool`）、`onSelectionChanged`/`onSelectionCleared` case 名稱與既有 `foliate_epub_reader_view.dart:340-354` 完全一致；新增測試使用的 `Key('nav_zone_$index')`／channel 命名與既有 `foliate_epub_reader_view_test.dart` 慣例一致。
