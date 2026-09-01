# Epic 36 — 三目的地導覽／書架下鑽強化／設定四分區：Discovery

## 緣起與範圍界定

依 `elinkBook-uiux-audit.dc.html` 第 5～8 節與多輪 `/grill-with-docs` 定案，`DESIGN.md` 已更新 §11（導覽）、§15（圖書庫與書架）、§17（設定畫面，新增章節）。本 Epic 是這些規範落地到 `app/lib` 的實作端，並修正過程中發現的三處 `DESIGN.md` 自身內部矛盾（詳見下方「已解決的規格矛盾」）。完整討論過程記錄於 `docs/research/uiux/eink-redesign-rebuild-plan.md`（含原型 `prototype/elinkbook_theme_prototype.html` 的驗證結果），本文件只整理落地到程式碼所需的結論。

依循 `UI_DESIGN_RULES.md`：本 Epic 只碰 Navigation／Library UI／Settings UI／Bottom sheets／Dialogs／Layout，不碰 OPDS／WebDAV／雲端來源實作、書籍儲存、閱讀進度持久化等核心架構清單項目。每個 Issue 的 `plan-issue-N.md` 動手改程式碼前，須先說明：(1) 改哪個 UI 元件 (2) 為什麼要改 (3) 哪些畫面依賴它 (4) 是否影響 business logic。

## 現有程式碼現況（決定了本 Epic 是「從無到有」還是「修正既有」）

- **導覽架構：從無到有。** `main.dart` 目前 `home: LibraryScreen(...)`，畫面切換靠各畫面自己的 AppBar 按鈕＋`Navigator.push`，完全沒有 `NavigationBar`／`NavigationRail`／`AdaptiveScaffold`。§11.1 的三目的地標題列圖示導覽（書架／來源／設定互相跳轉、平板走 `NavigationRail`）是本 Epic 要新蓋的部分。
- **書架長按批次選取：已存在，沿用。** `library_screen.dart` 已有 `_selectedBookIds`／`onLongPress` 驅動的多選模式（移動分類／移除快取／刪除），跟 §15.1「長按維持多選（不改為單書動作選單）」的定案相容，不需重做。
- **書架分類下鑽：已存在，需強化。** 現行程式碼已用 `_buildBookList()` 把分類拼貼格與書籍混排在同一個 `GridView`（見 `CLAUDE.md` 對 `LibraryScreen` 的既有描述），符合 §11.2「保留」的決策；本 Epic 要做的是疊加：換頁控制列（`PagingBar`，取代目前推測是無限捲動的呈現方式，需在 Issue 規劃時實測確認現況）、繼續閱讀列、「⋮」單書動作選單。
- **設定畫面：已存在，需重分區＋補項目。** `settings_screen.dart`（256 行）已有主題圓點與 E-Ink 開關（見 `epic-35` design.md），但不是 §17.1 定義的四分區結構（外觀／閱讀／同步與帳號／關於），且缺「朗讀語音與語速」項目、「關於」獨立區塊。

## 本次落地範圍（依 `DESIGN.md` 章節）

1. **§11.1／11.2 導覽**：三目的地標題列圖示導覽（書架／來源／設定），手機寬度不用底部導覽列；平板／桌機走 `NavigationRail`（規格沿用既有 §11.1 未變動部分，本 Epic 不重新設計斷點邏輯本身，只確保手機寬度的圖示改動落地）。
2. **§15.1／15.2 書架**：繼續閱讀列（常駐顯示最近閱讀書籍與進度）、換頁控制列 `PagingBar`（52dp／觸控 48dp、E-Ink 56dp，取代無限捲動）、單書「⋮」動作選單（`EBSheetShell` 包裹：詳細資料／移動／版面覆寫／移除快取／刪除，移除快取限遠端書庫書籍——重用既有批次操作的同一組底層邏輯，不重寫）、AppBar 改三圖示（排序/檢視、來源、設定，取消「＋」/FAB）。
3. **§17 設定**：四分區重排（外觀含主題選擇＋E-Ink 開關＋字型管理；閱讀含閱讀預設值／顯示頁首頁尾／翻頁與熱區／朗讀語音與語速；同步與帳號；關於）；主題選擇器沿用 `epic-35` 落地的 `ElinkTokens`。

## 明確排除於本 Epic 之外

- **來源畫面統一（`SourceBrowser`，§16）**：`DESIGN.md` §16 本身沒有新決策要交付（這次只在原型裡示範了假資料麵包屑，`DESIGN.md` 文字未變動），且牽涉 `OpdsServerProvider`／雲端 Provider，屬於 `UI_DESIGN_RULES.md` 明文禁止本輪碰的「OPDS/WebDAV/雲端來源實作」風險區。留在 `DESIGN.md` §19 階段四 Backlog，不含在本 Epic。
- **閱讀器 Chrome／TTS 重構（§12／§13）**：多輪 grilling 已明確決定「既有 2b/2c 閱讀器、2d 版面設定四分頁原封不動」，本 Epic 不動。

## 已解決的規格矛盾（落地時無需再確認，直接照此執行）

1. 書架分類**維持下鑽**，不採用稽核報告建議的篩選晶片（見 `DESIGN.md` §11.2／§19 階段三註記）。
2. 書本卡片**長按＝多選**（沿用既有），**⋮ 圖示＝單書動作選單**——兩者不共用手勢（見 §15.1）。
3. AppBar 匯入「＋」與 FAB 兩案皆已淘汰，統一併入「來源」目的地（見 §15.2）。

## 下一步

Architecting：撰寫 `spec.md`，定義 `PagingBar`／單書動作 Sheet／設定四分區的元件介面與依賴（`ElinkTokens`、既有批次操作邏輯）。待 `epic-35` 歸檔、`ElinkTokens` 穩定合併後，進 Scrum Master 階段拆 `issues.md`。粗估切法：Issue 1（三目的地導覽架構，含平板 `NavigationRail`）、Issue 2（書架繼續閱讀列＋`PagingBar`）、Issue 3（書架單書「⋮」動作選單）、Issue 4（設定畫面四分區重排＋新增朗讀語音與語速／關於區塊）。
