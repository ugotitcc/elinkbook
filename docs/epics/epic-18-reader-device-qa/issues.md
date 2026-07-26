# Epic 18 — 真機 UI 精修：工單清單 (Issues)

依 `design.md`（使用者真機 QA 回報 8 項，其中項目 4 拆出不在本 Epic 範圍）與 `spec.md`（Issue 4／5 新介面定義）拆解出的 5 個工單（Issue 1-6，其中 Issue 6 取代 Issue 5）。Issue 6 完成合併後，使用者持續真機使用中再回報 5 項（見 `design.md`「第二輪真機使用回報」），拆解為 Issue 7-9。全部 8 個現行工單（Issue 1-4、6-9）彼此獨立、無依賴關係，可任意順序或平行開始。

---

## Issue 1：版面設定 Bottom Sheet 加入明確關閉按鈕

**Status:** ✅ 已完成並合併回 `main`（PR #73，merge commit `ee19b35`）。3 個設定選單（EPUB `ReaderSettingsSheet`、`PdfSettingsSheet` 與 `FxlSettingsSheet`）皆已成功加入固定式的關閉按鈕，並全面採用 `Column(mainAxisSize: MainAxisSize.min)` 搭配 `Flexible` 與 `shrinkWrap: true` 的防禦性佈局設計，解決了小螢幕 E-Ink 閱讀器無法關閉選單的缺陷。相關 Widget 測試與尺寸驗收皆已全數通過。

**依賴：** 無

**描述：**

`ReaderSettingsSheet`（`app/lib/screens/reader_screen.dart:516-529` 的 `_openLayoutSettings()` 以 `showModalBottomSheet(isScrollControlled: true, enableDrag: false, ...)` 開啟）目前完全沒有關閉按鈕，唯一的關閉方式是點擊背景遮罩（barrier）。在 824×1648／150 PPI 等小螢幕裝置上，`ReaderSettingsSheet`（`app/lib/screens/reader_settings_sheet.dart`，5 個滑桿 + 多組 icon 切換列）內容高度可能撐滿整個視窗高度，導致背景遮罩完全不可見、使用者無法關閉此畫面。

- **`ReaderSettingsSheet`**：`build()`（`reader_settings_sheet.dart:134-248`）目前開頭是 `Text('⚙️ 版面設定', ...)`，改為一個固定式關閉列（標題 `Expanded(child: Text(...))` + `IconButton(key: Key('reader_settings_close_button'), icon: Icon(Icons.close), onPressed: () => Navigator.of(context).pop())`）放在 `ListView` **之外**，確保無論內容多長都不會被捲動出畫面。**審查修正**：外層必須是 `Column(mainAxisSize: MainAxisSize.min, children: [關閉列, Flexible(child: ListView(shrinkWrap: true, ...))])`——**不可**只用 `Expanded` 而漏掉 `mainAxisSize: MainAxisSize.min`：`showModalBottomSheet(isScrollControlled: true)` 給子項的是 loose constraints（`minHeight: 0`），`Column` 預設 `mainAxisSize: MainAxisSize.max` 本身就會撐滿到可用高度上限，與是否使用 `Expanded` 無關；即使內容很短（例如只有雙頁模式切換的 `FxlSettingsSheet`）也會被撐成滿版留下大片空白。加上 `mainAxisSize: MainAxisSize.min` 後，`Flexible`（非 `Expanded`，`FlexFit.loose`）搭配 `shrinkWrap: true` 才能讓 `Column` 在內容小於螢幕高度時保持緊湊包裹，內容大於螢幕高度時才被限制最大高度並允許內部捲動，兩種情境皆正確。
- **檢查 `pdf_settings_sheet.dart`／`fxl_settings_sheet.dart` 是否有相同缺口**：兩者若同樣是 `showModalBottomSheet(isScrollControlled: true, enableDrag: false)` 且內部無關閉按鈕，需要一併補上相同的固定式關閉列（三者比照相同的 UI 模式，避免只修好 EPUB 流式路徑、PDF/FXL 路徑仍有相同缺陷）。

**實作備註（已於 `plans/plan-issue-1.md` Task 1 調查、經人類於程式碼審查後確認接受，見 `tmp/epic-18/reviews/review-issue-1.md` Important #1）**：實測 `FxlSettingsSheet` 並不具備本 Issue 描述的「背景遮罩完全不可見、無法關閉」缺陷（`enableDrag` 預設 `true` 仍可下滑關閉，內容本身已用 `mainAxisSize.min` 緊湊包裹）。實作階段仍額外為其加上同款關閉按鈕（`Key('fxl_settings_close_button')`），理由是三個版面設定 Sheet 的 UI 樣式統一，而非修補實際缺陷——此屬計畫範圍外的追加，已經人類確認接受，不需回退。

**單元測試要求：**
- `reader_settings_sheet_test.dart`（若不存在則新增）：`Key('reader_settings_close_button')` 存在且可點擊；點擊後 `Navigator.pop()` 被呼叫（`showModalBottomSheet` 的 `Future` resolve，或以 `find.byType(ReaderSettingsSheet)` 在點擊後 `findsNothing` 驗證）。
- 內容刻意撐到超過典型小螢幕高度（例如在測試中設定極小的 `MediaQuery` viewport）時，關閉按鈕仍在 `find.byKey` 找得到且未被捲動出視窗外（可用 `tester.getTopLeft()` 確認位置固定）。
- 同樣的測試模式套用到 `pdf_settings_sheet.dart`／`fxl_settings_sheet.dart`（若這兩者確實有相同缺口）。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- 真機（`3CEF42ECD491687`）以及等效於 824×1648／150 PPI、1404×1872／300 PPI（黑白）、702×936／150 PPI（彩色）三種螢幕尺寸/密度（透過 `flutter run` 搭配 `--dart-define` 或裝置設定模擬視窗尺寸，或實機測試）確認：版面設定畫面在三種尺寸下皆能正確顯示且關閉按鈕可點擊退出。

---

## Issue 2：閱讀畫面上下工具列瘦身（AppBar 高度 + 頁尾合併單行）

