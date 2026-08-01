# Epic 18 — 真機 UI 精修：工單清單 (Issues)

依 `design.md`（使用者真機 QA 回報 8 項，其中項目 4 拆出不在本 Epic 範圍）與 `spec.md`（Issue 4／5 新介面定義）拆解出的 5 個工單（Issue 1-6，其中 Issue 6 取代 Issue 5）。Issue 6 完成合併後，使用者持續真機使用中再回報 5 項（見 `design.md`「第二輪真機使用回報」），拆解為 Issue 7-9。Issue 8 於 `/diagnose` 調查後發現根因是 Flutter `AndroidView` 觸控轉發機制本身的限制（見 ADR 0013），改組為 Spike（驗證 `flutter_inappwebview` 是否可解），並新增 Issue 10 承接 Spike 通過後的完整遷移實作（**依賴 Issue 8**）。Issue 7-10 完成合併後，使用者持續真機使用中再回報 4 項（見 `design.md`「第三輪真機使用回報」），拆解為 Issue 11-14。2026-07-29 使用者於 `epic-19-shelf-reading-enhance` Issue 1（全螢幕模式）真機驗收時意外發現 FXL 橫屏雙頁置中留白問題，經 `/superpowers:requesting-code-review` 審查子代理判斷與該次變更無關、屬本 Epic 既有雙頁/FXL 領域的殘留問題，拆出獨立的 Issue 15。2026-07-30 `/grill-with-docs` Discovery 確認實際根因並非雙頁置中留白，而是部分漫畫 EPUB 被「引擎分派判斷」誤判為流式，Issue 15 已改為新增「人工版面覆蓋」選項（見 `design.md`「Issue 15 根因重新診斷與人工版面覆蓋功能」），狀態更新為 `ready-for-agent`。全部工單彼此獨立、無依賴關係（僅 Issue 10 依賴 Issue 8），可任意順序或平行開始。

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

**Status:** ✅ 已完成。書架封面格數依螢幕方向動態調整（直立 3 欄、橫放 4 欄），`childAspectRatio: 0.62` 維持不變，補上 `crossAxisSpacing: 8`／`mainAxisSpacing: 12` 避免封面緊貼。`flutter analyze` 乾淨、659 項測試全數通過。真機（`3CEF42ECD491687`）驗收通過：直立 3 欄、橫放 4 欄、旋轉即時切換正確，封面比例與間距視覺正常。

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

**Status:** ✅ 已完成並合併回 `main`（PR #79，merge commit `1302820`；分支 `epic-18/issue-7-foliate-chrome-refactor`）。依 `plans/plan-issue-7.md` 4 個 Task 逐一實作並分別 commit：

- Task 1：泛用化 FXL 書籤 toggle 方法命名（commit `97a1475`）
- Task 2：AppBar 抑制、6 顆浮動按鈕與頁眉/進度疊加層、移除舊 in-flow 頁尾（commit `afa34c7`）
- Task 3：修正因本 Issue 而失效的既有測試（commit `d088412`）
- Task 4：真機（`3CEF42ECD491687`）驗收（人工執行，8 項 Step 皆通過）

`flutter analyze` 乾淨、`flutter test` 644 項全數通過。程式碼審查（`reviews/review-issue-7.md`）結論為「Ready to merge, with fixes」（0 Critical／2 Important／2 Minor），2 項 Important（狀態文件更新、`plan-issue-7.md` Task 3 既有測試回歸計數修正）已於合併前依審查意見補正（commit `af5298e`）。

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

## Issue 8：Spike——`flutter_inappwebview` 能否解決流式 EPUB 真機無法畫線問題

**Status:** ✅ 已完成並合併回 `main`（PR #77，merge commit `fc71c53`；分支 `spike/epic-18-issue-8-inappwebview`）。首輪複審（`tmp/epic-18/reviews/review-issue-8-spike.md`）發現 Task 1 選取手勢核心驗證從未實際執行、`selectionLog` 為空卻仍下 GO 結論，已退回補測；補測後（commit `d0abab3`）真機以 `adb shell input touchscreen swipe` 實際模擬長按選字＋兩次拖曳位移，`selectionLog` 取得 3 筆隨拖曳遞增、內部一致的 `CHANGED` 紀錄，Task 2（ES module 載入）維持 `moduleLoadResult == 'module-ok'`，兩項 AND 判準皆有實測證據支撐，複審通過（`tmp/epic-18/reviews/review-issue-8-spike-round2.md`）。結論 **GO**，`flutter_inappwebview` 依賴已保留於 `pubspec.yaml`，完整遷移實作交由 Issue 10 承接。

**依賴：** 無（起始工單，可立即開始）

**背景：**

見 `design.md`「第二輪真機使用回報」項目 4。使用者回報流式 EPUB 在實體機上長按選字後，選取控點（handle）會出現，但拖曳控點調整範圍完全沒反應，導致無法建立劃線/備註。

原假設（Dart 端 9 宮格 `GestureDetector` 的 no-op drag handler 攔截了拖曳手勢）已透過 `/diagnose` session 的真機獨立實測**推翻**：把 `foliate_epub_reader_view.dart` 疊在 `AndroidView` 上的整層 `GestureDetector`（含 `onTap`）完全拿掉、只留裸 `AndroidView`，用 `adb shell input` 送真實硬體層級觸控重測，`webView.setOnTouchListener` 依然零觸發（`DecorView.dispatchTouchEvent` 有收到，但沒傳到 `WebView`）。三條獨立調查路線（`reviews/issue-8-selection-detection-report.md` 的 8 種方案實測、本次真機獨立驗證、`reviews/issue_8_new_solution_proposal.md`）收斂到同一根因：Flutter 官方 `AndroidView` 包裝 `android.webkit.WebView` 時，觸控轉發機制本身就無法完整還原「長按選字→拖曳控點」這個手勢序列，非本專案程式碼缺陷，詳見 **ADR 0013**。

`flutter_inappwebview` 有自己獨立於 Flutter 官方 `AndroidView` 的原生嵌入與觸控轉發機制，`anx-reader`（同樣是 Flutter + `foliate-js` 的產品）已在正式產品環境證實此路徑可行。但這是本專案完全沒用過的第三方套件，且流式 EPUB 目前的原生嵌入（`FoliateEpubReaderView.kt`）用了 `WebViewAssetLoader` 搭配一個當初特別處理過的 ES module CORS/MIME 陷阱（`main.js`/`view.js` 等皆為 `<script type="module">`，透過 `file://` 直接載入會被瀏覽器拒絕，見既有程式碼註解）——`flutter_inappwebview` 換一套資源載入機制後，這個陷阱是否會被重新踩到，未經驗證。比照 ADR 0011 當初「先做 Spike 驗證核心假設，GO 才進入完整遷移」的既有慣例（`epic-17-epub-render-migration` Issue 1），本 Issue 只做最小範圍驗證，不做完整遷移實作。

**驗證範圍（唯二兩項）：**

1. **觸控轉發**：用 `flutter_inappwebview` 的 `InAppWebView` 元件開一個最小 harness（不需要完整 `foliate-js`，可先用一個含長段可選文字的簡單 HTML 頁面驗證），真機長按選字→拖曳控點，確認選取範圍會隨拖曳正確擴大/縮小，且 Dart 端能透過 `InAppWebViewController.addJavaScriptHandler()`（JS 側呼叫 `window.flutter_inappwebview.callHandler('onSelectionChanged', ...)`）收到選取變動事件。
2. **ES module 資源載入**：把現有 `app/android/app/src/main/assets/foliate/` 的 8 個檔案（`index.html`／`main.js`／`view.js` 等）透過 `InAppWebView` 的 `shouldInterceptRequest` callback（`Future<WebResourceResponse?> Function(InAppWebViewController controller, WebResourceRequest request)`，已查證為 `flutter_inappwebview` 6.1.5 現行 API，非 deprecated 的 `androidShouldInterceptRequest`）比照現行 Kotlin `WebViewAssetLoader` 的 virtual origin（`https://appassets.androidplatform.net/assets/foliate/...`）與 `.js` 副檔名 MIME 覆寫邏輯（`text/javascript`）服務，確認 `<script type="module">` 的 `import` 陳述式正常載入、不重現 CORS 錯誤。

**明確不在本 Issue 範圍**：完整遷移實作（`FoliateEpubReaderView.kt`/`.dart` 改寫、`main.js` 選取偵測邏輯改為 `contextmenu`/`pointercancel`、字型 `@font-face`／書本內容讀取搬到 Dart 端等）——這些留待 Issue 10（GO 之後才展開，見下方）。

**GO/NO-GO 決策路徑：**
- **GO**（兩項驗證皆通過）：於 `design.md` 記錄 Spike 結果，Issue 10 開始撰寫完整遷移計畫。
- **NO-GO**（任一項失敗）：記錄具體失敗證據於 `reviews/`，`design.md` 補上「已評估並否決」的結論，回頭評估 ADR 0013 的其餘替代方案（例如接受劃線功能侷限、或重新評估其他 WebView 封裝方案）。

**單元測試要求：** 無（研究/驗證性質，比照 `epic-17-epub-render-migration` Issue 1 先例）。過程中產生的 throwaway harness 程式碼與素材（截圖、logcat）驗證後需清理，不進版控（放 `tmp/`，已 gitignore）。

**驗收標準：**
- 真機（`3CEF42ECD491687`）長按選字→拖曳控點→選取範圍正確擴大/縮小→Dart 端 `addJavaScriptHandler` 收到對應事件，皆有截圖或 log 佐證。
- ES module 透過 `shouldInterceptRequest` 載入無 CORS/MIME 錯誤，`main.js`（或等效驗證用 JS 檔）內的 `import` 陳述式成功執行。
- 明確依 GO/NO-GO 分類，寫入驗證報告（建議路徑：`docs/epics/epic-18-reader-device-qa/reviews/spike-flutter-inappwebview-selection.md`）。
- 依結果更新 `design.md` 對應段落。

**相關佐證：**
- ADR 0013（`docs/adr/0013-flutter-inappwebview-for-foliate-selection.md`）
- `design.md`「第二輪真機使用回報」
- `tmp/epic-18/reviews/anx_reader_foliate_js_highlighting_analysis.md`
- `docs/epics/epic-18-reader-device-qa/reviews/issue-8-selection-detection-report.md`
- `docs/epics/epic-18-reader-device-qa/reviews/issue_8_new_solution_proposal.md`

---

## Issue 9：裝置旋轉/視窗尺寸變化時重新呼叫 `applyPreferences()`

**Status:** ✅ 已完成並合併回 `main`（PR #80，merge commit `7fbafb9`；分支 `epic-18/issue-9-resize-reapply-prefs`）。依 `plans/plan-issue-9.md` 3 個 Task 逐一實作並分別 commit：

- Task 1：`main.js` 新增 `lastAppliedPrefs` 追蹤最後套用偏好（commit `54032d0`）
- Task 2：`main.js` 新增 `ResizeObserver` 於旋轉/尺寸變化時重新套用偏好（commit `499c3f5`）
- Task 3：真機（`3CEF42ECD491687`）驗收（人工執行）——雙欄模式旋轉後欄寬正確重算、目前頁碼/進度不跳動、單欄／自動模式不受影響，皆通過。

程式碼審查（`tmp/epic-18/reviews/review-issue-9.md`）結論為「Ready to merge, with fixes」（0 Critical／2 Important／2 Minor）：2 項 Important（`ResizeObserver` 首次 `.observe()` 保證觸發一次初始 callback、潛在的重複觸發風險）已併入 Task 3 真機驗收清單，人工肉眼確認皆未觀察到問題；Minor #1（`ResizeObserver` 未保留參照/未 `disconnect()`）已修正，新增 `hostResizeObserver` 保留參照並說明目前無對應 `disconnect()` 呼叫時機（commit `d90b54c`）；Minor #2（純 JS 變更下 `flutter analyze`/`flutter test` 驗證力有限）屬既有慣例如實記錄，非可修正項目。`flutter analyze` 乾淨、`flutter test` 644 項全數通過。

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

