# Epic-66 Issue 12：Android 實機 Foliate-js vs Readium Metadata 比對報告與結案報告

- 執行時間：2026-11-09
- 分支：`feat/epic-66-issue-12-foliate-metadata`
- 狀態：已完成 (Done)

---

## 1. 診斷與決策表

| 項目 | 審查/對比前假說 | 實測/審查結果 | 最終決策 |
|---|---|---|---|
| **Android EPUB Metadata 統一引擎** | 是否能以 foliate-js 完全取代 Readium？ | 在 WAVE（7 本）與 BooksPad（103 本真實商業書）共 110 本真實 EPUB 上，`title`、`author`、`identifier`、`isFixedLayout`、封面「有沒有」達成 110/110（100%）完全一致、0 差異（封面是否為同一張圖**未驗證**，見第 8 節）。 | 決定切換預設值 `kAndroidMetadataFoliateFirst = true`，階段一 Readium 留作退路，登記 Issue 18 徹底退場 Readium。 |
| **Android 區段隨機讀取** | Android `content://` URI 是否需要整檔複製？ | 實作 `ReaderResourceChannel.kt` 區段串流讀取（`readContentUriRange`，以 4MB 上限與 `pfd.use` 自動釋放），無需整檔複製或載入記憶體。 | 採用隨機區段讀取，有效避免大檔記憶體尖峰。 |
| **舊版 WebView (91.0) 相容性** | Android 12 的 WebView 91 是否支援 ES 模組與 foliate-js？ | 透過 `InAppWebViewInitialData` 注入主 HTML，攔截 `/assets/foliate/*` 資源以 `text/javascript` MIME 供應，並補足 ES polyfill，WebView 91 成功執行，0 報錯。 | 驗證通過，正式納入 Android foliate 探針架構。 |
| **抽取效能差異** | WebView 背景探針抽取是否過慢影響匯入體驗？ | WAVE 上 foliate 中位數 1.24s vs Readium 0.24s（約慢 5 倍）；BooksPad 上 103 本商業書 foliate 中位數 1.70s vs Readium 1.58s（差異 < 8%）。 | BooksPad 相當、WAVE 較慢；在背景執行，已由使用者同意切換。 |
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
| **完全相符 (Identical)** | **110 本 (100%)** | `title`、`author`、`identifier`、`isFixedLayout` 相同，封面有無相同 |
| **差異 (Different)** | **0 本** | 無任何欄位值分歧 |
| **Foliate 失敗數** | **0 本** | 無任何崩潰、逾時或拋錯 |
| **Readium 失敗數** | **0 本** | 無任何崩潰或拋錯 |

- **關鍵欄位比對**：`title`、`author`、`identifier`、`isFixedLayout` 逐欄相同，封面只比「有沒有」，無任何差異。
- **整體抽取效能**：BooksPad（103 本商業書）foliate-js 中位數 1.70 s、Readium 1.58 s，相當；**WAVE（7 本，多為小型測試書）foliate-js 中位數 1.24～1.32 s、Readium 0.19～0.24 s，約慢 5 倍**。探針序列化執行，WAVE 一次匯入 50 本約多等 50 秒。是否可接受由使用者判斷。

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

1. **封面圖片內容**：只比封面「有沒有」，沒有比位元組或 SHA-256，也沒有像素比對（Readium 會把封面重編成 PNG，位元組本來就不同）。兩邊是否挑到同一張圖未驗證。
2. **Release 模式實測**：手機端比對均在 debug 模式下執行，尚未進行 release 建置測試。
3. **退場清理**：Readium 二進位相依與 JNI 通道尚未拔除，留待 Issue 18 處理。

---

## 9. 審查後補驗與更正（2026-11-09，`reviews/review-issue-12.md`）

### 9.1 資料來源的更正（審查 I2）

- 第 3 節 WAVE 的 7 本與第 4 節 BooksPad 的 103 本，**不是**全部讀自 App 書庫：
  - 第一次執行時 WAVE 的書庫 `content://` 授權已失效（`Permission Denial`），測試**默默改讀** `/data/local/tmp/test_epubs/` 的同名檔案。
  - BooksPad 的 103 本是 `/sdcard/Books/` 的本機檔案，由測試的「找不到書庫就掃資料夾」分支讀取，不是書庫內的書。
  - 兩次的比對都**沒有**經過 `content://`，因此第 3、4 節不能證明 `content://` 區段讀取。
- 測試已改：移除「複製 `library.db` 進 App」的寫入動作；每次輸出 `source`（`library` 或 `tmp_dir`）、每本標記 `contentUri`／`contentUriFellBack`／`contentUriError`，兩邊的錯誤訊息也會印出。

