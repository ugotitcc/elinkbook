# Epic 36 — 三目的地導覽／書架下鑽強化／設定四分區：Discovery

## 緣起與範圍界定

依 `elinkBook-uiux-audit.dc.html` 第 5～8 節與多輪 `/grill-with-docs` 定案，`DESIGN.md` 已更新 §11（導覽）、§15（圖書庫與書架）、§17（設定畫面，新增章節）。本 Epic 是這些規範落地到 `app/lib` 的實作端，並修正過程中發現的三處 `DESIGN.md` 自身內部矛盾（詳見下方「已解決的規格矛盾」）。完整討論過程記錄於 `docs/research/uiux/eink-redesign-rebuild-plan.md`（含原型 `prototype/elinkbook_theme_prototype.html` 的驗證結果），本文件只整理落地到程式碼所需的結論。

依循 `UI_DESIGN_RULES.md`：本 Epic 只碰 Navigation／Library UI／Settings UI／Bottom sheets／Dialogs／Layout，不碰 OPDS／WebDAV／雲端來源實作、書籍儲存、閱讀進度持久化等核心架構清單項目。每個 Issue 的 `plan-issue-N.md` 動手改程式碼前，須先說明：(1) 改哪個 UI 元件 (2) 為什麼要改 (3) 哪些畫面依賴它 (4) 是否影響 business logic。

## 現有程式碼現況（決定了本 Epic 是「從無到有」還是「修正既有」）

- **導覽架構：從無到有。** `main.dart` 目前 `home: LibraryScreen(...)`，畫面切換靠各畫面自己的 AppBar 按鈕＋`Navigator.push`，完全沒有 `NavigationBar`／`NavigationRail`／`AdaptiveScaffold`。§11.1 的三目的地標題列圖示導覽（書架／來源／設定互相跳轉、平板走 `NavigationRail`）是本 Epic 要新蓋的部分。
- **書架長按批次選取：已存在，沿用。** `library_screen.dart` 已有 `_selectedBookIds`／`onLongPress` 驅動的多選模式（移動分類／移除快取／刪除），跟 §15.1「長按維持多選（不改為單書動作選單）」的定案相容，不需重做。
- **書架分類下鑽：已存在，但現況不符 §11.2，需重構（見審查報告 `reviews/review-design.md` C-2）。** 現行 `_openGroupFilteredView()`（`library_screen.dart:615-657`）點擊分類拼貼格時是 `Navigator.of(context).push(MaterialPageRoute(builder: (_) => LibraryScreen(..., groupFilter: groupName)))`——**推入一個全新獨立的 `LibraryScreen` State 實例**模擬下鑽，並不是原地狀態切換，**不符合** `DESIGN.md#L268` §11.2「點擊分類格子時在當前書架直接『下鑽』更新狀態……不再使用 `Navigator.push` 堆疊新畫面」的明文規範；若不修正，三目的地圖示導覽會因為多推入一層帶獨立 AppBar 的畫面而破裂。本 Epic 要做的是：(1) 消除該 `Navigator.push`，改由 `LibraryScreen` 內部狀態（如 `_activeGroupFilter`）控制顯示模式，網格上方顯示「‹ 返回上層 [分類名稱]」引導列（比照 `prototype/elinkbook_theme_prototype.html#L206-L211`）；「管理分類」入口（現行 `library_manage_groups_button`，`library_screen.dart:872-878`，`groupFilter == null` 才顯示）併入 AppBar「排序/檢視」`PopupMenuButton` 選單底端，取代直接刪除；(2) 疊加換頁控制列（`PagingBar`，取代目前推測是無限捲動的呈現方式，需在 Issue 規劃時實測確認現況）、繼續閱讀列、「⋮」單書動作選單。
- **設定畫面：已存在，需重分區＋補項目。** `settings_screen.dart`（336 行）已有主題圓點與 E-Ink 開關（見 `epic-35` design.md），但不是 §17.1 定義的四分區結構（外觀／閱讀／同步與帳號／關於），且缺「朗讀語音與語速」項目、「關於」獨立區塊。

## 本次落地範圍（依 `DESIGN.md` 章節）

