# Epic 9 Issue 5：統計畫面——貢獻圖、詳情、主題 Token 與 i18n — 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在設定頁新增「閱讀統計」畫面：近 365 天貢獻圖（週一起始、左側固定星期欄、右側水平捲動並預設在最右側）、固定詳情卡片、累計總時數、清除全部統計（含確認對話框），並補齊 `ElinkTokens` 五級色階與 4 份 ARB 字串，使 Issue 2～4 累計下來的資料第一次能被使用者看見。

**Architecture:**
- **純邏輯與畫面分離**：分級、日期網格、月份標籤、時數格式化放在 `app/lib/stats/` 的純 Dart 檔（可不掛 Widget 直接單元測試）；貢獻圖元件 `ReadingHeatmap` 只負責把網格畫出來（`CustomPaint` 逐格繪製，E-Ink 下自行畫網點／斜線紋理，選取外框用獨立的疊加層繪製以免被鄰格蓋住）；`ReadingStatsScreen` 負責載入資料、選取狀態與清除流程。
- **入口與注入**：`SettingsScaffold` 新增選用參數 `readingStatsRepository`（null 時不顯示項目），由 `AdaptiveShellScaffold` 從既有 `readerFeatureRepositories.readingStatsRepository` 轉交（Issue 4 已把 repository 放進該 bundle，本 Issue 不動 `main.dart`）。
- **Token 與 i18n**：`ElinkTokens` 新增 `heatmapLevel0`～`heatmapLevel4`，四套主題各自定案值（取自 `epic.md` Issue 1 定案表）；14 個字串鍵（`spec.md` 表列 11 個＋星期標籤 3 個）同步進 4 份 ARB。

**Tech Stack:** Flutter／Dart 3、`flutter_test`（`testWidgets`、`paints` matcher）、`intl`（`DateFormat`）、`package:clock`、既有 `FakeReadingStatsRepository`（`app/test/support/`）與 `pumpLocalizedWidget`。

**Spec:** [`../spec.md`](../spec.md)（「統計畫面」「主題與 E-Ink」「國際化」「測試決策」seam 3）、[`../issues.md`](../issues.md) Issue 5、[`../epic.md`](../epic.md)「Issue 1 完成記錄」的**定案值表**（色值、紋理、尺寸的唯一來源）；視覺參照 `prototype/elinkbook_theme_prototype.html` 的 `STATS-LOGIC` 區塊與「畫面 F：閱讀統計」。

## Global Constraints

- 貢獻圖涵蓋「今天往前 365 天」（含今天），一週從**週一**開始（第 0 列週一、第 6 列週日），首週週一之前與末週今天之後的格子畫成**不可點擊的透明佔位**。
- 五級分級依「當日全部書籍總時數」：`0`、未滿 15 分、未滿 30 分、未滿 60 分、60 分以上；邊界秒數為 `1..899 → 1`、`900..1799 → 2`、`1800..3599 → 3`、`≥3600 → 4`。
- 版面兩欄：左側固定星期標籤欄（「一、三、五」，不隨捲動移動），右側水平捲動容器（月份標籤在方格上方、隨方格捲動），畫面載入後預設捲到最右側。
- 尺寸（取自原型）：方格 16px、間距 3px、圓角 2px（E-Ink 改 0＋1px 黑框）；選取外框 2px（E-Ink 3px）、偏移 1px；捲動容器左、右、下留 4px 內距避免外框被裁；星期欄寬約 18px（含 4px 右內距）。
- **不使用 Tooltip 或任何浮動層顯示詳情**（詳情只在貢獻圖下方固定卡片）；不依賴動畫（E-Ink 友善）。清除確認對話框在 E-Ink 下 `animationStyle: AnimationStyle.noAnimation`。
- 詳情各書依秒數由多到少（repository 已排序，畫面不重排）；已刪除書籍直接顯示書名快照；當日無紀錄顯示 `statsNoDataOnDate`。
- 時數顯示：`X 小時 Y 分鐘`／`Y 分鐘`；有紀錄但不滿 1 分鐘者顯示「1 分鐘」（原型定案、人類已確認）；完全沒有紀錄（0 秒）顯示「0 分鐘」。
- 所有使用者可見字串走 `AppLocalizations`；4 份 ARB（`app_zh_TW.arb` 範本含 `@` 說明、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`）鍵名與佔位符以 `spec.md` 表為準，修改後必須執行 `cd app && flutter gen-l10n`，**產出的 `app_localizations*.dart` 一併提交**。
- 新增測試的 `MaterialApp` 一律經 `pumpLocalizedWidget`（補 locale）；測試以 Widget Key 定位，不依賴文字比對（驗證 i18n 字串本身、時數格式時除外）。
- 不改動 `ReadingStatsRepository`／`ReadingStatsTracker`／`FakeReadingStatsRepository` 的公開簽章（Issue 2、3、4 已合併）。
- 程式碼註解一律使用正體中文；提交前 `flutter analyze` 須乾淨；提交訊息結尾附 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- 只跑異動觸及的測試檔；**最後一個 Task 跑一次完整 `flutter test`**（本 Issue 動到 `ElinkTokens` 建構子與 `SettingsScaffold`，波及面廣）。

## Review Focus

以下是 spec 隱含、但主要驗收條件沒有直接涵蓋，最可能讓使用者踩到的情況（最可能的在前）：

1. **英文介面的星期標籤（`Mon`／`Wed`／`Fri`）塞不進 18px 固定寬欄**：折行或溢位會讓星期欄與方格列錯位、或丟出 overflow 例外。→ Task 4 用 `IntrinsicWidth`＋單行不折行＋`TextScaler.noScaling`，並以英文 locale 測試「無例外、標籤與同列方格頂端對齊」。
2. **快速連續點選兩個方格，先點的那次查詢較晚回來**：舊結果蓋掉新選取，詳情顯示成前一天。→ Task 5 以請求序號丟棄過期結果，並用「先點 A（查詢被卡住）、再點 B、最後放行 A」的測試鎖住。
3. **全新安裝、完全沒有任何紀錄**：畫面必須正常顯示（總時數「0 分鐘」、全部方格第 0 級、今天顯示「當日無閱讀記錄」），不可因空 Map 例外。→ Task 5 「空資料」測試。
4. **一年以前的舊紀錄**：不會出現在貢獻圖（沒有對應方格），但累計總時數要計入（`spec.md`：累計總時數＝repository 總和）。→ Task 5 「視窗外舊資料」測試。
5. **超長書名（例如 200 字、無空白）**：詳情列不可溢位。→ Task 5 「超長書名」測試（`Expanded`＋自動換行）。

另在 Task 3 用閏日（`2028-02-29`）與「今天恰為週日」兩種邊界鎖住網格計算；DST 由「以 `DateTime(y, m, d + n)` 做日期運算、以 UTC 日期計算天數差」構造性避開（測試機時區若無 DST 則測不到，屬已知限制）。

## 已知取捨與偏離（請審查者留意）

- **入口接線位置與 `spec.md` 字面不同**：`spec.md`「依賴注入鏈路」寫「`SettingsScaffold` 由 `LibraryScreen` 取得同一個 repository」，實際上 `SettingsScaffold` 是在 `AdaptiveShellScaffold`（`adaptive_shell_scaffold.dart:134`）建構，與其他設定項目取自 `readerFeatureRepositories` 同一處。本計畫沿用實況，在 `AdaptiveShellScaffold` 轉交。
- **E-Ink 方格底色**：`epic.md` 定案表明訂 E-Ink 灰階值供 `ElinkTokens` 使用，並同時說明「灰階僅供參考，實際靠黑框＋紋理區分」；原型 CSS 實際是「白底＋黑紋理」。本計畫依 `issues.md` 字面——Token 存灰階（`#ffffff／#d4d4d4／#a3a3a3／#525252／#000000`），畫面以 Token 灰階為底、再疊黑色紋理與黑框。第 3 級（`#525252` 底）疊 1.5px 黑線對比偏弱，**需在真機目視確認（Task 6 Step 7）**；若不理想，改成原型的「第 0–3 級白底、第 4 級黑底」只需改 `HeatmapCellPainter.paint()` 一處（不影響 Token 與其他程式）。
- **確認對話框的確認鈕文字**：`spec.md` 字串表沒有獨立的「清除」按鈕鍵。依 `DESIGN.md` §9.2「主動作按鈕文字需標明具體後果」，確認鈕直接重用 `statsClearAllTitle`（「清除全部統計」），取消鈕重用既有 `cancel`，不新增鍵。
- **設定頁項目不加副標題**：原型的設定項目有副標題「近 365 天的閱讀時數與貢獻圖」，但 `spec.md` 表列 11 個鍵沒有它；為不擴充已定案的鍵集合，Flutter 端只用 `statsScreenTitle` 當項目標題（其他設定項目在 Flutter 端本來也多半沒有副標題）。
- **清除失敗不特別處理**：`clearAllStats()` 只是一句 SQLite `DELETE`，spec 沒有失敗情境；不加 try/catch，與同畫面其他資料庫呼叫一致。
- **資料載入只在進入畫面時進行**：畫面關閉再開會重新載入；畫面開著時不會因閱讀器寫入而即時更新（閱讀器與統計畫面不會同時存在於前景）。跨午夜不重算「今天」（下次進入才更新）。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb` | 修改 | 新增 14 個統計字串鍵 |
| `app/lib/l10n/app_localizations*.dart` | 重新產生 | `flutter gen-l10n` 的產出，納入版控 |
| `app/lib/theme/elink_tokens.dart` | 修改 | 新增 `heatmapLevel0`～`4`、`heatmapLevelColor(int)` |
| `app/lib/theme/app_theme_data.dart` | 修改 | 四套主題填入五級色值 |
| `app/lib/stats/heatmap_grid.dart` | 新增 | 純 Dart：分級、日期鍵、週一起始網格、月份標籤 |
| `app/lib/stats/reading_duration_format.dart` | 新增 | `formatReadingDuration(l10n, seconds)` |
| `app/lib/screens/widgets/reading_heatmap.dart` | 新增 | 貢獻圖元件、方格與選取外框繪製、星期欄、圖例 |
| `app/lib/screens/reading_stats_screen.dart` | 新增 | 統計畫面、詳情卡片、清除確認流程 |
| `app/lib/screens/settings_scaffold.dart` | 修改 | 新參數與「閱讀統計」入口 |
| `app/lib/screens/adaptive_shell_scaffold.dart` | 修改 | 轉交 `readingStatsRepository` |
| `app/test/l10n/stats_l10n_test.dart` | 新增 | 三語言（含 `zh` 退路）字串齊備 |
| `app/test/theme/elink_tokens_heatmap_test.dart` | 新增 | 五級色值、可區分性、`copyWith`／`lerp` |
| `app/test/theme/elink_tokens_test.dart`、`app/test/reader/highlight_style_test.dart` | 修改 | 建構子新增必填欄位後的既有測試補欄位 |
| `app/test/stats/heatmap_grid_test.dart` | 新增 | 網格與分級單元測試 |
| `app/test/stats/reading_duration_format_test.dart` | 新增 | 時數格式化 |
| `app/test/screens/reading_heatmap_test.dart` | 新增 | 元件層 widget 測試 |
| `app/test/screens/reading_stats_screen_test.dart` | 新增 | 畫面層 widget 測試（本 Issue 主要驗收依據） |
| `app/test/screens/settings_scaffold_reading_stats_test.dart` | 新增 | 設定頁入口與 shell 轉交 |

（`issues.md` 只指定 `reading_stats_screen.dart`、`reading_heatmap.dart`、`reading_stats_screen_test.dart` 三個檔案；這裡依「純邏輯／元件／畫面」拆出兩個 `lib/stats/` 純 Dart 檔與元件層測試，讓每個檔案聚焦。）

以下所有指令都在 `app/` 目錄下執行（`cd C:\Users\fycdc\AI\elinkBook\app`）。

---

### Task 1：4 份 ARB 與 `flutter gen-l10n`

**Files:**
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app/lib/l10n/app_zh.arb`、`app/lib/l10n/app_zh_CN.arb`、`app/lib/l10n/app_en.arb`
- Regenerate: `app/lib/l10n/app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart`
- Test: `app/test/l10n/stats_l10n_test.dart`

**Interfaces:**
- Consumes: 無。
- Produces（`AppLocalizations` 新增成員，後續 Task 直接使用）：
  - `String statsScreenTitle`、`statsTotalDuration`、`statsNoDataOnDate`、`statsLegendLess`、`statsLegendMore`、`statsClearAllTitle`、`statsClearAllConfirmMessage`、`statsClearAllSuccess`、`statsWeekdayMon`、`statsWeekdayWed`、`statsWeekdayFri`
  - `String statsHoursMinutesFormat(int hours, int minutes)`
  - `String statsMinutesFormat(int minutes)`
  - `String statsDailyDetailsTitle(String date)`

- [x] **Step 1: 建立分支**

```bash
git switch -c epic-9/issue-5-stats-screen
```

- [x] **Step 2: 寫失敗測試**

建立 `app/test/l10n/stats_l10n_test.dart`：

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';

