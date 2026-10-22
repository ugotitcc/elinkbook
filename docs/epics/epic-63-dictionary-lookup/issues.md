# Epic 63 — 字典查詢：工單清單 (Issues)

9 個 Issue，皆為垂直切片。型別、資料表、驗收編號（驗收 N）指 `spec.md`；範圍與風險見 `epic.md`。

| Issue | 標題 | 依賴 | 狀態 | PR |
|---|---|---|---|---|
| 1 | MDX 解析器技術驗證（spike，需真機與真實字典） | 無 | done | #343 |
| 2 | 模型、介面、`dictionary.db` 與 `DictionaryStore` | 無 | done | #344 |
| 3 | JSON/CSV 與 CC-CEDICT 匯入、重複匯入偵測、查詢候選鏈、本機查詢 | 2 | done | #345 |
| 4 | 查詢面板、`AnnotationToolbar` 按鈕、選字規則、依賴注入 | 3 | done | #347 |
| 5 | 字典設定畫面 | 3 | done | #349 |
| 6a | MDX 匯入、詞條顯示、交叉參照與錨點、返回堆疊 | 1、4、5 | done | #350 |
| 6b | MDX 圖片、獨立 CSS、深色與 E-Ink 配色 | 6a | ready-for-human | |
| 7 | 線上查詞（萌典）、同意對話框、隱私更新 | 3、4、5 | ready-for-agent | |
| 8 | 授權頁、隱私頁、l10n 收尾、整合測試 | 全部 | ready-for-human | |

```
Issue 1（MDX 驗證 spike）────────────────────────┐
Issue 2（模型＋資料庫）──> Issue 3（匯入＋查詢）─┬─> Issue 4（面板＋按鈕）──┬─> Issue 6a ──> Issue 6b ─┐
                                                 ├─> Issue 5（設定畫面）────┘                          ├─> Issue 8
                                                 └─> Issue 7（線上查詞，需 3、4、5）─────────────────┘
```

Issue 1、2 互相獨立，可平行；Issue 4、5 在 Issue 3 之後可平行；Issue 6a 需等 1、4、5。

**發版限制：** Issue 4 合併後，工具列就會出現「查字典」按鈕。在 Issue 7 與 8 完成前，不建議切出發行版：沒有線上查詞時，沒匯入字典的使用者只會看到「尚未匯入字典」。

---

## Issue 1：MDX 解析器技術驗證（spike）

**Status:** done（2026-10-19：採用 `dict_reader 1.6.1`；平板與 E-Ink 實機皆已量測）

**依賴：** 無。

**What to build：**
- 比較 `dict_reader` 與 `mdict_flutter`，決定 MDX 使用哪個套件，或判斷兩者都不夠、需要另外評估自寫。
- 用真實 MDX 驗證。驗收檔放在 `tmp/dictionary/`（不進版控）：
  - `教育部重編國語辭典(第五版).mdx`：UTF-16、`Encrypted=2`、有 `StyleSheet`、163,085 筆。
  - `簡明古漢語常用字字典（川大版2003）正體.mdx`：UTF-8、`Encrypted=2`、`StripKey=Yes`、標題為佔位字串、引用不存在的外部 CSS。
  - 兩者都只看到 zlib。目前沒有 LZO 字典，Phase 1 不支援 LZO；Issue 1 只需確認所選套件遇到 LZO 區塊時丟出明確錯誤而不是當掉。若手上有 LZO 檔可順便測，但不是必要條件。
- 兩個檔案的第三方授權不明，不得進版控、不得放進 fixtures，文件只記格式資訊。
- 驗證清單見 `docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md` §4。
- 先試 `flutter pub get`，確認不破壞 `pubspec.yaml` 的 `win32` 相依解析。
- 追加驗證：`InAppWebView` 在 `javaScriptEnabled: false`、`loadDataWithBaseURL` 下，`<a href="#x">` 是否能原生跳轉；MDD 資源路徑含反斜線、空白、URL 編碼時，所選套件能否取到。
- 結論寫回 `DICTIONARY_FORMATS_AND_LICENSES.md` 的「驗證結果」一節。

**測試要求：** 無產品程式碼。spike 的程式放 `.scratch/`，不進版控。