## Issue 10：流式 EPUB 原生嵌入遷移至 `flutter_inappwebview`（完整實作）

**Status:** ✅ 已完成並合併回 `main`（PR #78，merge commit `17ad0a8`）。完整實作 Task 1 至 Task 7 並通過雙輪 Code Review（`review-code-issue-10.md` 與 `review-issue-10-worktree-implementation.md` FULL PASS）：
- `db24b9c` Task 1：Dart codec layer（`foliate_bridge_codec.dart` + 25 tests）
- `be61dcd` Task 2：Native resource channel（`ReaderResourceChannel.kt` + `MainActivity` volumeKey dispatch）
- `b315713` Task 3：Dart native bridge（`foliate_native_bridge.dart` + 7 tests）
- `15f2a6e` Task 4：`FoliateEpubReaderView` 改用 `InAppWebView`（公開介面不變）
- `3cb723c` Task 5：`main.js` JS 橋接改為 `flutter_inappwebview.callHandler`，依 ADR 0013 新增 Android `contextmenu`/`pointercancel` 選字偵測
- `54cb037` Task 6：移除舊有 Kotlin 檔案與 PlatformView 註冊
- `dc578f4` Review Fix 1：更新 `main.js` 架構註解，改指向 Dart 端橋接
- `4c0351c` Review Fix 2：回補 9 宮格導航熱區 widget test，抽出共用 `FakeInAppWebViewPlatform`（全專案測試數提升至 634）

**測試與驗證**：抽出 `FakeInAppWebViewPlatform` 讓 `InAppWebView` Widget 可在純 `flutter_test` 環境 pump，回補熱區導航與 debug overlay 測試。全專案 634 項測試全數通過、`flutter analyze` 為 `No issues found!`。

**依賴：** Issue 8（Spike 須為 GO 結論才可開始）

**描述：**

見 ADR 0013。Issue 8 的 Spike 若確認 `flutter_inappwebview` 能解決真機無法畫線問題且不重現 ES module 載入陷阱，本 Issue 執行完整遷移：

- `app/pubspec.yaml` 正式引入 `flutter_inappwebview` 依賴。
- `app/lib/reader/foliate_epub_reader_view.dart`：`AndroidView` 換成 `InAppWebView`，公開建構參數與 callback 契約（`onPageRendered`／`onSelectionChanged`／`onSelectionCleared`／`onLocatorChanged`／`onAnnotationActivated` 等）維持不變，`ReaderScreen` 不需要改動。
- JS↔Dart 橋接從 Kotlin `addJavascriptInterface`（`window.FoliateBridge.xxx(...)`）改為 `flutter_inappwebview` 的 `addJavaScriptHandler`（JS 側改為 `window.flutter_inappwebview.callHandler('xxx', ...)`），`main.js` 目前 8 處 `window.FoliateBridge.` 呼叫點需要逐一改寫（`onTableOfContentsReady`×2／`onPageRendered`／`onLocatorChanged`／`onAnnotationActivated`／`onSelectionCleared`／`onSelectionChanged`／`onError`）。
- `main.js` 新增 Android 專用的 `contextmenu`/`pointercancel` 選取偵測分支（比照 ADR 0013 決策，anx-reader 已驗證手法），取代現有 iframe `selectionchange` 監聽器在 Android 平台完全不觸發的既有邏輯；非 Android 平台維持既有邏輯。
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt`／`FoliateEpubReaderViewFactory.kt`：`WebViewAssetLoader`（含 `.js` MIME 覆寫）、`BookPathHandler`（讀取目前開啟書籍檔案/`content://` URI）、`buildFontFaceCss()`（5 款內建字型 `@font-face` 產生）三塊邏輯，需要決定搬到 Dart 端 `shouldInterceptRequest` 或以其他方式對接 `flutter_inappwebview`——具體設計留待本 Issue 的 `plan-issue-10.md` 階段依 Issue 8 Spike 的實測結果決定，`MainActivity.kt` 的 `FoliateEpubReaderViewFactory` 註冊（`MainActivity.kt:123-125`）預期整段移除。
- `ReaderViewAttachmentTracker`（原生端音量鍵攔截狀態追蹤，見 `epic-7-interaction` Issue 7）目前掛在 `FoliateEpubReaderView.kt` 的 `init`/`dispose()`，遷移後需要確認新架構下這個追蹤機制如何對接，不得讓音量鍵翻頁功能回歸。

**單元測試要求：** 待 `plan-issue-10.md` 階段依實際設計定案（此階段無法預先寫出，需求已在 Issue 8 Spike 確認可行後才知道最終架構）。至少須涵蓋：`foliate_epub_reader_view_test.dart` 既有測試套件（`initialPreferences` map 組裝、`didUpdateWidget` 偏好變動、9 宮格熱區、`onSelectionChanged`/`onSelectionCleared`/`onLocatorChanged` 等 callback 解析）全數改寫後依然通過對稱行為；真機 `integration_test` 回歸確認換頁/劃線/目錄/書籤功能無 regression。

**驗收標準：**
- 真機（`3CEF42ECD491687`）流式 EPUB 長按選字→拖曳控點→放開→成功建立劃線（顏色/底線皆可）。
- 既有功能（換頁、9 宮格熱區、沉浸模式、TOC、書籤、直排/橫排切換、欄數模式、音量鍵翻頁）真機回歸確認無 regression。
- `flutter analyze` 乾淨、`flutter test` 全數通過、`./gradlew :app:testDebugUnitTest`（若原生端仍有可測邏輯）通過。

**相關佐證：**
- ADR 0013（`docs/adr/0013-flutter-inappwebview-for-foliate-selection.md`）
- Issue 8 的 Spike 結論報告（`reviews/spike-flutter-inappwebview-selection.md`）
- `tmp/epic-18/reviews/issue_8_new_solution_proposal.md`

---

## Issue 11：流式 EPUB 進度/跳頁 Bottom Sheet 補上 `SafeArea`

**Status:** ✅ 已完成並合併回 `main`（PR #81，merge commit `19c9468`）。`_openFoliateProgressSheet()` 的 `builder` 已補上 `SafeArea` 包裹，比照 `ReaderSettingsSheet`/`TocBottomSheet` 既有寫法。新增的 widget 測試（模擬 `viewPadding.bottom: 48` 的系統手勢列情境）驗證跳頁滑桿確實位於 `SafeArea` 之內，`flutter analyze` 乾淨、`flutter test` 全數通過。真機驗收由使用者本人於裝置 `3CEF42ECD491687` 上實測完成：開啟流式 EPUB 後點擊進度/跳頁浮動按鈕，確認跳頁捲軸與輸入框完整顯示在系統手勢列上方，可正常拖曳互動、未被遮擋，結果為 Pass。

**依賴：** 無

**描述：**

見 `design.md`「第三輪真機使用回報」項目 1。`_openFoliateProgressSheet()`（`reader_screen.dart:1836-1845`）的 `builder` 直接回傳 `_buildFoliateEpubFooter(positionInfo)`（一個 `ReaderFooter`），未包 `SafeArea`，導致有系統手勢列/三鍵導覽列的裝置上，進度捲軸/跳頁輸入框被系統工具列蓋住、無法正常拖曳。對照同檔案內其餘 Bottom Sheet：`ReaderSettingsSheet`（`reader_settings_sheet.dart:144`）、`TocBottomSheet`（`toc_bottom_sheet.dart:114`）皆已用 `SafeArea` 包裹其內容，唯獨這個進度/跳頁 Sheet 遺漏。

- **`_openFoliateProgressSheet()`**（`reader_screen.dart:1836-1845`）：`builder` 回傳值改為 `SafeArea(child: positionInfo == null ? const SizedBox.shrink() : _buildFoliateEpubFooter(positionInfo))`，比照 `ReaderSettingsSheet`/`TocBottomSheet` 既有寫法（`SafeArea` 預設 `top`/`bottom` 皆為 `true`，Bottom Sheet 情境下只需要在意 `bottom`，直接沿用預設值即可，不需要額外指定 `top: false`——那是 `_buildBody()` 主畫面 `Scaffold` 才需要的特例，見該處註解）。

**單元測試要求：**
- `reader_screen_test.dart`：以有 `viewPadding.bottom`（模擬系統手勢列/三鍵導覽列）的 `MediaQuery` pump `ReaderScreen`（流式 EPUB），點擊 `reader_foliate_progress_button` 開啟 Bottom Sheet 後，`find.byType(SafeArea)` 在該 Bottom Sheet 的 widget 子樹中 `findsOneWidget`（或以 `tester.getBottomLeft(find.byKey(Key('reader_footer_jump_slider')))` 確認其 `dy` 不超過 `size.height - viewPadding.bottom`，證明沒有被系統工具列遮擋範圍覆蓋）。
- 既有 `reader_footer_progress_text`/`reader_footer_jump_input`/`reader_footer_jump_slider` 相關測試案例（輸入頁碼跳頁、拖曳捲軸跳頁、`totalPages <= 1` 停用）需在補上 `SafeArea` 後重新驗證仍然通過（純外層包裝，預期無行為變化）。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- 真機（`3CEF42ECD491687`，若可取得有系統手勢列的裝置則一併確認）開啟進度/跳頁 Bottom Sheet，確認捲軸/輸入框完整顯示在系統工具列上方，可正常拖曳互動。

**相關佐證：**
- `design.md`「第三輪真機使用回報」項目 1

---

## Issue 12：進度/跳頁浮動按鈕移除 `showFooter` 額外限制

**Status:** ✅ 已完成並合併回 `main`（PR #82，merge commit `4bb00ab`）。`reader_foliate_progress_button` 的顯示條件已移除 `(_resolved?.showFooter ?? true)`，改與其餘 5 顆浮動按鈕共用同一組 `format == BookFormat.epub && _dispatchedIsFixedLayout == false && _chromeVisible` 基底；`reader_foliate_progress_text`（資訊顯示）維持不變，仍受 `showFooter` 控制。既有測試已改寫並驗證先紅後綠，`flutter analyze` 乾淨、`flutter test` 646 個測試全數通過。真機驗收由使用者本人於裝置 `3CEF42ECD491687` 實測完成：關閉「顯示頁尾」後，進度/跳頁浮動按鈕仍與其餘 5 顆按鈕一起顯示，點擊可正常開啟跳頁 Bottom Sheet；切換沉浸模式時該按鈕仍跟其餘按鈕一起收合，結果為 Pass。

**依賴：** 無

**描述：**

見 `design.md`「第三輪真機使用回報」項目 2。`reader_foliate_progress_button` 的顯示條件（`reader_screen.dart:1618-1621`）比其餘 5 顆浮動按鈕（`reader_foliate_back_button`/`reader_foliate_toc_button`/`reader_foliate_settings_button`/`reader_foliate_bookmark_toggle_button`/`reader_foliate_notes_button`）多了 `(_resolved?.showFooter ?? true)` 這個額外條件。此為 Issue 7 計畫階段的刻意設計（理由：「看不到進度就不該讓使用者以為能跳頁」的一致性考量），使用者實際使用後回報希望此按鈕比照其餘 5 顆只看 `_chromeVisible`，恆常可跳頁（不論「顯示頁尾」開關為何）。

- **`reader_screen.dart:1618-1621`**：`reader_foliate_progress_button` 的 `Positioned` 顯示條件，移除 `(_resolved?.showFooter ?? true)` 這一項，改為與其餘 5 顆按鈕相同的 `format == BookFormat.epub && _dispatchedIsFixedLayout == false && _chromeVisible`。

**單元測試要求：**
- `reader_screen_test.dart`：既有測試「流式 EPUB：`showFooter=false` 時進度文字與進度/跳頁按鈕皆不顯示（Issue 7）」需修改為「`showFooter=false` 時進度文字不顯示，但進度/跳頁按鈕仍顯示」（`find.byKey(Key('reader_foliate_progress_button'))` 改為 `findsOneWidget`），並補上點擊該按鈕後仍可正常開啟 Bottom Sheet 的斷言。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- 真機（`3CEF42ECD491687`）確認：關閉「顯示頁尾」後，進度/跳頁浮動按鈕仍與其餘 5 顆按鈕一起顯示，點擊仍可開啟跳頁 Bottom Sheet。

