# `epic-63-dictionary-lookup` 規格（SPEC）

> 本檔案是此 Epic 核心介面、型別、資料庫與驗收標準的唯一事實來源。背景、已決定範圍、風險、待確認項目見同目錄 `epic.md`；工單見 `issues.md`；調查依據見 `docs/research/dictionary/`。
>
> 章節編號沿用調查階段的計畫書，所以不連續：§1、§2、§6、§10、§11 在 `epic.md`，§8 在 `issues.md`。文中的「§N」交叉參照仍以這個編號為準。

## 3. 架構

### 3.1 目錄

```
app/lib/dictionary/
  models/
    dictionary_source.dart      DictionarySource、DictionaryFormat、DictionaryLang
    dictionary_entry.dart       DictionaryEntry、EntryBodyKind
    lookup_request.dart         LookupRequest
    lookup_result.dart          LookupResult、ProviderOutcome
  providers/
    dictionary_provider.dart    DictionaryProvider（抽象介面）
    local_dictionary_provider.dart
    online_dictionary_provider.dart   OnlineDictionaryProvider（抽象）
    moedict_provider.dart       萌典實作
  importers/
    dictionary_importer.dart    DictionaryImporter（抽象）、ImportProgress
    json_csv_importer.dart
    mdx_importer.dart
  storage/
    dictionary_database.dart    dictionary.db 開啟與版本
    dictionary_store.dart       來源與詞條的讀寫
    mdx_reader.dart             MDX 解析器的薄封裝（介面）
  dictionary_service.dart       LookupCoordinator 與對外門面
  dictionary_settings_repository.dart   shared_preferences
  lookup_candidates.dart          有序候選清單（含語言別詞形還原登錄表）
  lemmatize/
    lemmatizer.dart               Lemmatizer 型別與語言登錄表
    english_lemmatizer.dart
  lookup_text_normalizer.dart     去標點、長度與片語判斷
app/lib/screens/
  dictionary_lookup_sheet.dart
  dictionary_settings_screen.dart
  dictionary_online_consent_dialog.dart
```

### 3.2 模型

```dart
enum DictionaryFormat { jsonCsv, mdx }          // stardict 之後再加

class DictionarySource {
  final String id;
  final String name;
  final DictionaryFormat format;
  final String sourceLang;      // 例：'en'、'zh'
  final String targetLang;      // 例：'zh-Hant'、'en'
  final int priority;           // 數字小者先查
  final bool enabled;
  final String storagePath;     // MDX 原檔路徑；JSON/CSV 為空
  final int entryCount;
  final String licenseNote;     // 使用者匯入時可填，顯示用
  final DateTime importedAt;
}

enum EntryBodyKind { plainText, html }

class DictionaryEntry {
  final String sourceId;
  final String headword;
  final String? pronunciation;
  final String? partOfSpeech;
  final String body;
  final EntryBodyKind bodyKind;
}

/// 查詢請求。刻意只有一個詞，沒有前後文欄位：
/// 從型別上保證不可能把書中內容送出去。
class LookupRequest {
  final String word;
}

class LookupResult {
  final LookupRequest request;
  final List<ProviderOutcome> outcomes;   // 每個 provider 一筆，保持順序
}

class ProviderOutcome {
  final String providerId;
  final String displayName;
  final OutcomeStatus status;             // found、notFound、skipped、failed
  final List<DictionaryEntry> entries;
  final String? attribution;              // 例：萌典的來源標示
  final String? errorCode;                // 供 l10n 轉譯，不放 stack trace
}
```

### 3.3 介面

```dart
abstract class DictionaryProvider {
  String get id;
  Future<ProviderOutcome> lookup(LookupRequest request);
}

abstract class OnlineDictionaryProvider implements DictionaryProvider {}

abstract class DictionaryImporter {
  bool canHandle(String fileName);
  Stream<ImportProgress> import(ImportRequest request, {required CancelToken cancel});
}
```

匯入器的執行緒分工（審查 Important 1）：

