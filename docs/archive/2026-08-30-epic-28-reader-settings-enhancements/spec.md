# Epic 28 — 閱讀器設定強化：Architecting

僅 Issue 3（版面設定預設集／書籍設定複製）需要新介面/型別，走完整 Architecting。Issue 1（字距）／Issue 2（Console Log 開關）為既有流程加欄位/開關，無新架構，直接依 `design.md` 的決策內容進入實作，不在本檔案重複。

## 資料模型

### `LayoutPreset`（新型別，`app/lib/reader/layout_preset.dart`）

```dart
class LayoutPreset {
  final int? id;               // null = 尚未存入資料庫（新建立時的暫存物件）
  final String name;           // 使用者自訂名稱，須先 trim()、長度 1~20 字元（見下方「命名驗證」）
  final DateTime createdAt;    // 首次建立時間，覆蓋（replace）時維持不變，僅供「這組存在多久了」的參考資訊
  final DateTime updatedAt;    // 內容最後一次寫入時間（新建時等於 createdAt，覆蓋時更新），用於「選要覆蓋哪一組」時顯示辨識
  final BookReaderPrefs prefs; // 快照內容，見下方「儲存格式」
}
```

`id` 一旦指定後在覆蓋（`replace`）流程中維持不變（同一個 slot 身份），列表顯示順序固定採 `id ASC`（即插入順序），**不隨覆蓋時間重新排序**——`updatedAt` 只在「選擇要覆蓋哪一組」的選單文字說明中顯示，不驅動排序，避免使用者覆蓋某一組後，畫面上 3 個 slot 卡片的位置無預警互換位置造成困惑（採納審查 Recommendation 4）。

**命名驗證**（採納審查 Issue 2.6）：儲存前一律 `name.trim()`；trim 後為空字串時拒絕儲存並提示「名稱不可為空」；長度上限 20 字元（涵蓋中英文，本專案目前無其他命名欄位可比照，20 字元足以容納一般用途描述如「臥室夜讀直排」且不易在卡片 UI 跑版，超過時輸入框直接截斷或拒絕輸入，由實作者擇一）；**允許重複名稱**——不做唯一性檢查、不自動視為覆蓋（3 組數量本來就少，使用者若真的想用同名，不強制阻止；「存滿時選要覆蓋哪一組」的既有流程已經是唯一的覆蓋入口，不需要額外用「同名即覆蓋」這個容易誤觸發的隱性規則）。

`prefs` 直接重用既有 `BookReaderPrefs` 類別，不新建一個窄化的欄位子集型別——理由見下方「儲存格式」。

**欄位污染防護（採納審查 Minor Issue 2.8，修正原設計的假設）**：原設計假設「PDF/雙頁/舊版 `pageMargins` 欄位在流式 EPUB 情境下結構性恆為 `null`，故無需額外驗證」——此假設在「書籍設定複製」（方向 B）情境下不可靠：來源書籍若曾經歷過「人工版面覆蓋」（`CONTEXT.md` 既有詞條，FXL↔流式互相切換）或未來程式碼變更，其 `book_reader_prefs` 列可能殘留非 `null` 的 `dualPage*`／`pdf*` 欄位。改為**明確的允許清單過濾**，而非依賴「假設恆為 null」：新增 `BookReaderPrefs.reflowableEpubFields()` 方法（或等義的頂層函式），只複製 `design.md`「欄位範圍」明列的欄位（`fontFamily`／`fontSize`／`fontWeight`／`lineHeight`／`paragraphSpacing`／`marginTop/Bottom/Left/Right`／`letterSpacing`／`textAlign`／`publisherStyles`／`showHeader`／`showFooter`／`fullscreen`／`columnMode`／`columnSize`／`writingModeOverride`／`pageTurnModeOverride`／`screenOrientationOverride`），其餘一律強制設為 `null`，不論來源物件實際內容為何。「另存為預設集」（方向 A，來源是當下 `ReaderSettingsSheet` 的 draft，本來就不含 PDF/雙頁欄位）與「書籍設定複製」（方向 B）寫入 `LayoutPreset.prefs` 前皆須經過這道過濾，從程式碼結構上杜絕污染，不依賴「這欄位應該一直是 null」的隱性假設。

### 儲存格式：`prefs_json`（TEXT 欄位），非逐欄位對應

```sql
CREATE TABLE layout_preset (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,  -- epoch milliseconds，首次建立時間，replace 時不變
  updated_at INTEGER NOT NULL,  -- epoch milliseconds，最後寫入時間，新建時等於 created_at
  prefs_json TEXT NOT NULL
);
```

