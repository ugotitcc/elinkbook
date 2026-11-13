# Spec：閱讀統計

本規格依 `design.md`（含 2026-09-29 審查修訂）與 `CONTEXT.md` 詞彙撰寫，自此成為 `epic-9-stats` 的唯一事實來源。術語一律沿用 `CONTEXT.md`：**閱讀活動**、**每日閱讀統計**、**貢獻圖**。

## Problem Statement

使用者不知道自己讀了多久。App 目前完全沒有閱讀時間的紀錄，使用者無法回顧最近一年的閱讀習慣，也看不出哪幾天讀得多、哪幾本書花了最多時間。PRD FR-17（P2）要求依「實際閱讀活動」計時，排除閒置與背景時間，並用貢獻圖呈現近 365 天的閱讀活躍度。

計時本身有幾個不容易做對的地方：使用者常常開書後先讀一頁才翻頁、離開前最後一頁也沒有翻頁事件；聽書（TTS）時螢幕鎖定、App 在背景，但確實在「讀」；手機時鐘可能被倒撥；一段閱讀可能跨越午夜。

## Solution

從使用者的角度：

- 平常照常讀書，App 在背景默默累計每天、每本書的閱讀時間，使用者不需要按任何按鈕。
- 在設定頁進入「閱讀統計」，看到一張近 365 天的貢獻圖（每格代表一天，顏色深淺代表當天讀了多久）、累計總時數，以及貢獻圖下方顯示所選日期各書的閱讀時數。進入畫面時預設選中今天。
- 點選任一格，下方的詳情卡片切換成該日的各書時數，不會彈出浮動視窗。
- 貢獻圖可以左右捲動，一進畫面就停在最近的一週。
- 使用者可以清除全部統計（需確認）。
- 書被刪除後，過去的閱讀時數仍保留，詳情裡顯示當時的書名。
- E-Ink 模式下，貢獻圖不靠顏色，而是用灰階加紋理區分級別。

## User Stories

