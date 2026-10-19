# Epic 63 — 字典查詢：工單清單 (Issues)

9 個 Issue，皆為垂直切片。型別、資料表、驗收編號（驗收 N）指 `spec.md`；範圍與風險見 `epic.md`。

| Issue | 標題 | 依賴 | 狀態 | PR |
|---|---|---|---|---|
| 1 | MDX 解析器技術驗證（spike，需真機與真實字典） | 無 | ready-for-human | |
| 2 | 模型、介面、`dictionary.db` 與 `DictionaryStore` | 無 | ready-for-agent | |
| 3 | JSON/CSV 匯入、重複匯入偵測、查詢候選鏈、本機查詢 | 2 | ready-for-agent | |
| 4 | 查詢面板、`AnnotationToolbar` 按鈕、選字規則、依賴注入 | 3 | ready-for-agent | |
| 5 | 字典設定畫面 | 3 | ready-for-agent | |
| 6a | MDX 匯入、詞條顯示、交叉參照與錨點、返回堆疊 | 1、4、5 | ready-for-agent | |
| 6b | MDX 圖片、獨立 CSS、深色與 E-Ink 配色 | 6a | ready-for-human | |
| 7 | 線上查詞（萌典）、同意對話框、隱私更新 | 3、4 | ready-for-agent | |
| 8 | 授權頁、隱私頁、l10n 收尾、整合測試 | 全部 | ready-for-human | |

```
Issue 1（MDX 驗證 spike）────────────────────────┐
Issue 2（模型＋資料庫）──> Issue 3（匯入＋查詢）─┬─> Issue 4（面板＋按鈕）──┬─> Issue 6a ──> Issue 6b ─┐
                                                 ├─> Issue 5（設定畫面）────┘                          ├─> Issue 8
                                                 └─────────────> Issue 7（線上查詞，需 4）────────────┘
```

Issue 1、2 互相獨立，可平行；Issue 4、5 在 Issue 3 之後可平行；Issue 6a 需等 1、4、5。

**發版限制：** Issue 4 合併後，工具列就會出現「查字典」按鈕。在 Issue 7 與 8 完成前，不建議切出發行版：沒有線上查詞時，沒匯入字典的使用者只會看到「尚未匯入字典」。

---

## Issue 1：MDX 解析器技術驗證（spike）

**Status:** ready-for-human

**依賴：** 無。

**What to build：**
- 比較 `dict_reader` 與 `mdict_flutter`，決定 MDX 使用哪個套件，或判斷兩者都不夠、需要另外評估自寫。
- 用 2 至 3 本真實 MDX 驗證。其中一本要是 LZO 壓縮。字典由人類提供。
- 驗證清單見 `docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md` §4。
- 先試 `flutter pub get`，確認不破壞 `pubspec.yaml` 的 `win32` 相依解析。
- 結論寫回 `DICTIONARY_FORMATS_AND_LICENSES.md` 的「驗證結果」一節。

**測試要求：** 無產品程式碼。spike 的程式放 `.scratch/`，不進版控。

**驗收標準：** 驗證清單 6 項都有數字或結論；選定套件；授權全文與相依套件授權已讀過；實體 E-Ink 裝置上量測開啟時間、記憶體、查詢延遲。

**Blocked by：** 無。

---

## Issue 2：模型、介面、`dictionary.db` 與 `DictionaryStore`

**Status:** ready-for-agent

**依賴：** 無。

**What to build：**
- `app/lib/dictionary/models/`：`DictionarySource`、`DictionaryEntry`、`LookupRequest`（只有 `word`）、`LookupResult`、`ProviderOutcome`。
- `DictionaryProvider`、`OnlineDictionaryProvider`、`DictionaryImporter` 抽象介面。
- `dictionary_database.dart`：開啟 `dictionary.db`，自帶版本號，啟用 `PRAGMA foreign_keys = ON`。
- `DictionaryStore`：來源與詞條的讀寫、依優先順序列出、刪除連動。
- 不動主資料庫（`version: 28`），不登錄 `sync_table_specs.dart`。

**測試要求：**
- `dictionary_store_test.dart`：寫入、查詢、優先順序、啟用旗標、刪除連動（詞條隨來源刪除）。
- `lookup_request_test.dart`：型別只有 `word`，防止日後加前後文欄位。
- 主庫版本斷言：`version` 仍為 28。