**Status:** ✅ 已完成並合併回 `main`（PR #74，merge commit `3113135`）。AppBar 高度順利瘦身至 20dp，並同步透過 `IconButton.styleFrom` 與 `shrinkWrap` 收斂動作按鈕、圖示與字型，成功解決溢出與誤觸問題；頁尾 `ReaderFooter` 合併為單行 Row 並簡化進度文字為 `XXX/OOO`，保留 `Column(mainAxisSize: MainAxisSize.min)` 避開 Slider 佈局拉伸地雷。全專案 595 個測試與靜態分析全數通過。

**依賴：** 無

**描述：**

對應使用者回報項目 2（工具列過高）與項目 5（頁尾進度文字/捲軸分兩列）——兩者皆是「閱讀畫面上下工具列佔用過多垂直空間」的具體症狀，合併處理。

- **AppBar 高度**（`reader_screen.dart:1207-1210`）：目前 `AppBar(title: ..., actions: ...)` 未設定 `toolbarHeight`，使用 Flutter 預設 `kToolbarHeight`（56dp）。改為明確設定 `toolbarHeight: 20`（現有高度的約 1/3，`design.md` 決策 #2）。**審查修正**：**不可只設定 `toolbarHeight` 就結束**——`IconButton` 預設觸控區域是 48×48dp、預設圖示 24dp，`title` 文字也有預設字級與內邊距，在 20dp 高的 AppBar 內若不動這些子項會直接溢出（overflow）且與下方 WebView 內容區重疊，在 E-Ink 裝置上尤其容易誤觸換頁/畫線。必須同步明確收斂：`actions` 內的 `IconButton` 加上 `padding: EdgeInsets.zero`、`constraints: BoxConstraints(minWidth: ?, minHeight: ?)`（起始建議值 32×32，實際數字依真機點擊手感調整）、圖示 `size` 縮小（起始建議 18-20）；`title` 文字 `fontSize` 同步縮小（起始建議 12-14）。並評估是否需要 `SafeArea`／額外處理避開系統狀態列。以上具體數字皆為起始建議值，非最終規格，最終數值需真機調校後定案。
- **頁尾合併單行**（`app/lib/screens/reader_footer.dart:88-138`）：目前 `Column` 內是「進度文字」`Text` 一列 + 「輸入框+捲軸」`Row` 一列。改為單一 `Row`：進度文字改為較窄的固定寬度 `Text`（或縮短為僅顯示頁碼「XXX/OOO」，完整的「進度 YY%」可考慮移至 `Slider` 的 `label`/`overlay`，具體取捨留待實作階段依真機視覺效果決定，但整體高度需明顯低於目前的「文字列+互動列」兩列高度）；`reader_footer_progress_text`／`reader_footer_jump_input`／`reader_footer_jump_slider` 三個既有 `Key` 需全數保留（既有測試依賴這些 Key，見下方單元測試要求）。

**單元測試要求：**
- `reader_footer_test.dart`（若不存在則新增/擴充既有測試）：合併後 `Key('reader_footer_progress_text')`／`Key('reader_footer_jump_input')`／`Key('reader_footer_jump_slider')` 三者仍存在且行為不變（輸入框輸入頁碼觸發 `onPageChanged`、拖曳捲軸觸發 `onPageChanged`、`totalPages <= 1` 時捲軸停用等既有測試案例需全數保持通過）。
- `reader_footer_test.dart` 新增高度斷言（例如 `tester.getSize(find.byKey(Key('reader_footer'))).height` 與合併前的既有高度快照比較，確認明顯縮短）。
- `reader_screen_test.dart`：AppBar 存在時 `find.byType(AppBar)` 的 `preferredSize.height` 等於新設定的 `toolbarHeight`。
- **審查修正——既有字串斷言會壞掉，需同步更新**：若頁尾文字格式從完整的「進度 YY% ｜ 第 XXX/OOO 頁」縮短（例如只顯示「XXX/OOO」），下列既有測試中對完整字串的精確比對會直接失敗，需同步修改斷言內容為新格式：`app/test/screens/reader_footer_test.dart:17,138`；`app/test/screens/reader_screen_test.dart:963,1068,1098,1151,1179,1201,2764`（共 2＋7 處，非僅 `reader_footer_test.dart`）。實作前先 `grep -rn "進度.*第.*頁" app/test/` 重新確認實際命中處，避免遺漏。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- 真機確認 AppBar／頁尾縮短後，既有功能（返回、設定按鈕、書籤、跳頁輸入框、拖曳捲軸）皆仍可正常點擊操作，無誤觸或觸控區域過小的問題。

---

## Issue 3：書架封面格數依螢幕方向自適應（直立 3／橫放 4）

**Status:** `ready-for-agent`

**依賴：** 無

**描述：**

`app/lib/screens/library_screen.dart:584-590` 目前 `GridView.builder` 的 `gridDelegate` 是寫死的 `const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, childAspectRatio: 0.62)`，不論螢幕方向皆固定 6 欄。改為依 `MediaQuery.of(context).orientation` 動態決定：`Orientation.portrait` → 3 欄、`Orientation.landscape` → 4 欄（`design.md`「使用者回報項目 3」，範例參考 `tmp/sample/書櫃首頁範例.png`）。`childAspectRatio` 是否需要隨欄數調整（欄數變少、每欄變寬，封面圖比例若沿用同一 `childAspectRatio` 可能會使封面看起來過寬/過窄）需在實作階段真機確認視覺效果，若需要調整比照現有封面圖片比例（書籍封面常見長寬比）決定新數值。**審查建議（Nice to have，非必要）**：原本 6 欄時封面極小，緊貼排列尚可接受；縮為 3 欄後每欄變寬，建議一併補上 `crossAxisSpacing`／`mainAxisSpacing`（起始建議 8／12）避免封面互相緊貼、顯得擁擠，具體數值同樣依真機視覺效果調整。