1. 身為讀者，我想要 App 自動記錄我每天的閱讀時間，這樣我不需要手動計時。
2. 身為讀者，我想要只有實際在讀的時間才被計入，這樣把書開著放在桌上不會灌高數字。
3. 身為讀者，我想要翻頁、捲動、長按劃線都算閱讀，這樣不同讀法都被如實記錄。
4. 身為讀者，我想要單純點一下螢幕叫出工具列不算閱讀，這樣誤觸不會產生時數。
5. 身為讀者，我想要開書後讀完第一頁才翻頁的那段時間也被算進去，這樣每次開書的第一頁不會被漏掉。
6. 身為讀者，我想要離開閱讀器前最後一頁的閱讀時間也被算進去，這樣讀到最後一頁就退出的時間不會消失。
7. 身為讀者，我想要開書後發呆超過 2 分鐘的空檔不被計入，這樣數字反映的是真正投入的時間。
8. 身為讀者，我想要開書看一眼就退出不產生時數，這樣誤開書不會留下紀錄。
9. 身為讀者，我想要聽書（TTS）時也算閱讀時間，這樣我戴耳機聽書的時間會被記錄。
10. 身為聽書的讀者，我想要螢幕鎖定或切到其他 App 時，只要朗讀還在進行就持續計時，這樣一小時的背景聽書不會變成 0 分鐘。
11. 身為聽書的讀者，我想要朗讀暫停、結束或睡眠定時器到期時，聽書時數就在那一刻結算，這樣不會多算也不會漏算。
12. 身為讀者，我想要一般閱讀時 App 進入背景就立即結算，這樣我切去回訊息的時間不會被算成閱讀。
13. 身為讀者，我想要跨過午夜的一段閱讀被拆到前後兩天，這樣每天的數字是準確的。
14. 身為讀者，我想要手機時間被校正、倒撥或時區變動時，我的累計時數不會變少或出現負數，這樣歷史資料不會被破壞。
15. 身為讀者，我想要手機時間被手動調快時，不會有一大段時間被灌進統計，這樣數字不會失真。
16. 身為讀者，我想要漫畫（CBZ）也被計時，這樣所有格式一視同仁。
17. 身為讀者，我想要 EPUB、PDF、TXT、MD、KF8 都被計時，這樣統計涵蓋我讀的所有書。
18. 身為讀者，我想要每 30 秒左右就有累計落地，這樣 App 被系統強制關閉時最多只損失很短的時間。
19. 身為讀者，我想要退出閱讀器時剩餘的累計立即寫入，這樣退出後馬上去看統計就是最新的數字。
20. 身為讀者，我想要在設定頁找到「閱讀統計」，這樣我知道去哪裡看。
21. 身為讀者，我想要看到近 365 天的貢獻圖，這樣我能一眼看出一整年的閱讀習慣。
22. 身為讀者，我想要每格顏色依當天總閱讀時數分成五級（0、未滿 15 分、未滿 30 分、未滿 60 分、60 分以上），這樣深淺差異有明確意義。
23. 身為讀者，我想要貢獻圖底下有圖例（較少到較多），這樣我知道顏色代表什麼。
24. 身為讀者，我想要貢獻圖一進畫面就停在最近的一週，這樣不用滑動就能看到今天。
25. 身為讀者，我想要可以左右捲動貢獻圖回看更早的日子，這樣手機直屏也看得到完整一年。
26. 身為讀者，我想要進入統計畫面時預設選中今天，這樣不用點擊就知道今天讀了多久。
27. 身為讀者，我想要今天沒有閱讀紀錄時看到「當日無閱讀記錄」的說明，這樣不會誤以為畫面壞了。
28. 身為讀者，我想要點選某一格就在貢獻圖下方看到該日各書的閱讀時數，這樣我知道那天讀了哪些書。
29. 身為讀者，我想要被選中的方格有明顯的外框標記，這樣我知道目前看的是哪一天。
30. 身為讀者，我想要詳情顯示在固定區塊而不是彈出視窗，這樣手指不會遮住內容，E-Ink 螢幕也不會殘影。
31. 身為讀者，我想要詳情裡的各書依閱讀時數由多到少排列，這樣最重要的書在最上面。
32. 身為讀者，我想要看到累計總閱讀時數，這樣我知道自己一共讀了多久。
33. 身為讀者，我想要時數以「X 小時 Y 分鐘」或「Y 分鐘」顯示，這樣好讀。
34. 身為讀者，我想要刪掉一本書後過去的時數仍然保留，這樣清理書架不會讓閱讀歷史消失。
35. 身為讀者，我想要被刪除的書在詳情裡仍顯示當時的書名，這樣我認得出那是哪一本。
36. 身為讀者，我想要書名被修改後統計顯示最新的書名，這樣資料不會殘留舊名稱。
37. 身為讀者，我想要可以清除全部閱讀統計，這樣我能重新開始或保護隱私。
38. 身為讀者，我想要清除前有確認對話框，這樣不會誤刪整年的資料。
39. 身為讀者，我想要清除後統計畫面立即回到空白狀態，這樣我知道已經清乾淨。
40. 身為讀者，我想要清除統計之後，剛才正在累計、還沒寫入的時間也一起被丟掉，這樣清除後今天不會又冒出數字。
41. 身為 E-Ink 裝置的使用者，我想要貢獻圖用灰階與紋理區分級別，這樣黑白螢幕上也看得出深淺。
42. 身為 E-Ink 裝置的使用者，我想要統計畫面沒有需要動畫或浮動層的互動，這樣不會出現殘影。
43. 身為使用深色或羊皮紙主題的讀者，我想要貢獻圖的顏色跟著主題調整，這樣畫面風格一致。
44. 身為使用英文或簡體中文介面的讀者，我想要統計畫面的所有文字都跟著介面語言，這樣看得懂。
45. 身為讀者，我想要統計只存在我的裝置上，這樣我的閱讀習慣不會被上傳。
46. 身為開發者，我想要計時邏輯是不依賴 Flutter 的純 Dart 類別，這樣能用單元測試確定性地驗證。
47. 身為開發者，我想要計時器的時鐘可以注入，這樣測試不需要真的等 2 分鐘。
48. 身為開發者，我想要 30 秒寫入計時器只在計時中存在，這樣 widget 測試不會出現殘留 Timer。
49. 身為開發者，我想要統計資料表不設外鍵，這樣刪除書籍不會失敗，歷史時數也不會被連帶刪除。
50. 身為開發者，我想要新的計時類別名稱不和既有的 `ReaderActivityTracker` 混淆，這樣自動匯入和程式碼審查不會出錯。

