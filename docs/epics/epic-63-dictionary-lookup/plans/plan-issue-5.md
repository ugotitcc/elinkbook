# Issue 5：字典設定畫面 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用者在「設定 → 閱讀 → 字典」匯入、停用、排序、刪除字典，並設定語言方向；MDX 附屬檔案（`.mdd`、`.css`）的配對、複製與缺檔提醒先做好。

**Architecture:** 新增 `DictionaryManager`（字典管理門面：列出、啟用、排序、刪除、匯入、附屬檔案），與 `DictionaryService` 共用同一個延遲開啟的 `DictionaryStore`（新的 `DictionaryStoreProvider`）。`DictionaryManager` 放進 `ReaderFeatureDependencies`（ADR 0037），設定畫面從 `readerFeatures` 取得。畫面是純 Flutter；檔案選擇、匯入流程以可注入的函式讓 widget test 不碰平台。

**Tech Stack:** Flutter、`file_picker`（既有）、`sqflite`（既有）、`gen-l10n`（四份 ARB）。不新增套件，不動 `pubspec.yaml`、主資料庫、`main.js`。

**Spec:** `docs/epics/epic-63-dictionary-lookup/spec.md` §3.5、§3.7、§4（刪除）、§5（重複匯入偵測、檔名取得）、§9（驗收 1、2、6、20、38）；`issues.md` 的 Issue 5；Issue 3、4 延後項見 `plan-issue-3.md`、`plan-issue-4.md` 尾端「交給後續 Issue」。

## Global Constraints

- 不新增套件；不動 `pubspec.yaml`、主資料庫（`version: 28`）、`main.js`、`sync_table_specs.dart`；`dictionary.db` 的版本與表結構不變（`referenced_css` 欄位已存在）。
- 檔名一律用 `PlatformFile.name`，不從路徑解析（spec §5「檔名取得」）。
- 錯誤訊息一律三段式：發生什麼、為什麼、使用者要做什麼。不顯示 stack trace 與內部類別名稱。
- 字串一律走 `AppLocalizations`；新字串同時加進四份 ARB（`app_zh_TW.arb` 為範本，要附 `@key` 說明）。
- 畫面不加 `AnimatedXxx`；E-Ink 用邊框不用陰影。
- 刪除字典：來源列、詞條（外鍵連帶）、私有目錄檔案在同一個流程完成（spec §4）。
- 本 Issue 不解析 MDX（Issue 6a）；`DictionaryFormat.mdx` 的來源只需能顯示、啟用、排序、刪除、補附屬檔案。
- 所有文件與註解用正體中文；commit 訊息不加 `Co-Authored-By`。
- 每個 Task 只跑觸及的測試檔；完整 `flutter test` 只在最後一個 Task 跑一次。

## Review Focus

1. **匯入進行中離開畫面**：返回鍵先跳確認；確認離開就取消匯入，資料庫沒有半成品字典（Task 5）。
2. **刪除後查詢**：刪除一本字典後，`DictionaryService.lookup` 不再回傳它，私有目錄一併清除（Task 2）。
3. **清單裡有無法辨識的 `format`**：清單照常顯示其他字典，不整個失敗（Task 1）。
4. **空檔或沒有有效詞條的檔案**：顯示三段式錯誤，清單不多出一本空字典（Task 5）。
5. **同一批選到 `.mdx` 但沒有任何匯入器能處理**：該檔顯示「這個版本還不能匯入 MDX」，不影響同批其他檔案（Task 5）。

## 已決定事項（spec 沒寫清楚，本計畫的選擇）