**單元測試要求：**
- `library_screen_test.dart`：以不同的 `MediaQuery` viewport 尺寸（寬>高＝橫放、高>寬＝直立）分別 pump `LibraryScreen`，驗證 `SliverGridDelegateWithFixedCrossAxisCount.crossAxisCount` 或等效的實際欄位排列數量（例如以 `find.byKey(Key('library_grid_view'))` 取得 widget 後檢查 `gridDelegate`）為 3（直立）／4（橫放）。
- 裝置旋轉（`MediaQuery` 從直立變橫放）後 `LibraryScreen` 正確 rebuild 為新的欄數，不需要重新導航或重建整個畫面。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- 真機（`3CEF42ECD491687`）分別在直立與橫放下確認書架封面格數符合 3／4 欄，旋轉裝置後即時切換正確。

---

## Issue 4：直排文字頂端裁切與本文/頁尾間空白過多

**Status:** ✅ 已完成。直排上下邊距已不再依賴 foliate-js 內建的固定 48px，改由 `main.js` 根據使用者偏好的 `pageMargins` 與 `showFooter` 動態設定。真機 smoke test 與既有 integration 回歸測試均已在實機上全數通過，且經人類人工視覺驗收確認直排頂端壓字與本文/頁尾空白症狀皆已消除，橫排模式不受影響。

**依賴：** 無

**描述：**

見 `spec.md`「`main.js` 上下邊距組裝」。根因：`readest/foliate-js` 的 `paginator.js` 內建 `--_margin-top: 48px`／`--_margin-bottom: 48px`（`paginator.js:1232/1234`，版面配置引擎計算分頁時使用的版心邊界，**不是** CSS `body` padding），`main.js` 的 `buildOverrideCss()` 目前只把使用者 `pageMargins` 偏好套用到左右 `body { padding }`（`main.js` 既有程式碼），從未接上這兩個上下邊距——導致：(a) 直排文字頂端在某些字級/行高組合下實際可視區域被裁切（使用者回報項目 6：「上面會壓到字」）；(b) 本文底部與頁尾之間留白過多（使用者回報項目 7），因為 `ReaderFooter` 在 `Column` 中是 in-flow 子項、已經會壓縮 WebView 可視高度（`reader_screen.dart` 既有註解已標記此為已知的 resize 來源），`paginator.js` 又在這個已經被壓縮過的高度內再扣一次固定 48px 下邊距，兩者疊加造成「多一行空白」。

- **`main.js`**：新增依 `prefs.pageMargins`（或新的上下邊距概念，實作階段決定是否重用同一個滑桿數值或需要獨立控制項——`design.md`「決策」未強制要求新增獨立 UI，優先嘗試重用既有 `pageMargins` 換算出合理的上下邊距值）呼叫 `view.renderer.setAttribute('margin-top', ...)`／`setAttribute('margin-bottom', ...)`，取代目前完全依賴 `paginator.js` 內建 48px 預設值的現狀。
- **底部邊距** 需要避免與 `ReaderFooter` 實際佔用高度重複扣除——具體數值/公式（例如：頁尾顯示時下邊距可以縮小或歸零，因為視窗高度已經因 in-flow footer 被壓縮過一次；頁尾隱藏時則需要保留合理下邊距避免文字貼齊螢幕邊緣）留待實作階段真機量測後決定，不得憑空假設一個數字了事。

**單元測試要求：**
- `main.js` 的 `setAttribute` 呼叫本身無 JVM/JS 單元測試（見 `spec.md`「測試決策」，比照 Epic 17 既有慣例），驗收依賴真機 `integration_test` 與人工視覺確認。
- 若因本 Issue 需要新增/調整 Dart 端偏好欄位（例如把上下邊距獨立成新欄位而非重用 `pageMargins`），比照既有欄位新增時的 `flutter test` 單元測試模式（`toMap`/`fromMap`/`copyWith`/`==`/`hashCode`）。

**驗收標準：**
- `flutter analyze` 乾淨、既有 `flutter test`/`./gradlew :app:testDebugUnitTest` 全數通過（無回歸）。
- 真機（`3CEF42ECD491687`）直排開書，確認畫面頂端文字不再被裁切/壓字。
- 真機確認本文最後一行與頁尾進度列之間不再有明顯多餘空白（不要求數學上完全零間距，只要求「約一行」的過多空白症狀消除）。
- 橫排模式（不受本 Issue 影響的既定行為）需回歸確認未被意外改動。

---

## Issue 5：新增「強制單欄」版面偏好（避免直排部分書籍被拆成需多次翻頁的「兩欄」）

**Status:** ✅ 已完成（含 code review 修訂，分支 `epic-18/issue-5-single-column`）。全 610 項 `flutter test` 通過、`flutter analyze` 乾淨。6 個 Task 皆已實現並分別 commit，另有 2 個 review 修訂 commit：

- Task 1: `BookReaderPrefs.singleColumn` 欄位（commit `f29f57d`）
- Task 2: SQLite schema v11→v12 migration（commit `fcdbb0e`）
- Task 3: `FoliateEpubReaderView.singleColumn` 建構參數（commit `f83814c`）
- Task 4: `ResolvedPreferences`/`ReaderPrefsManagerImpl`/`ReaderScreen` 接通透傳（commit `3513ab8`）
- Task 5: `ReaderSettingsSheet` 新增「強制單欄（直排）」SwitchListTile（commit `c96cbfd`）
- Task 6: `main.js applyPreferences` 新增 `max-column-count` setAttribute + 整合測試（commit `85d3efd`）
- Round 1 review fix: 修正 `_notifyChanged` singleColumn 三態正確性、新增 widget test 可逆性覆蓋（commit `fcb1936`）
- Round 2 review fix: 重寫整合測試——使用 `sample_long_chinese_vertical.epub`（10KB 繁體中文直排 EPUB，~7 頁）搭配 `FoliateEpubReaderView.nextPage()` static helper + `pageIndex` 嚴格遞增斷言（去除 relocate 事件的連續重複值後驗證）（commit `1937647`）