## Implementation Decisions

### 模組與職責

- **`ReadingStatsTracker`（新增，純 Dart）**：閱讀計時的唯一決策者，只知道「事件」和「時間」，不知道 Widget、資料庫或 WebView。負責三態狀態機、回溯採計、退出結算、背景 TTS 例外、時鐘防護、跨午夜切分與寫入節流。時鐘由外部注入（比照 `TapZoneDetector`，正式環境使用 `package:clock` 的 `clock.now()`）。它是**每本書一個的會話級實例**（持有 `bookId`、`bookTitle`），與既有全域單例 `ReaderActivityTracker`（只回答「目前是否有閱讀畫面開啟」，供全文檢索排程器使用）互不取代、互不依賴。
- **`ReadingStatsRepository`（新增，抽象介面）＋ SQLite 實作**：每日閱讀統計的存取，比照 `LibraryRepository` 的抽象介面加正式實作模式，測試可以用假實作。簽章見下方「核心介面」。
- **`ReaderScreen`（修改）**：只負責把事件餵給 tracker——翻頁、捲動、長按劃線各路徑（Foliate、PDF 兩條）的回報、TTS 狀態變化、`paused`／`resumed`、開書與退出——不包含任何計時邏輯。依賴注入方式見下方「依賴注入鏈路」。

### 核心介面

以下簽章為跨 Issue 的共同契約（Issue 2～5 分別實作或使用），實作時不得各自更改命名或參數順序。日期一律為 `YYYY-MM-DD` 本地日期字串。

```dart
class DailyBookReadingStat {
  final String bookId;
  final String bookTitle;
  final int readingSeconds;
  const DailyBookReadingStat({required this.bookId, required this.bookTitle, required this.readingSeconds});
}

abstract class ReadingStatsRepository {
  /// upsert 累加秒數，並以傳入書名覆寫快照。
  Future<void> addReadingSeconds({required String date, required String bookId, required String bookTitle, required int seconds});
  /// 日期區間（含起訖日）每日總秒數，key 為 YYYY-MM-DD；無紀錄的日期不出現。
  Future<Map<String, int>> getDailyTotals({required String startDate, required String endDate});
  /// 指定日期各書秒數，依秒數由大到小排序。
  Future<List<DailyBookReadingStat>> getBookStatsForDate(String date);
  Future<int> getTotalReadingSeconds();
  /// 清除全部後，透過 [onCleared] 廣播通知。
  Future<void> clearAllStats();
  /// 清除完成事件（廣播 Stream，可多個監聽者）。
  Stream<void> get onCleared;
}

typedef ReadingStatsFlush = Future<void> Function(String date, String bookId, String bookTitle, int seconds);

class ReadingStatsTracker {
  ReadingStatsTracker({required String bookId, required String bookTitle, required ReadingStatsFlush onFlush, Stream<void>? onCleared, Clock? clock});
  void recordActivity();              // 翻頁、捲動、長按劃線
  void onEnteredBackground();         // App paused
  void onReturnedToForeground();      // App resumed
  void onTtsPlayingChanged(bool isPlaying);
  Future<void> flushAndClose();       // 退出閱讀器：結算尾段、寫入、釋放計時器
  void dispose();
}
```

- tracker 刻意不使用 `AppLifecycleState` 與 `TtsPlaybackStatus`，維持「純 Dart、不依賴 Flutter」；由 `ReaderScreen` 負責把生命週期與 TTS 狀態轉成上述方法呼叫。
- tracker 建構時若收到 `onCleared`，訂閱後於事件到達時把記憶體內尚未寫入的秒數與暫態時間全部丟棄；`dispose()` 取消訂閱。

### 依賴注入鏈路

