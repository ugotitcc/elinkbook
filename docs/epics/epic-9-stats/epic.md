# Epic 9：閱讀統計

## 背景

PRD FR-17（P2）要求系統紀錄每日閱讀時長，計時須基於偵測到的實際閱讀活動（翻頁、捲動、長按），排除閒置與背景時間，並以「貢獻圖」呈現近 365 天的閱讀活躍度，點擊方格可看當日詳細數據。此 Epic 長期停留在 `docs/epics.md` 的 Backlog（原排期順延至 `epic-14-system-settings` 之後）。

2026-09-29 透過 `/grill-with-docs`（`/grilling` ＋ `/domain-modeling`）完成 Discovery，共 15 題、3 輪問答。

Discovery 前已核實的事實：

- 專案內尚無任何閱讀統計實作；`CONTEXT.md` 也沒有相關詞彙（本次新增「閱讀活動」、「每日閱讀統計」、「貢獻圖」三個詞條）。
- `prototype/elinkbook_theme_prototype.html` 與 `DESIGN.md` 皆**沒有**統計畫面或貢獻圖色階，需先補原型。
- `ReaderScreen` 已有 `didChangeAppLifecycleState`（`paused` 時寫入位置）與 Foliate／PDF 兩條路徑的位置回報回呼，可作為活動事件來源。
- SQLite schema 目前為 v26，連線全程開著 `PRAGMA foreign_keys = ON`。
- 語音朗讀（TTS）經 `audio_service` 以前景服務運行，支援螢幕鎖定與背景播放（PRD FR-45），計時須涵蓋這個情境。
- `ElinkTokens` 目前沒有貢獻圖色階；`app/lib/reader/reader_activity_tracker.dart` 已有 `ReaderActivityTracker`（全文檢索排程用），新計時類別因此命名為 `ReadingStatsTracker`。

## 目標

1. 新增每日閱讀統計的本機儲存與累計。
2. 新增依實際閱讀活動計時的 `ReadingStatsTracker`（含背景 TTS 聽書計時）。
3. 新增貢獻圖主題色階 Token 與統計畫面 i18n 字串。
4. 新增設定頁「閱讀統計」畫面：365 天貢獻圖、點擊看當日各書時數、累計總時數、清除全部。

## Discovery 結論（2026-09-29 `/grill-with-docs`）

詳見 `design.md`。

2026-09-29 審查（`reviews/review-epic-and-design.md`：2 Critical、4 Important、3 Minor）後修訂：計時改為三態狀態機並新增背景 TTS 例外、明訂資料表不設外鍵、加入時鐘倒撥防護、貢獻圖改用水平捲動與 Inline 詳情卡片、新類別改名、Issue 切分定案為 5 張（見 `issues.md`）。

## Issue 1 完成記錄（原型，2026-09-29 人類目視確認完成）

**做了什麼：** `prototype/elinkbook_theme_prototype.html` 新增「閱讀統計」畫面（設定 → 閱讀統計；側欄「閱讀統計（貢獻圖）」），含 53 週貢獻圖、固定星期欄、Inline 詳情卡片、累計總時數、圖例、清除全部確認流程，以及四種假資料情境（一般／今天無紀錄／全空／重度）。純邏輯（分級、網格、假資料）以 `node --test prototype/tests/stats_logic.test.js` 驗證（本機 Windows Node v24 須寫明確檔名，目錄形式會 `MODULE_NOT_FOUND`）。

**定案值（Issue 5 直接取用）：**

