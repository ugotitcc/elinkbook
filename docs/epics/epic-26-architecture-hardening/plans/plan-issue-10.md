# Epic 26 Issue 10：拆開 `EpubPositionInfo` 的 `pageIndex`／`location` 語意混用 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 以逐 Task 執行本計畫。步驟採用 checkbox（`- [ ]`）語法追蹤進度。

**Goal:** `EpubPositionInfo` 的 `pageIndex`／`totalPages` 兩個欄位，正常情況下裝的其實是 foliate-js `SectionProgress` 算出的位元組估計刻度（`location.current`／`location.total`），只有在少數退回情況才裝章節序號；欄位名稱卻讓呼叫端誤以為拿到的是精確視覺頁碼。本 Issue 把這兩個欄位拆成語意誠實、互斥的兩組：`locationIndex`／`locationTotal`（流式格式，估計值）與 `visualPageIndex`／`visualTotalPages`（FXL／CBZ，全書真實頁碼），讓介面精度誠實對應底層實作精度。

**Architecture:** 主要為純介面重構，流式格式不改變任何使用者可觀察行為；FXL／CBZ 頁尾顯示則有一項刻意保留的附帶修正（見 Global Constraints「零行為改變」條目與 `issues.md` Issue 10「實作後追加澄清」）。`main.js` 的 `onLocatorChanged` payload 從 4 個 positional 參數改為 2 個參數（`locatorJson` 字串維持不動＋新的具名 JSON 物件），依 `view.isFixedLayout` 分流只填其中一組頁碼欄位。Dart 端新增 `foliate_bridge_codec.dart` 的 `parseLocatorChanged()` 純函式（比照既有 `extractCfi()`／`parseTableOfContents()` 慣例，把 JS→Dart 邊界的解析邏輯從 widget 內的匿名 closure 抽成可直接單元測試的頂層函式），`EpubPositionInfo` 新增 `displayPageIndex`／`displayTotalPages` 兩個便利 getter（`visualPageIndex ?? locationIndex`／`visualTotalPages ?? locationTotal`）集中「挑值」邏輯，`reader_screen.dart` 的 3 處消費點改用這兩個 getter。

**Tech Stack:** Flutter／Dart（JS→Dart 橋接解析）＋ `flutter_inappwebview` JS 橋接（payload 形狀）。無新增套件依賴。

**Spec:** `docs/epics/epic-26-architecture-hardening/issues.md` Issue 10；`docs/research/architecture-review-flowable-pagination-precision.md` 候選 1；`/grilling` 會談記錄（Q1-Q11，本文件「規劃階段查證」逐項落地）。

## 規劃階段查證：欄位對帳、FXL 真頁碼佐證、持久化邊界、既有測試分類（務必先讀）

1. **`main.js:560-575` 現況三種語意，逐一核實。** `pageIndex = section?.current ?? 0`（`main.js:562`）是章節／spine index；`location?.current ?? pageIndex`（`main.js:573`，送給 Dart 端 `EpubPositionInfo.pageIndex` 的實際值）正常情況下是 `location.current`（位元組估計刻度），只有 `location` 不存在時才退回章節序號——這代表舊欄位名稱「pageIndex」對應的實際語意會依情境在兩種完全不同的東西之間切換。FXL 書籍另外有 `if (view.isFixedLayout && !totalPages && view.renderer) { pageIndex = view.renderer.page; totalPages = view.renderer.pages }`（`main.js:565-567`）覆寫路徑。

2. **FXL／CBZ 的 `view.renderer.page`／`.pages` 是全書真實視覺頁碼，非渲染視窗內的估計——與流式格式的 `Paginator.page`／`.pages`（`paginator.js:1968-1976`，只反映目前渲染視窗內的頁數）是完全不同的類別。** 已查證 `fixed-layout.js:1586-1593`：`get pages() { if (this.#scrollMode) return this.#scrollPages.length; return this.#spreads?.length ?? 0 }`——`#spreads` 是開書當下就算好的全書 spread 陣列，不依賴目前渲染了多少 section，精度等同實際渲染結果。這是本 Issue 決定「FXL 走 `visualPageIndex`（真頁碼）、流式走 `locationIndex`（估計值），而非兩者共用一個改名後的欄位」的關鍵。

3. **`locatorJson`（`main.js:571` 第一個參數）持久化＋跨裝置同步，內容維持完全不動。** 已查證 `reader_screen.dart` 多處把 `_epubPositionInfo?.locatorJson`（或其他來源的 `EpubPositionInfo.locatorJson`）原樣寫入 `epubLocatorJson`（書籤／劃線／備註／`ReadingPosition`），且 `sync_engine.dart`／`sync_reading_position.dart` 會把這個欄位跨裝置同步到 PocketBase。位置估計值是「這台裝置這次算出來的」，若塞進同一包 JSON 會被永久存進跨裝置同步紀錄，語意錯誤——因此 `locatorJson` 維持獨立參數，新的 `position` 物件（`fraction`／`locationIndex`／`locationTotal`／`visualPageIndex`／`visualTotalPages`）是另一個完全獨立、只供即時 UI 顯示用途的第二參數，不落地persist。

4. **`main.js:571` 內嵌在 `locatorJson` JSON 字串裡的 `index`（章節序號，第三種語意）維持原樣不動，不在本 Issue 範圍內。** 已查證 `foliate_bridge_codec.dart` 的 `extractCfi()` 只讀取 `cfi` 鍵，從未讀取 `index`／`fraction` 兩個鍵——這是寫入後沒人讀的孤兒資料，目前不會造成任何行為混淆，動它超出「只解決正在造成混淆的語意」這個範圍。

