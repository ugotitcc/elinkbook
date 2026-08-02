# Epic 14 — 系統設定：規格 (Spec)

這是實作 `epic-14-system-settings` 的唯一事實來源。決策的完整討論過程與理由請見 `design.md`（`/grill-with-docs` 2026-08-02，7 項決策，含 `/superpowers:requesting-code-review`／`/superpowers:receiving-code-review` 審查修訂，見 `tmp/epic-14/review-design.md`與 `tmp/epic-14/review-spec.md`）與 [ADR 0021](../../adr/0021-custom-font-content-uri-no-copy.md)（自訂字型不落地複本的架構決策）。本文件延續 `design.md` 的所有範圍界定，不重複列出理由，僅在此定案核心行為決策，供 Scrum Master 階段拆解工單使用。

## Problem Statement

`SettingsScreen`（`epic-18` Issue 24 建立）目前只有「佈景」「導航熱區」「關於」三個項目。使用者目前完全沒有辦法：

- 上傳/管理自訂字型，只能從 5 款內建字型中選（FR-35）。
- 用一個總開關停用音量鍵翻頁（FR-36），只能單書逐一設定螢幕方向/翻頁模式覆寫。
- 設定「跨書籍生效」的螢幕方向、翻頁模式、全螢幕顯示預設值，每本新匯入的書都要重新設一次（FR-37/38/42）。

另外，`NavZoneSettingsScreen`（`epic-7` 既有畫面）的熱區模板選擇目前是純文字 `RadioListTile`，使用者要靠讀文字理解「左翻頁/右翻頁/單手」三種模板的實際分區方式，不夠直覺。

## Solution

在既有的 `SettingsScreen` 之上，新增：

1. **字型管理**（FR-35）：獨立子畫面，支援批次上傳 `.ttf`/`.otf`、清單顯示（內建 5 款＋自訂）、重新命名、刪除（含使用中字型自動退回預設與快取刷新）。
2. **閱讀預設值**（FR-36/37/38/42）：獨立子畫面，集中音量鍵開關、螢幕方向 5 選一、翻頁模式 2 選一、全螢幕開關，各自獨立即時生效。
3. **導航熱區模板圖示化**：`NavZoneSettingsScreen` 改為「簡單／自訂」二選一（`SegmentedButton`），「簡單」下方橫排 3 張圖示卡片取代文字 `RadioListTile`。

## User Stories

1. 作為一個想用特定字體閱讀的使用者，我想要上傳自己喜歡的字型檔案，這樣就不受限於 App 內建的 5 款字型。
2. 作為一個上傳過多款字型的使用者，我想要一次選取多個字型檔案批次上傳，不用一款一款重複操作。
3. 作為一個不小心上傳重複字型的使用者，系統會直接擋下並告訴我「這款字型已存在」，這樣我不會在清單裡看到一堆看起來一樣的項目。
4. 作為一個想清理字型清單的使用者，我可以刪除不需要的自訂字型；如果目前有書正在用這款字型，系統會先提醒我有幾本書會被改回預設字型。
5. 作為一個不喜歡音量鍵翻頁的使用者，我想要一個總開關直接關掉這個功能，不用進每本書分別關。
6. 作為一個習慣直向閱讀的使用者，我想要設定一個全域的螢幕方向預設值，這樣新匯入的書一開始就是我想要的方向，不用每本都重設。
7. 作為一個習慣滾動閱讀的使用者，我想要設定全域翻頁模式預設為「滾動翻頁」，同理。
8. 作為一個喜歡沉浸式閱讀的使用者，我想要設定全域的「全螢幕顯示」預設為開啟，涵蓋我讀的所有格式（流式/固定版面/PDF）。
9. 作為一個在書架情境下調整這些預設值的使用者（此時沒有任何書籍畫面可以預覽效果），我希望每項設定切換的當下就直接生效並被記住，不需要額外按「儲存」，這樣我不用擔心自己忘記存檔。
10. 作為一個第一次設定熱區模板的使用者，我想要用色塊+箭頭圖示的視覺化卡片來選「左翻頁/右翻頁/單手」，而不是猜文字敘述代表的實際分區長什麼樣子。
11. 作為一個想要完全自訂熱區的使用者，我切到「自訂」分頁後，看到的還是原本熟悉的 9 格編輯器，不會因為這次改版而重新學一次操作方式。

## Implementation Decisions

### 範圍界定（承接 `design.md`，不重複展開理由）

- FR-39（同步設定入口）完全由 `epic-8-sync` 處理，本 epic 不建立任何相關 UI。
- PDF 不套用自訂字型（原生點陣圖渲染），FR-35 只對 EPUB 生效。
- 音量鍵翻頁的原生攔截邏輯本身（`epic-7`）與螢幕方向/翻頁模式的全域-單書雙層解析邏輯（既有 `resolve()`）皆已存在，本 epic 只新增 UI 與（`fullscreen`／`volumeKeyEnabled`）解析邏輯擴充與門閥判斷。