| 級別 | 意義 | Light | Dark | Sepia | E-Ink 灰階 | E-Ink 紋理 |
|---|---|---|---|---|---|---|
| 0 | 無紀錄 | `#eaf1f5` | `#2c2c34` | `#e6dfcb` | `#ffffff` | 留白 |
| 1 | 未滿 15 分 | `#bae6fd` | `#0c4a6e` | `#efd3c4` | `#d4d4d4` | 網點（4px 週期，1px 點） |
| 2 | 未滿 30 分 | `#7dd3fc` | `#0369a1` | `#dea08e` | `#a3a3a3` | 45° 單向斜線（4px 週期，1px 線） |
| 3 | 未滿 60 分 | `#38bdf8` | `#0ea5e9` | `#c85f4f` | `#525252` | 交叉斜線（4px 週期，1.5px 線） |
| 4 | 60 分以上 | `#0284c7` | `#7dd3fc` | `#b8362d` | `#000000` | 實心 |

- 方格 16px、間距 3px、圓角 2px（E-Ink 改 0、加 1px 黑框）；被選方格外框 2px（E-Ink 3px）、偏移 1px，且需提升層級（`z-index`）並在捲動容器左、右、下留 4px 內距，避免外框被裁切（Flutter 端繪製選取框時同樣要留出外擴空間）。
- 星期標籤欄寬 18px（含 4px 右內距，內容寬 14px），避免不同字型度量造成折行。
- E-Ink 下灰階值僅供參考，實際靠「黑框＋紋理」區分級別；灰階欄位供 Flutter 端 `ElinkTokens` 的 E-Ink 色值使用。
- 一週從週一開始；月份標籤置於方格上方，第一個標籤若與第二個相距不到 2 週則捨棄。
- 顯示規則：有紀錄但不滿 1 分鐘者顯示「1 分鐘」（避免出現「0 分鐘」；原型自訂規則，人類已確認接受）。
- 假資料：「重度」情境每日單書 65～154 分鐘；「一般」情境約 55% 的日子有紀錄，一天 1～3 本。

**驗證結果：**

自動化（本機執行，皆通過）：
- `node --test prototype/tests/stats_logic.test.js`：9 個測試全過（含 53 週／365 格、週一起始缺角、週日滿週、月份標籤不重疊、月份標籤第一個被捨棄／保留兩種情況、四情境假資料、五級 1～4 皆出現）。本機 Windows Node v24.19.0 的 `node --test prototype/tests/` 目錄形式會 `MODULE_NOT_FOUND`，一律使用明確檔名。
- 內嵌腳本語法檢查：`ok 3`。
- DOM-stub 功能檢查（**手動、一次性執行，腳本未納入版控，無法自動重現**；日後需要時請在瀏覽器手動操作原型，或另立工單補上可重現的 DOM 測試）：貢獻圖 365 格／6 透明佔位、預設選中今天、詳情排序與切換、無紀錄說明、四情境（一般／今天無紀錄／全空／重度）、清除確認全流程（取消不變／確認清空＋通知＋高亮切全空／重進仍空／切回一般復原）、無 Tooltip 機制，皆通過。
- 定案值逐字核對：19 個色值皆存在；Dark heat-0（`#2c2c34`）與深色底（`#1d1d22`）可區分；E-Ink 五紋理規則皆存在；方格顏色全走 CSS 變數（無行內色，主題切換無殘留，程式碼檢查確認）。

人類目視（agent 環境無瀏覽器，**未驗證**，待確認）：
- Light／Dark／Sepia／E-Ink 四組合的實際對比與美感；E-Ink 純黑白下五級可辨。
- 星期欄與方格列的像素對齊、單行不折行；被選外框四邊完整（右／下不被裁）。
- 橫向 640×480 版面；E-Ink 開關與主題切換的即時跟隨；清除鈕四主題按壓態。
- Review Focus 第 4 項（週日）已由自動化測試涵蓋；其餘視覺項同上待目視。

**人類確認（2026-09-29）：** 色階配色、E-Ink 紋理樣式、「不滿 1 分鐘顯示 1 分鐘」規則皆已目視確認定案，Issue 5 可以開始。

## Issue 2 完成記錄（資料層，2026-09-29，PR #297 已合併）

