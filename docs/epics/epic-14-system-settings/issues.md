# Epic 14 — 系統設定：工單清單 (Issues)

依 `spec.md`（搭配 `design.md`、`/grill-with-docs` Discovery + Architecting，另見 [ADR 0021](../../adr/0021-custom-font-content-uri-no-copy.md)）拆解出的 5 個垂直切片工單。字型模組為循序鏈：Issue 1（資料模型＋解析器）→ Issue 2（管理畫面＋單書選擇器整合）→ Issue 3（Foliate-JS 原生渲染）。Issue 4（閱讀預設值）與 Issue 5（導航熱區圖示化）皆與字型模組完全獨立、彼此也互不依賴，可與 Issue 1 平行開始。

`/to-issues` 拆解過程中發現一個 `spec.md` 未提及的缺口：既有單書字型選擇器（`reader_settings_sheet.dart:424-438`，目前寫死走訪 `AppFont.values`）需要跟著 `book_reader_prefs.fontFamily` 型別遷移一併改為合併「內建 5 款＋自訂字型清單」，否則使用者上傳字型後無從選用。已併入 Issue 2 範圍。

---

## Issue 1：自訂字型資料模型 + 二進位解析器

**Status:** ✅ 已完成並合併（PR #99，`feat/epic-14-issue-1-custom-fonts` → `main`，2026-08-02）——依 `plans/plan-issue-1.md` 3 個 Task 實作：`custom_fonts` 表＋SQLite v15→v16 migration（既有 `AppFont` 列舉值字串資料轉換為 family name 字串）、`fontFamily` 型別由 `AppFont?` 貫穿改為 `String?`（`BookReaderPrefs`／`ResolvedPreferences`／`FoliateEpubReaderView`／`reader_settings_sheet.dart` 字型選單，行為零變更）、手刻 TTF/OTF `name` table 二進位解析器（含真實字型檔 `app/test/fixtures/sample.ttf` 測試案例）。`/superpowers:requesting-code-review` 程式碼審查發現並修正 1 項 Critical（`_createCustomFontsTable` 誤放在 `onUpgrade` 的 `else`／`oldVersion>=2` 分支內，導致停留在 schema version 1 的裝置跳級升級到 16 時該表不會被建立，已搬到頂層無條件執行並補回歸測試）與 1 項 Important（`reader_prefs_manager_test.dart` 遺漏計畫要求的測試，已補上）；1 項 Minor 建議（移除 migration 函式防禦性檢查）實測會打壞既有無關測試，予以保留並非疏漏。全專案 `flutter test`／`flutter analyze` 皆確認乾淨。詳見 `plans/plan-issue-1.md`「審查修正紀錄」與 `tmp/epic-14/review-issue-1.md`（未進版控）。

**依賴／Blocked by：** None - can start immediately

**What to build：**

新增 `custom_fonts` 表（`id INTEGER PRIMARY KEY`／`display_name TEXT`／`family_name TEXT UNIQUE`／`font_uri TEXT`），與 `book_reader_prefs.font_family` 欄位型別遷移（`AppFont?` 封閉列舉 → `String?` family name 字串）。SQLite 版本自 15 升級至 16，比照既有累加式 `if (oldVersion < N)` 慣例，全新安裝（`onCreate`）與既有裝置升級（`onUpgrade`）兩條路徑皆須涵蓋（比照 `epic-6` Issue 1 的全新安裝防禦教訓）。既有 `AppFont` 列舉值需逐筆轉換為對應 family name 字串（`sourceHanSans`→`SourceHanSansTC`／`sourceHanSerif`→`SourceHanSerifTC`／`guanKiapTsingKhai`→`GuanKiapTsingKhai`／`taiwanPearl`→`TaiwanPearl`／`genRyuMinTW`→`GenRyuMinTW`，取自 `app_font.dart:19-32` 現行 `AppFontFamilyName.familyName` 實際值），`NULL` 維持 `NULL`。

新增手刻最小化 Dart 二進位解析器，讀取 TTF/OTF 檔案的 `name` table 取得 family name，解碼優先順序：Platform 3（Windows）Unicode 16-bit BigEndian，`nameID=1`（Font Family）→ Platform 1（Macintosh），`nameID=1` → `nameID=4`（Full Name）或 `nameID=6`（PostScript Name）回退 → 皆無法解碼或二進位結構損壞時，退回檔名（去副檔名）作為 family name。不引入第三方套件（比照 `foliate-js` 釘定複製、TXT 引擎規劃自訂輕量解析的既有慣例）。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - `custom_fonts` 表 schema migration：全新安裝（`onCreate`）與既有裝置升級（`onUpgrade`，涵蓋從各種舊版本跳級）皆須驗證表格存在、`book_reader_prefs.font_family` 型別遷移後既有 5 種列舉值資料正確轉換為對應 family name 字串、`NULL` 值不受影響。
  - 二進位解析器純函式單元測試：提供已知 Unicode（Platform 3）name table 的 `.ttf`/`.otf` fixture（存於 `app/test/fixtures/`），斷言解析出正確 family name；提供僅有 Platform 1（Mac）記錄的 fixture，驗證回退路徑；提供無 `name` table 或二進位結構損壞的畸形檔案，驗證退回檔名邏輯。