void main() {
  test('正體中文（zh_TW）統計字串齊備', () {
    final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
    expect(l10n.statsScreenTitle, '閱讀統計');
    expect(l10n.statsTotalDuration, '累計閱讀時數');
    expect(l10n.statsHoursMinutesFormat(1, 5), '1 小時 5 分鐘');
    expect(l10n.statsMinutesFormat(7), '7 分鐘');
    expect(l10n.statsDailyDetailsTitle('2026/9/29'), '2026/9/29 閱讀明細');
    expect(l10n.statsNoDataOnDate, '當日無閱讀記錄');
    expect(l10n.statsLegendLess, '較少');
    expect(l10n.statsLegendMore, '較多');
    expect(l10n.statsClearAllTitle, '清除全部統計');
    expect(l10n.statsClearAllConfirmMessage, '確定要清除所有閱讀統計嗎？此動作無法復原。');
    expect(l10n.statsClearAllSuccess, '已清除全部閱讀統計');
    expect(l10n.statsWeekdayMon, '一');
    expect(l10n.statsWeekdayWed, '三');
    expect(l10n.statsWeekdayFri, '五');
  });

  test('中文通用退路（zh）與正體中文內容相同', () {
    final l10n = lookupAppLocalizations(const Locale('zh'));
    expect(l10n.statsScreenTitle, '閱讀統計');
    expect(l10n.statsHoursMinutesFormat(2, 0), '2 小時 0 分鐘');
    expect(l10n.statsDailyDetailsTitle('X'), 'X 閱讀明細');
    expect(l10n.statsWeekdayFri, '五');
  });

  test('簡體中文（zh_CN）統計字串齊備', () {
    final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));
    expect(l10n.statsScreenTitle, '阅读统计');
    expect(l10n.statsTotalDuration, '累计阅读时长');
    expect(l10n.statsHoursMinutesFormat(1, 5), '1 小时 5 分钟');
    expect(l10n.statsMinutesFormat(7), '7 分钟');
    expect(l10n.statsDailyDetailsTitle('2026/9/29'), '2026/9/29 阅读明细');
    expect(l10n.statsNoDataOnDate, '当日无阅读记录');
    expect(l10n.statsLegendLess, '较少');
    expect(l10n.statsLegendMore, '较多');
    expect(l10n.statsClearAllTitle, '清除全部统计');
    expect(l10n.statsClearAllConfirmMessage, '确定要清除所有阅读统计吗？此操作无法撤销。');
    expect(l10n.statsClearAllSuccess, '已清除全部阅读统计');
    expect(l10n.statsWeekdayMon, '一');
    expect(l10n.statsWeekdayWed, '三');
    expect(l10n.statsWeekdayFri, '五');
  });

  test('英文（en）統計字串齊備', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(l10n.statsScreenTitle, 'Reading Stats');
    expect(l10n.statsTotalDuration, 'Total Reading Time');
    expect(l10n.statsHoursMinutesFormat(1, 5), '1 hr 5 min');
    expect(l10n.statsMinutesFormat(7), '7 min');
    expect(l10n.statsDailyDetailsTitle('9/29/2026'), 'Reading on 9/29/2026');
    expect(l10n.statsNoDataOnDate, 'No reading on this day');
    expect(l10n.statsLegendLess, 'Less');
    expect(l10n.statsLegendMore, 'More');
    expect(l10n.statsClearAllTitle, 'Clear All Stats');
    expect(
      l10n.statsClearAllConfirmMessage,
      'Clear all reading stats? This cannot be undone.',
    );
    expect(l10n.statsClearAllSuccess, 'All reading stats cleared');
    expect(l10n.statsWeekdayMon, 'Mon');
    expect(l10n.statsWeekdayWed, 'Wed');
    expect(l10n.statsWeekdayFri, 'Fri');
  });
}
```

- [x] **Step 3: 執行測試確認失敗**

Run: `flutter test test/l10n/stats_l10n_test.dart`
Expected: FAIL（編譯錯誤：`The getter 'statsScreenTitle' isn't defined for the type 'AppLocalizations'`）

- [x] **Step 4: 寫入 `app_zh_TW.arb`（範本，含 `@` 說明區塊）**

先用 Read 看檔案最後幾行（最後一個鍵是 `wifiPageUploadTimeout` 及其 `@` 區塊），把最後一個 `}` 之前那個區塊的結尾 `}` 補上逗號，然後在最後的 `}` 之前加入：

```json
  "statsScreenTitle": "閱讀統計",
  "@statsScreenTitle": {
    "description": "閱讀統計畫面標題，同時作為設定頁「閱讀統計」入口的標籤"
  },
  "statsTotalDuration": "累計閱讀時數",
  "@statsTotalDuration": {
    "description": "閱讀統計畫面「累計總時數」卡片的標題"
  },
  "statsHoursMinutesFormat": "{hours} 小時 {minutes} 分鐘",
  "@statsHoursMinutesFormat": {
    "description": "時數顯示（滿 1 小時）：{hours} 為小時數、{minutes} 為剩餘分鐘數（0–59）",
    "placeholders": {
      "hours": {
        "type": "int"
      },
      "minutes": {
        "type": "int"
      }
    }
  },
  "statsMinutesFormat": "{minutes} 分鐘",
  "@statsMinutesFormat": {
    "description": "時數顯示（未滿 1 小時）：{minutes} 為分鐘數",
    "placeholders": {
      "minutes": {
        "type": "int"
      }
    }
  },
  "statsDailyDetailsTitle": "{date} 閱讀明細",
  "@statsDailyDetailsTitle": {
    "description": "當日詳情卡片標題，{date} 為已依目前介面語言格式化的日期字串（DateFormat.yMd(locale) 的結果）",
    "placeholders": {
      "date": {
        "type": "String"
      }
    }
  },
  "statsNoDataOnDate": "當日無閱讀記錄",
  "@statsNoDataOnDate": {
    "description": "當日詳情卡片在該日沒有任何閱讀紀錄時顯示的說明文字"
  },
  "statsLegendLess": "較少",
  "@statsLegendLess": {
    "description": "貢獻圖圖例左端文字（色階較淺＝閱讀較少）"
  },
  "statsLegendMore": "較多",
  "@statsLegendMore": {
    "description": "貢獻圖圖例右端文字（色階較深＝閱讀較多）"
  },
  "statsClearAllTitle": "清除全部統計",
  "@statsClearAllTitle": {
    "description": "「清除全部統計」按鈕文字，同時是確認對話框的標題與確認鈕文字（DESIGN.md §9.2：確認鈕需標明具體後果）"
  },
  "statsClearAllConfirmMessage": "確定要清除所有閱讀統計嗎？此動作無法復原。",
  "@statsClearAllConfirmMessage": {
    "description": "清除全部統計確認對話框的內文"
  },
  "statsClearAllSuccess": "已清除全部閱讀統計",
  "@statsClearAllSuccess": {
    "description": "清除全部統計成功後的提示訊息（SnackBar）"
  },
  "statsWeekdayMon": "一",
  "@statsWeekdayMon": {
    "description": "貢獻圖左側星期標籤欄：星期一（週一列）"
  },
  "statsWeekdayWed": "三",
  "@statsWeekdayWed": {
    "description": "貢獻圖左側星期標籤欄：星期三（週三列）"
  },
  "statsWeekdayFri": "五",
  "@statsWeekdayFri": {
    "description": "貢獻圖左側星期標籤欄：星期五（週五列）"
  }
```

- [x] **Step 5: 寫入 `app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`（無 `@` 區塊）**

三個檔案都比照上一步：Read 檔尾、前一個鍵補逗號、在最後的 `}` 之前加入。

`app_zh.arb`（內容與正體中文相同）：

```json
  "statsScreenTitle": "閱讀統計",
  "statsTotalDuration": "累計閱讀時數",
  "statsHoursMinutesFormat": "{hours} 小時 {minutes} 分鐘",
  "statsMinutesFormat": "{minutes} 分鐘",
  "statsDailyDetailsTitle": "{date} 閱讀明細",
  "statsNoDataOnDate": "當日無閱讀記錄",
  "statsLegendLess": "較少",
  "statsLegendMore": "較多",
  "statsClearAllTitle": "清除全部統計",
  "statsClearAllConfirmMessage": "確定要清除所有閱讀統計嗎？此動作無法復原。",
  "statsClearAllSuccess": "已清除全部閱讀統計",
  "statsWeekdayMon": "一",
  "statsWeekdayWed": "三",
  "statsWeekdayFri": "五"
```

`app_zh_CN.arb`：

```json
  "statsScreenTitle": "阅读统计",
  "statsTotalDuration": "累计阅读时长",
  "statsHoursMinutesFormat": "{hours} 小时 {minutes} 分钟",
  "statsMinutesFormat": "{minutes} 分钟",
  "statsDailyDetailsTitle": "{date} 阅读明细",
  "statsNoDataOnDate": "当日无阅读记录",
  "statsLegendLess": "较少",
  "statsLegendMore": "较多",
  "statsClearAllTitle": "清除全部统计",
  "statsClearAllConfirmMessage": "确定要清除所有阅读统计吗？此操作无法撤销。",
  "statsClearAllSuccess": "已清除全部阅读统计",
  "statsWeekdayMon": "一",
  "statsWeekdayWed": "三",
  "statsWeekdayFri": "五"
```

`app_en.arb`：

```json
  "statsScreenTitle": "Reading Stats",
  "statsTotalDuration": "Total Reading Time",
  "statsHoursMinutesFormat": "{hours} hr {minutes} min",
  "statsMinutesFormat": "{minutes} min",
  "statsDailyDetailsTitle": "Reading on {date}",
  "statsNoDataOnDate": "No reading on this day",
  "statsLegendLess": "Less",
  "statsLegendMore": "More",
  "statsClearAllTitle": "Clear All Stats",
  "statsClearAllConfirmMessage": "Clear all reading stats? This cannot be undone.",
  "statsClearAllSuccess": "All reading stats cleared",
  "statsWeekdayMon": "Mon",
  "statsWeekdayWed": "Wed",
  "statsWeekdayFri": "Fri"
```

- [x] **Step 6: 重新產生 l10n 並確認簽章**

Run: `flutter gen-l10n`
Expected: 無錯誤；`lib/l10n/app_localizations*.dart` 有變更。

Run: `grep -n "String statsHoursMinutesFormat\|String statsMinutesFormat\|String statsDailyDetailsTitle" lib/l10n/app_localizations.dart`
Expected: 看到 `String statsHoursMinutesFormat(int hours, int minutes);`、`String statsMinutesFormat(int minutes);`、`String statsDailyDetailsTitle(String date);`。若參數順序與此不同，以產出檔案為準，並同步修正 Task 3 的 `formatReadingDuration()` 呼叫。

- [x] **Step 7: 執行測試確認通過**

Run: `flutter test test/l10n/stats_l10n_test.dart test/l10n/app_localizations_generated_test.dart`
Expected: PASS

- [x] **Step 8: 靜態檢查與提交**

Run: `flutter analyze`
Expected: `No issues found!`

```bash
git add lib/l10n test/l10n/stats_l10n_test.dart
git commit -m "feat(stats): epic-9 Issue 5 新增統計畫面 14 個 i18n 字串（4 份 ARB）" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：`ElinkTokens` 五級色階

**Files:**
- Modify: `app/lib/theme/elink_tokens.dart`
- Modify: `app/lib/theme/app_theme_data.dart`
- Modify: `app/test/theme/elink_tokens_test.dart`
- Modify: `app/test/reader/highlight_style_test.dart`
- Test: `app/test/theme/elink_tokens_heatmap_test.dart`

**Interfaces:**
- Consumes: 無。
- Produces：
  - `ElinkTokens` 新增五個 `final Color`：`heatmapLevel0`、`heatmapLevel1`、`heatmapLevel2`、`heatmapLevel3`、`heatmapLevel4`（建構子皆為 `required`）。
  - `Color ElinkTokens.heatmapLevelColor(int level)`：`level` 為 `0..4`，超出範圍拋 `RangeError`。
  - `copyWith`／`lerp` 涵蓋五個新欄位。

- [x] **Step 1: 寫失敗測試**

建立 `app/test/theme/elink_tokens_heatmap_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/app_theme_data.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

ElinkTokens _tokensOf(ThemeData theme) => theme.extension<ElinkTokens>()!;

List<Color> _levels(ElinkTokens t) => [
      t.heatmapLevel0,
      t.heatmapLevel1,
      t.heatmapLevel2,
      t.heatmapLevel3,
      t.heatmapLevel4,
    ];

