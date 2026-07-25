# Epic 18 — 真機 UI 精修：工單清單 (Issues)

依 `design.md`（使用者真機 QA 回報 8 項，其中項目 4 拆出不在本 Epic 範圍）與 `spec.md`（Issue 4／5 新介面定義）拆解出的 5 個工單。5 個工單彼此獨立、無依賴關係，可任意順序或平行開始。

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

## Issue 6：調查——「強制單欄」偏好在常見裝置幾何尺寸下可能無法真正生效（Issue 5 衍生追蹤項目）

**Status:** `needs-triage`

**依賴：** Issue 5（`singleColumn` 機制已實作；本項是該實作在真機驗證過程中意外發現的疑慮，**不阻擋** Issue 5 既有六層透傳機制／UI 開關本身合併，僅追蹤「這個偏好在特定裝置幾何下是否真的解決了使用者回報的症狀」這個獨立的產品層級問題）

**背景：**

Issue 5 為直排 EPUB 新增「強制單欄」偏好，機制是透過 `main.js` 呼叫 `view.renderer.setAttribute('max-column-count', singleColumn ? '1' : '2')`，把值寫入 `readest/foliate-js` `paginator.js` 的 `--_max-column-count` CSS 自訂屬性。在 Issue 5 的 code review 第三輪（`tmp/epic-18/reviews/review-issue-5-round3.md`）中，審查者以真機 mutation test（裝置 `3CEF42ECD491687`：先跑一次 fix 生效版本，再暫時把 `main.js` 的 `singleColumn` 分支整段移除模擬「bug 未修復」重跑一次，比對兩次的原始事件序列）驗證「整合測試是否真的能偵測到 bug」時發現：無論 `singleColumn` 開啟或維持未修復狀態，實際算出的欄數（`divisor`）皆相同（都是 2），代表這個開關在該裝置上**對直排書籍完全沒有產生任何可觀察差異**。

**根因（已查證，見 `paginator.js:1817-1822` `#beforeRender()`）：**

```js
const divisor = flow === 'scrolled'
    ? 1
    : Math.min(
        maxColumnCount + (vertical ? 1 : 0),
        Math.ceil(Math.floor(hostSize) / Math.floor(maxInlineSize)),
    )
```

直排書籍（`vertical === true`）會在 `maxColumnCount` 上無條件 `+1`（此行為屬於 vendored、釘定版本的 `readest/foliate-js` 既有邏輯，非本專案程式碼，Epic 18 依既有決策不修改 vendored 檔案）。`maxInlineSize` 固定為 `720`（CSS px，`paginator.js` 內建常數）。因此：

- `singleColumn=true`（`maxColumnCount=1`）：`divisor = min(1+1, ceil(hostSize/720)) = min(2, ceil(hostSize/720))`
- `singleColumn=false`/未設定（`maxColumnCount=2`）：`divisor = min(2+1, ceil(hostSize/720)) = min(3, ceil(hostSize/720))`

這兩者只有在 `ceil(hostSize/720) >= 3`（即 `hostSize > 1440` CSS px）時才會算出不同的 `divisor`。`hostSize` 是直排書籍可視區域的實際渲染高度。

**已知裝置數據：**

| 裝置 | 螢幕解析度／密度 | 換算高度（dp／CSS px 近似值） | `singleColumn` 是否有效差異 |
|---|---|---|---|
| `3CEF42ECD491687`（9491G，Android 15，本專案既有測試裝置） | 1600×2400 physical @ 320dpi（`adb shell wm size`／`wm density` 實測） | 2400 / (320/160) = **1200dp**，已是整台裝置螢幕高度上限 | 否——低於 1440 門檻，`divisor` 兩種狀態皆為 2（已用 mutation test 實測確認，逐值相同） |
| AiPaper Reader C（`design.md` 使用者原始回報項目 8 的問題裝置） | 824×1648／150 PPI | 1648 / (150/160) ≈ **1758dp**（公式推算，**尚未在該裝置實機驗證**） | 理論上有差異，但只從 3 欄降到 2 欄（`min(2,3)=2` vs `min(3,3)=3`），並非真正的「單欄」 |

**待調查/待確認事項：**