- **新增 `DictionaryManager` 欄位，不擴充 `DictionaryService`。** spec §3.5 說設定畫面「從同一個 `ReaderFeatureDependencies` 取得，不另開依賴組」；加一個欄位符合 ADR 0037。查詢與管理分成兩個類別，各自單一職責。
- **共用延遲開啟：** 新增 `DictionaryStoreProvider`，`DictionaryService` 與 `DictionaryManager` 共用同一個實例，避免兩邊各自記憶「開啟中」的狀態。`DictionaryService.lazy` 保留（內部包一個 provider），`DictionaryService.fromProvider` 新增。
- **匯入期間暫停查詢（Issue 2 審查 M-9）不需要額外機制：** 匯入在設定畫面進行，閱讀器不在前景；離開設定畫面會取消匯入（見 Review Focus 1）。
- **語言方向：** 三個固定選項，必選：英→繁中（`en`／`zh-Hant`）、中→英（`zh`／`en`）、中→中（`zh`／`zh-Hant`）。檔案提示的 `sourceLang`／`targetLang` 對得上其中一個就預選，對不上就不預選、不允許送出。CC-CEDICT 預設中→英（spec §5）。
- **匯入對話框欄位：** 名稱（預填 `ImportHints.name`，可改）、方向（必選）、授權說明（預填 `licenseNote`，可改）。多檔匯入逐檔跳出對話框，同一個流程依序處理。
- **大檔提示：** 選檔後單檔超過 50 MB，對話框顯示「檔案較大，匯入可能需要較長時間」（spec §3.3）。
- **MDX 附屬檔案目錄：** `<App 支援目錄>/dictionaries/<sourceId>/`，放 MDX 私有複本、`.mdd`、`.css`（保留原檔名）。刪除字典時整個目錄刪除。
- **MDX 在本 Issue 的行為：** 匯入流程會對選到的 `.mdx`／`.mdd`／`.css` 做配對並顯示結果，但因為沒有 MDX 匯入器（Issue 6a），`.mdx` 顯示「這個版本還不能匯入 MDX」。`DictionaryManager` 以匯入器清單判斷能不能處理；Issue 6a 加入 `MdxImporter` 即生效。「新增附屬檔案」與缺檔提醒對任何 `format == mdx` 的來源都可運作，本 Issue 以直接寫入 store 的 MDX 來源測試。
- **`referenced_css` 的取得：** 本 Issue 提供純函式 `extractReferencedCssNames(Iterable<String> bodies)`（抽樣掃詞條 HTML 的 `<link href>`）與 store 的 `setReferencedCss`；實際抽樣前 200 筆詞條要讀 MDX，由 Issue 6a 呼叫。
- **排序：** `ReorderableListView` 拖曳，放手後把整份順序重寫成 `priority = 0..n-1`（不留空號、不重複）。
- **查詢面板的「前往字典設定」：** 本 Issue 接上（Issue 4 交接）。點了先關面板再開設定畫面，不清選取。

---

## 檔案結構

```text
app/lib/
├── dictionary/
│   ├── dictionary_manager.dart                [新增] 管理門面
│   ├── dictionary_file_store.dart             [新增] 私有目錄與附屬檔案複製、刪除
│   ├── mdx_companion_files.dart               [新增] 配對、抽樣引用的 CSS、缺檔計算（純函式）
│   ├── dictionary_service.dart                [修改] fromProvider
│   ├── models/dictionary_source.dart          [修改] referencedCss
│   └── storage/
│       ├── dictionary_store.dart              [修改] 容錯 listSources、setReferencedCss、reorder
│       └── dictionary_store_provider.dart     [新增] 延遲開啟
├── screens/
│   ├── dictionary_settings_screen.dart        [新增]
│   ├── widgets/dictionary_import_dialog.dart  [新增] 匯入設定對話框（名稱、方向、授權）
│   ├── reader_feature_dependencies.dart       [修改] dictionaryManager
│   ├── settings_scaffold.dart                 [修改] 「閱讀」分區入口
│   └── reader_screen.dart                     [修改] onOpenSettings
├── l10n/app_{zh_TW,zh,zh_CN,en}.arb           [修改]
└── main.dart                                  [修改]

app/test/
├── dictionary/
│   ├── dictionary_store_test.dart             [修改]
│   ├── dictionary_store_provider_test.dart    [新增]
│   ├── dictionary_manager_test.dart           [新增]
│   └── mdx_companion_files_test.dart          [新增]
├── screens/
│   ├── dictionary_settings_screen_test.dart   [新增]
│   ├── widgets/dictionary_import_dialog_test.dart [新增]
│   ├── settings_scaffold_test.dart            [修改]
│   └── reader_screen_test.dart                [修改]
└── support/
    ├── fake_dictionary_manager.dart           [新增]
    └── fake_reader_feature_dependencies.dart  [修改]
```

---

### Task 1：資料層補強

**Files:**
- Create: `app/lib/dictionary/storage/dictionary_store_provider.dart`
- Modify: `app/lib/dictionary/dictionary_service.dart`、`app/lib/dictionary/models/dictionary_source.dart`、`app/lib/dictionary/storage/dictionary_store.dart`
- Test: `app/test/dictionary/dictionary_store_provider_test.dart`、`app/test/dictionary/dictionary_store_test.dart`、`app/test/dictionary/dictionary_service_test.dart`

