# Epic 28 — 閱讀器設定強化：工單清單 (Issues)

依 `design.md`（Discovery，含 `/grilling`＋`/domain-modeling` 決策紀錄）與 `spec.md`（Architecting，含 2026-08-14 `/superpowers:requesting-code-review` 審查修訂）拆解為 3 個垂直切片。Issue 3 原規劃拆為「書籍設定複製」／「版面設定預設集」兩個工單，人類確認合併回一個（兩者共用同一套「讀來源 → 選書 → 寫目標」機制，分開對此規模而言切得過細）。

---

## Issue 1：流式 EPUB 版面設定新增字距（letter-spacing）選項

**Status:** `ready-for-agent`

**依賴：** 無，可立即開始

**來源：** 使用者需求，`design.md`「Issue 1：字距選項」。

**背景／需求：** `ReaderSettingsSheet`（流式 EPUB 版面設定）目前已有字型大小/字重/行高/段落間距/邊界等排版數值控制項，缺少字距（`letter-spacing`）。

**設計要點（依 `design.md`）：**
- 數值範圍 `-0.05em ~ 1em`，預設 `0`（不覆蓋書本原生字距），step `0.01em`，UI 沿用現有 `_buildSliderRow`（含 +/- 微調按鈕）。
- 橫排／直排（`vertical-rl`）皆套用同一份 CSS 規則，不特別排除。
- 完全比照現有 `lineHeight`/`paragraphSpacing` 欄位模式：
  - `BookReaderPrefs`（`app/lib/reader/book_reader_prefs.dart`）新增 `letterSpacing` 欄位，`toMap`/`fromMap`/`==`/`hashCode`/`copyWith` 五處同步加；`fromMap()` 反序列化須用 `(map['letter_spacing'] as num?)?.toDouble()`，**不可**寫成 `as double?`（`spec.md`「反序列化容錯要求」，避免 JSON 路徑讀到 `int` 值時 `TypeError`）。
  - `ResolvedPreferences`（`app/lib/reader/resolved_preferences.dart`）新增對應欄位。
  - `ReaderPrefsManagerImpl.resolve()` 加一行透傳。
  - `sqlite_library_repository.dart`：`ALTER TABLE book_reader_prefs ADD COLUMN letter_spacing REAL`，`version:` +1（若與 Issue 3 同 PR 合併，兩者的 migration 合併為同一個版本號區塊，見 `spec.md`「SQLite Migration」）。
  - `FoliateEpubReaderView`：`buildFoliatePreferencesMap()`／`foliatePreferencesChanged()` 各加一行。
  - `reader_screen.dart`：建構 `FoliateEpubReaderView` 處多傳一個參數。
  - `main.js`：`buildOverrideCss()` 新增 `letter-spacing` CSS 規則，複用既有廣選擇器。

**單元測試要求：**
- `BookReaderPrefs`：`toMap`/`fromMap` 往返測試涵蓋 `letterSpacing`（含 `null` 與具體數值）；`fromMap()` 餵入 `int` 型別值（模擬 JSON 反序列化情境）須正確轉為 `double`，不拋例外。
- SQLite migration 測試：舊版本升級後 `letter_spacing` 欄位存在且預設為 `null`。
- `ReaderSettingsSheet` widget test：滑桿互動觸發 `onChanged` 帶正確 `letterSpacing` 值，範圍/step 符合設計。
- `buildOverrideCss()`（或其 Dart 端呼叫路徑）測試：`letterSpacing` 非 null 時 CSS 字串含 `letter-spacing` 規則。