**已知限制（合併時記錄，經人類確認先行合併，不阻擋）**：`tmp/epic-18/reviews/review-issue-5-round3.md` 以真機 mutation test 發現，`app/integration_test/foliate_single_column_test.dart` 的 `pageIndex` 嚴格遞增斷言在既有測試裝置 `3CEF42ECD491687` 上對「`singleColumn` 未生效」這個 mutation 無偵測力——根因非測試斷言邏輯，而是 `paginator.js` 直排書籍欄數公式在該裝置幾何下讓 `singleColumn` 偏好本身變成 no-op（詳細根因與待調查事項見本文件 Issue 6）。六層透傳機制（`BookReaderPrefs`／SQLite／`ResolvedPreferences`／`FoliateEpubReaderView`／UI 開關）與三輪 review 的其餘發現皆已修正確認無誤，僅整合測試對此特定裝置幾何情境的偵測力，以及功能本身在常見裝置尺寸是否真的生效，留待 Issue 6 獨立調查。

**依賴：** 無

**描述：**

見 `spec.md`「`singleColumn` 偏好」表格。根因：切換為直排時，部分書籍因內容寬度/字級組合，被 `readest/foliate-js` 內建的 `--_max-column-count: 2`（`paginator.js:1238`）判定應該以「兩欄」呈現單一邏輯頁，導致使用者需要多按一次「翻頁」才能看完原本認知中的「一頁」內容（使用者回報項目 8，參考 `tmp/issues/2-1.png`／`2-2.png`：同一個「第 13/186 頁」被拆成兩張畫面）。`max-column-count` 本身是 `paginator.js` 既有的、透過 `attributeChangedCallback()` 支援外部 `setAttribute()` 調整的既有機制（`paginator.js:1158-1159`／`1545-1559`），非本 Epic 新增能力，只是目前完全沒有接上任何使用者可調整的偏好。

- **`BookReaderPrefs`**：新增 `final bool? singleColumn` 欄位，`toMap`/`fromMap`/`copyWith`/`==`/`hashCode` 同步新增（比照既有 `showHeader`/`showFooter` 欄位新增時的既有寫法）。
- **`book_reader_prefs` schema migration**：新增 `single_column INTEGER`（nullable），比照既有累加式 `if (oldVersion < N)` migration 慣例。
- **`ReaderSettingsSheet`**：新增 `SwitchListTile(key: Key('reader_settings_single_column'), title: Text('強制單欄（直排）'), value: _singleColumn ?? false, onChanged: ...)`，加入既有「⚙️版面設定」畫面（`design.md` 決策 #3：加入既有設定畫面，非新增獨立入口）。
- **`FoliateEpubReaderView`（Dart）**：新增 `singleColumn` 建構參數，`_buildPreferencesMap()`／`_preferencesChanged()` 同步更新。
- **`ReaderScreen`**：`_buildNativeView()` 的 `FoliateEpubReaderView(...)` 建構呼叫新增 `singleColumn: resolved.singleColumn`。
- **`main.js`**：`window.applyPreferences(prefs)`（或對應的偏好套用函式）新增：`prefs.singleColumn` 非 `undefined` 時呼叫 `view.renderer.setAttribute('max-column-count', prefs.singleColumn ? '1' : '2')`；`undefined` 時完全不呼叫，保留 `paginator.js` 內建預設值（見 `spec.md`「`singleColumn` 偏好」表格下方說明，這是「預設關閉」在機制層級的實作方式）。

**單元測試要求：**
- `BookReaderPrefs`：新增欄位的 `toMap`/`fromMap` round-trip、`copyWith`、`==`/`hashCode` 測試。
- `foliate_epub_reader_view_test.dart`：`singleColumn: true` 時 `openBook`/`setPreferences` 送出的 map 含 `'singleColumn': true`；`singleColumn` 為 `null`（預設）時 map 不含此 key（比照既有其餘 nullable 偏好欄位的既有測試模式）。
- `reader_settings_sheet_test.dart`：`Key('reader_settings_single_column')` 存在、預設狀態為關閉、點擊後觸發 `onChanged` 帶出 `singleColumn: true`。
- **審查修正——原文遺漏的 SQLite migration round-trip 測試**：目前 `sqlite_library_repository.dart:30` 的 schema 版本為 `version: 11`，本 Issue 需升級至 `version: 12` 並新增 `if (oldVersion < 12)` 累加式 migration 分支（比照既有 `_addEpubLayoutColumn` 等既有 helper 命名/寫法慣例）。需在 `app/test/library/sqlite_library_repository_test.dart`（或對應既有測試檔）新增 round-trip 測試：(a) 新裝置直接以 `version: 12` 建表，`book_reader_prefs` 含 `single_column` 欄位且可讀寫；(b) 模擬既有 `version: 11` 裝置升級到 `version: 12` 後，既有資料列的 `single_column` 為 `NULL`（比照 Epic 17 Issue 2 `is_fixed_layout` 欄位新增時的既有測試模式）。資料庫升級屬高風險操作，缺少此測試會讓未來 schema 異動時的回歸不被察覺。
- `main.js` 的 `setAttribute` 呼叫本身無 JVM/JS 單元測試（同 Issue 4），驗收依賴真機 `integration_test`。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨、`./gradlew :app:testDebugUnitTest` 全數通過。
- 真機（`3CEF42ECD491687`）以參考截圖（`tmp/issues/2-1.png`／`2-2.png`）中會拆成「兩欄」的書籍/字級組合開書，確認：(a) 預設關閉時維持現有行為（不強制改變，避免影響已經正常運作的多數書籍）；(b) 開啟「強制單欄」後，原本需要兩次翻頁才能看完的內容整合為一次翻頁可見（比照 `tmp/issues/3.png` 參考效果）。

---

## Issue 6：流式 EPUB「欄數」三態控制 +「欄位大小」閾值（取代 Issue 5 的 `singleColumn`）

**Status:** ✅ 已完成並合併回 `main`（PR #76，merge commit `eda4f79`；review followup commit `fefeb06`）。6 個 Task 皆已實現並分別 commit（`013de7b`/`96de5f6`/`2ba65d5`/`5c3a4d5`/`85ccb72`/`a950fe5`），經計畫兩輪審查（`review-plan-issue-6.md`、`review-plan-issue-6-passed.md`）與程式碼審查（`review-issue-6.md`，Ready to merge: Yes）確認：「雙欄」模式的分欄算式（`Math.ceil`）與 SQLite v13 migration 位置皆經獨立驗算/追蹤確認正確；`flutter analyze` 乾淨、`flutter test` 616 項全數通過。程式碼審查提出的 Important #1（雙欄模式旋轉限制）與 Minor #1-4 已於合併後另行修正並記錄進 ADR 0012。