5. **`_writeCurrentPosition()`（`reader_screen.dart:546-587`）EPUB 分支完全不使用 `pageIndex`／`totalPages`，只用 `progression`／`locatorJson`，不受本 Issue 影響。** 已逐行核對該方法的 EPUB／TXT／MD／AZW3／CBZ 分支（`reader_screen.dart:562-587`），確認閱讀位置持久化走的是 `progression`，與本次改動的兩組頁碼欄位無關，不需要修改。

6. **`reader_screen.dart` 內實際讀取 `EpubPositionInfo.pageIndex`／`.totalPages` 的消費點恰好 3 處**（已用 `grep` 排除 `PdfPageInfo`／`PdfTocItem`／`PdfSearchMatch`／`PdfSelectionInfo` 等同名但不相關的 PDF 端欄位）：
   - `reader_screen.dart:2317`（頁尾／進度文字的顯示 gating 條件 `(_epubPositionInfo?.totalPages ?? 0) > 0`）。
   - `reader_screen.dart:2437-2440`（`_buildFoliateProgressText()`）。
   - `reader_screen.dart:2506-2509`（`_buildFoliateEpubFooter()`）。
   `ReaderFooter`（`reader_footer.dart`）本身格式無關，只接收已換算好的 `currentPage`／`totalPages` 整數，不需要修改。

7. **`reader_screen_test.dart` 有 22 處 `EpubPositionInfo(...)` 建構呼叫，但只有 15 處實際帶 `pageIndex:`／`totalPages:` 值（其餘 7 處只設 `locatorJson`／`progression`，不受本次欄位改名影響，零修改）。** 已用腳本逐一比對每處建構呼叫附近的 `testWidgets()` 標題，15 處中：
   - **14 處**測試標題含「流式 EPUB」字樣（`3105/3144/3243/3634/3720/3787/3854/4126/4173/4228/4282/4340/4396/5168/5241`，其中 `3144`／`5168`／`5241` 為多行標題、行號指向 `EpubPositionInfo(` 本身），欄位改為 `locationIndex`／`locationTotal`。
   - **1 處**（`5300`，測試標題「EPUB 固定版面：不論主題為何，頁首/頁尾文字色維持既有寫死 Colors.black」）是 FXL 情境，欄位改為 `visualPageIndex`／`visualTotalPages`。
   - 另外 4 處 FXL 標題測試（`2249/2338/2402/2467`，書籤/筆記相關）**不在**這 15 處清單內——這些測試的 `EpubPositionInfo(...)` 建構只設 `locatorJson`／`progression`，從未帶 `pageIndex`／`totalPages` 值，本次零修改。

**結論：** JS 端（`main.js`）改動範圍限縮在 `relocate` 事件處理常式本身；Dart 端改動限縮在 `epub_position_info.dart`（型別）、`foliate_bridge_codec.dart`（新增純函式）、`foliate_reader_view.dart`（handler 改呼叫新函式）、`reader_screen.dart`（3 處消費點）、`reader_screen_test.dart`（15 處欄位改名，其餘 7 處不動），以及 `integration_test/foliate_single_column_test.dart`／`foliate_toc_footer_test.dart` 共 5 處直接讀取舊欄位的斷言（審查報告 Important #1 補上，見 Task 4 Step 3）。

## Global Constraints

- 程式碼註解／變數說明使用中文，遵循既有檔案風格。
- 零行為改變（僅限流式格式）：流式書籍的頁尾／進度顯示、跳頁互動，改動前後輸出完全一致（`locationIndex` 挑值結果，等同舊 `pageIndex` 原本在對應情境下的實際值）。FXL／CBZ **不在此保證範圍內**——程式審查（`reviews/review-issue-10.md` Important #2）發現並經查證屬實：main.js 重構前 FXL 覆寫條件多了 `!totalPages`，但 `location.total`（`Math.ceil(sizeTotal/1500)`）對任何有實際內容的書籍恆 `>= 1`，該條件在真實書籍上幾乎從未成立過，FXL／CBZ 先前實際顯示的其實是位元組估計值而非真頁碼；本次重構順帶移除這個從未生效的條件閘，讓 FXL／CBZ 一律採用真實視覺頁數，是刻意保留的一次附帶修正，詳見 `issues.md` Issue 10「實作後追加澄清」。
- 硬換名，不保留 `pageIndex`／`totalPages` 作為 deprecated alias。
- 本 Issue 不涉及 `main.js` 內嵌 `index` 欄位（`locatorJson` 內部結構）、不新增 UI 上的「估計值」視覺標示、不牴觸任何 ADR（純介面重構）。
- `main.js` 無自動化測試框架可用（比照專案既有兩層測試架構限制，見 CLAUDE.md「兩層測試架構」），Task 2 的驗證手段是逐鍵核對 payload 形狀與 Task 1 `parseLocatorChanged()` 讀取的鍵名完全一致，而非新增 JS 測試。
- Commit message 慣例：`refactor(epic-26): Issue 10 Task N——<描述>`。
- 中繼編譯狀態（審查報告 Minor #3）：Task 1 移除 `EpubPositionInfo` 舊欄位後，到 Task 4 改完 `reader_screen_test.dart` 與 2 份整合測試檔案為止，全專案處於預期中的編譯失敗狀態——Task 1-3 一律只執行限定路徑的 `flutter test <指定檔案>` 或 `flutter analyze lib/`，不要在此期間執行未限定路徑的全專案 `flutter test`／`flutter analyze`，待 Task 4 完成後才在 Task 5 執行全專案驗證。

---

### Task 1：`EpubPositionInfo` 新欄位＋`parseLocatorChanged()` 純函式（TDD）

**Files:**
- Modify: `app/lib/reader/epub_position_info.dart`
- Modify: `app/lib/reader/foliate_bridge_codec.dart`
- Modify: `app/lib/reader/foliate_reader_view.dart`
- Test: `app/test/reader/foliate_bridge_codec_test.dart`