**做了什麼：** 新增每日閱讀統計的本機儲存。SQLite schema 升為 v27，新增 `daily_reading_stats` 表（主鍵 `(date, book_id)`、日期索引，**刻意不設外鍵**）；新增 `app/lib/stats/` 的 `DailyBookReadingStat`、`ReadingStatsRepository` 抽象介面與 `SqliteReadingStatsRepository`；新增共用測試替身 `FakeReadingStatsRepository`（`app/test/support/`）。**尚未接進 `main.dart`／`ReaderScreen`（Issue 4），使用者看不到行為變化。**

**計畫補充的決定（spec 未明說）：**
- `addReadingSeconds` 的 `seconds <= 0` 不做任何事（統計只增不減）。
- `getBookStatsForDate` 秒數相同時依書名、再依書籍 id 由小到大。
- `getDailyTotals` 的鍵依日期由早到晚（SQL `ORDER BY date ASC`；Fake 排序保證），避免兩種實作遍歷順序不一致。
- Fake 提供 `addReadingSecondsError`，供 Issue 4 驗證「寫入失敗不影響閱讀」。

**驗證結果：**
- `flutter analyze` 乾淨；資料層測試（`test/stats`＋替身測試）41 個全過；Fake 與 SQLite 共用同一組 17 個契約測試。
- 完整 `flutter test`（分支 HEAD `709d8f4b`）：3059 通過、1 略過（既有測試，未追查原因）、0 失敗。
- 程式審查（`reviews/review-issue-2.md`，不進版控）：Ready to merge，Critical 0、Important 0、Minor 2；審查者以四種突變（加外鍵、拿掉排序、累加改覆寫、多發一次事件）確認測試有效。

**已知限制（Minor 1，決定不修）：** 「`onCleared` 事件送達時資料已清空」的測試，抓不到「先發事件、後刪除」的順序寫反：刪除已先排進資料庫佇列，監聽者之後的查詢必然排在它後面。現行實作順序正確。

**給後續 Issue 的提醒：** Issue 4 需在 `main.dart` 以 `SqliteReadingStatsRepository(database: repository.database)` 建立實例，放進 `LibraryReaderFeatureRepositories`；Issue 3 的 tracker 訂閱的是 `ReadingStatsRepository.onCleared`。

## Issue 3 完成記錄（`ReadingStatsTracker`，2026-09-29，PR #298 已合併）

**做了什麼：** 新增 `app/lib/stats/reading_stats_tracker.dart`：每本書一個的會話級純 Dart 計時器（不 import Flutter，時鐘可注入）。三態狀態機、回溯採計、暫態時間不落地、30 秒寫入兼閒置看門狗、背景與 TTS 規則、時鐘防護、跨午夜切分、寫入串接與失敗重試、`onCleared` 歸零、`flushAndClose()`／`dispose()`。**尚未接進 `ReaderScreen`（Issue 4），使用者看不到行為變化。**

**計畫補充的決定（spec 未明說）：**
- **倒撥跨日**：記住「已見過的最晚日期」，早於它的日期一律不寫入。時鐘快轉後又校正回來，或向西跨時區，該次開書其後的秒數會被丟棄（下次開書重置）。審查 Minor 1，**決定維持現狀**。
- TTS 開始播放本身算一次活動（含開書後尚無活動時的回溯）。
- 進背景且 TTS 未播放時，連「開書後尚無活動」的回溯也一併作廢。
- 背景且 TTS 未播放時，`recordActivity()` 一律忽略（審查 Minor 2 修訂）；TTS 開始播放走內部 `_activity()`，背景中由通知欄開始播放仍算活動。
- 測試多拆一個檔：`reading_stats_tracker_background_test.dart`，與 `reading_stats_tracker_test.dart` 共用 `reading_stats_tracker_harness.dart`。

