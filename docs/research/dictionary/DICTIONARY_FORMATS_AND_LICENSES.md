# 字典格式與授權

調查日期：2026-10-19。

**本文不是法律意見。** 標記「待查證」的項目，實作前必須讀原始授權文件確認。

## 1. 已決定

- Phase 1 匯入格式：JSON/CSV 與 MDX。
- StarDict：延後。介面預留。
- 線上查詞：預設用萌典 API。自訂網址延後。
- App 不內建任何字典資料。使用者自行匯入。

## 2. 格式比較

| 項目 | JSON/CSV | MDX/MDD | StarDict |
|---|---|---|---|
| 檔案組成 | 單一文字檔 | `.mdx`（詞條）、`.mdd`（圖片、音訊） | 同資料夾多檔：`.ifo`、`.idx`、`.dict` 或 `.dict.dz`、選用 `.syn` |
| 詞條內容 | 純文字或 HTML，由我們定欄位 | HTML | 純文字、HTML 或 Pango，依 `.ifo` 的 `sametypesequence` |
| 解析難度 | 低 | 高：加密、多種壓縮、版本差異 | 中：`.idx` 排序，`.dz` 是可隨機讀取的 gzip |
| 取得來源 | 使用者自製、整理 | 華語圈最多。牛津、朗文等多為有版權檔案 | 有可自由散布的字典（待查證各自授權） |
| Phase 1 | 做 | 做 | 不做 |

StarDict 格式資訊來自一般知識，實作前對照官方格式文件確認。

## 3. 匯入策略

### JSON/CSV：匯入成標準化 SQLite

- 解析後寫入 `dictionary.db`（獨立資料庫，不動主庫）。
- 查詢走索引，不需整檔載入記憶體。
- 優點：查詢快、行為可預測、可分批匯入並顯示進度。
- 缺點：匯入需時間，佔用額外儲存空間。

建議表結構（草案，實作計畫會再定稿）：

```
dictionary_sources
  id, name, format, source_lang, target_lang,
  priority, enabled, storage_path, entry_count,
  license_note, imported_at

dictionary_entries            -- 只給 JSON/CSV 來源
  id, source_id, headword, headword_norm,
  pronunciation, part_of_speech, body, body_kind
  INDEX (source_id, headword_norm)
```

### MDX：保留原檔，不轉入 SQLite

- 複製到 App 私有目錄，用解析器直接查。
- 原因：MDX 動輒數十到數百 MB，轉入 SQLite 會讓匯入很慢、空間加倍。
- 解析器依賴詞典內建的排序索引做查詢，需要實測確認。
- 資源檔 `.mdd`（圖片、音訊）Phase 1 只做「找得到就顯示，找不到就略過」，詳見實作計畫。

### 查詢字串正規化

- 去頭尾空白與標點。
- 英文轉小寫。
- 簡繁互轉**僅用於查本機字典的候選詞**，**不用於萌典結果的顯示**（見 §6 的 ND 條款）。

## 4. MDX 解析器評估

兩個候選都**尚未用真實字典實測**。以下是從 pub.dev 與 GitHub 頁面讀到的資訊。

| 項目 | `mdict_flutter` | `dict_reader` |
|---|---|---|
| 版本 | 0.1.1 | 1.6.1 |
| 授權 | BSD-3-Clause | MIT |
| 發布 | 2025-11-18 | 約 51 天前（查詢當時） |
| 格式 | MDX、MDD | MDX、MDD |
| 已知缺口 | 頁面未說明 v3、LZO、加密 | 不支援校驗碼、LZO、v3、加密區塊 |
| 查詢 API | `lookup`、`prefixSearch`、`locate` | 待讀 API 文件 |
| 平台 | Android、iOS、Linux、macOS、Windows | 同左 |
| 成熟度 | GitHub 0 星、3 個 commit；pub.dev 下載 10 次 | 下載 470 次，pub points 150 |
| 來源風險 | 自稱「基於 mdict-cpp 原理的復刻實作」。mdict-cpp 的授權與是否含 GPL 程式碼**待查證** | 待查證 |