**Interfaces:**
- Produces:
  - `class DictionaryStoreProvider { DictionaryStoreProvider(Future<DictionaryStore> Function() open); Future<DictionaryStore> call(); }`：第一次呼叫才開啟並記住；開啟失敗不記住，下次呼叫重試。
  - `DictionaryService.fromProvider(DictionaryStoreProvider provider)`；既有 `DictionaryService.lazy(open)` 內部改包一個 provider，行為不變。
  - `DictionarySource.referencedCss`：`List<String>`，建構子選填、預設 `const []`。
  - `DictionaryStore.setReferencedCss(String sourceId, List<String> names)`：以 JSON 陣列存入 `referenced_css`。
  - `DictionaryStore.reorderSources(List<String> orderedIds)`：同一個交易內把 `priority` 重寫成 `0..n-1`；不在清單內的來源不動。
  - `listSources()`：略過 `format` 無法辨識的列（不丟例外）。

- [ ] **Step 1: 寫失敗的測試**

`dictionary_store_provider_test.dart`：
- `test('第一次呼叫才開啟，之後回傳同一個 store')`（計數 `open` 次數為 1）。
- `test('開啟失敗不記住：下次呼叫重試')`。

`dictionary_store_test.dart` 新增：
- `test('setReferencedCss 寫入後 getSource 讀得回 referencedCss')`；未設定時為空清單。
- `test('reorderSources 重寫成 0..n-1，listSources 依新順序')`；傳入的 id 不存在時忽略。
- `test('listSources 略過 format 無法辨識的列，其餘照常回傳')`（直接 `rawInsert` 一列 `format = 'stardict'`）。

`dictionary_service_test.dart` 新增 `test('fromProvider：兩個 service 共用同一個 provider 只開啟一次')`。

- [ ] **Step 2: 執行測試，確認失敗**

Run（在 `app/`）: `flutter test test/dictionary/dictionary_store_provider_test.dart test/dictionary/dictionary_store_test.dart test/dictionary/dictionary_service_test.dart`
Expected: FAIL（找不到類別或方法）。

- [ ] **Step 3: 實作**

