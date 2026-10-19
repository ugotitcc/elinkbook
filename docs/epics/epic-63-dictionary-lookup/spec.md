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