**Interfaces:**
- Produces：`EpubPositionInfo({required String locatorJson, double? progression, int? locationIndex, int? locationTotal, int? visualPageIndex, int? visualTotalPages})`，新增 `int? get displayPageIndex`／`int? get displayTotalPages` 兩個 getter。
- Produces：`EpubPositionInfo parseLocatorChanged(List<dynamic> args)`（`foliate_bridge_codec.dart`）。

- [x] **Step 1：寫失敗測試，涵蓋 `parseLocatorChanged()` 的流式／FXL／缺席／格式錯誤四種情境，以及 `displayPageIndex`／`displayTotalPages` 兩個 getter**

```dart
// app/test/reader/foliate_bridge_codec_test.dart
// 檔案頂端新增 import：
// import 'package:elinkbook/reader/epub_position_info.dart';
//
// 於既有 group('extractCfi', ...) 之後新增：

  group('parseLocatorChanged', () {
    test('流式格式：position 帶 locationIndex/locationTotal，'
        'visualPageIndex/visualTotalPages 為 null', () {
      final info = parseLocatorChanged([
        '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        '{"fraction":0.1,"locationIndex":9,"locationTotal":100,'
            '"visualPageIndex":null,"visualTotalPages":null}',
      ]);
      expect(info.locatorJson, '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}');
      expect(info.progression, 0.1);
      expect(info.locationIndex, 9);
      expect(info.locationTotal, 100);
      expect(info.visualPageIndex, isNull);
      expect(info.visualTotalPages, isNull);
    });

    test('FXL/CBZ 格式：position 帶 visualPageIndex/visualTotalPages，'
        'locationIndex/locationTotal 為 null', () {
      final info = parseLocatorChanged([
        '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.5}',
        '{"fraction":0.5,"locationIndex":null,"locationTotal":null,'
            '"visualPageIndex":3,"visualTotalPages":20}',
      ]);
      expect(info.locationIndex, isNull);
      expect(info.locationTotal, isNull);
      expect(info.visualPageIndex, 3);
      expect(info.visualTotalPages, 20);
    });

    test('args 只有 1 個元素（第二參數缺席）：位置欄位皆為 null，'
        'progression 退回 0.0，locatorJson 仍取自 args[0]', () {
      final info = parseLocatorChanged(['{"cfi":"epubcfi(/6/4)"}']);
      expect(info.locatorJson, '{"cfi":"epubcfi(/6/4)"}');
      expect(info.progression, 0.0);
      expect(info.locationIndex, isNull);
      expect(info.locationTotal, isNull);
      expect(info.visualPageIndex, isNull);
      expect(info.visualTotalPages, isNull);
    });

    test('args 為空清單：locatorJson 為空字串，位置欄位皆為 null', () {
      final info = parseLocatorChanged(const []);
      expect(info.locatorJson, '');
      expect(info.progression, 0.0);
      expect(info.locationIndex, isNull);
    });

    test('args[1] 格式錯誤（非合法 JSON）：位置欄位皆為 null，不拋出例外', () {
      final info = parseLocatorChanged([
        '{"cfi":"epubcfi(/6/4)"}',
        'not a json string',
      ]);
      expect(info.locationIndex, isNull);
      expect(info.locationTotal, isNull);
      expect(info.visualPageIndex, isNull);
      expect(info.visualTotalPages, isNull);
    });
  });

  group('EpubPositionInfo.displayPageIndex / displayTotalPages', () {
    test('流式格式（只有 locationIndex/locationTotal 有值）：'
        'display getter 退回採用 location 值', () {
      const info = EpubPositionInfo(
        locatorJson: '{}',
        locationIndex: 9,
        locationTotal: 100,
      );
      expect(info.displayPageIndex, 9);
      expect(info.displayTotalPages, 100);
    });

    test('FXL 格式（只有 visualPageIndex/visualTotalPages 有值）：'
        'display getter 優先採用 visual 值', () {
      const info = EpubPositionInfo(
        locatorJson: '{}',
        visualPageIndex: 3,
        visualTotalPages: 20,
      );
      expect(info.displayPageIndex, 3);
      expect(info.displayTotalPages, 20);
    });

    test('兩組皆為 null（尚未收到任何 relocate 事件）：display getter 回傳 null',
        () {
      const info = EpubPositionInfo(locatorJson: '{}');
      expect(info.displayPageIndex, isNull);
      expect(info.displayTotalPages, isNull);
    });
  });
```

- [x] **Step 2：執行測試確認失敗（`parseLocatorChanged`／新欄位／新 getter 尚未存在，編譯失敗）**

執行：`cd app && flutter test test/reader/foliate_bridge_codec_test.dart`
預期：`FAIL`，編譯期錯誤（找不到 `parseLocatorChanged`、`EpubPositionInfo` 找不到 `locationIndex` 等具名參數）。

- [x] **Step 3：`epub_position_info.dart` 改為新欄位＋新增 `displayPageIndex`/`displayTotalPages` getter**

修改 `app/lib/reader/epub_position_info.dart`，整份取代為：