把 `DictionaryService._store()` 的記憶與失敗重試邏輯搬進 `DictionaryStoreProvider`；`DictionaryService` 只持有 provider。`_rowToSource` 讀 `referenced_css`（空或 `null` → 空清單）。`listSources` 先轉換、轉不出來的列略過（用 `DictionaryFormat.values.asNameMap()` 查找，查無就略過）。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS（含 Issue 4 的 3 個 `lazy` 測試仍通過）。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary app/test/dictionary
git commit -m "feat(epic-63): Issue 5 共用延遲開啟 provider 與 store 補強"
```

---

### Task 2：`DictionaryManager`、私有目錄與 MDX 附屬檔案純函式

**Files:**
- Create: `app/lib/dictionary/mdx_companion_files.dart`、`app/lib/dictionary/dictionary_file_store.dart`、`app/lib/dictionary/dictionary_manager.dart`
- Test: `app/test/dictionary/mdx_companion_files_test.dart`、`app/test/dictionary/dictionary_manager_test.dart`

**Interfaces:**
- Produces（`mdx_companion_files.dart`，全為純函式）:
  - `class PickedFile { const PickedFile({required String path, required String name, required int size}); }`
  - `class MdxGroup { final PickedFile mdx; final PickedFile? mdd; final List<PickedFile> css; }`
  - `class CompanionPlan { final List<MdxGroup> groups; final List<PickedFile> others; final List<PickedFile> unmatchedCompanions; }`：`others` 是非 MDX 檔（交給一般匯入器）；`unmatchedCompanions` 是沒有任何 `.mdx` 可附加的 `.mdd`／`.css`。
  - `CompanionPlan planCompanions(List<PickedFile> files)`：副檔名不分大小寫；每個 `.mdx` 成為一組；`.mdd` 與 `.mdx` 主檔名相同（不分大小寫）者配對；同一批的所有 `.css` 附加到每一組（引用比對在抽樣後才做，這裡不過濾）。
  - `Set<String> extractReferencedCssNames(Iterable<String> bodies)`：從 HTML 的 `<link ... href="x.css">` 取檔名（只取檔名、不含路徑、轉小寫存放；`@import` 不算）。
  - `List<String> missingCss({required Iterable<String> referenced, required Iterable<String> present})`：不分大小寫比對，回傳缺的檔名（維持 `referenced` 的順序與原寫法）。
- Produces（`dictionary_file_store.dart`）:
  - `class DictionaryFileStore { DictionaryFileStore(Directory root); Directory dirFor(String sourceId); Future<List<String>> listFiles(String sourceId); Future<void> copyInto(String sourceId, PickedFile file); Future<void> deleteAll(String sourceId); }`：`copyInto` 保留原檔名、同名覆蓋；`deleteAll` 目錄不存在時不丟例外。
- Produces（`dictionary_manager.dart`）:
  - `class DictionaryListItem { final DictionarySource source; final List<String> missingCss; }`
  - `class DictionaryManager { DictionaryManager({required DictionaryStoreProvider store, required DictionaryFileStore files, required List<DictionaryImporter Function(DictionaryStore)> importerFactories}); }`
  - `Future<List<DictionaryListItem>> list()`；`Future<void> setEnabled(String id, bool enabled)`；`Future<void> reorder(List<String> orderedIds)`；`Future<void> delete(String id)`（刪來源列、再 `files.deleteAll`；任一步失敗讓例外往上丟，不吞掉）；`Future<void> addCompanions(String sourceId, List<PickedFile> files)`（只接受 `.css`、`.mdd`，其他副檔名忽略）。
  - `Future<bool> canImport(String fileName)`：任一匯入器 `canHandle` 即為真。
  - `Future<ImportHints> readHints(PickedFile file)`；`Stream<ImportProgress> import(PickedFile file, ImportRequest request, {required CancelToken cancel})`：用第一個 `canHandle` 的匯入器。

- [ ] **Step 1: 寫失敗的測試**

`mdx_companion_files_test.dart`：
- `planCompanions`：`a.mdx`＋`a.MDD`＋`x.css` → 一組，`mdd` 配上、`css` 附上；`a.mdx`＋`b.mdd` → `mdd` 為 `null`、`b.mdd` 進 `unmatchedCompanions`；兩個 `.mdx` 與一個共用 `.css` → 兩組都帶該 `css`；`.json` 進 `others`；沒有 `.mdx` 時所有 `.css` 進 `unmatchedCompanions`。
- `extractReferencedCssNames`：`<link rel="stylesheet" href="GHYCHYZ.css">` → `{'ghychyz.css'}`；`href="css/a.css"` 取 `a.css`；`@import url(x.css)` 不算；多筆去重。
- `missingCss`：引用 `[ghychyz.css]`、現有 `[GHYCHYZ.CSS]` → 空；現有為空 → `[ghychyz.css]`。

`dictionary_manager_test.dart`（記憶體 DB＋暫存目錄）：
- `list()` 依優先順序回傳；MDX 來源 `referencedCss` 有而目錄沒有 → `missingCss` 有該檔名；補 `addCompanions`（`.css`）後再 `list()` → `missingCss` 為空（驗收 38）。
- `delete` 後：`list()` 沒有它、`store.lookup` 查不到詞條、私有目錄不存在（驗收 6、Review Focus 2）。
- `delete` 時目錄刪除失敗（注入會丟例外的 `DictionaryFileStore` 子類）→ 例外往上傳，來源列已刪（不留半個字典的 UI 狀態由畫面處理，見 Task 4）。
- `reorder` 後 `DictionaryService.lookup` 的 `outcomes` 順序跟著變。
- `addCompanions` 忽略 `.txt`；同名 `.css` 覆蓋。
- `canImport('a.json')` 為真、`canImport('a.mdx')` 為假（本 Issue 沒有 MDX 匯入器）。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/dictionary/mdx_companion_files_test.dart test/dictionary/dictionary_manager_test.dart`
Expected: FAIL（找不到檔案）。

- [ ] **Step 3: 實作**