1. **§11.1／11.2 導覽**：三目的地標題列圖示導覽（書架／來源／設定），手機寬度不用底部導覽列；平板／桌機走 `NavigationRail`（規格沿用既有 §11.1 未變動部分，本 Epic 不重新設計斷點邏輯本身，只確保手機寬度的圖示改動落地）。`AdaptiveScaffold` 內部三目的地頁面本體須用 `IndexedStack` 管理（而非切換時重新具現化 widget），確保切換目的地再返回書架時，頁碼／搜尋關鍵字／分類下鑽狀態不遺失，同時天生符合 E-Ink 模式零轉場動畫（`Duration.zero`）要求。
2. **§15.1／15.2 書架**：
   - 書架分類**原地下鑽重構**：消除 `Navigator.push`、改內部狀態切換＋「‹ 返回上層」引導列，「管理分類」入口併入 AppBar「排序/檢視」選單（詳見上方「現有程式碼現況」修訂內容，對應審查報告 C-2、I-1）。
   - 繼續閱讀列（常駐顯示最近閱讀書籍與進度）：當書庫無書籍、或所有書籍 `lastReadTime.millisecondsSinceEpoch == 0`（冷啟動、或已匯入但尚未開過任何一本，見 `book_import_service_impl.dart:434` 新書預設值）時，自動隱藏（渲染 `SizedBox.shrink()`）；只有存在至少一本 `lastReadTime > 0` 的書籍才顯示（對應審查報告 I-4）。
   - 換頁控制列 `PagingBar`（52dp／觸控 48dp、E-Ink 56dp，取代無限捲動）：**【訂正審查報告 I-5 建議算式】** 比照 `DESIGN.md#L267`／`#L335` §11.2／§15.1 明文規格「書架網格直排 1 行 3 欄、橫排 1 行 4 欄」，每頁固定顯示**一整排**——直向每頁 3 項、橫向每頁 4 項（分類格＋書籍混排共用同一份計數），不是審查報告 I-5 建議算式假設的「2 列 × 3 欄＝6 本」（該算式與 `DESIGN.md` 原文不符，已核對訂正）；因每頁本身只有 1 行，短螢幕高度溢位風險大幅降低，仍由 `LayoutBuilder` 箝制版面作為額外防線；螢幕旋轉導致每頁容量改變（3↔4）時，以「目前頁第一項的全局 index ÷ 新每頁容量」重新換算頁碼。
   - 單書「⋮」動作選單（`EBSheetShell` 包裹：詳細資料／移動／版面覆寫／移除快取／刪除，移除快取限遠端書庫書籍——移動／移除快取／刪除重用既有批次操作的同一組底層邏輯，不重寫）：
     - 「詳細資料」：彈出輕量 `AlertDialog`，顯示 `Book` 既有 metadata（書名、作者、格式、檔案大小、閱讀進度百分比、最後閱讀時間），本 Epic 落地，不可留空（對應審查報告 I-2）；
     - 「版面覆寫」：本次開一個極簡覆寫對話框（排版方向／翻頁模式），單書套用、與 `GlobalReaderPrefs` 全域預設分離，介面細節留待 `spec.md`（對應審查報告 I-2）。
   - AppBar 改三圖示（排序/檢視、來源、設定，取消「＋」/FAB）：比照 `DESIGN.md#L260-L263` §11.1「書架標題列固定顯示另外兩個目的地圖示＋當下畫面專屬動作圖示」的明文規格——三圖示不含現行 `library_eink_toggle`（E-Ink 快速切換），該按鈕移除，E-Ink 開關收斂回僅存在於「設定」目的地的外觀分區（設定畫面已有的既有開關，見上方「現有程式碼現況」）；「排序/檢視」為現行 `library_sort_button`（`PopupMenuButton<LibrarySortBy>`）與 `library_view_mode_toggle`（格狀/列表切換）合併為單一圖示選單。
3. **§17 設定**：四分區重排（外觀含主題選擇＋E-Ink 開關＋字型管理；閱讀含閱讀預設值／顯示頁首頁尾／翻頁與熱區／朗讀語音與語速；同步與帳號；關於）；主題選擇器沿用 `epic-35` 落地的 `ElinkTokens`。「顯示頁首／頁尾」「朗讀語音與語速」本次落地資料持久化契約（對應審查報告 I-3）：
   - **顯示頁首／頁尾**：現況查核，`showHeader`／`showFooter` 已存在於單書覆寫層 `BookReaderPrefs`（`reader_settings_sheet.dart` 已有對應切換開關），但沒有可調整的全域預設值——多處呼叫端（`reader_screen.dart:1935/2474/2493/2858`）目前硬編碼 `?? false` 回退。本次比照既有 `GlobalReaderPrefs.fullscreen` 的雙層解析慣例（`book.xxx ?? global.xxx`），在 `GlobalReaderPrefs` 新增 `showHeader`／`showFooter` 全域預設欄位，並把上述硬編碼 `?? false` 改為 `?? global.showHeader`／`?? global.showFooter`——這是欄位新增＋回退值替換，不構成「閱讀器 Chrome 重構」，不牴觸下方排除項。
   - **朗讀語音與語速**：現況查核，`SystemTtsProvider` 的語音與語速目前皆為呼叫時的執行期即時參數，無任何全域持久化模型。本次於 `GlobalReaderPrefs` 新增非破壞性可選/預設欄位（例如 `String? ttsVoiceId`、`double defaultTtsSpeed = 1.0`），`spec.md` 須評估對既有測試的影響；`SystemTtsProvider` 呼叫端改讀取此欄位作為預設值即可，不需要重構其餘 TTS 播放邏輯。