來源：[mdict_flutter（pub.dev）](https://pub.dev/packages/mdict_flutter)、[mdict_flutter（GitHub）](https://github.com/stevennight/mdict_flutter)、[dict_reader（pub.dev）](https://pub.dev/packages/dict_reader)。

### `readest/js-mdict` 可行性（2026-10-19，已決定不採用）

- v7.0.0（2026-03-20）起，`js-mdict` 從 MIT 改為 **AGPL-3.0**。README 寫明：v7.0.0 之前的版本仍是 MIT；要用在閉源 App，需向作者購買商業授權。
- Readest 的分支（最後推送 2026-05-28）在 v7 之後，是 AGPL。瀏覽器用的 Blob 讀取、延遲初始化、非同步 API 都只在這些版本。
- 最後一個 MIT 版本是 v6.0.7（2025-01）。它只能用 Node 的 `fs` 讀檔，沒有瀏覽器版。內含 LZO（`lzo1x`）與 `ripemd128`。
- 技術上要用它，得開一個 JavaScript 開啟的 WebView，再另外做本機大檔的隨機讀取，記憶體影響未量測。
- **決定（2026-10-19）：不用 v7 以後的任何程式碼。** 理由：AGPL 會連到整個 App，與 Epic 的「不含 AGPL／GPL 程式碼」驗收衝突。
- 保留的備案（Issue 1 驗證後才決定）：
  1. 在 MIT 授權下修補（vendor）`dict_reader`，補上缺的功能。
  2. 把 MIT 的 v6.0.7 移植成 Dart。保留版權聲明。移植者不得參考 v7 以後的程式碼。

### 補充證據（GitHub API，2026-10-19）

| 項目 | `mdict_flutter` | `dict_reader` |
|---|---|---|
| 最後推送 | 2025-11-18（約 11 個月無更新） | 2026-09-24 |
| 倉庫授權欄位 | BSD-3-Clause | MIT |

- `mdict_flutter` 自稱復刻 `mdict-cpp`。GitHub 上的 `dictlab/mdict-cpp` 授權為 BSD-3-Clause，血統看起來乾淨。但無法確認作者參考的就是這個倉庫，仍列為待查證。
- 同類型的 JavaScript 解析器 `js-mdict`（Readest 使用其分支）是 **AGPL-3.0**。MDX 解析器常見傳染性授權，引入前務必讀 LICENSE 與相依套件。
- 維護狀況偏向 `dict_reader`。

### 結論

- **尚未選定。** 先在 Phase 1 的第一個 Issue 做「技術驗證」（spike），用 2 至 3 本真實 MDX 比較。
- 傾向 `dict_reader`：授權乾淨、較多人用。
- 缺 LZO 是實際風險。部分舊 MDX 用 LZO 壓縮。驗證時要挑一本 LZO 的字典看會怎樣。
- 不論選哪個，都藏在 `DictionaryImporter` 與 `MdxReader` 介面後面。換套件不影響其他程式。
- 若兩個都不夠用，備案是自己寫解析器。這要另開評估，不在 Phase 1 預設範圍。
- 引入前，在 `DICTIONARY_FORMATS_AND_LICENSES.md` 補上「驗證結果」一節。
- 引入後，授權全文加進 `app/assets/licenses/` 並登錄到 `app/lib/licenses/third_party_licenses.dart`。

### 驗證清單

1. 用 `flutter pub get` 確認不破壞 `pubspec.yaml` 的 `win32` 相依解析。
2. 開啟 100 MB 以上的 MDX：記錄開啟時間、記憶體增量。
3. 精確查詢與前綴查詢各 100 次：記錄中位數與 p95 延遲。
4. 有 LZO、有加密、v3 的檔案：確認是丟出明確錯誤，不是當掉。
5. 檔名與內容為 UTF-8、UTF-16、Big5 的 MDX：確認編碼。
6. 在實體 E-Ink 裝置上重做第 2、3 項。
7. `Encrypted=2`（只加密關鍵字索引區，不需密碼）的檔案能否開啟與查詢。
8. 標頭有 `StyleSheet` 的檔案：詞條內的 `` `數字` `` 標記是否被展開；若套件不處理，記下需在 `MdxReader` 補。
9. `StripKey=Yes` 的檔案：查詢字串的空白與標點處理是否與製作時一致。
10. 詞條 HTML 引用的外部 CSS 沒有一併匯入時：行為是否安全（不當掉、不載入網路）。
11. 目前三個驗收檔都沒有 LZO，手上也沒有 LZO 字典。Phase 1 決定不支援 LZO（2026-10-19），只確認遇到 LZO 區塊時丟出明確錯誤；可用自製的假區塊測試，不需要真字典。

### 驗證結果（Issue 1，2026-10-19）

**結論：採用 `dict_reader 1.6.1`（MIT）。** `mdict_flutter` 淘汰。

#### 決策規則的套用

| 順序 | 條件 | 結果 |
|---|---|---|
| 1 | `mdict_flutter` 在兩個真實檔案開啟失敗 | 成立，淘汰。兩個檔案都丟 `FormatException: Filter error, bad data`（`report/mdict_flutter_elimination.json`）。另讀原始碼確認：記錄區塊壓縮型態不是 zlib 時 `return null`，與「查無此詞」無法區分 |
| 2 | `dict_reader` 真實檔開啟失敗，或遞移相依有 GPL／AGPL／LGPL | 不成立。兩個檔案都能開啟；授權見下表，無 copyleft |
| 3 | `large.mdx` 記憶體增量 < 50 MB 且 p95 < 300 ms | 成立，但前提很窄：合成的 ASCII 鍵、一台非 E-Ink 實機、查詢集中於前 1000 筆；**開啟後增量最高 45.0 MB，離門檻只剩 5 MB**。真實大檔、隨機查詢、E-Ink 都要補測，見「效能」一節的警語 |

#### `dict_reader` 授權（含遞移相依）

| 套件 | 版本 | 授權 | 放進 `app/assets/licenses/` |
|---|---|---|---|
| dict_reader | 1.6.1 | MIT | 是 |
| blockchain_utils | 6.0.0 | BSD-3-Clause | 是 |
| pointycastle | 4.0.0 | MIT（Bouncy Castle） | 是 |
| charset | 2.0.1 | Apache-2.0 | 是 |
| convert、collection、typed_data、html_unescape | 3.1.2、1.19.1、1.4.0、2.0.0 | BSD-3-Clause | 是 |

另：`flutter pub add dict_reader --dry-run` 在 `app/` 解析成功，只新增 `dict_reader`、`blockchain_utils`、`charset`、`convert`、`html_unescape`、`pointycastle`，沒有升降級既有套件，`win32` 相依鏈不受影響。

#### 真實檔案（`dict_reader`）

| 項目 | 教育部 MDX | 古漢語 MDX |
|---|---|---|
| 開啟（`Encrypted=2`） | 成功，163,085 筆 | 成功，7,587 筆 |
| `lookup('一')` | 命中 | 命中 |
| 取樣 200 個鍵全部可查 | 是 | 是 |
| `StyleSheet` 展開 | 已展開，200 筆取樣無 `` `數字` `` 殘留 | 無樣式表 |
| `StripKey=Yes` | — | **不處理**：`' 一 '`、`'一，'` 查無 |
| 標題佔位字串 | — | `Title (No HTML code allowed)`，`Description` 非空 |
| 缺檔 CSS | — | 詞條內含 `<link href="ghychyz.css">`，查詢本身不受影響 |
| CJK／全形括號檔名 | 在 Android 上複製成該檔名後可正常開啟 | 同左 |

#### 合成檔案

- 通過：開啟、50 筆、查詢命中／查無、空字串與純空白鍵不丟例外、前綴搜尋、CJK 鍵、假 LZO 區塊丟 `unsupportedCompression`（`dict_reader` 丟的是**字串**，轉接層包成統一例外）、截斷檔 10 秒內丟 `corrupt`、檔案不存在丟 `notFound`。
- 失敗：`KeyCaseSensitive=No` 時 `lookup('APPLE')` 查無（`dict_reader` 以精確字串比對）。見 `report/synthetic_failures.md`。
- MDD：只有反斜線形式 `\pic\a b.png` 查得到；`/pic/a b.png`、`pic/a b.png` 都查無。

#### 效能

實機：OPPO OPD2102（Android 13、3.7 GB RAM、release 模式；**非 E-Ink**）。每次量測前強制停止 App，一次只量一個檔案。

| 檔案 | 筆數 | 開啟 | 開啟後記憶體增量 | 查詢後記憶體增量 | p50 | p95 |
|---|---|---|---|---|---|---|
| 教育部（UTF-16，3 次） | 163,085 | 630–643 ms | 21.7–24.3 MB | 25.5–27.8 MB | 0.07 ms | 0.22 ms |
| 古漢語（1 次） | 7,587 | 37 ms | 0.0 MB | 1.0 MB | 0.01 ms | 0.05 ms |
| large.mdx（102 MB 合成，3 次） | 400,000 | 1,123–1,170 ms | **40.1–45.0 MB** | 24.6–42.6 MB | 0.01 ms | 0.82–1.24 ms |

- 查詢只量了精確查詢 100 次；前綴查詢未在實機量測。
- 門檻定義的是「開啟 100 MB MDX」的記憶體增量，所以以**開啟後增量**為準：large.mdx 為 40.1–45.0 MB，峰值 45.0 MB，離 50 MB 只剩 5 MB。「查詢後增量」較低（24.6–42.6 MB）是 GC 在開啟後才回收，不代表實際用量下降。（最後審查指出：初版文件採用了查詢後的數字，低報了峰值。）
- `dict_reader` 會把所有鍵載入記憶體，增量與筆數成正比。以下三個因素讓這個結果只代表「最有利的情境」：
  1. **鍵的形式**：large.mdx 的鍵是 ASCII 的合成詞，Dart 對 ASCII 字串較省記憶體。每把鍵約 108 B；教育部（UTF-16 的 CJK 鍵）約 140 B。照此外推，一本 40 萬筆的真實 CJK 字典約 56 MB，可能超過 50 MB。
  2. **查詢沒讓快取長大**：量測的查詢鍵取自 `prefix('', limit: 1000)`，只落在前幾個記錄區塊；`dict_reader` 有最多 32 MB 的記錄區塊快取。實際隨機查詢時，快取最多再加 32 MB。
  3. **薄封裝的額外記憶體**：`KeyCaseSensitive=No` 的大小寫摺疊，因 `dict_reader` 以精確字串比對，可能需要另建一份摺疊後的鍵索引，這份記憶體尚未估算。
- 因此 E-Ink 補測（與 Issue 6a 開工前）必量：真實 CJK 大檔或 UTF-16 合成大檔、隨機鍵查詢、穩態 RSS（含快取）、開啟後峰值。
- 桌面預檢（Windows，非實機）：教育部開啟 3.5 s、增量 30.6 MB；large 開啟 0.6 s、增量 45.1 MB。

#### WebView（`javaScriptEnabled: false`，System WebView 155，`loadDataWithBaseURL`，baseUrl `https://dict.local/`）

- `#錨點` 在無 JavaScript 下**原生跳轉成立**（截圖為證）。純 `#錨點` 導航**不觸發** `shouldOverrideUrlLoading` 與 `onUpdateVisitedHistory`，所以不能靠這兩個回呼偵測，也不需要攔截。`spec.md` §3.6 的「Dart 端把 `entry://#x` 改寫成 `#x`」做法可行。
- `entry://apple`：`shouldOverrideUrlLoading` 收到原樣字串。回傳 ALLOW 時還會進 `shouldInterceptRequest`；實作要回傳 CANCEL。
- 圖片：三種寫法（`pic/a b.png`、`pic/a%20b.png`、`\pic\a b.png`）全部歸一成 `https://dict.local/pic/a%20b.png`（空白變 `%20`、反斜線變 `/`，且只送一次請求）。
- `shouldInterceptRequest` 也會收到 `data:text/html;...` 與 `https://dict.local/favicon.ico`。**回傳 `null` 的請求會走真實網路**，所以要擋網路，就必須對所有 `http(s)` 請求回傳明確的回應。
- 探針 App 缺 `INTERNET` 權限時 `InAppWebView` 建立失敗；正式 App 已有此權限。

#### `MdxReader` 薄封裝必須補的功能

1. `KeyCaseSensitive=No`：對鍵與查詢字串套用同一個大小寫摺疊。
2. `StripKey=Yes`：查詢字串套用與製作時相同的去空白、去標點規則。
3. 標題為佔位字串時改用 `Description` 第一行，再不行用檔名。
4. 把字串例外與各種例外包成統一的錯誤型別（`unsupportedCompression`、`corrupt`、`notFound`），LZO 顯示三段式錯誤。
4a. **匯入時就擋下 LZO 與截斷檔**：`dict_reader` 的 `open()` 不解壓記錄區塊，假 LZO 檔與「截在記錄區段」的檔案都能 `open()` 成功；LZO 要到該區塊第一次被查詢才丟錯，截斷檔則只有落在被截區域的鍵才出錯，其餘鍵照常回傳。`spec.md` §3.6 與驗收 39 要求匯入時就顯示錯誤並整批回復，所以匯入流程必須掃描所有記錄區塊的壓縮型態欄位與實際長度。已用兩個會失敗的測試描述這項缺口（`synthetic_fixtures_test.dart` 的 `open() alone rejects ...`，標籤 `wrapper-gap`）。
5. MDD 資源鍵轉換：網址 → 去掉 baseUrl 與開頭 `/` → `Uri.decodeComponent` → 把 `/` 換成 `\` → 前面加 `\`（順序以 `spec.md` §3.6 為準：先剝 baseUrl 再解碼，避免編碼後的斜線 `%2F` 干擾剝除）。
6. `shouldInterceptRequest` 對所有 `http(s)` 請求（含 `favicon.ico`）回傳明確回應，找不到就回 404 空內容。
7. 缺檔 CSS：把沒有對應檔案的 `<link>` 移除（`spec.md` §3.6 已定）。

#### 驗證清單逐項

| # | 項目 | 結果 |
|---|---|---|
| 1 | `pub` 相依解析 | 完成，無衝突 |
| 2 | 開啟 100 MB 以上 MDX：時間、記憶體 | 完成（合成檔，實機一台） |
| 3 | 精確與前綴查詢 p50／p95 | 精確查詢完成；**前綴查詢未在實機量測** |
| 4 | LZO、加密、v3 的錯誤行為 | LZO 以假區塊完成；`Encrypted=1`（記錄區塊加密）與 v3 **未驗證**（沒有樣本） |
| 5 | UTF-8、UTF-16、Big5 | UTF-8、UTF-16 完成；**Big5 未驗證**（沒有樣本） |
| 6 | E-Ink 裝置重做第 2、3 項 | **未驗證**（沒有 E-Ink 裝置）。Issue 6a 開工前補測；若記憶體增量超過 50 MB，備案是修補（vendor）`dict_reader` 改成依區塊延遲載入鍵 |
| 7 | `Encrypted=2` | 完成，兩個真實檔都通過 |
| 8 | `StyleSheet` 展開 | 完成，`dict_reader` 內建 |
| 9 | `StripKey=Yes` | 完成，`dict_reader` 不處理，需在 `MdxReader` 補 |
| 10 | 缺檔 CSS | 完成，查詢不受影響；WebView 端要攔截所有請求 |
| 11 | LZO 驗收檔 | 不取得；Phase 1 不支援 LZO，已用假區塊驗證錯誤路徑 |

原始量測與探針輸出在 `.scratch/mdx_spike/report/`（不進版控）。

### 驗收檔探測結果（2026-10-19，唯讀，只讀標頭與區塊型態）

檔案放在 `tmp/dictionary/`（已被 `.gitignore` 排除，不進版控）。文件只記格式資訊，不貼內容。

| 項目 | 教育部重編國語辭典（第五版） | 簡明古漢語常用字字典（川大版 2003）正體 |
|---|---|---|
| 大小、詞條數 | 20 MB、163,085 筆 | 464 KB、7,587 筆 |
| 版本、編碼 | 2.0、UTF-16 | 2.0、UTF-8 |
| 壓縮 | 只看到 zlib | 只看到 zlib |
| `Encrypted` | 2 | 2 |
| `StyleSheet` | 有（詞條含 `` `數字` `` 標記） | 空 |
| `StripKey` | No | Yes |
| `Title` | 有意義的書名 | 預設佔位字串 `Title (No HTML code allowed)` |
| 外部資源 | 無 `.mdd`、`.css` | 詞條引用 `ghychyz.css`，但目錄中沒有此檔；使用自訂標籤 |
| 方向 | 中→中 | 中→中（古漢語） |

對設計的影響：

- 兩個檔案都是 `Encrypted=2`，所以解析器必須支援關鍵字索引區解密，這是 Issue 1 的必過項目。
- 標題為佔位字串時，字典名稱改用 `Description`，再不行用檔名。
- `StripKey=Yes` 時，查詢字串要套用同樣的去空白、去標點規則。
- CSS 檔名可能和 MDX 主檔名無關（此例為 `ghychyz.css`），所以不能只用主檔名配對。詳見 `spec.md` §3.6。
- 這兩份是第三方打包檔，授權不明。教育部《重編國語辭典》本身是 CC BY-ND 3.0 TW。只作本機測試與 Issue 1 驗收，不進版控、不放 fixtures。

### CC-CEDICT 實測（2026-10-19）

- `https://cc-cedict.org/editor/editor.php?handler=Download` 回傳的是編輯器網頁，不是資料。
- 正式發行檔在 MDBG：`https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.zip`（壓縮檔 3.98 MB，內含 `cedict_ts.u8` 9.87 MB）。
- 125,297 筆，日期 2026-10-17。檔頭註明授權為 CC BY-SA 4.0，並列出引用作品 CEDICT（Paul Andrew Denisowski）。
- 格式：純文字，一行一筆，`#` 開頭為註解：`繁體 簡體 [pin1 yin1] /釋義1/釋義2/`。
- 釋義中可含交叉參照，例如 `see 五寨縣|五寨县[Wu3 zhai4 Xian4]`。
- 它不是 JSON、CSV 或 MDX，所以 Phase 1 新增 `CedictImporter`（見 `spec.md` §5）。
- 不內建、不散布。使用者自行下載後匯入。ShareAlike 只約束資料及其改作，我們不重新散布。

## 5. 授權與散布

### 不可做的事

- 不複製任何 GPL 字典應用程式的程式碼進本 App（例如 GoldenDict）。若要參考，先做獨立授權審查。
- 不在 App 或網站內附帶有版權的字典檔。
- 不把字典資料放進同步（PocketBase）。

### 套件授權

- BSD-3-Clause 與 MIT 都要求散布時保留版權聲明。比照 `foliate-js`、`OpenCC` 的做法，加進授權頁。

### 候選字典來源（皆待查證授權條款與格式）

| 來源 | 方向 | 授權（印象，待查證） | 備註 |
|---|---|---|---|
| CC-CEDICT | 中→英 | CC BY-SA 4.0（檔頭已確認） | 簡體與繁體並列；Phase 1 以 `CedictImporter` 匯入，見上方實測 |
| ECDICT | 英→中 | MIT | 中文為簡體。英→**繁中**需轉換，轉換是否算改作待查證 |
| 教育部《重編國語辭典修訂本》 | 中→中 | CC BY-ND 3.0 TW | 要標示來源，不可改動詞條 |
| FreeDict | 多語 | 依各字典 | 是否有英→繁中待查證 |

**風險**：英→繁中的自由授權字典稀少。Phase 1 可能只能提供匯入機制，由使用者自備字典。

## 6. 萌典（moedict）線上 API

### 事實

- API 文件在 [g0v/moedict-webkit](https://github.com/g0v/moedict-webkit)，不在 `g0v/moedict.tw`。
- [g0v/moedict.tw](https://github.com/g0v/moedict.tw) README 沒有公開 API 契約。它說 Worker 提供 `/api/search-index/*.json`，但沒有格式說明。
- 查詞網址：`https://www.moedict.tw/uni/{詞}`，回傳 JSON，含 `title`、`heteronyms`（`bopomofo`、`pinyin`、`definitions`）。
- `www.moedict.tw` 有開 CORS。
- 沒有公開的使用條款、速率限制、服務保證。
- 只涵蓋中→中。`/a/` 端點附少量英、法、德翻譯，不是英→中字典。

### 授權

- 專案程式碼：CC0 1.0。
- 字典資料：README 明說「不應視為 CC0」。教育部《重編國語辭典修訂本》為 CC BY-ND 3.0 TW。
  - 要標示來源。
  - 不可改動詞條（ND）。
  - 其他上游來源 README 沒說明，待查證。

### 對設計的影響

1. 萌典結果**原文顯示**。不做簡繁轉換、不刪減釋義。
2. 結果頁固定顯示來源標示，例如「資料來源：教育部《重編國語辭典修訂本》（CC BY-ND 3.0 TW），經由萌典提供」。
3. 因為沒有服務保證，要有逾時（建議 5 秒）與失敗訊息，不能卡住閱讀畫面。
4. 萌典是志工營運。查詢量大時可能被限流。要有快取與合理的重試上限。
5. 回傳格式沒有契約。解析要寬鬆：缺欄位不當掉，整體格式不認得時顯示「無法解析」並可回報。
6. `usesCleartextTraffic="true"` 存在，程式碼必須拒絕非 `https`。

## 7. 隱私規則

- 線上查詞**預設關閉**。
- 第一次開啟前，顯示同意對話框，說明：
  - 會送出什麼：**只有選取的那個詞**。
  - 送去哪裡：`www.moedict.tw`。
  - 不會送出：書名、前後文、位置、裝置識別。
- 同意狀態可隨時在設定關閉。
- `LookupRequest` 型別只有一個詞，**沒有前後文欄位**。從型別上就不可能送出前後文。
- 網路請求只含詞與必要標頭。不帶 cookie、不帶自訂識別。
- 更新 `site/privacy.html` 與 Google Play 資料安全表單。

## 8. 效能與裝置考量（目標值，待實測）

下列數字是設計目標，**不是已量測的結果**。

| 項目 | 目標 |
|---|---|
| 本機精確查詢 | p95 小於 300 ms |
| 開啟查詢面板到顯示結果（本機） | 小於 500 ms |
| 記憶體增量（開啟一本 100 MB MDX） | 小於 50 MB（待實測，不通過就改策略） |
| 匯入 10 萬筆 JSON/CSV | 有進度顯示，可取消，不凍結 UI |

E-Ink 裝置：

- 查詢面板不使用動畫。
- 沿用 `isEinkMode` 邊框語彙，不用陰影。
- 避免連續重繪。結果一次顯示，不逐筆刷新。
- 匯入在背景 Isolate 執行。注意 `CLAUDE.md` 記載的限制：`Isolate.run()` 的 closure 必須是頂層函式，參數只含可跨 Isolate 傳遞的型別。

## 9. 待查證清單

- [ ] `mdict_flutter` 與 `dict_reader` 的真實字典測試。
- [ ] mdict-cpp 的授權，以及 `mdict_flutter` 是否含衍生程式碼。
- [ ] ECDICT 的授權原文。（CC-CEDICT 已由檔頭確認 CC BY-SA 4.0，但授權全文仍需放進授權頁。）
- [x] LZO 驗收檔：不取得。Phase 1 不支援 LZO，只驗證錯誤路徑。
- [ ] FreeDict 是否有英→繁中。
- [ ] 簡轉繁後再散布或顯示，是否構成改作（ECDICT 轉繁中時）。
- [ ] 萌典資料其他上游來源的授權。
- [ ] StarDict 格式文件（Phase 2 前）。
