# Epic 9 — 閱讀統計：工單清單 (Issues)

依 [spec.md](./spec.md)（唯一事實來源）拆成 5 個垂直切片。Issue 1 是設計關卡（原型），須經人類確認後 Issue 5 才能開始實作。Issue 2（資料層）與 Issue 3（計時器）互不相依，可以平行開發；Issue 4 把兩者接進閱讀器，之後就能靠資料庫驗證計時是否正確，不必等統計畫面。

```
Issue 1（原型）────────────────────────────────┐
                                               ├──> Issue 5（統計畫面）
Issue 2（資料層）──┬────────────────────────────┘
                   └──┐
                      ├──> Issue 4（接進 ReaderScreen）
Issue 3（Tracker）────┘
```

術語沿用 `CONTEXT.md`：**閱讀活動**、**每日閱讀統計**、**貢獻圖**。簽章與規則以 `spec.md`「核心介面」「實作決策」為準，本檔不重複。

**測試執行範圍：** 各 Issue 只跑異動實際觸及的測試檔；完整 `flutter test` 只在 Issue 4 完成時與 Issue 5 完成時各跑一次。每張提交前 `flutter analyze` 須乾淨；新增或修改畫面字串後執行 `node tool/check_l10n_hardcoded_strings.js`。

---

## Issue 1：原型 HTML——閱讀統計畫面與貢獻圖

**Status:** ready-for-agent

**Blocked by：** 無（可以馬上開始）。

**What to build：**
在 `prototype/elinkbook_theme_prototype.html` 新增「閱讀統計」畫面，並從設定畫面進得去。畫面包含：
- 近 365 天貢獻圖，一週從週一開始，左側固定的星期標籤欄（一、三、五）不隨水平捲動移動，月份標籤隨方格捲動；頁面載入後預設捲到最右側；首週與末週缺角處為不可點擊的透明佔位。
- 五級色階（0、未滿 15 分、未滿 30 分、未滿 60 分、60 分以上）與圖例（較少到較多）。
- 貢獻圖下方的固定詳情卡片：預設選中今天；點選方格以高對比外框標示並切換內容；當日無紀錄顯示「當日無閱讀記錄」；各書依時數由多到少。
- 累計總時數，以「X 小時 Y 分鐘」或「Y 分鐘」顯示。
- 底部「清除全部統計」與確認對話框、清除後的空白狀態。
- 需提供假資料（含一天讀多本書、一整年疏密不均、今天無紀錄的情境）供切換檢視。
- 在 Light、Dark、Sepia 與 E-Ink 修飾子下都要能切換檢視。E-Ink 下不靠色相：定案採用的灰階階梯，以及哪幾級加斜線或網點紋理、紋理樣式。

**驗收標準：**
- [ ] 上述所有元素都能在原型中操作，四種主題組合下版面與對比皆可讀。
- [ ] E-Ink 呈現的灰階值與紋理樣式在原型中明確定案（供 Issue 5 直接取值）。
- [ ] 沒有 Tooltip 或浮動層，詳情只出現在固定區塊。
- [ ] 人類確認原型後，Issue 5 才開始。

**測試要求：** 無自動化測試（HTML 原型）；以瀏覽器手動逐一切換四種主題組合驗證，結果記於 `epic.md`。

---

## Issue 2：資料層——每日閱讀統計儲存

**Status:** ready-for-agent

**Blocked by：** 無（可以馬上開始）。

**What to build：**
- SQLite schema 升為 v27，新增 `daily_reading_stats` 表（DDL 見 `spec.md`：主鍵為日期加書籍 id、書名快照、秒數、更新時間，日期索引），**不設外鍵**。升級遵守既有 `onUpgrade` 對 `PRAGMA foreign_keys` 的處理限制。
- `ReadingStatsRepository` 抽象介面與 `DailyBookReadingStat` 模型（簽章依 `spec.md`「核心介面」），以及 SQLite 實作：upsert 累加並覆寫書名快照、區間每日總計、單日各書（秒數由大到小）、累計總和、清除全部並透過 `onCleared` 廣播。
- 當日詳情與累計總和的查詢不得 JOIN `books`。
- 建立共用測試替身 `FakeReadingStatsRepository`（記憶體 Map 實作同一個抽象介面，含 upsert 累加、書名快照覆寫、區間查詢、排序、清除與 `onCleared` 廣播，並提供預先填入資料的輔助方法），供 Issue 4、Issue 5 共用，避免各自另寫互不相容的假物件。