**驗收標準：** 驗證清單 6 項都有數字或結論；選定套件；授權全文與相依套件授權已讀過；實體 E-Ink 裝置上量測開啟時間、記憶體、查詢延遲（2026-10-19 已在 Allwinner WAVE E-Ink 平板完成，見 `DICTIONARY_FORMATS_AND_LICENSES.md`「驗證結果」）。

**Blocked by：** 無。

---

## Issue 2：模型、介面、`dictionary.db` 與 `DictionaryStore`

**Status:** done（2026-10-19：已合併，PR #344）

**依賴：** 無。

**What to build：**
- `app/lib/dictionary/models/`：`DictionarySource`、`DictionaryEntry`、`LookupRequest`（只有 `word`）、`LookupResult`、`ProviderOutcome`。
- `DictionaryProvider`、`OnlineDictionaryProvider`、`DictionaryImporter` 抽象介面。
- `dictionary_database.dart`：開啟 `dictionary.db`，自帶版本號，啟用 `PRAGMA foreign_keys = ON`。
- `DictionaryStore`：來源與詞條的讀寫、依優先順序列出、刪除連動。
- `PRAGMA foreign_keys = ON` 放在 `openDatabase` 的 `onConfigure`（連線層級設定；比照主庫的做法）。
- 不動主資料庫（`version: 28`），不登錄 `sync_table_specs.dart`。

**測試要求：**
- `dictionary_store_test.dart`：寫入、查詢、優先順序、啟用旗標、刪除連動（詞條隨來源刪除）。
- `lookup_request_test.dart`：型別只有 `word`，防止日後加前後文欄位。
- 主庫版本斷言：`version` 仍為 28。
- 重新開啟資料庫後，刪除來源仍會連帶刪除詞條（確認 `onConfigure` 每次開啟都生效）。

**驗收標準：** 驗收 28。`flutter analyze` 乾淨；上述測試通過。

**Blocked by：** 無。

---

## Issue 3：JSON/CSV 與 CC-CEDICT 匯入、重複匯入偵測、查詢候選鏈、本機查詢

**Status:** done（2026-10-20：已合併，PR #345）

**依賴：** Issue 2。

**What to build：**
- `JsonCsvImporter`：格式見 `spec.md` §5。解析放進 `Isolate.run()`（closure 用頂層函式，見 `CLAUDE.md`、`AGENTS.md`），寫入留在主 Isolate 分批進行，每批之間檢查 `CancelToken` 並發出 `ImportProgress`，取消時整個交易回復。執行緒分工見 `spec.md` §3.3。
- `CedictImporter`：格式見 `spec.md` §5。繁體與簡體各產生詞頭，拼音以原文存放，釋義存成純文字。
- `pinyin_tone_marks.dart`：聲調數字轉聲調符號的純函式（規則見 `spec.md` §5）。顯示端在 Issue 4 的查詢面板呼叫。
- 重複匯入偵測（`content_id`）與檔名取得規則（用 `PlatformFile.name`）。
- `lookup_text_normalizer.dart`（去頭尾標點、內部標點、CJK 8 字元規則，見 `spec.md` §3.4）、`lookup_candidates.dart`（含 Latin 變音符號對照表，不做 Unicode 正規化）、`lemmatize/`（只登錄英文）。
- 匯入時計算 `headword_norm = headword.trim().toLowerCase()`。
- `LocalDictionaryProvider` 與 `DictionaryService`（僅本機；依字元類型與語言方向挑字典）。

**測試要求：**
- `json_csv_importer_test.dart`：正常檔、缺欄、壞編碼、超大詞條、取消。
- `cedict_importer_test.dart`、`pinyin_tone_marks_test.dart`：案例見 `spec.md` §7。
- `lookup_text_normalizer_test.dart`、`lookup_candidates_test.dart`、`english_lemmatizer_test.dart`、`lemmatizer_registry_test.dart`、`content_id_test.dart`（案例見 `spec.md` §7）。
- `local_dictionary_provider_test.dart`、`dictionary_service_test.dart`：方向挑選、候選依序嘗試、第一個命中就停。

**驗收標準：** 驗收 1、2、12、13、14、20、23、24、33、37（資料層與轉換函式；畫面顯示在 Issue 4）。匯入 10 萬筆有進度、可取消、UI 不凍結。

**Blocked by：** Issue 2。

---

## Issue 4：查詢面板、`AnnotationToolbar` 按鈕、選字規則、依賴注入

**Status:** done（2026-10-20：已合併，PR #347）

**依賴：** Issue 3。