### 字型管理模組

- **資料模型**：新表 `custom_fonts`（`id INTEGER PRIMARY KEY`／`display_name TEXT`／`family_name TEXT UNIQUE`／`font_uri TEXT`）。`book_reader_prefs.fontFamily` 型別由 `AppFont?` 改為 `String?`（family name 字串），內建 5 款字型的 family name 為固定常數（`app_font.dart` 既有 `AppFontFamilyName.familyName`），自訂字型的 family name 來自上傳時解析結果。
- **上傳與二進位解析流程**：`file_picker`（`FileType.custom`，`allowedExtensions: ['ttf', 'otf']`，`allowMultiple: true`）→ 對每個選中檔案：`takePersistableUriPermission()` → 手刻最小化 Dart 二進位解析器讀取 `name` table 取得 family name。解析解碼優先順序：
  1. Platform 3 (Windows) Unicode 16-bit BigEndian (UTF-16BE)，`nameID=1` (Font Family)。
  2. Platform 1 (Macintosh)，`nameID=1`。
  3. `nameID=4` (Full Name) 或 `nameID=6` (PostScript Name) 回退條目。
  4. 若皆無法解碼或二進位結構損壞，退回檔名去副檔名作為 family name。
  比對 `custom_fonts.family_name` 是否已存在，存在則跳過並計入「已存在」計數、不存在則寫入新記錄並計入「已新增」計數 → 全部處理完後用單一合併訊息呈現結果（比照 `epic-21` `ImportResult` 模式，例如「已新增 3 款字型，2 款已存在已跳過」）。
- **顯示名稱**：預設用檔名（去副檔名），使用者可於清單重新命名（僅改 `display_name`，不影響 `family_name`）。
- **刪除流程與連動**：點擊刪除 → 查詢 `book_reader_prefs` 中 `font_family = 該 family_name` 的書籍數量 → 跳出 `AlertDialog`（一般情況「確定要刪除『{display_name}』嗎？」；使用中情況額外附加「目前有 {N} 本書使用此字型，刪除後將自動改用預設字型」）→ 確認後於同一交易內執行 `DELETE FROM custom_fonts WHERE id = ?` 與 `UPDATE book_reader_prefs SET font_family = NULL WHERE font_family = ?`。**不需要額外的快取清除或開啟中閱讀器通知機制**：`ReaderPrefsManager` 本身不含任何記憶體快取（純 I/O + 純函式 `resolve()`），而 `SettingsScreen`／`FontManagementScreen` 只能從 `LibraryScreen` 進入（`library_screen.dart:623`），`ReaderScreen` 沒有通往此畫面的路徑，刪除字型當下不可能有該書的 `ReaderScreen` 同時存在——下次重新開啟該書時 `load()`/`resolve()` 自然讀到已改為 `NULL` 的 `fontFamily` 並退回預設字型。
- **清單呈現**：不即時查詢/顯示「使用中」標記（避免清單捲動觸發大量查詢），使用情況只在刪除當下查詢一次。
- **服務機制**（見 `design.md` 決策 3、[ADR 0021](../../adr/0021-custom-font-content-uri-no-copy.md)）：`foliate_native_bridge.dart` 的 `buildFontFaceCss()` 擴充為同時輸出內建與自訂字型的 `@font-face` 規則（自訂字型指向新虛擬路徑前綴 `/assets/custom-fonts/<familyName>`）；`foliate_epub_reader_view.dart` 的 `_shouldInterceptRequest` 新增對應分支呼叫新橋接函式；`ReaderResourceChannel.kt` 新增 `readCustomFontBytes(uri)`，以 `ContentResolver.openInputStream(uri).use { it.readBytes() }` 一次性讀取回傳，不落地快取（與既有 `readAndroidAsset` 同構，非 `cacheBookForServing` 的落地快取模式）。

### 閱讀預設值模組

- 新建 `ReadingDefaultsScreen`，四個獨立控制項，讀寫 `GlobalReaderPrefs`：
  - 音量鍵翻頁開關（`SwitchListTile`，讀寫 `volumeKeyEnabled`，預設 `true`）
  - 螢幕方向（5 選一，讀寫既有 `screenOrientation`／`ScreenOrientationSetting`）
  - 翻頁模式（2 選一，讀寫既有 `pageTurnMode`／`PageTurnMode`）
  - 全螢幕顯示開關（`SwitchListTile`，讀寫新增 `fullscreen`，預設 `false`）
