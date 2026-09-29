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

## 目前狀態

Discovery、Architecting（`spec.md`）、Scrum Master（`issues.md`，5 張，含審查修訂）皆完成。Issue 1（原型）、Issue 2（資料層）已完成，待開發 Issue 3～5：Issue 3 可立即開始；Issue 4 依賴 Issue 2、3；Issue 5 依賴 Issue 1、2。
