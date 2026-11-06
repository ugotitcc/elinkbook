# Epic 66 Issue 8 報告：Windows 索引器讓整個 App 消失

## 結論

Windows 上全庫全文索引跑不完的根因，是索引器沒有登錄 `onLocatorChanged` 等處理器。網頁一渲染完，JS 就呼叫這些處理器。`flutter_inappwebview_windows` 遇到 Dart 端沒登錄的處理器，會直接結束**整個 App 程序**（Android 不會）。沒有例外、沒有 stderr、沒有 Windows 崩潰紀錄（WER），Flutter 只顯示 `Lost connection to device`。

修法：索引器對 `main.js` 會呼叫、但自己不處理的 9 個處理器，全部登錄空處理器。

## 推翻的舊說法

`issue-3-report.md` §4.2 與 `issue-4-report.md` 推論：隱藏視窗讓 Chromium 暫停 `requestAnimationFrame`，導致索引器卡住。**這個推論不成立。** 階段 5 實測：隱藏的 `HeadlessInAppWebView` 載入索引頁後，`onPageRendered` 與 `onLocatorChanged` 都正常觸發，程序存活。

也不是大檔造成的。3 章的小 EPUB 就會重現。

## 診斷過程（2026-11-06，Windows 11，Flutter 3.41.9，Debug 版）

回饋迴圈：`flutter test integration_test/foliate_content_indexer_test.dart -d windows`（需設 `CL=/utf-8`，見 `epic.md` 決策 27）。固定 2 秒內 `did not complete`，每次相同，結束碼 79。

先排除「測試沒建立 WebView2 環境」：補上環境後仍紅。

二分實驗（暫時測試，已刪除）：

| 階段 | 內容 | 結果 |
|---|---|---|
| 1 | 只做 `cacheBookForServing` 與 `LocalBookServer.register` | 存活 |
| 2 | 隱藏 WebView 載入 `about:blank`（800×1280） | 存活 |
| 3 | 載入真正的索引頁，只攔截資源，不登錄處理器 | 死，最後一個請求是 `paginator.js` |
| 4 | 同階段 3，`paginator.js` 換成替身 | 死，已印出 `STUB open`，所以不是 paginator 的程式碼 |
| 5 | 載入索引頁，登錄 8 個處理器 | 存活，頁面正常渲染，`onLocatorChanged` 反覆觸發 |
| 6 | 替身 paginator 加上處理器 | 存活，JS 的 `onError` 被 Dart 收到 |
| 7 | 同階段 5，只漏掉 `onLocatorChanged` | **死** |

階段 5 與 7 只差一個處理器，直接證明因果。

## 修正

- `FoliateBridgeHandlers.all`：`main.js` 會呼叫的全部 13 個處理器名稱。
- `foliateIndexerNoopHandlerNames()`：`all` 扣掉索引器自己處理的 4 個（`onSectionCountReady`、`onSegmentsForSectionReady`、`onPageRendered`、`onError`），其餘登錄空處理器。
- `integration_test/foliate_content_indexer_test.dart` 補上 WebView2 環境初始化（原本在 Windows 不是有效測試）。

## 測試證據

- `test/reader/foliate_bridge_handlers_test.dart` 新增 2 個測試：`all` 必須等於 `main.js` 實際呼叫的名稱集合（日後新增呼叫卻沒登錄，測試會變紅）；索引器空處理器名稱的組成。修正前紅（符號未定義），修正後綠。
- Windows 整合測試 `foliate_content_indexer_test.dart`：修正前紅（App 消失），修正後 2 個測試全綠（3 章 EPUB 擷取每章句子與 CFI；`resumeFromChapter`）。
- `flutter analyze`：No issues found。

## 未驗證

- 大檔（224 MB）的索引能否跑完：沒有測。`integration_test/windows_leak/indexer_leak_test.dart` 未重跑。
- 真實 App 背景排程（`ContentIndexingScheduler`）在 Windows 的端到端行為：沒有手動驗證。
- 全套 `flutter test`：未跑；只跑了異動檔案與 `test/search`。
- 其他平台：Android 未測。修正只是多登錄空處理器，Android 行為預期不變，但沒有實機驗證。

## 為何先前沒被發現

`foliate_content_indexer_test.dart` 自 Epic 10 起存在，但沒有 Windows 環境初始化，在 Windows 上一直是壞的；Issue 3 的探針沒有保留，把「程序消失」誤判成「卡住」。