- `ReadingStatsRepository` 由 `main.dart` 建構（SQLite 實作），放進既有的 `LibraryReaderFeatureRepositories` bundle（新增可為 null 的欄位），沿用該 bundle 已貫穿所有開書路徑的做法。
- `buildReaderScreen()` 把 `features` 內的 repository 轉交給 `ReaderScreen`；書架、全庫搜尋、單書搜尋三個呼叫點因此自動取得，不需逐一修改。
- `ReaderScreen` 接受兩個可選參數：`readingStatsRepository`（正式環境）與 `readingStatsTracker`（測試直接注入）。`initState` 時：有 tracker 用 tracker；否則有 repository 就以本書的 `bookId`、書名與 repository 的寫入方法、`onCleared` 建立會話級 tracker；兩者皆無則不計時，行為與現況完全相同。
- `SettingsScaffold` 由 `LibraryScreen` 取得同一個 repository（同 bundle），用於開啟統計畫面；為 null 時設定頁不顯示「閱讀統計」項目。
- **統計畫面（新增）**：唯讀顯示貢獻圖、累計總時數、當日詳情，並提供清除全部。入口在設定頁。
- **`ElinkTokens`（修改）**：新增貢獻圖 5 級色階欄位，並補齊 Light、Dark、Sepia 與 E-Ink 修飾子的配色。

### 閱讀活動事件

- 算活動：翻頁、捲動、長按劃線、TTS 播放中。單純點擊叫出工具列不算。所有格式（含 CBZ）一視同仁。
- 閒置門檻為 2 分鐘，是產品常數，不開放使用者設定。

### 計時狀態機

三種狀態：`unverified`（剛開書、尚無活動）、`active`（閱讀中）、`idle`（已閒置、凍結）。

- 開書時進入 `unverified`，記錄開書時間，累計 0 秒。
- **首次活動**：若距開書不超過閒置門檻，把這段時間回溯採計後轉為 `active`；若超過，不回溯，轉為 `active`，從該次活動起算。
- **暫態時間與確認時間**：距最後一次活動經過的時間，在被後續事件確認之前只是「暫態時間」，**絕不寫入資料庫**。只有下列情況暫態時間才轉為「確認時間」，累入記憶體待寫入緩衝：
  1. 後續活動到達，且距上一次活動不超過閒置門檻——證明這段時間確實在讀，整段確認。
  2. 合法退出閱讀器（或非背景 TTS 的 `paused`），且距最後一次活動不超過閒置門檻——尾段確認。
  3. TTS 播放中——朗讀時間本身即為連續活動，持續確認。
- 距上一次活動**超過**閒置門檻的空檔視為閒置，**整段丟棄**（不是只截到門檻長度），並在下一次活動時重新起算。時鐘防護的單次上限只用來擋倒撥與快轉，不改變這條規則。
- **閒置看門狗**：計時中的定時器兼任閒置偵測。每次觸發若距最後一次活動已達閒置門檻（TTS 播放中除外），轉為 `idle`、丟棄暫態時間並取消定時器；使用者之後再次活動時回到 `active` 並重新建立定時器。
- **退出閱讀器**：`unverified` 狀態退出記 0 秒。
- **子秒精度**：內部一律以 `Duration` 累加，不逐次截為整數秒；只在把確認時間推入寫入緩衝時取整數秒，未滿 1 秒的餘額保留到下次累加（避免快速翻頁被截成 0 秒）。
- 已知限制：整段閱讀完全沒有活動事件時記 0 秒。

### 背景與 TTS

- 收到 `paused` 時：TTS 不是 `playing`，立即結算並要求寫入，結束該段；TTS 是 `playing`，不結束，進入背景計時。
- 背景計時中，TTS 轉為 `paused` 或 `idle`（含睡眠定時器到期、通知欄或耳機暫停）時結算並要求寫入。
- 背景計時中收到 `resumed` 且 TTS 仍在播放，無縫延續，不重複結算。
- TTS 播放中本身算活動，背景聽書不會被閒置門檻切掉。

### 時鐘防護與日期切分

- 所有時間差一律鉗位：小於 0 視為 0；單次計量不超過閒置門檻。時鐘倒撥或快轉永遠不會產生負值或巨量時數。
- 日期為裝置本地時區的日曆日，以午夜切分。當要確認的區間跨越午夜（上次活動時間與目前時間不在同一個日曆日，且間隔未超過閒置門檻）時，以目前時間所在日的本地午夜（該日 0 時 0 分 0 秒）為切分點：前一天記「午夜減上次活動時間」，當天記「目前時間減午夜」，分別對各自日期寫入一次。
- 偵測到目前日期早於計時段起始日期（倒撥跨日）時，只終止前段，不向過去日期寫入。

