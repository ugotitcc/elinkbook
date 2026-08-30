# Epic 28 — 閱讀器設定強化：Discovery

## 背景

2026-08-13 使用者提出三項與「版面設定」相關的功能需求，經 `/brainstorming` 分類後拆為 3 個 Issue：

1. **字距（letter-spacing）選項**——流式 EPUB 版面設定新增一項排版數值控制。
2. **Console Log 可手動關閉**——「閱讀器 Console Log」目前無條件攔截 WebView console 訊息，需要一個開關。
3. **版面設定預設集**——可儲存最多 3 組具名版面設定，並可套用到目前書籍或跨書套用。

Issue 1、2 屬 **bounded**（既有流程加欄位/開關，已在對話中定案，見下方，不另外走 Architecting）；Issue 3 屬 **architectural**（新資料表＋新 Repository＋跨書套用 UI），走完整 Discovery → Architecting 流程，架構細節見 `spec.md`。

三者皆先確認一個關鍵事實：`ReaderSettingsSheet`（流式 EPUB）、`PdfSettingsSheet`（PDF）、`FxlSettingsSheet`（固定版面 EPUB）是三個完全獨立的版面設定畫面（`reader_screen.dart:653/664/674`），不是共用元件。本 Epic 三項需求皆只涉及 `ReaderSettingsSheet`，不影響 PDF／FXL。

## `/grilling` 決策紀錄

### Issue 1：字距選項

- 數值範圍 `-0.05em ~ 1em`，預設 `0`（不覆蓋書本原生字距），step `0.01em`，UI 沿用現有 `_buildSliderRow`（含 +/- 微調按鈕）。
- 橫排／直排（`vertical-rl`）皆套用同一份 CSS 規則，不特別排除——`letter-spacing` 作用於 inline 軸方向，直排下 inline 軸為垂直方向，語意依然合法。
- 完全比照現有 `lineHeight`/`paragraphSpacing` 欄位模式：`BookReaderPrefs`＋`ResolvedPreferences`＋SQLite migration＋`main.js` 的 `buildOverrideCss()` 新增一條 `letter-spacing` CSS 規則，複用既有的廣選擇器。

### Issue 2：Console Log 開關

- 位置：`SettingsScreen`（與「閱讀器 Console Log」入口同一頁）新增一個 `SwitchListTile`。
- 預設**關閉**。
- 開關只控制一般等級（`onConsoleMessage` 回報的 `[LOG]`/`[WARNING]` 等非 ERROR 等級）訊息是否寫入 `ReaderConsoleLog`；**`[ERROR]` 等級（含 WebView 自動鏡射的未捕捉例外）永遠強制記錄，不受開關影響**，保留崩潰診斷能力（`epic-27-reader-device-compat` 的崩潰診斷正是靠這條線索）。
- 關閉當下不清空既有紀錄，只是停止新增一般等級訊息——`ReaderConsoleLog`（`app/lib/reader/reader_console_log.dart`）本來就是純記憶體 `ValueNotifier`，不落地持久化資料庫、App 重啟即清空，且**已有**既有的 500 筆上限與 `ReaderConsoleLogScreen` 的「清空」按鈕（2026-08-14 審查一度誤以為需要新增資料庫成長上限與清除按鈕，經核實現況後澄清不需要新增，見 `spec.md`「審查回應」）。
- 與 `_globalErrorCaptureJs`（`window.onerror`/`window.onunhandledrejection` → `onError` bridge → `reader_screen.dart` 的 `_handleError()`）是完全獨立的另一條管線，本開關不影響它——那是驅動閱讀器錯誤畫面狀態的核心錯誤處理機制，不是「log 功能」。

### Issue 3：版面設定預設集 ＋ 書籍設定複製