- `Isolate.run()` 是一次性的，回傳單一 `Future`，不能中途串流進度，也收不到取消信號。所以**不在背景 Isolate 內寫資料庫**。
- 分工：
  1. **解析**放進 `Isolate.run()`：讀檔、解碼、驗證欄位、計算 `headword_norm`，回傳純資料（`List<Map>` 或簡單記錄）與略過統計。closure 用頂層函式，參數只含可跨 Isolate 傳遞的型別（見 `CLAUDE.md`、`AGENTS.md`）。
  2. **寫入**留在主 Isolate：用 `DictionaryStore` 分批（每批 2,000 筆）寫入，每批之間檢查 `CancelToken`、發出一筆 `ImportProgress`。
- 資料庫 I/O 不會卡 UI：`sqflite_common_ffi` 的 `databaseFactoryFfi` 預設在自己的 Isolate 執行 SQLite（另有 `databaseFactoryFfiNoIsolate`），`main.dart` 已設定為前者。
- 取消：`CancelToken` 被設定後，下一批不再寫入，丟出內部取消例外，使外層交易回復。因為整個匯入在單一交易內，取消後資料庫沒有殘留。
- 解析一次回傳整份資料的記憶體代價：10 萬筆約數十 MB，可接受。超過 50 MB 的檔案在選檔後提示「檔案較大，匯入可能需要較長時間」。更大的檔案改成分段解析，列為後續優化，不在 Phase 1。

- `LocalDictionaryProvider` 與 `OnlineDictionaryProvider` 實作同一個 `DictionaryProvider`。`DictionaryService` 只認介面。
- `MoedictProvider` 是第一個 `OnlineDictionaryProvider`。日後換端點、加自訂網址都不動上層。

### 3.4 `DictionaryService`（LookupCoordinator）

查詢流程：

```
選字文字
  -> lookup_text_normalizer（步驟見下方「選字處理」）
       -> 無效：回傳 invalidSelection 或 tooLong，結束（不查本機、不查線上）
  -> 判斷字元類型：拉丁 / CJK / 混合
  -> lookup_candidates 產生有序候選清單
  -> 挑出 enabled 且 sourceLang 相符的字典，依 priority 排序
  -> 逐個本機 provider 查詢：依候選順序嘗試，第一個命中就停
  -> 若 [線上已同意] 且 [線上已開啟] 且 [有網路] 且 [字元類型含 CJK]
        -> 萌典 provider 查詢（逾時 5 秒；只送原選字，不送候選）
  -> 回傳 LookupResult（本機字典依優先順序在前，線上結果最後；每個 provider 一個分段）
```

選字處理（`lookup_text_normalizer`，審查 Important 4）：

1. **去頭尾**：去掉頭尾的空白、換行與標點符號（Unicode 類別 `\p{P}`、`\p{S}`，含「」『』《》與各種引號）。`「相濡以沫」`、`《紅樓夢》` 因此會變成 `相濡以沫`、`紅樓夢`。
2. **空字串**：回傳 `invalidSelection`。
3. **內部標點**（去頭尾後，字串中間仍有標點或控制字元）：
   - 拉丁字母單詞允許內部的連字號與撇號（`state-of-the-art`、`don't`）。
   - 含空白的片語允許內部標點，整串查一次。
   - 其他（例如 `天地，玄黃`）：回傳 `invalidSelection`，面板顯示「選取內容含有標點，請重新選取」。
4. **CJK 長度**：長度 1 至 8 個字元。超過回傳 `tooLong`，面板顯示「選取範圍太長，請縮短後再查」。
5. **有空白**：視為片語，整串查一次，不縮短，不設長度上限。
6. **其他單一詞**：不設長度上限。

`invalidSelection` 與 `tooLong` 都不發出任何查詢，含線上。

候選清單規則：

- 順序：原字串、小寫、首字大寫、全大寫；再加語言別詞形還原；最後去變音符號後重複一次。
- 去變音符號只是備援：`café` 要先於 `cafe`。Dart 沒有內建的變音符號處理，用一張對照表處理拉丁字母（Latin-1 Supplement 與 Latin Extended-A），不引入新套件。
- **不做 Unicode NFC／NFD 正規化。** Dart 標準庫沒有 `String.normalize()`，專案也沒有相關套件。EPUB 文字幾乎都是組合形式，Phase 1 不為此加依賴。若真機回報分解形式的詞查不到，再評估 `unorm_dart` 或對照表，並確認其授權。
- 候選比對語意（審查 Important 3）：
  - JSON/CSV 的本機查詢比對 `headword_norm`（公式見 §4）。每個候選先套同一個公式再查詢，**套用後相同的候選去重**。所以大小寫變體對 JSON/CSV 最終只會查一次。
  - MDX 的比對區分大小寫，所以原字串、小寫、首字大寫、全大寫四種都會送進解析器。
  - 因此候選清單保留大小寫變體是為了 MDX，不是多餘。