### 寫入策略

- 計時中每 30 秒把**已確認**的緩衝秒數寫入一次並歸零（暫態時間不寫，見上方狀態機）；退出閱讀器、非背景 TTS 的 `paused`、背景 TTS 結束時各補寫一次。TTS 播放中沒有活動事件，由這個 30 秒定時器持續把朗讀經過的時間轉為確認時間。
- 30 秒計時器按需啟動：只在 `active`（含背景 TTS）時存在，進入 `idle`、結算或釋放時立即取消（兼任閒置看門狗）。
- tracker 不直接依賴資料庫，透過注入的寫入回呼把確認秒數交給 repository。寫入回呼失敗時，該批秒數保留在緩衝，下次再試。

### 資料表（schema v27）

新增 `daily_reading_stats`，主鍵為（日期、書籍 id），欄位為本地日期（`YYYY-MM-DD` 文字）、書籍 id、書名快照、閱讀秒數、更新時間；另建日期索引。

```sql
CREATE TABLE daily_reading_stats (
  date TEXT NOT NULL,
  book_id TEXT NOT NULL,
  book_title TEXT NOT NULL,
  reading_seconds INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (date, book_id)
);
CREATE INDEX idx_daily_reading_stats_date ON daily_reading_stats(date);
```

- **嚴禁宣告外鍵**。連線全程開著 `PRAGMA foreign_keys = ON`，設 RESTRICT 會讓刪書失敗，設 CASCADE 會抹掉書刪除後應保留的時數。`book_id` 只是弱關聯的文字欄位。
- 寫入為 upsert：主鍵衝突時把秒數累加，同時以最新書名覆寫快照與更新時間。
- 「當日詳情」與「累計總時數」查詢**不得** JOIN `books`，直接讀本表，已刪除的書才能顯示名稱。
- 本表不進入雲端同步，主鍵設計保留日後同步時選擇「取最大值」或「加總」的空間。
- 遷移比照既有 schema 升級慣例，須遵守既有 `onUpgrade` 內對 `PRAGMA foreign_keys` 的處理限制。

### 清除全部統計

- 清除時刪除本表全部資料，完成後由 repository 的 `onCleared` 廣播通知所有作用中的 tracker，把記憶體內未落地的確認秒數與暫態時間全部丟棄，之後不得再寫入清除前的累計。不使用全域靜態變數；設定頁與閱讀器之間只透過 repository 溝通。

### 統計畫面

- 入口：設定頁新項目「閱讀統計」。
- 貢獻圖涵蓋近 365 天，排成約 53 週的方格陣列。**一週從週一開始**（第 0 列為週一、第 6 列為週日）；第一週週一之前與最後一週今天之後的格子畫成不可點擊的透明佔位。
- **版面為兩欄**：左側是固定的星期標籤欄（顯示「一、三、五」，不隨捲動移動）；右側是 53 週方格的水平捲動容器，月份標籤在方格上方、隨容器一起捲動。畫面建構完成後預設捲到最右側（今天所在的一週）。
- 分五級：0、未滿 15 分、未滿 30 分、未滿 60 分、60 分以上；以當日全部書籍的總時數判定。
- 不使用 Tooltip 或浮動層。選中的方格以高對比外框標示，詳情顯示在貢獻圖下方固定區塊；預設選中今天，今天沒有紀錄時顯示「當日無閱讀記錄」。詳情各書依時數由多到少排序。
- 圖例（較少到較多）顯示於貢獻圖下方。
- 累計總時數為 repository 提供的總和，以「X 小時 Y 分鐘」或「Y 分鐘」顯示。
- 「清除全部統計」在畫面底部，點擊後須經確認對話框（比照既有批次刪除需確認的慣例），成功後畫面回到空白狀態並提示。

### 主題與 E-Ink