**What to build：**
- `AnnotationToolbar` 新增 `onLookupPressed` 與按鈕；`reader_screen.dart` 兩處（EPUB 約 2928 行、PDF 約 2950 行）傳入 callback。PDF 端 Phase 1 不顯示按鈕。
- `dictionary_lookup_sheet.dart`：各狀態（有結果、無結果、尚未匯入、線上已關閉、失敗、選取含標點、選取太長）。用 `EbSheetShell`，無動畫，E-Ink 用邊框。
- 分段選擇器，一次只顯示一本字典（`spec.md` §3.6）；預設選第一個有結果的分段；只有一個 provider 時不顯示選擇器；同時最多一個 `InAppWebView`，且獨佔剩餘高度。
- `DictionaryService` 加入 `ReaderFeatureDependencies`（`required`）；`main.dart` 建構一次；`test/support/` 工廠加預設 fake。
- 關閉面板後，既有選取範圍與原本的 `AnnotationToolbar` 維持，不重複建立工具列、不重新觸發選取變更事件。
- l10n 字串進四份 ARB。

**測試要求：**
- `annotation_toolbar_test.dart`：新按鈕出現、點擊觸發 callback。
- `dictionary_lookup_sheet_test.dart`：各狀態、太長提示、含標點提示；分段選擇器的預設選取、切換、單一 provider 時隱藏。
- `reader_screen_test.dart` 相關案例：FXL 與 CBZ 不顯示按鈕；關閉字典面板後，既有選取範圍與原本的 `AnnotationToolbar` 維持，不出現第二個實例。
- `node tool/check_l10n_hardcoded_strings.js`。

**驗收標準：** 驗收 3、4、5、12、26、32。選字到顯示結果可用；Android 原生選取控點不蓋住面板（真機確認）。

**Blocked by：** Issue 3。

---

## Issue 5：字典設定畫面

**Status:** done（2026-10-20：已合併，PR #349）

**依賴：** Issue 3。

**What to build：**
- `dictionary_settings_screen.dart`，入口在 `settings_scaffold.dart` 的「閱讀」分區。
- 字典清單：名稱、語言方向、筆數、啟用開關、拖曳排序、刪除（需確認）。
- 匯入流程：選檔（可一次多選）→ 選語言方向（必填）→ 進度 → 可取消。
- MDX 附屬檔案：一次選 `.mdx`、`.mdd`、`.css`；抽樣記錄 `referenced_css`；缺檔提醒；「新增附屬檔案」動作（規則見 `spec.md` §3.7）。MDX 的實際解析在 Issue 6a，本 Issue 先把檔案配對與複製做好。
- 錯誤訊息一律三段式。

**測試要求：**
- `dictionary_settings_screen_test.dart`：匯入流程、排序、啟用、刪除確認、重複匯入提示、多選匯入、缺 CSS 提醒與補匯入後提醒消失。
- `mdx_companion_files_test.dart`：案例見 `spec.md` §7。
- `node tool/check_l10n_hardcoded_strings.js`。

**驗收標準：** 驗收 1、2、6、20、38。三種方向都可設定；刪除後檔案與資料一併清除。

**Blocked by：** Issue 3。

---

## Issue 6a：MDX 匯入、詞條顯示、交叉參照與錨點、返回堆疊

**Status:** done（2026-10-21：已合併，PR #350）

**依賴：** Issue 1（選定套件）、Issue 4、Issue 5。