`prefs_json` 為 `jsonEncode(prefs.toMap('') ..remove('book_id'))` 的序列化結果（`BookReaderPrefs.toMap()` 現有簽章需要 `bookId` 參數純粹是因為要組進 `book_reader_prefs` 表的主鍵，`layout_preset` 表不需要這個欄位，序列化前先移除即可；`fromMap()` 讀回時代入任意 `book_id` 佔位字串或改用一個不含 `book_id` 的 map 皆可，不影響其餘欄位解析）。

**選擇 JSON blob 而非逐欄位對應（比照 `book_reader_prefs` schema 開一整排同名欄位）的理由**：`BookReaderPrefs` 未來每新增一個欄位（例如本 Epic 的 `letterSpacing`，或日後任何新排版選項），逐欄位設計都需要同步維護**兩張表**的 migration（`book_reader_prefs` 與 `layout_preset`），容易遺漏其中一邊；JSON blob 設計下，`layout_preset` 表結構本身完全不受 `BookReaderPrefs` 欄位增減影響，只需要 `BookReaderPrefs.toMap()`/`fromMap()` 這一份序列化邏輯保持正確即可（此類「序列化為 JSON TEXT 欄位」在本專案已有前例：`book_reader_prefs.pdf_crop_rect` 欄位本身就是 `PdfCropRect.toJson()`/`fromJson()` 的 JSON 字串）。代價是無法對個別欄位下 SQL `WHERE` 查詢，但 `layout_preset` 的存取模式（列出全部 3 組、依 id 存取單一組）完全不需要這種查詢能力，此代價可接受。

**反序列化容錯要求（採納審查 Critical Issue 2.1／2.2）**：`BookReaderPrefs.fromMap()` 目前對 enum 欄位一律用 `EnumType.values.byName(...)`，找不到對應名稱時會直接拋出 `ArgumentError`；此函式現有的 SQLite 讀取路徑（`book_reader_prefs` 表）與本 Epic 新增的 JSON 反序列化路徑（`layout_preset.prefs_json` → `jsonDecode()`）**共用同一份程式碼**，任一路徑讀到「目前 App 版本不認識的 enum 名稱」（例如使用者曾用較新版本建立過 preset，之後裝置降級/回退到較舊版本）都會導致開書或開啟版面設定畫面時整個 App 崩潰。本 Epic 實作 Issue 3 時，須將 `fromMap()` 內所有 enum 欄位的還原邏輯改為透過一個安全輔助函式（例如 `enumByNameOrNull<T extends Enum>(List<T> values, String? name)`，找不到時回傳 `null` 而非拋例外——`null` 在 `BookReaderPrefs` 語意上正是「未覆寫/採用預設」，是最安全的降級行為），此函式可放在 `book_reader_prefs.dart` 內或抽成 `app/lib/util/` 下的共用小工具（供未來其他 JSON 序列化場景重用，採納審查 Recommendation 1，但不強制立新檔案，由實作者依現有 `util/` 目錄慣例決定）。**此修改連帶讓既有 `book_reader_prefs` 表讀取路徑一併變得更健壯，是可接受的正面副作用，不視為擴大範圍**——因為正是本 Epic 決定重用 `fromMap()` 服務 JSON 這個新用途，才讓這個既有的潛在風險變得需要處理。

`letterSpacing`（Issue 1 新增）與任何其他 `double` 欄位的反序列化，必須沿用既有慣例 `(map['field'] as num?)?.toDouble()`（`fromMap()` 現有其餘 double 欄位皆如此），**不可**寫成 `map['field'] as double?`——`jsonDecode()` 對整數值（例如字距剛好存入 `0`）會解析成 Dart `int` 而非 `double`，直接 `as double?` 轉型会拋出 `TypeError`。此要求原本就是既有程式碼的既有慣例，此處明確記錄僅為避免實作 Issue 1 時的疏忽（採納審查 Critical Issue 2.2）。

### `LayoutPresetRepository`（新檔案，`app/lib/reader/layout_preset_repository.dart`）

比照 `BookReaderPrefsRepository` 的既有模式，與其共用同一個 `Database` 連線（`main.dart` 建構時比照 `final layoutPresetRepository = LayoutPresetRepository(repository.database);`）：

