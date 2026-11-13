# Design：閱讀統計

## 問題陳述

App 目前不知道使用者讀了多久。PRD FR-17 要求以實際閱讀活動計時，並用貢獻圖呈現近 365 天的閱讀情況。術語定義見 `CONTEXT.md`：**閱讀活動**、**每日閱讀統計**、**貢獻圖**。

## 決策紀錄

### 1. 閱讀活動判定與計時（Q1、Q10、Q11；2026-09-29 審查 C-1、C-2、I-2 修訂）

**算活動**：翻頁、捲動、長按劃線、TTS 播放中。單純點擊叫出工具列不算。所有格式一視同仁（含 CBZ）。

**閒置門檻**：2 分鐘（產品常數，不開放設定）。

**三態狀態機**（取代原「第一次活動才起算、閒置只計到最後一次活動」的字面規則，該規則會漏計每次開書的第一頁與離開前的最後一頁）：

| 狀態 | 意義 |
|---|---|
| `unverified` | 剛開書，記錄開書時間 `T_open`，累計 0 秒 |
| `active` | 已確認閱讀中，持有最近一次活動時間 `T_last` |
| `idle` | 已超過閒置門檻，計時凍結 |

- **首次活動**（`T_first`）：若 `T_first - T_open` ≤ 2 分鐘，把這段時間**回溯採計**，轉為 `active`；若超過 2 分鐘（開書後發呆），不回溯，轉為 `active`，自 `T_first` 起算。
- **活動累計**：每次活動事件，若距上一次活動不超過閒置門檻，把這段間隔確認並累加；超過門檻的空檔視為閒置，整段丟棄。未被後續事件確認的「暫態時間」絕不寫入資料庫（詳見 `spec.md`）。
- **退出結算**（離開閱讀器）：`active` 狀態下，若距 `T_last` 不到 2 分鐘，把這段記入；超過則不補。`unverified` 狀態退出（開書後從未有任何活動）記 0 秒，這保留了「只查看一下就離開不產生時數」的原始需求。
- **已知限制**：整段閱讀完全沒有活動事件（例如單頁 PDF 讀完直接退出）記為 0 秒。

**背景與 TTS 例外**：
- `paused` 時檢查 TTS：狀態非 `TtsPlaybackStatus.playing`（純視覺閱讀）→ 立即結算並寫入，結束該段。
- `paused` 時 TTS 為 `playing`（PRD FR-45 支援背景播放；`audio_service` 為前景服務）→ **不結束**，轉入背景計時；TTS 轉為 `paused` 或 `idle`（含睡眠定時器到期、通知欄或耳機暫停）時才結算並寫入。
- 背景計時期間 App 回到前景（`resumed`）且 TTS 仍在播放，無縫延續，不重複結算。
- TTS 播放中本身就算活動，所以背景聽書不會被 2 分鐘閒置門檻切掉。

**時鐘防護**（審查 I-2）：
- 時長一律鉗位：差值小於 0 視為 0；超過閒置門檻的間隔一律丟棄，不會因時鐘快轉灌入巨量時數。系統時間倒撥或快轉永遠不會產生負值或巨量時數。
- 日期以本地 `clock.now()` 判定；偵測到日期早於目前計時段起始日期（倒撥跨日）時，只終止前段，不向過去日期寫入。
- 跨午夜的一段閱讀依裝置本地時區午夜切開，分記兩天（每次累計時比對日期，不同日先結算前一天）。
- 單元測試須含「時鐘倒撥」與「極端快轉」案例，斷言累計值不為負。

### 2. 資料模型與儲存（Q2、Q3、Q4；審查 I-1）

- 粒度：每日每書彙總，不做逐次閱讀區段。本機儲存，不跨裝置同步；主鍵保留 `(date, book_id)`，供日後同步選擇「取最大值」或「加總」。
- SQLite schema 升為 v27，DDL 契約：

```sql
CREATE TABLE daily_reading_stats (
  date TEXT NOT NULL,            -- 本地日期 YYYY-MM-DD
  book_id TEXT NOT NULL,         -- 弱關聯，不設外鍵
  book_title TEXT NOT NULL,      -- 書名快照
  reading_seconds INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (date, book_id)
);
CREATE INDEX idx_daily_reading_stats_date ON daily_reading_stats(date);
```

- **嚴禁**宣告 `FOREIGN KEY (book_id) REFERENCES books(id)`：連線全程開著 `PRAGMA foreign_keys = ON`，設 RESTRICT 會讓刪書失敗，設 CASCADE 會抹掉「書刪除後保留時數」的歷史。
- 寫入為 upsert 累加，同時覆寫書名快照，使未刪除的書永遠反映最新書名：

```sql
INSERT INTO daily_reading_stats (date, book_id, book_title, reading_seconds, updated_at)
VALUES (?, ?, ?, ?, ?)
ON CONFLICT(date, book_id) DO UPDATE SET
  reading_seconds = daily_reading_stats.reading_seconds + excluded.reading_seconds,
  book_title = excluded.book_title,
  updated_at = excluded.updated_at;
```