**相關佐證：**
- `design.md`「第三輪真機使用回報」項目 2
- `issues.md` Issue 7（本 Issue 修正的原始設計決策出處）

---

## Issue 13：流式 EPUB 頁首/進度文字從沉浸模式拆出、跟內文常駐顯示

**Status:** ✅ 已完成並合併回 `main`（PR #83，merge commit `5b83ba5`）。頁首文字（`reader_foliate_header_text`）與進度文字（`reader_foliate_progress_text`）的 `Positioned` 顯示條件皆已移除 `_chromeVisible`，改為只依各自的 `showHeader`/`showFooter` 開關決定顯示；6 顆浮動功能按鈕（含 Issue 12 修正後的進度/跳頁鈕）維持不變，仍跟隨 `_chromeVisible`。新增的兩個測試驗證沉浸模式收起選單後，按鈕收合但頁首/進度文字仍常駐顯示，`flutter analyze` 乾淨、`flutter test` 648 個測試全數通過。真機驗收由使用者本人於裝置 `3CEF42ECD491687` 實測完成：頁首/進度文字在沉浸模式收合時仍常駐顯示，再次叫出選單時按鈕與常駐文字無重疊衝突，關閉「顯示頁首」/「顯示進度」仍可正確隱藏對應文字；FXL 與 PDF 既有沉浸模式行為未受影響，結果為 Pass。

**依賴：** 無

**描述：**

見 `design.md`「第三輪真機使用回報」項目 3。全 App 既有「沉浸模式」設計（`_chromeVisible`，`design.md` 第一輪「決策」#14）：點擊畫面中央熱區同時切換 PDF 的 AppBar/頁尾、FXL 與流式 EPUB 的所有浮動按鈕＋頁首＋進度文字。使用者回報希望**僅流式 EPUB**的頁首文字（`reader_foliate_header_text`）與進度文字（`reader_foliate_progress_text`）改為跟內文（`_resolved?.showHeader`/`showFooter` 開啟時）常駐顯示，不受 `_chromeVisible` 切換影響；6 顆浮動**功能按鈕**（含 Issue 12 修正後的進度/跳頁鈕）維持跟隨 `_chromeVisible`——本 Issue 只拆分「資訊顯示」，不動「功能操作」的既有沉浸模式行為。FXL（本無頁首/頁尾文字，只有按鈕）與 PDF（in-flow 頁尾，牽動既有 resize 限制，範圍外）不受本 Issue 影響。

- **`reader_screen.dart:1637-1646`**（頁首文字 `Positioned`）：顯示條件由 `format == BookFormat.epub && _dispatchedIsFixedLayout == false && _chromeVisible && (_resolved?.showHeader ?? true)` 改為 `format == BookFormat.epub && _dispatchedIsFixedLayout == false && (_resolved?.showHeader ?? true)`（移除 `_chromeVisible`）。
- **`reader_screen.dart:1647-1666`**（進度文字 `Positioned`，含直排/橫排兩種佈局分支）：顯示條件由 `format == BookFormat.epub && _dispatchedIsFixedLayout == false && _chromeVisible && (_resolved?.showFooter ?? true) && (_epubPositionInfo?.totalPages ?? 0) > 0` 改為 `format == BookFormat.epub && _dispatchedIsFixedLayout == false && (_resolved?.showFooter ?? true) && (_epubPositionInfo?.totalPages ?? 0) > 0`（移除 `_chromeVisible`）。
- 6 顆浮動功能按鈕（`reader_foliate_back_button`／`reader_foliate_toc_button`／`reader_foliate_settings_button`／`reader_foliate_bookmark_toggle_button`／`reader_foliate_notes_button`／`reader_foliate_progress_button`）的既有顯示條件**不變動**，繼續跟隨 `_chromeVisible`。

**單元測試要求：**
- `reader_screen_test.dart`：既有測試「流式 EPUB：頁眉純顯示章節名稱、不可點擊，`showHeader=false` 時不顯示（Issue 7）」等相關測試，需新增/調整案例驗證 `_chromeVisible == false`（沉浸模式已收起選單）時，`showHeader == true` 的頁首文字與 `showFooter == true` 的進度文字**仍然顯示**（`findsOneWidget`），但 6 顆浮動功能按鈕在同一狀態下**不顯示**（`findsNothing`），證明兩者已正確拆分為獨立顯示條件。
- 既有「`showHeader`/`showFooter` 為 `false` 時頁首/進度文字不顯示」的既有測試案例需保持通過（本 Issue 不改變這一半的判斷條件，只移除 `_chromeVisible` 這一項）。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- 真機（`3CEF42ECD491687`）確認：開啟「顯示頁首」/「顯示進度」後，點擊熱區收起選單（`_chromeVisible = false`）時，頁首文字/進度文字仍常駐顯示；6 顆浮動按鈕正確收合。
- FXL 與 PDF 既有沉浸模式行為回歸確認無影響。

**相關佐證：**
- `design.md`「第三輪真機使用回報」項目 3
- `design.md` 第一輪「決策」#14（`_chromeVisible` 沉浸模式原始設計）

---

## Issue 14：流式 EPUB 邊距重新設計為上/下/左/右 4 個獨立欄位

**Status:** ✅ 已完成並合併回 `main`（PR #84，merge commit `871b73d`）。`BookReaderPrefs`／SQLite schema（v13→v14）／`ResolvedPreferences`／`FoliateEpubReaderView`／`ReaderSettingsSheet` 皆已依計畫拆為上/下/左/右 4 個獨立 px 欄位，`main.js` 的 `applyPreferences()` 統一依這 4 個欄位動態設定 Paginator 的 `margin-top`/`margin-bottom`/`margin-left`/`margin-right` attribute，橫排/直排皆生效，字級調整不再連帶影響左右留白。`flutter analyze` 乾淨、`flutter test` 655 個測試全數通過。

程式碼審查（review-issue-14）發現的兩項問題皆已修正：
1. Task 6 新增 4 個獨立滑桿後 `ReaderSettingsSheet` 內容變高，既有測試固定 viewport 過小導致 6 項測試失敗——已調高 `_pumpSheet()`／`reader_screen_test.dart` 的 viewport 至 `Size(800, 1600)` 解決。
2. 真機驗收發現的建置環境問題（非本 Issue 程式碼缺陷）：使用者本機一份不完整/過期的 `flutter build apk --debug` 建置產物（缺少部分 ABI 的完整 `libflutter.so`）導致 App 卡在系統啟動畫面；改用乾淨重新建置（`flutter clean` 後重建）即正常，已於裝置 `3CEF42ECD491687` 上以升級/全新安裝兩種路徑重複驗證。

真機驗收（`3CEF42ECD491687`）額外發現並修正一項邊界案例：左/右邊界滑桿調到 0 時仍殘留約一顆 FAB 大小的空白，根因是 `main.js` 原本用 `body { padding-left/right }` CSS 疊加左右留白，但 Paginator 自身內建的 `--_margin-left`/`--_margin-right` 預設值（48px）從未被觸碰；改為直接比照 `margin-top`/`margin-bottom` 既有作法，把值送進 Paginator 原生的 `margin-left`/`margin-right` attribute，徹底取代內建 48px 預設。使用者確認浮動按鈕（FAB）疊在內容上沒關係，不需要另外保留按鈕安全邊界。

真機驗收結果（Pass）：4 個方向獨立可調、橫排模式上下邊距確實生效（不再永遠固定 48px）、字級放大後左右留白不再等比例膨脹、FXL 既有行為回歸確認無影響。

**依賴：** 無

**描述：**

見 `design.md`「第三輪真機使用回報」項目 4、ADR 0014（`docs/adr/0014-foliate-epub-independent-margins.md`）。現況：單一「邊距」滑桿（`BookReaderPrefs.pageMargins`）同時驅動兩種不相干的機制——(a) `main.js` 的 `buildOverrideCss()`（`main.js:99-100`）：`body { padding: 0 ${1.5 * prefs.pageMargins}em }`，`em` 單位隨字級等比例放大，所有排版方向皆生效；(b) `epic-18` Issue 4 引入的 `main.js` 機制（`main.js:172-211`）：直排模式下 `view.renderer.setAttribute('margin-top'/'margin-bottom', ...)`（px 單位），橫排永遠固定 `paginator.js` 內建 48px、完全不受此滑桿影響。使用者回報左右留白過多（根因是 `em` 單位隨字級放大，`epic-18` 稍早的字級診斷已將字級滑桿上限由 40 調到 80，副作用更明顯），並要求比照 `docs/prd.md`「版面控制項」原始需求，補齊上/下/左/右 4 個獨立可調欄位。

依 ADR 0014：**本 Issue 範圍僅限流式 EPUB**（`FoliateEpubReaderView`/`main.js`），不修改 `EpubReaderView`／Readium／FXL 路徑；既有 `pageMargins` 欄位保留不變、不刪除、不遷移既有值（繼續透過 `EpubReaderView.pageMargins` 傳給 Readium，供 FXL 使用；FXL 目前無 UI 寫入此欄位，形同無害保留）。

- **`BookReaderPrefs`**：新增 `final double? marginTop`、`final double? marginBottom`、`final double? marginLeft`、`final double? marginRight` 4 個欄位，`toMap`/`fromMap`/`copyWith`/`==`/`hashCode` 同步新增（比照既有 `pageMargins` 欄位新增時的既有寫法，`book_reader_prefs.dart:26/56/88/124/183/210/242/268`）。
- **`book_reader_prefs` schema migration**：目前版本 `sqlite_library_repository.dart:30` 為 `version: 13`，本 Issue 升級至 `version: 14`，新增 `if (oldVersion < 14)` 累加式 migration 分支，新增 4 個 nullable 欄位（`margin_top`/`margin_bottom`/`margin_left`/`margin_right` REAL），比照既有累加式 migration 慣例；既有 `page_margins` 欄位不受影響、不做任何遷移。
- **`ReaderSettingsSheet`**：既有單一「邊距」`_buildSliderRow`（`reader_settings_sheet.dart:224-236`，`Key('reader_settings_page_margins')`）拆為 4 個獨立滑桿：「上邊界」（`Key('reader_settings_margin_top')`）、「下邊界」（`Key('reader_settings_margin_bottom')`）、「左邊界」（`Key('reader_settings_margin_left')`）、「右邊界」（`Key('reader_settings_margin_right')`），滑桿範圍/step/預設值比照既有「邊距」滑桿（0-50，step 1，預設 15，即倍率 1.0，具體數值換算公式與是否 4 者共用同一個 `_toMultiplier(_, 15.0)` 換算基準，留待實作階段依真機視覺效果確認）。
- **`FoliateEpubReaderView`（Dart）**：新增 `marginTop`/`marginBottom`/`marginLeft`/`marginRight` 4 個 `double?` 建構參數（取代原本傳遞給流式 EPUB 路徑的 `pageMargins`，`pageMargins` 本身作為 `EpubReaderView` 建構參數的既有傳遞路徑不受影響），`_buildPreferencesMap()`／`_preferencesChanged()` 同步更新。
- **`ReaderScreen`**：`_buildNativeView()` 的 `FoliateEpubReaderView(...)` 建構呼叫新增 4 個新欄位透傳（`resolved.marginTop`/`marginBottom`/`marginLeft`/`marginRight`），`ResolvedPreferences` 同步新增對應欄位。**維持 nullable**（`double?`，比照既有 `pageMargins`／`fontSize` 等 8 個 EPUB 字型/排版欄位的既有慣例，見 `resolved_preferences.dart:18-26` 開頭註解：這批欄位 null 時整個 key 省略、交由 `main.js`／`paginator.js` 內建預設值決定，不得發明目前不存在的預設值）——**不**比照 `columnMode`/`columnSize` 的 non-nullable 例外模式（那兩者有文件明載的特殊理由）。
- **`main.js`**：
  - `buildOverrideCss()`（`main.js:99-100`）：`prefs.pageMargins` 條件式改為分別讀取 `prefs.marginLeft`/`prefs.marginRight`，各自產生 `body { padding-left: ${...}em !important; }`／`body { padding-right: ${...}em !important; }`（取代目前合併的 `padding: 0 Xem`），單位是否仍用 `em`（維持隨字級縮放的既有視覺比例關係）或改為與上下邊距一致的 `px`（避免字級再放大時左右留白又不成比例膨脹，這正是本次回報的根因）留待實作階段依真機視覺效果決定，若改用 `px` 需在計劃階段明確記錄换算公式。
  - `main.js:172-211` 的直排/橫排 margin-top/margin-bottom 邏輯：改吃 `prefs.marginTop`/`prefs.marginBottom`（取代目前的 `prefs.pageMargins`），且**移除橫排永遠固定 48px 的既有限制**——橫排模式下也依 `marginTop`/`marginBottom` 動態計算並呼叫 `setAttribute`，兩種排版方向皆一致生效（不再有「只有直排才受邊距滑桿影響」的既有不對稱行為）。

