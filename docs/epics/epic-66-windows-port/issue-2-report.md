# Issue 2：Windows Metadata 解析——對比與記憶體報告

本報告記錄 epic-66 Issue 2 的實測結果：Android Readium 與 Windows foliate-js 的 metadata 逐欄對比、224 MB 大檔的記憶體量測，以及程式碼審查（`reviews/review-issue-2.md`）發現的**記憶體洩漏**的診斷與修正。

> **這份報告取代了先前的版本。** 先前版本寫「無常駐洩漏（Residual Leak = 0 MB）」，那個結論是看「App 程序結束後回落」得出的，**是錯的**。審查指出後，實測證明每解析一次 224 MB 的書，App 私有記憶體會永久多約 452 MB。下文第 4 節記錄完整過程。

---

## 1. 測試環境

- **Android（Readium）：** BooksPad（`B78CW2508006423`，Android 12），原生通道 `elinkbook/book_metadata`。指令：`flutter test integration_test/metadata_comparison_test.dart -d B78CW2508006423`。
- **Windows（foliate-js）：** Windows 11 x64、WebView2。實作為 `HeadlessInAppWebView` 加 `metadata-probe.js`。指令：`flutter test integration_test/windows_metadata/epub_metadata_test.dart -d windows`。
- **版本：** 記憶體診斷迴圈用 debug 版；批次匯入量測（修正前）用 release 版。兩者標在各表。

---

## 2. 13 份 Fixture 逐欄對比

比對欄位：書名（title）、作者（author）、識別碼（identifier）、是否固定版面（isFixedLayout）、有無封面。**13 份全部一致，不一致 0 份。**

| Fixture | title | author | identifier（兩端相同） | 固定版面 | 封面（Readium／foliate 位元組） |
|---|---|---|---|---|---|
| `meta_basic` | 基本書名 | 王小明 | `urn:uuid:meta-basic` | 否 | 有（99／70） |
| `meta_multi_identifier` | 多識別碼 | null | `urn:uuid:meta-multi-second` | 否 | 無 |
| `meta_lang_titles_two_creators` | 繁中書名 | 王小明 | `urn:uuid:meta-lang` | 否 | 無 |
| `meta_creator_role` | 角色作者 | 張三 | `urn:uuid:meta-role` | 否 | 無 |
| `meta_epub2_cover` | EPUB2 封面 | null | `urn:uuid:meta-epub2` | 否 | 有（99／70） |
| `meta_no_cover` | 無封面 | null | `urn:uuid:meta-nocover` | 否 | 無 |
| `meta_fixed_layout` | 固定版面 | null | `urn:uuid:meta-fxl` | **是** | 無 |
| `meta_no_identifier` | 無識別碼 | null | `null` | 否 | 無 |
| **`meta_unique_id_dangling`** | 識別碼懸空 | null | `9789860000009` | 否 | 無 |
| **`meta_identifier_whitespace`** | 識別碼含空白 | null | `urn:uuid:meta-ws` | 否 | 無 |
| **`meta_identifier_opf_scheme`** | 識別碼含 opf:scheme | null | `urn:uuid:meta-scheme` | 否 | 無 |
| `sample` | elinkBook 範例 EPUB | null | `urn:uuid:00000000-0000-0000-0000-000000000001` | 否 | 有（105／73） |
| `sample_fxl_svg_cover` | elinkBook FXL 範例（…alternates 可達） | null | `urn:uuid:00000000-0000-0000-0000-000000000002` | **是** | 有（105／73） |

粗體三列是審查（Important 5）要求補的邊界案例。三種邊界在兩端取值相同：

- `unique-identifier` 指向不存在的 id：兩端都退回**第一筆** `dc:identifier`（ISBN）。
- identifier 帶前後空白與換行：兩端都去掉空白。
- identifier 帶 `opf:scheme`：兩端都取 `unique-identifier` 指向的那筆。

封面位元組不同是已知的：Android 把封面解碼成 `Bitmap` 再壓成 PNG（99／105 位元組），foliate-js 直接取 zip 內的原始圖檔（70／73 位元組）。兩者皆為有效圖片，且 Windows 的 `_landCover` 一律寫成 `<bookId>.png`，Flutter 依內容解碼，實務上沒有影響。

---

## 3. identifier 一致性的結論與限制