- `ElinkTokens` 新增 5 級色階，Light、Dark、Sepia 各自配色，色值取自 Issue 1 原型定案，於 Issue 5 實作。
- `ElinkTokens` 只提供 5 級色值（`Color` 無法表達紋理）。`isEink` 為真時，色值改為階梯灰階，並由貢獻圖自己的繪製邏輯（自訂繪製）在部分級別的方格內畫斜線或網點紋理；哪幾級加紋理、紋理樣式由 Issue 1 原型定案。不依賴動畫。

### 國際化

- 統計畫面所有字串走 `AppLocalizations`，並需通過 `check_l10n_hardcoded_strings.js`。鍵名與佔位符在此定案，須同時補進 `app_zh_TW.arb`、`app_zh_CN.arb`、`app_en.arb`（並比照既有慣例處理 `app_zh.arb`）；簡體中文與英文為人工翻譯：

| ARB 鍵名 | 佔位符 | 正體中文 | 简体中文 | English |
|---|---|---|---|---|
| `statsScreenTitle` | 無 | 閱讀統計 | 阅读统计 | Reading Stats |
| `statsTotalDuration` | 無 | 累計閱讀時數 | 累计阅读时长 | Total Reading Time |
| `statsHoursMinutesFormat` | `{hours}`、`{minutes}` | {hours} 小時 {minutes} 分鐘 | {hours} 小时 {minutes} 分钟 | {hours} hr {minutes} min |
| `statsMinutesFormat` | `{minutes}` | {minutes} 分鐘 | {minutes} 分钟 | {minutes} min |
| `statsDailyDetailsTitle` | `{date}` | {date} 閱讀明細 | {date} 阅读明细 | Reading on {date} |
| `statsNoDataOnDate` | 無 | 當日無閱讀記錄 | 当日无阅读记录 | No reading on this day |
| `statsLegendLess` | 無 | 較少 | 较少 | Less |
| `statsLegendMore` | 無 | 較多 | 较多 | More |
| `statsClearAllTitle` | 無 | 清除全部統計 | 清除全部统计 | Clear All Stats |
| `statsClearAllConfirmMessage` | 無 | 確定要清除所有閱讀統計嗎？此動作無法復原。 | 确定要清除所有阅读统计吗？此操作无法撤销。 | Clear all reading stats? This cannot be undone. |
| `statsClearAllSuccess` | 無 | 已清除全部閱讀統計 | 已清除全部阅读统计 | All reading stats cleared |

  `{date}` 由呼叫端依介面語系格式化後傳入；星期標籤（一、三、五）與月份標籤同樣走 ARB，鍵名於 Issue 5 依上表慣例補齊（`statsWeekdayMon`、`statsWeekdayWed`、`statsWeekdayFri`、月份標籤沿用系統日期格式化）。

### 範圍與相依

- 「最後閱讀」排序沿用既有時間戳，不受本 Epic 影響。
- 開書當下不算活動，第一次活動才進入 `active`（回溯規則見上）。
- 計時、寫入失敗（例如資料庫錯誤）時不得影響閱讀本身：寫入失敗只記錄診斷資訊，不中斷閱讀器。

## Testing Decisions

### 什麼是好的測試

只測外部可觀察的行為：給定事件序列與時鐘，斷言累計秒數與寫入呼叫；給定資料庫操作，斷言查詢結果；給定資料與主題，斷言畫面呈現。不測私有欄位、內部狀態名稱或計時器的建立次數。

### 測試 seam（共 3 個）