```dart
class LayoutPresetRepository {
  const LayoutPresetRepository(this._db);
  final Database _db;

  Future<List<LayoutPreset>> listAll();               // 依 id ASC（插入順序）排序，見上方「id 一旦指定後...」
  Future<void> insert(LayoutPreset preset);            // preset.id == null，createdAt/updatedAt 皆設為當下時間
  Future<void> replace(int id, LayoutPreset preset);   // 覆蓋既有一組（存滿 3 組時）：id/created_at 不變，updated_at 更新為當下時間
  Future<void> delete(int id);
}
```

不需要 `update(name)`（重新命名）／`upsert` 等額外方法——`design.md` 決策的「儲存流程」只有「新建（存滿前）」與「選一組整份覆蓋（存滿後）」兩種操作，「重新命名」若未來有需求可視為「用相同內容 `replace`、只改 `name`」，不需要獨立方法。

### SQLite Migration

`sqlite_library_repository.dart` 目前 `version: 18`（見 `_onUpgrade`）。Issue 3 依賴 Issue 1 的 `letterSpacing` 欄位（見 `design.md`「依賴關係」），版本號規劃依實際合併方式而定（修正原設計「一律各自遞增一個版本號」的說法，採納審查 Important Issue 2.5）：

- **若 Issue 1／Issue 3 在同一個 PR／同一次提交合併**：合併為**同一個** `if (oldVersion < N)` 區塊，同時執行 `ALTER TABLE book_reader_prefs ADD COLUMN letter_spacing REAL` 與建立 `layout_preset` 表，`version:` 只需 +1，不拆成兩個版本號——兩者本來就是同一次資料庫結構變更，拆成兩個版本號只會增加 migration 邏輯複雜度、沒有實質好處。
- **若 Issue 1 先獨立合併回 `main`、Issue 3 之後另開分支**（比照 `epic-24-pdf-engine-rebuild` 逐張個別合併的既有慣例）：Issue 1 的 migration 使用當時 `version:` 現值 +1；Issue 3 開分支時基於已合併 Issue 1 之後的 `main`，其 migration 使用**屆時**的 `version:` 現值 +1（可能因為 `epic-26`／`epic-27` 等並行 Epic 同期也合併了 migration 而不是簡單的「原值+2」，實作者合併前務必重新確認當下 `main` 的實際 `version:` 數值，不可憑空預先假設數字）。

`layout_preset` 是全新獨立表，比照既有 `bookmarks`／`custom_fonts` 表的建表慣例（`_createXxxTable` 獨立函式，無條件建立，不放在 `book_reader_prefs` 存在與否的 if/else 分支內）。

## UI 元件責任劃分

延續現有模式：`ReaderSettingsSheet` 是純展示 widget，不直接做 Repository I/O（現有 `onChanged` callback 模式）；預設集/書籍複製的實際讀寫交由 `reader_screen.dart`（已持有 `widget.prefsManager`，比照方式注入 `LayoutPresetRepository`／`LibraryRepository`）處理。`ReaderSettingsSheet` 新增以下 callback，皆由呼叫端（`ReaderScreen`）決定如何完成：

- `onSaveAsPreset(BookReaderPrefs currentDraft)` → 呼叫端負責「存量是否已滿 3 組」判斷、命名輸入（含「命名驗證」規則）、覆蓋選擇/確認對話框、以 `reflowableEpubFields()` 過濾後寫入 `LayoutPresetRepository`。
- `onApplyPreset(LayoutPreset preset, {required List<String> targetBookIds})` → 呼叫端負責寫入，`targetBookIds` 為 `[目前 bookId]`（單一）或多選批次結果（見下方批次寫入效能）。
- `onApplyFromBook(String sourceBookId, {required List<String> targetBookIds})` → 呼叫端先 `BookReaderPrefsRepository.load(sourceBookId)` 取得來源 `BookReaderPrefs`，以 `reflowableEpubFields()` 過濾後其餘同上。
- `onRequestBookPicker({required bool multiSelect})` → 回傳 `Future<List<String>?>`（使用者取消回傳 `null`），呼叫端負責彈出選書 UI 並套用「僅列出流式 EPUB」的過濾條件。

**批次寫入效能（採納審查 Important Issue 2.3）**：原設計「逐一呼叫 `BookReaderPrefsRepository.save()`」在使用者對多本書套用時，會產生多次獨立 SQLite 交易，造成 UI 卡頓。`BookReaderPrefsRepository` 新增：

```dart
Future<void> saveMultiple(List<String> bookIds, BookReaderPrefs prefs) async {
  await _db.transaction((txn) async {
    for (final bookId in bookIds) {
      await txn.insert('book_reader_prefs', prefs.toMap(bookId),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}
```