**驗收標準：**

- [x] `custom_fonts` 表與累加式 migration（v15→16）正確建立，`onCreate`／`onUpgrade` 兩條路徑皆不拋出例外
- [x] `book_reader_prefs.font_family` 型別遷移正確：既有 5 種 `AppFont` 列舉值資料轉換為對應 family name 字串，`NULL` 不受影響
- [x] 二進位解析器對 Unicode／Mac 兩種 name table 記錄皆能正確解析 family name
- [x] 解析器對畸形/無 `name` table 檔案正確退回檔名
- [x] 上述測試皆通過，`flutter analyze` 乾淨

---

## Issue 2：字型管理畫面 + 單書字型選擇器整合

**Status:** ✅ 已完成並合併（PR #100，`feat/epic-14-issue-2-font-management` → `main`，2026-08-02）——依 `plans/plan-issue-2.md` 4 個 Task 實作：`CustomFont`／`CustomFontsRepository`、`FontManagementScreen`（批次上傳、內建 5 款字型阻擋重名、清單、重新命名、刪除含使用中提示與級聯重置）、`SettingsScreen`「字型管理」入口＋`customFontsRepository` 全鏈路貫穿（含 `LibraryScreen._openGroupFilteredView()` 遞迴建構點）、`reader_settings_sheet.dart` 字型選單合併自訂字型清單＋`ReaderScreen` 貫穿。計畫審查（`/superpowers:requesting-code-review`）發現並修正 1 項 Critical（自訂字型與內建字型 family name 相同會導致 `DropdownButton` 重複 `value` 崩潰）；實作審查另發現並修正 1 項 Important（`_renameFont` 的 `TextEditingController` 缺釋放，首次修法 `try/finally` 立即 dispose 實測會觸發 Flutter Focus assertion 崩潰，改採本專案 `notes_bottom_sheet.dart` 既有的「State 生命週期保管」正確模式）與 1 項 Important（plan checkbox 追蹤失準已補齊）。全專案 `flutter test`／`flutter analyze` 皆確認乾淨。詳見 `plans/plan-issue-2.md`「審查修正紀錄」與 `tmp/epic-14/review-plan-issue-2.md`／`review-issue-2.md`（未進版控）。

**依賴／Blocked by：** Issue 1

**What to build：**

新建 `FontManagementScreen`：`file_picker`（`FileType.custom`，`allowedExtensions: ['ttf', 'otf']`，`allowMultiple: true`）批次選取字型檔 → 對每個檔案 `takePersistableUriPermission()` → 呼叫 Issue 1 的二進位解析器取得 family name → 比對 `custom_fonts.family_name` 是否已存在，存在則跳過並計入「已存在」計數、不存在則寫入新記錄並計入「已新增」計數 → 全部處理完後用單一合併訊息呈現結果（比照 `epic-21` `ImportResult` 模式，例如「已新增 3 款字型，2 款已存在已跳過」）。清單顯示內建 5 款＋自訂字型（顯示名稱預設用檔名去副檔名，使用者可重新命名，僅改 `display_name` 不影響 `family_name`）。刪除自訂字型：查詢 `book_reader_prefs` 中使用該 family name 的書籍數量 → 跳出 `AlertDialog`（一般情況「確定要刪除『{display_name}』嗎？」；使用中情況額外附加「目前有 {N} 本書使用此字型，刪除後將自動改用預設字型」）→ 確認後同一交易內執行 `DELETE FROM custom_fonts` 與 `UPDATE book_reader_prefs SET font_family = NULL WHERE font_family = ?`。清單不即時顯示「使用中」標記（僅刪除當下查詢一次）。

`SettingsScreen` 新增「字型管理」入口（比照既有「導航熱區」`ListTile` → `Navigator.push` 模式）。