**驗收標準：** 使用者可在流式 EPUB 版面設定調整字距、即時生效並持久化；橫排/直排皆正確套用；`flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。

---

## Issue 2：Console Log 攔截可手動關閉

**Status:** `ready-for-agent`

**依賴：** 無，可立即開始

**來源：** 使用者需求，`design.md`「Issue 2：Console Log 開關」。

**背景／需求：** `onConsoleMessage`（`foliate_epub_reader_view.dart:770`）目前無條件攔截 WebView console 訊息寫入 `ReaderConsoleLog`，無任何開關。

**設計要點（依 `design.md`）：**
- `SettingsScreen` 新增一個 `SwitchListTile`（與「閱讀器 Console Log」入口同一頁），比照 `ReaderSettingsSheet` 既有開關樣式。
- 持久化比照 `GlobalReaderPrefs`（`volumeKeyEnabled` 等）既有 SharedPreferences 模式，新增一個布林欄位（例如 `consoleLogEnabled`），預設**關閉**。
- `handleFoliateConsoleMessage()`（`foliate_epub_reader_view.dart:213`）依開關狀態決定是否呼叫 `ReaderConsoleLog.add()`，**但**：`[ERROR]` 等級（`levelName` 對應 WebView 自動鏡射的未捕捉例外）永遠強制記錄，不受開關影響；`[LOG]`/`[WARNING]` 等其餘等級才受開關控制。
- `_globalErrorCaptureJs`（`window.onerror`/`window.onunhandledrejection` → `onError` bridge → `_handleError()`）是完全獨立的另一條管線，本開關不影響它。
- 關閉當下不清空既有紀錄（`ReaderConsoleLog` 既有 500 筆記憶體上限與 `ReaderConsoleLogScreen` 既有清空按鈕已足夠，不需新增，見 `spec.md`「審查回應」對 Minor 2.9 的澄清）。

**單元測試要求：**
- `handleFoliateConsoleMessage()`：開關關閉時，`[LOG]`/`[WARNING]` 等級不寫入 `ReaderConsoleLog`，`[ERROR]` 等級仍寫入；開關開啟時所有等級皆寫入（回歸既有行為）。
- `GlobalReaderPrefs`/`ReaderPrefsManagerImpl`：新欄位讀寫往返測試，預設值為關閉。
- `SettingsScreen` widget test：開關互動正確觸發持久化寫入、畫面狀態正確反映已儲存值。

**驗收標準：** 使用者可在「設定」畫面關閉/開啟 Console Log 攔截；關閉時一般等級訊息不再記錄，`[ERROR]` 等級與崩潰診斷能力不受影響；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 3：版面設定預設集（存 3 組具名預設集）＋書籍設定複製

**Status:** `ready-for-agent`

**依賴：** Issue 1（`letterSpacing` 欄位須先存在，`reflowableEpubFields()` 允許清單需含它）

**來源：** 使用者需求，`design.md`「Issue 3：版面設定預設集＋書籍設定複製」，架構細節見 `spec.md`（含 2026-08-14 審查修訂：enum 容錯反序列化、批次寫入、資料庫層書籍過濾、migration 版本規劃、命名驗證、`updated_at`／排序、欄位污染防護、Bottom Sheet 同步）。

**背景／需求：** 版面設定可儲存最多 3 組具名預設集並跨書套用；另需支援「不經預設集，直接複製指定書籍目前的版面設定」到其他書籍——兩個方向共用同一套「讀來源 `BookReaderPrefs` → 選書 → 寫目標」機制（人類確認合併為單一工單，不拆兩張）。範圍僅流式 EPUB，PDF/FXL 不適用。

**設計要點（依 `spec.md`，逐項見該檔案完整內容，此處列實作檢查清單）：**

1. **資料模型**：新增 `LayoutPreset`（`app/lib/reader/layout_preset.dart`，`id`/`name`/`createdAt`/`updatedAt`/`prefs: BookReaderPrefs`）。新表 `layout_preset`（`id INTEGER PK AUTOINCREMENT`／`name TEXT NOT NULL`／`created_at INTEGER NOT NULL`／`updated_at INTEGER NOT NULL`／`prefs_json TEXT NOT NULL`），`prefs_json` 為過濾後 `BookReaderPrefs` 的 JSON 序列化（**不**逐欄位對應，理由見 `spec.md`「儲存格式」）。
2. **反序列化容錯**：`BookReaderPrefs.fromMap()` 的 enum 欄位還原改用安全輔助函式（`enumByNameOrNull`，找不到對應名稱回傳 `null` 而非拋 `ArgumentError`）——此函式同時服務既有 `book_reader_prefs` SQLite 讀取路徑與新的 JSON 路徑。放置位置（`book_reader_prefs.dart` 內或 `app/lib/util/`）由實作者依當下目錄現況決定。
3. **欄位污染防護**：新增 `BookReaderPrefs.reflowableEpubFields()`（或等義函式），只保留 `design.md`「欄位範圍」列出的欄位，其餘（PDF/雙頁/舊版 `pageMargins`）強制設為 `null`；「另存為預設集」與「書籍設定複製」寫入前皆須經此過濾，不依賴「應該恆為 null」的假設。
4. **`LayoutPresetRepository`**（`app/lib/reader/layout_preset_repository.dart`）：`listAll()`（`id ASC`）／`insert()`／`replace(id, preset)`（`id`/`created_at` 不變，`updated_at` 更新）／`delete(id)`。與 `BookReaderPrefsRepository` 共用同一個 `Database` 連線（`main.dart` 注入）。
5. **命名驗證**：`name.trim()`，空字串拒絕並提示；長度上限 20 字元；允許重複名稱、不做唯一性檢查。
6. **`BookReaderPrefsRepository.saveMultiple(List<String> bookIds, BookReaderPrefs prefs)`**：以單一 `Database.transaction()` 包裹多筆寫入（比照 `sqlite_library_repository.dart` 既有 `.transaction()` 用法），避免批次套用時多次獨立交易造成 UI 卡頓。單一書籍套用繼續用既有 `save()`。
7. **`LibraryRepository.listReflowableEpubBooks({String? excludeBookId})`**：資料庫層級查詢（`WHERE filePath LIKE '%.epub' AND (is_fixed_layout IS NULL OR is_fixed_layout != 1)`），取代原本「撈全部書籍後在記憶體過濾」的設計；不需分頁/搜尋 UI（YAGNI，理由見 `spec.md`）。
8. **`ReaderSettingsSheet` 新增區塊**：預設集管理（3 個 slot 卡片＋「另存為新預設集」按鈕，存滿時跳出覆蓋選單，顯示名稱＋最後更新時間，覆蓋前二次確認）；套用來源二選一「從我的預設集」／「從其他書籍複製」；套用目標二選一「套用到目前書籍」（無需確認）／「套用到其他書籍」（批次選書＋「即將覆蓋 N 本書」確認對話框）。純展示 widget，不直接做 Repository I/O，透過新增的 4 個 callback（`onSaveAsPreset`/`onApplyPreset`/`onApplyFromBook`/`onRequestBookPicker`，簽章見 `spec.md`「UI 元件責任劃分」）與 `reader_screen.dart` 溝通。
9. **Bottom Sheet 開啟中同步**：套用當下若 `ReaderSettingsSheet` 仍開啟，須確認其內部草稿狀態隨外部 `prefs` 更新同步刷新（`didUpdateWidget`，比照 `CONTEXT.md`「設定面板草稿具現化原則」）。
10. **SQLite Migration**：`layout_preset` 建表比照 `bookmarks`/`custom_fonts` 既有慣例（`_createXxxTable`，無條件建立）。若本 Issue 與 Issue 1 同一 PR 合併，兩者的欄位新增與建表合併為同一個版本號區塊；若分開合併，各自取合併當下的 `version:` 現值 +1（實作前務必重新確認，不可預先假設數字）。

**單元測試要求：**
- `LayoutPresetRepository`：`insert`/`replace`/`delete`/`listAll`（含排序、`replace` 後 `id`/`created_at` 不變但 `updated_at` 更新）、JSON 序列化往返。
- `fromMap()` 容錯：未知 enum 名稱回傳 `null`（不拋例外）；`int` 型別 double 欄位正確轉型。
- `reflowableEpubFields()`：含非 null PDF/雙頁欄位的輸入，過濾後這些欄位為 `null`，允許清單欄位保留。
- `saveMultiple()`：多筆 `bookId` 正確寫入、單一交易。
- `listReflowableEpubBooks()`：流式 EPUB／FXL EPUB／PDF／TXT 四種輸入的過濾結果，含 `excludeBookId`。
- 命名驗證：空字串/純空白/超長輸入。
- `ReaderSettingsSheet` widget test：存滿 3 組觸發覆蓋選單、未滿直接新增、套用當下 Sheet 開啟時草稿同步刷新。
- `reader_screen.dart` 新 callback：套用到目前書籍即時反映新值、套用到其他書籍時目前畫面不受影響。

**驗收標準：** 使用者可在流式 EPUB 版面設定另存/管理最多 3 組具名預設集，並可從預設集或直接複製其他書籍的設定，套用到目前書籍或批次套用到其他流式 EPUB 書籍；PDF/FXL 書籍不出現在選書清單；`flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。