```dart
/// [EpubReaderView]／[FoliateEpubReaderView] 目前定位變動時（開書完成、
/// 翻頁、跳轉）一次性回報的位置資訊（epic-5-toc-pagination Issue 2）。
/// [locatorJson] 對 [EpubReaderView] 是原生端 `Locator.toJSON().toString()`
/// 的原樣字串；對 [FoliateEpubReaderView] 是 epic-17-epub-render-migration
/// Issue 6 新增的 CFI 格式 JSON 字串（`{"cfi":...,"index":...,"fraction":...}`，
/// 見 spec.md「資料模型」）——兩種格式完全不相容，但 Dart 端不解析其內部
/// 結構、只負責持久化與之後原樣傳回原生端還原，型別簽章不需要區分兩者。
/// [locatorJson] 會被持久化到書籤／劃線／備註／閱讀進度並跨裝置同步，
/// 內容必須與底下四個頁碼欄位（僅供即時 UI 顯示用途、不落地persist）完全
/// 脫鉤（epic-26-architecture-hardening Issue 10 規劃階段查證）。
/// [progression] 是原生端額外拆出的全書進度比例平面數值，供 Dart 端直接
/// 用於 `Book.progress` 而不需要自行解析 [locatorJson] 的巢狀 JSON 結構。
///
/// [locationIndex]/[locationTotal] 與 [visualPageIndex]/[visualTotalPages]
/// （epic-26-architecture-hardening Issue 10，取代原本混用的 pageIndex/
/// totalPages）是兩組精度完全不同、互斥的頁碼欄位——同一本書恆有一組為
/// `null`，只有 [FoliateEpubReaderView] 會回報非 null 值，[EpubReaderView]
/// （Readium）兩組皆永遠為 `null`：
/// - [locationIndex]/[locationTotal]：流式格式（EPUB 流式／TXT／MD）專用，
///   foliate-js `SectionProgress.getProgress()` 的 `location.current`／
///   `location.total`——以 spine 檔案未壓縮位元組數除以固定常數 1500 算出的
///   近似刻度，與畫面實際渲染出來的視覺頁完全無關，僅供粗略進度顯示用途
///   （見 `CONTEXT.md`「Location 刻度」詞條）。FXL／CBZ 恆為 `null`。
/// - [visualPageIndex]/[visualTotalPages]：固定版面（FXL）／CBZ 專用，
///   foliate-js `FixedLayout`（`fixed-layout.js`）的 `page`/`pages`——全書
///   真實視覺頁數，精度等同實際渲染結果（見 `CONTEXT.md`「視覺頁碼」
///   詞條）。流式格式恆為 `null`（`docs/research/
///   architecture-review-flowable-pagination-precision.md` 候選 2 落地後
///   才會有值）。
/// [displayPageIndex]/[displayTotalPages] 是集中「挑值」邏輯的便利 getter，
/// `ReaderScreen` 建構頁尾一律用這兩個 getter，不直接依賴任何一組單獨欄位。
class EpubPositionInfo {
  final String locatorJson;
  final double? progression;
  final int? locationIndex;
  final int? locationTotal;
  final int? visualPageIndex;
  final int? visualTotalPages;

  const EpubPositionInfo({
    required this.locatorJson,
    this.progression,
    this.locationIndex,
    this.locationTotal,
    this.visualPageIndex,
    this.visualTotalPages,
  });

  /// 優先採用精確的視覺頁碼，只有在該格式沒有視覺頁碼資料時（目前是全部
  /// 流式格式）才退回估計刻度。
  int? get displayPageIndex => visualPageIndex ?? locationIndex;
  int? get displayTotalPages => visualTotalPages ?? locationTotal;

  @override
  bool operator ==(Object other) =>
      other is EpubPositionInfo &&
      other.locatorJson == locatorJson &&
      other.progression == progression &&
      other.locationIndex == locationIndex &&
      other.locationTotal == locationTotal &&
      other.visualPageIndex == visualPageIndex &&
      other.visualTotalPages == visualTotalPages;

  @override
  int get hashCode => Object.hash(locatorJson, progression, locationIndex,
      locationTotal, visualPageIndex, visualTotalPages);

  @override
  String toString() =>
      'EpubPositionInfo(locatorJson: $locatorJson, progression: $progression, '
      'locationIndex: $locationIndex, locationTotal: $locationTotal, '
      'visualPageIndex: $visualPageIndex, visualTotalPages: $visualTotalPages)';
}
```

- [x] **Step 4：`foliate_bridge_codec.dart` 新增 `parseLocatorChanged()`**

在檔案頂端新增 `import 'epub_position_info.dart';`，並在 `extractCfi()` 之後、`parseTableOfContents()` 之前新增：

```dart
/// 把 `main.js` `onLocatorChanged` relocate handler 送出的 JS→Dart 橋接
/// 參數（epic-26-architecture-hardening Issue 10，取代原本 4 個 positional
/// 參數混用 pageIndex/location 語意的舊格式）解析為 [EpubPositionInfo]。
/// [args] 恰好 2 個元素：`args[0]` 為 [EpubPositionInfo.locatorJson]（含
/// cfi 的字串，原樣不動，見 [extractCfi]）；`args[1]` 為具名 JSON 物件
/// 字串，包含 `fraction`／`locationIndex`／`locationTotal`／
/// `visualPageIndex`／`visualTotalPages` 五個鍵，依書籍是否為固定版面
/// （FXL／CBZ）互斥填值。[args] 元素不足、`args[1]` 缺席或格式錯誤時，
/// 位置相關欄位一律回傳 `null`，不拋出例外（比照 [extractCfi] 既有的優雅
/// 退回原則）。
EpubPositionInfo parseLocatorChanged(List<dynamic> args) {
  final locatorJson =
      args.isNotEmpty && args[0] is String ? args[0] as String : '';
  Map<String, dynamic> position = const {};
  if (args.length > 1 && args[1] is String) {
    try {
      final decoded = jsonDecode(args[1] as String);
      if (decoded is Map<String, dynamic>) position = decoded;
    } catch (_) {
      // 格式錯誤時維持空 map，位置相關欄位一律回傳 null。
    }
  }
  return EpubPositionInfo(
    locatorJson: locatorJson,
    progression: (position['fraction'] as num?)?.toDouble() ?? 0.0,
    locationIndex: (position['locationIndex'] as num?)?.toInt(),
    locationTotal: (position['locationTotal'] as num?)?.toInt(),
    visualPageIndex: (position['visualPageIndex'] as num?)?.toInt(),
    visualTotalPages: (position['visualTotalPages'] as num?)?.toInt(),
  );
}
```

- [x] **Step 5：`foliate_reader_view.dart` 的 `onLocatorChanged` handler 改呼叫 `parseLocatorChanged()`**

修改 `app/lib/reader/foliate_reader_view.dart`，原本（`foliate_reader_view.dart:648-666`）：

```dart
    controller.addJavaScriptHandler(
      handlerName: 'onLocatorChanged',
      callback: (args) {
        // 審查修正：main.js 目前以 `fraction ?? 0`／`location?.current ?? 0`／
        // `location?.total ?? 0` 保底，理論上不會送出 null；但改用 `as num?`
        // + `?? 0` 防禦性轉型，與本檔案其餘 handler（onPageRendered/onError/
        // onTableOfContentsReady 的 `args.isNotEmpty` 檢查）保持一致的防禦
        //風格，避免未來 main.js 若不慎移除 `?? 0` 保底時整個閱讀畫面直接
        // 因 TypeError 崩潰。
        widget.onLocatorChanged?.call(EpubPositionInfo(
          locatorJson: args.isNotEmpty ? args[0] as String : '',
          progression:
              (args.length > 1 ? args[1] as num? : null)?.toDouble() ?? 0.0,
          pageIndex:
              (args.length > 2 ? args[2] as num? : null)?.toInt() ?? 0,
          totalPages:
              (args.length > 3 ? args[3] as num? : null)?.toInt() ?? 0,
        ));
      },
    );