**驗收標準：** 驗收 28。`flutter analyze` 乾淨；上述測試通過。

**Blocked by：** 無。

---

## Issue 3：JSON/CSV 匯入、重複匯入偵測、查詢候選鏈、本機查詢

**Status:** ready-for-agent

**依賴：** Issue 2。

**What to build：**
- `JsonCsvImporter`：格式見 `spec.md` §5。單一交易分批寫入，可取消，背景 Isolate（closure 用頂層函式，見 `CLAUDE.md`）。
- 重複匯入偵測（`content_id`）與檔名取得規則（用 `PlatformFile.name`）。
- `lookup_text_normalizer.dart`、`lookup_candidates.dart`、`lemmatize/`（只登錄英文）。
- `LocalDictionaryProvider` 與 `DictionaryService`（僅本機；依字元類型與語言方向挑字典）。

**測試要求：**
- `json_csv_importer_test.dart`：正常檔、缺欄、壞編碼、超大詞條、取消。
- `lookup_text_normalizer_test.dart`、`lookup_candidates_test.dart`、`english_lemmatizer_test.dart`、`lemmatizer_registry_test.dart`、`content_id_test.dart`（案例見 `spec.md` §7）。
- `local_dictionary_provider_test.dart`、`dictionary_service_test.dart`：方向挑選、候選依序嘗試、第一個命中就停。

**驗收標準：** 驗收 1、2、12、13、14、20、23、24。匯入 10 萬筆有進度、可取消、UI 不凍結。

**Blocked by：** Issue 2。

---

## Issue 4：查詢面板、`AnnotationToolbar` 按鈕、選字規則、依賴注入

**Status:** ready-for-agent

**依賴：** Issue 3。

**What to build：**
- `AnnotationToolbar` 新增 `onLookupPressed` 與按鈕；`reader_screen.dart` 兩處（EPUB 約 2928 行、PDF 約 2950 行）傳入 callback。PDF 端 Phase 1 不顯示按鈕。
- `dictionary_lookup_sheet.dart`：各狀態（有結果、無結果、尚未匯入、線上已關閉、失敗、選取太長）。用 `EbSheetShell`，無動畫，E-Ink 用邊框。
- `DictionaryService` 加入 `ReaderFeatureDependencies`（`required`）；`main.dart` 建構一次；`test/support/` 工廠加預設 fake。
- 關閉面板時保留選取，不重複彈出標註工具列。
- l10n 字串進四份 ARB。

**測試要求：**
- `annotation_toolbar_test.dart`：新按鈕出現、點擊觸發 callback。
- `dictionary_lookup_sheet_test.dart`：六種狀態、太長提示、關閉後選取保留。
- `reader_screen_test.dart` 相關案例：FXL 與 CBZ 不顯示按鈕。
- `node tool/check_l10n_hardcoded_strings.js`。

**驗收標準：** 驗收 3、4、5、12、26。選字到顯示結果可用；Android 原生選取控點不蓋住面板（真機確認）。

**Blocked by：** Issue 3。

---

## Issue 5：字典設定畫面

**Status:** ready-for-agent

**依賴：** Issue 3。

**What to build：**
- `dictionary_settings_screen.dart`，入口在 `settings_scaffold.dart` 的「閱讀」分區。
- 字典清單：名稱、語言方向、筆數、啟用開關、拖曳排序、刪除（需確認）。
- 匯入流程：選檔 → 選語言方向（必填）→ 進度 → 可取消。
- 錯誤訊息一律三段式。

**測試要求：**
- `dictionary_settings_screen_test.dart`：匯入流程、排序、啟用、刪除確認、重複匯入提示。
- `node tool/check_l10n_hardcoded_strings.js`。

**驗收標準：** 驗收 1、2、6、20。三種方向都可設定；刪除後檔案與資料一併清除。

**Blocked by：** Issue 3。

---

## Issue 6a：MDX 匯入、詞條顯示、交叉參照與錨點、返回堆疊

**Status:** ready-for-agent

**依賴：** Issue 1（選定套件）、Issue 4、Issue 5。