1. **`ReadingStatsTracker` 公開介面（純 Dart 單元測試）**：以注入時鐘與 `fakeAsync` 驅動，涵蓋：
   - 三態狀態機：回溯採計（首次活動在門檻內／超過門檻）、後續活動累計、閒置空檔不計、退出結算（門檻內／超過）、誤開書退出記 0 秒。
   - 背景與 TTS：`paused` 且 TTS 非播放即結算；`paused` 且 TTS 播放中持續計時；背景中 TTS 暫停或結束即結算；`resumed` 且 TTS 仍播放不重複結算。
   - 時鐘：倒撥不產生負值、極端快轉單次不超過門檻、倒撥跨日不寫入過去日期、跨午夜切成兩天。
   - 寫入節流：30 秒寫入、計時器按需啟動與釋放（測試結束後無殘留 Timer）。
   - 暫態時間不落地：使用者放下手機發呆到轉為閒置，累計寫入的秒數只包含閒置前已被確認的部分；閒置後定時器已取消、不再寫入。
   - TTS 播放中沒有活動事件時，30 秒定時器仍持續確認並寫入朗讀時間。
   - 子秒精度：連續多次間隔小於 1 秒的活動，餘額累積後仍正確進位，不被截成 0。
   - 跨午夜：前後兩天各自的秒數等於午夜切分點前後的差值；間隔超過閒置門檻時不切分、直接丟棄。
   - 寫入回呼失敗時秒數保留、下次重試。
   - 收到 `onCleared` 後記憶體累計與暫態時間全部歸零，之後的寫入不含清除前的秒數。
2. **`ReadingStatsRepository`（SQLite 整合測試）**：upsert 累加、書名快照被最新書名覆寫、區間查詢、某日各書查詢、累計總和、清除全部；刪除書籍（`books` 表）後統計仍在且仍可查到書名；schema 由 v26 升級到 v27 後既有資料不受影響。
3. **統計畫面（widget test）**：貢獻圖分級對應、預設選中今天並顯示詳情、點選方格切換詳情、今天無紀錄顯示說明、水平捲動預設在最右側、清除全部需確認且確認後畫面清空、E-Ink 模式的級別可區分（紋理或灰階）、各主題下能正常渲染、繁中／簡中／英文字串齊備。

`ReaderScreen` 刻意不設獨立 seam。它只負責餵事件，行為由 seam 1 涵蓋；另用一個整合測試驗證「開書、翻頁、`paused` 後確實有資料落地」。**依賴注入鏈路**另以小型 widget test 驗證：`buildReaderScreen()` 會把 bundle 內的 repository 轉交給 `ReaderScreen`；僅注入 repository 時 `ReaderScreen` 會自行建立 tracker 並在翻頁後寫入；兩者皆未注入時完全不計時；`SettingsScaffold` 在 repository 為 null 時不顯示「閱讀統計」項目。
   - 統計畫面 widget test 另涵蓋：一週從週一開始的列對齊與首末週透明佔位、左側星期標籤欄不隨水平捲動移動。

### 既有做法可參照

- `TapZoneDetector` 測試：時鐘注入與純 widget 測試。
- `sqlite_library_repository_test.dart`：SQLite 行為與 schema 升級。
- `settings_scaffold_test.dart` 與各設定畫面測試：設定畫面 widget 測試，含 `MaterialApp` 補 locale。
- `tts_controller_test.dart`：以假 provider／player 驅動 TTS 狀態變化。

### 提交前檢查

- `flutter analyze` 必須乾淨；新增字串後執行 `node tool/check_l10n_hardcoded_strings.js`。
- 各 Issue 只跑實際觸及的測試檔，完整 `flutter test` 只在整張計畫最後一個 Task 完成時與準備合併前各跑一次。

## Out of Scope

- 跨裝置同步統計。
- 連續閱讀天數、每週目標、成就徽章。
- 統計圖片分享（屬 `epic-12-social`）。
- 統計資料匯出（Markdown 導出仍只含劃線、備註、書籤）。
- 單書統計清除。
- 逐次閱讀區段紀錄（只存每日每書彙總）。
- 閒置門檻與活動類型的使用者設定。
- 更動「最後閱讀」排序邏輯。

## Further Notes

- 本 Epic 不寫 ADR：資料表為衍生資料，計時器為純 Dart，兩者皆不難反轉，也沒有令人意外的取捨。
- 預定 Issue 切分（5 張）見 `design.md` 與 `issues.md`：原型 HTML、資料層、`ReadingStatsTracker`、接進 `ReaderScreen`、統計畫面（含 Token 與 i18n）。原型須先經人類確認才進 Flutter 實作。
- `prototype/elinkbook_theme_prototype.html` 與 `DESIGN.md` 目前沒有統計畫面與貢獻圖色階，色值以 Issue 1 原型為準。
- 已知限制：整段閱讀完全沒有活動事件（例如單頁 PDF 讀完直接退出）記為 0 秒，屬設計取捨。