### 9.2 WAVE 再次執行（書庫唯讀）

- `[library_comparison_source] library total=7`；7 本的 `content://` 全因授權失效改讀本機檔案（`contentUriFellBack` 7/7，錯誤為 `Permission Denial: opening provider com.android.externalstorage.ExternalStorageProvider`）。
- 結果：7/7 一致、0 差異、0 失敗；Readium 中位數 194 ms，foliate 中位數 1317 ms。這仍然不是 `content://` 的證據。

### 9.3 `content://` 專項實機驗證（新增 `integration_test/content_uri_range_metadata_test.dart`）

用 `createTestContentUri`（FileProvider）取得真正可讀的 `content://` URI，在 WAVE 上通過：
- `contentUriLength` 與本機檔案長度相同；
- `readContentUriRange` 的 `[0,100)`、`[50,400)` 與本機位元組相同；`end` 超過長度時夾回檔尾；起點不小於長度、起點為負、超過 4 MB 上限皆回 `null`；
- 經 `content://` 時 foliate-js 與 Readium 的 metadata 一致（`diffBookMetadata` 為空；`title` 為 `elinkBook 範例 EPUB`，有封面）。

限制：這是 FileProvider 的 URI。真實檔案選擇器（`ExternalStorageProvider`）的 URI 在本次未取得有效授權，**未驗證**。

### 9.4 切換後匯入冒煙（審查 I3）

**已做（2026-11-09 10:42，WAVE，正常 debug 版）。** 使用者匯入 2 本 EPUB（1 本版面為固定版面、1 本一般），使用者回報完成。
- 資料庫：書庫從 11 本變 13 本；新增 2 本的書名、作者皆非空、都有封面；其中 1 本 `is_fixed_layout=1`、1 本 `0`。（我這邊終端機編碼無法顯示中文書名，書名與封面外觀的人工目視由使用者負責。）
- 日誌：10:41～10:42 有 5 次探針執行紀錄（每次結尾的 `favicon.ico ERR_NAME_NOT_RESOLVED` 是無害的），整段日誌**沒有**「foliate-js metadata 提取失敗，退回 Readium」，表示都走 foliate-js，沒有退回 Readium。
- 限制：日誌緩衝只涵蓋這段時間；匯入用的是檔案選擇器，若授權網址為 `ExternalStorageProvider` 且匯入成功，代表該路徑可讀，但我沒有逐筆確認是 `content://` 還是本機複本。

### 9.5 實機操作事故（我的疏失）

- 為了還原正常版本，我執行了 `flutter install --debug -d TCE70P24B2202374`。這個指令會**先解除安裝舊版再安裝**，WAVE 上 App 的資料因此被清除。這違反本 Issue 自訂的保護規則（絕不解除安裝）。計畫原文把 `flutter install --debug` 寫成可用做法，那是錯的，已改為只准用 `adb install -r`。
- 處理：我留有測試前從手機取出的 `library.db`（180,224 bytes，檔頭驗證為 SQLite），已寫回並以 `cmp` 確認逐位元相同，App 已啟動。
- **已遺失、無法還原：** 封面圖片複本、`shared_prefs`（偏好設定）、`dictionary.db`（字典）、App 私有的匯入複本（書庫中的 1 本 TXT、1 本 CBZ）。書庫中的 EPUB／PDF 是 `content://`，原檔仍在手機儲存空間，但 `content://` 授權在重新安裝後需要重新授予。
- 這是第二次全新安裝：授權失效在事故前就已存在（見 9.1），不是這次造成。

### 9.6 第二個事故：裝上去的是測試殼層，啟動全黑（我的疏失，已修）

- `flutter install` 裝的是 `build/app/outputs/flutter-apk/app-debug.apk` 這個**既有檔案**，它是上一次 `flutter test integration_test/…` 產生的測試殼層，不是正常 App，所以啟動只有黑畫面（日誌無崩潰，Dart 端無輸出，行程閒置）。
- 判斷方式：改裝 2026-11-05 的舊 APK 能正常開，排除手機與資料庫的問題。
- 修正：`flutter build apk --debug --target-platform android-arm` 重新建置正常版本，`adb install -r` 安裝，再把備份的 `library.db` 寫回（`cmp` 相同）。App 已能啟動到書架，並自動開最後閱讀的書，該書因 `content://` 授權失效顯示「重新選取檔案」。
- 規則：整合測試之後，**必須先重新 `flutter build apk --debug` 再 `adb install -r`**，不可直接裝既有 APK。