**單元測試要求：**
- `BookReaderPrefs`：4 個新欄位的 `toMap`/`fromMap` round-trip、`copyWith`、`==`/`hashCode` 測試（比照既有 `pageMargins` 欄位測試模式）。
- SQLite migration round-trip：`sqlite_library_repository_test.dart`（或對應既有測試檔）新增測試：(a) 新裝置直接以 `version: 14` 建表，4 個新欄位可讀寫；(b) 模擬既有 `version: 13` 裝置升級到 `version: 14` 後，既有資料列的 4 個新欄位為 `NULL`、既有 `page_margins` 欄位值不變（比照既有 migration 測試模式，如 Epic 18 Issue 5/6 先例）。
- `foliate_epub_reader_view_test.dart`：`marginTop`/`marginBottom`/`marginLeft`/`marginRight` 出現/不出現於 `initialPreferences` map、`didUpdateWidget` 變動時觸發 `setPreferences`。
- `reader_settings_sheet_test.dart`：4 個新 `Key`（`reader_settings_margin_top`/`_bottom`/`_left`/`_right`）皆存在、可調整、觸發 `onChanged` 帶出對應欄位；既有 `Key('reader_settings_page_margins')` 相關測試需移除或改寫（滑桿本身已拆分，不再存在單一「邊距」滑桿）。
- `reader_screen_test.dart`：4 個新欄位從 `ResolvedPreferences` 正確透傳到 `FoliateEpubReaderView`。
- `main.js` 的 `setAttribute`/CSS 覆寫呼叫無 JS 單元測試（比照 Issue 4/5/6/7/9 既有慣例），驗收依賴真機 `integration_test` 與人工視覺確認。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨、`./gradlew :app:testDebugUnitTest` 全數通過。
- 真機（`3CEF42ECD491687`）流式 EPUB 開書：分別調整「上邊界」「下邊界」「左邊界」「右邊界」4 個滑桿，確認四個方向的留白各自獨立變化、互不影響。
- 真機確認：橫排模式下調整「上邊界」「下邊界」滑桿，確認上下留白會變化（修正前橫排永遠固定 48px、不受影響的既有限制）。
- 真機確認：調大字級後，左右留白不再隨字級等比例失控膨脹（視實作階段是否改用 `px` 單位而定，若維持 `em` 單位需額外確認此驗收標準是否仍然成立，不成立則需回頭調整單位選擇）。
- FXL（`EpubReaderView`／Readium）既有 `pageMargins` 行為回歸確認無影響（本 Issue 不觸碰該路徑）。

**相關佐證：**
- `design.md`「第三輪真機使用回報」項目 4
- ADR 0005（`docs/adr/0005-epub-page-margins-single-value.md`，本 Issue 縮小其適用範圍的前置決策）
- ADR 0014（`docs/adr/0014-foliate-epub-independent-margins.md`）
- `docs/prd.md`「版面控制項」原始需求（獨立的上/下/左/右邊距滑桿）

---

## Issue 15：漫畫 EPUB 誤判為流式，新增「人工版面覆蓋」選項（取代原「FXL 雙頁置中留白」推論方向）

**Status:** ✅ 3 個 Task 皆已完成，含程式碼審查與真機驗收（分支 `feature/epic-18-issue-15-force-fxl`；commit `9c29ad3`／`2316827` Task 1-2、`97878c4` 計畫外追加修正、`f155caa`／`36a7c3d` 審查修正回填）。審查報告 `tmp/epic-18/review-issue-15.md`，結論 Ready to merge, with fixes，0 Critical／3 Important／2 Minor：Important #2（`97878c4` 未同步更新文件）與 Important #3（`97878c4` 缺少回歸測試）已修正並補齊（見 `plan-issue-15.md`「實作備註」與 `design.md` 決策 #7 後方備註、新增的 `reader_screen_test.dart` 回歸測試）；Important #1（真機驗收發現「強制 FXL 後橫向雙頁模式退化成單頁」，根因為 Readium 原生端獨立判讀書本 metadata、不受「強制 FXL」影響）判斷超出本 Issue 範圍，已另立 **Issue 16** 追蹤（見下方），不阻擋本 Issue 合併。`plans/plan-issue-15.md` Task 3（真機驗收）Step 1-5 全數 Pass，待人類確認後合併。

**依賴：** 無

**背景／根因變更說明：**

本條目原始標題為「FXL 橫屏雙頁瀏覽置中留白（左右兩頁中間有間隙）」，2026-07-29 於 `epic-19-shelf-reading-enhance` Issue 1 程式碼審查時意外拆出，當時僅有「初步判斷」（見下方「相關佐證」的舊審查報告），尚未進入正式 Discovery。使用者後續實際使用中確認：**部分書檔本質上是漫畫（理應為固定版面 FXL），但「引擎分派判斷」（見 `CONTEXT.md`）誤判為流式 EPUB**，導致改走 `foliate-js` 路徑後渲染異常——這才是本次要處理的根因，**取代**原始「雙頁置中留白」的推論方向。原「中縫空白／`applyFxlFitScale()`」調查線索（`EpubReaderView.kt`「【中縫空白修正，實驗性】」區塊）予以擱置，若未來真的有人重現雙頁置中留白症狀，再另行拆出新 Issue 調查，不在本次範圍內延續。

**引擎分派判斷機制**（見 `CONTEXT.md`「引擎分派判斷」詞條）：EPUB 該用 Readium（FXL）或 `foliate-js`（流式）開書，取決於開書前快取在 `Book.isFixedLayout`（`app/lib/library/models/book.dart:50`，nullable bool）的判斷結果，來源為 `extractMetadata`（匯入時）或 `detectAndCacheEpubLayout`/`detectEpubLayout`（既有書籍首次開書時補判斷）這兩個原生 channel（讀取 EPUB OPF `rendition:layout` 屬性）。少數漫畫 EPUB 因來源檔案 metadata 不完整/不規範，被誤判為流式。**本次範圍僅新增人工救濟手段，不調查/修正這個判斷邏輯本身**（經 grilling 確認的刻意範圍縮小，見 `design.md`）。

**描述：**

新增「人工版面覆蓋」（見 `CONTEXT.md`）功能，讓使用者可對誤判的書籍手動修正：

- **資料層（零新增）**：不新增欄位、不需要 SQLite migration。
  - 「強制 FXL」：對選取的每本 EPUB 呼叫既有 `LibraryRepository.updateBook(book.copyWith(isFixedLayout: true))`。
  - 「恢復自動判斷」：對選取的每本 EPUB 重新呼叫既有 `LibraryRepository.detectAndCacheEpubLayout(book.id, book.filePath)`（本來就會重新偵測並覆寫資料庫，語意上等同「回到系統原始判斷」）。
- **`LibraryScreen`**：不新增長按手勢或三點選單，沿用現有多選模式（`_enterSelectionMode`/`_selectedBookIds`），在既有選取工具列（`_buildSelectionAppBar()`，「移動到分類」旁）新增兩顆獨立按鈕：
  - `Key('library_force_fxl_button')`：「強制 FXL」
  - `Key('library_restore_auto_layout_button')`：「恢復自動判斷」
  - 兩者批次套用於 `_selectedBookIds` 中所有 `format == BookFileFormat.epub` 的書籍；選取集合中若含 PDF/TXT，自動跳過、不報錯（比照既有「移動到分類」「刪除」按鈕：選取模式下永遠顯示，不因選取內容而隱藏/停用）。
  - 點擊後**不**彈確認對話框，直接執行（比照 `_moveSelectedBooksToGroup()` 而非 `_confirmDeleteBooks()`）：立即 `_exitSelectionMode()` → 逐筆呼叫對應 repository 方法 → `_loadBooks()` 重新整理，**不**額外顯示 SnackBar（比照 `_moveSelectedBooksToGroup()` 既有模式）。
  - 書架封面/列表**不**新增視覺標記（badge）表示「已人工覆蓋」（經 grilling 確認的刻意精簡）。
- **生效時機**：`ReaderScreen._resolveEpubEngineDispatch()`（`reader_screen.dart:291-309`）本來就是每次開書時才解析引擎，下次從書架開啟該書時自然套用新值，**不需要**改動 `ReaderScreen`/`FoliateEpubReaderView`/`EpubReaderView`。

**單元測試要求：**
- `library_screen_test.dart`：
  - 進入多選模式後，`Key('library_force_fxl_button')`／`Key('library_restore_auto_layout_button')` 皆存在且可點擊。
  - 選取純 EPUB 書籍後點擊「強制 FXL」：對應 `repository.updateBook` 被呼叫、傳入的 `Book.isFixedLayout == true`；點擊後 `_inSelectionMode` 變為 `false`（沿用「移動到分類」既有斷言模式）。
  - 選取純 EPUB 書籍後點擊「恢復自動判斷」：對應 `repository.detectAndCacheEpubLayout(bookId, filePath)` 被呼叫。
  - 選取集合同時包含 EPUB 與 PDF/TXT：點擊任一按鈕後，只有 EPUB 書籍觸發對應 repository 呼叫，非 EPUB 書籍不觸發任何呼叫、不拋錯。
  - 兩顆按鈕在選取模式下即使選取集合全為非 EPUB，仍然顯示（不隱藏/不停用）。

**驗收標準：**
- 上述測試皆通過、`flutter analyze` 乾淨。
- 真機（`3CEF42ECD491687`）以一本已知被誤判為流式的漫畫 EPUB 驗證：於書架多選該書、點擊「強制 FXL」後重新開啟，確認改用 Readium（FXL）路徑渲染、不再出現流式引擎的渲染異常。
- 真機確認：點擊「恢復自動判斷」後重新開啟同一本書，確認 `Book.isFixedLayout` 回到系統原始判斷值（與該書從未被覆蓋過時一致）。
- 真機確認：選取集合混雜 EPUB 與 PDF/TXT 時，兩顆按鈕仍可點擊，僅 EPUB 書籍受影響、PDF/TXT 不受影響。

**相關佐證：**
- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 15 根因重新診斷與人工版面覆蓋功能」（本次 `/grill-with-docs` Discovery 完整決策記錄）
- `CONTEXT.md`「固定版面（FXL）」「引擎分派判斷」「人工版面覆蓋」詞彙定義
- `app/lib/library/models/book.dart:41-50`（`Book.isFixedLayout` 既有註解）
- `app/lib/screens/reader_screen.dart:282-309`（`_resolveEpubEngineDispatch()`）
- `app/lib/library/sqlite_library_repository.dart:449-462`（`detectAndCacheEpubLayout()`）
- （舊）`epic-19-shelf-reading-enhance` Issue 1 程式碼審查報告「附錄：FXL 雙頁置中問題初步判斷」（2026-07-29；原始發現來源，根因推論已被本次取代，僅保留歷史脈絡）

---

## Issue 16：強制 FXL 後，橫向雙頁模式退化成單頁（Readium 原生端獨立判讀書本 metadata，不受人工覆蓋影響）

**Status:** 已由 Issue 19 完整修復並合併（2026-07-30）。Issue 19 透過 `Publication.Builder` 重建 `effectivePublication` 強制 `metadata.layout = Layout.FIXED`，解決了 Readium 原生端獨立判讀導致的雙頁退化問題。