**驗證結果：**
- `flutter analyze` 乾淨；tracker 測試 48 個全過。
- 完整 `flutter test`（分支 HEAD `d5f9afbb`）：3107 通過、1 略過（既有測試，未追查原因）、0 失敗。
- 程式審查（`reviews/review-issue-3.md`，不進版控）：With fixes，Critical 0、Important 0、Minor 5；Minor 2、3、4 已修，Minor 1 維持現狀，Minor 5 為給 Issue 4 的提醒。審查時存活的 6 個突變（24、21、26、28、25、29）現在全被抓到；計畫的 8 個突變在修訂後重跑仍全被抓到。

**已知限制（不修）：**
- **清除當下在途的寫入**：`clearAllStats()` 在資料庫刪除完成後才發 `onCleared`；已送進資料庫佇列的那一批（至多 30 秒）仍會落地。tracker 無法取消已送出的寫入，只保證清除後新累積的秒數不受影響。
- **寫入失敗後無重試機會（審查 Minor 5）**：tracker 已 idle 或已關閉時，失敗的那批沒有「下一次」。

**給 Issue 4 的提醒：**
- 退出閱讀器時 `await`（或至少 `unawaited`）`flushAndClose()`，再 `dispose()`；不要只呼叫 `dispose()`，它不寫入。
- 由 `ReaderScreen` 把 `paused`／`resumed` 轉成 `onEnteredBackground()`／`onReturnedToForeground()`，TTS 狀態轉成 `onTtsPlayingChanged(bool)`。tracker 已自行忽略「背景且 TTS 未播放」時的 `recordActivity()`，但仍應避免在背景送事件。
- tracker 的寫入回呼失敗只記診斷日誌（`dart:developer`），不會拋出，不會影響閱讀。
- 寫入回呼簽章為 `(date, bookId, bookTitle, seconds)`，與 `ReadingStatsRepository.addReadingSeconds` 的具名參數不同，需自行轉接。

## Issue 4 完成記錄（`ReaderScreen` 接入計時，2026-09-29，PR #299 已合併）

**做了什麼：** 統計 repository 注入鏈路（`main.dart` → bundle → `buildReaderScreen` → `ReaderScreen`）；`ReaderScreen` 建立 `ReadingStatsTracker`，轉送 paused／resumed、TTS 播放狀態，退出時 `flushAndClose()` 結算；轉送閱讀活動（Foliate／PDF 位置回報、熱區翻頁、長按選取）。開書後第一次回報、同位置重複回報不算活動。**使用者仍看不到統計畫面（Issue 5）。**

- 程式審查已依報告修訂；完整 `flutter test` 3134 通過、1 跳過、0 失敗。
- 真機確認發現並修正 `fraction` 抖動問題，詳見下節。

### Issue 4 真機確認記錄（2026-09-29，`plan-issue-4.md` Task 4 Step 6）

裝置：`bfa4e772`（debug 版），以 `run-as` 匯出 `library.db` 查 `daily_reading_stats`。

- **測試 1（開書不動 30 秒）：首次失敗，修後通過。** 首次開書不動仍記了 42 秒。日誌顯示重排時同一 `cfi` 的 `fraction` 在 0.0064／0.0080 間來回抖動，字串整段比較把它當成翻頁。修法：`reader_screen.dart` 的 `_locatorPositionKey()` 只比 `cfi` 與 `index`（解析失敗退回整段字串），並新增測試「同一 cfi 只有進度小數抖動不算閱讀活動」。修後重測，該書時數不變。
- **測試 2（翻頁閱讀約 1 分鐘）：通過。** 修後重測兩本書各約 1 分鐘，各增加 58、57 秒。
- **測試 3（背景朗讀 1 分鐘）：通過。** 新書累計 79 秒，包含背景那段。
- **已知取捨：** 捲動模式下若 `cfi` 範圍不隨捲動改變、只有 `fraction` 變，該次捲動不算活動。未在真機驗證捲動模式。

