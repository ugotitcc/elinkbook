# 字典功能 Phase 1：實作計畫

狀態：草案，等待審查。**尚未實作。**

相關文件：`PHASE1_AUDIT.md`（現況）、`DICTIONARY_FORMATS_AND_LICENSES.md`（格式與授權）。

## 1. 已決定的範圍

| 決定 | 內容 |
|---|---|
| 平台 | 只做 Android |
| 入口 | `AnnotationToolbar` 新增「查字典」按鈕，點了開底部面板 |
| 匯入格式 | JSON/CSV、MDX。StarDict 延後 |
| 字典存放 | 獨立的 `dictionary.db`，不動主庫（`version: 28`） |
| 線上查詞 | 預設關閉。預設端點為萌典。第一次使用要同意。只送選取的詞 |
| 自訂網址 | 不做 |
| 方向 | 每本字典標記來源語言與目標語言。依選字內容的字元類型挑字典。使用者可調順序 |
| MDX 顯示 | 在 WebView 顯示，關閉 JavaScript，擋掉所有網路連線 |
| 查詢候選 | 產出有序候選清單（大小寫、Unicode 正規化、英文詞形還原、去變音符號），第一個命中就停 |
| 選字規則 | 按鈕一律顯示。有空白視為片語整串查；CJK 不含標點且最多 8 個字元；超過就提示「選取範圍太長」，不發出任何查詢 |
| MDX 顯示最低要求 | 交叉參照（`entry://`、`bword://`）、同詞條錨點、圖片、獨立 `.css`、深色與 E-Ink 配色 |
| 文件位置 | 調查文件在 `docs/research/dictionary/`；本計畫書暫留 `docs/dictionary/`，核准後轉成 Epic 的 `design.md` 與 `spec.md`。暫不開 Epic、不改 `docs/epics.md` |

決定依據見 `docs/research/dictionary/READEST_ANALYSIS_AND_PROPOSAL.md`。

## 2. 不做的事

- 不內建任何字典資料。
- 不做 StarDict、自訂線上網址、PDF 選字查詢、桌面版。
- 不做 MDX 的 `sound://` 音訊、外開連結範本、外部字典 App 呼叫（列為 Phase 2 候選，見 §11）。
- 不複製 Readest 或任何 AGPL／GPL 專案的程式碼。
- 不改 `main.js`、CFI、閱讀進度、劃線、TTS。
- 不把字典資料放進同步。
- 不送出書名、前後文、閱讀位置。

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
  Stream<ImportProgress> import(ImportRequest request);   // 可取消
}
```

- `LocalDictionaryProvider` 與 `OnlineDictionaryProvider` 實作同一個 `DictionaryProvider`。`DictionaryService` 只認介面。
- `MoedictProvider` 是第一個 `OnlineDictionaryProvider`。日後換端點、加自訂網址都不動上層。

### 3.4 `DictionaryService`（LookupCoordinator）

查詢流程：

```
選字文字
  -> lookup_text_normalizer（去頭尾空白與標點、長度與片語檢查）
       -> 太長：回傳 tooLong，結束（不查本機、不查線上）
  -> 判斷字元類型：拉丁 / CJK / 混合
  -> lookup_candidates 產生有序候選清單
  -> 挑出 enabled 且 sourceLang 相符的字典，依 priority 排序
  -> 逐個本機 provider 查詢：依候選順序嘗試，第一個命中就停
  -> 若 [線上已同意] 且 [線上已開啟] 且 [有網路] 且 [字元類型含 CJK]
        -> 萌典 provider 查詢（逾時 5 秒；只送原選字，不送候選）
  -> 回傳 LookupResult（本機結果在前，線上結果獨立一區）