- 範圍：僅流式 EPUB（`ReaderSettingsSheet`），PDF/FXL 不適用。
- 預設集內容：`ReaderSettingsSheet` 目前呈現的**全部項目**（含排版數值型欄位，也含方向/翻頁模式/螢幕方向覆寫等），非僅數值型欄位子集——見下方「欄位範圍」精確定義。
- 最多 3 組，使用者可自訂名稱（trim 後 1~20 字元，允許重複名稱，細節見 `spec.md`「命名驗證」）；存滿時跳出選單選擇覆蓋哪一組（顯示名稱＋最後更新時間），覆蓋前二次確認。
- 管理介面（新增/命名/刪除）內嵌在 `ReaderSettingsSheet` 底部新增區塊，不另開畫面。
- 套用來源二選一：
  - ①「從我的預設集」——選一組已存的具名預設集。
  - ②「從其他書籍複製」——直接讀某本來源書籍目前的單書版面偏好設定，不經預設集中介、不受 3 組數量上限限制，一次性書對書操作。兩個方向皆須實作（見下方可行性評估）。
- 套用目標二選一：
  - 「套用到目前書籍」——直接寫入，不需額外確認（比照其他版面設定變更的既有 UX，非破壞性、可隨時再調整）。
  - 「套用到其他書籍」——彈出批次選書清單＋「即將覆蓋 N 本書」確認對話框。
- 書籍選擇器（複製來源／套用目標皆共用）只列出**流式（非 FXL）EPUB** 書籍，排除 PDF/FXL/TXT——欄位語意不共通，避免誤選。

**方向 A（預設集）vs 方向 B（書籍複製）的可行性評估**（回應使用者提問）：兩者共用同一套「讀來源 `BookReaderPrefs` → 寫目標書籍」的底層邏輯，差別只在來源——方向 A 來源是新表的一列，方向 B 來源直接是 `BookReaderPrefsRepository.load(sourceBookId)`。方向 B 事實上比方向 A 更簡單（不需要「命名/3組上限/覆蓋管理」這些狀態），邊際成本低，建議兩者都做、共用同一套「套用到目前書籍/其他書籍」的寫入與選書 UI。

## 欄位範圍（Issue 3 精確定義）

`BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`）目前 29 個欄位中，`ReaderSettingsSheet` 實際呈現的子集為：

`fontFamily`／`fontSize`／`fontWeight`／`lineHeight`／`paragraphSpacing`／`marginTop`／`marginBottom`／`marginLeft`／`marginRight`／`textAlign`／`publisherStyles`／`showHeader`／`showFooter`／`fullscreen`／`columnMode`／`columnSize`／`writingModeOverride`／`pageTurnModeOverride`／`screenOrientationOverride`，加上本 Epic Issue 1 新增的 `letterSpacing`。

**不含**：`pageMargins`（EPUB 舊版單值邊距，僅 `EpubReaderView`/FXL 使用，已被 `marginTop/Bottom/Left/Right` 取代）、6 個 `pdf*` 欄位、3 個 `dualPage*` 欄位——這些欄位在一本流式 EPUB 的 `book_reader_prefs` 列上結構性恆為 `null`（`ReaderSettingsSheet` 從未寫入過），詳見 `spec.md`「儲存格式」對此如何簡化實作的說明。

## 依賴關係

Issue 3 的預設集欄位快照須包含 `letterSpacing`，因此**依賴 Issue 1 先完成**（`BookReaderPrefs` 需先有這個欄位）。Issue 2 與 Issue 1、3 互相獨立。

## 範圍界定

- 涵蓋：流式 EPUB 版面設定新增字距欄位；Console Log 攔截開關（一般等級可關閉、ERROR 等級強制保留）；版面設定預設集（最多 3 組，具名，可套用到目前/其他書籍）；書籍設定直接複製（跨書、無數量上限）。
- 不涵蓋：PDF／FXL 版面設定的字距或預設集（欄位語意不共通，留待未來需求另立 Issue）；Console Log 內容格式或等級分類邏輯本身的變更（僅新增「是否記錄非 ERROR 等級」的開關）；預設集/書籍複製套用到 PDF/FXL 書籍。

## 新詞彙（已記入 `CONTEXT.md`）

「版面設定預設集（Layout Preset）」、「書籍設定複製（Copy Layout From Book）」，與既有「單書版面偏好設定」「全域預設值」的區別已於 `CONTEXT.md` 明確註記，避免混淆。