**依賴：** 無（獨立於 Issue 15，Issue 15 的「強制 FXL」核心交付物——引擎確實從 `FoliateEpubReaderView` 切換到 `EpubReaderView`——已確認正常運作，不受本 Issue 影響，故不阻擋 Issue 15 合併）。

**描述：**

使用者對一本被「引擎分派判斷」誤判為流式的漫畫 EPUB 點擊「強制 FXL」（見 Issue 15）後，重新開書確實改走 `EpubReaderView`（Readium／FXL）路徑，但裝置橫向且雙頁模式（`DualPageMode`）開啟時，畫面仍只顯示一頁（固定在左邊），翻頁行為也是一頁一頁換，而非兩頁一組（spread）切換——雙頁功能形同虛設。

**根因（已於 Issue 15 程式碼審查以靜態分析確認並經 2026-07-30 grilling session 補充查證，見 `tmp/epic-18/review-issue-15.md` Important #1 與 `design.md`「Issue 16／17 修復方向 Discovery」）：**

`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` 有**三處**（審查報告原本只發現兩處，grilling 階段補上第 3 處）**各自獨立**讀取 `publication?.metadata?.layout == Layout.FIXED` 來判斷書本是否真的是 FXL，完全不知道 Flutter 端「強制 FXL」這個人工決定：

- `EpubReaderView.kt:501`（`applyFxlFitScale()`，雙頁 spread 位置/縮放計算的**唯一**函式，`docs/archive/2026-07-14-epic-16-dual-page` 核心邏輯）：`if (!isFixedLayout) { removeFxlLayoutListener(); return }`——書本被 Readium 自己判定為非 FXL 時整段短路跳過，spread 計算完全不執行。
- `EpubReaderView.kt:998`（決定是否註冊原生端 tap 熱區監聽器，`epic-7-interaction` Issue 6，僅流式路徑用）：若「強制 FXL」的書被 Readium 判定非 FXL，會同時註冊原生端 tap 監聽器，與 Dart 端已疊上的 FXL 專屬 9 宮格 `GestureDetector`（`epic-7-interaction` Issue 5）同時作用，可能造成雙重輸入處理衝突。
- `EpubReaderView.kt:1199`（回報給 Dart 端 `onLayoutResolved` 的 payload 建構處）：同樣獨立讀取，驅動 `app/lib/reader/epub_reader_view.dart:326`（`EpubLayoutInfo.isFixedLayout`）。

**更根本的不確定性**（grilling 階段查證）：上述 3 個檢查點只是本專案自己的 bookkeeping，真正決定 WebView 渲染模式的是 Readium 官方元件 `EpubNavigatorFragment`（非本專案程式碼）。查證 `EpubNavigatorFragment.Configuration`（`EpubReaderView.kt:819-853`）**沒有任何欄位可以覆寫**它自己對 `publication.metadata.layout` 的獨立判讀。也就是說：即使把本專案自己的 3 個檢查點都改成信任「強制 FXL」，`EpubNavigatorFragment` 本身是否會跟著改變渲染模式**無法從程式碼確認**，見 `CONTEXT.md`「Readium 內部版面渲染決策」新詞條。

「強制 FXL」（`Book.isFixedLayout`，見 `CONTEXT.md`「引擎分派判斷」）在設計上只能改變**開書前該用哪個 widget 開書**，無法改變 Readium 開書後對這本書*自身* metadata 的獨立判讀——而這本書當初會被誤判為流式，很可能正是因為同一份不規範的 OPF `rendition:layout` metadata，讓 Readium 官方解析器（`DefaultPublicationParser`）也判斷不出 FXL。也就是說：「強制 FXL」對「metadata 不完整但 Readium 官方解析器仍判斷得出來」的書籍能完全救濟，但對「metadata 損壞到連 Readium 官方解析器都判斷不出 FXL」的書籍**先天無法完全救濟**。

**額外發現**：Issue 15 追加修正 `commit 97878c4` 只保護了 `ReaderScreen._isFixedLayout`，`EpubReaderView` widget 自己內部同名欄位（`epub_reader_view.dart:326`，驅動 FXL 換頁熱區疊加層顯示，見 `CONTEXT.md`「FXL 換頁熱區（暫代版）」）未受保護，`setState(() => _isFixedLayout = info.isFixedLayout);` 仍無條件套用 native 回報值——不確定是否已造成使用者觀察到「強制 FXL 書籍點擊左右熱區無反應」的症狀，待後續 Spike／實作階段一併確認。

**修復方向（已於 2026-07-30 grilling session 定案架構原則，執行順序見下方；不含旗標傳遞管線的完整實作細節，那屬於 Issue 17 GO 之後的新工單範圍）：**

- 3 個檢查點改為讀取單一 class 層級的典範值（例如 `effectiveIsFixedLayout`），一次計算、全部引用，取代各自獨立重算——避免像 Issue 15 審查報告建議的「各自改 OR 條件」那樣容易漏改（審查報告自己就漏了第 3 個檢查點）。
- 「強制 FXL」旗標傳遞方式：新增為 `EpubReaderView.kt` `openBook()` 的專屬參數（非塞進既有 `initialPreferences` Map）——語意上是「開書前已確定、不會在閱讀中途改變的書本事實」，不是使用者可隨時調整的版面偏好。
- **因核心假設（`EpubNavigatorFragment` 是否會跟著改變渲染模式）無法從程式碼確認，先做 Spike 驗證，見 Issue 17。**

**建議後續：**
- Issue 17（Spike）GO 之後，回本 Issue 或新增工單撰寫 `plans/plan-issue-16.md` 承接完整實作（含完整 Dart→Kotlin 旗標傳遞管線、`epub_reader_view.dart:326` guard 同步修正上方「額外發現」）。
- Issue 17 NO-GO 則回頭評估其餘替代方案（例如接受此限制、或在 UI 上提示使用者「強制 FXL 對此類書籍的雙頁排版效果有限」），本 Issue 屆時可能改為 `wontfix` 或降級為文件/UX 提示層級的小工單。

**相關佐證：**
- `tmp/epic-18/review-issue-15.md` Important #1（原始根因推導與程式碼位置引用）
- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 16／17 修復方向 Discovery」（2026-07-30 grilling 完整決策記錄，含本條目查證發現的完整脈絡）
- `docs/epics/epic-18-reader-device-qa/plans/plan-issue-15.md`「實作備註」
- `docs/archive/2026-07-14-epic-16-dual-page/`（已歸檔的雙頁模式 Epic，`DualPageMode`／`applyFxlFitScale()` 原始設計）
- `CONTEXT.md`「固定版面（FXL）」「引擎分派判斷」「Readium 內部版面渲染決策」「FXL 換頁熱區（暫代版）」詞彙定義
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:501,819-853,998,1199`

---

## Issue 17：Spike——強制 FXL 覆蓋本專案檢查點後，`EpubNavigatorFragment` 是否真的會渲染成 FXL

**Status:** ✅ 已完成（`spike/epic-18-issue-17-fxl-metadata-override` 分支）。結論 **NO-GO**——硬編碼 3 個 `isFixedLayout` 檢查點後，`EpubNavigatorFragment` 仍以單頁模式渲染，確認其渲染模式由 Readium 官方元件獨立判讀 publication metadata 決定，本專案無法透過覆寫自身檢查點來影響。完整報告見 `reviews/spike-issue16-fxl-metadata-override.md`。

**依賴：** 無（獨立於 Issue 15／16，起始工單，可立即開始）。

**背景：**

見 Issue 16「更根本的不確定性」段落。`EpubReaderView.kt` 有 3 個各自獨立讀取 `publication.metadata.layout == Layout.FIXED` 的檢查點（`:501`／`:998`／`:1199`），但真正決定 WebView 渲染模式（FXL 左右並排 vs. reflowable 單欄連續捲動）的是 Readium 官方元件 `EpubNavigatorFragment`（`readium-kotlin-toolkit`，非本專案程式碼），其 `Configuration`（`EpubReaderView.kt:819-853`）沒有任何欄位可以覆寫它自己對書本 metadata 的獨立判讀。即使把本專案自己的 3 個檢查點都改成信任「強制 FXL」，`EpubNavigatorFragment` 本身是否會跟著改變渲染模式**無法從程式碼確認**，需要真機驗證這個核心假設是否成立，才能決定 Issue 16 的完整修復方向值不值得投入（比照 ADR 0011／Issue 8 的既有 Spike-first 慣例）。

**驗證範圍：**

1. **主要驗證**：在 `EpubReaderView.kt` 的 3 個檢查點（`:501`／`:998`／`:1199`）**硬編碼** `isFixedLayout`／`effectiveIsFixedLayout` 為 `true`（或加一個臨時 debug flag），模擬「強制 FXL」旗標已生效的情境，**不需要**撰寫完整的 Dart→Kotlin 旗標傳遞管線（不新增 `openBook()` 參數、不新增 `EpubReaderView` widget 建構參數）。
2. 用 Issue 15 真機驗收時已知會被誤判為流式的同一本漫畫 EPUB，於裝置 `3CEF42ECD491687` 上：先重現「強制 FXL」後橫向雙頁模式仍退化成單頁的現況，再套用上述硬編碼重新安裝驗證。
3. **附帶驗證（不影響 GO/NO-GO，僅記錄）**：確認 Issue 16 提到的 `EpubReaderView.kt:998` tap 熱區風險——套用硬編碼後，原生端 tap 熱區監聽器是否確實與 Dart 端 9 宮格 `GestureDetector` 同時作用，若是，記錄具體症狀（例如點擊翻頁是否觸發兩次、或觀察到的其他異常行為）。

**明確不在本 Issue 範圍**：完整的 Dart→Kotlin 旗標傳遞管線實作（`openBook()` 新增專屬參數、`EpubReaderView.dart` 新增建構參數、3 個檢查點改為讀取單一典範值 `effectiveIsFixedLayout`）——這些留待 GO 之後的新工單（見下方「GO/NO-GO 決策路徑」）。

**GO/NO-GO 決策路徑：**
- **GO**（硬編碼後，橫向雙頁模式下該書真的顯示兩頁並排且翻頁行為正常，非兩個單頁正常顯示、非頁碼順序錯誤）：於 `design.md` 記錄 Spike 結果，新增工單承接完整實作（比照 Issue 8→10 模式）。
- **NO-GO**（渲染結果仍是單頁、當機、或畫面損壞）：記錄具體失敗證據於 `reviews/`，`design.md` 補上「已評估並否決」的結論，回頭評估 Issue 16 的其餘替代方案（例如接受此限制、或在 UI 上提示使用者「強制 FXL 對此類書籍的雙頁排版效果有限」）。

**單元測試要求：** 無（研究/驗證性質，比照 `epic-17-epub-render-migration` Issue 1、本 Epic Issue 8 先例）。過程中產生的硬編碼與素材（截圖、logcat）驗證後需清理，不進版控（放 `tmp/`，已 gitignore）；硬編碼本身不進 `main`，僅真機臨時 build。

**驗收標準：**
- 真機（`3CEF42ECD491687`）以已知誤判書籍驗證，明確記錄 GO/NO-GO 判定與依據（截圖或 log 佐證）。
- 附帶的 tap 熱區風險驗證結果（是否重現雙重輸入處理），不論 GO/NO-GO 皆需記錄。
- 依結果更新 `design.md` 對應段落與 `issues.md` Issue 16 狀態。

**相關佐證：**
- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 16／17 修復方向 Discovery」（本次 `/grill-with-docs` Discovery 完整決策記錄）
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 16（根因與修復方向背景）
- `docs/adr/0011-epub-reflowable-migrate-to-foliate-js.md`（Spike-first 既有慣例）
- `issues.md` Issue 8（本 Epic 既有 Spike 先例，GO/NO-GO 決策路徑格式參考）
- `CONTEXT.md`「Readium 內部版面渲染決策」詞彙定義
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:501,819-853,998,1199`

---

## Issue 18：Spike v2——重建 `Publication` 物件覆寫 `metadata.layout`，驗證是否讓 `EpubNavigatorFragment` 渲染成 FXL

