# Epic 43 — 閱讀器模組架構深化：工單清單 (Issues)

依 `/improve-codebase-architecture`（2026-09-16，範圍全專案異動熱點檔案，4 個候選深化機會）逐項用 `/grilling` 敲定實作細節後拆案。各 Issue 依賴見 `epic.md` 依賴圖。

---

## Issue 1：收斂 ReaderScreen 的劃線/備註 CRUD 成 AnnotationSession 模組

**Status:** completed（**2026-09-16 已完成並合併回 `main`（PR [#252](https://git.jigong.org/huthief/elinkBook/pulls/252)，分支 `feat/epic-43-issue-1`）**：`plans/plan-issue-1.md` 8 個 Task 全數完成——新增 `app/lib/reader/annotation_session.dart`（`AnnotationSnapshot`／`AnnotationLocator`／`AnnotationSession` 含 `reload`/`createHighlight`/`createOrUpdateNote`/`deleteExisting`），`ReaderScreen` EPUB／PDF 兩側劃線/備註 CRUD 改用 `_annotationSession`，對應方法維持各自獨立不合併，`_deleteAnnotationRecords` 已整個移除無殘留呼叫點。獨立程式審查（`reviews/review-issue-1.md`）：0 Critical／0 Important／2 Minor（Minor 1 純記錄性質、已於報告中確認不需修改；Minor 2 `annotation_session_test.dart` import 排序已於審查後追加 commit 修正），結論 Ready to merge: Yes。`flutter analyze`（No issues found）／`flutter test`（245+ 測試全過，含新增 15 個 `AnnotationSession` 單元測試）皆為綠燈，零回歸。）

**依賴：** 無

**來源：** `/improve-codebase-architecture` 候選 1（Strong）。`/grilling` 已敲定介面形狀（Q1-Q7，全數 (a) 定案）。

**背景／目標：** `reader_screen.dart` 的劃線/備註 CRUD，EPUB／PDF 兩條路徑各自把「查選取 → guard → 建物件 → CRUD → reload → 送原生端」完整重寫一遍，5 對方法、約 220 行近乎逐行同構：

- `_handleHighlightStyleSelected`(1973)/`_handlePdfHighlightStyleSelected`(2070)
- `_handleNotePressed`(1989)/`_handlePdfNotePressed`(2086)
- `_reloadAnnotationsAndRefreshDecorations`(2028)/`_reloadPdfAnnotationsAndSync`(2125)
- `_sendDecorationsToNative`(2046)/`_sendPdfAnnotationsToNative`(2139)
- `_handleDeleteExistingAnnotation`(1905)/`_handlePdfDeleteExistingAnnotation`(1911)，共用 `_deleteAnnotationRecords`(1898)

Deletion test：刪掉其中一份，複雜度不會消失——它會在另一份原封不動重新出現，因為它已經重新出現過一次。不牴觸 ADR 0022／0023（規定的是渲染路徑分離，不涉及資料層 CRUD 邏輯）。

`_toggleBookmark`/`_togglePdfBookmark`（1270/1297）雖然外觀也是同構配對，但兩者已共同委派既有深模組 `bookmark_toggle.toggleBookmark()`（Epic 26 Issue 1），剩餘重複量很小且書籤在網域上是「完全不同的物件類型」（見 `CONTEXT.md`「書籤」詞條）——`/grilling` Q4 已確認**不**併入本 Issue，`bookmark_toggle.dart` 維持不動。

**Solution（`/grilling` Q1-Q7 定案）：**

- 新增 `app/lib/reader/annotation_session.dart`：

  ```dart
  @immutable
  class AnnotationSnapshot {
    const AnnotationSnapshot({required this.highlights, required this.notes});
    final List<Highlight> highlights;
    final List<Note> notes;

    // M-1（審查修訂）：補上值相等性——單元測試斷言 reload()/CRUD 回傳值
    // 時慣用 `expect(result, const AnnotationSnapshot(...))`，未覆寫時會
    // 退化成記憶體參照比對而失敗。
    @override
    bool operator ==(Object other) =>
        other is AnnotationSnapshot &&
        listEquals(other.highlights, highlights) &&
        listEquals(other.notes, notes);

    @override
    int get hashCode => Object.hash(Object.hashAll(highlights), Object.hashAll(notes));
  }

  /// 統一 EPUB／PDF 定位方式的值物件——比照 [Highlight]/[Note] 建構子
  /// 本身既有的「一組欄位皆可空」寫法（Q1），不引入正式 adapter 介面。
  class AnnotationLocator {
    const AnnotationLocator.epub({required String locatorJson, this.progression})
        : epubLocatorJson = locatorJson,
          pdfPageIndex = null,
          pdfRect = null;
    const AnnotationLocator.pdf({required int pageIndex, required PercentRect rect})
        : pdfPageIndex = pageIndex,
          pdfRect = rect,
          epubLocatorJson = null,
          progression = null;

    final String? epubLocatorJson;
    final double? progression;
    final int? pdfPageIndex;
    final PercentRect? pdfRect;
  }

  /// 建構子注入依賴（Q7）；只做 repository CRUD＋查詢，不依賴
  /// BuildContext／GlobalKey（Q3、Q5 皆決定「送原生端」「跳窗拿文字」
  /// 留在 ReaderScreen 呼叫端），純資料物件，回傳快照而非產生副作用（Q2）。
  class AnnotationSession {
    AnnotationSession({
      required this.highlightsRepository,
      required this.notesRepository,
      required this.bookId,
    });

    final HighlightsRepository highlightsRepository;
    final NotesRepository notesRepository;
    final String bookId;

    Future<AnnotationSnapshot> reload();

    /// 回傳新建 highlight 的 id（供呼叫端設定
    /// `_pendingHighlightIdForSelection`/`_pendingPdfHighlightIdForSelection`），
    /// 取代原本用 side-effect 直接寫欄位的作法。
    Future<({AnnotationSnapshot snapshot, String highlightId})> createHighlight({
      required AnnotationLocator locator,
      required HighlightStyle style,
    });

    /// `existing != null` 時呼叫 `updateText`，否則 insert 新 Note。
    /// 跳窗拿 `text` 的步驟維持在 ReaderScreen（Q5），這裡只收「給定 text
    /// 之後」的 CRUD。
    Future<AnnotationSnapshot> createOrUpdateNote({
      required AnnotationLocator locator,
      required String text,
      Note? existing,
      String? pendingHighlightId,
    });

    /// 對應現有 `_deleteAnnotationRecords`，刪除後內部呼叫一次 `reload()`
    /// 回傳最新快照——呼叫端不需要再自己額外呼叫 reload。
    Future<AnnotationSnapshot> deleteExisting(AnnotationListItem item);
  }
  ```

  `highlightsRepository`/`notesRepository` 皆為**非空**型別（Q7 延伸決定，依 `reader_screen_test.dart` 現有 34 處建構點逐一核對，兩者在實務上永遠成對提供或成對省略，不存在「只給一個」的既有情境——見下方 Global Constraints）。

- `ReaderScreen` 修改：
  - 新增 `late final AnnotationSession? _annotationSession`：僅在 `widget.highlightsRepository != null && widget.notesRepository != null` 時建構，否則為 `null`。所有呼叫端統一 guard `if (_annotationSession == null) return;`，取代原本每個方法各自重複的 `repository == null` 檢查（含 `_handleHighlightStyleSelected` 原本只檢查 `highlightsRepository`、現在一併要求 `notesRepository` 非空的既有行為調整——實務上兩者永遠成對出現，此調整不改變任何既有測試/使用情境的實際結果）。
  - `_handleHighlightStyleSelected`/`_handlePdfHighlightStyleSelected`：**兩個方法本身不合併**（EPUB／PDF 建構 `AnnotationLocator` 的方式、送原生端的方式都不同，維持既有分派），各自改為建構對應格式的 `AnnotationLocator`，呼叫 `_annotationSession!.createHighlight(...)`，取得 `(snapshot, highlightId)` 後 `setState` 更新 `_highlights`/`_notes`/`_pendingHighlightIdForSelection`（或 PDF 版本），再呼叫既有 `_sendDecorationsToNative()`/`_sendPdfAnnotationsToNative()`。
  - `_handleNotePressed`/`_handlePdfNotePressed`：跳窗拿 `text` 的部分不變（`showNoteTextDialog`），之後改呼叫 `_annotationSession!.createOrUpdateNote(...)`。
  - `_handleDeleteExistingAnnotation`/`_handlePdfDeleteExistingAnnotation`：改呼叫 `_annotationSession!.deleteExisting(item)`，取得快照後 `setState`，再呼叫既有 `_sendDecorationsToNative()`/`_sendPdfAnnotationsToNative()` 與各自 UI 收尾（`_handleCloseAnnotationToolbar()`/`_handlePdfSelectionCanceled()`，維持不變，Q6 已確認不收進 session）。
  - `_reloadAnnotationsAndRefreshDecorations`/`_reloadPdfAnnotationsAndSync`：內部改呼叫 `_annotationSession!.reload()` 取代手動查詢兩個 repository，其餘（`setState`＋送原生端）不變——**這兩個方法本身也不合併**，理由同上。
  - `_sendDecorationsToNative`/`_sendPdfAnnotationsToNative` 完全不變（本來就不動，Q3 已確認留在呼叫端）。

**Global Constraints：**

- 實作前先跑 `grep -c "highlightsRepository:\|notesRepository:" app/test/screens/reader_screen_test.dart` 核對兩者出現次數是否仍相等（本次規劃當下皆為 34），確認「永遠成對」前提在實作當下仍然成立；若不成立需回頭重新評估 Q7 的非空型別決定，不可逕自忽略。
- `AnnotationLocator` 不需要 `operator ==`/`hashCode`（僅作為方法參數傳遞，不進清單比對）。`AnnotationSnapshot` 需要（見上方 M-1 審查修訂），`Highlight`/`Note` 本身已有既有 `operator ==`（`highlight.dart:57`／`note.dart:73`），`listEquals` 可正確逐筆比對。

**單元測試要求：**

- 新增 `test/reader/annotation_session_test.dart`：`AnnotationSession` 獨立單元測試（不依賴 `BuildContext`/`Widget`，比照 `bookmark_toggle` 既有測試慣例用 in-memory fake repository），涵蓋：
  - `createHighlight`：EPUB／PDF 各自正確寫入對應欄位（另一組維持 `null`）、回傳的 `highlightId` 與實際 insert 的 id 一致。
  - `createOrUpdateNote`：新增（`existing == null`）／編輯（`existing != null`，呼叫 `updateText` 而非 insert）兩種路徑。
  - `deleteExisting`：僅 highlight／僅 note／兩者皆有（同一選取範圍同時有畫線與備註）三種組合，皆正確刪除對應記錄。
  - `reload()`：正確回傳兩個 repository 目前的完整清單。
- 既有 `reader_screen_test.dart` 劃線/備註相關測試（EPUB／PDF 建立/編輯/刪除、送原生端 decoration/annotation 內容、`_pendingHighlightIdForSelection` 相關的「畫線後緊接著加備註會依附同一筆畫線」既有行為）必須零回歸。

**驗收標準：** `reader_screen.dart` 內劃線/備註 CRUD 不再各自手寫 repository 存取；`flutter analyze` 乾淨；`flutter test test/reader/annotation_session_test.dart test/screens/reader_screen_test.dart` 全數通過，零回歸。

---

## Issue 2：抽出 LayoutPreset 共用操作函式，合併 applyPreset/applyFromBook 重複邏輯

**Status:** completed（**2026-09-16 已完成並合併回 `main`（PR [#253](https://git.jigong.org/huthief/elinkBook/pulls/253)，分支 `feat/epic-43-issue-2`）**：`plans/plan-issue-2.md`（經 `reviews/review-plan-issue-2.md` 審查修訂 2 項 Important——I-1 `applyLayoutPresetPrefs()` 空清單提早返回、I-2 `_handleSaveAsPreset`/`_handleDeletePreset` 補齊 `!confirmed || !mounted` 生命週期防禦——與 2 項 Minor 後定案）8 個 Task 全數完成：新增 `app/lib/reader/layout_preset_actions.dart`（`layoutPresetTargetsCurrentBookOnly`/`insertNewLayoutPreset`/`overwriteLayoutPreset`/`deleteLayoutPreset`/`applyLayoutPresetPrefs`，頂層函式、無 `BuildContext` 依賴），`ReaderScreen` 新增 `_applyPrefsToTargets` 收斂 `_handleApplyPreset`/`_handleApplyFromBook` 重複中段邏輯，`_handleSaveAsPreset`/`_handleDeletePreset` 改呼叫對應函式後直接 `setState`；對外方法簽章（含 `ReaderSettingsSheet` 6 個 callback 參數）維持不變。獨立程式審查（`reviews/review-issue-2.md`）：0 Critical／0 Important／2 Minor（皆觀察性記錄，非需修正項目），並逐項核對 I-1/I-2/M-1/M-2 四項審查修訂皆已落地，結論 Ready to merge: Yes。`flutter test test/reader/layout_preset_actions_test.dart test/screens/reader_screen_test.dart`（12+242 個測試全過，零回歸）／`flutter analyze`（No issues found）皆為綠燈。）

**依賴：** 建議候選 1（Issue 1）完成後再進行，降低同時改 `reader_screen.dart` 的 merge 衝突風險。

**來源：** `/improve-codebase-architecture` 候選 2（Worth exploring）。`/grilling` 已敲定介面形狀（Q1-Q4，全數採建議答案定案；Q5 使用者確認不夾帶，另立 Issue 5）。

**背景／目標：** `reader_screen.dart:960-1201`，8 個私有方法、約 240 行，業務規則與 `showDialog`/`SnackBar` 糾纏。證據最硬的重複是 `_handleApplyPreset`(1090)/`_handleApplyFromBook`(1117) 這一對——兩者除了 `prefs` 來源不同（`preset.prefs` vs 讀來源書籍當下設定），其餘「判斷是否僅套用到目前書籍 → 視情況跳確認 → 單筆/批次寫入 → 套用到目前書籍時呼叫 `_handlePrefsChanged`」逐行相同，且共用同一個 `_confirmApplyToOtherBooks`(1057) 對話框。`_handleSaveAsPreset`(960)/`_handleDeletePreset`(1142) 兩個各自獨立，重複證據較弱，但一併收斂「操作本體＋重新查詢清單」的形狀，讓四個方法維持一致寫法。

**Solution（`/grilling` Q1-Q4 定案）：**

- 新增 `app/lib/reader/layout_preset_actions.dart`（**頂層函式，不做成類別**——Q3 已確認：`LayoutPresetRepository`／`BookReaderPrefsRepository` 分屬不同操作子集、已證實不永遠成對提供，比照 `bookmark_toggle.dart` 風格，各函式各自宣告自己實際需要的 repository 為必要參數）：

  ```dart
  /// Q4：`_handleApplyPreset`/`_handleApplyFromBook` 原本各自重複的
  /// inline 判斷抽成純函式。
  bool layoutPresetTargetsCurrentBookOnly(
    List<String> targetBookIds,
    String currentBookId,
  ) =>
      targetBookIds.length == 1 && targetBookIds.single == currentBookId;

  /// Q2：完成後回傳 `repository.listAll()` 最新結果，取代呼叫端另外
  /// 呼叫 `_loadLayoutPresets()`。
  Future<List<LayoutPreset>> insertNewLayoutPreset(
    LayoutPresetRepository repository, {
    required String name,
    required BookReaderPrefs prefs,
  });

  // M-2（審查修訂）：target.id 為 int?（未存檔的暫存物件可為 null），
  // 入口加 assert 讓呼叫端誤傳未持久化 preset 時有明確的除錯訊息，
  // 而非隱蔽的 `target.id!` 執行期 null check 崩潰。
  Future<List<LayoutPreset>> overwriteLayoutPreset(
    LayoutPresetRepository repository, {
    required LayoutPreset target,
    required String name,
    required BookReaderPrefs prefs,
  }) {
    assert(target.id != null, 'Target layout preset must have a valid id for overwrite');
    // ...
  }

  Future<List<LayoutPreset>> deleteLayoutPreset(
    LayoutPresetRepository repository,
    int id,
  );

  /// Q1：`_handleApplyPreset`/`_handleApplyFromBook` 共用的核心。只做
  /// 寫入（單筆 `save`／批次 `saveMultiple`），不含確認對話框、不含
  /// `_handlePrefsChanged` 呼叫（皆需要 BuildContext／ReaderScreen 自身
  /// 狀態，留在呼叫端，比照候選 1 Q3/Q5/Q6 一貫的邊界原則）。
  Future<void> applyLayoutPresetPrefs(
    BookReaderPrefsRepository repository, {
    required BookReaderPrefs prefs,
    required List<String> targetBookIds,
  });
  ```

- `ReaderScreen` 修改：
  - `_handleSaveAsPreset`：`repository == null` 時顯示 SnackBar 的既有邏輯不變；`try` 區塊內改呼叫 `insertNewLayoutPreset`/`overwriteLayoutPreset`，取得回傳的最新清單後 `setState(() => _layoutPresets = updated)`，取代原本另外呼叫 `_loadLayoutPresets()`。`catch` 區塊錯誤處理完全不變。
  - `_handleDeletePreset`：呼叫 `deleteLayoutPreset`，取得回傳清單後 `setState`，取代 `_loadLayoutPresets()`。
  - 新增 `_applyPrefsToTargets(BookReaderPrefs prefs, List<String> targetBookIds)` 私有方法，取代 `_handleApplyPreset`/`_handleApplyFromBook` 原本重複的中段邏輯：
    ```dart
    Future<void> _applyPrefsToTargets(
      BookReaderPrefs prefs,
      List<String> targetBookIds,
    ) async {
      final repository = widget.bookReaderPrefsRepository;
      if (repository == null || targetBookIds.isEmpty) return;
      if (!layoutPresetTargetsCurrentBookOnly(targetBookIds, widget.bookId)) {
        final confirmed = await _confirmApplyToOtherBooks(targetBookIds.length);
        // I-3（審查修訂）：對話框彈出期間使用者可能退出閱讀器，pop 後
        // State 可能已 unmounted，`!confirmed` 與 `!mounted` 合併檢查。
        if (!confirmed || !mounted) return;
      }
      await applyLayoutPresetPrefs(repository, prefs: prefs, targetBookIds: targetBookIds);
      // I-3（審查修訂）：非同步 SQLite 批次寫入完成後才呼叫
      // _handlePrefsChanged()（會觸發 setState），須先確認未 unmounted，
      // 否則引發 `setState() called after dispose()`。
      if (!mounted) return;
      if (targetBookIds.contains(widget.bookId)) {
        _handlePrefsChanged(prefs);
      }
    }
    ```
    `_handleApplyPreset(preset, {targetBookIds})` 改為直接 `await _applyPrefsToTargets(preset.prefs, targetBookIds)`。`_handleApplyFromBook(sourceBookId, {targetBookIds})` 保留原本讀取來源書籍 `sourcePrefs` 的既有前段（含其自己的 `repository == null` 早期 return——與 `_applyPrefsToTargets` 內部的檢查重複但無害，維持既有「呼叫前先檢查」寫法一致性），之後改呼叫 `await _applyPrefsToTargets(sourcePrefs, targetBookIds)`。
  - `_confirmApplyToOtherBooks`/`_selectPresetToOverwrite`/`_confirmOverwrite`/`_confirmDeletePreset`/`_handleRequestBookPicker` 完全不動（皆為 `BuildContext`/`Navigator` 依賴的 UI 邏輯，維持留在呼叫端）。

**單元測試要求：**

- 新增 `test/reader/layout_preset_actions_test.dart`：`layoutPresetTargetsCurrentBookOnly`／`insertNewLayoutPreset`／`overwriteLayoutPreset`／`deleteLayoutPreset`／`applyLayoutPresetPrefs` 各自獨立單元測試（不依賴 `BuildContext`），含 `applyLayoutPresetPrefs` 單筆／批次寫入兩種路徑。
- 既有 `reader_screen_test.dart` 版面設定預設集相關測試（另存/套用/套用來源書籍/刪除、3 組上限觸發覆蓋流程、套用到目前書籍時畫面即時刷新）必須零回歸。

**驗收標準：** `_handleApplyPreset`/`_handleApplyFromBook` 不再各自重複「判斷/確認/寫入/刷新」邏輯；`flutter analyze` 乾淨；`flutter test test/reader/layout_preset_actions_test.dart test/screens/reader_screen_test.dart` 全數通過，零回歸。

---

## Issue 3：（記錄用，暫不動手）library_screen 過濾邏輯抽取，範圍比報告原估小很多

**Status:** needs-info

**依賴：** 無

**來源：** `/improve-codebase-architecture` 候選 3（Speculative）。`/grilling` Q1 已確認：範圍不足以立即拆 Issue，先只記錄。

**背景：** 報告原估 `library_screen.dart:1100-1410`（`_buildBookList`，約 310 行）「過濾/分組計算與 widget 建構混在同一方法」。實際讀碼（2026-09-16）發現落差：

- `_buildGroupTiles()`（1081-1095）其實**已經是獨立方法**，不是問題的一部分。
- `_buildBookList()` 本身只有 194 行（1100-1293），不是 310 行。
- 其中真正屬於「過濾/分組計算」的只有 `visibleBooks` 這段（1106-1112，約 7 行）。
- 佔篇幅最大的是 `LayoutBuilder` 內的分頁/格線幾何計算（動態算每頁列數/欄數），這塊複雜度已有清楚理由支撐（`epic-36-adaptive-shelf-navigation` Issue 7 大量註解記錄過往真機 bug），跟候選 3 原本「過濾邏輯與 widget 建構混雜」的框架不是同一種摩擦，不該被一起算進同一個候選。

**為什麼現在不動手（`/grilling` Q1）：** 唯一站得住腳的抽取（7 行 `visibleBooks` 純函式化）帶來的可測試性提升有限，撐不起一個完整 Issue 生命週期（計畫→審查→TDD→審查→合併）的成本，deletion test 證據本來就弱（抽出後 widget 建構部分不會變簡單）。

**觸發重新評估的條件：** `visibleBooks` 的過濾規則變複雜（例如新增多條件交集、排序邏輯併入同一段）、或者 `LayoutBuilder` 內的分頁幾何計算本身開始出現重複的證據（例如另一個畫面需要同一套分頁列數計算邏輯）時，回頭重新評估是否值得拆 Issue。

**驗收標準：** 無（本 Issue 純記錄，不產生程式碼異動）。

---

## Issue 4：抽出 FoliateBridgeHandlers，收斂 JS→Dart handler name 字串常值重複

**Status:** completed（**2026-09-17 已完成並合併回 `main`（PR [#254](https://git.jigong.org/huthief/elinkBook/pulls/254)，分支 `feat/epic-43-issue-4`）**：`plans/plan-issue-4.md`（經 `reviews/review-plan-issue-4.md` 審查修訂 1 項 Important（I-1 `git add` 路徑）與 2 項 Minor（M-1 `const` 宣告、M-2 驗證指令涵蓋範圍）採納，1 項 Minor（M-3 新增 `all`/`values` 聚合集合）評估為 YAGNI 明確不採納）4 個 Task 全數完成：新增 `app/lib/reader/foliate_bridge_handlers.dart`（`abstract final class FoliateBridgeHandlers`，11 個 `static const String`），`foliate_reader_view.dart`（12 處）／`search/foliate_content_indexer.dart`（5 處）全部 `handlerName: '...'` 字面值改為常數引用，`JsBridgeGateway` 兩處轉呼叫參數變數維持不動，`main.js` 未觸碰。獨立程式審查（`reviews/review-issue-4.md`）：0 Critical／0 Important／2 Minor（皆記錄性質，非需修正項目），並逐項核對 I-1/M-1/M-2/M-3 四項審查修訂皆正確落地（特別確認 M-3 未被偷加），結論 Ready to merge: Yes。異動觸及測試檔（`foliate_bridge_handlers_test.dart`／`foliate_reader_view_test.dart`）全過／`flutter analyze`（No issues found）皆為綠燈。）

**依賴：** 無，與其餘 Issue 皆獨立，可隨時進行。

**來源：** `/improve-codebase-architecture` 候選 4（Speculative）。`/grilling` Q1 已縮小範圍定案（採建議答案 (a)）。

**背景／目標：** 報告原框架是「`main.js`↔Dart 缺一份單一契約清單」，實際查證（2026-09-16）後範圍已縮小：

- Dart→JS（`main.js` 的 17 個 `window.*` 函式）：每個都只在 `foliate_reader_view.dart` 有單一呼叫點（`state._evaluate('window.xxx(...)')`），deletion test 站不住腳，**不在本 Issue 範圍**。
- JS→Dart（`main.js` 呼叫 `window.flutter_inappwebview.callHandler('...')` 通知 Dart，**11 個**相異 handler name——**I-1 審查修訂**：原稿誤算為 8 個，漏算 3 個因多行呼叫格式〔`callHandler(\n  'name', ...)`，字串不在 `callHandler(` 同一行〕被初次盤點遺漏的 handler）：這邊有真實重複——`JsBridgeGateway.register(handlerName: ...)`／`.request(handlerName: ...)` 這對呼叫，同一個 handler name 字串常值在 Dart 端手打兩次以上：
  - `foliate_reader_view.dart`：`'onTableOfContentsReady'`(578/614)、`'onTtsSegmentsReady'`(586/620)、`'onTtsSegmentIndexReady'`(599/626)、`'onPageRendered'`(631)、`'onError'`(645)、`'onLocatorChanged'`(651，main.js:1050 發送，全書翻頁/章節切換/進度計算/書籤狀態核心事件)、`'onTtsHighlightOutOfSafeWindow'`(660)、`'onSelectionChanged'`(674，main.js:1185 發送，選取文字/喚起標記工具列核心事件)、`'onSelectionCleared'`(697)。
  - `search/foliate_content_indexer.dart`：`'onSectionCountReady'`(105/164)、`'onSegmentsForSectionReady'`(114，main.js:877 發送，全文檢索建立索引章節段落的核心回呼)、`'onPageRendered'`(132)、`'onError'`(139)——與 `foliate_reader_view.dart` 的 `'onPageRendered'`/`'onError'` 是跨檔案重複。

  任一處打錯字（例如 `'onPageRenderd'`）不會被型別系統攔到，只會在執行期靜默逾時（`JsBridgeGateway.request()` 逾時退回 fallback 值，見 `js_bridge_gateway.dart` 既有註解）。`main.js` 自己內部呼叫 `callHandler('...')` 的字串（vendor 檔案原始碼字面值）不在範圍內——不改動釘定的 vendor 檔案本身。

**Solution：**

- 新增 `app/lib/reader/foliate_bridge_handlers.dart`：
  ```dart
  /// JS→Dart `callHandler()` 的 handler name 常數（Epic 43 Issue 4）。
  /// main.js 端呼叫 callHandler() 時的字串字面值本身不受此常數約束
  /// （vendor 檔案，不改動），僅收斂 Dart 端 register()/request() 的
  /// 重複字串常值。
  abstract final class FoliateBridgeHandlers {
    static const onTableOfContentsReady = 'onTableOfContentsReady';
    static const onTtsSegmentsReady = 'onTtsSegmentsReady';
    static const onTtsSegmentIndexReady = 'onTtsSegmentIndexReady';
    static const onPageRendered = 'onPageRendered';
    static const onError = 'onError';
    static const onTtsHighlightOutOfSafeWindow = 'onTtsHighlightOutOfSafeWindow';
    static const onSelectionCleared = 'onSelectionCleared';
    static const onSectionCountReady = 'onSectionCountReady';
    // I-1（審查修訂）：原稿遺漏的 3 個 handler。
    static const onSegmentsForSectionReady = 'onSegmentsForSectionReady';
    static const onLocatorChanged = 'onLocatorChanged';
    static const onSelectionChanged = 'onSelectionChanged';
  }
  ```
- `foliate_reader_view.dart`（含 I-1 補上的 `onLocatorChanged`(651)／`onSelectionChanged`(674)）／`search/foliate_content_indexer.dart`（含 I-1 補上的 `onSegmentsForSectionReady`(114)）內全部 `handlerName: '...'` 字面值改為 `handlerName: FoliateBridgeHandlers.xxx`。純替換，不改變任何呼叫邏輯、時序、fallback 值。

**單元測試要求：**

- 新增 `test/reader/foliate_bridge_handlers_test.dart`（M-4 審查修訂）：以 Map/Set 比對斷言 `FoliateBridgeHandlers` 每個常數值與預期字串完全相符，防止常數本身筆誤（純靜態分析無法檢驗字串值拼寫）。
- 其餘不需新增測試——本 Issue 純粹是把字串常值換成常數引用，不改變任何執行期行為，既有 `foliate_reader_view_test.dart`／`foliate_content_indexer_test.dart`／`reader_screen_test.dart` 等既有測試必須零回歸即為驗證。

**驗收標準：** `foliate_reader_view.dart`／`search/foliate_content_indexer.dart` 內不再出現重複手打的 handler name 字串常值（含 I-1 補上的 3 個）；`flutter analyze` 乾淨；`flutter test test/reader/foliate_bridge_handlers_test.dart` 及全套 `flutter test` 全數通過，零回歸。

---

## Issue 5：補齊版面設定預設集「套用／刪除」的錯誤處理一致性

**Status:** completed（**2026-09-17 已完成並合併回 `main`（PR [#255](https://git.jigong.org/huthief/elinkBook/pulls/255)，分支 `feat/epic-43-issue-5`）**：`plans/plan-issue-5.md`（經 `reviews/review-plan-issue-5.md` 審查修訂 4 項 Minor——M-1 措辭統一、M-2 saveMultiple 覆蓋範圍加註解不重複測試、M-3 刪除失敗測試補資料完整性斷言、M-4 紅燈步驟改用 `--plain-name` 加速——後定案）4 個 Task 全數完成：`_applyPrefsToTargets`／`_handleApplyFromBook`（自己獨立一層 try/catch，涵蓋 `repository.load()`）／`_handleDeletePreset` 皆補上 try/catch + SnackBar（`reader_apply_preset_error_snackbar`／`reader_delete_preset_error_snackbar`），比照既有 `_handleSaveAsPreset` 模式；新增測試替身 `_ThrowingBookReaderPrefsRepository` 與 `_ThrowingLayoutPresetRepository.delete()` 覆寫。獨立程式審查（`reviews/review-issue-5.md`）：0 Critical／0 Important／0 Minor，實測確認 `_handleApplyFromBook` 兩層獨立 try/catch 不會重複顯示 SnackBar，M-1～M-4 四項修訂皆確實落地，結論 Ready to merge: Yes。`flutter test`（預設集群組 14 案例＋整檔 233 案例全過，零回歸）／`flutter analyze`（No issues found）皆為綠燈。）

**依賴：** Issue 2（直接修改 Issue 2 收斂後的 `_handleApplyPreset`/`_handleApplyFromBook`/`_handleDeletePreset`/`_applyPrefsToTargets`，需等 Issue 2 合併後才有意義的 diff 基礎）

**來源：** `/grilling` 候選 2 Q5——使用者確認需要補齊此既有落差，但不與候選 2 主重構夾帶，另立本 Issue（2026-09-16 使用者明確指示）。

**背景／目標：** `_handleSaveAsPreset` 有 `try/catch` + SnackBar 錯誤提示（`epic-27-reader-device-compat` Issue 4 既有修復，見 `reader_save_as_preset_error_snackbar`/`reader_save_as_preset_repository_unavailable_snackbar` 兩個既有 Key）。但 `_handleApplyPreset`/`_handleApplyFromBook`（Issue 2 後皆委派 `_applyPrefsToTargets`）／`_handleDeletePreset` 失敗時仍是靜默無提示——`repository.save`/`saveMultiple`/`delete` 拋出例外會被吞掉（無 try/catch 包覆），使用者不會知道套用/刪除失敗，畫面停留原狀但無任何回饋。

**I-2（審查修訂，重要）：** `_handleApplyFromBook` 在呼叫 `_applyPrefsToTargets` **之前**先執行 `await repository.load(sourceBookId)`（讀取來源書籍目前的版面設定）——這段不在 `_applyPrefsToTargets` 的 try/catch 保護範圍內。若只替 `_applyPrefsToTargets` 加 try/catch，`repository.load()` 本身拋出例外（例如 SQLite 讀取錯誤、JSON 解析失敗）時仍會完全不提示、直接向上拋出未捕捉例外，無法達成本 Issue「套用來源書籍失敗時皆有提示」的驗收標準。故 `_handleApplyFromBook` 需要**自己獨立的一層 try/catch**，把 `repository.load()` 與後續呼叫 `_applyPrefsToTargets` 一併包住——不能只在 `_applyPrefsToTargets` 內部處理。

**Solution：** 比照 `_handleSaveAsPreset` 既有的 try/catch + SnackBar 模式，補上等價錯誤處理：

- `_applyPrefsToTargets`：包一層 try/catch，`catch` 顯示 SnackBar 前先 `if (!mounted) return;`（M-3 審查修訂，避免 `use_build_context_synchronously` analyzer 警告），才呼叫 `ScaffoldMessenger.of(context).showSnackBar(SnackBar(key: Key('reader_apply_preset_error_snackbar'), content: Text('套用版面設定失敗：$e')))`，比照既有 `debugPrint` 保留診斷輸出的既有慣例。`_handleApplyPreset` 透過這層 try/catch 即已涵蓋。
- `_handleApplyFromBook`：**新增自己獨立的 try/catch**，包住 `await repository.load(sourceBookId)` 與後續 `await _applyPrefsToTargets(sourcePrefs, targetBookIds)` 兩步；`catch` 同樣先 `if (!mounted) return;` 才顯示同一個 `reader_apply_preset_error_snackbar`（與 `_applyPrefsToTargets` 內部的 try/catch 是兩層獨立保護，`_applyPrefsToTargets` 內部再拋出的例外會被這一層外層 catch 一併接住，不會重複跳兩次 SnackBar——`_applyPrefsToTargets` 只在自己單獨被 `_handleApplyPreset` 呼叫的路徑上才會走到自己的 catch）。
- `_handleDeletePreset`：包一層 try/catch，`catch` 同樣先 `if (!mounted) return;`，才顯示 `SnackBar(key: Key('reader_delete_preset_error_snackbar'), content: Text('刪除預設集失敗：$e'))`。
- 訊息格式與既有 `另存為新預設集失敗：$e` 風格一致；不新增 `repository == null` 的提示（維持現狀不變——本 Issue 只補「repository 存在但操作拋例外」這條路徑的提示，`repository == null` 屬於另一個既有落差，不在本 Issue 範圍內，若需要另評估）。

**單元測試要求：**

- 比照既有 `_handleSaveAsPreset` 失敗路徑的既有測試手法（`reader_screen_test.dart` 對應測試，用會拋例外的假 repository），新增：
  - `_applyPrefsToTargets`（經 `_handleApplyPreset` 觸發）：`repository.save`/`saveMultiple` 拋例外時顯示 `reader_apply_preset_error_snackbar`。
  - `_handleApplyFromBook`：`repository.load(sourceBookId)` 拋例外時顯示 `reader_apply_preset_error_snackbar`（I-2 審查修訂新增，驗證外層 try/catch 有效包住讀取階段）。
  - `_handleDeletePreset`：`repository.delete` 拋例外時顯示 `reader_delete_preset_error_snackbar`。

**驗收標準：** 三個操作（套用／套用來源書籍，含其讀取來源書籍設定階段／刪除）失敗時皆有使用者可見錯誤提示；`flutter analyze` 乾淨；`flutter test` 全數通過，零回歸。