- 寧可多產生，讓字典驗證。錯的詞幹只是查不到，換下一個。
- 詞形還原用語言登錄表。Phase 1 只登錄英文。未登錄的語言回傳空清單，不套用英文規則到中文。
- 英文規則要讓名詞優先：`analyses` 先試 `analysis`，再試 `analyse`。
- 候選只用在本機字典。線上請求只送使用者選取的原字串。

其他規則：

- 本機結果先顯示。線上結果分開一區，標示來源。
- 任一 provider 失敗不影響其他。
- 線上查詢條件不滿足時，狀態為 `skipped`，面板顯示「線上查詢已關閉」並附設定入口，不顯示錯誤。
- 沒有任何字典時，面板提示「尚未匯入字典」並附匯入入口。

### 3.5 依賴注入（遵守 ADR 0037）

- 新增 `DictionaryService` 欄位到 `ReaderFeatureDependencies`（`required`，non-null）。
- 在 `main.dart` 建構一次，放進 `readerFeatures`。
- 設定畫面從同一個 `ReaderFeatureDependencies` 取得，不另開依賴組。
- 測試：在 `app/test/support/` 的工廠加預設 fake 的 `DictionaryService`。
- 不引入新的 DI 套件。

### 3.6 查詢面板

- 以底部面板顯示，用既有 `EbSheetShell`。
- 內容：查詢詞、字典分段選擇器、目前選中字典的結果。
- **一次只顯示一本字典**（審查 Important 2）：面板上方是分段選擇器（Segmented Control），每個 provider 一個分段，依優先順序排列，線上結果在最後。預設選中第一個有結果的分段。
- 選中的是 MDX 字典時，詞條用 `InAppWebView` 顯示，並**獨佔面板剩餘高度**（`Expanded`）。畫面上同時最多一個 `InAppWebView`，避免巢狀捲動、無法預知高度、以及多個 WebView 同時佔用記憶體。
- 切換分段時，丟棄前一個 WebView 並建立新的，不同時保留多個。
- 分段上標示結果狀態：有結果、無結果、已略過。無結果的分段仍可選，內容顯示「查無此詞」。
- 只有一個 provider 時，不顯示分段選擇器。
- 分段多到放不下時，選擇器可橫向捲動。E-Ink 模式下用邊框標示選中的分段，不用陰影或動畫。
- 非 MDX 字典（JSON/CSV、萌典）的結果用一般 Flutter 元件顯示，在面板內垂直捲動。
- MDX 的 `InAppWebView`：關閉 JavaScript、擋所有網路與檔案請求。只載入我們傳入的 HTML 字串。
- 沒有動畫。E-Ink 模式用邊框。
- 關閉面板後，既有選取範圍維持，原本的 `AnnotationToolbar` 維持顯示，使用者可以接著劃線。不重複建立工具列、不重新觸發選取變更事件。
- 面板有簡單的返回堆疊：點交叉參照進入新詞條時推入，可返回上一詞。

MDX 詞條處理（無需 JavaScript）：

| 項目 | 做法 |
|---|---|
| `entry://詞`、`bword://詞` | 在 `shouldOverrideUrlLoading` 攔截。URL 解碼後重新查詢，推入返回堆疊 |
| `#錨點`、`entry://#錨點` | 載入詞條 HTML 前，在 Dart 端把 `href="entry://#x"` 改寫成 `href="#x"`。用 `loadDataWithBaseURL` 載入，並指定固定的 baseUrl，讓純 `#x` 由 WebView 原生處理，不需要 JavaScript，也不需要 `shouldOverrideUrlLoading` 攔截。不當作詞條名稱查詢 |
| 圖片 | 在 `shouldInterceptRequest` 從 `.mdd` 回傳資源。先對網址做 `Uri.decodeComponent`，再把反斜線換成 `/`，先試原路徑，找不到再去掉開頭的 `/`。依副檔名設 `contentType`（`image/jpeg`、`image/png`、`image/gif`、`image/webp`、`image/svg+xml`）；沒設正確的型別，部分 WebView 會拒絕渲染 |
| 獨立 `.css` | 匯入時依主檔名一併複製到私有目錄，載入詞條時注入 |
| 深色與 E-Ink 配色 | 注入覆寫樣式，蓋掉詞條寫死的文字與背景顏色 |
| 加密 MDX | 匯入時偵測並顯示明確錯誤，不支援 |
| `sound://` 音訊 | Phase 1 不做，連結不可點並維持原樣顯示 |