```

長度與片語規則：

- 有空白：視為片語，整串查一次，不縮短。
- CJK 且不含標點與符號：最多 8 個字元。
- 其他單一詞：不設上限。
- 超過上限：面板顯示「選取範圍太長，請縮短後再查」。不發出任何查詢，含線上。

候選清單規則：

- 順序：原字串、小寫、首字大寫、全大寫；再加上各自的 NFC 與 NFD 形式；再加語言別詞形還原；最後去變音符號後重複一次。
- 去變音符號只是備援：`café` 要先於 `cafe`。
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
- 內容：查詢詞、各字典分區、MDX 詞條用 `InAppWebView` 顯示。
- MDX 的 `InAppWebView`：關閉 JavaScript、擋所有網路與檔案請求。只載入我們傳入的 HTML 字串。
- 沒有動畫。E-Ink 模式用邊框。
- 關閉面板時保留選取狀態，使用者可以接著劃線。
- 面板有簡單的返回堆疊：點交叉參照進入新詞條時推入，可返回上一詞。

MDX 詞條處理（無需 JavaScript）：

| 項目 | 做法 |
|---|---|
| `entry://詞`、`bword://詞` | 在 `shouldOverrideUrlLoading` 攔截。URL 解碼後重新查詢，推入返回堆疊 |
| `#錨點`、`entry://#錨點` | 轉成 WebView 原生的錨點跳轉，不當作詞條名稱查詢 |
| 圖片 | 在 `shouldInterceptRequest` 從 `.mdd` 回傳資源。先試原路徑，找不到再去掉開頭的 `/` |
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
- 線上查詢區塊：開關、萌典說明、同意狀態。
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
  content_id TEXT,              -- 重複匯入偵測：檔案前後各一段位元組的雜湊 + 大小 + 檔名
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

- 啟用 `PRAGMA foreign_keys = ON`。
- 刪除字典：刪來源列（詞條連帶刪除）、刪 MDX 私有複本，放在同一個流程內。
- 不進同步：`sync_table_specs.dart` 不登錄這些表。

## 5. 匯入格式規格

### JSON

```json
{
  "name": "我的字典",
  "entries": [
    { "headword": "apple", "pronunciation": "ˈæp.əl", "pos": "n.", "definition": "蘋果" }
  ]
}
```

### CSV

- UTF-8，第一列為標題。
- 欄位：`headword`、`definition`（必填）、`pronunciation`、`pos`（選填）。

### 通用規則

- 缺必填欄位的列略過，並在匯入結果顯示略過筆數與前幾筆原因。
- 單筆 `definition` 上限建議 64 KB，超過略過並計數。
- 匯入在單一交易內分批寫入（建議每批 2,000 筆），支援取消，取消時回復。

### 重複匯入偵測

- 匯入前算 `content_id`：檔案前後各一段位元組的雜湊 + 檔案大小 + 檔名。用已有的 `crypto` 套件。
- 已有相同 `content_id` 時，提示「這本字典已匯入」，讓使用者選擇略過或取代。
- 只用於本機辨識重複，不用於同步。

### 檔名取得

- 一律使用 `file_picker` 回傳的 `PlatformFile.name`（真實檔名），不從路徑字串解析。
- 原因：Android 的 `content://` 路徑有時沒有副檔名。Readest 曾因此把多檔格式判成「不完整」。
- 對 MDX，用主檔名配對 `.mdx`、`.mdd`、`.css`。

## 6. 風險與緩解