- 「當日詳情」與累計總時數的查詢**嚴禁** JOIN `books`，直接讀 `daily_reading_stats.book_title`，已刪除的書才能正確顯示名稱。

### 3. 計時器架構與寫入（Q8、Q9；審查 M-1、M-2、M-3）

- 獨立純 Dart 類別 **`ReadingStatsTracker`**（不叫 `ReadingActivityTracker`，避免與既有 `app/lib/reader/reader_activity_tracker.dart` 的 `ReaderActivityTracker` 僅差一字而混淆；後者只負責「是否有閱讀畫面開啟」給全文檢索排程器用，兩者互不取代）。每本書一個會話級實例，經 `ReaderScreen` 依 repository 建立，介面簽章見 `spec.md`。
- 只接收活動事件、`paused`／`resumed`、TTS 狀態，輸出秒數；時鐘以 `package:clock` 注入（比照 `TapZoneDetector`）。`ReaderScreen` 只負責餵事件。
- 寫入時機：每 30 秒把已確認的秒數寫一次（兼任 2 分鐘閒置看門狗），加上退出閱讀器、`paused`（非背景 TTS 時）、背景 TTS 結束時各補寫一次。
- 30 秒計時器**按需啟動**：只在 `active`（含背景 TTS）時存在，進入 `idle`、結算或 `dispose()` 時立即 `cancel()`，避免 `testWidgets` 出現殘留 Timer。tracker 須能純以 `fakeAsync.elapse()` 驅動測試。
- 「清除全部統計」須同步把作用中 tracker 記憶體內未落地的累計秒數歸零，否則之後的 flush 會讓當日資料復活。
- 「最後閱讀」排序沿用既有時間戳，不動（Q12）。

### 4. 統計畫面（Q5、Q6、Q7、Q13；審查 I-3、I-4）

- 入口：設定頁新項目「閱讀統計」。
- 內容：365 天貢獻圖、當日詳情、累計總時數、底部「清除全部統計」（需確認對話框）。
- 貢獻圖分 5 級：0、未滿 15 分、未滿 30 分、未滿 60 分、60 分以上。
- **版面**：365 天約 53 週，寬度超過手機直屏。一週從週一開始；左側為固定不捲動的星期標籤欄，右側為水平捲動容器，畫面建構完成後**預設捲到最右側**（今天所在週）。
- **詳情卡片**：不使用 Tooltip 或彈出層（E-Ink 殘影、手指遮擋）。點選方格以高對比外框標記，並在貢獻圖**下方固定區塊**顯示該日各書時數；進入畫面預設選中今天（無紀錄顯示「當日無閱讀記錄」）。
- **主題 Token**：`ElinkTokens` 新增 `heatmapLevel0`～`heatmapLevel4`，Light／Dark／Sepia 各自配色。E-Ink 修飾子啟用（`isEink == true`）時改用階梯灰階並輔以斜線或網點紋理，不只靠色相區分。
- **i18n**：字串走 `AppLocalizations`（須通過 `node tool/check_l10n_hardcoded_strings.js`）。預定 ARB 鍵：`statsScreenTitle`、`statsTotalDuration`、`statsHoursMinutesFormat(hours, minutes)`、`statsMinutesFormat(minutes)`、`statsDailyDetailsTitle(date)`、`statsNoDataOnDate`、`statsLegendLess`、`statsLegendMore`、`statsClearAllTitle`、`statsClearAllConfirmMessage`、`statsClearAllSuccess`；正式鍵名於 Architecting 定案。
- 原型 HTML 先補上統計畫面（含 E-Ink 呈現與詳情卡片），經人類確認後才進 Flutter 實作。

## 範圍外（Q14）

- 跨裝置同步
- 連續閱讀天數、每週目標、成就徽章
- 統計圖片分享（屬 `epic-12-social`）
- 統計資料匯出（Markdown 導出目前只含劃線、備註、書籤）
- 單書統計清除

## Issue 切分（2026-09-29 `/to-tickets` 定案，共 5 張）

1. 原型 HTML：統計畫面與貢獻圖（含 E-Ink 呈現、詳情卡片）。
2. 資料層：schema v27、`daily_reading_stats` 表、repository 的 upsert 累加與區間查詢、清除全部。
3. `ReadingStatsTracker`：純 Dart，涵蓋三態狀態機、回溯採計、退出結算、TTS 背景例外、時鐘倒撥與快轉防護、跨午夜切分、按需 30 秒計時器、清除時歸零；不接畫面。
4. 接進 `ReaderScreen`（Foliate 與 PDF 兩條路徑餵事件、TTS 狀態、`paused`／`resumed`）並落地寫入。
5. 統計畫面：`ElinkTokens` 貢獻圖色階與 i18n 字串、水平捲動貢獻圖、Inline 詳情卡片、累計總時數、清除全部；設定頁入口（Token 與 i18n 原為獨立 Issue，2026-09-29 併入本 Issue）。

不寫 ADR：資料表可重建、計時器為純 Dart，皆不難反轉，也無令人意外的取捨。

## 開放問題

無。
