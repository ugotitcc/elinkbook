# Issue 36 實作計畫：Foliate 資源供應與書檔供應收攏

設計決策見 `epic.md`「Issue 36 設計決策」。本計畫只列施工步驟。

## 現況（2026-11-14 讀碼確認）

- `foliate_reader_view.dart:967` `_shouldInterceptRequest`、`foliate_content_indexer.dart:~100` `interceptIndexRequest`、`android_epub_metadata.dart:~197`、`windows_epub_metadata.dart:~146` 四處各寫一份 `/assets/foliate/` → 位元組 → `WebResourceResponse`，MIME 與找不到時的行為不一致。
- 書檔供應：`foliate_reader_view.dart` 的 `_cacheBook`／`dispose`／`_tryDeleteCacheDir`／`deleteBookCacheDirOf` 與 `foliate_content_indexer.dart` 的快取＋註冊＋finally 各寫一份。
- 殘留碼：`windows_reader_resources.dart` 的 `readWindowsBookBytes`、`windowsBookContentType` 在 `lib/` 無呼叫者。

## 目標 interface

```dart
// app/lib/reader/foliate_asset_serving.dart
class FoliateAssetResponse {            // 純值，可直接測
  final int statusCode;                 // 200 或 404
  final String contentType;             // 只含 MIME，不含 charset
  final Uint8List data;
}
/// path 不在 /assets/foliate/ 底下回 null（不是它的事）；在底下但找不到回 404。
Future<FoliateAssetResponse?> serveFoliateAsset(String path,
    {Future<Uint8List?> Function(String relativePath)? loadAsset});
extension FoliateAssetResponseX on FoliateAssetResponse {
  WebResourceResponse toWebResourceResponse();  // 四處共用的薄 adapter
}

// app/lib/reader/book_serving.dart
class BookServing {
  final String cacheDir;      // 供 Android InternalStoragePathHandler
  final Uri? bookBaseUri;     // Windows loopback 才有
  static Future<BookServing?> open(String filePath, String instanceId); // 快取失敗回 null
  void dispose();             // 冪等：中止 loopback 註冊＋刪快取目錄（含鎖檔重試）
}
```

`open()` 內 `register` 失敗會先刪掉剛複製的快取再重拋；呼叫端在 `await` 後發現已離開畫面，只需 `dispose()` 一行（取代原本兩段 `mounted` 巢狀清理）。

## Task 1：Foliate 資源供應 module（TDD）

- [x] 1.1 寫 `test/reader/foliate_asset_serving_test.dart`（紅）：`.js` → `text/javascript`；`.css` → `text/css`；`.html` 與未知副檔名 → `text/html`；找不到 → 404 空 body；非 `/assets/foliate/` 路徑 → `null`；相對路徑為 `foliate/` 加上前綴之後的部分；`legacy/` 路徑照常服務。
- [x] 1.2 實作 `foliate_asset_serving.dart`（綠），預設 `loadAsset` 為 `loadAndroidAsset`（Windows 在其內部轉給 `loadWindowsFoliateAsset`）。
- [x] 1.3 驗證：`flutter test test/reader/foliate_asset_serving_test.dart`

## Task 2：四處改用 Foliate 資源供應

- [x] 2.1 `foliate_reader_view.dart`：`_shouldInterceptRequest` 先呼叫 `serveFoliateAsset`，非 null 即轉換回傳；其餘仍由 `classifyFoliateRequestPath` 處理字型與 `/book/`。移除 `FoliateRequestKind.foliateAsset`，同步更新 `test/reader/foliate_intercept_test.dart`。
- [x] 2.2 `foliate_content_indexer.dart`：`interceptIndexRequest` 改用之。
- [x] 2.3 `android_epub_metadata.dart`、`windows_epub_metadata.dart`：`/assets/foliate/` 分支改用之（兩者的 `/book/current.epub` 範圍讀取與 `/probe.html` 不動）。
- [x] 2.4 驗證：`flutter test test/reader/foliate_intercept_test.dart test/library/android_epub_metadata_test.dart test/library/windows_epub_range_test.dart`

## Task 3：書檔供應 module（TDD）

- [x] 3.1 寫 `test/reader/book_serving_test.dart`（紅）：快取失敗回 `null`；成功時 `cacheDir` 為快取檔所在目錄；`dispose()` 刪目錄；`dispose()` 兩次不拋；Windows 分支 `register` 失敗時快取目錄被刪並重拋（以可注入的 `register` 覆寫測）；Windows 成功時 `bookBaseUri` 非 null、`dispose()` 會釋放註冊。
- [x] 3.2 實作 `book_serving.dart`，把 `deleteBookCacheDirOf`、`_tryDeleteCacheDir`／`_retryDeleteCacheDir` 的鎖檔重試搬入（綠）。
- [x] 3.3 驗證：`flutter test test/reader/book_serving_test.dart`

## Task 4：閱讀器與索引器改用書檔供應

- [x] 4.1 `foliate_reader_view.dart`：`_cacheBook` 改為 `BookServing.open`＋一次 `mounted` 檢查；欄位 `_bookCacheDir`／`_serveHandle` 換成 `_serving`；`dispose()` 改為 `_serving?.dispose()`；移除 `deleteBookCacheDirOf`、`_tryDeleteCacheDir`、`_retryDeleteCacheDir`，更新引用它們的測試。
- [x] 4.2 `foliate_content_indexer.dart`：`finally` 改為先 `await headlessWebView?.dispose()`（包 try/finally）再 `serving?.dispose()`，確保 WebView 釋放失敗也會清快取。
- [x] 4.3 驗證：`flutter test test/reader/foliate_reader_view_test.dart test/reader/foliate_reader_view_keyboard_test.dart test/search`

## Task 5：刪除殘留碼

- [x] 5.1 刪除 `readWindowsBookBytes`、`windowsBookContentType` 與 `windows_reader_resources_test.dart` 中對應的測試。
- [x] 5.2 驗證：`flutter test test/reader/windows_reader_resources_test.dart`

## Task 6：收尾（整張計畫最後一個 Task）

- [x] 6.1 `flutter analyze` 乾淨。
- [x] 6.2 `node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`（見 `app/tool/README.md`；Node 取自 pnpm，見記憶 `reference_windows-node-via-pnpm`）。
- [x] 6.3 完整 `flutter test`（無參數）。
- [x] 6.4 更新 `epic.md` 開發記錄、`issues.md` Issue 36 狀態。

## 風險與未驗證項目

- MIME 統一（`.css` 改 `text/css`）在 Chrome 83 以下 WebView（iReader Ocean 4 Plus）的行為**須真機驗證**；本計畫只能以單元測試保證回應內容，不能證明真機渲染。
- Windows 探針原本 `.js` 的 `contentType` 內嵌 `; charset=utf-8`，現統一為不含 charset 的 MIME（`WebResourceResponse` 預設 `contentEncoding` 為 utf-8）；單元測試不能證明 WebView2 實際行為。
- 範圍外（見 `epic.md`）：Windows 探針 polyfill 與 `onError`；`foliate_native_bridge.dart` 其餘整理；探針改走 loopback。