**What to build：**
- `MdxImporter` 與 `mdx_reader.dart` 薄封裝（隔離所選套件 **`dict_reader 1.6.1`，MIT**；Issue 1 選定）。MDX 保留原檔，複製到私有目錄。
- `dict_reader` 缺的功能由薄封裝補：`KeyCaseSensitive=No` 大小寫摺疊、`StripKey=Yes` 去空白標點、標題佔位字串、統一錯誤型別（它對 LZO 丟的是字串）、MDD 鍵轉換、對所有 `http(s)` 請求回傳明確回應（清單與理由見 `DICTIONARY_FORMATS_AND_LICENSES.md`「驗證結果」）。
- 加入 `app/pubspec.yaml` 前先把相依套件授權（見同文件授權表）放進 `app/assets/licenses/` 並登錄 `third_party_licenses.dart`。
- **第一個任務：在 E-Ink 上補測真實情境的記憶體。** Issue 1 已在 E-Ink 實機（Allwinner WAVE）量過合成檔：`large.mdx` 開啟後增量最高 45.7 MB、p95 最高 3.2 ms，離 50 MB 門檻只剩約 4 MB。仍須補量：真實 CJK 大檔或 UTF-16 合成大檔、隨機鍵查詢、穩態 RSS（含快取）。結果超過門檻時，備案是修補（vendor）`dict_reader` 改成依區塊延遲載入鍵。
- 匯入時掃描所有記錄區塊的壓縮型態與實際長度，擋下 LZO 與截斷檔（`dict_reader` 的 `open()` 不會發現；見研究文件「必須補的功能」第 4a 項）。fixture 要包含「截在記錄區段」的檔案，不只是截在關鍵字區段。
- 詞條以 `InAppWebView` 顯示：JavaScript 關閉、擋所有網路與檔案請求。
- `shouldOverrideUrlLoading` 處理 `entry://詞`、`bword://詞`（URL 解碼後重新查詢並推入返回堆疊）。
- `#錨點`：載入詞條前在 Dart 端把 `entry://#x` 改寫成 `#x`，用 `loadDataWithBaseURL` 搭配固定 baseUrl 載入，由 WebView 原生處理，不需要 JavaScript。Issue 1 的驗證若顯示此做法不成立，回報後再調整。
- 偵測 LZO 壓縮區塊：匯入時顯示三段式錯誤並整批回復（Phase 1 不支援 LZO，見 `spec.md` §3.6）。
- 支援 `Encrypted=2`；記錄區塊加密（需註冊碼）匯入時顯示三段式錯誤。
- 展開標頭 `StyleSheet`；`StripKey` 與 `KeyCaseSensitive` 的查詢規則；標題為佔位字串時改用 `Description` 或檔名（見 `spec.md` §3.6）。
- 非內部連結（`http`、`https`、`file`）不載入、不開啟。

**測試要求：**
- 以自製小型 MDX fixture 做單元測試：查詢、前綴、加密偵測、壞檔、LZO 假區塊（壓縮型態標成 LZO）觸發錯誤且不留半成品。
- `dictionary_lookup_sheet_test.dart`：返回堆疊。
- 整合測試（真機）：`entry://` 可點可返回；`#錨點` 跳轉；JavaScript 不執行；網路請求被擋。

**驗收標準：** 驗收 11、16、17、21、22、34、35、36、39。

**Blocked by：** Issue 1、4、5。

---

## Issue 6b：MDX 圖片、獨立 CSS、深色與 E-Ink 配色

**Status:** ready-for-human

**依賴：** Issue 6a。

**What to build：**
- 圖片：在 `shouldInterceptRequest` 從 `.mdd` 回傳資源。網址轉成 MDD 鍵的規則以 `spec.md` §3.6 為準（去掉 baseUrl 與開頭 `/` → `Uri.decodeComponent` → 把 `/` 換成 `\` → 前面加 `\`；實測 WebView 送來的是 `https://dict.local/pic/a%20b.png`，而 MDD 的鍵是 `\pic\a b.png`）。依副檔名設 `contentType`。
- 外部 `.css`：載入詞條前，依詞條 `<link href>` 的檔名換成內嵌 `<style>`，移除 `@import`；沒有對應檔案的 `<link>` 直接移除（規則見 `spec.md` §3.6）。
- 深色與 E-Ink 配色：注入覆寫樣式，蓋掉詞條寫死的文字與背景顏色。
- MDD 鍵轉換：把 WebView 送來的網址（`https://dict.local/pic/a%20b.png`）轉成 MDD 的鍵（`\pic\a b.png`）。Issue 6a 的 `MdxReader` 薄封裝只做了 MDX 詞條讀取，**沒有**實作這段轉換（Issue 6a 計畫 I-1 已把圖片整個切給本 Issue），做法照上一條的規則實作並補單元測試。
- 已知限制寫進設定畫面說明：依賴 `onclick` 的互動（例如牛津 9 圖片放大）在 JavaScript 關閉時不運作。
- 併入 Issue 7 實機測試發現的兩項（見檔尾「後續項目」）：
  - E-Ink 模式下，`EBSheetShell`（`app/lib/screens/widgets/eb_sheet_shell.dart`）加外框，不用陰影。
  - 查字典面板開啟時隱藏系統選取控點，關閉後還原；不可清掉選取範圍。

