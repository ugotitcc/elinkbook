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
| CC-CEDICT | 中→英 | CC BY-SA 4.0 | 簡體與繁體並列，可作中→英測試資料 |
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
- [ ] ECDICT、CC-CEDICT 的授權原文。
- [ ] FreeDict 是否有英→繁中。
- [ ] 簡轉繁後再散布或顯示，是否構成改作（ECDICT 轉繁中時）。
- [ ] 萌典資料其他上游來源的授權。
- [ ] StarDict 格式文件（Phase 2 前）。