```

改為：

```dart
    controller.addJavaScriptHandler(
      handlerName: 'onLocatorChanged',
      // epic-26-architecture-hardening Issue 10：解析邏輯抽成
      // foliate_bridge_codec.dart 的 parseLocatorChanged() 純函式（比照
      // extractCfi()/parseTableOfContents() 既有慣例），可脫離 WebView
      // 直接單元測試，不再是這個 widget 內無法獨立驗證的匿名 closure。
      callback: (args) =>
          widget.onLocatorChanged?.call(parseLocatorChanged(args)),
    );
```

- [x] **Step 6：執行測試確認 Step 1 新增的案例全數通過**

執行：`cd app && flutter test test/reader/foliate_bridge_codec_test.dart`
預期：`PASS`。

- [x] **Step 7：Commit**

```bash
git add app/lib/reader/epub_position_info.dart app/lib/reader/foliate_bridge_codec.dart app/lib/reader/foliate_reader_view.dart app/test/reader/foliate_bridge_codec_test.dart
git commit -m "refactor(epic-26): Issue 10 Task 1——EpubPositionInfo 新欄位與 parseLocatorChanged() 純函式（TDD）"
```

---

### Task 2：`main.js` 的 `onLocatorChanged` 改為兩參數、依格式分流填值

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

- [x] **Step 1：修改 `relocate` 事件處理常式**

修改 `app/android/app/src/main/assets/foliate/main.js`，原本（`main.js:549-576`，含前導註解）：

```js
    // FR-06/onPageRendered 監聽器各自獨立、互不影響，開書當下的第一次
    // relocate 事件兩者皆會觸發。location.current／location.total 為
    // foliate-js SectionProgress.getProgress() 既有輸出（見
    // progress.js），近似頁碼概念，非精確渲染頁數。
    // Epic 20 Issue 2：FXL 書籍的 relocate 事件 e.detail 欄位形狀可能與
    // 流式書籍不同——fixed-layout.js 有 page/pages/index 等 getter，但
    // location.current/location.total 可能不存在。依 view.isFixedLayout 分流
    // 組裝 onLocatorChanged payload，確保 FXL 書籍的 pageIndex/totalPages
    // 仍有意義。
    view.addEventListener('relocate', (e) => {
      const { cfi, section, fraction, location } = e.detail
      let pageIndex = section?.current ?? 0
      let totalPages = location?.total ?? 0
      // FXL 書籍：若 location.current/total 不存在，改用 renderer 的 page/pages
      if (view.isFixedLayout && !totalPages && view.renderer) {
        pageIndex = view.renderer.page ?? pageIndex
        totalPages = view.renderer.pages ?? totalPages
      }
      window.flutter_inappwebview.callHandler(
        'onLocatorChanged',
        JSON.stringify({ cfi, index: pageIndex, fraction: fraction ?? 0 }),
        fraction ?? 0,
        location?.current ?? pageIndex,
        totalPages,
      )
    })
```

改為：

```js
    // FR-06/onPageRendered 監聽器各自獨立、互不影響，開書當下的第一次
    // relocate 事件兩者皆會觸發。
    // epic-26-architecture-hardening Issue 10：payload 改為兩參數——
    // 第 1 個參數（locatorJson）內容維持不動，會被 Dart 端持久化並跨裝置
    // 同步，不可混入下方估計/真實頁碼；第 2 個參數是具名 JSON 物件，依
    // view.isFixedLayout 分流只填其中一組頁碼欄位，另一組明確傳 null
    // （取代原本 pageIndex/totalPages 兩個欄位在不同格式下語意不一致的
    // 舊寫法）。
    view.addEventListener('relocate', (e) => {
      const { cfi, section, fraction, location } = e.detail
      // locatorJson 內嵌的 index 是章節/spine index，非頁碼——沿用既有
      // 寫法不動（extractCfi() 從未讀取這個鍵，見規劃階段查證）。
      const chapterIndex = section?.current ?? 0
      const position = view.isFixedLayout && view.renderer
        // FXL/CBZ：view.renderer.page/.pages（fixed-layout.js）是全書
        // 真實視覺頁數，非估計值。
        ? {
            fraction: fraction ?? 0,
            locationIndex: null,
            locationTotal: null,
            visualPageIndex: view.renderer.page ?? 0,
            visualTotalPages: view.renderer.pages ?? 0,
          }
        // 流式格式：location.current/.total 是 SectionProgress 的位元組
        // 估計刻度（每 1500 bytes 一個刻度），非精確視覺頁數。
        : {
            fraction: fraction ?? 0,
            locationIndex: location?.current ?? chapterIndex,
            locationTotal: location?.total ?? 0,
            visualPageIndex: null,
            visualTotalPages: null,
          }
      window.flutter_inappwebview.callHandler(
        'onLocatorChanged',
        JSON.stringify({ cfi, index: chapterIndex, fraction: fraction ?? 0 }),
        JSON.stringify(position),
      )
    })