---

## 2026-08-15 追加：`/grill-with-docs` 決策紀錄——版面設定 UI 重構（Issue 5／Issue 6）

Issue 1-3 上線後，`ReaderSettingsSheet` 累積的控制項數量已相當可觀（本 Epic 疊加字距等新欄位，加上既有全部排版控制項），使用者需要大量捲動才能找到想調整的項目；同時「從其他書籍複製」的選書畫面（`LayoutPresetBookPickerScreen`）單選模式點擊項目即立即觸發複製、無任何確認機制，滑動時有真實的誤觸風險（已用原始碼交叉核對確認：`ListTile.onTap` 直接 `Navigator.pop([book.id])`，無防呆）。使用者提出 UI 重構需求，經 `/grill-with-docs`（`grilling` + `domain-modeling`）三輪問答定案，人類確認併入本 Epic，拆為 Issue 5、Issue 6（見 `issues.md`）。

### 整體導覽結構（Issue 5）

- **容器維持 Bottom Sheet**（不改為全螢幕頁面），改用 `DefaultTabController` + `TabBar` + `Expanded(child: TabBarView(...))` 包裹既有內容——比照本 Epic 上線後、`epic-24-pdf-engine-rebuild` Issue 5 為 `TocBottomSheet` 建立的既有先例（`toc_bottom_sheet.dart:178-202`，PDF 版「章節目錄／縮圖／搜尋」三分頁）：`Expanded` 需要有界高度，`showModalBottomSheet(isScrollControlled: true)` 恰好提供這個上限，讓 Sheet 撐到近全螢幕高度、各頁籤各自獨立捲動，技術路徑已在本專案驗證過。
- **4 個頁籤，依「頁籤負載平衡」而非嚴格語意分類分配**——目標是讓多數頁籤在一般手機直向螢幕下不需捲動即可看到該頁籤全部控制項（非強制零捲動，內容量本來就大的頁籤例如「設定喜好」可接受捲動）：
  1. **文字內容**：停用本書CSS、單書閱讀字型、字型大小、字型粗細、行高、段落間距、字距
  2. **邊界首尾**（原提案「版面邊界」，因加入非邊界性質的頁首/頁尾改名以求名實相符）：上下左右邊界、顯示頁首、顯示頁尾、文字對齊——顯示頁首/頁尾之所以歸類在此，是因為「文字內容」頁籤欄位數量已較多，放進「邊界首尾」頁籤是為了平衡各頁籤捲動量，並非因為兩者語意相關（頁首/頁尾本質是控制 App 介面元件顯示，非書本樣式）。
  3. **版面呈現**：全螢幕模式、欄數、排版方向模式、螢幕方向鎖定覆寫、翻頁模式覆寫
  4. **設定喜好**：版面設定預設集、從其他書籍複製
- **重構範圍**：既有控制項搬進新 Tab 容器＋針對有助於減少捲動的控制項重新設計視覺密度（例如「版面呈現」頁籤內 4 組圖示列的緊湊排列，具體佈局留給實作計畫定案），操作邏輯與既有測試 `Key` 維持不變。
- **已知最大工作量來源**：`reader_settings_sheet_test.dart`（1124+ 行、50+ 則測試）內既有測試皆假設所有欄位在同一個可視畫面內，改為分頁後多數既有測試需要先切換到正確 Tab 才能互動到目標欄位，是本 Issue 範圍中工作量最大的部分，需在實作計畫中逐一盤點。

### 選擇書籍畫面優化（Issue 6）