已知限制：JavaScript 關閉時，依賴 `onclick` 的互動（例如牛津 9 的圖片放大）不會運作，只看得到縮圖。在字典設定的說明註明。

所有攔截到的非 MDX 內部連結（`http`、`https`、`file` 等）一律不載入、不開啟。

### 3.7 設定與匯入畫面

放在「設定 → 閱讀 → 字典」。

- 字典清單：名稱、語言方向、筆數、啟用開關、拖曳排序、刪除（需確認）。
- 匯入：選檔 → 選語言方向（必填）→ 顯示進度 → 可取消。
- 線上查詢區塊：開關、萌典說明、同意狀態。由 Issue 7 在 `dictionary_settings_screen.dart` 補上（Issue 5 先建立畫面骨架）。
- 錯誤訊息採三段式：發生什麼、為什麼、使用者要做什麼。

## 4. 資料庫

`dictionary.db`（與主庫分開，自帶版本號）。

```sql
CREATE TABLE dictionary_sources (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  format TEXT NOT NULL,
  source_lang TEXT NOT NULL,
  target_lang TEXT NOT NULL,
  priority INTEGER NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  storage_path TEXT,
  content_id TEXT,              -- 重複匯入偵測，算法見 §5
  entry_count INTEGER NOT NULL DEFAULT 0,
  license_note TEXT,
  imported_at TEXT NOT NULL
);

CREATE TABLE dictionary_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_id TEXT NOT NULL REFERENCES dictionary_sources(id) ON DELETE CASCADE,
  headword TEXT NOT NULL,
  headword_norm TEXT NOT NULL,
  pronunciation TEXT,
  part_of_speech TEXT,
  body TEXT NOT NULL,
  body_kind TEXT NOT NULL
);
CREATE INDEX idx_entries_lookup ON dictionary_entries(source_id, headword_norm);
```

- `headword_norm` 公式（審查 Important 3）：`headword.trim().toLowerCase()`。不做 Unicode 正規化（見 §3.4）。匯入時計算並寫入；查詢時候選先套同一個公式。
- 同一個 `headword_norm` 可對應多筆（例如 `IT` 與 `it`）。查詢回傳全部，依 `id` 排序。
- 查詢：`SELECT ... FROM dictionary_entries WHERE source_id = ? AND headword_norm = ?`。
- 外鍵：`PRAGMA foreign_keys = ON` 必須放在 `openDatabase(..., onConfigure: ...)`。它是連線層級設定，每次開啟都要設，只放 `onCreate` 會讓後續開啟時 `ON DELETE CASCADE` 失效。主庫也是這個做法（`sqlite_library_repository.dart` 的 `onConfigure`）。
- 刪除字典：刪來源列（詞條連帶刪除）、刪 MDX 私有複本，放在同一個流程內。
- 不進同步：`sync_table_specs.dart` 不登錄這些表。

## 5. 匯入格式規格

### JSON

```json
{
  "name": "我的字典",
  "sourceLang": "en",
  "targetLang": "zh-Hant",
  "licenseNote": "CC BY-SA 4.0",
  "entries": [
    { "headword": "apple", "pronunciation": "ˈæp.əl", "pos": "n.", "definition": "蘋果" }
  ]
}
```

- `sourceLang`、`targetLang`、`licenseNote` 為選填。有填時，匯入畫面的語言方向選擇器預設代入該值，使用者仍可修改。
- 欄位名稱一旦發布就難以更動，所以現在先定下來。

### CSV