```

- [x] **Step 2：逐鍵核對 payload 形狀與 Task 1 `parseLocatorChanged()` 完全一致（無 JS 測試框架，手動核對取代自動化測試）**

核對清單：
- [x] `callHandler` 第 1 個參數（字串）：`args[0]`，`parseLocatorChanged()` 原樣取用為 `locatorJson`——確認未變更内部結構（仍是 `{cfi, index, fraction}`）。
- [x] `callHandler` 第 2 個參數（`JSON.stringify(position)`）：`args[1]`，`parseLocatorChanged()` 用 `jsonDecode` 還原後讀取 `fraction`／`locationIndex`／`locationTotal`／`visualPageIndex`／`visualTotalPages` 五個鍵——逐一確認 `main.js` 兩個分支（FXL／流式）皆完整填滿這五個鍵（互斥的一組為 `null`），鍵名逐字相同（大小寫敏感）。
- [x] FXL 分支：`visualPageIndex`/`visualTotalPages` 為 `view.renderer.page ?? 0`/`view.renderer.pages ?? 0`（`?? 0` 是既有退回值，非本次新增邏輯，維持原樣）。
- [x] 流式分支：`locationIndex`/`locationTotal` 為 `location?.current ?? chapterIndex`/`location?.total ?? 0`（與舊版 `pageIndex`/`totalPages` 在對應情境下的計算方式逐一比對相同，只是欄位名稱與位置改變）。

- [x] **Step 3：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "refactor(epic-26): Issue 10 Task 2——main.js onLocatorChanged 改為兩參數、依格式分流填值"
```

---

### Task 3：`reader_screen.dart` 消費端改用 `displayPageIndex`/`displayTotalPages`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`

- [x] **Step 1：頁尾／進度文字顯示 gating 條件**

修改 `app/lib/screens/reader_screen.dart:2315-2317`，原本：

```dart
            if (isFoliateFormat(format) &&
                (_resolved?.showFooter ?? false) &&
                (_epubPositionInfo?.totalPages ?? 0) > 0)
```

改為：

```dart
            if (isFoliateFormat(format) &&
                (_resolved?.showFooter ?? false) &&
                (_epubPositionInfo?.displayTotalPages ?? 0) > 0)
```

- [x] **Step 2：`_buildFoliateProgressText()`，並改寫過時 doc comment**

修改 `app/lib/screens/reader_screen.dart:2431-2440`，原本：

```dart
  /// 流式 EPUB 進度純顯示（epic-18-reader-device-qa Issue 7）：內容換算邏輯
  /// 與 _buildFoliateEpubFooter() 相同（pageIndex/totalPages 皆為 0-indexed/
  /// 近似頁碼，+1 換算為人類慣用的 1-indexed），呼叫端已保證
  /// totalPages > 0 才會建構本 widget。跳頁互動已獨立到
  /// reader_foliate_progress_button 開啟的 Bottom Sheet，本 widget 不含任何
  /// 手勢 widget。
  Widget _buildFoliateProgressText() {
    final info = _epubPositionInfo!;
    final totalPages = info.totalPages!;
    final currentPage = ((info.pageIndex ?? 0) + 1).clamp(1, totalPages);
```

改為：

```dart
  /// 流式 EPUB 進度純顯示（epic-18-reader-device-qa Issue 7）：內容換算邏輯
  /// 與 _buildFoliateEpubFooter() 相同（displayPageIndex/displayTotalPages
  /// 皆為 0-indexed，+1 換算為人類慣用的 1-indexed，見
  /// epic-26-architecture-hardening Issue 10：兩個 getter 依格式互斥挑選
  /// 精確視覺頁碼或估計刻度），呼叫端已保證 displayTotalPages > 0 才會
  /// 建構本 widget。跳頁互動已獨立到 reader_foliate_progress_button 開啟的
  /// Bottom Sheet，本 widget 不含任何手勢 widget。
  Widget _buildFoliateProgressText() {
    final info = _epubPositionInfo!;
    final totalPages = info.displayTotalPages!;
    final currentPage =
        ((info.displayPageIndex ?? 0) + 1).clamp(1, totalPages);
```

- [x] **Step 3：`_buildFoliateEpubFooter()`，並改寫過時 doc comment**

修改 `app/lib/screens/reader_screen.dart:2498-2509`，原本：

```dart
  /// 流式 EPUB（FoliateReaderView）頁尾（epic-17-epub-render-migration
  /// Issue 6）：直接使用原生端 relocate 事件回報的 pageIndex／totalPages
  /// （foliate-js SectionProgress.getProgress() 的 location.current／
  /// location.total，近似頁碼概念，非精確渲染頁數，見 spec.md「頁碼
  /// 估算」）。pageIndex 為 0-indexed（比照原生端既有慣例），ReaderFooter
  /// 要求 1-indexed，此處 +1 換算。onPageChanged 透過既有
  /// jumpToProgression（Issue 5）換算目標頁對應的全書進度比例（近似值，
  /// 非精確反解頁碼）。
  Widget _buildFoliateEpubFooter(EpubPositionInfo info) {
    final totalPages = info.totalPages ?? 0;
    if (totalPages <= 0) return const SizedBox.shrink();
    final currentPage = ((info.pageIndex ?? 0) + 1).clamp(1, totalPages);
```