**檔案位置（新增目錄 `app/lib/stats/`，讓平行開發的 Issue 2、3 不會各自放到不同模組）：**
- 模型 `app/lib/stats/daily_book_reading_stat.dart`、抽象介面 `app/lib/stats/reading_stats_repository.dart`、SQLite 實作 `app/lib/stats/sqlite_reading_stats_repository.dart`。
- 共用測試替身 `app/test/support/fake_reading_stats_repository.dart`；SQLite 測試 `app/test/stats/sqlite_reading_stats_repository_test.dart`。

**驗收標準：**
- [ ] `FakeReadingStatsRepository` 完整實作介面行為（upsert 累加、書名覆寫、區間查詢、排序、清除與 `onCleared` 廣播），可獨立用於單元與 widget 測試。
- [ ] 同日同書多次累加秒數相加；書名以最新一次寫入為準。
- [ ] 區間查詢只回傳有紀錄的日期，含起訖日；單日各書依秒數排序。
- [ ] 刪除 `books` 內的書之後，該書的統計時數與書名快照仍可查到，且刪書本身不受影響。
- [ ] `clearAllStats()` 清空資料並發出 `onCleared` 事件（多個監聽者皆收到）。
- [ ] 由 v26 升級到 v27 後既有資料完整，且新表存在；全新安裝直接建立 v27。

**測試要求：**
- 在 `sqlite_library_repository_test.dart` 同一套 SQLite 測試基礎上，新增 repository 測試檔（比照既有做法），涵蓋上述全部驗收標準，含「刪書後統計保留」與「v26 升 v27」。
- 替身本身也要有測試，斷言它的行為與 SQLite 實作一致（同一組案例對兩者各跑一遍），確保 Issue 4、5 用替身驗證的結果可信。
- 只跑異動觸及的測試檔（repository 新測試、既有 `sqlite_library_repository_test.dart`）。

---

## Issue 3：`ReadingStatsTracker`——純 Dart 計時器

**Status:** ready-for-agent

**Blocked by：** 無（可以馬上開始；只依賴寫入回呼與 `onCleared` 的 Stream，不需要真實 repository）。

**What to build：**
依 `spec.md` 實作 `ReadingStatsTracker`（簽章見「核心介面」），不依賴 Flutter、資料庫或 WebView，時鐘可注入。行為涵蓋：
- 三態狀態機：開書為 `unverified`；首次活動在門檻內則回溯採計，超過則從該次活動起算；後續活動確認間隔；超過閒置門檻的空檔整段丟棄。
- 暫態時間不落地；只有後續活動、合法退出、TTS 播放中三種情況才轉為確認時間；30 秒定時器把確認秒數寫入並兼任閒置看門狗（達門檻轉 `idle`、取消定時器）。
- 進入背景：TTS 非播放中立即結算寫入；播放中則持續背景計時，TTS 暫停或結束時結算；回到前景且仍在播放則無縫延續。
- 時鐘防護（倒撥視為 0、超過門檻丟棄、倒撥跨日不寫過去日期）、內部以 `Duration` 保留子秒精度、跨午夜以本地午夜切分兩天。
- 收到 `onCleared` 後丟棄記憶體累計與暫態時間；寫入回呼失敗時秒數保留下次重試。
- 提供 `Future<void> flushAndClose()`：退出閱讀器時呼叫，結算尾段、非同步寫入確認秒數並釋放計時器；`dispose()` 是同步方法，只用來取消訂閱與釋放資源，不得在其中執行非同步寫入。
- 計時器按需啟動，僅在計時中存在。

**檔案位置：** 計時核心 `app/lib/stats/reading_stats_tracker.dart`；測試 `app/test/stats/reading_stats_tracker_test.dart`。

**驗收標準：**
- [ ] 開書後 90 秒才翻頁再讀 80 秒退出，共記約 170 秒；開書後從未有活動就退出記 0 秒。
- [ ] 放下手機發呆超過門檻：寫入總量只含閒置前已確認的部分，之後不再寫入，定時器已取消。
- [ ] 進背景時 TTS 播放中持續計時並於 TTS 結束時結算；非播放中立即結算。
- [ ] 時鐘倒撥或快轉不產生負值或巨量秒數；跨午夜正確切成前後兩天。
- [ ] 連續多次小於 1 秒的間隔，餘額進位後總秒數正確。
- [ ] `flushAndClose()` 完成後尾段已寫入且計時器已釋放；其後再呼叫 `dispose()` 不會再寫入或拋例外。
- [ ] `onCleared` 之後不會寫入清除前的秒數；寫入失敗後下次成功重試；測試結束時無殘留 Timer。