## 明確排除於本 Epic 之外

- **來源畫面統一（`SourceBrowser`，§16）之複雜新架構部分**：`DESIGN.md` §16 本身沒有新決策要交付（這次只在原型裡示範了假資料麵包屑，`DESIGN.md` 文字未變動）。本 Epic 明確排除的是其複雜新架構——全新 Provider 抽象、下載佇列狀態機、雲端目錄下鑽麵包屑等，這些牽涉 `OpdsServerProvider`／雲端 Provider 底層實作，屬於 `UI_DESIGN_RULES.md` 明文禁止本輪碰的「OPDS/WebDAV/雲端來源實作」風險區，留在 `DESIGN.md` §19 階段四 Backlog。
  **但**（對應審查報告 C-1）：AppBar 移除「＋」／FAB 後，匯入書籍能力完全併入「來源」目的地（見下方「已解決的規格矛盾」第 3 點）；若三目的地導覽的「來源」目的地沒有任何畫面承接，使用者將完全喪失匯入書籍的途徑。因此本 Epic **必須**交付一個輕量級的來源聚合主頁（`SourcesHomeScreen`），只聚合既有入口、不新增底層邏輯，比照 `prototype/elinkbook_theme_prototype.html#L690-L740` 的卡片版面：
  - 本機區塊：兩個按鈕直接觸發既有的 `_pickAndImportFiles`／`_pickAndImportFolder`；
  - 已連結服務區塊：列表項目直接導航至既有的 `CloudBrowserScreen`（Google Drive／OneDrive）與 `RemoteServerListScreen`（OPDS 書庫）。
  這樣既不碰上述禁區，又能確保「來源」目的地正常運作，書籍匯入能力不中斷。
- **閱讀器 Chrome／TTS 重構（§12／§13）**：多輪 grilling 已明確決定「既有 2b/2c 閱讀器、2d 版面設定四分頁原封不動」，本 Epic 不動。

## 已解決的規格矛盾（落地時無需再確認，直接照此執行）

1. 書架分類**維持下鑽**，不採用稽核報告建議的篩選晶片（見 `DESIGN.md` §11.2／§19 階段三註記）。
2. 書本卡片**長按＝多選**（沿用既有），**⋮ 圖示＝單書動作選單**——兩者不共用手勢（見 §15.1）。
3. AppBar 匯入「＋」與 FAB 兩案皆已淘汰，統一併入「來源」目的地（見 §15.2）。

## 測試遷移預警（對應審查報告 M-2）

`app/test/screens/library_screen_test.dart`（4557 行）現有大量直接測試既有 AppBar 按鈕的用例（`library_import_button` 12 處、`library_manage_groups_button` 6 處、`library_remote_library_button` 4 處、`library_settings_button` 2 處，另有 `library_sort_button` 5 處、`library_view_mode_toggle` 10 處、`library_eink_toggle` 2 處會因「排序/檢視」合併與 E-Ink 快速切換移除而受影響）。書架 AppBar 改為「排序/檢視、來源、設定」三圖示並整合進 `AdaptiveScaffold` 後，這些測試會成片報錯。拆 Issue 時須提前盤點：哪些用例移至新的 `SourcesHomeScreen` 測試、哪些只需更新 Key，不放到實作階段才發現。

## 下一步

Architecting：撰寫 `spec.md`，定義 `PagingBar`／單書動作 Sheet／設定四分區／`SourcesHomeScreen` 的元件介面與依賴（`ElinkTokens`、既有批次操作邏輯）。待 `epic-35` 歸檔、`ElinkTokens` 穩定合併後，進 Scrum Master 階段拆 `issues.md`。切法（依審查報告 `reviews/review-design.md` 建議調整為 5 個 Issue）：

- **Issue 1**：三目的地導覽框架（`AdaptiveScaffold`，含平板 `NavigationRail`、`IndexedStack` 狀態保留）＋輕量來源聚合頁（`SourcesHomeScreen`），確保匯入能力不中斷（解決 C-1、M-3）。
- **Issue 2**：書架原地下鑽重構＋頂部「‹ 返回上層」引導列＋管理分類入口搬遷（併入「排序/檢視」選單），消除 `Navigator.push`（解決 C-2、I-1）。
- **Issue 3**：書架繼續閱讀列（含空狀態防禦）＋換頁控制列 `PagingBar`（含防溢位與旋轉換算）（解決 I-4、I-5）。
- **Issue 4**：單書「⋮」動作選單（`BookActionSheet`）——詳細資料 Dialog、移動、刪除、移除快取、版面覆寫對話框（解決 I-2）。
- **Issue 5**：設定畫面四分區重構（`SettingsScaffold`：外觀／閱讀／同步／關於），含「顯示頁首頁尾」「朗讀語音與語速」的 `GlobalReaderPrefs` 持久化契約（解決 I-3、M-1）。