**測試要求：**
- 配色覆寫與資源路徑解析的單元測試。
- 整合測試（真機）：圖片在無 JavaScript 下顯示；深色與 E-Ink 下文字可讀。
- 用 2 至 3 本真實 MDX 驗收（字典由人類提供）。

**驗收標準：** 驗收 18、19、25。真機量測開啟 100 MB MDX 的記憶體增量。
另加：E-Ink 面板有外框；開面板後選取控點不再蓋在面板上，關閉後選取範圍仍在。

**Blocked by：** Issue 6a。

---

## Issue 7：線上查詞（萌典）、同意對話框、隱私更新

**Status:** done（2026-10-21：已合併，PR #351）

**依賴：** Issue 3、Issue 4、Issue 5。

**What to build：**
- 在 `dictionary_settings_screen.dart`（Issue 5 建立）補上線上查詢區塊：開關、萌典說明、同意狀態卡片。
- 查詢面板的「線上查詢已關閉」提示附上通往此區塊的設定入口。
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
- 補 `docs/prd.md` 的字典 FR 條目與 `CONTEXT.md` 詞條（`epic.md` 與本檔統一在此 Issue 處理）。
- 補兩份 ADR（見 `epic.md` §10 第 4 項）。
- 補齊整合測試與真機驗收。

**測試要求：**
- `flutter analyze`、`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`。
- 完整 `flutter test`（計畫最後一個 Task 時執行一次）。
- 真機：EPUB 選字 → 查字典 → 結果顯示；E-Ink 裝置量測。

**驗收標準：** `spec.md` §9 驗收 1～39 全數成立；驗收 31（沒有取自 AGPL／GPL 專案的程式碼）由人類最終確認。

**Blocked by：** Issue 1～7。

---

## 後續項目（Issue 7 實機測試發現，不屬於 Issue 7 範圍；已併入 Issue 6b）

兩項都在 Issue 4 起就存在，Issue 7 沒有動到相關程式。2026-10-21 在 WAVE E-Ink 機實測發現。

1. **E-Ink 模式下查字典面板沒有外框。**
   - 位置：`app/lib/screens/widgets/eb_sheet_shell.dart` 的外殼只有把手、標題、關閉鍵，沒有 E-Ink 邊框。
   - 目前只有已選的分段有邊框（`dictionary_lookup_sheet.dart`）。
   - 方向：E-Ink 時外殼加外框，不用陰影。