三個檔案依 Interfaces。`DictionaryManager.import` 用 `async*` 轉發匯入器的 stream，使呼叫端取消訂閱時能一路傳到匯入器（Issue 3 已保證取消訂閱會回復交易）。`list()` 的 `missingCss` 只對 `format == mdx` 計算：`missingCss(referenced: source.referencedCss, present: await files.listFiles(source.id))`。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/dictionary app/test/dictionary
git commit -m "feat(epic-63): Issue 5 字典管理門面與 MDX 附屬檔案配對"
```

---

### Task 3：依賴注入

**Files:**
- Modify: `app/lib/screens/reader_feature_dependencies.dart`、`app/lib/main.dart`
- Create: `app/test/support/fake_dictionary_manager.dart`
- Modify: `app/test/support/fake_reader_feature_dependencies.dart`
- Test: `app/test/support/fake_reader_feature_dependencies_test.dart`

**Interfaces:**
- Produces: `ReaderFeatureDependencies.dictionaryManager`（`required`，`DictionaryManager`，non-null）。
- `main.dart`：建構一個 `DictionaryStoreProvider`（內容同 Issue 4 的開啟函式），`DictionaryService.fromProvider(provider)` 與 `DictionaryManager(store: provider, files: DictionaryFileStore(<getApplicationSupportDirectory()>/dictionaries), importerFactories: [(s) => JsonCsvImporter(store: s), (s) => CedictImporter(store: s)])` 共用它。
- 測試替身：`class FakeDictionaryManager implements DictionaryManager`，用記憶體 `List<DictionaryListItem>` 回應 `list()`，記錄 `setEnabled`、`reorder`、`delete`、`addCompanions`、`import` 的呼叫；`import` 回傳可由建構子設定的進度 stream。`fakeReaderFeatureDependencies({DictionaryManager? dictionaryManager})` 預設 `FakeDictionaryManager()`。

- [ ] **Step 1: 寫失敗的測試**

`fake_reader_feature_dependencies_test.dart` 新增：`test('預設帶有 DictionaryManager，且每次呼叫是新實例')`、`test('可覆寫 dictionaryManager')`。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/support/fake_reader_feature_dependencies_test.dart`
Expected: FAIL（編譯錯誤）。

- [ ] **Step 3: 實作**

欄位、`main.dart` 接線、替身。`getApplicationSupportDirectory()` 在 `main.dart` 已有 import（字型下載用）。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2；再跑 `flutter analyze` 確認所有 `ReaderFeatureDependencies(` 呼叫處都編譯過。
Expected: PASS、No issues found。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/reader_feature_dependencies.dart app/lib/main.dart app/test/support
git commit -m "feat(epic-63): Issue 5 DictionaryManager 加入 ReaderFeatureDependencies"
```

---

### Task 4：設定畫面——清單、啟用、排序、刪除、缺檔提醒

**Files:**
- Create: `app/lib/screens/dictionary_settings_screen.dart`
- Modify: 四份 ARB
- Test: `app/test/screens/dictionary_settings_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `DictionaryManager`、`DictionaryListItem`、`PickedFile`。
- Produces: `class DictionarySettingsScreen extends StatefulWidget`，建構參數 `{required DictionaryManager manager, required bool isEinkMode, Future<List<PickedFile>?> Function(List<String> extensions)? pickFiles}`（`pickFiles` 預設用 `FilePicker`，Task 5 使用；本 Task 的「新增附屬檔案」也用它）。
- 固定 Key：`dictionary_settings_list`、`dictionary_item_<id>`、`dictionary_enabled_<id>`、`dictionary_delete_<id>`、`dictionary_missing_css_<id>`、`dictionary_add_companion_<id>`（只在 `format == mdx` 顯示）、`dictionary_settings_empty`、`dictionary_settings_import_button`（Task 5 接線）。
- 每列顯示：名稱、方向（例：「英→繁中」）、筆數、啟用開關、拖曳把手；MDX 且 `missingCss` 非空時多一行提醒（「詞條引用了 ghychyz.css，但沒有匯入」，多個檔名以頓號連接）；授權說明有填時顯示。
- l10n：標題「字典」、方向三個標籤（「英→繁中」「中→英」「中→中」）、筆數（ICU plural）、空清單文字（「尚未匯入字典」附一句下一步）、刪除確認（標題、內容含字典名稱與「詞條與附屬檔案會一併刪除，無法復原」、按鈕）、缺檔提醒、「新增附屬檔案」、刪除失敗三段式訊息（`dictionarySettingsDeleteFailed`）。四份 ARB 都要加，zh_TW 附 `@key` 說明。

- [ ] **Step 1: 寫失敗的測試**