**What to build：**
- `MdxImporter` 與 `mdx_reader.dart` 薄封裝（隔離所選套件）。MDX 保留原檔，複製到私有目錄。
- 詞條以 `InAppWebView` 顯示：JavaScript 關閉、擋所有網路與檔案請求。
- `shouldOverrideUrlLoading` 處理 `entry://`、`bword://`（URL 解碼後重新查詢並推入返回堆疊）、`#錨點`、`entry://#錨點`。
- 加密 MDX 匯入時顯示三段式錯誤。
- 非內部連結（`http`、`https`、`file`）不載入、不開啟。

**測試要求：**
- 以自製小型 MDX fixture 做單元測試：查詢、前綴、加密偵測、壞檔。
- `dictionary_lookup_sheet_test.dart`：返回堆疊。
- 整合測試（真機）：`entry://` 可點可返回；`#錨點` 跳轉；JavaScript 不執行；網路請求被擋。

**驗收標準：** 驗收 11、16、17、21、22。

**Blocked by：** Issue 1、4、5。

---

## Issue 6b：MDX 圖片、獨立 CSS、深色與 E-Ink 配色

**Status:** ready-for-human

**依賴：** Issue 6a。

**What to build：**
- 圖片：在 `shouldInterceptRequest` 從 `.mdd` 回傳資源。先試原路徑，找不到再去掉開頭的 `/`。
- 獨立 `.css`：匯入時依主檔名一併複製，載入詞條時注入。
- 深色與 E-Ink 配色：注入覆寫樣式，蓋掉詞條寫死的文字與背景顏色。
- 已知限制寫進設定畫面說明：依賴 `onclick` 的互動（例如牛津 9 圖片放大）在 JavaScript 關閉時不運作。

**測試要求：**
- 配色覆寫與資源路徑解析的單元測試。
- 整合測試（真機）：圖片在無 JavaScript 下顯示；深色與 E-Ink 下文字可讀。
- 用 2 至 3 本真實 MDX 驗收（字典由人類提供）。

**驗收標準：** 驗收 18、19、25。真機量測開啟 100 MB MDX 的記憶體增量。

**Blocked by：** Issue 6a。

---

## Issue 7：線上查詞（萌典）、同意對話框、隱私更新

**Status:** ready-for-agent

**依賴：** Issue 3、Issue 4。

**What to build：**
- `MoedictProvider`（`OnlineDictionaryProvider`）：`https://www.moedict.tw/uni/{詞}`，逾時 5 秒，寬鬆解析（缺欄位不當掉，格式不認得時顯示「無法解析」）。
- 只接受 `https`（`AndroidManifest.xml` 有 `usesCleartextTraffic="true"`，必須在 Dart 端擋）。
- `dictionary_online_consent_dialog.dart`；同意狀態存 `dictionary_settings_repository.dart`（`shared_preferences`）。預設關閉。
- 結果原文顯示，固定來源標示（教育部《重編國語辭典修訂本》，CC BY-ND 3.0 TW，經由萌典提供）；不做簡繁轉換。
- 請求只送使用者選取的原字串，不送候選詞。
- 更新 `site/privacy.html`；備註 Google Play 資料安全表單需同步更新（人工）。

**測試要求：**
- `moedict_provider_test.dart`（`MockClient`）：請求網址只含詞、拒絕 `http`、逾時、404、壞 JSON、缺欄位。
- `dictionary_service_test.dart`：未同意時網路呼叫次數為 0；本機與線上互不影響。
- `dictionary_online_consent_dialog_test.dart`。

**驗收標準：** 驗收 7、8、9、10、15。

**Blocked by：** Issue 3、4。

---

## Issue 8：授權頁、隱私頁、l10n 收尾、整合測試

**Status:** ready-for-human

**依賴：** Issue 1～7。

**What to build：**
- 新增所用套件的授權全文到 `app/assets/licenses/`，登錄到 `app/lib/licenses/third_party_licenses.dart`。
- 補 `docs/prd.md` 的字典 FR 條目與 `CONTEXT.md` 詞條。
- 補兩份 ADR（見 `epic.md` §10 第 4 項）。
- 補齊整合測試與真機驗收。

**測試要求：**
- `flutter analyze`、`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`。
- 完整 `flutter test`（計畫最後一個 Task 時執行一次）。
- 真機：EPUB 選字 → 查字典 → 結果顯示；E-Ink 裝置量測。

**驗收標準：** `spec.md` §9 驗收 1～31 全數成立；驗收 31（沒有取自 AGPL／GPL 專案的程式碼）由人類最終確認。

**Blocked by：** Issue 1～7。