2. **選字的圓點（系統選取控點）會一直畫在字典面板上。**
   - 原因：控點由系統畫在最上層（Android `APPLICATION_SUB_PANEL` 的 `PopupWindow`）。`ReaderScreen._handleLookupPressed` 刻意不動選取狀態，好讓關面板後還能劃線。
   - 方向：面板開啟時隱藏選取控點，關閉後還原；不可清掉選取範圍。
   - **Issue 6b Task 7 真機探測結果（2026-10-21，WAVE E-Ink 機 Android 12，結論：失敗，本 Issue 不出貨，見 `reviews/issue-6b-task-7-probe.md`）：**
     1. `InAppWebViewController.clearFocus()`（對應原生 `webView.clearFocus()`）雖能立即移除兩個系統選取控點 `PopupWindow`，但 Chromium `SelectionPopupControllerImpl.onViewFocusChanged(false)` 會連帶把章節 iframe 內的 DOM `Selection` 折疊（`isCollapsed: true, text: ""`），立刻觸發 `main.js` 的 `selectionchange` → `onSelectionCleared` → `ReaderScreen._handleSelectionCleared()`，清空 `_currentSelection` 並銷毀 `AnnotationToolbar`。
     2. 計畫所列三條還原路徑皆無法讓控點回來：
        - Flutter 端 `FocusNode.requestFocus()`：`PlatformViewLink._handleFrameworkFocusChanged` 只在 `isFocused == false` 時呼叫 `_controller.clearFocus()`，`isFocused == true` 時為空操作（`PlatformViewController` 與 `flutter_inappwebview_android` 皆無 `requestFocus` 方法）；且一旦把 `PlatformViewLink` 的 `FocusNode` 設為有焦點，後續每次開底部面板都會觸發失焦並自動呼叫 `_controller.clearFocus()` 清掉選取。
        - Flutter 端 `FocusScope.of(context).requestFocus(...)`：同樣無法還原原生 `android.webkit.WebView` 的 View 焦點（`document.hasFocus()` 維持 `false`），控點與選取皆不回來。
        - 關面板後以 JS 重新送出原選取（開面板前 `cloneRange()`，關面板後 `removeAllRanges()` + `addRange(range)`）：若曾呼叫 `clearFocus()`，因原生 `WebView` 已失去 Android View 焦點且無 `requestFocus()` 可還原，選取僅顯示為失焦灰底、控點不出現；即使不呼叫 `clearFocus()` 保留 View 焦點，Chromium Blink 的 `DOMSelection::addRange()` 對程式觸發的選取固定設 `ShouldShowHandle(false)`，只會畫出藍底反白，不會重新建立系統選取控點 `PopupWindow`。
     3. 額外探測「同一 WebView 內切換焦點 frame」（開面板時 `document.body.tabIndex = -1; document.body.focus()` 把 Blink 焦點移到外層 `index.html`，關面板時對有選取的章節 iframe 呼叫 `doc.defaultView?.focus()`）：單純開關面板、捲動 MDX 詞條或切換分段時，控點可隱藏且關面板後控點與藍底選取皆能完整回來；但只要使用者在 `MdxEntryView`（面板內的第二個 `InAppWebView`）內發生點擊（例如點 `entry://` 交叉參照或 `#錨點`），第二個原生 `WebView` 就會搶走 Android View 焦點（使底層閱讀器 `WebView` 的 `document.hasFocus()` 變成 `false`），關閉面板銷毀 `MdxEntryView` 後 Android 只把 View 焦點退回根層 `FlutterView`，底層閱讀器 `WebView` 因缺少原生 `requestFocus()` 介面而無法取回焦點，控點仍不會回來。
   - **下一步方向（留待後續工單）：**
     - 在 vendored 的 `app/patches/flutter_inappwebview_android` 補上原生 `requestFocus` channel 方法（呼叫 `webView.requestFocus()`），或讓 `MdxEntryView` 的原生 `WebView` 不搶奪觸控焦點（`setFocusable(false)` / `setFocusableInTouchMode(false)`），再搭配 `FoliateReaderView` 內外層 frame 焦點切換（開面板聚焦外層 `document.body`、關面板先 `controller.requestFocus()` 再聚焦章節 `iframe`），即可在不改 `main.js` 且不破壞 DOM `Selection` 的前提下穩定隱藏並還原系統選取控點。

另有一張 2026-10-21 16:46 的紅畫面截圖（字典設定拖曳排序：`No Material widget found`）。後續實測沒有再出現。

3. **WAVE E-Ink 機長按選字很難觸發（2026-10-22，真機錄影與觸控原始訊號，結論：裝置觸控限制，本 Issue 不處理）。**
   - 現象：手指長按文字，工具列很久才出現或不出現，畫面還會閃一下（錄影 `tmp/images/難選字.mp4`）。
   - 觸控訊號（`adb shell getevent -l -t /dev/input/event4`，裝置 `cyttsp5_mt`）：
     - 25 秒 51 次按壓，平均約 0.3 秒就斷開；超過 0.5 秒的按壓有 10 次，其中 9 次同時偵測到 2 至 5 個接觸點、位置橫跳。
     - 只用單根指尖按住不動，同一個位置（誤差 ±3 單位）在 1.6 秒內連續回報 7 次「按下、放開」，每次 0.02 至 0.43 秒；沒有任何一次達到長按需要的約 0.5 秒連續接觸。
   - 對照：用 `adb shell input swipe` 注入的單指長按（500 至 1500 ms、手指飄移到 16 px）每次都成功跳出工具列，所以 App 的長按到選字流程本身正常。
   - 判讀（假設，未證實）：觸控面板或電子紙刷新干擾造成斷訊；「畫面閃一下」可能是同一個原因。唯一確定的是：訊號層面同一點會連續斷訊，且常同時出現 2 至 5 個接觸點。
   - 可能的方向（皆未做）：用 Wacom 電磁筆選字（不受電容觸控斷訊影響，未驗證）；在 App 內做容忍斷訊的長按偵測（動到選字核心，風險高，需另立計畫）；在系統桌面長按圖示錄同樣的訊號，確認是否整台裝置的問題。
   - 相關的已修問題：選字時多一根手指碰螢幕會讓整頁縮放（Task 10 已關閉流式格式的 WebView 原生縮放）。上述 2 至 5 個幽靈接觸點可能就是當時縮放誤觸的來源，兩者可能有同一個根因。
