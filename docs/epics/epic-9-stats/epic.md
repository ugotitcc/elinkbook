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

## 目前狀態

Discovery、Architecting（`spec.md`）、Scrum Master（`issues.md`，5 張，含審查修訂）皆完成，待開發。