- **即時生效，不設「儲存」按鈕**：每項控制項變更當下立即呼叫 `saveGlobalPrefs()` 寫入並生效，比照 `NavZoneSettingsScreen` 既有互動模式，全 App 維持一致的設定頁 UX；四項彼此獨立、無需要一起提交的欄位依賴關係，即時生效不會造成中間狀態不一致的風險。
- **`ResolvedPreferences` 擴充與音量鍵門閥判定**：
  - `ResolvedPreferences` 新增 `volumeKeyEnabled: global.volumeKeyEnabled` 與 `fullscreen: book.fullscreen ?? global.fullscreen`（`reader_prefs_manager_impl.dart`）。
  - `ReaderScreen._handleVolumeKeyCall` 收到原生端 `onVolumeKey` 回呼時，早期檢查 `if (_resolved?.volumeKeyEnabled == false) return;`，當全域音量鍵翻頁關閉時，忽略此觸發，不執行 `_handleZoneAction` 翻頁。
- `GlobalReaderPrefs` 新增欄位與既有 `global_reader_<欄位名>` 命名慣例一致的 SharedPreferences key：`volumeKeyEnabled`（`global_reader_volume_key_enabled`）、`fullscreen`（`global_reader_fullscreen`）。

### 導航熱區模板圖示化

- `NavZoneSettingsScreen` 頂部新增 `SegmentedButton<bool>`（`false`=簡單／`true`=自訂，映射至 `navZoneMode == NavZoneMode.custom`）。
- **「簡單」**（`navZoneMode != NavZoneMode.custom`）：橫排 3 張圖示卡片（左翻頁／右翻頁／單手，各自繪製縮小版三欄示意圖：左/中/右三色區塊＋←/≡/→圖示），點選即呼叫既有 `_selectMode()` 立即全域生效；屬性與目前 `navZoneMode` 一致的卡片呈現 Selected 選中外框。
- **「自訂」**（`navZoneMode == NavZoneMode.custom`）：導向現有 9 格編輯器（`nav_zone_settings_screen.dart` 既有實作不動），維持 Epic 7 既有的「至少 1 格須為選單 `ZoneAction.menu`」儲存前驗證。
- 切換「簡單／自訂」本身不清空／不重新初始化 `navZoneCustomActions`（9 格自訂資料）——只是 UI 呈現切換，兩種模式底下的資料各自獨立保留在 `GlobalReaderPrefs`，切回「自訂」時使用者上次編輯的 9 格配置原樣還在。

### Migration

- SQLite 版本自 15 升級至 16（`sqlite_library_repository.dart`）：
  1. 建立 `custom_fonts` 表。
  2. `book_reader_prefs.font_family` 欄位型別遷移：既有 `AppFont` 列舉值字串（`sourceHanSans`／`sourceHanSerif`／`guanKiapTsingKhai`／`taiwanPearl`／`genRyuMinTW`）逐筆轉換為對應 family name 字串（`SourceHanSansTC`／`SourceHanSerifTC`／`GuanKiapTsingKhai`／`TaiwanPearl`／`GenRyuMinTW`），`NULL` 維持 `NULL`。
- `GlobalReaderPrefs` 新增欄位透過 SharedPreferences 新 key 存放，不需要 SQLite migration（既有慣例，`global_reader_prefs.dart` 全域值皆走 SharedPreferences）。

## Testing Decisions

- **接縫**：`SettingsScreen` 既有公開入口模式（`ListTile` → `Navigator.push`），新畫面比照既有 `NavZoneSettingsScreen`/`AboutScreen` 慣例，不新增測試接縫。
- **`app/test/`**（純 widget test，不需真機）：
  - 字型名稱二進位解析器的純函式單元測試（提供已知 Unicode/Mac name table 的 `.ttf`/`.otf` fixture，於 `app/test/fixtures/`，斷言解析結果；提供無 name table / 損壞的畸形檔案，斷言退回檔名）。
  - `FontManagementScreen`：批次上傳結果合併訊息、重複阻擋、刪除確認對話框（一般/使用中兩種文案，含正確查詢使用中書籍數量）、刪除後 `book_reader_prefs.font_family` 確實被設回 `NULL`、重新命名。
  - `ReadingDefaultsScreen`：四項控制項切換即時呼叫 `saveGlobalPrefs()`、初始值正確讀取既有 `GlobalReaderPrefs`、音量鍵關閉時 `ReaderScreen` 阻擋翻頁。
  - `NavZoneSettingsScreen`：`SegmentedButton` 切換簡單/自訂、圖示卡片點選套用模板與 Selected 狀態、切換後 `navZoneCustomActions` 保留不被清空、防死鎖驗證維持。
  - `reader_prefs_manager_impl_test.dart`（或既有測試檔案）：`resolve()` 的 `fullscreen` 雙層解析（`book.fullscreen ?? global.fullscreen`）與 `volumeKeyEnabled` 三種情境測試。
