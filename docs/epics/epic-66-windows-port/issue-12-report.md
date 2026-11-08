# Epic-66 Issue 12：Android 實機 Foliate-js vs Readium Metadata 比對報告

- 執行時間：2026-11-09
- 分支：`feat/epic-66-issue-12-foliate-metadata`
- 測試工單：Epic-66 Issue 12 Task 5

## 測試環境

- **實機型號**：WAVE（`ro.product.model: WAVE`）
- **裝置序號**：`TCE70P24B2202374`
- **Android 版本**：Android 12（`ro.build.version.release: 12`）
- **System WebView 版本**：`com.android.webview` 91.0.4472.114
- **測試方式**：整合測試 `integration_test/library_metadata_comparison_test.dart`（`--no-uninstall`，唯讀保護）
- **資料庫保護**：測試前後 `library.db` 檔案大小（180,224 bytes）與修改時間（2026-11-08 06:03）完全一致，無任何寫入。

## 書目比對清單（共 7 本）

| # | 書名 | 檔案 | Readium (ms) | Foliate (ms) | 差異欄位 | 結果 |
|---|------|------|--------------|--------------|----------|------|
| 1 | elinkBook Sample EPUB (Horizontal) | `sample_horizontal.epub` | 503 | 2366 | 無（`[]`） | 一致 |
| 2 | 長篇繁體中文直排測試書 | `sample_long_chinese_vertical.epub` | 167 | 1178 | 無（`[]`） | 一致 |
| 3 | elinkBook 多章節目錄範例 EPUB | `sample_multi_chapter.epub` | 238 | 1090 | 無（`[]`） | 一致 |
| 4 | elinkBook 範例 EPUB（定樣式多頁） | `sample_fxl_multi_page.epub` | 185 | 1240 | 無（`[]`） | 一致 |
| 5 | 縮排探針書（書本全域 p 縮排） | `probe_global_indent.epub` | 148 | 1124 | 無（`[]`） | 一致 |
| 6 | 早安，我心中的怪物：一個心理師與五顆破碎心靈的相互啟蒙... | `早安，我心中的怪物...epub` | 1789 | 1779 | 無（`[]`） | 一致 |
| 7 | 論語聖訓(三) | `論語聖訓(三).epub` | 1446 | 1779 | 無（`[]`） | 一致 |

## 比對統計摘要

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

- **比對成功率**：100%（7/7 本完全相符）
- **關鍵欄位比對**：`title`, `author`, `identifier`, `isFixedLayout`, `coverBytes`（封面位元組 SHA-256）無任何差異。
- **解析效能評估**：
  - Readium 中位數耗時約 238 ms，總耗時 4.48 秒。
  - Foliate-js（HeadlessInAppWebView 探針）中位數耗時約 1240 ms，總耗時 10.56 秒。
  - 由於 EPUB 詮釋資料抽取主要在匯入書本時非同步背景執行，1.2 秒的中位數抽取耗時完全在可接受的使用者體驗範圍內。

## 探針架構與 ES 兼容性驗證

1. **InAppWebView 探針加載架構**：
   - 探針主 HTML 透過 `InAppWebViewInitialData` 注入，`baseUrl` 設為 `https://appassets.androidplatform.net/assets/foliate/`。
   - 靜態 ES 模組由 `shouldInterceptRequest` 攔截 `/assets/foliate/*` 路徑，經 `foliate_native_bridge.dart` 的 `loadAndroidAsset()` 讀取 APK assets，並以純 `text/javascript` MIME type 回傳，完美規避 Chromium 91 對 ES 模組的嚴格 MIME 檢查。
   - 書檔位元組透過 `/book/current.epub?start=...&end=...` 經 `interceptBookRange` 與 `readBookRange`（ByteRange.kt）提供隨機讀取，無須將整本 EPUB 載入記憶體。
2. **ES Polyfill 驗證**：
   - Android 12 WebView 91 成功執行 `metadata-probe.js` 與 `readest/foliate-js`，無語法或 API 相容性錯誤。