**測試要求：**
- 新增 tracker 純 Dart 單元測試檔，以注入時鐘與 `fakeAsync` 驅動，涵蓋 `spec.md`「測試決策」seam 1 的全部案例（狀態機、背景與 TTS、時鐘、寫入節流、暫態不落地、TTS 持續確認、子秒、跨午夜、失敗重試、清除歸零）。
- 參照 `tap_zone_detector_test.dart` 的時鐘注入做法與 `tts_controller_test.dart` 的假物件做法。
- 只跑新測試檔。

---

## Issue 4：接進 `ReaderScreen` 並落地寫入

**Status:** ready-for-agent

**Blocked by：** Issue 2、Issue 3。

**What to build：**
- 依 `spec.md`「依賴注入鏈路」：`main.dart` 建構 SQLite 版 `ReadingStatsRepository` 並放進 `LibraryReaderFeatureRepositories`（新增可為 null 的欄位）；`buildReaderScreen()` 把它轉交給 `ReaderScreen`；`ReaderScreen` 新增選用參數 `readingStatsRepository` 與 `readingStatsTracker`，`initState` 時有 tracker 用 tracker，否則有 repository 就以本書 id、書名、repository 的寫入方法與 `onCleared` 建立會話級 tracker，兩者皆無則不計時、行為與現況完全相同。
- `ReaderScreen` 的其他建構點（例如單書搜尋內重建 bundle 的路徑）也要把 repository 一路帶下去，避免「閱讀器 → 單書搜尋 → 閱讀器」遺失。
- Foliate 與 PDF 兩條路徑把閱讀活動（翻頁、捲動、長按劃線）餵給 tracker；`paused`／`resumed` 轉為進入背景／回到前景；TTS 播放狀態變化轉為 `onTtsPlayingChanged`；退出閱讀器時結算並寫入。單純點擊叫出工具列不算活動；開書當下不算活動。
- `ReaderScreen` 內不得有任何計時邏輯，只負責轉送事件。

**驗收標準：**
- [ ] 從書架、全庫搜尋、單書搜尋三種入口開書，翻頁後都會計時並落地（各自有測試覆蓋，或以單一注入鏈路測試涵蓋 `buildReaderScreen()`）。
- [ ] 僅注入 repository 時自動建立 tracker；僅注入 tracker 時直接使用；兩者皆無時完全不計時。
- [ ] 開書、翻頁、進入背景後，repository（widget 測試用 `FakeReadingStatsRepository`）出現當日該書的紀錄；不依賴真機即可驗收。
- [ ] 背景 TTS 播放中進入背景不結算，TTS 結束才寫入。
- [ ] 點擊叫出工具列不產生時數；開書後立即退出不產生時數。
- [ ] 寫入失敗不影響閱讀（閱讀器不崩潰、不顯示錯誤）。

**測試要求：**
- 注入鏈路與生命週期 widget test（新增 `app/test/screens/reader_screen_stats_test.dart`，這是本 Issue 的驗收依據，無真機也能跑）：以 `FakeReadingStatsRepository` 注入，驗證 `buildReaderScreen()` 轉交 repository、僅注入 repository 時建立 tracker、翻頁活動轉送、模擬 `paused`／`resumed` 時的寫入與不寫入、TTS 狀態轉送、退出閱讀器時 `flushAndClose()` 的寫入，以及兩者皆未注入時完全不計時。
- 整合測試（`integration_test/reader_stats_test.dart`，需 `-d <device-id>` 真機）：開書、翻頁、進背景後資料庫有紀錄。屬有真機時的選用驗證，不阻擋無裝置環境完成本 Issue。
- 跑既有 `reader_screen_test.dart`、`reader_screen_route_test.dart`、`library_screen_dependencies_test.dart`、`library_search_screen_test.dart`、`book_search_screen_test.dart`、`library_screen_test.dart`，證明既有行為不變。
- **本 Issue 動到 `ReaderScreen`，完成時跑一次完整 `flutter test`**，確認零回歸。

---

## Issue 5：統計畫面——貢獻圖、詳情、主題 Token 與 i18n

**Status:** ready-for-agent

**Blocked by：** Issue 1（原型定案並經人類確認）、Issue 2。