**整合既有單書字型選擇器**（`reader_settings_sheet.dart:424-438`）：`_fontFamily` 欄位型別由 `AppFont?` 改為 `String?`；選項清單改為合併內建 5 款固定 family name 常數＋查詢 `custom_fonts` 表取得的自訂字型清單；顯示文字內建字型沿用既有中文名稱對照（`_fontFamilyLabel` 等既有函式，`reader_settings_sheet.dart:449-457`），自訂字型顯示其 `display_name`。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - `FontManagementScreen`：批次上傳成功/部分重複的合併訊息文案、重複阻擋（同 family name 不建立新記錄）、刪除確認對話框（一般/使用中兩種文案，含正確查詢使用中書籍數量）、刪除後 `book_reader_prefs.font_family` 確實被設回 `NULL`、重新命名只改 `display_name`。
  - `SettingsScreen`：新增「字型管理」入口，點擊導航至 `FontManagementScreen`。
  - `reader_settings_sheet.dart` 字型選擇器：選項清單正確合併內建 5 款＋自訂字型、選擇自訂字型後正確寫入 `_fontFamily`（`String`）、既有內建字型中文名稱顯示不受影響。

**驗收標準：**

- [x] 批次上傳（多選）成功新增字型，重複 family name 正確阻擋並計入合併訊息
- [x] 字型清單顯示內建 5 款＋自訂字型，可重新命名（僅改顯示名稱）
- [x] 刪除字型：一般情況與使用中情況顯示不同確認文案，確認後正確刪除記錄且相關書籍 `font_family` 設回 `NULL`
- [x] `SettingsScreen` 新增「字型管理」入口可正確導航
- [x] `reader_settings_sheet.dart` 字型選擇器可選取內建與自訂字型，選取結果正確持久化
- [x] 上述測試皆通過，`flutter analyze` 乾淨

---

## Issue 3：自訂字型 Foliate-JS 原生渲染

**依賴／Blocked by：** Issue 2（需要能選字型才能測試渲染路徑）

**Status:** ready-for-agent

**What to build：**

`foliate_native_bridge.dart` 的 `buildFontFaceCss()` 擴充為同時輸出內建與自訂字型的 `@font-face` 規則，自訂字型指向新虛擬路徑前綴（例如 `/assets/custom-fonts/<familyName>`）。`foliate_epub_reader_view.dart` 的 `_shouldInterceptRequest` 新增對應路徑分支，呼叫新增的 Dart 橋接函式取得位元組。`ReaderResourceChannel.kt` 新增 `readCustomFontBytes(uri)` method，以 `ContentResolver.openInputStream(uri).use { it.readBytes() }` 一次性讀取後直接回傳，**不落地快取**（與既有 `readAndroidAsset` 同構，非 `cacheBookForServing` 的落地快取模式，見 [ADR 0021](../../adr/0021-custom-font-content-uri-no-copy.md)）。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - `buildFontFaceCss()` 輸出內容含自訂字型的 `@font-face` 規則、虛擬路徑格式正確。
  - `_shouldInterceptRequest` 對自訂字型路徑的分支呼叫正確的橋接函式。
- integration_test（真機）：
  - 自訂字型端到端流程：上傳測試字型 fixture → 開啟測試 EPUB → 於 `reader_settings_sheet.dart` 套用該字型 → 確認 `readCustomFontBytes` 呼叫成功、頁面無 `Key('reader_error_text')`。實際視覺是否正確換成該字體列為人工真機驗收項目，比照專案既有「自動化驗證機制運作、視覺效果人工確認」慣例（例如 `epic-4` PDF 濾鏡效果）。

**驗收標準：**

- [ ] `buildFontFaceCss()` 正確輸出自訂字型 `@font-face` 規則
- [ ] `_shouldInterceptRequest` 正確攔截自訂字型虛擬路徑請求
- [ ] `ReaderResourceChannel.readCustomFontBytes` 正確透過 `ContentResolver` 讀取位元組回傳，不寫入任何快取檔案
- [ ] 真機端到端流程：上傳字型 → 套用 → 開書無錯誤，`readCustomFontBytes` 呼叫成功
- [ ] 人工真機視覺驗收：套用的自訂字型確實顯示於閱讀畫面（記錄於本 Issue 完成時的驗收說明）
- [ ] 上述自動化測試皆通過，`flutter analyze` 乾淨

---

## Issue 4：閱讀預設值畫面

**依賴／Blocked by：** None - can start immediately（與字型模組完全獨立）

**Status:** ready-for-agent

**What to build：**

`GlobalReaderPrefs` 新增 `volumeKeyEnabled`（`bool`，預設 `true`）與 `fullscreen`（`bool`，預設 `false`）兩欄位，SharedPreferences key 沿用既有 `global_reader_<欄位名>` 命名慣例（`global_reader_volume_key_enabled`／`global_reader_fullscreen`）。`reader_prefs_manager_impl.dart` 的 `resolve()` 新增 `fullscreen: book.fullscreen ?? global.fullscreen`（比照 `pageTurnMode`/`screenOrientation` 既有雙層解析寫法）與 `volumeKeyEnabled: global.volumeKeyEnabled`（無單書覆寫層）。