- **`app/integration_test/`**（真機）：
  - 自訂字型端到端流程：上傳測試字型 fixture → 開啟測試 EPUB → 套用該字型 → 確認 `readCustomFontBytes` 呼叫成功、頁面無 `Key('reader_error_text')`。實際視覺是否正確換成該字體列為人工真機驗收項目，比照專案既有「自動化驗證機制運作、視覺效果人工確認」慣例（例如 `epic-4` PDF 濾鏡效果）。
- 良好測試的判準（比照專案既有慣例，非本 epic 新創）：只驗證外部可觀察行為與資料庫/SharedPreferences 最終寫入值，不斷言內部實作細節。

## Out of Scope

- FR-39（同步設定入口）——`epic-8-sync` 職責。
- PDF 自訂字型——PDF 不套用字型設定。
- 音量鍵原生攔截邏輯本身——`epic-7-interaction` 已完成，本 epic 只加開關與門閥控制。
- 字型清單即時顯示「使用中」標記——僅刪除當下查詢。
- `ReadingDefaultsScreen` 的「放棄變更」確認對話框——即時生效模式下無此情境。

## Further Notes

- 本規格未列出所有欄位/方法的最終精確簽章（例如 `readCustomFontBytes` 確切的 method channel 參數/回傳型別），實作前請參閱 `design.md`「架構影響摘要」表格，實際簽章留待實作計畫階段（`plans/plan-issue-N.md`）決定。
- `ReadingDefaultsScreen` 採「即時生效、無儲存按鈕」與 `NavZoneSettingsScreen` 一致，但與一般直覺「書架情境下沒有預覽、應該要有儲存確認」的想法不同——這是刻意討論後的決定（見 `design.md`／grilling 對話紀錄：無預覽跟要不要即時存檔是兩個獨立問題，四項設定彼此獨立不需要批次提交語意），避免日後被誤認為疏漏而「修正」成儲存按鈕模式。
- 字型檔案本身不落地複本（[ADR 0021](../../adr/0021-custom-font-content-uri-no-copy.md)），使用者若在系統檔案管理員搬移/刪除原始字型檔會導致字型失效——與既有書籍檔案的風險一致，UI 不需要對此做特殊防禦（例如定期檢查 URI 是否仍可存取），發生時比照書籍檔案的既有處理方式（開啟失敗才處理）即可。

## 審查修正紀錄（`tmp/epic-14/review-spec.md`）

- **Critical（確認屬實，已採納）**：`volumeKeyEnabled` 全域開關缺乏 `ResolvedPreferences`／`ReaderScreen` 端的門閥判定，關掉開關後音量鍵仍會翻頁。已於「閱讀預設值模組」補上 `ResolvedPreferences.volumeKeyEnabled` 欄位與 `ReaderScreen._handleVolumeKeyCall`（`reader_screen.dart:1886`，`_resolved` 欄位見 `reader_screen.dart:171`，皆已核對存在）的早期 `return` 檢查。
- **Critical（確認屬實，已採納）**：手刻二進位字型解析器缺乏編碼優先順序指引，中文字型檔容易解析出亂碼。已補上 Platform 3 UTF-16BE → Platform 1 Mac → nameID 4/6 回退 → 檔名的標準 TrueType/OpenType 解碼順序。
- **Important（前提有誤，已修正為反映實際情況）**：審查建議刪除字型時要清除 `ReaderPrefsManager` 記憶體快取並通知開啟中的 `ReaderScreen` 刷新。查證後 `ReaderPrefsManager` 完全不含任何記憶體快取（`reader_prefs_manager.dart`／`_impl.dart` 皆為純 I/O + 純函式 `resolve()`），且 `SettingsScreen`／`FontManagementScreen` 只能從 `LibraryScreen` 進入（`library_screen.dart:623`）、`ReaderScreen` 無通往此畫面的路徑，刪除字型當下不可能有該書的 `ReaderScreen` 同時存在——此建議描述的情境在本 App 導覽結構下不會發生。已移除虛構的快取清除/通知機制，改為說明下次開書時 `load()`/`resolve()` 自然讀到 `NULL` 退回預設字型即可，不需額外處理（YAGNI）。對應測試項目（原「刪除後偏好快取與閱讀器重置」）已改為驗證 `book_reader_prefs.font_family` 確實寫回 `NULL`。
- **Important（確認屬實，已採納）**：`SegmentedButton<bool>` 與 4 選一 `NavZoneMode` 的映射關係補充明確定義（已於當前版本套用，維持不變）。
- **Minor（確認屬實，已採納）**：字型解析器測試 fixture 路徑已標明為 `app/test/fixtures/`。