**Status:** ✅ Spike 完成（GO）。2026-07-30 真機驗證確認：`Publication.Builder` 重建 `metadata.layout = Layout.FIXED` 後，`EpubNavigatorFragment` 正確渲染成雙頁 FXL 並排。翻頁正常、熱區翻頁正常。Service Loss 風險：進度條不可見、頁數呈現模式異常（疑似因 `ServicesBuilder()` 空物件導致）。完整報告見 `reviews/spike-issue18-publication-builder-override.md`。待人類決定是否進入正式實作（含 Dart→Kotlin 旗標傳遞管線）。

**依賴：** 無（獨立於 Issue 15／16／17，Issue 17 已確認 NO-GO 的路徑〔覆寫本專案自己的 3 個 bookkeeping 檢查點〕不再嘗試，本 Issue 是全新方向）。

**背景：**

Issue 17 Spike 確認：覆寫 `EpubReaderView.kt` 自己的 3 個 `isFixedLayout` 檢查點對 `EpubNavigatorFragment` 的實際渲染行為無效（NO-GO）。使用者提供的外部分析報告提出新方向：**不改我們自己的檢查點，改覆寫傳給 `EpubNavigatorFactory` 的 `Publication` 物件本身**。

**根因查證（已對照 Readium `kotlin-toolkit` 3.3.0 官方原始碼逐一確認，非僅閱讀外部報告推論）：**

- `EpubNavigatorFactory`（`readium-navigator` 3.3.0）建構時計算 `private val layout = publication.metadata.layout ?: Layout.REFLOWABLE`，並把**同一個** `publication` 物件參照直接傳給 `EpubNavigatorFragment`。
- `EpubNavigatorFragment` 內部在多個方法（`onCreateView()`／`resetResourcePagerAdapter()`／`goForward()`/`goBackward()`／`firstVisibleElementLocator()`）各自重新讀取 `publication.metadata.layout` 決定渲染/分頁/導航行為——這完全解釋了 Issue 17 為何 NO-GO：我們自己的 3 個檢查點根本不是 Readium 官方元件實際讀取的東西。
- `EpubNavigatorFragment.Configuration`（本專案唯一能設定的組態介面）**確認沒有**任何欄位可以覆寫渲染模式判讀——與 Issue 16／17 的既有結論一致。

**外部分析報告的技術主張逐一查證結果：**

| 主張 | 查證結果 |
|---|---|
| 根因：`EpubNavigatorFactory`/`EpubNavigatorFragment` 獨立讀取 `publication.metadata.layout`，本專案自己的檢查點無效 | ✅ 正確，已對照原始碼確認 |
| 提出的修復程式碼 `openedPublication.copy(manifest = ...)` | ❌ **編譯不過**——`Publication`（3.3.0）**不是** Kotlin `data class`（一般 `class`），沒有 `.copy()` 方法：`public class Publication(public val manifest: Manifest, public val container: Container<Resource> = EmptyContainer(), private val servicesBuilder: ServicesBuilder = ServicesBuilder())`。`Manifest` 才是 `data class`（`.copy(metadata = ...)` 沒問題），問題出在外層對 `Publication` 呼叫 `.copy()`。 |
| 「複製並覆寫」策略本身可行 | ⚠️ **需要修正做法＋有未驗證風險**——Readium 提供官方 `Publication.Builder(manifest, container, servicesBuilder)` 可重建 `Publication`，但原始 `openedPublication` 的 `servicesBuilder` 是 **private** 建構子參數，本專案程式碼**無法讀取/複用**原本 `DefaultPublicationParser`/`EpubParser` 真正配置的那份 `servicesBuilder`，重建時只能傳一個全新的預設 `ServicesBuilder()`——可能遺失 EPUB 解析器額外註冊的服務。本專案已確認依賴 `openedPublication.services.positions()`（`computeTotalCharacterCountInBackground()`，見 `EpubReaderView.kt`），這正是這類服務的實際使用案例，遺失後果**查不出來，只能真機測**。書本內容本身的渲染不受影響（`container` 不是 private，可原樣複用）。 |

**額外查證（外部報告未提及）**：`EpubReaderView.kt:998` 那個 tap 熱區檢查點讀的是 `attachNavigator()` 的**區域變數** `openedPublication`（非 class 欄位 `publication`），跟 `:501`／`:1199` 讀的 class 欄位是不同參照——正確做法需要讓這 3 處都改讀同一個 `effectivePublication`（比照 Issue 16 決策「單一典範值」），不能只改 class 欄位就以為 3 處都覆蓋到。

**修復方向（本 Issue 只做最小範圍 Spike 驗證，不做完整實作）：**

```kotlin
val effectivePublication = if (isForceFxl) {
    Publication.Builder(
        manifest = openedPublication.manifest.copy(
            metadata = openedPublication.metadata.copy(layout = Layout.FIXED),
        ),
        container = openedPublication.container,
        // 注意：無法取得原始 servicesBuilder，此處只能用預設值——這正是本 Spike
        // 要驗證「是否造成可觀察功能退化」的地方。
    ).build()
} else {
    openedPublication
}
```

**驗證範圍：**

1. **主要驗證**：套用上述（或等效）程式碼，`publication`／`openedPublication` 三處檢查點皆改讀 `effectivePublication`，真機驗證橫向雙頁模式是否真的顯示兩頁並排、翻頁行為是否正常。
2. **服務遺失風險驗證（本 Issue 新增，外部報告未提及）**：對已套用「強制 FXL」且使用 `effectivePublication` 的書籍，確認既有依賴 Readium services 的功能是否仍正常運作，至少涵蓋：全書字元數統計（`computeTotalCharacterCountInBackground`）是否仍正確計算、目錄（TOC）是否仍正常載入、劃線/備註（Decorator）功能是否仍正常。
3. **附帶驗證（沿用 Issue 16 已知風險，不影響 GO/NO-GO）**：`:998` tap 熱區監聽器改為讀取 `effectivePublication` 後，是否仍與 Dart 端 9 宮格 `GestureDetector` 同時作用。

**明確不在本 Issue 範圍**：完整的 Dart→Kotlin `isForceFxl` 旗標傳遞管線（`openBook()` 新增專屬參數、`EpubReaderView.dart` 新增建構參數）——本 Spike 比照 Issue 17 慣例，直接在 Kotlin 端硬編碼 `isForceFxl = true` 模擬，不寫管線。

**GO/NO-GO 決策路徑：**
- **GO**（雙頁排版正常顯示，且服務遺失風險驗證未發現功能退化，或發現的退化範圍可接受）：於 `design.md` 記錄結果，新增工單承接完整實作（含 Dart→Kotlin 旗標傳遞管線）。
- **NO-GO**（雙頁排版仍不正常，或發現服務遺失造成無法接受的功能退化如字元數統計失效）：記錄具體證據，回頭評估 Issue 16 其餘替代方案（接受限制／UI 提示）。
- **部分 GO**（雙頁排版正常但服務遺失有明確、範圍有限的退化）：記錄退化清單，交由人類決定是否可接受、或需要額外方案補救遺失的服務（例如手動註冊等效服務到 `Publication.Builder`）。

**單元測試要求：** 無（研究/驗證性質，比照 Issue 8／17 先例）。

**驗收標準：**
- 真機（`3CEF42ECD491687`）以已知誤判書籍驗證，明確記錄 GO/NO-GO 判定與依據。
- 服務遺失風險驗證結果（字元數統計／TOC／劃線備註）明確記錄，不論結果為何。
- 依結果更新 `design.md`／`issues.md` 對應狀態。

**相關佐證：**
- `tmp/epic-18/issue-16-solution-analysis.md`（外部分析報告，本 Issue 根因診斷部分已查證屬實）
- `docs/epics/epic-18-reader-device-qa/reviews/spike-issue16-fxl-metadata-override.md`（Issue 17 NO-GO 報告，本 Issue 承接的前一次失敗嘗試）
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 16／17
- Readium `kotlin-toolkit` 3.3.0 官方原始碼（`readium/shared/.../publication/Publication.kt`／`Manifest.kt`；`readium/navigator/.../epub/EpubNavigatorFactory.kt`／`EpubNavigatorFragment.kt`）
- `CONTEXT.md`「Readium 內部版面渲染決策」詞彙定義
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:501,891-924,998,1199`

---

## Issue 19：正式實作——「強制 FXL」書籍橫向雙頁排版修復（`Publication.Builder` 重建 `metadata.layout`）

**Status:** 已完成並合併回 `main`（2026-07-30，PR #90：https://git.jigong.org/huthief/elinkBook/pulls/90，分支 `feature/epic-18-issue-19-fxl-metadata-override`）。程式碼審查通過（`tmp/epic-18/review-plan-issue-19.md`，Important #1/#2 已修正）；`flutter test` 704/704 全數通過、`flutter analyze` 無警告、`flutter build apk --debug` 建置成功；真機驗證通過——橫向雙頁模式正確顯示兩頁並排，翻頁正常，tap 熱區無雙重觸發。Slider 進度條不可用，經複核確認為 FXL（Readium）路徑本身既有限制、與本次改動無關，已另立 Issue 20 獨立排查，不影響本 Issue 驗收。

**依賴：** Issue 15（「強制 FXL」人工覆蓋機制，本 Issue 修復其已知副作用）、Issue 18（Spike 驗證 GO，本 Issue 的技術方向依據）、ADR 0016（本 Issue 的架構決策紀錄）。

**背景：**

Issue 16 確認「強制 FXL」後橫向雙頁模式退化成單頁的根因；Issue 17（覆寫本專案自身 3 個檢查點）驗證 NO-GO；Issue 18（改用 `Publication.Builder` 重建整個 `Publication` 物件、強制 `metadata.layout = Layout.FIXED`）驗證 **GO**——`EpubNavigatorFragment` 會正確渲染成雙頁並排，翻頁與熱區翻頁皆正常。本 Issue 將 Issue 18 的硬編碼 Spike 收斂為正式、可維護的實作。

**範圍（2026-07-30 grilling 定案，見 ADR 0016）：**

1. **不做 Dart→Kotlin 旗標傳遞管線**——`EpubReaderView`（FXL 路徑）這個 widget 本來就只在 `Book.isFixedLayout == true` 時才會被建構（見 `CONTEXT.md`「引擎分派判斷」，涵蓋使用者強制／自動判斷／既有退回預設值三種情況），所以 Kotlin 端 `attachNavigator()` 只要在執行期發現 `openedPublication.metadata.layout != Layout.FIXED`，就已完整等同於「上游已決定這本書要走 FXL，但 Readium 官方解析器不同意」，不需要從 Dart 額外傳一個旗標。這**不影響**使用者透過「強制 FXL」按鈕做出的手動決定——那個決定完整保留在上游 `Book.isFixedLayout`／Dart 端 widget 分派這一層，本次只是補齊「決定之後，Readium 內部渲染也真的照做」這最後一哩路。
2. **Kotlin 端**：於 `attachNavigator()` 檢查 `openedPublication.metadata.layout != Layout.FIXED`，若成立則用 `Publication.Builder` 重建 `effectivePublication`（比照 Issue 18 Spike 已驗證的程式碼結構與隔離設計——class 欄位 `publication` 維持指向原始物件，`effectivePublication` 只供 FXL 判斷檢查點使用），`applyFxlFitScale()`（`:501`）／tap 熱區監聽器註冊（`:998`）／`reportLayoutResolved()`（`:1199`）三處 FXL 判斷檢查點統一改讀 `effectivePublication`。
3. **`epub_reader_view.dart:326` 防禦性修法**：修復後 `reportLayoutResolved()` 回報給 Dart 端的 `isFixedLayout` 理論上恆為 `true`（因為判斷結果不對時已在 Kotlin 端強制覆寫），此處的既有 bug（`setState(() => _isFixedLayout = info.isFixedLayout)` 無條件套用 native 回報值）在正常路徑下不會再被觸發，但仍需比照 Issue 15 `commit 97878c4` 對 `ReaderScreen._isFixedLayout` 的既有保護模式補上防護，作為 `Publication.Builder` 重建失敗等邊界情況的防禦層。

**Service Loss 因應（人類已決定範圍）：** 本 Issue **不**處理進度條/頁數呈現異常本身，該現象另開 **Issue 20** 獨立排查（不確定是否為本 Issue 改動所導致，或本來就是既有缺陷）。本 Issue 僅需確保：套用 `Publication.Builder` 重建後，不引入*超出 Issue 20 已知範圍*的新退化——沿用 Issue 18 Spike 已驗證的驗證項目（頁面渲染／Slider 進度跳轉／`onLocatorChanged` progression 觀察／TOC 跳轉）重新於正式實作後真機複驗。

**單元測試要求：** Kotlin 原生渲染邏輯無法用 `flutter test` 覆蓋（見 `CLAUDE.md`「兩層測試架構」），沿用既有 `EpubReaderView.kt` 慣例僅真機驗證；`epub_reader_view.dart:326` 的保護邏輯需補 Dart 端 widget test（比照 `reader_screen_test.dart` 中 Issue 15 `commit 97878c4` 回歸測試的既有寫法）；`integration_test/` 需真機驗證橫向雙頁排版正常顯示。

**驗收標準：**
- 已知被誤判為流式的漫畫 EPUB，套用「強制 FXL」後，橫向雙頁模式正確顯示兩頁並排，翻頁行為正常（`3CEF42ECD491687` 真機驗證）。
- `epub_reader_view.dart:326` 的 `_isFixedLayout` 不再被 native 異步回報覆蓋，回歸測試通過。
- Issue 18 Spike 已驗證的 4 項服務驗證（頁面渲染／Slider 跳轉／`onLocatorChanged` progression／TOC 跳轉）於正式實作後真機重新驗證仍通過。
- `flutter analyze` 無新增警告，既有測試全數通過。

**相關佐證：**
- `docs/adr/0016-fxl-metadata-override-via-publication-builder.md`（本 Issue 的架構決策 ADR）
- `docs/epics/epic-18-reader-device-qa/reviews/spike-issue18-publication-builder-override.md`（Issue 18 Spike 報告，本 Issue 承接其「建議下一步」）
- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 16／17 修復方向 Discovery」「Issue 18 Spike 結論」「Issue 19 Discovery」
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 15（`commit 97878c4` 既有保護模式參考）／16／17／18
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:164,501,911-924,998,1199`
- `app/lib/reader/epub_reader_view.dart:326`