`book_content_fingerprint.dart` 優先用 `identifier` 當指紋，兩端不一致會讓同步把同一本書當成兩本，所以這是本 Issue 最重要的對比。

**結論：已測的 13 份沒有任何不一致。** 這是「已測案例無不一致」，**不是**「零風險」的保證。

**未驗證的範圍（誠實列出）：**

- 只涵蓋 13 份人工建構的 fixture。真實出版社書籍（EPUB 2 套件、更多樣的 `dc:identifier` 寫法、非標準 OPF）尚未與 Readium 對比。
- 224 MB 的真實書（見第 4 節）只跑了 foliate 端，沒有在 BooksPad 上跑 Readium。
- Readium 與 foliate-js 的版本差異、不同 Android WebView 版本是否影響 foliate-js 的取值，沒有驗證。

**建議：** 之後用使用者書庫裡的真實 EPUB（數十本）各跑一次兩端，再決定是否統一兩端至 foliate-js。

另外更正 Issue 1 報告的一個錯誤：foliate-js 的作者欄位是 `metadata.author`（字串、`{name, role}` 物件或陣列），不是 `creator`；書名可能是語系物件如 `{"zh-TW":"繁中書名"}`。`metadata-probe.js` 的 `firstText()` 已處理這些形態。

---

## 4. 大檔記憶體：發現洩漏、診斷、修正

### 4.1 時間線

| 階段 | 做法 | 結論 |
|---|---|---|
| 第一版報告 | 單次解析 224 MB，看「程序結束後回落」 | 誤判「無洩漏」；量測腳本還混入了全系統的 WebView2 程序 |
| 審查 | 指出結論沒有證據、腳本違反「只算 App 子孫程序」 | 重量 |
| 批次匯入（release 版，同一個 App 程序） | 匯入 5 本，再匯入 5 本 224 MB 的複本 | 見 4.2 |
| 診斷迴圈（debug 版） | 同一程序內只重複 `extractWindowsBookMetadata`，程序內讀記憶體 | 洩漏在 metadata 解析路徑，不在匯入流程 |
| 假設驗證與排除 | 見 4.3 | 洩漏在 `shouldInterceptRequest` 回傳大資料之後的原生端 |
| 修正 | 只傳需要的區段 | 見 4.4 |

### 4.2 修正前：批次匯入實測（release 版，只計 App 及其 WebView2 子程序，平均取樣間隔 0.09 秒）

| 階段 | `elinkbook.exe` 穩定值 | WebView2（App 子程序） |
|---|---|---|
| 匯入前 | 約 295 MB | 約 320 MB |
| 第 1 批 5 本匯入後 | **1,414 到 1,473 MB**（+約 1.1 GB） | 約 321 MB |
| 第 2 批 5 本匯入後 | **2,559 MB**（再 +約 1.1 GB） | 約 324 MB |
| App 尖峰 | 第 1 批 3,332 MB／第 2 批 **5,032 MB** | 1,679 到 1,718 MB |

每 5 本多約 1.1 GB（約書檔大小），**兩批線性累加**，不是第二批重複使用第一批的空間。WebView2 每次回到約 320 MB，所以洩漏在 `elinkbook.exe` 自己的程序。

### 4.3 診斷（debug 版，同一程序重複解析同一本 224 MB 書，每次後等 6 秒）

| 實驗 | 每次解析後的變化 |
|---|---|
| 無修改 | 私有記憶體 359 → 816 → 1,268 → 1,722 → **2,173 MB**（每次 **+約 452 MB，約書檔 2 倍**）；工作集每次 +約 228 MB；不回落 |
| 每次攔截都回傳**同一個** Dart `Uint8List` | 工作集第 1 次 +461 MB，之後每次約 +225 MB → **排除 Dart 端抓著** |
| 補外掛 `toWebView2Response()` 少的 `Release()` | 數字**完全不變**（649、877、1,104、1,331）→ 那是真的程式缺陷，但**不是主因**，已移除該修補 |

**結論：** 洩漏在 `shouldInterceptRequest` 回傳大資料之後的原生端（外掛或 WebView2 內部），量與「傳輸的位元組」成正比。**更細的根因沒有查明**（外掛 C++ 與 WebView2 內部程式碼不在我們手上）。

### 4.4 修正：只傳需要的區段

metadata 只需要 ZIP 中央目錄、OPF 與封面。`metadata-probe.js` 新增 `readBookMetadataByRange`（類 Blob 物件，256 KB 區塊快取），Dart 的攔截只回應被要求的 `start`／`end` 區段，沒帶參數絕不整本回傳。