**What to build：**
- 依 Issue 1 原型實作「閱讀統計」畫面與設定頁入口：`SettingsScaffold` 從同一個 bundle 取得 repository，為 null 時不顯示該項目。
- 貢獻圖：近 365 天、週一起始、左側固定星期標籤欄、右側水平捲動並預設在最右側、首末週透明佔位、五級分級（以當日全部書籍總時數判定）、圖例。
- 貢獻圖下方固定詳情卡片：預設選中今天，無紀錄顯示「當日無閱讀記錄」；點選方格切換並以高對比外框標示；各書依時數由多到少，已刪除的書顯示書名快照；不使用 Tooltip 或浮動層。
- 累計總時數，以「X 小時 Y 分鐘」或「Y 分鐘」顯示。
- 「清除全部統計」置於底部，經確認對話框，成功後畫面回到空白狀態並提示。
- **主題 Token**：`ElinkTokens` 新增 5 級色階，Light、Dark、Sepia 各自配色，色值取自原型；`isEink` 為真時改為階梯灰階，並由貢獻圖自己的繪製邏輯在原型定案的級別畫斜線或網點紋理。
- **i18n**：`spec.md` 表列 11 個鍵與星期標籤鍵，須同步加入 **4 份 ARB**：`app_zh_TW.arb`（範本，含 `@` 說明區塊）、`app_zh.arb`（中文通用退路，內容同正體中文）、`app_zh_CN.arb`、`app_en.arb`。修改後必須執行 `cd app && flutter gen-l10n` 重新產生 `app_localizations*.dart`，產出檔案有納入版控、須一併提交；再執行 `node tool/check_l10n_hardcoded_strings.js`。所有字串走 `AppLocalizations`。

**檔案位置：** 畫面 `app/lib/screens/reading_stats_screen.dart`；貢獻圖元件 `app/lib/screens/widgets/reading_heatmap.dart`；測試 `app/test/screens/reading_stats_screen_test.dart`。

**Widget Key 契約（供測試定位，沿用 `settings_*_button` 既有命名慣例）：**
- 設定頁入口：`settings_reading_stats_button`
- 貢獻圖水平捲動元件：`reading_stats_heatmap`
- 當日詳情卡片：`reading_stats_daily_detail_card`
- 清除全部統計按鈕：`reading_stats_clear_all_button`
- 確認對話框的確認／取消按鈕：`reading_stats_clear_all_confirm_button`、`reading_stats_clear_all_cancel_button`

**建議實作順序（範疇不變，供實作或寫計畫時分階段，降低單次上下文過長的風險）：**
1. 4 份 ARB、`flutter gen-l10n`、`ElinkTokens` 擴充與 Token 測試。
2. 貢獻圖元件（網格與 E-Ink 紋理繪製、固定星期標籤欄、水平捲動與預設在最右側）。
3. 詳情卡片、累計總時數、清除全部確認流程。
4. `SettingsScaffold` 整合、統計畫面組裝、完整 widget 測試。

**驗收標準：**
- [ ] 貢獻圖分級對應正確（0、未滿 15、未滿 30、未滿 60、60 分以上各一格）；一週從週一開始，首末週有透明佔位。
- [ ] 進入畫面預設選中今天並顯示詳情；點選其他方格更新詳情；無紀錄顯示說明文字。
- [ ] 星期標籤欄不隨水平捲動移動；畫面預設捲到最右側。
- [ ] 已刪除書籍的時數在詳情裡仍以書名快照顯示；累計總時數等於全部紀錄加總。
- [ ] 清除全部需確認；確認後畫面清空、repository 資料清空；取消則不變。
- [ ] 四種主題組合皆能正常渲染；E-Ink 下五級可區分（灰階加紋理），不依賴色相。
- [ ] repository 為 null 時設定頁不顯示「閱讀統計」項目。
- [ ] 4 份 ARB 皆已加入所有鍵，`flutter gen-l10n` 已執行且產出檔案已納入提交，`check_l10n_hardcoded_strings.js` 通過。

**測試要求：**
- 統計畫面 widget test（比照 `settings_scaffold_test.dart` 的 `MaterialApp` 補 locale 做法，使用 Issue 2 產出的 `FakeReadingStatsRepository`）：涵蓋上述全部驗收標準，含五級分級、週一對齊、星期欄固定、清除確認流程、E-Ink 呈現、繁中／簡中／英文三種介面語言。測試一律以上方 Widget Key 定位，不依賴文字比對。
- `ElinkTokens` 測試：各主題五級色值存在，E-Ink 五級可區分。
- 設定頁測試：repository 為 null 時不顯示項目。
- 跑既有 `settings_scaffold_test.dart` 與主題相關測試確認不回歸；真機目視確認貢獻圖在直屏的水平捲動與 E-Ink 呈現。
- **完成時跑一次完整 `flutter test`**，再準備發 PR。