改為：

```dart
  /// 流式 EPUB／FXL／CBZ（FoliateReaderView）頁尾：直接使用原生端 relocate
  /// 事件回報的 displayPageIndex／displayTotalPages（epic-26-architecture-
  /// hardening Issue 10：流式格式是 foliate-js SectionProgress 的位元組
  /// 估計刻度，FXL／CBZ 是 FixedLayout 的全書真實視覺頁數，兩個 getter
  /// 依格式互斥挑選，見 EpubPositionInfo 型別文件）。displayPageIndex 為
  /// 0-indexed（比照原生端既有慣例），ReaderFooter 要求 1-indexed，此處
  /// +1 換算。onPageChanged 透過既有 jumpToProgression（Issue 5）換算目標
  /// 頁對應的全書進度比例（流式格式為近似值，非精確反解頁碼；FXL/CBZ 沿用
  /// 既有行為不變）。
  Widget _buildFoliateEpubFooter(EpubPositionInfo info) {
    final totalPages = info.displayTotalPages ?? 0;
    if (totalPages <= 0) return const SizedBox.shrink();
    final currentPage =
        ((info.displayPageIndex ?? 0) + 1).clamp(1, totalPages);
```

- [x] **Step 4：執行 `flutter analyze` 確認編譯乾淨（本 Task 尚未更新測試檔，預期此時 `reader_screen_test.dart` 因舊欄位名消失而編譯失敗，屬預期中的中繼狀態，留待 Task 4 處理）**

執行：`cd app && flutter analyze lib/`
預期：`No issues found!`（僅檢查 `lib/`，`test/` 留待 Task 4 完成後再一併驗證）。

- [x] **Step 5：Commit**

```bash
git add app/lib/screens/reader_screen.dart
git commit -m "refactor(epic-26): Issue 10 Task 3——reader_screen.dart 消費端改用 displayPageIndex/displayTotalPages"
```

---

### Task 4：`reader_screen_test.dart` 既有 15 處呼叫點，以及 2 份整合測試檔案欄位改名

**Files:**
- Modify: `app/test/screens/reader_screen_test.dart`
- Modify: `app/integration_test/foliate_single_column_test.dart`
- Modify: `app/integration_test/foliate_toc_footer_test.dart`

- [x] **Step 1：14 處「流式 EPUB」情境，`pageIndex:`/`totalPages:` 改為 `locationIndex:`/`locationTotal:`**

涉及行號（改動前，逐一核對後手動修改，數值本身不變，只改欄位名）：`3105-3109`／`3144-3148`（`pageIndex=9 totalPages=100`）、`3243-3247`（`pageIndex=0 totalPages=0`）、`3634-3638`／`3720-3724`／`3787-3791`／`4282-4286`／`4396-4400`（`pageIndex=0 totalPages=10`）、`4126-4130`／`4173-4177`／`4228-4232`（`pageIndex=167 totalPages=197`）、`4340-4344`（`pageIndex=9 totalPages=100`）、`5168-5172`／`5241-5245`（`pageIndex=9 totalPages=100`）。

範例（`3105-3110`），原本：

```dart
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        pageIndex: 9,
        totalPages: 100,
      ),
```

改為：

```dart
      const EpubPositionInfo(
        locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        progression: 0.1,
        locationIndex: 9,
        locationTotal: 100,
      ),
```

其餘 13 處比照同一模式（`pageIndex: N` → `locationIndex: N`，`totalPages: N` → `locationTotal: N`，`locatorJson`/`progression` 值不動）逐一修改。

- [x] **Step 2：1 處「EPUB 固定版面」（FXL）情境，`pageIndex:`/`totalPages:` 改為 `visualPageIndex:`/`visualTotalPages:`**

修改 `reader_screen_test.dart:5296-5305` 附近（測試標題「EPUB 固定版面：不論主題為何，頁首/頁尾文字色維持既有寫死 Colors.black」），原本：

```dart
      const EpubPositionInfo(
        locatorJson: '...',
        progression: ...,
        pageIndex: 9,
        totalPages: 100,
      ),
```

改為：

```dart
      const EpubPositionInfo(
        locatorJson: '...',
        progression: ...,
        visualPageIndex: 9,
        visualTotalPages: 100,
      ),
```

（`locatorJson`/`progression` 實際值以檔案現況為準，不在此列出——只改頁碼欄位名稱與所屬欄位組。）

- [x] **Step 3：2 份整合測試檔案同步改名（審查報告 `review-plan-issue-10.md` Important #1：Task 1 移除舊欄位後，這兩份檔案原本會編譯失敗）**

1. `app/integration_test/foliate_single_column_test.dart:94`——該測試（`sample_long_chinese_vertical.epub`，流式格式，非 FXL）doc comment 明確說明驗證對象是 `SectionProgress` 位元組估計刻度的嚴格遞增行為，選用 `locationIndex`（與 `displayPageIndex` 挑值結果一致，但語意更精確對應測試意圖），原本：

```dart
            onLocatorChanged: (info) {
              final pageIndex = info.pageIndex;
              if (pageIndex != null) {
                pageIndexLog.add(pageIndex);
              }
            },
```

改為：

```dart
            onLocatorChanged: (info) {
              final pageIndex = info.locationIndex;
              if (pageIndex != null) {
                pageIndexLog.add(pageIndex);
              }
            },
```

2. `app/integration_test/foliate_toc_footer_test.dart:153/155/161/209`——該測試驗證的是頁尾實際消費的挑值結果（`_buildFoliateEpubFooter()` 邏輯），選用 `displayTotalPages`/`displayPageIndex`：