`dictionary_settings_screen_test.dart`（用 `FakeDictionaryManager`；比照其他畫面 widget test 的 pump 輔助）：
- `空清單顯示尚未匯入字典`。
- `清單依序顯示名稱、方向標籤、筆數`；三種方向各一本，標籤分別為「英→繁中」「中→英」「中→中」（驗收 2）。
- `切換啟用開關呼叫 setEnabled 並更新畫面`。
- `拖曳排序後呼叫 reorder，傳入新的 id 順序`（用 `tester.drag` 拖把手）。
- `刪除：先出確認對話框；取消不刪；確認後呼叫 delete 並從清單消失`。
- `刪除失敗（delete 丟例外）：顯示三段式錯誤，清單重新載入`。
- `MDX 來源缺 CSS 時顯示提醒；非 MDX 來源不顯示提醒與「新增附屬檔案」`。
- `點新增附屬檔案：選檔後呼叫 addCompanions，提醒消失`（`pickFiles` 注入回傳一個 `ghychyz.css`；`FakeDictionaryManager` 在 `addCompanions` 後更新 `missingCss`）。
- `list() 丟例外時顯示失敗訊息，不是空白畫面`。
- `E-Ink 模式找不到 AnimatedXxx（AnimatedSwitcher、AnimatedContainer）`。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/dictionary_settings_screen_test.dart`
Expected: FAIL（找不到檔案）。

- [ ] **Step 3: 實作**

先加 ARB 並 `flutter gen-l10n`，再寫畫面。`ReorderableListView` 的 `buildDefaultDragHandles: false`，每列自帶 `ReorderableDragStartListener` 與 `Key('dictionary_item_<id>')`。操作後都呼叫 `_reload()` 重新取得清單，不在本地手動改狀態。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/dictionary_settings_screen.dart app/lib/l10n app/test/screens/dictionary_settings_screen_test.dart
git commit -m "feat(epic-63): Issue 5 字典設定畫面清單與管理動作"
```

---

### Task 5：匯入流程

**Files:**
- Create: `app/lib/screens/widgets/dictionary_import_dialog.dart`
- Modify: `app/lib/screens/dictionary_settings_screen.dart`、四份 ARB
- Test: `app/test/screens/widgets/dictionary_import_dialog_test.dart`、`app/test/screens/dictionary_settings_screen_test.dart`（新增 group）

**Interfaces:**
- Produces（`dictionary_import_dialog.dart`）:
  - `enum DictionaryDirection { enToZh, zhToEn, zhToZh }`，附 `String sourceLang`、`String targetLang`（`en`／`zh-Hant`、`zh`／`en`、`zh`／`zh-Hant`）；`static DictionaryDirection? fromLangs(String? source, String? target)`（對不上回傳 `null`）。
  - `typedef ImportChoices = ({String name, DictionaryDirection direction, String licenseNote});`
  - `Future<ImportChoices?> showDictionaryImportDialog(BuildContext, {required ImportHints hints, required DictionaryDirection? initialDirection, required bool isLargeFile, required bool isEinkMode})`：取消回傳 `null`；方向未選時「匯入」按鈕停用。固定 Key：`dictionary_import_name`、`dictionary_import_direction_<enToZh|zhToEn|zhToZh>`、`dictionary_import_license`、`dictionary_import_confirm`、`dictionary_import_large_file_hint`。
- 畫面流程（`dictionary_settings_screen.dart`）:
  1. 按 `dictionary_settings_import_button`：`pickFiles(['json','csv','txt','u8','mdx','mdd','css'])`，可多選。
  2. `planCompanions` 分組。`others` 逐檔：`canImport` 為假 → 該檔顯示三段式「不支援的檔案」；為真 → `readHints`（失敗顯示三段式錯誤並跳過）→ 對話框 → 匯入。`groups`（MDX）：`canImport(mdx.name)` 為假 → 顯示「這個版本還不能匯入 MDX」並略過整組；`unmatchedCompanions` 顯示一則提醒（沒有可附加的 `.mdx`）。
  3. 匯入中顯示進度對話框（已處理／總數、取消鈕）；取消呼叫 `CancelToken.cancel()` 並等 `ImportStage.cancelled`。
  4. `DuplicateDictionaryException` → 對話框「這本字典已匯入」，按鈕「略過」「取代」（驗收 20）；取代以 `replaceExisting: true` 重跑一次。
  5. 完成：顯示摘要「匯入 N 筆」；`skippedCount > 0` 時加「略過 M 筆」與前幾筆原因（`ImportSkip.reason` 轉 l10n）；完成後 `_reload()`。
  6. `DictionaryImportException.code`（`unreadableFile`、`invalidEncoding`、`invalidFormat`、`noValidEntries`）各轉成三段式 l10n 訊息。
  7. 匯入進行中以 `PopScope` 攔返回：先跳「離開會取消匯入」確認，確認才取消並離開（Review Focus 1）。
- l10n：匯入按鈕、對話框欄位標籤、方向三個標籤（沿用 Task 4）、大檔提示、進度文字、取消、「這本字典已匯入」與略過／取代、摘要、四個錯誤碼的三段式訊息、略過原因（`missingHeadword`、`missingDefinition`、`definitionTooLong`、`invalidField`、`malformedLine`）、「不支援的檔案」、「這個版本還不能匯入 MDX」、離開確認。