---

## Issue 20：FXL 書籍新增進度條／頁尾 FAB（比照流式 EPUB，根因已確認為 UI 層從未接線）

**Status:** 🚫 不再執行（2026-07-31）。`epic-20-fxl-foliate-migration` Issue 1 Spike 真機以真實問題書籍驗證 **GO**（`docs/epics/epic-20-fxl-foliate-migration/reviews/spike-issue1-fxl-foliate.md`）——FXL 確定整個遷移到 `foliate-js`，本 Issue 針對 Readium 路徑（`EpubReaderView.kt`）的進度條/頁尾 UI 修補工作不再需要，正式實作方向改在 `epic-20` Architecting 階段承接。

**依賴：** 無（獨立於 Issue 21，UI 接線與資料來源皆已查證清楚，可直接進 Planning）。

**根因（2026-07-30 grilling 查證，取代先前「Readium 內部限制」的推測）**：`reader_screen.dart` 目前有兩組完全獨立的浮動按鈕群組——流式 EPUB（`_dispatchedIsFixedLayout == false`）與 FXL（`_isFixedLayout`）。**FXL 那組只有 4 顆按鈕（返回／版面設定／書籤／筆記），從未接上對應流式 EPUB `reader_foliate_progress_button`「跳頁」的按鈕**，也沒有對應 `_buildFoliateProgressText()` 的常駐進度文字。另外，舊有的 `_buildEpubFooter()`（in-flow 頁尾、依全書字元數估算頁碼）雖然還在程式碼中，但其顯示條件 `!_isFixedLayout` 是 ADR 0011 把流式 EPUB 遷移到 `foliate-js` 之前的殘留判斷式——現在 FXL 書籍一律 `_isFixedLayout == true`，此條件恆假，是打不到的死碼。**結論：「進度條不可見」的根因是 UI 層在 FXL 路徑上從未接線，不是 Readium 官方元件的限制**，先前 Issue 18/19 Spike 觀察到的異常本身仍有效（真的看不到進度條），但根因推測方向已修正。

**修復方向（2026-07-30 grilling 定案）：**
1. **比照流式 EPUB 的 FAB＋Bottom Sheet 模式**：於 FXL 浮動按鈕群組新增一顆對應 `reader_foliate_progress_button` 的「跳頁」按鈕（`reader_fixed_layout_progress_button`，置於下一個可用欄位 `top:184, right:16`），點擊開啟含 `ReaderFooter`（既有共用元件，PDF／流式 EPUB／舊 `_buildEpubFooter` 皆已使用）的 Bottom Sheet。
2. **頁尾常駐顯示由閱讀設定 `showFooter` 控制**：比照流式 EPUB `_buildFoliateProgressText()` 的既有 gating 模式（`(_resolved?.showFooter ?? true) && _chromeVisible`）。
3. **頁碼資料來源改用 `readingOrder` 索引，不用字元數估算**——**這是本次 grilling 的關鍵修正**：人類指出 FXL 書籍（漫畫）內文字元數趨近於 0，`EpubPageEstimator` 的字元估算模型（`_buildEpubFooter()` 原本的作法）完全不適用；改為查證發現 `readingOrder`（`EpubReaderView.kt:1103` 已在用）是 `Publication` manifest 的基本屬性，不經過 `positions()`／`servicesBuilder` 那套有疑慮的服務層，`readingOrder.size` 本身就是精確、可靠的總頁數（FXL 每個 `readingOrder` 項目對應一頁圖片），完全不需要估算；目前頁用 `Locator.href` 對照 `readingOrder` 索引位置取得。需要在 Kotlin 端新增這個索引查找邏輯（不需要新的 Dart→Kotlin 旗標），並透過既有 `onLocatorChanged`／或擴充其 payload 回報給 Dart 端。

**明確不在本 Issue 範圍：**
- Issue 21：封面獨立顯示／頁碼配對模式（`1,3-2,5-4`），為獨立的技術不確定性問題，需要先做 Spike。
- Issue 22：FXL 缺少目錄（TOC）按鈕，順帶發現但範圍不同，另立追蹤。

**單元測試要求：** Dart 端 widget test 涵蓋新按鈕的顯示條件（`_isFixedLayout && _chromeVisible`）與 Bottom Sheet 開啟行為，比照既有 `reader_foliate_progress_button` 測試模式；Kotlin 端 `readingOrder` 索引邏輯無法用 `flutter test` 覆蓋，真機驗證（比照既有兩層測試架構慣例）。

**驗收標準：**
- FXL 書籍點擊新「跳頁」按鈕，開啟含正確目前頁／總頁數的 Bottom Sheet，可拖曳 Slider 跳頁。
- `showFooter` 設定關閉時，FXL 常駐進度文字不顯示；開啟時正確顯示。
- 真機驗證：漫畫 EPUB（已知會被誤判為流式、已套用強制 FXL）與一般原生判定 FXL 書籍皆正確顯示頁碼，不依賴字元數估算。

**相關佐證：**
- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 20／21 修復方向 Discovery」（2026-07-30 grilling 完整決策記錄）
- `app/lib/screens/reader_screen.dart:1666-1711`（流式 EPUB FAB＋常駐進度文字既有模式，本次比照對象）
- `app/lib/screens/reader_screen.dart:1792-1818`（`_buildEpubFooter()` 死碼，字元估算模型不適用於 FXL 的原始寫法）
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:1103`（`readingOrder` 既有使用範例，佐證其不依賴 `positions()`／`servicesBuilder`）

---

## Issue 21：Spike——FXL 封面獨立顯示／頁碼配對（`1,3-2,5-4`），驗證能否覆寫 `page` 屬性強制首頁獨立成頁

**Status:** 🚫 不再執行（2026-07-31）。`epic-20-fxl-foliate-migration` Issue 1 Spike 真機以真實問題書籍驗證 **GO**（`docs/epics/epic-20-fxl-foliate-migration/reviews/spike-issue1-fxl-foliate.md`）——確認 `foliate-js` 的 `epub.js`／`fixed-layout.js` 對這本書的原始 `rendition:page-spread-center`／`page-spread-left`／`page-spread-right` metadata 開箱即用、無需任何修補即可正確渲染封面獨立顯示與 RTL 頁序，本 Issue 在 Readium 內覆寫 `page` 屬性的方向不再需要，正式實作方向改在 `epic-20` Architecting 階段承接。

**依賴：** 無（獨立於 Issue 20，可平行進行）。

**背景：** 使用者真機測試發現，強制 FXL 的漫畫 EPUB 在雙頁模式下，頁碼配對沒有依照「封面獨立成頁、之後兩兩並排」（`1,3-2,5-4`）的慣例呈現，PDF 已有對應的「封面獨立顯示」功能（`dualPageCoverAlone`，`PdfReaderView.kt` 手寫的配對演算法），EPUB FXL 這邊完全沒有對應機制。

**外部分析報告（`docs/epics/epic-18-reader-device-qa/reviews/spike-fxl-first-page-single-spread.md`）技術主張逐一查證結果（對照 Readium 3.3.0 官方原始碼）：**

| 主張 | 查證結果 |
|---|---|
| `Spread` Enum（`AUTO`/`NEVER`/`ALWAYS`）僅為全域偏好，無頁面層級控制，無法單靠它讓第一頁獨立成頁 | ✅ 正確——已對照 `Types.kt` 確認 `Spread` 只有 3 個全域值，KDoc 僅「Synthetic spread policy」 |
| 建議程式碼：`org.readium.r2.shared.publication.presentation.Page`、`Page.CENTER`、`link.properties.presentation.copy(page = Page.CENTER)` | ❌ **不存在**——已查證 `presentation/Properties.kt` 只有 5 個已棄用擴充屬性（`clipped`/`fit`/`orientation`/`overflow`/`spread`），沒有 `page`／`Page` 這組 API；`epub/Presentation.kt` 只有一個已棄用的 `layoutOf()`。此 API 為編造，不會編譯（與 Issue 18 承接的前一份外部報告犯了同一種錯誤——概念方向可能對，具體程式碼是錯的）。 |
| 建議程式碼：`publication.readingOrder[0] = firstLink.copy(...)` 直接索引賦值 | ❌ **不會編譯**——`Manifest.readingOrder` 是不可變 `List<Link>`，沒有 `set` 運算子。 |
| 「覆寫第一頁屬性讓 Readium 自動歸為單頁 Spread」這個**方向**是否可行 | ⚠️ **需要修正做法＋核心假設未經真機驗證**——查證到 `Properties`（`readium/shared/.../publication/Properties.kt`）是 `data class`，本質包一個 `otherProperties: Map<String, Any>`，提供 `.add(properties: Map<String, Any>)` 合併任意 key（已棄用的 `spread` 擴充屬性底層就是讀 `this["spread"] as? String` 這個原始 key）；另外查到官方 `ManifestTransformer` 介面（`transform(link: Link): Link`）搭配 `Manifest.copy(transformer)`，是比外部報告乾淨的官方轉換管道。但 Readium 的 spread 演算法實際上讀哪個 key（很可能是 `"page"`，對應 EPUB `page-spread-center`，但未經證實）、以及讀了之後是否真的按單頁處理，**無法只靠讀原始碼確認，需要真機驗證**（與 Issue 16-19 一路查到的模式一致）。 |

**修復方向（Spike 假設，需真機驗證）：** 在 `attachNavigator()`（沿用 Issue 19 已在用的 `Publication.Builder` 重建同一處）額外覆寫 `readingOrder` 第一項 `Link.properties`，用 `.add(mapOf("page" to "center"))`（或真機驗證後找到的正確 key）標記為獨立頁，重建後傳給 `EpubNavigatorFactory`，觀察 Readium 的 spread 演算法是否真的把它當獨立頁處理。

**Spike 範圍：**
1. 硬編碼上述覆寫邏輯（不做 Dart→Kotlin 旗標傳遞管線，比照 Issue 17/18 既有 throwaway 慣例）。
2. 真機驗證：橫向雙頁模式下，第一頁（封面）是否真的獨立顯示，第二頁起是否正確兩兩配對（`2,3`／`4,5`……）。
3. 若 `"page"` key 無效，嘗試查證正確 key 名稱（可能需要對照 Readium 如何解析 EPUB OPF 的 `page-spread-*` 屬性、或攔截/記錄 spread 演算法實際讀取的 key）。

**GO/NO-GO 決策路徑：**
- **GO**：覆寫後首頁確實獨立成頁、後續正確配對，記錄結果，新增工單承接完整實作。
- **NO-GO**：Readium spread 演算法不讀取此屬性、或讀取但效果不符預期：記錄具體證據，評估外部報告「方案 3」（Native App 層物理裁切，已被報告自身標註不推薦、會有畫面殘影）是否值得一試，或回頭評估其餘替代方案（例如接受此限制、UI 提示）。

**單元測試要求：** 無（研究/驗證性質，比照 Issue 8／17／18 先例）。

**相關佐證：**
- `docs/epics/epic-18-reader-device-qa/reviews/spike-fxl-first-page-single-spread.md`（外部分析報告，方向查證屬實，具體程式碼已查證有誤並修正）
- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 20／21 修復方向 Discovery」
- `docs/epics/epic-18-reader-device-qa/plans/plan-issue-18.md`（`Publication.Builder` 重建既有慣例，本 Spike 沿用同一處掛鉤點）
- Readium `kotlin-toolkit` 3.3.0 官方原始碼：`navigator/preferences/Types.kt`（`Spread` enum）、`shared/publication/presentation/Properties.kt`（已棄用擴充屬性）、`shared/publication/Properties.kt`（`Properties` data class／`.add()`）、`shared/publication/ManifestTransformer.kt`（官方轉換介面）
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`（PDF `dualPageCoverAlone` 既有實作參考）