| 風險 | 影響 | 緩解 |
|---|---|---|
| MDX 套件品質不明 | 無法開啟或查詢錯誤 | Issue 1 先做技術驗證；介面隔離，可換套件 |
| 舊 MDX 用 LZO | 匯入失敗 | 匯入時偵測並顯示明確訊息；驗證階段決定是否自寫 |
| 英→繁中免費字典稀少 | 使用者沒有資料可用 | 文件說明；Phase 1 只保證匯入機制 |
| 萌典無服務保證 | 查詢失敗 | 逾時、錯誤分類、不阻塞閱讀 |
| 萌典 ND 授權 | 違規改動詞條 | 原文顯示、固定來源標示、不做簡繁轉換 |
| `cleartext` 允許 | 誤走 `http` | Dart 端只接受 `https`，有單元測試 |
| `win32` 相依鏈 | `pub get` 失敗 | 加套件前先試解析；失敗就退回備案 |
| 面板內的 WebView 在 E-Ink 太慢 | 體驗差 | 真機量測；不通過則 MDX 改顯示純文字（備案） |
| 大 MDX 佔記憶體 | 閃退 | 驗證階段量測；設定檔案大小警告 |
| 匯入凍結 UI | 體驗差 | 背景 Isolate；closure 用頂層函式（見 `CLAUDE.md`） |
| 選字太長 | 查不到、版面爆掉 | 片語與 CJK 8 字元規則（見 §3.4），超過不發任何查詢 |
| 新資料庫遷移 | 資料遺失 | `dictionary.db` 自有版本；刪除不影響書庫 |
| MDX 真實世界相容性 | 版面壞掉、連結失效 | Readest 一路修了許多 MDX 渲染問題（見 `READEST_ANALYSIS_AND_PROPOSAL.md` §2.7），預期會遇到。用 2 至 3 本真實字典驗收 |
| Android 原生選取控點與面板重疊 | 面板被控點蓋住 | 計畫保留選取以便劃線。真機確認；不行就在面板開啟時隱藏控點 |
| 關閉面板後工具列重新出現 | 體驗差 | Readest 曾因此出錯（#5526、#5585）。加入 widget 測試案例 |
| 詞形還原誤判 | 查到錯的詞 | 只在精確比對全數落空後才用；候選只用於本機字典 |
| 授權污染 | 法律風險 | 不複製 Readest 或任何 AGPL／GPL 程式碼。寫規格與寫程式分開 |

遷移風險：主庫 schema 不變，所以沒有主庫遷移風險。

## 7. 測試策略

遵守 CLAUDE.md 的範圍規則：每個 Task 只跑觸及的測試檔。完整 `flutter test` 只在計畫最後一個 Task 與合併前各一次。

### 單元測試（`app/test/dictionary/`）

- `lookup_text_normalizer_test.dart`：標點、片語、CJK 8 字元上限、含標點的 CJK、字元類型判斷。
- `lookup_candidates_test.dart`：候選順序、去重、NFC／NFD、去變音符號只當備援（`café` 先於 `cafe`）、空字串回傳空清單。
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
- `dictionary_lookup_sheet_test.dart`：各狀態（有結果、無結果、未匯入、線上已關閉、失敗）。
- `dictionary_settings_screen_test.dart`：匯入流程、排序、刪除確認。
- `dictionary_online_consent_dialog_test.dart`
- `dictionary_lookup_sheet_test.dart` 另加：選字太長的提示、返回堆疊、關閉面板後選取狀態保留、不重複彈出標註工具列。

### 整合測試（真機，`app/integration_test/`）

- 開 EPUB → 選字 → 點查字典 → 面板出現 → 結果顯示。
- MDX 詞條在 WebView 顯示，且 JavaScript 不執行、網路請求被擋。
- MDX 交叉參照可點、可返回；`#錨點` 可跳轉；`.mdd` 圖片在無 JavaScript 下顯示。
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

## 8. 建議的 Issue 拆分

每張 Issue 可獨立合併，順序有相依。

| # | 內容 | 驗收重點 |
|---|---|---|
| 1 | MDX 解析器技術驗證（spike） | 驗證清單完成，結論寫入 `DICTIONARY_FORMATS_AND_LICENSES.md`，選定套件 |
| 2 | 模型、介面、`dictionary.db`、`DictionaryStore` | 單元測試通過；刪除連動 |
| 3 | JSON/CSV 匯入 + 重複匯入偵測 + 查詢候選鏈與英文詞形還原 + 本機 provider + `DictionaryService`（僅本機） | 匯入 10 萬筆有進度可取消；查詢達標；`ran` 查得到 `run`；重複匯入有提示 |
| 4 | 查詢面板 + `AnnotationToolbar` 按鈕 + 選字規則 + 依賴注入 | 選字到顯示結果可用；FXL 不顯示按鈕；太長有提示 |
| 5 | 字典設定畫面（清單、匯入、排序、刪除、啟用） | 三種方向可設定；刪除需確認 |
| 6a | MDX 匯入 + 詞條 WebView 顯示 + 交叉參照與錨點 + 返回堆疊 | JS 關閉、網路被擋；`entry://` 可點可返回；`#錨點` 可跳轉 |
| 6b | MDX 圖片（`.mdd`）、獨立 `.css`、深色與 E-Ink 配色 | 無 JS 下圖片顯示；深色與 E-Ink 下文字可讀；真機量測 |
| 7 | 線上查詞（萌典）+ 同意對話框 + 隱私更新 | 未同意零請求；來源標示；`https` 強制 |
| 8 | 授權頁、隱私頁、l10n 收尾、整合測試 | 檢查腳本通過；真機測試 |