```dart
    expect(positionAfterOpen?.totalPages, isNotNull,
        reason: '開書後應已收到 totalPages，供頁尾顯示使用');
    expect(positionAfterOpen!.totalPages, greaterThan(0));

    FoliateReaderView.nextPage(key);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(errorMessage, isNull, reason: '換頁後不應觸發 onError');
    expect(lastPosition?.totalPages, positionAfterOpen.totalPages,
        reason: '同一本書換頁不應改變 totalPages');
```

改為：

```dart
    expect(positionAfterOpen?.displayTotalPages, isNotNull,
        reason: '開書後應已收到 displayTotalPages，供頁尾顯示使用');
    expect(positionAfterOpen!.displayTotalPages, greaterThan(0));

    FoliateReaderView.nextPage(key);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(errorMessage, isNull, reason: '換頁後不應觸發 onError');
    expect(lastPosition?.displayTotalPages, positionAfterOpen.displayTotalPages,
        reason: '同一本書換頁不應改變 displayTotalPages');
```

以及行 209：

```dart
    expect(firstPosition!.pageIndex, anyOf(isNull, equals(0)),
        reason: '優雅退回後應從書本開頭開始（pageIndex 0 或尚未回報）');
```

改為：

```dart
    expect(firstPosition!.displayPageIndex, anyOf(isNull, equals(0)),
        reason: '優雅退回後應從書本開頭開始（displayPageIndex 0 或尚未回報）');
```

同步將行 117 測試標題「頁尾頁碼正確反映 pageIndex/totalPages，且隨翻頁更新」改為「頁尾頁碼正確反映 displayPageIndex/displayTotalPages，且隨翻頁更新」。

- [x] **Step 4：執行 `reader_screen_test.dart` 確認全數通過（整合測試需真實裝置，留待 Task 5 `flutter analyze` 做編譯期驗證，見 Global Constraints 與兩層測試架構限制）**

執行：`cd app && flutter test test/screens/reader_screen_test.dart`
預期：`PASS`，全數既有案例零回歸（15 處欄位改名不影響任何斷言邏輯，數值與挑值後的 `displayPageIndex`/`displayTotalPages` 結果與修改前完全一致）。

- [x] **Step 5：Commit**

```bash
git add app/test/screens/reader_screen_test.dart app/integration_test/foliate_single_column_test.dart app/integration_test/foliate_toc_footer_test.dart
git commit -m "refactor(epic-26): Issue 10 Task 4——reader_screen_test.dart 15 處呼叫點與 2 份整合測試檔案改用 locationIndex/locationTotal、visualPageIndex/visualTotalPages 或 displayPageIndex/displayTotalPages"
```

---

### Task 5：全專案最終驗證

**Files:**
- 無新增/修改檔案，純驗證。

- [x] **Step 1：全域殘留掃描，確認 `pageIndex`／`totalPages` 舊欄位名已從 `EpubPositionInfo` 相關程式碼徹底移除**

執行：

```bash
cd app
grep -rn "\.pageIndex\b\|\.totalPages\b" lib/reader/epub_position_info.dart lib/reader/foliate_bridge_codec.dart lib/reader/foliate_reader_view.dart lib/screens/reader_screen.dart
grep -n "pageIndex:\|totalPages:" test/screens/reader_screen_test.dart
grep -rn "\.pageIndex\b\|\.totalPages\b" integration_test/
```

預期：第一條指令零輸出（`EpubPositionInfo` 相關檔案已無舊欄位讀取）；第二條指令零輸出（`EpubPositionInfo(...)` 建構呼叫已無舊欄位名——注意這條指令會連帶掃到 `PdfPageInfo`／`PdfTocItem` 等同名不相關型別的建構呼叫，若有殘留輸出需逐一核對是否為 PDF 端既有程式碼，非本 Issue 遺漏）；第三條指令零輸出（審查報告 Important #1／Minor #2：`integration_test/` 下 `EpubPositionInfo` 相關的舊欄位讀取已在 Task 4 Step 3 改名，此處連帶掃到的 PDF 端 `PdfPageInfo`／`PdfSelectionInfo` 等同名型別若有殘留輸出，同樣需逐一核對非本 Issue 遺漏）。

- [x] **Step 2：執行 `flutter analyze`**

執行：`cd app && flutter analyze`
預期：`No issues found!`

- [x] **Step 3：執行全專案測試**

執行：`cd app && flutter test`
預期：全數通過，零回歸（相較 Issue 9 合併後的基準數字 1629，本 Issue Task 1 新增 8 項 `parseLocatorChanged()`／`displayPageIndex`/`displayTotalPages` 單元測試，其餘為既有測試逐欄位改名，總數應為「1629 + 8」）。

- [x] **Step 4：逐項核對驗收標準**

- [x] `EpubPositionInfo` 不再有 `pageIndex`／`totalPages` 欄位，改為 `locationIndex`／`locationTotal`／`visualPageIndex`／`visualTotalPages` 四個欄位，同一本書恆有一組為 `null`。
- [x] `main.js` 的 `onLocatorChanged` payload 改為兩參數，`locatorJson` 內容不受影響。
- [x] 流式書籍的頁尾顯示行為零改變；FXL／CBZ 頁尾顯示改為真實視覺頁數（刻意保留的附帶修正，非零行為改變，見 Global Constraints 與 `issues.md` Issue 10「實作後追加澄清」）。
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。

- [x] **Step 5：Commit（若 Step 1-4 有任何微調）**

```bash
git add -A
git commit -m "refactor(epic-26): Issue 10 Task 5——最終驗證：殘留掃描、flutter analyze 乾淨、全數測試通過"
```

（若 Step 1-4 皆一次到位無需任何修改，本 Task 可以不產生新 commit，直接在審查報告中記錄驗證結果。）