---

## Issue 22：FXL 缺少目錄（TOC）按鈕（順帶發現，另立追蹤）

**Status:** needs-triage，已於 Issue 20 grilling 順帶發現，尚未進行完整 Discovery。

**依賴：** 無。

**描述：** 流式 EPUB 浮動按鈕群組有 `reader_foliate_toc_button`（開啟目錄），FXL 浮動按鈕群組（`reader_fixed_layout_*`）沒有對應物——FXL 目前完全沒有從閱讀畫面開啟目錄的入口。範圍與確切修復方式（新按鈕位置、是否共用既有 TOC Bottom Sheet 元件）留待正式 Discovery。

**明確不在本 Issue 範圍**：Issue 20（進度條/頁尾）、Issue 21（封面獨立顯示），本次 grilling 決定不與之合併處理。

**相關佐證：**
- `app/lib/screens/reader_screen.dart:1577-1596`（流式 EPUB `reader_foliate_toc_button` 既有實作參考）
- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 20／21 修復方向 Discovery」

---

## Issue 23：頁首/頁尾行為調整（邊界預設、FXL 開關補齊、預設關閉、直排位置、章節名稱顯示）

**Status:** 實作計劃已撰寫（`plans/plan-issue-23.md`），待計劃審查通過後開始執行。已完成 `/diagnose` 現況查證（`reviews/bugfix-repro-header-footer.md`，未進版控），5 項需求皆已定位到確切修改點，3 個開放問題已與人類確認（見下方各子項）。計劃拆為 6 個 Task：Task 1-5 對應 5 項需求逐一實作，Task 6 最終驗證與收尾。

**依賴：** 無（皆為既有頁首/頁尾機制上的調整，不依賴其他未完成 Issue）。

**背景：** 使用者提出 5 項頁首/頁尾相關的行為調整需求，經 `/diagnose` 逐項查證程式碼現況（診斷過程詳見 `reviews/bugfix-repro-header-footer.md`）。

**範圍：**

1. **流式 EPUB 上邊界預設改 32**：`app/android/app/src/main/assets/foliate/main.js:222` 的 `marginTopPx` 未設定時預設值由 `64` 改為 `32`（此段落已明確標註僅適用流式書籍，FXL 不受影響）。

2. **FXL 補齊頁首/頁尾開關**：`app/lib/screens/fxl_settings_sheet.dart` 目前完全沒有「顯示頁首」/「顯示頁尾」控制項（`reader_settings_sheet.dart:306-318` 流式書籍已有）。底層資料模型與 `reader_screen.dart` 的顯示邏輯已對 FXL/流式一視同仁，純粹是 FXL 設定畫面遺漏 UI，比照既有 `SwitchListTile` 模式補上，接到既有的 `BookReaderPrefs.showHeader`/`showFooter` 儲存機制。

3. **兩種格式（含 PDF）預設皆改為關閉**：唯一正式預設值來源 `app/lib/reader/reader_prefs_manager_impl.dart:179-180` 的 `book.showHeader ?? true`／`book.showFooter ?? true` 改為 `?? false`（PDF 與 EPUB 共用同一個 `ResolvedPreferences.showFooter` 欄位與解析點，需在實作階段確認是否真為同一路徑，非另外獨立分支）；另需一併檢視 `reader_screen.dart`／`reader_settings_sheet.dart` 內數個「`_resolved` 尚未載入完成前」的防呆用 `?? true` 站點（`reader_screen.dart:1235,1545,1553,1623`；`reader_settings_sheet.dart:90-91,120-121`），同步改為 `?? false`，避免開書瞬間短暫顯示、`_resolved` load 完成後才消失的畫面閃爍。

4. **直排頁首移到右上角＋與 FAB 互斥**：`reader_screen.dart:1545-1551`（頁首 `Positioned`）目前完全沒有直排分支（永遠水平置中），也完全沒有 `_chromeVisible` 判斷（是全部浮動元素中唯一的例外，其餘 6 顆 FAB 按鈕與頁尾皆各自有明確的顯示條件）。改動兩點：(a) 比照頁尾既有的直排寫法（`reader_screen.dart:1552-1569` 的 `RotatedBox(quarterTurns: 1)` 模式）新增頁首的直排分支，改置於右上角；(b) 不分直排/橫排，顯示條件加上 `!_chromeVisible`，改為「只在非沉浸模式（實際閱讀中）時顯示，FAB 顯示時必隱藏」。**此變更會反轉 Issue 13 當初的明確決策**（Issue 13 刻意移除頁首/頁尾的 `_chromeVisible` 判斷，讓頁首「跟內文常駐顯示、不受沉浸模式影響」）——本次不是恢復 Issue 13 之前「只在 `_chromeVisible == true` 時顯示」的舊行為（那樣會跟 FAB 同時出現），而是新的第三種狀態「只在 `_chromeVisible == false` 時顯示」，三者差異需在實作與測試中清楚區分，避免與 Issue 13 歷史決策混淆。**本項目只改頁首，不影響 Issue 13 對頁尾（進度文字）常駐顯示的既有決策，頁尾維持現狀。**

5. **頁首文字改善——第一層章節名稱或書名**：`_buildFoliateHeaderText()`（`reader_screen.dart:1684-1704`）目前用 `currentPath.last.title`（目錄巢狀路徑最深層項目，非第一層章節），改為 `currentPath.first.title`；找不到章節時目前寫死顯示 `'閱讀器'`，改為顯示書名。**`ReaderScreen` 目前沒有任何管道能拿到書名**，需新增 `bookTitle` 建構參數（由 `library_screen.dart:402-412` 的 `_openBook(Book book)` 直接從既有 `Book` 物件傳入 `book.title`，不新增 `LibraryRepository` 查詢方法、不在 `ReaderScreen` 內部另外非同步查詢），並同步更新 `CLAUDE.md`「`ReaderScreen` 對外的公開建構參數」段落（目前記載為 `filePath`／`bookId`／`prefsRepository`，屬新增性質，不影響既有參數相容性）。另查證確認：`_buildAppBarTitle()`（`reader_screen.dart:1234-1257`）雖有類似的 `currentPath.last.title` 邏輯，但 EPUB 格式的 `Scaffold.appBar` 恆為 `null`（`_isFixedLayout`／`_dispatchedIsFixedLayout == false` 兩者對 FXL／流式各自恆真），此方法實質只服務 PDF（PDF 走固定靜態文字分支，不受本項目影響），**本項目不需修改 `_buildAppBarTitle()`**。

**單元測試要求：**
- `foliate_epub_reader_view_test.dart` 或等效測試：`main.js` 的 `marginTopPx` 預設值變更（若有對應的既有斷言需同步更新）。
- `fxl_settings_sheet_test.dart`（若存在）或 widget test：新增的頁首/頁尾開關可正確切換並持久化。
- `reader_prefs_manager_impl_test.dart`：預設值 `?? false` 的既有測試斷言需盤點並更新（原本假設預設 `true` 的測試會失敗）。
- `reader_screen_test.dart`：盤點所有假設「頁首/頁尾預設顯示」「頁首在 `_chromeVisible == true` 時仍顯示」（尤其 Issue 13 建立的測試）的既有測試，依新行為改寫；新增測試驗證 `!_chromeVisible` 時頁首顯示、`_chromeVisible` 時頁首隱藏（含直排/橫排各一）；新增測試驗證 `bookTitle` 在無章節資訊時正確顯示為頁首文字。

**驗收標準：**
- 上述測試皆通過，`flutter analyze` 乾淨。
- 真機（`3CEF42ECD491687`）驗證 5 項需求：流式書籍預設上邊界為 32px；FXL 設定畫面可切換頁首/頁尾；全新書籍開啟時頁首/頁尾（含 PDF 頁尾）預設關閉；直排時頁首正確顯示於右上角且與 FAB 互斥（顯示 FAB 時頁首消失，收起 FAB 進入閱讀時頁首出現）；頁首文字在有章節資訊時顯示第一層章節名稱、無章節資訊時顯示書名（非「閱讀器」字樣）。

**相關佐證：**
- `docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-header-footer.md`（`/diagnose` 完整查證過程，本 Issue 全部修改點的來源）
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 13（本次項目 4 會反轉的既有決策，需對照理解）
- `CLAUDE.md`「`ReaderScreen` 對外的公開建構參數」段落（項目 5 需同步更新）

---

## 審查修訂紀錄（`tmp/epic-18/reviews/review_report.md`，經人類確認後採納）

- **採納**：`spec.md`／Issue 4 澄清 `buildOverrideCss()` 維持純函式，所有 `setAttribute` 呼叫改到 `window.applyPreferences(prefs)`（既有的副作用進入點，`pageTurnMode`/`writingMode` 已是同樣模式）。
- **採納**：`spec.md`／Issue 4 新增明確要求：`setAttribute('margin-top'/'margin-bottom', ...)` 的值必須是帶 CSS 單位的字串（如 `"24px"`），純數字對長度屬性是無效值、會被靜默忽略。
- **採納**：Issue 1 的 Bottom Sheet 版面改為 `Column(mainAxisSize: MainAxisSize.min, children: [關閉列, Flexible(child: ListView(shrinkWrap: true, ...))])`——原文缺少 `mainAxisSize: MainAxisSize.min`，會導致內容再短的 Sheet 也被撐滿版面，與是否使用 `Expanded` 無關（loose constraints + `Column` 預設 `mainAxisSize.max` 所致）。
- **採納**：Issue 2 新增明確要求：`toolbarHeight: 20` 必須同步收斂 `IconButton` 的 `padding`/`constraints`/圖示大小與 `title` 字級，否則會溢出/與內容區重疊/誤觸，具體像素值列為起始建議而非最終規格。
- **採納**：Issue 2 補上既有字串斷言會壞掉的完整清單（`reader_footer_test.dart` 2 處＋`reader_screen_test.dart` 7 處，原審查報告只提到前者，複查後補齊後者）。
- **採納**：Issue 3 補上 `crossAxisSpacing`/`mainAxisSpacing` 的視覺建議（Minor，非必要）。
- **採納**：Issue 5 補上原文遺漏的 SQLite migration round-trip 測試要求（`version: 11 → 12`），複查確認目前 schema 版本確實是 11。