新建 `ReadingDefaultsScreen`：四個獨立控制項（音量鍵翻頁開關、螢幕方向 5 選一、翻頁模式 2 選一、全螢幕顯示開關），皆為**即時生效、不設「儲存」按鈕**——每項控制項變更當下立即呼叫 `saveGlobalPrefs()`（比照 `NavZoneSettingsScreen` 既有互動模式）。`SettingsScreen` 新增「閱讀預設值」入口。

`ReaderScreen._handleVolumeKeyCall`（`reader_screen.dart:1886`）新增早期檢查 `if (_resolved?.volumeKeyEnabled == false) return;`，全域音量鍵翻頁關閉時忽略原生端 `onVolumeKey` 觸發，不執行翻頁動作。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - `ReadingDefaultsScreen`：四項控制項初始值正確讀取既有 `GlobalReaderPrefs`、切換任一項立即呼叫 `saveGlobalPrefs()` 並反映新值、無「儲存」按鈕。
  - `SettingsScreen`：新增「閱讀預設值」入口，點擊導航正確。
  - `reader_prefs_manager_impl_test.dart`（或既有測試檔案）：`resolve()` 的 `fullscreen` 雙層解析三種情境（單書覆寫優先／未覆寫回退全域／兩者皆未設定的預設值 `false`）。
  - `ReaderScreen`：`_resolved.volumeKeyEnabled == false` 時，模擬原生 `onVolumeKey` 呼叫不觸發翻頁（`_handleZoneAction` 未被呼叫）；`== true`（或 `null`）時正常翻頁。

**驗收標準：**

- [ ] `GlobalReaderPrefs` 新增 `volumeKeyEnabled`／`fullscreen` 兩欄位，SharedPreferences key 命名與既有慣例一致
- [ ] `ReadingDefaultsScreen` 四項控制項即時生效，無儲存按鈕
- [ ] `SettingsScreen` 新增「閱讀預設值」入口可正確導航
- [ ] `resolve()` 的 `fullscreen` 雙層解析正確（單書覆寫 > 全域 > 預設 `false`）
- [ ] 全域音量鍵開關關閉時，`ReaderScreen` 忽略音量鍵翻頁觸發
- [ ] 上述測試皆通過，`flutter analyze` 乾淨

---

## Issue 5：導航熱區模板圖示化

**依賴／Blocked by：** None - can start immediately（與字型模組、閱讀預設值皆完全獨立）

**Status:** ready-for-agent

**What to build：**

`NavZoneSettingsScreen` 頂部新增 `SegmentedButton<bool>`（`false`=簡單／`true`=自訂，映射 `navZoneMode != NavZoneMode.custom` / `== NavZoneMode.custom`）。「簡單」狀態下方橫排 3 張圖示卡片（左翻頁／右翻頁／單手），各自繪製縮小版三欄示意圖（左/中/右三色區塊＋←/≡/→圖示，參考 `tmp/images/導航熱區建議.jpg`），點選即呼叫既有 `_selectMode()` 立即全域生效；與目前 `navZoneMode` 一致的卡片呈現選中外框。「自訂」狀態導向現有 9 格編輯器（`nav_zone_settings_screen.dart` 既有實作不動），維持既有「至少 1 格須為選單 `ZoneAction.menu`」儲存前驗證。切換「簡單／自訂」本身不清空／不重新初始化 `navZoneCustomActions`（9 格自訂資料），兩種模式底下的資料各自獨立保留在 `GlobalReaderPrefs`。底層 `NavZoneMode` 4 選一資料模型完全不變。

**單元測試要求：**

- widget test（純 Dart，不需真機）：
  - `SegmentedButton` 初始狀態正確反映目前 `navZoneMode`（4 種模板值皆對應「簡單」、`custom` 對應「自訂」）。
  - 「簡單」3 張圖示卡片點選正確呼叫 `_selectMode()` 並立即全域生效；選中卡片正確顯示外框。
  - 切換至「自訂」正確顯示既有 9 格編輯器；切回「簡單」再切回「自訂」，`navZoneCustomActions` 內容不受影響（未被清空/重置）。
  - 既有防死鎖驗證（至少 1 格須為選單）在改版後行為不變。

**驗收標準：**

- [ ] `SegmentedButton` 正確反映並切換「簡單／自訂」狀態
- [ ] 「簡單」下 3 張圖示卡片正確呈現與選取，立即全域生效
- [ ] 「自訂」下 9 格編輯器行為與改版前完全一致（含防死鎖驗證）
- [ ] 模式切換不影響 `navZoneCustomActions` 既有資料
- [ ] 上述測試皆通過，`flutter analyze` 乾淨