**依賴：** 無（Issue 5 的 `singleColumn` 六層透傳機制已合併至 `main`，本 Issue 在其基礎上重新設計並取代）

**背景：**

Issue 5 的 `singleColumn` 布林開關因 `paginator.js` 對直排書籍的 `maxColumnCount + 1` 邏輯（`paginator.js:1820`），在多數裝置上是 no-op（見 ADR 0012）。此外，大螢幕裝置（如 AiPaper Reader C，~1758dp）上使用者實際遇到了三欄排版問題。本 Issue 將 `singleColumn` 布林升級為「欄數（Column Mode）」三態選擇 +「欄位大小（Column Size）」閾值滑桿，核心機制改為透過 `setAttribute('max-inline-size', ...)` 控制分欄閾值。

**設計決策（經 grilling session 確認，見 ADR 0012）：**

### 三態行為

| 模式 | `max-inline-size` 行為 | `max-column-count` 行為 | 滑桿狀態 |
|---|---|---|---|
| **單欄** | 設為極大值（如 `99999`）→ 強制 `divisor = 1` | 不設定（保留預設） | 隱藏/停用 |
| **自動** | 使用「欄位大小」滑桿值（預設 720px） | 不設定（保留預設） | 顯示且可調 |
| **雙欄** | JS 端動態計算，保證 `ceil(hostSize / maxInlineSize) <= 2` | 不設定（保留預設） | 隱藏/停用 |

### 滑桿參數

- 範圍：360–1440px
- 步進：60px
- 預設：720px（與 `paginator.js` 內建 `--_max-inline-size` 一致）
- UI 標籤：「欄位大小」，顯示目前數值（如「欄位大小 720px」）

### 適用範圍

僅限流式 EPUB（`ReaderSettingsSheet`）。固定版面 EPUB 和 PDF 不受影響（兩者有各自獨立的「雙頁模式」概念）。

### 資料層變更

- **`BookReaderPrefs`**：移除 `singleColumn: bool?`，新增 `columnMode: ColumnMode?`（enum: `auto`, `single`, `double`）和 `columnSize: double?`
- **SQLite migration v12 → v13**：新增 `column_mode TEXT`（nullable）和 `column_size REAL`（nullable），既有 `single_column` 欄位所有值遷移為 `NULL`（等同自動）
- **`FoliateEpubReaderView`**：`singleColumn: bool?` 替換為 `columnMode: ColumnMode?` + `columnSize: double?`，`_buildPreferencesMap()` 和 `_preferencesChanged()` 同步更新
- **`ResolvedPreferences`**：`singleColumn: bool` 替換為 `columnMode: ColumnMode`（non-nullable，預設 `auto`）+ `columnSize: double`（non-nullable，預設 `720.0`）
- **`main.js`**：`prefs.singleColumn` 分支替換為 `prefs.columnMode` + `prefs.columnSize` 邏輯，依三態行為表呼叫 `setAttribute('max-inline-size', ...)`

### UI 變更

- **取代**：`ReaderSettingsSheet` 的「強制單欄（直排）」`SwitchListTile`（`Key('reader_settings_single_column')`）
- **新增**：分段按鈕（自動/單欄/雙欄），UI 風格比照既有「書寫方向」分段按鈕
- **新增**：「欄位大小」`Slider`，僅在「自動」模式下顯示/啟用
- **參考截圖**：`tmp/image/setting_fields.jpg`

**單元測試要求：**
- `BookReaderPrefs`：`columnMode`/`columnSize` 的 `toMap`/`fromMap` round-trip、`copyWith`、`==`/`hashCode` 測試
- SQLite migration round-trip：v11 → v12 → v13 升級後，既有 `single_column` 值正確遷移為 `NULL`，新欄位可讀寫
- `foliate_epub_reader_view_test.dart`：`columnMode`/`columnSize` 出現/不出現於 `initialPreferences` map、`didUpdateWidget` 變動時觸發 `setPreferences`
- `reader_settings_sheet_test.dart`：三態分段按鈕存在、預設為自動、點擊切換正確觸發 `onChanged`；滑桿僅在自動模式下可見
- `reader_screen_test.dart`：`columnMode`/`columnSize` 從 `ResolvedPreferences` 正確透傳到 `FoliateEpubReaderView`
- `main.js` 的 `setAttribute` 呼叫無 JS 單元測試（同 Issue 4/5 慣例），驗收依賴真機 `integration_test`

**驗收標準：**
- `flutter analyze` 乾淨、既有 `flutter test` 全數通過（無回歸）
- 真機（`3CEF42ECD491687`）直排開書：「單欄」模式下確認只有一欄（不再受制於 `+1` 邏輯）
- 真機直排開書：「雙欄」模式下確認最多兩欄（即使裝置高度 > 1440 CSS px 也不出現三欄）
- 真機直排開書：「自動」模式下調整滑桿，確認欄數隨閾值變化
- 橫排模式回歸確認：三種模式皆不影響橫排既有行為（橫排無 `+1`，本來就正常）

**相關佐證：**
- ADR 0012（`docs/adr/0012-column-mode-replaces-single-column.md`）
- `tmp/epic-18/reviews/review-issue-5-round3.md`（Issue 5 mutation test 發現根因）
- `tmp/image/setting_fields.jpg`（UI 參考截圖）
- `CONTEXT.md`「欄數」「欄位大小」詞彙定義


---

## Issue 7：流式 EPUB Chrome 重構（浮動選單列＋頁眉/進度資訊分離）

**Status:** `ready-for-agent`

**依賴：** 無

**描述：**