void main() {
  group('四套主題的五級色值（epic.md Issue 1 定案表）', () {
    test('Light', () {
      expect(_levels(_tokensOf(buildThemeData(AppTheme.light))), const [
        Color(0xFFEAF1F5),
        Color(0xFFBAE6FD),
        Color(0xFF7DD3FC),
        Color(0xFF38BDF8),
        Color(0xFF0284C7),
      ]);
    });

    test('Dark', () {
      expect(_levels(_tokensOf(buildThemeData(AppTheme.dark))), const [
        Color(0xFF2C2C34),
        Color(0xFF0C4A6E),
        Color(0xFF0369A1),
        Color(0xFF0EA5E9),
        Color(0xFF7DD3FC),
      ]);
    });

    test('Sepia', () {
      expect(_levels(_tokensOf(buildThemeData(AppTheme.sepia))), const [
        Color(0xFFE6DFCB),
        Color(0xFFEFD3C4),
        Color(0xFFDEA08E),
        Color(0xFFC85F4F),
        Color(0xFFB8362D),
      ]);
    });

    test('E-Ink：階梯灰階', () {
      expect(_levels(_tokensOf(buildEinkThemeData())), const [
        Color(0xFFFFFFFF),
        Color(0xFFD4D4D4),
        Color(0xFFA3A3A3),
        Color(0xFF525252),
        Color(0xFF000000),
      ]);
    });
  });

  test('四套主題各自的五級色值彼此不同（E-Ink 灰階可區分，不依賴色相）', () {
    for (final theme in [
      buildThemeData(AppTheme.light),
      buildThemeData(AppTheme.dark),
      buildThemeData(AppTheme.sepia),
      buildEinkThemeData(),
    ]) {
      expect(_levels(_tokensOf(theme)).toSet().length, 5);
    }
  });

  test('Dark 第 0 級與深色底 surface 可區分（0 級方格看得見）', () {
    final theme = buildThemeData(AppTheme.dark);
    expect(_tokensOf(theme).heatmapLevel0, isNot(theme.colorScheme.surface));
  });

  test('E-Ink 灰階由淺到深單調遞減', () {
    final levels = _levels(_tokensOf(buildEinkThemeData()));
    final lum = [for (final c in levels) c.computeLuminance()];
    for (var i = 1; i < lum.length; i++) {
      expect(lum[i], lessThan(lum[i - 1]));
    }
  });

  test('heatmapLevelColor 依級別取值，超出 0–4 拋 RangeError', () {
    final t = _tokensOf(buildThemeData(AppTheme.light));
    for (var i = 0; i < 5; i++) {
      expect(t.heatmapLevelColor(i), _levels(t)[i]);
    }
    expect(() => t.heatmapLevelColor(5), throwsRangeError);
    expect(() => t.heatmapLevelColor(-1), throwsRangeError);
  });

  test('copyWith 只覆寫指定的色階欄位；lerp 在 t=0.5 走 Color.lerp', () {
    final light = _tokensOf(buildThemeData(AppTheme.light));
    final dark = _tokensOf(buildThemeData(AppTheme.dark));
    final copy = light.copyWith(heatmapLevel3: const Color(0xFF123456));
    expect(copy.heatmapLevel3, const Color(0xFF123456));
    expect(copy.heatmapLevel0, light.heatmapLevel0);
    expect(copy.heatmapLevel4, light.heatmapLevel4);

    final mid = light.lerp(dark, 0.5);
    expect(mid.heatmapLevel2,
        Color.lerp(light.heatmapLevel2, dark.heatmapLevel2, 0.5));
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/theme/elink_tokens_heatmap_test.dart`
Expected: FAIL（編譯錯誤：`The getter 'heatmapLevel0' isn't defined for the type 'ElinkTokens'`）

- [x] **Step 3: 修改 `elink_tokens.dart`**

在 `ttsActiveHighlight` 欄位後新增欄位、建構子參數、`copyWith`、`lerp`，並新增取值方法（完整改動）：

```dart
  final Color ttsActiveHighlight;

  /// 閱讀統計貢獻圖五級色階（epic-9-stats Issue 5，色值取自 `epic.md`
  /// Issue 1 原型定案表）：0 無紀錄、1 未滿 15 分、2 未滿 30 分、
  /// 3 未滿 60 分、4 六十分以上。E-Ink 下為階梯灰階；`Color` 無法表達紋理，
  /// 網點／斜線由貢獻圖元件自己的繪製邏輯疊加（見 `reading_heatmap.dart`）。
  final Color heatmapLevel0;
  final Color heatmapLevel1;
  final Color heatmapLevel2;
  final Color heatmapLevel3;
  final Color heatmapLevel4;
```

建構子（在 `required this.ttsActiveHighlight,` 之後）：

```dart
    required this.heatmapLevel0,
    required this.heatmapLevel1,
    required this.heatmapLevel2,
    required this.heatmapLevel3,
    required this.heatmapLevel4,
```

`copyWith` 參數（在 `Color? ttsActiveHighlight,` 之後）與回傳（在 `ttsActiveHighlight: ...,` 之後）：

```dart
    Color? heatmapLevel0,
    Color? heatmapLevel1,
    Color? heatmapLevel2,
    Color? heatmapLevel3,
    Color? heatmapLevel4,
```

```dart
      heatmapLevel0: heatmapLevel0 ?? this.heatmapLevel0,
      heatmapLevel1: heatmapLevel1 ?? this.heatmapLevel1,
      heatmapLevel2: heatmapLevel2 ?? this.heatmapLevel2,
      heatmapLevel3: heatmapLevel3 ?? this.heatmapLevel3,
      heatmapLevel4: heatmapLevel4 ?? this.heatmapLevel4,
```

`lerp`（在 `ttsActiveHighlight:` 兩行之後）：

```dart
      heatmapLevel0: Color.lerp(heatmapLevel0, other.heatmapLevel0, t)!,
      heatmapLevel1: Color.lerp(heatmapLevel1, other.heatmapLevel1, t)!,
      heatmapLevel2: Color.lerp(heatmapLevel2, other.heatmapLevel2, t)!,
      heatmapLevel3: Color.lerp(heatmapLevel3, other.heatmapLevel3, t)!,
      heatmapLevel4: Color.lerp(heatmapLevel4, other.heatmapLevel4, t)!,
```

在類別末端（`lerp` 之後、類別結尾 `}` 之前）新增：

```dart

  /// 依貢獻圖級別（0–4）取對應色階；超出範圍拋 [RangeError]。
  Color heatmapLevelColor(int level) => [
        heatmapLevel0,
        heatmapLevel1,
        heatmapLevel2,
        heatmapLevel3,
        heatmapLevel4,
      ][level];
```

- [x] **Step 4: 修改 `app_theme_data.dart` 四套主題**

在各主題 `ElinkTokens(...)` 內、`ttsActiveHighlight` 那行之後加入五級色值（用 Edit 逐一以各主題唯一的 `ttsActiveHighlight` 那行定位）：

Light（接在 `ttsActiveHighlight: Color(0xFFE0F2FE),` 之後）：

```dart
        heatmapLevel0: Color(0xFFEAF1F5),
        heatmapLevel1: Color(0xFFBAE6FD),
        heatmapLevel2: Color(0xFF7DD3FC),
        heatmapLevel3: Color(0xFF38BDF8),
        heatmapLevel4: Color(0xFF0284C7),
```

Dark（接在 `ttsActiveHighlight: Color(0xFF182836),` 之後）：

```dart
        heatmapLevel0: Color(0xFF2C2C34),
        heatmapLevel1: Color(0xFF0C4A6E),
        heatmapLevel2: Color(0xFF0369A1),
        heatmapLevel3: Color(0xFF0EA5E9),
        heatmapLevel4: Color(0xFF7DD3FC),
```

Sepia（接在 `ttsActiveHighlight: Color(0xFFFAECEA),` 之後）：

```dart
        heatmapLevel0: Color(0xFFE6DFCB),
        heatmapLevel1: Color(0xFFEFD3C4),
        heatmapLevel2: Color(0xFFDEA08E),
        heatmapLevel3: Color(0xFFC85F4F),
        heatmapLevel4: Color(0xFFB8362D),
```

E-Ink（接在 `ttsActiveHighlight: Color(0xFF000000),` 之後）：

```dart
        // 貢獻圖五級：階梯灰階（epic.md Issue 1 定案）。灰階僅供參考，實際級別
        // 另由貢獻圖元件疊加黑框與紋理區分，不只靠深淺。
        heatmapLevel0: Color(0xFFFFFFFF),
        heatmapLevel1: Color(0xFFD4D4D4),
        heatmapLevel2: Color(0xFFA3A3A3),
        heatmapLevel3: Color(0xFF525252),
        heatmapLevel4: Color(0xFF000000),
```

- [x] **Step 5: 補既有兩個測試檔的建構子欄位**

`app/test/theme/elink_tokens_test.dart`：`_base` 在 `ttsActiveHighlight: Color(0xFF888888),` 後加：

```dart
  heatmapLevel0: Color(0xFF999999),
  heatmapLevel1: Color(0xFFAAAAAA),
  heatmapLevel2: Color(0xFFBBBBBB),
  heatmapLevel3: Color(0xFFCCCCCC),
  heatmapLevel4: Color(0xFFDDDDDD),
```

同檔 `_expectAllFieldsEqual` 在 `expect(a.ttsActiveHighlight, b.ttsActiveHighlight);` 後加：

```dart
  expect(a.heatmapLevel0, b.heatmapLevel0);
  expect(a.heatmapLevel1, b.heatmapLevel1);
  expect(a.heatmapLevel2, b.heatmapLevel2);
  expect(a.heatmapLevel3, b.heatmapLevel3);
  expect(a.heatmapLevel4, b.heatmapLevel4);
```

`app/test/reader/highlight_style_test.dart`：`tokens` 在 `ttsActiveHighlight: Color(0xFFE0F2FE),` 後加：

```dart
    heatmapLevel0: Color(0xFFEAF1F5),
    heatmapLevel1: Color(0xFFBAE6FD),
    heatmapLevel2: Color(0xFF7DD3FC),
    heatmapLevel3: Color(0xFF38BDF8),
    heatmapLevel4: Color(0xFF0284C7),
```

- [x] **Step 6: 執行測試確認通過**

Run: `flutter test test/theme test/reader/highlight_style_test.dart`
Expected: PASS（含既有 `app_theme_data_test.dart`、`theme_test.dart`）

若 `flutter analyze` 報其他檔案還有直接建構 `ElinkTokens(` 的地方缺欄位，依報錯補上（目前 `grep` 只有這兩個測試檔與 `app_theme_data.dart`）。

- [x] **Step 7: 靜態檢查與提交**

Run: `flutter analyze`
Expected: `No issues found!`

```bash
git add lib/theme test/theme test/reader/highlight_style_test.dart
git commit -m "feat(stats): epic-9 Issue 5 ElinkTokens 新增貢獻圖五級色階" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：貢獻圖純邏輯與時數格式化

**Files:**
- Create: `app/lib/stats/heatmap_grid.dart`
- Create: `app/lib/stats/reading_duration_format.dart`
- Test: `app/test/stats/heatmap_grid_test.dart`
- Test: `app/test/stats/reading_duration_format_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `AppLocalizations.statsHoursMinutesFormat(int, int)`、`statsMinutesFormat(int)`。
- Produces（`app/lib/stats/heatmap_grid.dart`）：
  - `const int kHeatmapWindowDays = 365`
  - `String formatDateKey(DateTime d)` → `YYYY-MM-DD`（本地日期）
  - `int heatmapLevelForSeconds(int seconds)` → `0..4`
  - `class HeatmapMonthLabel { final int weekIndex; final int month; }`（`==`／`hashCode`／`toString` 供測試比對）
  - `class HeatmapGrid { final List<List<String?>> weeks; final List<HeatmapMonthLabel> monthLabels; final String startDate; final String endDate; int get weekCount; ({int week, int row})? locate(String date); }`（`weeks[w][row]`，`row 0`＝週一，範圍外為 `null`）
  - `HeatmapGrid buildHeatmapGrid(DateTime today)`
- Produces（`app/lib/stats/reading_duration_format.dart`）：`String formatReadingDuration(AppLocalizations l10n, int seconds)`

- [x] **Step 1: 寫失敗測試（網格與分級）**

建立 `app/test/stats/heatmap_grid_test.dart`（以下日期已核對：2026-09-29 為週二、2026-09-27 為週日、2025-09-29 為週一）：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/stats/heatmap_grid.dart';

int _validCount(HeatmapGrid g) =>
    g.weeks.expand((w) => w).where((c) => c != null).length;

int _nullCount(HeatmapGrid g) =>
    g.weeks.expand((w) => w).where((c) => c == null).length;

void main() {
  group('formatDateKey', () {
    test('補零成 YYYY-MM-DD', () {
      expect(formatDateKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(formatDateKey(DateTime(2026, 12, 31, 23, 59)), '2026-12-31');
    });
  });

  group('heatmapLevelForSeconds 五級邊界', () {
    test('0 與負值為第 0 級', () {
      expect(heatmapLevelForSeconds(0), 0);
      expect(heatmapLevelForSeconds(-5), 0);
    });
    test('1..899 秒為第 1 級', () {
      expect(heatmapLevelForSeconds(1), 1);
      expect(heatmapLevelForSeconds(899), 1);
    });
    test('900..1799 秒為第 2 級', () {
      expect(heatmapLevelForSeconds(900), 2);
      expect(heatmapLevelForSeconds(1799), 2);
    });
    test('1800..3599 秒為第 3 級', () {
      expect(heatmapLevelForSeconds(1800), 3);
      expect(heatmapLevelForSeconds(3599), 3);
    });
    test('3600 秒（含）以上為第 4 級', () {
      expect(heatmapLevelForSeconds(3600), 4);
      expect(heatmapLevelForSeconds(999999), 4);
    });
  });

  group('buildHeatmapGrid（今天＝2026-09-29 週二）', () {
    final grid = buildHeatmapGrid(DateTime(2026, 9, 29, 15, 30));

    test('共 53 週、365 個有效格、6 個透明佔位', () {
      expect(grid.weekCount, 53);
      expect(grid.weeks.every((w) => w.length == 7), isTrue);
      expect(_validCount(grid), 365);
      expect(_nullCount(grid), 6);
    });

    test('起訖日為今天往前 364 天到今天', () {
      expect(grid.startDate, '2025-09-30');
      expect(grid.endDate, '2026-09-29');
    });

    test('一週從週一開始：首週週一為佔位、週二為起始日', () {
      expect(grid.weeks.first[0], isNull); // 2025-09-29 週一，早於起始日
      expect(grid.weeks.first[1], '2025-09-30'); // 週二
    });

    test('末週：週一、週二（今天）有效，週三到週日為佔位', () {
      final last = grid.weeks.last;
      expect(last[0], '2026-09-28');
      expect(last[1], '2026-09-29');
      expect(last.sublist(2).every((c) => c == null), isTrue);
    });

    test('locate 回傳日期所在的週序號與列（0＝週一）', () {
      expect(grid.locate('2026-09-29'), (week: 52, row: 1));
      expect(grid.locate('2026-09-28'), (week: 52, row: 0));
      expect(grid.locate('2026-09-27'), (week: 51, row: 6)); // 週日
      expect(grid.locate('2025-09-30'), (week: 0, row: 1));
      expect(grid.locate('2025-09-29'), isNull); // 佔位格不是有效日期
      expect(grid.locate('2026-09-30'), isNull); // 未來
    });

    test('月份標籤：第一個標籤與第二個相距不到 2 週時捨棄第一個', () {
      // 週 0 的第一個有效格是 9 月、週 1 首格是 10 月，相距 1 週 → 捨棄 9 月標籤
      expect(grid.monthLabels.first,
          const HeatmapMonthLabel(weekIndex: 1, month: 10));
      expect(grid.monthLabels[1],
          const HeatmapMonthLabel(weekIndex: 5, month: 11));
      expect(grid.monthLabels.last,
          const HeatmapMonthLabel(weekIndex: 49, month: 9));
    });
  });

  group('buildHeatmapGrid 邊界', () {
    test('今天為週日：末週為完整七格、佔位全在首週', () {
      final grid = buildHeatmapGrid(DateTime(2026, 9, 27)); // 週日
      expect(grid.weekCount, 53);
      expect(grid.weeks.last.every((c) => c != null), isTrue);
      expect(grid.weeks.last[6], '2026-09-27');
      expect(_validCount(grid), 365);
      expect(_nullCount(grid), 6);
      expect(grid.weeks.first.where((c) => c == null).length, 6);
      expect(grid.weeks.first[6], '2025-09-28'); // 起始日也是週日
    });

    test('閏日：今天為 2028-02-29 時仍是 365 格且含閏日', () {
      final grid = buildHeatmapGrid(DateTime(2028, 2, 29));
      expect(_validCount(grid), 365);
      expect(grid.endDate, '2028-02-29');
      expect(grid.startDate, '2027-03-02');
      expect(grid.locate('2028-02-29'), isNotNull);
    });

    test('今天為週一：末週只有週一一格有效', () {
      final grid = buildHeatmapGrid(DateTime(2026, 9, 28)); // 週一
      final last = grid.weeks.last;
      expect(last[0], '2026-09-28');
      expect(last.sublist(1).every((c) => c == null), isTrue);
      expect(_validCount(grid), 365);
    });
  });
}
```

- [x] **Step 2: 寫失敗測試（時數格式化）**

建立 `app/test/stats/reading_duration_format_test.dart`：

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/stats/reading_duration_format.dart';

void main() {
  final tw = lookupAppLocalizations(const Locale('zh', 'TW'));
  final cn = lookupAppLocalizations(const Locale('zh', 'CN'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('0 秒顯示「0 分鐘」；負數秒數防禦性視為 0', () {
    expect(formatReadingDuration(tw, 0), '0 分鐘');
    expect(formatReadingDuration(tw, -120), '0 分鐘');
  });

  test('有紀錄但不滿 1 分鐘顯示「1 分鐘」（原型定案，避免出現 0 分鐘）', () {
    expect(formatReadingDuration(tw, 1), '1 分鐘');
    expect(formatReadingDuration(tw, 59), '1 分鐘');
  });

  test('未滿 1 小時只顯示分鐘（無條件捨去秒）', () {
    expect(formatReadingDuration(tw, 60), '1 分鐘');
    expect(formatReadingDuration(tw, 119), '1 分鐘');
    expect(formatReadingDuration(tw, 3599), '59 分鐘');
  });

  test('滿 1 小時顯示「X 小時 Y 分鐘」，整點也顯示「0 分鐘」', () {
    expect(formatReadingDuration(tw, 3600), '1 小時 0 分鐘');
    expect(formatReadingDuration(tw, 3900), '1 小時 5 分鐘');
    expect(formatReadingDuration(tw, 7384), '2 小時 3 分鐘');
  });

  test('簡體中文與英文', () {
    expect(formatReadingDuration(cn, 3900), '1 小时 5 分钟');
    expect(formatReadingDuration(cn, 600), '10 分钟');
    expect(formatReadingDuration(en, 3900), '1 hr 5 min');
    expect(formatReadingDuration(en, 600), '10 min');
  });
}
```

- [x] **Step 3: 執行測試確認失敗**

Run: `flutter test test/stats/heatmap_grid_test.dart test/stats/reading_duration_format_test.dart`
Expected: FAIL（`Target of URI doesn't exist: 'package:elinkbook/stats/heatmap_grid.dart'`）

- [x] **Step 4: 寫 `heatmap_grid.dart`**

```dart
// app/lib/stats/heatmap_grid.dart

/// 貢獻圖涵蓋的天數（含今天）。
const int kHeatmapWindowDays = 365;

/// 本地日期 → `YYYY-MM-DD`，與 `ReadingStatsRepository` 的日期鍵格式一致。
String formatDateKey(DateTime d) {
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-$mm-$dd';
}

/// 五級分級（以當日全部書籍總秒數判定）：
/// 0 無紀錄；1 未滿 15 分；2 未滿 30 分；3 未滿 60 分；4 六十分以上。
int heatmapLevelForSeconds(int seconds) {
  if (seconds <= 0) return 0;
  if (seconds < 15 * 60) return 1;
  if (seconds < 30 * 60) return 2;
  if (seconds < 60 * 60) return 3;
  return 4;
}

/// 月份標籤：貼在第 [weekIndex] 週的方格欄上方，[month] 為 1–12。
class HeatmapMonthLabel {
  final int weekIndex;
  final int month;

  const HeatmapMonthLabel({required this.weekIndex, required this.month});

  @override
  bool operator ==(Object other) =>
      other is HeatmapMonthLabel &&
      other.weekIndex == weekIndex &&
      other.month == month;

  @override
  int get hashCode => Object.hash(weekIndex, month);

  @override
  String toString() => 'HeatmapMonthLabel(week: $weekIndex, month: $month)';
}

/// 貢獻圖的日期網格。
///
/// [weeks] 的每個元素是一週（一欄）的七格：索引 0＝週一、6＝週日；範圍外的
/// 格子（第一週週一之前、最後一週今天之後）為 `null`，畫成不可點擊的透明佔位。
class HeatmapGrid {
  final List<List<String?>> weeks;
  final List<HeatmapMonthLabel> monthLabels;

  /// 視窗第一天與最後一天（今天），供 repository 區間查詢使用。
  final String startDate;
  final String endDate;

  const HeatmapGrid({
    required this.weeks,
    required this.monthLabels,
    required this.startDate,
    required this.endDate,
  });

  int get weekCount => weeks.length;

  /// 回傳 [date]（`YYYY-MM-DD`）所在的週序號與列；不在網格內回傳 `null`。
  ({int week, int row})? locate(String date) {
    for (var w = 0; w < weeks.length; w++) {
      final row = weeks[w].indexOf(date);
      if (row >= 0) return (week: w, row: row);
    }
    return null;
  }
}

/// 建立涵蓋「今天往前 365 天」的貢獻圖網格，一週從週一開始。
///
/// 日期運算一律用 `DateTime(y, m, d + n)`（由 `DateTime` 自行進位），天數差
/// 以 UTC 日期計算——避免夏令時間讓「本地兩日相差」不是整數個 24 小時。
HeatmapGrid buildHeatmapGrid(DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  final start = DateTime(t.year, t.month, t.day - (kHeatmapWindowDays - 1));
  // Dart 的 weekday：週一＝1…週日＝7，往回推到該週週一。
  final startMonday =
      DateTime(start.year, start.month, start.day - (start.weekday - 1));
  final spanDays = DateTime.utc(t.year, t.month, t.day)
          .difference(DateTime.utc(
              startMonday.year, startMonday.month, startMonday.day))
          .inDays +
      1;
  final weekCount = (spanDays / 7).ceil();

  // 範圍判斷一律比對 `YYYY-MM-DD` 字串（與 repository 的日期鍵約定一致），
  // 不比對 DateTime 的時分秒，避免時區／夏令時間造成的時間偏移影響邊界格。
  final startKey = formatDateKey(start);
  final endKey = formatDateKey(t);

  final weeks = <List<String?>>[];
  for (var w = 0; w < weekCount; w++) {
    final col = <String?>[];
    for (var row = 0; row < 7; row++) {
      final key = formatDateKey(DateTime(
          startMonday.year, startMonday.month, startMonday.day + w * 7 + row));
      col.add(key.compareTo(startKey) < 0 || key.compareTo(endKey) > 0
          ? null
          : key);
    }
    weeks.add(col);
  }

  // 月份標籤：某週第一個有效格的月份與前一個標籤不同時標出；第一個標籤若與
  // 第二個相距不到 2 週（會重疊）則捨棄第一個（與原型一致）。
  final labels = <HeatmapMonthLabel>[];
  var lastMonth = -1;
  for (var w = 0; w < weeks.length; w++) {
    final first = weeks[w].firstWhere((c) => c != null, orElse: () => null);
    if (first == null) continue;
    final month = int.parse(first.substring(5, 7));
    if (month != lastMonth) {
      labels.add(HeatmapMonthLabel(weekIndex: w, month: month));
      lastMonth = month;
    }
  }
  if (labels.length >= 2 && labels[1].weekIndex - labels[0].weekIndex < 2) {
    labels.removeAt(0);
  }

  return HeatmapGrid(
    weeks: weeks,
    monthLabels: labels,
    startDate: startKey,
    endDate: endKey,
  );
}
```

- [x] **Step 5: 寫 `reading_duration_format.dart`**

```dart
// app/lib/stats/reading_duration_format.dart
import '../l10n/app_localizations.dart';

/// 把閱讀秒數格式化成「X 小時 Y 分鐘」或「Y 分鐘」。
///
/// 秒數無條件捨去到分鐘；有紀錄但不滿 1 分鐘者顯示「1 分鐘」（避免出現
/// 「0 分鐘」，epic.md Issue 1 原型定案）；完全沒有紀錄（0 秒）顯示「0 分鐘」。
String formatReadingDuration(AppLocalizations l10n, int seconds) {
  // repository 保證秒數不為負；這裡仍防禦性歸零，避免顯示「-2 分鐘」。
  if (seconds <= 0) return l10n.statsMinutesFormat(0);
  var minutes = seconds ~/ 60;
  if (seconds > 0 && minutes == 0) minutes = 1;
  final hours = minutes ~/ 60;
  return hours > 0
      ? l10n.statsHoursMinutesFormat(hours, minutes % 60)
      : l10n.statsMinutesFormat(minutes);
}
```

- [x] **Step 6: 執行測試確認通過**

Run: `flutter test test/stats/heatmap_grid_test.dart test/stats/reading_duration_format_test.dart`
Expected: PASS

- [x] **Step 7: 靜態檢查與提交**

Run: `flutter analyze`
Expected: `No issues found!`

```bash
git add lib/stats/heatmap_grid.dart lib/stats/reading_duration_format.dart test/stats/heatmap_grid_test.dart test/stats/reading_duration_format_test.dart
git commit -m "feat(stats): epic-9 Issue 5 貢獻圖網格、分級與時數格式化純邏輯" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4：貢獻圖元件（網格、E-Ink 紋理、固定星期欄、選取外框、圖例）

**Files:**
- Create: `app/lib/screens/widgets/reading_heatmap.dart`
- Test: `app/test/screens/reading_heatmap_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `statsWeekdayMon/Wed/Fri`、`statsLegendLess/More`；Task 2 的 `ElinkTokens.heatmapLevelColor(int)`、`isEink`；Task 3 的 `HeatmapGrid`、`heatmapLevelForSeconds`。
- Produces（`reading_heatmap.dart`）：
  - 尺寸常數 `kHeatmapCellSize = 16`、`kHeatmapCellGap = 3`、`kHeatmapPitch = 19`。
  - `enum HeatmapTexture { none, dots, diagonal, cross, solid }`、`HeatmapTexture heatmapTextureForLevel(int level)`（`0→none, 1→dots, 2→diagonal, 3→cross, 4→solid`）。
  - `class HeatmapCellPainter extends CustomPainter`：欄位 `int level`、`Color fillColor`、`bool isEink`、`Color inkColor`；getter `HeatmapTexture texture`（非 E-Ink 恆為 `none`）；`factory HeatmapCellPainter.of(ThemeData theme, int level)`。
  - `class HeatmapSelectionOutlinePainter extends CustomPainter`：欄位 `Color color`、`double strokeWidth`。
  - `class ReadingHeatmap extends StatelessWidget`：`ReadingHeatmap({super.key, required HeatmapGrid grid, required Map<String,int> dailyTotals, required String? selectedDate, required ValueChanged<String> onSelectDate, required ScrollController scrollController})`。
  - `class ReadingHeatmapLegend extends StatelessWidget`：`const ReadingHeatmapLegend({super.key})`。
  - **Widget Key 契約**：水平捲動元件 `Key('reading_stats_heatmap')`（`SingleChildScrollView`）；星期欄 `Key('heatmap_weekday_column')`；星期標籤 `Key('heatmap_weekday_label_mon')`／`_wed`／`_fri`；有效方格 `Key('heatmap_cell_<YYYY-MM-DD>')`（最外層 `GestureDetector`，其下唯一的 `CustomPaint` 的 `painter` 是 `HeatmapCellPainter`）；透明佔位 `Key('heatmap_placeholder_<week>_<row>')`（實作裁決：全域單一 Key 會因末週 5 個佔位同屬一個 Column 而觸發 duplicate-keys 斷言，見 ledger Task 4 Ruling；測試以前綴 predicate 定位）；選取外框 `Key('heatmap_selection_outline')`（其 `CustomPaint.painter` 是 `HeatmapSelectionOutlinePainter`）；圖例 `Key('reading_stats_legend')`。

- [x] **Step 1: 寫失敗測試**

建立 `app/test/screens/reading_heatmap_test.dart`（今天固定為 2026-09-29 週二，網格 53 週）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/widgets/reading_heatmap.dart';
import 'package:elinkbook/stats/heatmap_grid.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

import '../support/pump_localized_widget.dart';

final _grid = buildHeatmapGrid(DateTime(2026, 9, 29));

Finder _cell(String date) => find.byKey(Key('heatmap_cell_$date'));

HeatmapCellPainter _painterOf(WidgetTester tester, String date) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: _cell(date), matching: find.byType(CustomPaint)),
  );
  return paint.painter! as HeatmapCellPainter;
}

Finder get _allCells => find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> && k.value.startsWith('heatmap_cell_');
    });