比照 `sqlite_library_repository.dart` 既有的 `Database.transaction((txn) async {...})` 用法（例如分類重新命名／刪除，`:865`/`:888`），單一 `bookId`（套用到目前書籍）可直接呼叫既有 `save()`，多筆才使用 `saveMultiple()`。

**書籍選擇器過濾與效能（採納審查 Important Issue 2.4，修正原設計的記憶體過濾方式）**：原設計以 `LibraryRepository.listBooks()` 撈出全部書籍後在 Dart 記憶體過濾，`LibraryRepository` 改為新增資料庫層級查詢方法：

```dart
Future<List<Book>> listReflowableEpubBooks({String? excludeBookId});
```

底層 SQL 對應 `WHERE filePath LIKE '%.epub' AND (is_fixed_layout IS NULL OR is_fixed_layout != 1)`（`LIKE` 對 ASCII 字母預設不分大小寫，與既有 `detectBookFormat()` 的 `toLowerCase()` 判斷邏輯等價），`excludeBookId` 用於「複製其他書籍」流程排除來源書本身。**分頁載入與關鍵字搜尋列為本 Epic 範圍外（YAGNI）**：本專案圖書庫目標規模約 1000 本（見 PRD FR-04 全文檢索效能指標），資料庫層級過濾後結果集通常遠小於全庫規模，`ListView.builder` 本身已是延遲渲染、不需要額外分頁機制；若未來實際圖書庫規模證實需要搜尋/分頁，屬獨立的圖書庫瀏覽體驗優化，另立 Issue 處理，不在本 Epic 預先加上目前用不到的複雜度。

## 套用到目前書籍後的畫面刷新

比照 `ReaderSettingsSheet` 既有其他控制項改變時的既有機制（`onChanged` 回傳完整 `BookReaderPrefs` 觸發 `_handlePrefsChanged`），套用預設集/書籍複製到「目前書籍」時，呼叫端在完成 `BookReaderPrefsRepository.save()` 後，直接呼叫既有的 `_handlePrefsChanged(appliedPrefs)`，不需要新增另一條刷新路徑。「套用到其他書籍」（目前書籍不在目標內時）則不觸發畫面刷新，僅背景寫入。

**Bottom Sheet 開啟中即時同步（採納審查 Minor Issue 2.7）**：若套用當下 `ReaderSettingsSheet` 仍處於開啟狀態（例如使用者在同一個 Sheet 內先點「套用到目前書籍」），`_handlePrefsChanged` 更新 `_prefs` 後，須確保正在顯示的 `ReaderSettingsSheet` 也拿到新值並反映到其內部草稿狀態（滑桿/開關當前顯示值），而非停留在套用前的舊草稿——`ReaderSettingsSheet` 目前以 `prefs` 建構參數接收初始值後在內部 State 維護草稿，需確認 `didUpdateWidget` 已正確處理外部 `prefs` 變更並同步覆寫內部草稿（比照 `CONTEXT.md`「設定面板草稿具現化原則」既有規範判斷是否需要新增/調整 `didUpdateWidget` 邏輯），避免使用者誤以為套用失敗。

## 測試策略

- `LayoutPresetRepository`：純 Dart 單元測試（假 in-memory `Database`，比照 `BookReaderPrefsRepository` 既有測試模式），涵蓋 `insert`/`replace`/`delete`/`listAll`（斷言依 `id ASC` 排序、`replace` 後 `id`/`created_at` 不變但 `updated_at` 更新）與 JSON 序列化往返（`toMap`→`fromMap` 應恢復原值，含 nullable 欄位）。
- **`fromMap()` 反序列化容錯**（新增，對應 Critical 2.1／2.2）：單元測試餵入「未知 enum 名稱字串」須回傳 `null` 而非拋例外；餵入 `jsonDecode()` 產生的整數（`int`）值到 `letterSpacing`／其餘既有 double 欄位須正確轉為 `double` 而非拋 `TypeError`。
- **`reflowableEpubFields()` 過濾**（新增，對應 Minor 2.8）：單元測試餵入一個含非 `null` `pdfFitMode`/`dualPageMode` 的 `BookReaderPrefs`，斷言過濾後回傳物件這些欄位皆為 `null`，其餘允許清單內欄位保留原值。
- **`BookReaderPrefsRepository.saveMultiple()`**（新增，對應 Important 2.3）：單元測試斷言多筆 `bookId` 皆正確寫入且為單一交易（可用 fake `Database` 記錄呼叫次數，或至少驗證結果正確性）。
- **`LibraryRepository.listReflowableEpubBooks()`**（新增，對應 Important 2.4）：獨立單元測試涵蓋「流式 EPUB／FXL EPUB／PDF／TXT」四種輸入，含 `excludeBookId` 排除邏輯。
- **命名驗證**（新增，對應 Minor 2.6）：單元測試涵蓋空字串/純空白/超長輸入的處理結果。
- `ReaderSettingsSheet` 新增 UI 區塊：widget test 驗證「存滿 3 組時觸發覆蓋選單」「未滿 3 組時直接新增」等互動流程，callback 呼叫參數斷言（比照現有 `reader_settings_sheet_test.dart` 既有測試風格，需先確認該檔案是否存在，若無則新建）；另需驗證套用當下 Sheet 若仍開啟，草稿狀態隨外部 `prefs` 更新同步刷新（對應 Minor 2.7）。
- `reader_screen.dart` 的三個新 callback 實作：widget test 驗證套用到目前書籍後畫面即時反映新值、套用到其他書籍時目前畫面不受影響。