見 `design.md`「第二輪真機使用回報」項目 1+2+3。現況 streaming EPUB（`_dispatchedIsFixedLayout == false`）用 in-flow `AppBar`（`reader_screen.dart:1205-1211`，含頁眉文字＋TOC/設定/筆記 3 個 icon）+ in-flow `ReaderFooter`（`reader_screen.dart:1556-1569`，頁碼＋跳頁滑桿）。既有註解（`reader_screen.dart:1192-1203`／`1523-1533`）記載頁尾 in-flow 顯示/隱藏仍會改變 body 實際高度、觸發底下 WebView 整本重新分頁的已知未解問題。FXL（`_isFixedLayout == true`）完全沒這問題，因為其頁眉/按鈕/書籤全部是 `Positioned` 浮動疊加層（`reader_screen.dart:1415-1492`，`ClipOval`+黑底圓鈕），`appBar` 為 `null`，body 高度恆定不變。本 Issue 把 streaming EPUB 的整組 chrome 改成跟 FXL 同款的浮動疊加層架構。

- **`build()`（`reader_screen.dart:1205-1211`）**：`appBar` 判斷式新增「streaming EPUB 一律 null」條件（`format == BookFormat.epub && _dispatchedIsFixedLayout == false` 時，不論 `_chromeVisible` 為何都不建構 `AppBar`——比照 `_isFixedLayout` 現有處理，讓兩種 EPUB 引擎路徑最終殊途同歸都是 `appBar: null`）。`_buildAppBarTitle()`／`_buildAppBarActions()` 對 streaming EPUB 不再被呼叫（PDF 分支不受影響，維持現有 `AppBar`）。
- **`_buildBody()`（`reader_screen.dart:1389-1574`）**：在既有 FXL 浮動按鈕 `Positioned` 區塊（`1415-1492`）之後，新增比照樣式的 streaming EPUB 專屬浮動疊加層區塊，皆以 `format == BookFormat.epub && _dispatchedIsFixedLayout == false && _chromeVisible` 為顯示條件：
  - 返回鈕（`Key('reader_foliate_back_button')`，左上，`Navigator.of(context).pop()`）
  - TOC 鈕（`Key('reader_foliate_toc_button')`，右上第 1 個，複用既有 `_openToc`，啟用條件同既有 `reader_toc_button`：`_autoDetectedWritingMode != null && _tocLoaded`）
  - 版面設定鈕（`Key('reader_foliate_settings_button')`，右上第 2 個，複用既有 `_openLayoutSettings`，啟用條件同既有 `reader_layout_settings_button`：`_autoDetectedWritingMode != null`）
  - 書籤 toggle 鈕（`Key('reader_foliate_bookmark_toggle_button')`，右上第 3 個，★/☆ 圖示切換，邏輯複用 `_fxlBookmarkAtCurrentPosition`/`_toggleFxlBookmark`——**這兩個方法名稱與內部欄位命名目前隱含「FXL 專屬」語意，本 Issue 需要泛用化供兩種 EPUB 引擎共用**，例如改名為 `_bookmarkAtCurrentPosition`/`_toggleBookmark`，行為完全不變，僅移除命名上的 FXL 專屬暗示；`widget.bookmarksRepository != null` 時才顯示，同既有 FXL 條件）
  - 筆記鈕（`Key('reader_foliate_notes_button')`，右上第 4 個，複用既有 `_openNotesSheet(BookFormat.epub)`，`widget.bookmarksRepository != null` 時才顯示）
  - 頁眉文字（`Key('reader_foliate_header_text')`，頂部置中，**純顯示、不可點擊**——內容邏輯複用現有 `_buildAppBarTitle()` 的章節名稱推導部分，但拿掉 `InkWell`/`onTap`，`_resolved?.showHeader ?? true` 為 `false` 時完全不顯示這個 widget，而非顯示靜態「閱讀器」文字——因為浮動疊加層沒有「不顯示頁眉時退回靜態標題」的既有 AppBar 慣例可沿用，`showHeader` 語意收斂為單純「顯示/隱藏這個 widget」）
  - 進度資訊（`Key('reader_foliate_progress_text')`，**純顯示、不可互動**，內容邏輯複用現有 `_buildFoliateEpubFooter()` 的 `currentPage`/`totalPages` 換算，格式維持「168/197」；橫排時置於畫面最下方置中，直排時（`resolved.writingMode == WritingMode.vertical`）改用 `RotatedBox(quarterTurns: 建議 1 或 3，依實際文字方向真機確認)` 置於左下角；`_resolved?.showFooter ?? true` 為 `false` 時不顯示；不顯示時鐘）
  - 進度/跳頁鈕（`Key('reader_foliate_progress_button')`，第 6 顆浮動鈕，位置待實作階段依真機視覺定案——建議與其餘 4 顆功能鈕同側但獨立一行，或畫面下方角落，避免與純顯示的進度資訊互相遮擋；點擊開啟 `showModalBottomSheet` 包住既有 `ReaderFooter` widget（**`ReaderFooter` widget 本身不需修改**，只是把它從目前 in-flow `Column` 子項改為 Bottom Sheet 內容，複用其既有 `currentPage`/`totalPages`/`onPageChanged` 介面與既有 `reader_footer_progress_text`/`reader_footer_jump_input`/`reader_footer_jump_slider` 三個 Key）；只在 `_resolved?.showFooter ?? true` 為 `true` 時顯示這顆按鈕本身（若進度顯示本身就被關閉，跳頁功能也一併隱藏，避免出現「看不到進度卻能跳頁」的不一致體驗）
- **移除舊路徑**：`_buildBody()` 內既有的 streaming EPUB in-flow `ReaderFooter`（`1556-1562`，呼叫 `_buildFoliateEpubFooter`）整段移除，改為上述浮動疊加層；`_buildFoliateEpubFooter()` 方法保留但改由新的進度/跳頁 Bottom Sheet 呼叫端使用其換算邏輯（或直接複用其回傳的 `ReaderFooter` widget實例，置入 Bottom Sheet `builder`）。