Future<ScrollController> _pump(
  WidgetTester tester, {
  Map<String, int> totals = const {},
  String? selected,
  ValueChanged<String>? onSelect,
  bool isEink = false,
  AppTheme theme = AppTheme.light,
  Locale locale = const Locale('zh', 'TW'),
}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await pumpLocalizedWidget(
    tester,
    Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ReadingHeatmap(
              grid: _grid,
              dailyTotals: totals,
              selectedDate: selected,
              onSelectDate: onSelect ?? (_) {},
              scrollController: controller,
            ),
            const ReadingHeatmapLegend(),
          ],
        ),
      ),
    ),
    isEinkMode: isEink,
    theme: theme,
    locale: locale,
  );
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('365 個有效方格與 6 個透明佔位', (tester) async {
    await _pump(tester);
    expect(_allCells, findsNWidgets(365));
    expect(find.byKey(const Key('heatmap_placeholder')), findsNWidgets(6));
  });

  testWidgets('一週從週一開始：同週同欄、列距 19、上週在左一欄', (tester) async {
    await _pump(tester);
    final mon = tester.getTopLeft(_cell('2026-09-28')); // 週一 row 0
    final tue = tester.getTopLeft(_cell('2026-09-29')); // 週二 row 1
    final prevSun = tester.getTopLeft(_cell('2026-09-27')); // 上週日 row 6
    expect(tue.dx, mon.dx);
    expect(tue.dy - mon.dy, kHeatmapPitch);
    expect(prevSun.dx, mon.dx - kHeatmapPitch);
    expect(prevSun.dy - mon.dy, 6 * kHeatmapPitch);
  });

  testWidgets('五級分級邊界對應正確的方格級別', (tester) async {
    await _pump(tester, totals: {
      '2026-09-21': 1,
      '2026-09-22': 899,
      '2026-09-23': 900,
      '2026-09-24': 1799,
      '2026-09-25': 1800,
      '2026-09-26': 3599,
      '2026-09-27': 3600,
      // 2026-09-28 沒有紀錄
    });
    final levels = [
      for (final d in [
        '2026-09-21',
        '2026-09-22',
        '2026-09-23',
        '2026-09-24',
        '2026-09-25',
        '2026-09-26',
        '2026-09-27',
        '2026-09-28',
      ])
        _painterOf(tester, d).level,
    ];
    expect(levels, [1, 1, 2, 2, 3, 3, 4, 0]);
  });

  testWidgets('星期欄不隨水平捲動移動，且標籤與同列方格頂端對齊', (tester) async {
    final controller = await _pump(tester);
    final before = tester.getTopLeft(find.byKey(const Key('heatmap_weekday_column')));

    controller.jumpTo(0);
    await tester.pump();
    final atStart = tester.getTopLeft(find.byKey(const Key('heatmap_weekday_column')));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    final atEnd = tester.getTopLeft(find.byKey(const Key('heatmap_weekday_column')));

    expect(atStart, before);
    expect(atEnd, before);
    expect(controller.position.maxScrollExtent, greaterThan(0));

    // 週一標籤（第 0 列）與週一方格頂端同高；週三、週五分別是第 2、4 列
    final monY = tester.getTopLeft(_cell('2026-09-28')).dy;
    expect(tester.getTopLeft(find.byKey(const Key('heatmap_weekday_label_mon'))).dy, monY);
    expect(tester.getTopLeft(find.byKey(const Key('heatmap_weekday_label_wed'))).dy,
        monY + 2 * kHeatmapPitch);
    expect(tester.getTopLeft(find.byKey(const Key('heatmap_weekday_label_fri'))).dy,
        monY + 4 * kHeatmapPitch);
  });

  testWidgets('選取外框疊在被選方格上；E-Ink 外框較粗；未選取時不畫', (tester) async {
    await _pump(tester, selected: '2026-09-29');
    final outline = find.byKey(const Key('heatmap_selection_outline'));
    expect(outline, findsOneWidget);
    expect(tester.getTopLeft(outline), tester.getTopLeft(_cell('2026-09-29')));
    final normal = tester.widget<CustomPaint>(outline).painter!
        as HeatmapSelectionOutlinePainter;
    expect(normal.strokeWidth, 2);

    await _pump(tester, selected: '2026-09-29', isEink: true);
    final eink = tester.widget<CustomPaint>(find.byKey(const Key('heatmap_selection_outline')))
        .painter! as HeatmapSelectionOutlinePainter;
    expect(eink.strokeWidth, 3);

    await _pump(tester, selected: null);
    expect(find.byKey(const Key('heatmap_selection_outline')), findsNothing);
  });

  testWidgets('點方格回呼該日期；透明佔位不可點', (tester) async {
    final tapped = <String>[];
    final controller = await _pump(tester, onSelect: tapped.add);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    await tester.tap(_cell('2026-09-28'));
    expect(tapped, ['2026-09-28']);

    await tester.tap(find.byKey(const Key('heatmap_placeholder')).first,
        warnIfMissed: false);
    expect(tapped, ['2026-09-28']);
  });

  group('E-Ink 呈現', () {
    testWidgets('五級紋理各不相同：留白、網點、單向斜線、交叉線、實心', (tester) async {
      await _pump(tester, isEink: true, totals: {
        '2026-09-22': 1,
        '2026-09-23': 900,
        '2026-09-24': 1800,
        '2026-09-25': 3600,
      });
      final textures = [
        for (final d in [
          '2026-09-21', // 無紀錄
          '2026-09-22',
          '2026-09-23',
          '2026-09-24',
          '2026-09-25',
        ])
          _painterOf(tester, d).texture,
      ];
      expect(textures, [
        HeatmapTexture.none,
        HeatmapTexture.dots,
        HeatmapTexture.diagonal,
        HeatmapTexture.cross,
        HeatmapTexture.solid,
      ]);
      expect(textures.toSet().length, 5);
    });

    testWidgets('網點級畫圓點、斜線級畫直線（實際有畫出紋理）', (tester) async {
      await _pump(tester, isEink: true, totals: {
        '2026-09-22': 1,
        '2026-09-23': 900,
      });
      RenderObject renderOf(String d) => tester.renderObject(
          find.descendant(of: _cell(d), matching: find.byType(CustomPaint)));
      expect(renderOf('2026-09-22'), paints..circle());
      expect(renderOf('2026-09-23'), paints..line());
    });

    testWidgets('非 E-Ink 主題不畫紋理，底色取自 Token', (tester) async {
      for (final theme in AppTheme.values) {
        await _pump(tester, theme: theme, totals: {'2026-09-25': 3600});
        final tokens = Theme.of(tester.element(find.byType(ReadingHeatmap)))
            .extension<ElinkTokens>()!;
        final p = _painterOf(tester, '2026-09-25');
        expect(p.isEink, isFalse);
        expect(p.texture, HeatmapTexture.none);
        expect(p.fillColor, tokens.heatmapLevel4);
        expect(_painterOf(tester, '2026-09-21').fillColor, tokens.heatmapLevel0);
      }
    });
  });

  testWidgets('英文介面：星期標籤單行不溢位、與正體中文版對齊一致', (tester) async {
    await _pump(tester, locale: const Locale('en'));
    expect(tester.takeException(), isNull);
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Wed'), findsOneWidget);
    expect(find.text('Fri'), findsOneWidget);
    final monY = tester.getTopLeft(_cell('2026-09-28')).dy;
    expect(tester.getTopLeft(find.byKey(const Key('heatmap_weekday_label_mon'))).dy, monY);
    // 標籤欄要寬到放得下「Mon」而不擠壓到方格區
    final columnRight =
        tester.getTopRight(find.byKey(const Key('heatmap_weekday_column'))).dx;
    final scrollLeft =
        tester.getTopLeft(find.byKey(const Key('reading_stats_heatmap'))).dx;
    expect(columnRight, lessThanOrEqualTo(scrollLeft));
  });

  testWidgets('圖例顯示「較少」「較多」與五個級別方格', (tester) async {
    await _pump(tester);
    final legend = find.byKey(const Key('reading_stats_legend'));
    expect(legend, findsOneWidget);
    expect(find.descendant(of: legend, matching: find.byType(CustomPaint)),
        findsNWidgets(5));
    expect(find.text('較少'), findsOneWidget);
    expect(find.text('較多'), findsOneWidget);
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reading_heatmap_test.dart`
Expected: FAIL（`Target of URI doesn't exist: 'package:elinkbook/screens/widgets/reading_heatmap.dart'`）

- [x] **Step 3: 寫 `reading_heatmap.dart`**

```dart
// app/lib/screens/widgets/reading_heatmap.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../stats/heatmap_grid.dart';
import '../../theme/elink_tokens.dart';

/// 方格邊長／間距／週欄間距（取自 epic.md Issue 1 原型定案值）。
const double kHeatmapCellSize = 16;
const double kHeatmapCellGap = 3;
const double kHeatmapPitch = kHeatmapCellSize + kHeatmapCellGap;

/// 月份標籤列高度，及其與方格區的間距；星期欄頂端以兩者相加的高度對齊。
const double _kMonthRowHeight = 14;
const double _kMonthToGridGap = 3;
const double _kGridTop = _kMonthRowHeight + _kMonthToGridGap;

/// 捲動容器左、右、下留白：選取外框最寬外擴 4px（E-Ink：偏移 1＋線寬 3），
/// 留白避免最右下角的「今天」被裁掉外框。上方不留，才能與左側星期欄垂直對齊。
const double _kScrollPadding = 4;

/// 貢獻圖方格的紋理（E-Ink 下不靠色相，用紋理輔助區分級別）。
enum HeatmapTexture { none, dots, diagonal, cross, solid }

/// 級別 → 紋理：0 留白、1 網點、2 單向斜線、3 交叉斜線、4 實心
/// （epic.md Issue 1 定案）。
HeatmapTexture heatmapTextureForLevel(int level) => switch (level) {
      1 => HeatmapTexture.dots,
      2 => HeatmapTexture.diagonal,
      3 => HeatmapTexture.cross,
      4 => HeatmapTexture.solid,
      _ => HeatmapTexture.none,
    };

/// 繪製單一方格。非 E-Ink：圓角 2px 純色。E-Ink：直角、Token 灰階底、
/// 依級別疊黑色紋理，最外圈畫 1px 黑框（不畫在紋理之下，避免被蓋掉）。
class HeatmapCellPainter extends CustomPainter {
  final int level;
  final Color fillColor;
  final bool isEink;

  /// 紋理與外框顏色（E-Ink 下即黑色）。
  final Color inkColor;

  const HeatmapCellPainter({
    required this.level,
    required this.fillColor,
    required this.isEink,
    required this.inkColor,
  });

  factory HeatmapCellPainter.of(ThemeData theme, int level) {
    final tokens = theme.extension<ElinkTokens>()!;
    return HeatmapCellPainter(
      level: level,
      fillColor: tokens.heatmapLevelColor(level),
      isEink: tokens.isEink,
      inkColor: theme.colorScheme.onSurface,
    );
  }

  /// 目前實際會畫出的紋理（非 E-Ink 恆為 [HeatmapTexture.none]）。
  HeatmapTexture get texture =>
      isEink ? heatmapTextureForLevel(level) : HeatmapTexture.none;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fill = Paint()..color = fillColor;
    if (!isEink) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        fill,
      );
      return;
    }

    canvas.drawRect(rect, fill);
    canvas.save();
    canvas.clipRect(rect.deflate(1));
    switch (texture) {
      case HeatmapTexture.dots:
        // 4px 週期的 1px 圓點
        final dot = Paint()..color = inkColor;
        for (var x = 2.0; x < size.width; x += 4) {
          for (var y = 2.0; y < size.height; y += 4) {
            canvas.drawCircle(Offset(x, y), 0.75, dot);
          }
        }
      case HeatmapTexture.diagonal:
        _drawDiagonals(canvas, size, rising: true, strokeWidth: 1);
      case HeatmapTexture.cross:
        _drawDiagonals(canvas, size, rising: true, strokeWidth: 1.5);
        _drawDiagonals(canvas, size, rising: false, strokeWidth: 1.5);
      case HeatmapTexture.none:
      case HeatmapTexture.solid:
        break;
    }
    canvas.restore();

    canvas.drawRect(
      rect.deflate(0.5),
      Paint()
        ..color = inkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// 45° 斜線，4px 週期；[rising] 為 true 畫「／」，否則畫「＼」。
  void _drawDiagonals(
    Canvas canvas,
    Size size, {
    required bool rising,
    required double strokeWidth,
  }) {
    final paint = Paint()
      ..color = inkColor
      ..strokeWidth = strokeWidth;
    for (var k = -size.height; k < size.width; k += 4) {
      if (rising) {
        canvas.drawLine(
            Offset(k, size.height), Offset(k + size.height, 0), paint);
      } else {
        canvas.drawLine(
            Offset(k, 0), Offset(k + size.height, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant HeatmapCellPainter old) =>
      old.level != level ||
      old.fillColor != fillColor ||
      old.isEink != isEink ||
      old.inkColor != inkColor;
}

/// 被選中方格的高對比外框：偏移 1px、線寬 [strokeWidth]（E-Ink 3、其餘 2）。
/// 畫在整張網格之上的獨立疊加層，不會被後畫的鄰格蓋住。
class HeatmapSelectionOutlinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const HeatmapSelectionOutlinePainter({
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).inflate(1 + strokeWidth / 2);
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant HeatmapSelectionOutlinePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

/// 貢獻圖：左側固定星期標籤欄＋右側水平捲動的方格區（月份標籤在方格上方、
/// 隨方格一起捲動）。捲動位置由呼叫端的 [scrollController] 控制（畫面載入
/// 後把它捲到最右側）。
class ReadingHeatmap extends StatelessWidget {
  final HeatmapGrid grid;

  /// `YYYY-MM-DD` → 當日全部書籍總秒數；沒有紀錄的日期不出現。
  final Map<String, int> dailyTotals;

  /// 目前選取的日期；`null` 表示不畫外框。
  final String? selectedDate;
  final ValueChanged<String> onSelectDate;
  final ScrollController scrollController;

  const ReadingHeatmap({
    super.key,
    required this.grid,
    required this.dailyTotals,
    required this.selectedDate,
    required this.onSelectDate,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isEink = theme.extension<ElinkTokens>()!.isEink;
    final ink = theme.colorScheme.onSurface;
    final selected = selectedDate == null ? null : grid.locate(selectedDate!);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WeekdayColumn(l10n: l10n, color: ink),
        Expanded(
          child: SingleChildScrollView(
            key: const Key('reading_stats_heatmap'),
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
                _kScrollPadding, 0, _kScrollPadding, _kScrollPadding),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MonthLabelRow(grid: grid, l10n: l10n, color: ink),
                    const SizedBox(height: _kMonthToGridGap),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _gapped(
                        [
                          for (final week in grid.weeks)
                            Column(
                              children: _gapped(
                                [
                                  for (final date in week)
                                    date == null
                                        ? const SizedBox.square(
                                            key: Key('heatmap_placeholder'),
                                            dimension: kHeatmapCellSize,
                                          )
                                        : _HeatmapCell(
                                            date: date,
                                            painter: HeatmapCellPainter.of(
                                              theme,
                                              heatmapLevelForSeconds(
                                                  dailyTotals[date] ?? 0),
                                            ),
                                            selected: date == selectedDate,
                                            onTap: onSelectDate,
                                          ),
                                ],
                                const SizedBox(height: kHeatmapCellGap),
                              ),
                            ),
                        ],
                        const SizedBox(width: kHeatmapCellGap),
                      ),
                    ),
                  ],
                ),
                if (selected != null)
                  Positioned(
                    left: selected.week * kHeatmapPitch,
                    top: _kGridTop + selected.row * kHeatmapPitch,
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const Key('heatmap_selection_outline'),
                        size: const Size.square(kHeatmapCellSize),
                        painter: HeatmapSelectionOutlinePainter(
                          color: ink,
                          strokeWidth: isEink ? 3 : 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

List<Widget> _gapped(List<Widget> items, Widget gap) => [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) gap,
        items[i],
      ],
    ];

class _HeatmapCell extends StatelessWidget {
  final String date;
  final HeatmapCellPainter painter;
  final bool selected;
  final ValueChanged<String> onTap;

  const _HeatmapCell({
    required this.date,
    required this.painter,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('heatmap_cell_$date'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(date),
      child: Semantics(
        label: date,
        button: true,
        selected: selected,
        child: CustomPaint(
          size: const Size.square(kHeatmapCellSize),
          painter: painter,
        ),
      ),
    );
  }
}

/// 左側固定星期標籤欄：只標「週一、三、五」（第 0、2、4 列）。標籤單行、不縮放，
/// 欄寬由文字撐開（最少 14px，加 4px 右內距），英文「Mon」也不會折行。
class _WeekdayColumn extends StatelessWidget {
  final AppLocalizations l10n;
  final Color color;

  const _WeekdayColumn({required this.l10n, required this.color});

  @override
  Widget build(BuildContext context) {
    final labels = <int, (Key, String)>{
      0: (const Key('heatmap_weekday_label_mon'), l10n.statsWeekdayMon),
      2: (const Key('heatmap_weekday_label_wed'), l10n.statsWeekdayWed),
      4: (const Key('heatmap_weekday_label_fri'), l10n.statsWeekdayFri),
    };
    return IntrinsicWidth(
      key: const Key('heatmap_weekday_column'),
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: _kGridTop),
              for (var row = 0; row < 7; row++) ...[
                if (row > 0) const SizedBox(height: kHeatmapCellGap),
                SizedBox(
                  key: labels[row]?.$1,
                  height: kHeatmapCellSize,
                  child: labels[row] == null
                      ? null
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            labels[row]!.$2,
                            maxLines: 1,
                            softWrap: false,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                                fontSize: 10, height: 1, color: color),
                          ),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 方格上方的月份標籤列：標籤貼在對應週欄的左緣，隨方格一起水平捲動。
class _MonthLabelRow extends StatelessWidget {
  final HeatmapGrid grid;
  final AppLocalizations l10n;
  final Color color;

  const _MonthLabelRow({
    required this.grid,
    required this.l10n,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final format = DateFormat.MMM(l10n.localeName);
    return SizedBox(
      height: _kMonthRowHeight,
      width: grid.weekCount * kHeatmapPitch,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final m in grid.monthLabels)
            Positioned(
              left: m.weekIndex * kHeatmapPitch,
              top: 0,
              child: Text(
                format.format(DateTime(2000, m.month)),
                maxLines: 1,
                softWrap: false,
                textScaler: TextScaler.noScaling,
                style: TextStyle(fontSize: 10, height: 1.4, color: color),
              ),
            ),
        ],
      ),
    );
  }
}

/// 圖例：「較少 ▢▢▢▢▢ 較多」，方格與貢獻圖使用同一個繪製器（E-Ink 下含紋理）。
class ReadingHeatmapLegend extends StatelessWidget {
  const ReadingHeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final style = TextStyle(fontSize: 10, color: theme.colorScheme.onSurface);
    return Row(
      key: const Key('reading_stats_legend'),
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(l10n.statsLegendLess, style: style),
        const SizedBox(width: 4),
        for (var level = 0; level < 5; level++) ...[
          if (level > 0) const SizedBox(width: 3),
          CustomPaint(
            size: const Size.square(kHeatmapCellSize),
            painter: HeatmapCellPainter.of(theme, level),
          ),
        ],
        const SizedBox(width: 4),
        Text(l10n.statsLegendMore, style: style),
      ],
    );
  }
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/reading_heatmap_test.dart`
Expected: PASS

若「圖例」測試因 `find.descendant(...CustomPaint)` 數量不符失敗（`Text` 不含 `CustomPaint`，理論上剛好 5 個），以實際結果檢查是否有 Flutter 內建元件夾帶額外 `CustomPaint`，改成只數 `heatmap` 圖例內 `CustomPaint` 且 `painter is HeatmapCellPainter` 的數量（`find.byWidgetPredicate`）。

- [x] **Step 5: 靜態檢查與提交**

Run: `flutter analyze`
Expected: `No issues found!`

```bash
git add lib/screens/widgets/reading_heatmap.dart test/screens/reading_heatmap_test.dart
git commit -m "feat(stats): epic-9 Issue 5 貢獻圖元件（固定星期欄、E-Ink 紋理、選取外框、圖例）" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5：統計畫面（載入、詳情、累計時數、清除流程）

**Files:**
- Create: `app/lib/screens/reading_stats_screen.dart`
- Test: `app/test/screens/reading_stats_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `buildHeatmapGrid`／`formatDateKey`／`formatReadingDuration`；Task 4 的 `ReadingHeatmap`／`ReadingHeatmapLegend`；既有 `ReadingStatsRepository`（`getDailyTotals`、`getTotalReadingSeconds`、`getBookStatsForDate`、`clearAllStats`）、`DailyBookReadingStat`、`EBFieldCard`。
- Produces：
  - `class ReadingStatsScreen extends StatefulWidget`：`const ReadingStatsScreen({super.key, required ReadingStatsRepository repository, DateTime Function()? nowProvider})`；`nowProvider` 預設 `clock.now`（測試可注入固定日期）。
  - **Widget Key 契約**（沿用 `issues.md` 六個，另補畫面內定位用的 Key）：
    - `Key('reading_stats_loading')`：載入中指示器
    - `Key('reading_stats_total_text')`：累計總時數文字（`Text`）
    - `Key('reading_stats_daily_detail_card')`：當日詳情卡片
    - `Key('reading_stats_detail_title')`：詳情標題（`Text`）
    - `Key('reading_stats_detail_empty')`：無紀錄說明（`Text`）
    - `Key('reading_stats_detail_row_<bookId>')`：詳情中每本書的一列
    - `Key('reading_stats_clear_all_button')`：清除全部統計按鈕
    - `Key('reading_stats_clear_all_dialog')`：確認對話框
    - `Key('reading_stats_clear_all_confirm_button')`、`Key('reading_stats_clear_all_cancel_button')`
    - `Key('reading_stats_clear_success_snackbar')`：清除成功提示

- [x] **Step 1: 寫失敗測試**

建立 `app/test/screens/reading_stats_screen_test.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/reading_stats_screen.dart';
import 'package:elinkbook/screens/widgets/reading_heatmap.dart';
import 'package:elinkbook/stats/daily_book_reading_stat.dart';
import 'package:elinkbook/stats/reading_stats_repository.dart';
import 'package:elinkbook/theme/app_theme.dart';
import 'package:elinkbook/theme/elink_tokens.dart';

import '../support/fake_reading_stats_repository.dart';
import '../support/pump_localized_widget.dart';

/// 固定「今天」為 2026-09-29（週二），網格為 2025-09-30 ～ 2026-09-29。
final _now = DateTime(2026, 9, 29, 10, 30);

DailyBookReadingStat _stat(String id, String title, int seconds) =>
    DailyBookReadingStat(bookId: id, bookTitle: title, readingSeconds: seconds);

Finder _cell(String date) => find.byKey(Key('heatmap_cell_$date'));
Finder _byKey(String key) => find.byKey(Key(key));

HeatmapCellPainter _painterOf(WidgetTester tester, String date) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: _cell(date), matching: find.byType(CustomPaint)),
  );
  return paint.painter! as HeatmapCellPainter;
}

ScrollController _scrollController(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(_byKey('reading_stats_heatmap'))
    .controller!;

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(_byKey(key)).data!;

Future<void> _pumpScreen(
  WidgetTester tester,
  ReadingStatsRepository repository, {
  Locale locale = const Locale('zh', 'TW'),
  AppTheme theme = AppTheme.light,
  bool isEinkMode = false,
}) async {
  // 加高視窗，讓清除按鈕在不捲動的情況下就看得到
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await pumpLocalizedWidget(
    tester,
    ReadingStatsScreen(repository: repository, nowProvider: () => _now),
    locale: locale,
    theme: theme,
    isEinkMode: isEinkMode,
  );
  await tester.pumpAndSettle();
}

/// 包一層，讓測試能卡住特定日期的詳情查詢，製造「先點的較晚回來」的競態。
class _GatedRepository implements ReadingStatsRepository {
  _GatedRepository(this.inner);
  final FakeReadingStatsRepository inner;
  final Map<String, Completer<void>> gates = {};

  @override
  Future<List<DailyBookReadingStat>> getBookStatsForDate(String date) async {
    final gate = gates[date];
    if (gate != null) await gate.future;
    return inner.getBookStatsForDate(date);
  }

  @override
  Future<void> addReadingSeconds({
    required String date,
    required String bookId,
    required String bookTitle,
    required int seconds,
  }) =>
      inner.addReadingSeconds(
          date: date, bookId: bookId, bookTitle: bookTitle, seconds: seconds);

  @override
  Future<Map<String, int>> getDailyTotals({
    required String startDate,
    required String endDate,
  }) =>
      inner.getDailyTotals(startDate: startDate, endDate: endDate);

  @override
  Future<int> getTotalReadingSeconds() => inner.getTotalReadingSeconds();

  @override
  Future<void> clearAllStats() => inner.clearAllStats();

  @override
  Stream<void> get onCleared => inner.onCleared;
}

void main() {
  testWidgets('載入完成後顯示貢獻圖；預設選中今天，今天沒有紀錄顯示說明', (tester) async {
    await _pumpScreen(tester, FakeReadingStatsRepository());

    expect(_byKey('reading_stats_loading'), findsNothing);
    expect(_byKey('reading_stats_heatmap'), findsOneWidget);
    // 外框疊在今天的方格上
    expect(tester.getTopLeft(_byKey('heatmap_selection_outline')),
        tester.getTopLeft(_cell('2026-09-29')));
    expect(_byKey('reading_stats_detail_empty'), findsOneWidget);
    expect(_textOf(tester, 'reading_stats_detail_title'), contains('2026'));
  });

  testWidgets('今天有多本書：詳情依時數由多到少，已刪除的書顯示書名快照', (tester) async {
    final repo = FakeReadingStatsRepository(initialStats: {
      '2026-09-29': [
        _stat('a', '紅樓夢', 600),
        _stat('gone', '已刪除的書（快照）', 3900),
        _stat('b', '三體', 1800),
      ],
    });
    await _pumpScreen(tester, repo);

    expect(_byKey('reading_stats_detail_empty'), findsNothing);
    final ys = [
      for (final id in ['gone', 'b', 'a'])
        tester.getTopLeft(_byKey('reading_stats_detail_row_$id')).dy,
    ];
    expect(ys[0], lessThan(ys[1]));
    expect(ys[1], lessThan(ys[2]));
    expect(
      find.descendant(
          of: _byKey('reading_stats_detail_row_gone'),
          matching: find.text('已刪除的書（快照）')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: _byKey('reading_stats_detail_row_gone'),
          matching: find.text('1 小時 5 分鐘')),
      findsOneWidget,
    );
  });

  testWidgets('點選其他方格：外框移動、詳情切換成該日', (tester) async {
    final repo = FakeReadingStatsRepository(initialStats: {
      '2026-09-29': [_stat('a', '今天的書', 600)],
      '2025-09-30': [_stat('old', '一年前的書', 1200)],
    });
    await _pumpScreen(tester, repo);
    expect(_byKey('reading_stats_detail_row_a'), findsOneWidget);

    _scrollController(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(_cell('2025-09-30'));
    await tester.pumpAndSettle();

    expect(_byKey('reading_stats_detail_row_old'), findsOneWidget);
    expect(_byKey('reading_stats_detail_row_a'), findsNothing);
    expect(tester.getTopLeft(_byKey('heatmap_selection_outline')),
        tester.getTopLeft(_cell('2025-09-30')));
    expect(_textOf(tester, 'reading_stats_detail_title'), contains('2025'));

    // 點沒有紀錄的日子 → 顯示說明
    await tester.tap(_cell('2025-10-01'));
    await tester.pumpAndSettle();
    expect(_byKey('reading_stats_detail_empty'), findsOneWidget);
  });

  testWidgets('進入畫面預設捲到最右側，星期欄不隨捲動移動', (tester) async {
    await _pumpScreen(tester, FakeReadingStatsRepository());
    final controller = _scrollController(tester);
    expect(controller.position.maxScrollExtent, greaterThan(0));
    expect(controller.offset, controller.position.maxScrollExtent);

    final columnBefore = tester.getTopLeft(_byKey('heatmap_weekday_column'));
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_byKey('heatmap_weekday_column')), columnBefore);
  });

  testWidgets('貢獻圖分級以當日全部書籍總時數判定', (tester) async {
    final repo = FakeReadingStatsRepository(initialStats: {
      // 兩本各 10 分鐘 → 合計 20 分鐘 → 第 2 級（不是各自的第 1 級）
      '2026-09-28': [_stat('a', 'A', 600), _stat('b', 'B', 600)],
      '2026-09-29': [_stat('a', 'A', 3600)],
    });
    await _pumpScreen(tester, repo);
    expect(_painterOf(tester, '2026-09-28').level, 2);
    expect(_painterOf(tester, '2026-09-29').level, 4);
    expect(_painterOf(tester, '2026-09-27').level, 0);
  });

  testWidgets('累計總時數＝全部紀錄加總，含一年以前（貢獻圖之外）的舊紀錄', (tester) async {
    final repo = FakeReadingStatsRepository(initialStats: {
      '2025-01-01': [_stat('old', '很久以前', 3600)], // 視窗外
      '2026-09-29': [_stat('a', 'A', 1800)],
    });
    await _pumpScreen(tester, repo);

    expect(_textOf(tester, 'reading_stats_total_text'), '1 小時 30 分鐘');
    expect(_cell('2025-01-01'), findsNothing); // 視窗外沒有對應方格
    expect(_painterOf(tester, '2026-09-29').level, 3);
  });

  testWidgets('全新安裝（沒有任何紀錄）：正常顯示、總時數 0 分鐘、方格全為第 0 級', (tester) async {
    await _pumpScreen(tester, FakeReadingStatsRepository());
    expect(tester.takeException(), isNull);
    expect(_textOf(tester, 'reading_stats_total_text'), '0 分鐘');
    expect(_painterOf(tester, '2026-09-29').level, 0);
    expect(_painterOf(tester, '2025-09-30').level, 0);
    expect(_byKey('reading_stats_detail_empty'), findsOneWidget);
  });

  testWidgets('超長書名在詳情中自動換行、不溢位', (tester) async {
    final longTitle = List.filled(200, '長').join();
    final repo = FakeReadingStatsRepository(initialStats: {
      '2026-09-29': [_stat('long', longTitle, 600)],
    });
    await _pumpScreen(tester, repo);
    expect(tester.takeException(), isNull);
    expect(_byKey('reading_stats_detail_row_long'), findsOneWidget);
  });

  testWidgets('書名快照為空白時退回書籍 id，不出現空白列', (tester) async {
    final repo = FakeReadingStatsRepository(initialStats: {
      '2026-09-29': [_stat('book-42', '   ', 600)],
    });
    await _pumpScreen(tester, repo);
    expect(
      find.descendant(
          of: _byKey('reading_stats_detail_row_book-42'),
          matching: find.text('book-42')),
      findsOneWidget,
    );
  });

  testWidgets('快速連點兩個方格：先點的查詢較晚回來，不會蓋掉後點的結果', (tester) async {
    final inner = FakeReadingStatsRepository(initialStats: {
      '2026-09-21': [_stat('a', 'A 書', 600)],
      '2026-09-22': [_stat('b', 'B 書', 600)],
    });
    final repo = _GatedRepository(inner);
    await _pumpScreen(tester, repo);

    repo.gates['2026-09-21'] = Completer<void>(); // 卡住 A 的詳情查詢
    await tester.tap(_cell('2026-09-21')); // 點 A（查詢卡住）
    await tester.pump();
    await tester.tap(_cell('2026-09-22')); // 再點 B（立即回來）
    await tester.pumpAndSettle();
    expect(_byKey('reading_stats_detail_row_b'), findsOneWidget);

    repo.gates['2026-09-21']!.complete(); // 最後才放行 A
    await tester.pumpAndSettle();

    expect(_byKey('reading_stats_detail_row_b'), findsOneWidget);
    expect(_byKey('reading_stats_detail_row_a'), findsNothing);
    expect(tester.getTopLeft(_byKey('heatmap_selection_outline')),
        tester.getTopLeft(_cell('2026-09-22')));
  });

  group('清除全部統計', () {
    FakeReadingStatsRepository seeded() => FakeReadingStatsRepository(
          initialStats: {
            '2026-09-29': [_stat('a', 'A', 1800)],
          },
        );

    testWidgets('按下清除只會先出確認對話框，取消則資料與畫面不變', (tester) async {
      final repo = seeded();
      await _pumpScreen(tester, repo);

      await tester.tap(_byKey('reading_stats_clear_all_button'));
      await tester.pumpAndSettle();
      expect(_byKey('reading_stats_clear_all_dialog'), findsOneWidget);
      expect(await repo.getTotalReadingSeconds(), 1800); // 尚未清除

      await tester.tap(_byKey('reading_stats_clear_all_cancel_button'));
      await tester.pumpAndSettle();

      expect(_byKey('reading_stats_clear_all_dialog'), findsNothing);
      expect(await repo.getTotalReadingSeconds(), 1800);
      expect(_textOf(tester, 'reading_stats_total_text'), '30 分鐘');
      expect(_byKey('reading_stats_detail_row_a'), findsOneWidget);
      expect(_byKey('reading_stats_clear_success_snackbar'), findsNothing);
    });

    testWidgets('確認後資料清空、畫面回到空白狀態並提示', (tester) async {
      final repo = seeded();
      await _pumpScreen(tester, repo);

      await tester.tap(_byKey('reading_stats_clear_all_button'));
      await tester.pumpAndSettle();
      await tester.tap(_byKey('reading_stats_clear_all_confirm_button'));
      await tester.pumpAndSettle();

      expect(await repo.getTotalReadingSeconds(), 0);
      expect(_textOf(tester, 'reading_stats_total_text'), '0 分鐘');
      expect(_byKey('reading_stats_detail_empty'), findsOneWidget);
      expect(_byKey('reading_stats_detail_row_a'), findsNothing);
      expect(_painterOf(tester, '2026-09-29').level, 0);
      expect(_byKey('reading_stats_clear_success_snackbar'), findsOneWidget);
    });

    testWidgets('先選了過去的日期再清除：清除後選取日回到今天', (tester) async {
      final repo = FakeReadingStatsRepository(initialStats: {
        '2026-09-28': [_stat('a', 'A', 600)],
        '2026-09-29': [_stat('a', 'A', 1800)],
      });
      await _pumpScreen(tester, repo);

      await tester.tap(_cell('2026-09-28')); // 選昨天
      await tester.pumpAndSettle();
      expect(_textOf(tester, 'reading_stats_detail_title'), contains('9/28'));

      await tester.tap(_byKey('reading_stats_clear_all_button'));
      await tester.pumpAndSettle();
      await tester.tap(_byKey('reading_stats_clear_all_confirm_button'));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(_byKey('heatmap_selection_outline')),
          tester.getTopLeft(_cell('2026-09-29')));
      expect(_textOf(tester, 'reading_stats_detail_title'), contains('9/29'));
      expect(_byKey('reading_stats_detail_empty'), findsOneWidget);
    });

    testWidgets('E-Ink 下對話框可正常開啟與確認', (tester) async {
      final repo = seeded();
      await _pumpScreen(tester, repo, isEinkMode: true);

      await tester.tap(_byKey('reading_stats_clear_all_button'));
      await tester.pump(); // 無動畫：一次 pump 就該出現
      expect(_byKey('reading_stats_clear_all_dialog'), findsOneWidget);

      await tester.tap(_byKey('reading_stats_clear_all_confirm_button'));
      await tester.pumpAndSettle();
      expect(await repo.getTotalReadingSeconds(), 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('主題與 E-Ink', () {
    testWidgets('Light／Dark／Sepia 皆能渲染，方格底色取自 Token', (tester) async {
      for (final theme in AppTheme.values) {
        final repo = FakeReadingStatsRepository(initialStats: {
          '2026-09-29': [_stat('a', 'A', 3600)],
        });
        await _pumpScreen(tester, repo, theme: theme);
        expect(tester.takeException(), isNull);
        final tokens = Theme.of(tester.element(find.byType(ReadingStatsScreen)))
            .extension<ElinkTokens>()!;
        expect(_painterOf(tester, '2026-09-29').fillColor, tokens.heatmapLevel4);
        expect(_painterOf(tester, '2026-09-28').fillColor, tokens.heatmapLevel0);
      }
    });

    testWidgets('E-Ink：五級可區分（灰階＋紋理），不依賴色相', (tester) async {
      final repo = FakeReadingStatsRepository(initialStats: {
        '2026-09-25': [_stat('a', 'A', 60)],
        '2026-09-26': [_stat('a', 'A', 900)],
        '2026-09-27': [_stat('a', 'A', 1800)],
        '2026-09-28': [_stat('a', 'A', 3600)],
      });
      await _pumpScreen(tester, repo, isEinkMode: true);

      final painters = [
        for (final d in [
          '2026-09-24', // 第 0 級
          '2026-09-25',
          '2026-09-26',
          '2026-09-27',
          '2026-09-28',
        ])
          _painterOf(tester, d),
      ];
      expect(painters.map((p) => p.level), [0, 1, 2, 3, 4]);
      expect(painters.every((p) => p.isEink), isTrue);
      expect(painters.map((p) => p.texture).toSet().length, 5);
      expect(painters.map((p) => p.fillColor).toSet().length, 5);
    });
  });

  group('介面語言', () {
    testWidgets('正體中文', (tester) async {
      await _pumpScreen(tester, FakeReadingStatsRepository());
      expect(find.text('閱讀統計'), findsOneWidget);
      expect(find.text('累計閱讀時數'), findsOneWidget);
      expect(find.text('當日無閱讀記錄'), findsOneWidget);
      expect(find.text('清除全部統計'), findsOneWidget);
    });

    testWidgets('簡體中文', (tester) async {
      await _pumpScreen(tester, FakeReadingStatsRepository(),
          locale: const Locale('zh', 'CN'));
      expect(find.text('阅读统计'), findsOneWidget);
      expect(find.text('累计阅读时长'), findsOneWidget);
      expect(find.text('当日无阅读记录'), findsOneWidget);
      expect(find.text('清除全部统计'), findsOneWidget);
    });

    testWidgets('英文', (tester) async {
      await _pumpScreen(tester, FakeReadingStatsRepository(),
          locale: const Locale('en'));
      expect(tester.takeException(), isNull);
      expect(find.text('Reading Stats'), findsOneWidget);
      expect(find.text('Total Reading Time'), findsOneWidget);
      expect(find.text('No reading on this day'), findsOneWidget);
      expect(find.text('Clear All Stats'), findsOneWidget);
    });
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reading_stats_screen_test.dart`
Expected: FAIL（`Target of URI doesn't exist: 'package:elinkbook/screens/reading_stats_screen.dart'`）

- [x] **Step 3: 寫 `reading_stats_screen.dart`**

```dart
// app/lib/screens/reading_stats_screen.dart
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../stats/daily_book_reading_stat.dart';
import '../stats/heatmap_grid.dart';
import '../stats/reading_duration_format.dart';
import '../stats/reading_stats_repository.dart';
import '../theme/elink_tokens.dart';
import 'widgets/eb_field_card.dart';
import 'widgets/reading_heatmap.dart';

/// 閱讀統計畫面（epic-9-stats Issue 5，入口在設定頁）：累計總時數、近 365 天
/// 貢獻圖、貢獻圖下方固定的當日詳情卡片，以及底部的「清除全部統計」。
///
/// 唯讀顯示 [repository] 的資料（清除除外）；詳情一律顯示在固定卡片，不使用
/// Tooltip 或任何浮動層（E-Ink 友善）。資料只在進入畫面與清除後載入。
class ReadingStatsScreen extends StatefulWidget {
  final ReadingStatsRepository repository;

  /// 取得「現在」的時間來源；預設 `clock.now`，測試可注入固定日期。
  final DateTime Function()? nowProvider;

  const ReadingStatsScreen({
    super.key,
    required this.repository,
    this.nowProvider,
  });

  @override
  State<ReadingStatsScreen> createState() => _ReadingStatsScreenState();
}

class _ReadingStatsScreenState extends State<ReadingStatsScreen> {
  final ScrollController _scrollController = ScrollController();
  late final HeatmapGrid _grid;
  late final String _todayKey;

  bool _loading = true;
  bool _didScrollToEnd = false;
  Map<String, int> _dailyTotals = const {};
  int _totalSeconds = 0;

  /// 目前選取的日期，與 [_details] 同步更新（見 [_selectDate]）。
  late String _selectedDate;
  List<DailyBookReadingStat> _details = const [];

  /// 詳情查詢的請求序號：快速連點時，只有最後一次發出的查詢結果會被採用。
  int _detailRequestId = 0;

  @override
  void initState() {
    super.initState();
    final today = (widget.nowProvider ?? clock.now)();
    _grid = buildHeatmapGrid(today);
    _todayKey = _grid.endDate;
    _selectedDate = _todayKey;
    _loadAll();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 載入貢獻圖各日總計、累計總時數與詳情。詳情預設載入目前選取日；
  /// 傳入 [selecting] 則改載入該日並一併切換選取（清除後用它回到今天）。
  Future<void> _loadAll({String? selecting}) async {
    final requestId = ++_detailRequestId;
    final repository = widget.repository;
    final date = selecting ?? _selectedDate;
    final totals = await repository.getDailyTotals(
      startDate: _grid.startDate,
      endDate: _grid.endDate,
    );
    final total = await repository.getTotalReadingSeconds();
    final details = await repository.getBookStatsForDate(date);
    if (!mounted || requestId != _detailRequestId) return;
    setState(() {
      _dailyTotals = totals;
      _totalSeconds = total;
      _selectedDate = date;
      _details = details;
      _loading = false;
    });
    _scrollToEndOnce();
  }

  /// 首次載入完成後把貢獻圖捲到最右側（今天所在的一週）。
  void _scrollToEndOnce() {
    if (_didScrollToEnd) return;
    _didScrollToEnd = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// 選取某一天：查完該日詳情後才**同時**更新外框與詳情，避免外框與詳情
  /// 短暫對不上；請求序號讓過期（較早發出但較晚回來）的結果被丟棄。
  Future<void> _selectDate(String date) async {
    final requestId = ++_detailRequestId;
    final details = await widget.repository.getBookStatsForDate(date);
    if (!mounted || requestId != _detailRequestId) return;
    setState(() {
      _selectedDate = date;
      _details = details;
    });
  }

  Future<void> _confirmAndClear() async {
    final confirmed = await _showClearConfirmDialog();
    if (confirmed != true || !mounted) return;
    await widget.repository.clearAllStats();
    if (!mounted) return;
    // 「回到空白狀態」＝與全新開啟畫面一致：選取日重置為今天，不停留在歷史日期
    await _loadAll(selecting: _todayKey);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('reading_stats_clear_success_snackbar'),
        content: Text(AppLocalizations.of(context)!.statsClearAllSuccess),
      ),
    );
  }

  /// 破壞性操作確認（`DESIGN.md` §9.1／§9.2）：寬度上限 400dp、主動作靠右、
  /// 確認鈕用 `error` 色並標明具體後果；E-Ink 下不淡入淡出。
  Future<bool?> _showClearConfirmDialog() {
    final isEink =
        Theme.of(context).extension<ElinkTokens>()?.isEink ?? false;
    return showDialog<bool>(
      context: context,
      animationStyle: isEink ? AnimationStyle.noAnimation : null,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          key: const Key('reading_stats_clear_all_dialog'),
          title: Text(l10n.statsClearAllTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(l10n.statsClearAllConfirmMessage),
          ),
          actions: [
            TextButton(
              key: const Key('reading_stats_clear_all_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('reading_stats_clear_all_confirm_button'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.statsClearAllTitle),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsScreenTitle)),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('reading_stats_loading'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildTotalCard(context, l10n),
                _buildHeatmapCard(),
                _buildDetailCard(context, l10n),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    key: const Key('reading_stats_clear_all_button'),
                    onPressed: _confirmAndClear,
                    child: Text(l10n.statsClearAllTitle),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTotalCard(BuildContext context, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    return EBFieldCard(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.statsTotalDuration, style: textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              formatReadingDuration(l10n, _totalSeconds),
              key: const Key('reading_stats_total_text'),
              style:
                  textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeatmapCard() {
    return EBFieldCard(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          ReadingHeatmap(
            grid: _grid,
            dailyTotals: _dailyTotals,
            selectedDate: _selectedDate,
            onSelectDate: _selectDate,
            scrollController: _scrollController,
          ),
          const SizedBox(height: 8),
          const ReadingHeatmapLegend(),
        ],
      ),
    );
  }

  Widget _buildDetailCard(BuildContext context, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    final dateLabel = DateFormat.yMd(l10n.localeName)
        .format(DateTime.parse(_selectedDate));
    return EBFieldCard(
      key: const Key('reading_stats_daily_detail_card'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.statsDailyDetailsTitle(dateLabel),
              key: const Key('reading_stats_detail_title'),
              style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            if (_details.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.statsNoDataOnDate,
                  key: const Key('reading_stats_detail_empty'),
                  style: textTheme.bodySmall,
                ),
              )
            else
              for (final stat in _details)
                Padding(
                  key: Key('reading_stats_detail_row_${stat.bookId}'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          // 書名快照若為空白，退回書籍 id，避免出現只有時數的空白列
                          stat.bookTitle.trim().isEmpty
                              ? stat.bookId
                              : stat.bookTitle,
                          style: textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatReadingDuration(l10n, stat.readingSeconds),
                        style: textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/reading_stats_screen_test.dart`
Expected: PASS

排錯提示（不改變設計）：
- 若「預設捲到最右側」失敗且 `offset` 為 0，確認 `_scrollToEndOnce()` 在 `setState` 之後呼叫，且 `pumpAndSettle()` 有跑到 post-frame callback。
- 若 E-Ink 對話框「一次 `pump()` 就該出現」失敗，確認 `animationStyle: AnimationStyle.noAnimation` 只在 `isEink` 為真時傳入；若 Flutter 版本對 `noAnimation` 仍需一個 frame，改成 `pump()` 後再 `pump(Duration.zero)`，不要改成 `pumpAndSettle()` 掩蓋。
- 若 `find.text('閱讀統計')` 找到兩個（AppBar 標題＋其他），表示畫面別處誤用了 `statsScreenTitle`，修畫面而非改測試。

- [x] **Step 5: 靜態檢查與提交**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `node tool/check_l10n_hardcoded_strings.js`
Expected: 通過（無新增硬編碼字串、測試檔的 `MaterialApp` 皆有 locale）。

```bash
git add lib/screens/reading_stats_screen.dart test/screens/reading_stats_screen_test.dart
git commit -m "feat(stats): epic-9 Issue 5 閱讀統計畫面（詳情卡片、累計時數、清除確認流程）" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6：設定頁入口、shell 轉交與收尾驗證

**Files:**
- Modify: `app/lib/screens/settings_scaffold.dart`
- Modify: `app/lib/screens/adaptive_shell_scaffold.dart`
- Test: `app/test/screens/settings_scaffold_reading_stats_test.dart`
- Docs: `docs/epics/epic-9-stats/issues.md`、`docs/epics/epic-9-stats/epic.md`

**Interfaces:**
- Consumes: Task 1 的 `statsScreenTitle`；Task 5 的 `ReadingStatsScreen(repository:)`；既有 `LibraryReaderFeatureRepositories.readingStatsRepository`（Issue 4）。
- Produces：
  - `SettingsScaffold` 新增選用參數 `final ReadingStatsRepository? readingStatsRepository`（預設 `null`）；非 null 時在「閱讀」分區、朗讀預設值項目之後顯示 `Key('settings_reading_stats_button')` 的 `ListTile`，點擊 push `ReadingStatsScreen`。
  - `AdaptiveShellScaffold` 把 `readerFeatureRepositories.readingStatsRepository` 轉交 `SettingsScaffold`。

- [x] **Step 1: 寫失敗測試**

建立 `app/test/screens/settings_scaffold_reading_stats_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/screens/adaptive_shell_scaffold.dart';
import 'package:elinkbook/screens/library_screen_dependencies.dart';
import 'package:elinkbook/screens/reading_stats_screen.dart';
import 'package:elinkbook/screens/settings_scaffold.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_library_repository.dart';
import '../support/fake_reader_prefs_manager.dart';
import '../support/fake_reading_stats_repository.dart';
import '../support/pump_localized_widget.dart';

void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('readingStatsRepository 為 null 時不顯示「閱讀統計」項目', (tester) async {
    _useTallView(tester);
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(prefsManager: FakeReaderPrefsManager()),
    );
    expect(find.byKey(const Key('settings_reading_stats_button')), findsNothing);
  });

  testWidgets('提供 repository 時顯示項目，點擊進入統計畫面', (tester) async {
    _useTallView(tester);
    await pumpLocalizedWidget(
      tester,
      SettingsScaffold(
        prefsManager: FakeReaderPrefsManager(),
        readingStatsRepository: FakeReadingStatsRepository(),
      ),
    );

    final entry = find.byKey(const Key('settings_reading_stats_button'));
    expect(entry, findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(ReadingStatsScreen), findsOneWidget);
    expect(find.byKey(const Key('reading_stats_heatmap')), findsOneWidget);
  });

  testWidgets('AdaptiveShellScaffold 把 bundle 內的 repository 轉交設定頁', (tester) async {
    _useTallView(tester);
    await pumpLocalizedWidget(
      tester,
      AdaptiveShellScaffold(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          readingStatsRepository: FakeReadingStatsRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 書架 → 來源 → 設定（比照 adaptive_shell_scaffold_test.dart 的切換方式）
    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sources_settings_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings_reading_stats_button')), findsOneWidget);
  });

  testWidgets('AdaptiveShellScaffold 的 bundle 沒有 repository 時設定頁不顯示項目', (tester) async {
    _useTallView(tester);
    await pumpLocalizedWidget(
      tester,
      AdaptiveShellScaffold(
        repository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        prefsManager: FakeReaderPrefsManager(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_source_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sources_settings_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings_reading_stats_button')), findsNothing);
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/settings_scaffold_reading_stats_test.dart`
Expected: FAIL（編譯錯誤：`The named parameter 'readingStatsRepository' isn't defined`）

- [x] **Step 3: 修改 `settings_scaffold.dart`**

匯入（依字母順序接在既有 import 之間）：

```dart
import '../stats/reading_stats_repository.dart';
```
與
```dart
import 'reading_stats_screen.dart';
```

（`reading_stats_screen.dart` 放在 `reading_defaults_screen.dart` 之後、`sync_settings_screen.dart` 之前。）

欄位（接在 `final bool isFullTextSearchAvailable;` 之後）：

```dart

  /// epic-9-stats Issue 5：閱讀統計 repository；null 時設定頁不顯示「閱讀統計」項目。
  final ReadingStatsRepository? readingStatsRepository;
```

建構子（接在 `this.isFullTextSearchAvailable = true,` 之後）：

```dart
    this.readingStatsRepository,
```

在「閱讀」分區、`settings_tts_defaults_button` 那張 `_SettingsCard` 之後（`if (!widget.isFullTextSearchAvailable)` 之前）加入：

```dart
          if (widget.readingStatsRepository != null)
            _SettingsCard(
              child: ListTile(
                key: const Key('settings_reading_stats_button'),
                title: Text(l10n.statsScreenTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ReadingStatsScreen(
                        repository: widget.readingStatsRepository!,
                      ),
                    ),
                  );
                },
              ),
            ),
```

- [x] **Step 4: 修改 `adaptive_shell_scaffold.dart`**

在 `SettingsScaffold(...)` 建構處、`isFullTextSearchAvailable: ...,` 之後加入：

```dart
              readingStatsRepository:
                  widget.readerFeatureRepositories.readingStatsRepository,
```

- [x] **Step 5: 執行測試確認通過，並跑既有設定頁／shell／主題測試**

Run: `flutter test test/screens/settings_scaffold_reading_stats_test.dart test/screens/settings_scaffold_test.dart test/screens/adaptive_shell_scaffold_test.dart test/theme test/l10n`
Expected: PASS

- [x] **Step 6: 靜態檢查、l10n 檢查與提交**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `node tool/check_l10n_hardcoded_strings.js`
Expected: 通過。

```bash
git add lib/screens/settings_scaffold.dart lib/screens/adaptive_shell_scaffold.dart test/screens/settings_scaffold_reading_stats_test.dart
git commit -m "feat(stats): epic-9 Issue 5 設定頁「閱讀統計」入口並由 shell 轉交 repository" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [x] **Step 7: 真機目視確認（有裝置時；無裝置環境不阻擋本 Issue 完成，需在完成記錄註明「未驗證」）**

Run: `flutter devices` 取得 `<device-id>`，再 `flutter run -d <device-id>`（debug 版）。先讀一段書讓資料庫有紀錄（Issue 4 已接好），然後：

1. 設定 → 閱讀統計：貢獻圖預設停在最右側、今天有外框；左右滑動時星期欄不動、月份標籤跟著方格走。
2. 點選其他方格：外框四邊完整（右、下不被裁）、下方詳情切換。
3. 切換 Light／Dark／Sepia：方格顏色跟著主題，Dark 的第 0 級方格看得見。
4. 開啟 E-Ink 修飾子：五級靠「黑框＋紋理」可區分；**特別檢查第 3 級（`#525252` 底疊黑色交叉線）紋理是否辨識得出**，若不理想，依上方「已知取捨」改成原型的白底做法（只改 `HeatmapCellPainter.paint()`，並同步調整 `reading_heatmap_test.dart` 中對 `fillColor` 的斷言）。
5. 清除全部統計：出現確認對話框、取消不變、確認後畫面清空並出現提示；E-Ink 下對話框無淡入淡出。
6. 英文介面：星期標籤「Mon／Wed／Fri」不折行、與方格列對齊。

把觀察結果（含未驗證項目）記入下一步的 `epic.md` 完成記錄。

- [x] **Step 8: 突變驗證（證明測試真的會抓到錯；每項改完只跑對應測試檔，確認失敗後立即還原）**

| # | 突變（暫時修改） | 必須失敗的測試檔 |
|---|---|---|
| 1 | `heatmapLevelForSeconds` 的 `seconds < 15 * 60` 改為 `<= 15 * 60` | `test/stats/heatmap_grid_test.dart` |
| 2 | `formatReadingDuration` 拿掉「有紀錄但不滿 1 分鐘顯示 1 分鐘」那一行 | `test/stats/reading_duration_format_test.dart` |
| 3 | `ReadingHeatmap` 不再建構選取外框（拿掉 `if (selected != null)` 區塊） | `test/screens/reading_heatmap_test.dart`、`test/screens/reading_stats_screen_test.dart` |
| 4 | `_WeekdayColumn` 把週一標籤的 `l10n.statsWeekdayMon` 改成 `l10n.statsWeekdayWed` | `test/screens/reading_heatmap_test.dart`（英文標籤測試） |
| 5 | `SettingsScaffold` 拿掉 `if (widget.readingStatsRepository != null)` 條件（無條件顯示） | `test/screens/settings_scaffold_reading_stats_test.dart` |
| 6 | `_selectDate` 拿掉 `requestId != _detailRequestId` 判斷 | `test/screens/reading_stats_screen_test.dart`（連點競態） |
| 7 | `_confirmAndClear` 的 `_loadAll(selecting: _todayKey)` 改回 `_loadAll()` | `test/screens/reading_stats_screen_test.dart`（清除後回到今天） |

每項都必須觀察到「測試失敗」才算通過；若某項突變後測試仍全過，代表該行為沒有被測試鎖住，先補測試再往下走。全部還原後以 `git diff` 確認沒有殘留的突變修改。

- [x] **Step 9: 完整測試與最終檢查（整張計畫最後一個 Task，跑一次完整測試）**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: 全數通過（前次基準：Issue 4 完成時 3134 通過、1 跳過、0 失敗；本 Issue 新增測試後總數增加，跳過數不變）。

Run: `node tool/check_l10n_hardcoded_strings.js`
Expected: 通過。

Run: `git status --short`
Expected: 沒有未提交的異動；確認 `lib/l10n/app_localizations*.dart` 已包含在提交中（`git log --stat -3 -- lib/l10n`）。

- [x] **Step 10: 文件收尾（程式審查完成、PR 合併後才寫入 PR 編號）**

- `docs/epics/epic-9-stats/issues.md`：Issue 5 的 `**Status:**` 由 `ready-for-agent` 改為 `completed`。
- `docs/epics/epic-9-stats/epic.md`：新增「Issue 5 完成記錄」段落（做了什麼、計畫補充的決定〔沿用本計畫「已知取捨與偏離」〕、驗證結果〔analyze、完整 `flutter test` 通過數與 commit、真機確認結果或「未驗證」項目〕、已知限制），並把「目前狀態」改為「五張 Issue 全數完成，待歸檔」。
- `docs/epics.md` 第 13 列備註改為「全數完成，待歸檔」（只寫精簡摘要，歷程留在 `epic.md`）。
- 程式審查報告存於 `docs/epics/epic-9-stats/reviews/review-issue-5.md`（`reviews/` 已在 `.gitignore`，不進版控）。

---

## 自我檢查（計畫撰寫者已執行）

**Spec／issues.md 覆蓋對照：**

| 要求 | 對應 |
|---|---|
| 設定頁入口、null 時不顯示、同一 bundle 取得 repository | Task 6 |
| 近 365 天、週一起始、首末週透明佔位、五級分級、圖例 | Task 3（邏輯）、Task 4（繪製） |
| 左側固定星期欄、右側水平捲動、預設最右側 | Task 4（星期欄／捲動容器）、Task 5（預設捲到最右） |
| 詳情卡片：預設今天、無紀錄說明、點選切換＋高對比外框、依時數排序、書名快照、無 Tooltip | Task 4（外框）、Task 5 |
| 累計總時數與格式 | Task 3（格式）、Task 5 |
| 清除全部：底部、確認對話框、成功後空白＋提示、取消不變 | Task 5 |
| `ElinkTokens` 五級色階（Light／Dark／Sepia／E-Ink 灰階）＋ E-Ink 紋理繪製 | Task 2、Task 4 |
| 4 份 ARB、`flutter gen-l10n`、產出檔入版控、`check_l10n_hardcoded_strings.js` | Task 1、Task 5／6 Step |
| Widget Key 契約（`settings_reading_stats_button` 等六個） | Task 4／5／6 的 Interfaces 與測試 |
| 測試：五級分級、週一對齊、星期欄固定、清除流程、E-Ink、三語言；Token 測試；設定頁 null 測試；既有測試不回歸；完整 `flutter test` | Task 2～6 |

**佔位符掃描：** 計畫內沒有 TBD／TODO／「之後補」；每個程式碼步驟都附完整程式碼；唯一「依實際結果調整」的是 Task 1 Step 6（gen-l10n 產出簽章比對）、Task 4／5 的排錯提示與 Task 6 Step 7 的真機結果，皆屬需實測才能確定的項目，並已寫明處置。

**型別一致性：** `HeatmapGrid.weeks`（`List<List<String?>>`）、`locate()` 回傳 `({int week, int row})?`、`HeatmapCellPainter{level, fillColor, isEink, inkColor, texture}`、`HeatmapSelectionOutlinePainter{color, strokeWidth}`、`ReadingHeatmap` 五個參數、`ReadingStatsScreen(repository, nowProvider)`、`formatReadingDuration(l10n, seconds)`、`ElinkTokens.heatmapLevel0..4`／`heatmapLevelColor(int)` 在各 Task 的定義與使用一致；測試用的 Key 字串與實作逐一對照過。

**Review Focus 覆蓋：** 英文星期標籤（Task 4 英文測試＋Task 5 英文測試）、快速連點競態（Task 5）、全新安裝（Task 5）、視窗外舊資料（Task 5）、超長書名（Task 5）皆各有測試。

**計畫審查修訂記錄（`reviews/review-plan-issue-5.md`）：**
- I-2 已採納：`_loadAll({String? selecting})`，清除後以 `selecting: _todayKey` 回到今天；新增測試「先選了過去的日期再清除：清除後選取日回到今天」。
- M-1 已採納：`buildHeatmapGrid` 範圍判斷改比對日期字串。
- M-2 已採納：`formatReadingDuration` 對 `seconds <= 0` 直接回傳「0 分鐘」，並補負數測試。
- M-3 已採納：詳情列書名為空白時退回 `bookId`，並補測試。
- M-4 已採納：Task 6 新增 Step 8 突變驗證清單（7 項，含針對 I-2 與連點競態的兩項）。
- I-1 **未採納**：`_drawDiagonals` 的 `k = 16` 線（`x + y = 32`）只碰到方格右下角一個點，且繪製前的 `clipRect(rect.deflate(1))` 只保留 1..15 的範圍（`x + y ≤ 30`），該線畫了也看不到；左側的 `k = -16`（`x + y = 0`）同樣被裁掉。實際可見的線為 `x + y ∈ {4, 8, …, 28}`，以 16 為中心對稱，沒有缺角。