- UTF-8，第一列為標題。
- 欄位：`headword`、`definition`（必填）、`pronunciation`、`pos`（選填）。

### 通用規則

- 缺必填欄位的列略過，並在匯入結果顯示略過筆數與前幾筆原因。
- 單筆 `definition` 上限建議 64 KB，超過略過並計數。
- 匯入在單一交易內分批寫入（每批 2,000 筆），支援取消，取消時回復。執行緒分工見 §3.3。

### 重複匯入偵測

- 匯入前算 `content_id`：檔案前 64 KB 與後 64 KB 的 SHA-256 + 檔案大小 + 檔名。檔案小於 128 KB 時，雜湊整個檔案。用已有的 `crypto` 套件。
- 已有相同 `content_id` 時，提示「這本字典已匯入」，讓使用者選擇略過或取代。
- 只用於本機辨識重複，不用於同步。

### 檔名取得

- 一律使用 `file_picker` 回傳的 `PlatformFile.name`（真實檔名），不從路徑字串解析。
- 原因：Android 的 `content://` 路徑有時沒有副檔名。Readest 曾因此把多檔格式判成「不完整」。
- 對 MDX，用主檔名配對 `.mdx`、`.mdd`、`.css`。

## 7. 測試策略

遵守 CLAUDE.md 的範圍規則：每個 Task 只跑觸及的測試檔。完整 `flutter test` 只在計畫最後一個 Task 與合併前各一次。

### 單元測試（`app/test/dictionary/`）

- `lookup_text_normalizer_test.dart`：
  - 去頭尾標點：`「相濡以沫」` 變成 `相濡以沫`、`《紅樓夢》` 變成 `紅樓夢`。
  - 內部標點：`天地，玄黃` 回傳 `invalidSelection`；`state-of-the-art`、`don't` 通過；含空白的片語通過。
  - CJK 8 字元上限：8 字通過，9 字回傳 `tooLong`。
  - 空字串、純標點回傳 `invalidSelection`。
  - 字元類型判斷。
- `lookup_candidates_test.dart`：候選順序、去變音符號只當備援（`café` 先於 `cafe`）、空字串回傳空清單；套用 `headword_norm` 公式後相同的候選去重。
- `english_lemmatizer_test.dart`：不規則（`ran`→`run`、`mice`→`mouse`、`children`→`child`）、規則（複數、過去式、`-ing`、比較級）、`analyses` 先出 `analysis`；非英文單詞（中文、帶重音）回傳空清單。
- `lemmatizer_registry_test.dart`：未登錄語言回傳空清單，不套用英文規則。
- `content_id_test.dart`：相同檔案同 ID、不同檔案不同 ID、重複匯入提示。
- `json_csv_importer_test.dart`：正常檔、缺欄、壞編碼、超大詞條、取消。
- `dictionary_store_test.dart`：寫入、查詢、刪除連動、優先順序。
- `local_dictionary_provider_test.dart`
- `moedict_provider_test.dart`：用 `MockClient` 驗證：
  - 請求網址只含詞。
  - 拒絕 `http`。
  - 逾時、404、壞 JSON、缺欄位。
- `dictionary_service_test.dart`：
  - 同意關閉時**不發出任何網路請求**（斷言 `MockClient` 呼叫次數為 0）。
  - 本機失敗不影響線上，反之亦然。
  - 方向挑選規則。
- `lookup_request_test.dart`：型別只有 `word`（防止有人日後加前後文欄位）。

### Widget 測試

- `annotation_toolbar_test.dart`：新按鈕出現、點擊觸發 callback。
- `dictionary_lookup_sheet_test.dart`：各狀態（有結果、無結果、未匯入、線上已關閉、失敗、選取含標點、選取太長）；分段選擇器：預設選第一個有結果的分段、切換分段、只有一個 provider 時不顯示選擇器、同一時間最多一個 `InAppWebView`。
- `dictionary_settings_screen_test.dart`：匯入流程、排序、刪除確認。
- `dictionary_online_consent_dialog_test.dart`
- `dictionary_lookup_sheet_test.dart` 另加：返回堆疊。
- `reader_screen_test.dart` 另加：關閉字典面板後，既有選取範圍與原本的 `AnnotationToolbar` 維持，不出現第二個工具列實例。