1. **在原始回報問題的裝置（或其他真實使用者裝置尺寸）上實機驗證**：`singleColumn=true` 開啟後，直排書籍的實際欄數是否真的從「使用者回報的兩欄拆分症狀」變成單欄，還是像公式推算的一樣只降到 2 欄（症狀部分緩解、但未完全消除）。需要在 AiPaper Reader C 或等效尺寸裝置上實機測試，比對 `tmp/issues/2-1.png`／`2-2.png`／`3.png` 參考截圖的實際呈現效果。
2. **是否需要重新設計「強制單欄」的實作機制**：若確認在常見裝置尺寸（包含 Issue 5 驗收標準指定的 `3CEF42ECD491687`）上此偏好是 no-op，需要評估是否有其他方式能繞過 `paginator.js` 對直排書籍的 `+1` 邏輯（例如：是否有其他 `observedAttributes` 可用、是否需要透過 CSS 直接覆蓋 `--_max-column-count-spread`／`--_max-column-count-portrait` 而非只設定 `--_max-column-count` 本身、或需要向上游 `readest/foliate-js` 回報這個行為）。
3. **Issue 5 的真機驗收（`plan-issue-5.md` Task 7）是否已經涵蓋這個情境**：若 Task 7 的真機驗收是在 `3CEF42ECD491687` 上進行，依本項發現，該次驗收記錄需要重新檢視——應改用已知會被拆成兩欄的書籍在 `3CEF42ECD491687` 上仔細比對開關開/關的實際視覺差異，而非僅信任先前的驗收記錄（該裝置幾何下開關理論上不應有任何視覺差異）。
4. **`integration_test/foliate_single_column_test.dart` 目前的測試缺口**：Issue 5 的核心症狀回歸測試（`pageIndex` 嚴格遞增）目前在 `3CEF42ECD491687` 上對此 mutation 無偵測力，根因就是本項調查的問題（開關本身在此裝置幾何下是 no-op，而非測試斷言邏輯的問題）。若本項調查確認需要調整實作機制，該測試屆時應一併修正；若調查結論是「此裝置幾何本來就不該預期有效果，這是產品層級的已知限制」，則測試需要改用其他裝置幾何、或改用直接讀取欄數的方式（見 `review-issue-5-round3.md` Critical #1 建議的方案 (a)：透過 `evaluateJavascript` 讀取渲染後的 `--_column-count` 計算值）才能有意義。

**相關佐證：**
- `tmp/epic-18/reviews/review-issue-5-round3.md`（Critical #1，附完整實機 mutation test 數據）
- `docs/epics/epic-18-reader-device-qa/spec.md`「`singleColumn` 偏好」表格（Issue 5 原始機制設計）
- `docs/epics/epic-18-reader-device-qa/design.md` 使用者回報項目 8 與參考截圖 `tmp/issues/2-1.png`／`2-2.png`／`3.png`

---

## 審查修訂紀錄（`tmp/epic-18/reviews/review_report.md`，經人類確認後採納）

- **採納**：`spec.md`／Issue 4 澄清 `buildOverrideCss()` 維持純函式，所有 `setAttribute` 呼叫改到 `window.applyPreferences(prefs)`（既有的副作用進入點，`pageTurnMode`/`writingMode` 已是同樣模式）。
- **採納**：`spec.md`／Issue 4 新增明確要求：`setAttribute('margin-top'/'margin-bottom', ...)` 的值必須是帶 CSS 單位的字串（如 `"24px"`），純數字對長度屬性是無效值、會被靜默忽略。
- **採納**：Issue 1 的 Bottom Sheet 版面改為 `Column(mainAxisSize: MainAxisSize.min, children: [關閉列, Flexible(child: ListView(shrinkWrap: true, ...))])`——原文缺少 `mainAxisSize: MainAxisSize.min`，會導致內容再短的 Sheet 也被撐滿版面，與是否使用 `Expanded` 無關（loose constraints + `Column` 預設 `mainAxisSize.max` 所致）。
- **採納**：Issue 2 新增明確要求：`toolbarHeight: 20` 必須同步收斂 `IconButton` 的 `padding`/`constraints`/圖示大小與 `title` 字級，否則會溢出/與內容區重疊/誤觸，具體像素值列為起始建議而非最終規格。
- **採納**：Issue 2 補上既有字串斷言會壞掉的完整清單（`reader_footer_test.dart` 2 處＋`reader_screen_test.dart` 7 處，原審查報告只提到前者，複查後補齊後者）。
- **採納**：Issue 3 補上 `crossAxisSpacing`/`mainAxisSpacing` 的視覺建議（Minor，非必要）。
- **採納**：Issue 5 補上原文遺漏的 SQLite migration round-trip 測試要求（`version: 11 → 12`），複查確認目前 schema 版本確實是 11。