- [ ] **Step 1: 寫失敗的測試**

`dictionary_import_dialog_test.dart`：
- `fromLangs`：`('en','zh-Hant')`→`enToZh`；`('zh','en')`→`zhToEn`；`('zh','zh-Hant')`→`zhToZh`；`('fr','en')`與 `null`→`null`。
- `initialDirection 為 null 時匯入按鈕停用，選了方向後啟用`。
- `名稱與授權預填 hints，可修改，確認時回傳修改後的值`。
- `isLargeFile 為真時顯示大檔提示`。
- `取消回傳 null`。

`dictionary_settings_screen_test.dart` 新增 `group('匯入流程')`（`pickFiles` 與 `FakeDictionaryManager.import` 都注入）：
- `選一個 JSON：對話框預填 → 確認 → 顯示進度 → 完成摘要 → 清單重新載入`。
- `重複匯入：丟 DuplicateDictionaryException → 顯示「這本字典已匯入」；按略過不再匯入；按取代以 replaceExisting: true 重新匯入`。
- `匯入中按取消：CancelToken 被取消，不出現完成摘要`。
- `多選兩個檔案：依序各跳一次對話框`。
- `空檔（noValidEntries）顯示三段式錯誤，清單沒有多一本`（Review Focus 4）。
- `有略過筆數：摘要列出略過數與原因`。
- `選到 a.mdx＋a.mdd＋x.css：顯示「這個版本還不能匯入 MDX」，同批的 b.json 照常匯入`（Review Focus 5）。
- `只選 .css（沒有 .mdx）：顯示沒有可附加的字典提醒`。
- `匯入進行中按返回：出現離開確認；確認後取消匯入並離開；不確認則留在畫面`（Review Focus 1）。
- `提示的 sourceLang／targetLang 對得上就預選方向（CEDICT 預設中→英）`。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/widgets/dictionary_import_dialog_test.dart test/screens/dictionary_settings_screen_test.dart`
Expected: FAIL。

- [ ] **Step 3: 實作**

先加 ARB 並 `flutter gen-l10n`。流程寫成畫面 State 內的一個 `_runImportFlow()`，逐檔 `await`；每一步後檢查 `mounted`，離開畫面就停止後續檔案。`ImportSkip.reason` 與錯誤碼的轉換各用一個 `switch`，未知碼落到通用三段式訊息，不顯示原始碼。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2。Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens app/lib/l10n app/test/screens
git commit -m "feat(epic-63): Issue 5 字典匯入流程"
```

---

### Task 6：設定入口與查詢面板接線

**Files:**
- Modify: `app/lib/screens/settings_scaffold.dart`、`app/lib/screens/reader_screen.dart`、四份 ARB
- Test: `app/test/screens/settings_scaffold_test.dart`、`app/test/screens/reader_screen_test.dart`

**Interfaces:**
- `settings_scaffold.dart`：「閱讀」分區在「閱讀預設值」之後加 `ListTile`，`Key('settings_dictionary_button')`，標題為 `settingsDictionaryLabel`（zh_TW「字典」），`chevron_right`，點了 `push(DictionarySettingsScreen(manager: widget.readerFeatures.dictionaryManager, isEinkMode: widget.appearance.isEinkMode))`。
- `reader_screen.dart`：`_handleLookupPressed` 傳給 `DictionaryLookupSheet.show` 的 `onOpenSettings` 由 `null` 改為：先 `Navigator.of(context).pop()` 關面板，再 `push(DictionarySettingsScreen(...))`。不呼叫 `_handleSelectionCleared`、`_handleCloseAnnotationToolbar`、`clearSelection`（沿用 Issue 4 約束）。

- [ ] **Step 1: 寫失敗的測試**

`settings_scaffold_test.dart` 新增：`testWidgets('閱讀分區有字典入口，點了開啟字典設定畫面')`。

`reader_screen_test.dart` 的 `group('Epic 63 Issue 4：查字典')` 之外新增 `group('Epic 63 Issue 5：前往字典設定')`：
- `尚未匯入字典時面板顯示前往字典設定；點了面板關閉並開啟字典設定畫面`。
- `從面板進入設定再返回後，AnnotationToolbar 仍只有一個實例，選取仍在`（Element 與 Issue 4 的案例同樣用 `same(...)` 斷言）。

- [ ] **Step 2: 執行測試，確認失敗**