### 整合測試（真機，`app/integration_test/`）

- 開 EPUB → 選字 → 點查字典 → 面板出現 → 結果顯示。
- MDX 詞條在 WebView 顯示，且 JavaScript 不執行、網路請求被擋。
- MDX 交叉參照可點、可返回；`#錨點` 與 `entry://#錨點`（改寫後）可跳轉；`.mdd` 圖片在無 JavaScript 下顯示，含路徑帶反斜線與空白的圖片。
- 深色與 E-Ink 模式下，MDX 詞條文字可讀。
- Android 原生選取控點不蓋住面板內容。
- E-Ink 裝置上量測面板開啟時間與記憶體。

### 固定測試檔

- 在 `app/test/fixtures/` 放**自製**的小型 JSON、CSV、MDX。不放有版權的字典。
- 小型 MDX 需另找方式產生（待定，如用 `mdict-utils` 產生；該工具授權待查證）。

### 提交前檢查

- `flutter analyze`：`No issues found!`
- `node tool/check_l10n_hardcoded_strings.js`
- 動到 `lib/` Key 或 `integration_test/` 時：`node tool/check_integration_keys.js`

## 9. 驗收標準

功能：

1. 使用者可匯入 JSON、CSV、MDX，並在設定看到清單。
2. 每本字典有來源語言與目標語言。三種方向（英→繁中、中→英、中→中）都能設定並查詢。
3. 在 EPUB、TXT、MD 選字後，工具列出現「查字典」，點擊開面板並顯示結果。
4. 固定版面（FXL）與 CBZ 不出現該按鈕。
5. 無網路時，本機查詢完全可用。
6. 使用者可停用、排序、刪除字典。刪除後相關檔案與資料一併清除。
7. 線上查詞預設關閉。未同意時，**不發出任何網路請求**。
8. 同意後只送選取的詞。請求網址與標頭不含書名、前後文、位置、裝置識別。
9. 萌典結果原文顯示，附固定來源標示。
10. 任何非 `https` 的線上請求被拒絕。
11. MDX 詞條顯示時，JavaScript 不執行，網路請求被擋。
12. 選字去頭尾標點後再判斷：含空白時整串查一次；CJK 超過 8 個字元顯示「選取範圍太長」；CJK 內部含標點顯示「選取內容含有標點」；兩者都不發出任何查詢（含線上）。`「相濡以沫」` 能正常查詢。
13. 查詢依候選順序嘗試，第一個命中就停。`ran` 能查到只存 `run` 的字典。
14. 詞形還原只登錄英文。查中文時不套用英文規則。
15. 線上請求只送使用者選取的原字串，不送候選詞。
16. MDX 的 `entry://`、`bword://` 交叉參照可點，進入新詞條後可返回。
17. MDX 的 `#錨點` 與 `entry://#錨點` 在同一詞條內跳轉，不會被當成詞條名稱查詢；JavaScript 維持關閉。
18. `.mdd` 內的圖片在 JavaScript 關閉時顯示。
19. MDX 詞條在深色與 E-Ink 模式下，文字與背景對比可讀。
20. 重複匯入同一檔案時，提示「這本字典已匯入」並讓使用者選擇略過或取代。
21. 加密 MDX 匯入時顯示三段式錯誤訊息，不當掉。
22. MDX 詞條內任何非內部連結（`http`、`https`、`file`）不載入、不開啟。

非功能（目標值，需實測）：

23. 本機精確查詢 p95 小於 300 ms（含候選鏈）。
24. 匯入 10 萬筆有進度，可取消，UI 不凍結。
25. 開啟 100 MB MDX 的記憶體增量小於 50 MB。
26. E-Ink 模式下面板無動畫。

回歸：

27. 劃線、備註、書籤、閱讀進度、TTS 既有測試全數通過。
28. 主資料庫 `version` 仍為 28。
29. `main.js` 無改動。
30. `flutter analyze` 無問題；兩支檢查腳本通過。
31. 程式碼中沒有取自 Readest 或其他 AGPL／GPL 專案的內容。
32. 查詢面板用分段選擇器，一次只顯示一本字典；同一時間畫面上最多一個 `InAppWebView`，且沒有巢狀捲動。