**單元測試要求：**
- `reader_screen_test.dart`：streaming EPUB 開書後 `find.byType(AppBar)` 為 `findsNothing`（比照既有 FXL 的斷言模式）；`Key('reader_foliate_back_button')`／`Key('reader_foliate_toc_button')`／`Key('reader_foliate_settings_button')`／`Key('reader_foliate_bookmark_toggle_button')`／`Key('reader_foliate_notes_button')`／`Key('reader_foliate_progress_button')` 皆存在且可點擊，點擊後觸發對應既有行為（開 TOC／開版面設定／toggle 書籤／開筆記／開進度 Bottom Sheet）。
- `Key('reader_foliate_header_text')`：`showHeader == false` 時 `findsNothing`；`true` 時顯示章節名稱且無 `onTap`（透過 `tester.widget<GestureDetector>`/`InkWell` 反查或直接確認外層無手勢 widget 包裹來驗證不可點擊）。
- `Key('reader_foliate_progress_text')`：`showFooter == false` 時 `findsNothing`；直排時外層存在 `RotatedBox` 且 `quarterTurns` 非 0；橫排時不存在 `RotatedBox`（或 `quarterTurns == 0`）。
- 進度/跳頁 Bottom Sheet 開啟後，既有 `reader_footer_progress_text`/`reader_footer_jump_input`/`reader_footer_jump_slider` 三個既有測試案例（輸入頁碼跳頁、拖曳捲軸跳頁、`totalPages <= 1` 停用）需在新的 Bottom Sheet 情境下重新驗證仍然通過。
- PDF 分支既有 `AppBar`／`ReaderFooter` 行為需回歸確認未被本 Issue 意外影響（`find.byType(AppBar)` 對 PDF 仍為 `findsOneWidget`）。
- FXL 既有的 4 個浮動按鈕測試（`reader_fixed_layout_*` keys）需回歸確認未被 `_toggleFxlBookmark`/`_fxlBookmarkAtCurrentPosition` 改名影響（改名後的呼叫端需同步更新，既有測試若直接呼叫這兩個方法名稱本身則需同步改寫，行為斷言不變）。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- 真機（`3CEF42ECD491687`）streaming EPUB 開書：6 顆浮動按鈕皆可點擊、行為與重構前一致；頁眉/進度顯示皆為純資訊、點擊無反應；切換沉浸模式（選單熱區）時 6 顆按鈕＋頁眉＋進度一起顯示/收合。
- 真機確認：切換「顯示頁眉」／「顯示進度」開關後，對應浮動元件正確顯示/隱藏；切換兩者不再觸發 WebView 整本重新分頁（既有 resize 問題已解掉，可用真機肉眼觀察翻頁動畫/捲動位置是否被打斷來間接驗證）。
- 真機確認直排模式下，進度資訊正確以旋轉文字顯示於左下角，格式為「168/197」。
- FXL 與 PDF 既有行為回歸確認無影響。

**相關佐證：**
- `design.md`「第二輪真機使用回報」
- `tmp/image/reading_process.jpg`（直排進度顯示位置參考）

---

## Issue 8：流式 EPUB 真機無法畫線

**Status:** `ready-for-agent`

**依賴：** 無

**描述：**

見 `design.md`「第二輪真機使用回報」項目 4。使用者回報流式 EPUB 在實體機上長按選字後，無法拖曳選取控點調整範圍以建立劃線。

**根因假設（未經真機驗證，本 Issue 第一步即驗證此假設）**：`foliate_epub_reader_view.dart:364-409` 的 `build()` 在 `AndroidView`（WebView）上疊了一層全螢幕 9 宮格 `GestureDetector`，`behavior: HitTestBehavior.opaque` 且註冊 `onHorizontalDragStart`/`onVerticalDragStart`（空 handler，`foliate_epub_reader_view.dart:383-384`）。此機制原記載於 `docs/archive/2026-07-24-epic-7-interaction/design.md:115`，是刻意設計——讓 9 宮格只認 tap、不讓底層原生（foliate-js）自己的滑動翻頁手勢跟 tap 熱區打架（ADR 0009/0010）。此機制原本只用於 FXL（`EpubReaderView`，決策 #7 排除劃線功能，不會踩到衝突），但被原樣複製到同樣需要支援劃線的 `FoliateEpubReaderView`，懷疑長按選字後「拖曳選取控點調整範圍」這個手勢被這層攔截，傳不到底下 WebView。

**參考研究**：`tmp/epic-18/reviews/anx_reader_foliate_js_highlighting_analysis.md`（anx-reader 專案基於 foliate-js 的畫線實作分析）第 4.1 節證實 Android 平台「原生選取 Handle 拖拽」是需要特別處理的獨立手勢類別，該專案監聽 `contextmenu`／`pointercancel` 事件避免拖拉控制點時誤觸自訂選單——若單純拿掉 no-op drag handler 仍無法完全解決，可參考此手法在 `main.js` 既有 `selectionchange` 監聽器（`main.js:432-462`）旁補上對應處理。

**執行流程（比照本 Epic 既有的真機 mutation test 方法論，Issue 5/6 皆用此法）：**

1. 真機（`3CEF42ECD491687`）重現現況：開一本流式 EPUB，長按選字，確認選取控點（handle）拖曳無反應、無法擴大/縮小選取範圍。
2. **Mutation 測試**：暫時移除 `foliate_epub_reader_view.dart:383-384` 的 `onHorizontalDragStart`/`onVerticalDragStart` 兩行，真機重新安裝測試：
   - 畫線功能是否恢復（長按選字→拖曳控點→放開→出現 `AnnotationToolbar`→選色成功建立劃線）？
   - 9 宮格 tap 熱區導覽（翻頁／選單）是否仍正常，有無出現非預期的滑動翻頁（foliate-js 內建手勢跑出來與 tap 熱區衝突）？
3. 依步驟 2 結果決定最終修法：
   - 若移除後兩者皆正常：直接移除這兩行（最簡方案）。
   - 若移除後翻頁手勢衝突：改為更精細的判斷（例如「目前是否有作用中選取範圍」時才放行拖曳，或參考 anx-reader 監聽 `contextmenu`/`pointercancel` 於 `main.js` 端處理，Dart 端 `GestureDetector` 維持攔截但改用不同手段辨識選取拖曳手勢），具體方案由實際測試結果決定，不預先鎖定。
4. 確認最終修法下，9 宮格 tap 導覽、沉浸模式切換、既有換頁功能皆無回歸。