## 開放問題（留給 Scrum Master／實作階段）

- `LayoutPreset`/`LayoutPresetRepository` 的單元測試檔案命名與既有慣例對齊（例如 `layout_preset_repository_test.dart`），由實作者於 `plan-issue-3.md` 定案。
- 書籍選擇器 UI 元件是否有現成可重用的元件（`LibraryScreen` 批次選取模式目前是否已抽成獨立可重用 widget，或需要在本 Issue 內新建一個精簡版），需要實作前查證 `library_screen.dart` 現況，非本 spec 阻塞項。
- `enumByNameOrNull` 輔助函式最終放置位置（`book_reader_prefs.dart` 內 private 函式 vs. `app/lib/util/` 共用工具），由實作者於 `plan-issue-3.md`／`plan-issue-1.md` 依當下 `util/` 目錄現況定案。

## 審查回應（`/superpowers:requesting-code-review`，2026-08-14）

`docs/epics/epic-28-reader-settings-enhancements/reviews/review-2026-08-14.md` 對 `design.md`／`spec.md` 審查，0 通過建議直接採用、2 Critical／3 Important／4 Minor、4 項架構建議。逐項核實後：

- **Critical 2.1（enum `byName` 崩潰風險）／2.2（JSON int/double 轉型崩潰風險）**：技術上成立且與本 Epic 決定重用 `BookReaderPrefs.fromMap()` 服務 JSON 反序列化直接相關，**全數採納**，已新增「反序列化容錯要求」段落。
- **Important 2.3（批次寫入效能）／2.4（書籍選擇器效能）**：**採納**，新增 `saveMultiple()`／`listReflowableEpubBooks()`；2.4 建議的「分頁與搜尋支援」**部分採納**——採納 DB 層級過濾，**不採納**分頁/搜尋 UI 基礎建設，理由見上方「書籍選擇器過濾與效能」段落（YAGNI，本專案圖書庫目標規模與 `ListView.builder` 既有延遲渲染特性下非必要）。
- **Important 2.5（migration 版本衝突）**：**採納**，原「一律各自遞增版本號」的描述確實不夠精確，已改為依合併方式（同 PR vs. 分開合併）分別說明。
- **Minor 2.6（命名驗證）／2.7（Sheet 開啟中同步）／2.8（欄位污染防護）**：**全數採納**。2.8 額外修正了原設計「假設恆為 null 故不需驗證」這個不夠嚴謹的推論，改為明確允許清單過濾。
- **Minor 2.9（Console Log 成長上限與清除按鈕）**：**不採納，前提有誤**——`ReaderConsoleLog`（`app/lib/reader/reader_console_log.dart`）是純記憶體 `ValueNotifier`，App 存活期間才累積、**不落地持久化到資料庫**，且**已有** 500 筆上限（既有實作，非本 Epic 範圍新增）；`ReaderConsoleLogScreen` 的 AppBar 也**已有**「清空」`IconButton`。審查報告描述的「資料庫 Log 膨脹」情境與現況不符，不需要新增設計。予以記錄澄清，避免下一位讀者誤以為這是待補功能。
- **架構建議 1（共用 enum 容錯工具）**：併入 2.1 修正一併處理，最終放置位置列為開放問題。
- **架構建議 2（批次寫入基礎建設）**：併入 2.3 修正。
- **架構建議 3（書籍選擇器可重用元件）**：已列為既有開放問題（`library_screen.dart` 現況待查），非本次修訂新增決策，維持開放。
- **架構建議 4（預設集排序穩定性）**：**採納**，新增 `updatedAt` 欄位、排序改為 `id ASC` 固定順序，已反映於「資料模型」段落。