相依：6a 需 2、4、5；6b 需 6a；7 需 3、4；Issue 1 的選型結果決定 6a 使用的套件。

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
12. 選字含空白時整串查一次；CJK 超過 8 個字元或含標點時，顯示「選取範圍太長」，且不發出任何查詢（含線上）。
13. 查詢依候選順序嘗試，第一個命中就停。`ran` 能查到只存 `run` 的字典。
14. 詞形還原只登錄英文。查中文時不套用英文規則。
15. 線上請求只送使用者選取的原字串，不送候選詞。
16. MDX 的 `entry://`、`bword://` 交叉參照可點，進入新詞條後可返回。
17. MDX 的 `#錨點` 與 `entry://#錨點` 在同一詞條內跳轉，不會被當成詞條名稱查詢。
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

## 10. 待確認項目

已確認（2026-10-19）：

- 選字規則改採 §3.4（片語整串查、CJK 8 字元上限）。取代原本的 50 字元與縮短重試。
- 英文詞形還原納入 Phase 1。取代原本的「只轉小寫」。
- MDX 最低要求納入 Phase 1，Issue 6 拆成 6a、6b。
- 外開連結與外部字典 App 列入 Phase 2 候選。

仍是預設假設，請確認或修改：

1. **PDF**：Phase 1 不接。PDF 的選字走 `PdfSelectionInfo`，後續另立 Issue。（預設：不做）
2. **線上結果出現時機**：本機有結果時，線上也一起查。（預設：一起查，分區顯示）
3. **詞彙表**：`CONTEXT.md` 尚無字典相關詞條。建議實作時補上「字典來源」「查詢請求」等詞。本次依指示未修改。
4. **ADR**：以下兩點符合「難以回復、事後令人意外、有真實取捨」，建議實作時各寫一份 ADR：
   - 字典資料獨立於主庫（`dictionary.db`）。
   - 線上查詢請求型別不含前後文。
5. **顯示方式**：Phase 1 用分區加返回堆疊。頁籤等真機試用後再決定。（預設：分區）
6. **Epic 編號與轉換**：計畫核准後，轉成 `docs/epics/<epic名>/` 的 `design.md` 與 `spec.md`，並更新 `docs/epics.md`。編號與優先順序由你定。

## 11. Phase 2 候選

不在 Phase 1 範圍。依優先順序：

1. **StarDict 匯入**：沿用 Readest 證明可行的策略：不轉入資料庫，掃一次 `.idx` 取偏移量，二分搜尋，LRU 快取。多檔依主檔名分組，不完整的組合明確回報。
2. **MDX `sound://` 音訊**：用現有 `just_audio` 播放。先在真機驗證 MIME 與播放時機。
3. **外開連結範本**：範本含 `%WORD%`，僅允許 `https`。結果頁只顯示「在 {名稱} 開啟」卡片，使用者點擊後才用系統瀏覽器開啟。不嵌入、不解析。
4. **外部字典 App 呼叫**：`ACTION_PROCESS_TEXT`，需 `AndroidManifest.xml` 加 `<queries>` 與過濾廠商瀏覽器。
5. **PDF 選字查詢**。
6. **頁籤式顯示**。

明確不做：把前後文送去 AI 服務。若日後要做，必須是另一個請求型別，有獨立的同意流程，不與 `LookupRequest` 共用。