**修正後（debug 版，同一程序）：**

| | 修正前 | 修正後 |
|---|---|---|
| 4 次解析後私有記憶體 | 2,173 MB | **381 MB**（359 → 372 → 377 → 380 → 381） |
| 每次後續解析的增量 | 約 +452 MB | **約 +3 到 5 MB** |
| 解析當下工作集增量 | 約 +235 MB 且不回落 | 約 +14 MB |
| 224 MB 解析耗時 | 9,019 ms | **約 2,500 ms**（2,486／2,524） |
| 解析時 App 尖峰 | 約 2.5 到 5 GB | **約 439 MB** |
| 解析時 App 加 WebView2 合計尖峰 | 約 3.7 到 4.3 GB | **約 800 MB** |
| 解析結果 | 書名、作者、識別碼、封面 716,032 位元組 | **完全相同** |

殘餘的每次約 3 到 5 MB 與每次傳輸量（約 1 到 2 MB，主要是封面）相稱，符合「洩漏與傳輸量成正比」的解釋。

**測試與證據：**

- `scenario-metadata-probe-range.mjs`：13 份 fixture 與整檔讀取結果一致；一本 **8 MB** 填充書只傳 **264 KB（2 次請求）**；`fetchRange` 失敗與損毀檔案都會 reject。
- `test/library/windows_epub_range_test.dart`：`readFileRange`、`parseBookRange` 的邊界與上限。
- `integration_test/windows_metadata/leak_probe_test.dart`：自動重現洩漏的迴圈（保留作為回歸量測）。

### 4.5 限制（誠實列出）

- 修正後的記憶體數字是 **debug 版、單程序、單一本書**；**release 版的批次匯入沒有重量**（修正前的批次數字是 release 版）。
- 取樣只涵蓋測試程序的存活期，平均間隔 0.05 秒、最大 0.97 秒，極短的尖峰可能漏掉。
- 先前報告的「UI 不凍結」**沒有量測**（沒有 frame time），已移除該說法。
- 洩漏的更細根因（外掛或 WebView2 哪一段不釋放）**未查明**；我們是繞開它，不是修好它。

---

## 5. 未解決的連帶風險：閱讀器開書路徑

同樣的 `shouldInterceptRequest` 整本回傳機制也用在：

- **閱讀器開書**（`FoliateReaderView`，Issue 1）：整本書位元組走攔截回應。
- **全文索引器**（`FoliateContentIndexer`）：同樣用 `HeadlessInAppWebView`。

洩漏**只在 headless metadata 路徑被證明**。Issue 1 的實測顯示：在閱讀器裡開同一本 224 MB 的書再離開，App 記憶體沒有多出約兩份書的大小，所以閱讀器路徑**可能不受影響**，但原因沒有查明，也沒有針對性驗證。**建議另開 Issue 驗證**閱讀器與索引器路徑：同一程序內重複開關同一本大書，量私有記憶體。

---

## 6. 審查意見處理紀錄（`reviews/review-issue-2.md`）

| 項 | 意見 | 處理 |
|---|---|---|
| Important 1 | 量測腳本取全系統 WebView2 程序 | 已重寫，只計 App 子孫程序（根程序名可設定、每 1 秒重掃子孫程序） |
| Important 2 | 「無常駐洩漏」沒證據 | 實測**推翻**原結論，找到並修正洩漏（4.1–4.4） |
| Important 3 | App 端尖峰 2.5 GB 沒解釋 | 同一修法：尖峰降到約 439 MB；「UI 不凍結」說法已移除 |
| Important 4 | 範圍外的 `gradle.properties` | 已還原（`665944b6`） |
| Important 5 | identifier 一致性只驗 10 份 | 補 3 份邊界 fixture，13 份兩端一致；結論改成「已測案例無不一致」並列出未驗證範圍（第 3 節） |
| Minor 3 | 新情境沒登錄進 `run-all.mjs` | **不成立**：`run-all.mjs` 以 `scenario-*.mjs` 自動收集（審查報告已更正） |
| 其餘 Minor | 角色區辨力、封面副檔名、`callHandler` 型別強轉、固定 50 ms 延遲等 | 未處理，列為後續（見審查報告 Minor 1、2、4、5、6、7） |