- **格線化**：`LayoutPresetBookPickerScreen` 由純文字 `ListView` 改為格線（比照 `LibraryScreen` 既有 `SliverGridDelegateWithFixedCrossAxisCount` 直向 3 欄／橫向 4 欄慣例），每格顯示封面圖（`Book.coverPath`，無封面時退回格式圖示佔位，比照 `LibraryScreen._BookCover` 既有 fallback 邏輯）＋書名。
- **單選確認機制統一**：單選（複製到本書）情境改為比照既有多選模式——Grid item 改為可選取狀態（Radio 語意）＋ AppBar 右上角新增「確定」按鈕（未選取時停用），取消目前「點擊即觸發」的零確認行為；多選模式維持既有 Checkbox 語意不變，兩種模式的視覺與互動邏輯自此完全統一（只差可選取數量），比新增一個獨立的「點擊後彈窗」互動模式更不容易日後行為不一致。
- **新增搜尋**：常駐顯示於 AppBar 下方的搜尋 `TextField`，即時比對書名＋作者（子字串、大小寫不敏感），純本機記憶體篩選（書籍清單已一次性載入，無網路/資料庫查詢延遲，不需等待送出鍵）；多選模式下，被篩選暫時隱藏的已選取項目須保留選取狀態，不因搜尋詞變動而遺失。

### Epic 歸屬

人類確認併入既有 `epic-28-reader-settings-enhancements`（不開新 Epic），列為 Issue 5、Issue 6，兩者互相獨立、無依賴，可平行推進。不涉及新增資料層介面/型別（`BookReaderPrefs`／`LayoutPreset`／各 Repository 皆不變），純 UI 層重構，故比照 `epic-27-reader-device-compat` 既有先例跳過正式 `spec.md`，直接進入 `issues.md`。

### 審查回應（2026-08-15，`/superpowers:requesting-code-review`，`reviews/review-issue-5-6-design.md`）

0 Critical／3 Important／3 Minor，逐項查證後皆技術正確，全數採納，已回寫至 `issues.md` 對應工單內文：

- **Important #1（`TabBarView` 水平滑動手勢與內部 Slider 拖曳手勢衝突）**：`TabBarView` 內部即 `PageView`，預設 `physics` 允許水平滑動切頁，會與「文字內容」（5 個 Slider）／「邊界首尾」（4 個 Slider）頁籤內大量橫向拖曳型控制項搶手勢競技場（Gesture Arena），造成「調整滑桿時意外切換頁籤」的真實風險——已查證屬 Flutter `TabBarView`+`Slider` 組合的已知通用陷阱，非本專案特有假設。採納：`TabBarView` 明確設定 `physics: const NeverScrollableScrollPhysics()`，只能點擊 `TabBar` 切換，已寫入 Issue 5「Solution」。
- **Important #2（單選模式取消時的 `null` 回傳契約）**：已用原始碼核對確認——`reader_settings_sheet.dart:898/904/910/912` 的 `_handleApplyPresetToOthers`／`_handleCopyFromBookToCurrent`／`_handleCopyFromBookToOthers` 皆已有 `if (targets == null || targets.isEmpty) return;` 既有防呆，**這個契約在 Issue 6 之前就已存在、不是新缺口**；審查抓到的是「Issue 6 重構過程中不能不小心破壞這個既有契約」的真實風險，而非目前程式碼缺少防呆。已將「未點擊確定即返回時一律回傳 `null`，呼叫端既有防呆邏輯須維持」明確寫入 Issue 6 驗收標準與單元測試要求（列為回歸測試，非新增功能）。
- **Important #3（Issue 4 草稿旗標在 Tab 切換下的狀態穩定性）**：本來的設計意圖（4 個頁籤只是同一個 `_ReaderSettingsSheetState` 的 `build()` 分支，不是獨立 `StatefulWidget`）已經滿足這個要求，但原文未明確寫出、容易被實作者誤解為「每個頁籤可以獨立抽出元件」。已在 Issue 5 明確補上這條限制。
- **Minor #1（既有測試遷移 Test Helper）**：已在 Issue 5「已知範圍風險」段落採納建議的 `switchToTab` 命名。
- **Minor #2（`_BookCover` 共用元件化）**：原文本就留給實作者決定是否抽出，現改為明確建議（非強制）抽出至 `app/lib/library/widgets/book_cover.dart`，已寫入 Issue 6。
- **Minor #3（軟體鍵盤彈出時的版面適配）**：已寫入 Issue 6「Solution」，`GridView` 以 `Expanded` 包裹、確認 `Scaffold.resizeToAvoidBottomInset` 正常運作。
