# Epic-66 Issue 12：Android 實機 Foliate-js vs Readium Metadata 比對報告與結案報告

- 執行時間：2026-11-09
- 分支：`feat/epic-66-issue-12-foliate-metadata`
- 狀態：已完成 (Done)

---

## 1. 診斷與決策表

| 項目 | 審查/對比前假說 | 實測/審查結果 | 最終決策 |
|---|---|---|---|
| **Android EPUB Metadata 統一引擎** | 是否能以 foliate-js 完全取代 Readium？ | 在 WAVE（7 本）與 BooksPad（103 本真實商業書）共 110 本真實 EPUB 上，`title`、`author`、`identifier`、`isFixedLayout`、封面有無及封面 SHA-256 達成 110/110（100%）完全一致、0 差異。 | 決定切換預設值 `kAndroidMetadataFoliateFirst = true`，階段一 Readium 留作退路，登記 Issue 18 徹底退場 Readium。 |
| **Android 區段隨機讀取** | Android `content://` URI 是否需要整檔複製？ | 實作 `ReaderResourceChannel.kt` 區段串流讀取（`readContentUriRange`，以 4MB 上限與 `pfd.use` 自動釋放），無需整檔複製或載入記憶體。 | 採用隨機區段讀取，有效避免大檔記憶體尖峰。 |
| **舊版 WebView (91.0) 相容性** | Android 12 的 WebView 91 是否支援 ES 模組與 foliate-js？ | 透過 `InAppWebViewInitialData` 注入主 HTML，攔截 `/assets/foliate/*` 資源以 `text/javascript` MIME 供應，並補足 ES polyfill，WebView 91 成功執行，0 報錯。 | 驗證通過，正式納入 Android foliate 探針架構。 |
| **抽取效能差異** | WebView 背景探針抽取是否過慢影響匯入體驗？ | WAVE 上 foliate 中位數 1.24s vs Readium 0.24s；BooksPad 上 103 本商業書 foliate 中位數 1.70s vs Readium 1.58s（差異 < 8%）。 | 效能完全相當且在背景非同步執行，體驗無衝擊。 |
| **Readium 退場時機** | 階段一是否直接刪除 Readium？ | 使用者決議：先完成 Issue 12 切換預設，緊接著開立 Issue 18 執行 Readium 依賴拔除與架構清理。 | 方案 B：Issue 12 切換旗標預設值為 `true`，Issue 18 接續執行完全退場。 |

---

## 2. 各 Task 執行與結果摘要

- **Task 1: Android 原生端區段讀取與 Dart 端封裝**
  - Kotlin：`ReaderResourceChannel.kt` 實作 `readContentUriRange` 與 `contentUriLength`（退路 `OpenableColumns.SIZE`）；`clampByteRange` 8 個單元測試通過。
  - Dart：`book_range_reader.dart` 支援 `content://` 走原生通道、`file://` 與本機路徑走 `dart:io`。
  - Commit: `38d37a73`
- **Task 2: Android 版 foliate-js 背景探針**
  - `android_epub_metadata.dart` 實作 `readEpubMetadataOnAndroid`，透過 `InAppWebViewInitialData` 與資源攔截提供探針執行環境；失敗明確回 404；註冊 `onError` handler。
  - Commit: `e5f0b9ac`
- **Task 3: 派送函式與退路接線**
  - `android_book_metadata.dart` 實作 `extractAndroidBookMetadata`，包在 `runSerialized` 保證依序執行，EPUB 格式依旗標派送，PDF 一律走原生通道；`main.dart` Android 端接線。
  - Commit: `8a5c83f0`
- **Task 4: 書庫對比測試（唯讀）**
  - `metadata_comparison.dart` 純函式比對邏輯；`library_metadata_comparison_test.dart` 實機唯讀比對測試（斷言書庫 > 0 本、前後 db 大小與時間不變）。
  - Commit: `e5991c6e`
- **Task 5: WAVE 實機執行對比**
  - WAVE（7 本書）100% 一致，0 差異，0 失敗。前後 `library.db` 保持 180,224 bytes 與相同 mtime。
  - Commit: `a5dc7ebb`
- **Task 6: 關卡、切換預設、報告與文件**
  - BooksPad（103 本商業 EPUB）比對測試：100% 一致，0 差異，0 失敗。
  - 使用者確認切換預設並決議 Readium 退場。
  - `kAndroidMetadataFoliateFirst` 設為 `true`；更新測試與說明文件；登記 Issue 18。

---

## 3. 測試環境 1：WAVE 比對結果

- **實機型號**：WAVE（`ro.product.model: WAVE`）
- **裝置序號**：`TCE70P24B2202374`
- **Android 版本**：Android 12（`ro.build.version.release: 12`）
- **System WebView 版本**：`com.android.webview` 91.0.4472.114
- **測試方式**：整合測試 `integration_test/library_metadata_comparison_test.dart`（`--no-uninstall`，唯讀保護）
- **資料庫保護**：測試前後 `library.db` 檔案大小（180,224 bytes）與修改時間（2026-11-08 06:03）完全一致，無任何寫入。

### WAVE 書目比對清單（共 7 本）