Run: `flutter test test/screens/settings_scaffold_test.dart` 與 `flutter test test/screens/reader_screen_test.dart --plain-name "Epic 63 Issue 5"`
Expected: FAIL。

- [ ] **Step 3: 實作**

入口與 callback 依 Interfaces。

- [ ] **Step 4: 執行測試，確認通過**

Run: 同 Step 2，再跑 Issue 4 的 `--plain-name "Epic 63 Issue 4"` 確認沒有回歸。
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens app/lib/l10n app/test/screens
git commit -m "feat(epic-63): Issue 5 設定入口與查詢面板前往字典設定"
```

---

### Task 7：全套驗證與真機確認

**Files:** 無新增。

- [ ] **Step 1: 靜態檢查**

在 `app/` 執行：
```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
node tool/check_integration_keys.js
```
Expected: 三者皆乾淨。

- [ ] **Step 2: 完整測試（整張計畫唯一一次）**

Run: `flutter test`
Expected: All tests passed。

- [ ] **Step 3: 回歸確認**

- `git diff main -- app/android app/pubspec.yaml app/pubspec.lock app/lib/library app/lib/sync` 無輸出。
- 主資料庫版本仍為 28；`dictionary.db` 版本仍為 1（`DictionaryDatabase.version`）。

- [ ] **Step 4: 真機確認（人工）**

在真機執行（`tmp/dictionary/` 的真實檔案只作本機測試）：
1. 設定 → 閱讀 → 字典，進入畫面，清單為空。
2. 匯入 `cedict_ts.u8`：預選中→英，有進度、可取消；完成後清單出現，顯示授權說明。
3. 再匯入同一個檔案：出現「這本字典已匯入」，略過與取代都可用。
4. 啟用開關、拖曳排序、刪除（有確認）；刪除後回到閱讀器查詢，該字典不再出現。
5. 匯入進行中按返回：出現離開確認。
6. 一次選 `教育部重編國語辭典.mdx` 與一個 `.css`：顯示「這個版本還不能匯入 MDX」，不當掉。
7. 閱讀器選字 → 查字典 → 尚未匯入字典時點「前往字典設定」：面板關閉、設定畫面開啟；返回後選取與工具列仍在。
8. E-Ink 機：畫面無動畫、拖曳排序可操作。

- [ ] **Step 5: 更新文件並 Commit**

把 `issues.md` Issue 5 狀態改成 `in-review`；本計畫 Step 全部勾選。

```bash
git add docs/epics/epic-63-dictionary-lookup
git commit -m "docs(epic-63): Issue 5 實作完成，更新狀態"
```

---

## 交給後續 Issue

- **Issue 6a：** `MdxImporter` 加入 `DictionaryManager` 的 `importerFactories`；匯入時用 `extractReferencedCssNames` 抽樣前 200 筆詞條並呼叫 `setReferencedCss`；把配對好的 `.mdx`／`.mdd`／`.css` 以 `DictionaryFileStore.copyInto` 複製進私有目錄，`storage_path` 指向私有複本；把本 Issue「這個版本還不能匯入 MDX」的分支換成實際匯入。
- **Issue 7：** 在 `dictionary_settings_screen.dart` 補線上查詢區塊（開關、萌典說明、同意狀態）；「線上查詢已關閉」的「前往字典設定」入口已由本 Issue 接上。

---

## 自我檢查

- **Spec 覆蓋：** §3.7 清單（Task 4）、匯入（Task 5）、MDX 配對與缺檔提醒與補匯入（Task 2、4）、線上區塊骨架（Issue 7 補，畫面已存在）；§4 刪除（Task 2、4）；§5 重複匯入提示（Task 5）、檔名取得（Task 5 用 `PickedFile.name`）；驗收 1（Task 5）、2（Task 4、5）、6（Task 2、4）、20（Task 5）、38（Task 2、4）。
- **Issue 3／4 延後項：** `readHints` 預填、`DuplicateDictionaryException`、三段式錯誤、`listSources` 未知 `format`（Task 1）、M-9 匯入期間暫停查詢（已決定事項）、`onOpenSettings` 接線（Task 6）。
- **型別一致：** `PickedFile`、`MdxGroup`、`CompanionPlan` 只在 Task 2 定義，Task 4、5 使用；`DictionaryListItem` 只在 Task 2 定義；`DictionaryDirection`、`ImportChoices` 只在 Task 5 定義；`dictionaryManager` 欄位只在 Task 3 定義，Task 6 使用。
- **比例：** 測試案例佔大宗；程式碼區塊只有簽章與固定值，沒有函式本體。