## Issue 5 完成記錄（統計畫面，2026-09-29，PR #300 已合併）

**做了什麼：** 設定頁「閱讀統計」入口（`SettingsScaffold.readingStatsRepository`，null 時隱藏，由 `AdaptiveShellScaffold` 從 bundle 轉交）；`ReadingStatsScreen`（累計總時數、近 365 天貢獻圖、下方固定詳情卡片、底部清除全部＋確認對話框）；`ReadingHeatmap`（左側固定星期欄、右側水平捲動預設最右、月份標籤、五級 `CustomPaint` 方格、E-Ink 紋理＋選取外框疊加層、圖例）；`lib/stats/` 純邏輯（分級、週一起始網格、時數格式化）；`ElinkTokens.heatmapLevel0..4` 四套主題色值（取自 Issue 1 定案表）；14 個字串鍵進 4 份 ARB（含 gen-l10n 產出檔入版控）。

**計畫補充的決定（沿用 `plans/plan-issue-5.md`「已知取捨與偏離」，另加實作裁決 2 項）：**
- 透明佔位 Key 由全域單一改為 `heatmap_placeholder_<week>_<row>` 座標唯一鍵（末週 5 佔位同 Column 會觸發 duplicate-keys 斷言；測試以前綴 predicate 定位）。
- Task 4 測試 helper 結尾 `pump()` 改 `pumpAndSettle()`（同 testWidgets 內換主題重 pump 時，MaterialApp AnimatedTheme 需 200ms 才切換完成，否則讀到舊主題）。

**驗證結果：** `flutter analyze` 乾淨；`check_l10n_hardcoded_strings.js` 雙 PASS；完整 `flutter test` **3201 通過、1 跳過、0 失敗**（Issue 4 基準 3134＋本 Issue 新增 67，跳過數不變）；突變驗證 7/7 皆使對應測試失敗（已還原）。提交：`060b5cf9`（i18n）、`7b8b5b92`（Token）、`97fa4d9b`（純邏輯）、`24c14d8f`（貢獻圖元件）、`4f23b854`（統計畫面）、`b8b5784e`（設定頁入口）。

**程式審查修訂（2026-09-30，`c4838713`、`c2a5a79d`）：** 審查 0 Critical、2 Important、5 Minor，全數已修。I-2：拆分 `_loadRequestId` 與 `_detailRequestId`，清除重載期間點方格不再讓累計時數與貢獻圖停留在清除前；M-3：讀取失敗顯示 `statsLoadFailed`（新增第 15 個字串鍵，4 份 ARB）而非永遠停在 spinner；M-4：方格無障礙標籤加上當日時數；M-5：`statsNoDataOnDate` 統一為「紀錄」；I-1／M-1／M-2 補測試鎖住 E-Ink 紋理 `clipRect`、選取外框留白、E-Ink 對話框無淡入。新增測試皆以突變驗證。修訂後完整 `flutter test` **3207 通過、1 跳過、0 失敗**。

**真機確認：未驗證**（本機無 Android 裝置，僅 Edge web）。待真機補：E-Ink 第 3 級（`#525252` 底疊黑色交叉線）對比是否可辨（若不理想，依計畫改原型白底做法，只動 `HeatmapCellPainter.paint()`）、星期欄與捲動預設位置、清除流程、Light／Dark／Sepia 目視。

**已知限制：** 資料只在進入畫面與清除後載入（畫面開著時不即時更新、跨午夜不重算，下次進入更新）；清除失敗不特別處理（單句 `DELETE`，與同畫面其他資料庫呼叫一致）。

## 目前狀態

Discovery、Architecting（`spec.md`）、Scrum Master（`issues.md`，5 張，含審查修訂）皆完成。Issue 1（原型）、Issue 2（資料層）、Issue 3（tracker）、Issue 4（`ReaderScreen` 接入）、Issue 5（統計畫面）**五張全數完成，待歸檔**。