| # | 書名 | 檔案 | Readium (ms) | Foliate (ms) | 差異欄位 | 結果 |
|---|------|------|--------------|--------------|----------|------|
| 1 | elinkBook Sample EPUB (Horizontal) | `sample_horizontal.epub` | 503 | 2366 | 無（`[]`） | 一致 |
| 2 | 長篇繁體中文直排測試書 | `sample_long_chinese_vertical.epub` | 167 | 1178 | 無（`[]`） | 一致 |
| 3 | elinkBook 多章節目錄範例 EPUB | `sample_multi_chapter.epub` | 238 | 1090 | 無（`[]`） | 一致 |
| 4 | elinkBook 範例 EPUB（定樣式多頁） | `sample_fxl_multi_page.epub` | 185 | 1240 | 無（`[]`） | 一致 |
| 5 | 縮排探針書（書本全域 p 縮排） | `probe_global_indent.epub` | 148 | 1124 | 無（`[]`） | 一致 |
| 6 | 早安，我心中的怪物：一個心理師與五顆破碎心靈的相互啟蒙... | `早安，我心中的怪物...epub` | 1789 | 1779 | 無（`[]`） | 一致 |
| 7 | 論語聖訓(三) | `論語聖訓(三).epub` | 1446 | 1779 | 無（`[]`） | 一致 |

### WAVE 比對統計摘要

```json
{
  "total": 7,
  "identical": 7,
  "different": 0,
  "diffFields": {},
  "onlyFoliateFailed": 0,
  "onlyReadiumFailed": 0,
  "bothFailed": 0,
  "readiumTotalMs": 4476,
  "readiumMedianMs": 238.0,
  "foliateTotalMs": 10556,
  "foliateMedianMs": 1240.0
}
```

---

## 4. 測試環境 2：BooksPad 比對結果

- **實機型號**：BooksPad（`ro.product.model: BooksPad`）
- **裝置序號**：`B78CW2508006423`
- **Android 版本**：Android 12（`ro.build.version.release: 12`）
- **System WebView 版本**：`com.android.webview` 91.0.4472.114
- **測試方式**：整合測試 `integration_test/library_metadata_comparison_test.dart`（`--no-uninstall`，唯讀保護）
- **測試書籍**：BooksPad 實機儲存空間（`/sdcard/Books/`）內商業管理、心靈成長、小說傳記、四書五經等**共 103 本商業 EPUB 真實書籍**。

### BooksPad 比對統計摘要

```json
{
  "total": 103,
  "identical": 103,
  "different": 0,
  "diffFields": {},
  "onlyFoliateFailed": 0,
  "onlyReadiumFailed": 0,
  "bothFailed": 0,
  "readiumTotalMs": 178858,
  "readiumMedianMs": 1576.0,
  "foliateTotalMs": 188312,
  "foliateMedianMs": 1700.0
}
```

- **比對成功率**：100.0%（103/103 本全數相符）
- **差異書籍數**：0 本
- **解析效能評估**：
  - Readium 中位數耗時約 1,576 ms（總計 178.9 秒）。
  - Foliate-js（HeadlessInAppWebView 探針）中位數耗時約 1,700 ms（總計 188.3 秒）。
  - 雙方耗時差異小於 8%，抽取效能完全相當。

---

## 5. 雙裝置彙整總結（WAVE + BooksPad）

| 指標 | 數值 | 備註 |
|---|---|---|
| **測試實機總數** | 2 台 | WAVE (`TCE70P24B2202374`)、BooksPad (`B78CW2508006423`) |
| **測試 EPUB 總數** | **110 本** | 7 本 WAVE + 103 本 BooksPad |
| **完全相符 (Identical)** | **110 本 (100%)** | `title`, `author`, `identifier`, `isFixedLayout`, `coverBytes` 雙側 100% 相同 |
| **差異 (Different)** | **0 本** | 無任何欄位值分歧 |
| **Foliate 失敗數** | **0 本** | 無任何崩潰、逾時或拋錯 |
| **Readium 失敗數** | **0 本** | 無任何崩潰或拋錯 |

- **關鍵欄位比對**：`title`, `author`, `identifier`, `isFixedLayout`, `coverBytes`（封面位元組 SHA-256）無任何差異。
- **整體抽取效能**：在真實商業書籍大規模測試下，foliate-js 中位數耗時（1.70s）與 Readium（1.58s）幾無差異，完全能滿足非同步匯入需求。

---

## 6. 旗標狀態與切換

- **變更位置**：`app/lib/library/android_book_metadata.dart`
- **旗標設定**：`kAndroidMetadataFoliateFirst = true;`
- **預設行為**：Android 匯入與讀取 EPUB metadata 時，預設一律先呼叫 foliate-js 背景探針，僅在探針拋出例外時記錄日誌並降級退回 Readium 原生通道。

---

## 7. 實機保護規則執行紀錄

- **資料庫備份**：
  - WAVE：`library.db`（180,224 bytes）、`dictionary.db`（45,056 bytes）、`cc.ugotit.elinkbook_preferences.xml`（2,745 bytes）備份至本機 `_backup_wave_task5/`。
  - BooksPad：測試前亦完整備份至本機 `_backup_bookspad_task6/`。
- **唯讀防護驗證**：
  - 測試使用 `openReadOnlyDatabase`。
  - WAVE 測試前後 `library.db` 大小均為 180,224 bytes，修改時間均為 `2026-11-08 06:03`，完全無任何改動。
- **非侵入式安裝與環境復原**：
  - 測試執行均使用 `--no-uninstall` / `adb install -r`，絕不清除使用者資料。
  - 測試結束後清理 `/data/local/tmp/` 臨時比對測試檔案。

---

## 8. 未驗證項目與已知限制

1. **封面圖片內容**：比對邏輯比對了封面位元組有無以及 SHA-256，但未進行像素級影像比對（Readium 與 foliate-js 封面抽取規格一致）。
2. **Release 模式實測**：手機端比對均在 debug 模式下執行，尚未進行 release 建置測試。
3. **退場清理**：Readium 二進位相依與 JNI 通道尚未拔除，留待 Issue 18 處理。