**單元測試要求：**
- 本 Issue 核心驗證依賴真機互動測試（長按選字＋拖曳手勢），非 `flutter test`/`integration_test` 自動化可完整覆蓋的範圍（比照本專案對純手勢層行為的既有測試決策）。
- 若最終修法涉及新增 Dart 端邏輯判斷（例如「是否有作用中選取範圍」的狀態），需為該邏輯本身新增對應的 widget test（依實際修法決定測試內容，本 Issue 撰寫階段無法預先寫出，因修法尚未定案）。
- 既有 `foliate_epub_reader_view_test.dart` 中 9 宮格 `Key('nav_zone_$index')` 存在且可點擊的既有測試需保持通過（回歸確認）。

**驗收標準：**
- 真機（`3CEF42ECD491687`）流式 EPUB 長按選字→拖曳控點調整範圍→放開→成功建立劃線（顏色/底線皆可）。
- 真機確認 9 宮格 tap 熱區導覽（上一頁/下一頁/選單）功能不受影響，無非預期的滑動翻頁。
- `flutter analyze` 乾淨、既有 `flutter test` 全數通過（無回歸）。

**相關佐證：**
- `design.md`「第二輪真機使用回報」
- `tmp/epic-18/reviews/anx_reader_foliate_js_highlighting_analysis.md`
- `docs/archive/2026-07-24-epic-7-interaction/design.md:115`（no-op drag 搶手勢競技場機制原始設計意圖）

---

## Issue 9：裝置旋轉/視窗尺寸變化時重新呼叫 `applyPreferences()`

**Status:** `ready-for-agent`

**依賴：** 無

**描述：**

見 `design.md`「第二輪真機使用回報」項目 5、ADR 0012「已知限制」段。「雙欄」模式的 `max-inline-size`（`main.js:125-132` 的 `targetSize = Math.max(360, Math.ceil(hostSize / 2))`）是呼叫 `applyPreferences()` 當下 `getBoundingClientRect()` 的一次性快照，裝置旋轉/視窗尺寸變化後不會重新計算，欄寬可能不再精確等於「當下 `hostSize` 的一半」。

- **`main.js`**：新增模組級變數 `let lastAppliedPrefs = initialPrefs`（`window.applyPreferences(prefs)` 函式開頭，`main.js:105` 附近，第一行就存一份 `lastAppliedPrefs = prefs`，確保任何時刻呼叫都能取得最新已套用的完整 prefs）。
- 對 `view`（或其父容器，實作階段確認哪個 DOM 節點的尺寸變化才是真正需要關心的訊號）新增**本專案自建**的 `ResizeObserver`（與 `paginator.js:1163` 既有的那個是兩個獨立 observer，互不干擾，不修改 vendored `paginator.js`，比照 ADR 0011）：resize callback 內 debounce（建議 200ms，實作階段可依真機測試結果微調）後呼叫 `window.applyPreferences(lastAppliedPrefs)`。
- **不特例只挑「雙欄模式」才重算**——整包 `lastAppliedPrefs` 全部重新套用，其餘欄位（字級/邊距/CSS 覆蓋）重算是 idempotent、無副作用，不值得為了省這點運算加一層「只有 double 才重算」的特例判斷（比照專案「不特地加狀態抑制無害重複呼叫」的既有慣例）。

**單元測試要求：**
- `main.js` 的 `setAttribute`/`ResizeObserver` 呼叫本身無 JVM/JS 單元測試（比照 Issue 4/5/6 既有慣例），驗收依賴真機 `integration_test` 與人工視覺確認。

**驗收標準：**
- `flutter analyze` 乾淨、既有 `flutter test`／`./gradlew :app:testDebugUnitTest` 全數通過（無回歸）。
- 真機（`3CEF42ECD491687`）流式 EPUB「雙欄」模式下旋轉裝置，確認欄寬重新計算為新 `hostSize` 的一半（可用 `showNavZoneDebugOverlay` 或直接肉眼比對欄寬變化）。
- 真機確認旋轉後目前閱讀位置/頁碼不跳動（`paginator.js` 的 CFI-based relocate 理論上會保留，需真機驗證）。
- 真機確認「單欄」／「自動」模式不受本 Issue 影響（兩者 `max-inline-size` 本就與 `hostSize` 無關）。

**相關佐證：**
- `design.md`「第二輪真機使用回報」
- `docs/adr/0012-column-mode-replaces-single-column.md`「已知限制」段

---

## 審查修訂紀錄（`tmp/epic-18/reviews/review_report.md`，經人類確認後採納）

- **採納**：`spec.md`／Issue 4 澄清 `buildOverrideCss()` 維持純函式，所有 `setAttribute` 呼叫改到 `window.applyPreferences(prefs)`（既有的副作用進入點，`pageTurnMode`/`writingMode` 已是同樣模式）。
- **採納**：`spec.md`／Issue 4 新增明確要求：`setAttribute('margin-top'/'margin-bottom', ...)` 的值必須是帶 CSS 單位的字串（如 `"24px"`），純數字對長度屬性是無效值、會被靜默忽略。
- **採納**：Issue 1 的 Bottom Sheet 版面改為 `Column(mainAxisSize: MainAxisSize.min, children: [關閉列, Flexible(child: ListView(shrinkWrap: true, ...))])`——原文缺少 `mainAxisSize: MainAxisSize.min`，會導致內容再短的 Sheet 也被撐滿版面，與是否使用 `Expanded` 無關（loose constraints + `Column` 預設 `mainAxisSize.max` 所致）。
- **採納**：Issue 2 新增明確要求：`toolbarHeight: 20` 必須同步收斂 `IconButton` 的 `padding`/`constraints`/圖示大小與 `title` 字級，否則會溢出/與內容區重疊/誤觸，具體像素值列為起始建議而非最終規格。
- **採納**：Issue 2 補上既有字串斷言會壞掉的完整清單（`reader_footer_test.dart` 2 處＋`reader_screen_test.dart` 7 處，原審查報告只提到前者，複查後補齊後者）。
- **採納**：Issue 3 補上 `crossAxisSpacing`/`mainAxisSpacing` 的視覺建議（Minor，非必要）。
- **採納**：Issue 5 補上原文遺漏的 SQLite migration round-trip 測試要求（`version: 11 → 12`），複查確認目前 schema 版本確實是 11。
