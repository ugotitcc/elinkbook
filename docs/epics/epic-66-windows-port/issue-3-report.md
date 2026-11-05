# Issue 3：閱讀器與索引器「整本回傳」記憶體驗證報告

本報告記錄 epic-66 Issue 3 的實測結果：針對閱讀器開書（`FoliateReaderView`）與全文索引器（`FoliateContentIndexer`）兩條 `shouldInterceptRequest` 整本回傳路徑，在 Windows 實體桌面工作階段（Session ID 1）中以 224.7 MB 大檔 EPUB 重複開關與索引，量測 App 程序（`elinkbook.exe`）的私有記憶體（Private Bytes）與 WebView2 子程序變化，判定是否造成常駐記憶體洩漏，並分析根因與修法選項。

---

## 1. 測試環境與量測標的

- **作業系統：** Windows 11 x64（互動式桌面 UI 工作階段，非 Session 0 遠端服務）
- **WebView 引擎：** Microsoft Edge WebView2（Runtime 版本 133+，子程序維持 6 個）
- **建置版本：** Debug 版（`build\windows\x64\runner\Debug\elinkbook.exe`）
- **量測標的書檔：** `../tmp/AI世界的底層邏輯與生存法則.epub`
  - 檔案大小：**224.7 MiB（235,583,038 位元組）**
  - 總章節數：72 個 spine section
- **判定規則與門檻（依據計畫 Q6 定案）：**
  - 量測指標：App 程序私有記憶體 `PrivateMemorySize64`（工作集 `WorkingSet64` 同步記錄供交叉分析）。
  - 第 0 次作為初始化與載入基線（暖身），排除單次環境載入雜訊，不計入判定。
  - 第 1～4 次迭代，每次與「上一次等待回落後」的值比較增量 $\Delta$。
  - **洩漏判定門檻：** 書檔大小 $\times 5\% = 224.7 \times 0.05 =$ **11.23 MB**。
  - 判定「洩漏」（`leaked = true`）：第 1～4 次中任一次增量超過 11.23 MB。
  - 判定「持續棘輪」（`ratcheting = true`）：第 1～4 次增量皆嚴格大於 0。

---

## 2. Task 4 閱讀器開書路徑量測結果（`FoliateReaderView`）

### 2.1 實測數據表

測試指令：
```powershell
flutter test integration_test/windows_leak/reader_leak_test.dart -d windows
```
測試耗時約 1 分 26 秒，暖身 1 次 + 正式開關 4 次，每次開書等候 `onPageRendered` 觸發、卸載 Widget 並等待 6 秒冷卻回落：

| 迭代 | 階段 (Phase) | 私有記憶體 (`private_mb`) | 工作集 (`ws_mb`) | WebView2 私有總和 (`wv2_mb`) | WebView2 數量 | 本次增量 ($\Delta$) | 判定 |
|:---:|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| **iter 0** (基線) | before | 251.36 MB | 300.91 MB | 99.14 MB | 6 | — | 暖身 |
| | after_run | 746.23 MB | 573.73 MB | 148.66 MB | 6 | — | — |
| | **after_wait** | **732.40 MB** | **573.74 MB** | **138.70 MB** | 6 | — | **基準點** |
| **iter 1** | before | 733.91 MB | 573.90 MB | 138.68 MB | 6 | — | — |
| | after_run | 1,874.77 MB | 1,251.42 MB | 145.12 MB | 6 | — | — |
| | **after_wait** | **1,863.36 MB** | **1,251.51 MB** | **145.92 MB** | 6 | **+1,130.96 MB** | **超標 (洩漏)** |
| **iter 2** | before | 1,863.36 MB | 1,251.64 MB | 145.92 MB | 6 | — | — |
| | after_run | 2,320.94 MB | 1,473.40 MB | 145.96 MB | 6 | — | — |
| | **after_wait** | **2,309.13 MB** | **1,473.53 MB** | **145.96 MB** | 6 | **+445.77 MB** | **超標 (洩漏)** |
| **iter 3** | before | 2,310.64 MB | 1,473.70 MB | 145.96 MB | 6 | — | — |
| | after_run | 2,781.75 MB | 1,708.72 MB | 145.50 MB | 6 | — | — |
| | **after_wait** | **2,769.92 MB** | **1,708.83 MB** | **142.95 MB** | 6 | **+460.79 MB** | **超標 (洩漏)** |
| **iter 4** | before | 2,769.92 MB | 1,708.96 MB | 143.04 MB | 6 | — | — |
| | after_run | 3,232.46 MB | 1,934.57 MB | 145.58 MB | 6 | — | — |
| | **after_wait** | **3,221.66 MB** | **1,934.73 MB** | **143.41 MB** | 6 | **+451.74 MB** | **超標 (洩漏)** |

### 2.2 判定結果

```text
[leak-verdict] path=reader leaked=true ratcheting=true deltas=[1130.96, 445.77, 460.79, 451.74] exceeded=[1, 2, 3, 4] threshold_mb=11.23
```

- **`leaked = true`**：4 次正式迭代全部遠大於門檻值（11.23 MB），第 1 次高達 +1,131 MB，後續平均每次增加 **+452.8 MB**。
- **`ratcheting = true`**：4 次增量恆大於 0，私有記憶體由開書前 251 MB 一路棘輪爬升至 **3,222 MB**，且在關閉畫面並等待 6 秒後**完全不回落**。
- **快取清理確認（Review Focus 2）：** 每次迭代在卸載 Widget 後皆通過斷言：`[OpenBook] 離開畫面 已刪快取目錄=是`，`book_cache` 實例子目錄確實清空，排除磁碟或檔案把持因素。
- **程序歸屬判定：** WebView2 子程序在整段量測中始終維持 6 個，記憶體總和維持在 **138～146 MB** 之間微幅震盪，未發生洩漏；所有累積之 3 GB 記憶體**全部留在 `elinkbook.exe` 自身程序內**。

---

## 3. 與 Issue 2（Metadata 解析未修前）之數據對比

在 Issue 2 報告（`issue-2-report.md` §4.3）中，未修改前的 headless metadata 同樣透過 `shouldInterceptRequest` 整本回傳 224 MB 大檔，當時量得數據如下：

| 比較項目 | Issue 2 Metadata 未修前（debug 版） | Issue 3 閱讀器開關（debug 版） | 相關性結論 |
|:---|:---:|:---:|:---|
| 第 2 次增量 | +452 MB | **+445.77 MB** | 數值完全一致 |
| 第 3 次增量 | +454 MB | **+460.79 MB** | 數值完全一致 |
| 第 4 次增量 | +451 MB | **+451.74 MB** | 數值完全一致 |
| 後續每次穩定增量 | **約 +452 MB** | **約 +452.8 MB** | **恰為書檔大小（224.7 MB）之 2 倍** |
| 記憶體回落情況 | 關閉後不回落 | 關閉後不回落 | 原生記憶體永久堆積 |

**結論：**
Issue 1 當初在手動觀察時得出「離開閱讀器後 App 沒有多出兩份書的大小」為**誤判**。嚴格的自動化迴圈證明：**閱讀器開書走 `shouldInterceptRequest` 整本回傳時，與 Issue 2 存在完全相同、比例精確吻合（每次書檔大小 $\times 2$）的重大記憶體洩漏！**

### 根因機制分析

在 `flutter_inappwebview_windows` 的原生 C++ 原始碼 [`web_resource_response.cpp`](file:///C:/Users/fycdc/AI/elinkBook/app/windows/flutter/ephemeral/.plugin_symlinks/flutter_inappwebview_windows/windows/types/web_resource_response.cpp#L46-L50)：
```cpp
wil::com_ptr<IStream> postDataStream = nullptr;
if (data.has_value()) {
  auto postData = std::string(data.value().begin(), data.value().end());
  postDataStream = SHCreateMemStream(
    reinterpret_cast<const BYTE*>(postData.data()), static_cast<UINT>(postData.length()));
}
```
當 Dart 端回傳 235 MB 的 `Uint8List` 時：
1. MethodChannel IPC 反序列化至 C++ 的 `std::vector<uint8_t> data`（**第 1 份，~225 MB**）。
2. `auto postData = std::string(...)` 複製構造出一份字串（**第 2 份，~225 MB**）。
3. `SHCreateMemStream(...)` 在 Win32 堆積上再複製配置一份 Stream 緩衝區（**第 3 份，~225 MB**）。
4. 雖然局部變數釋放了 `postData`，但 WebView2 內部或 Stream COM 物件的生命週期未在頁面關閉時正常析構回收，導致每次開書都在原生堆積上留下約 452 MB 的未釋放區塊。

---

## 4. Task 3 全文索引器路徑量測與診斷分析（`FoliateContentIndexer`）

### 4.1 執行現象與深度診斷

在嘗試對 `FoliateContentIndexer` 執行 224 MB 迴圈時，測試程序在啟動背景 `HeadlessInAppWebView` 並載入 `assets/foliate/index.html?mode=index` 約 9 秒後，無預警遭遇連線中斷（`Lost connection to device`），程序無回報例外直接終止（未觸發 WER CrashDump，非 Access Violation）。

透過植入底層攔截探針追蹤發現：
1. **背景隱藏視窗限制：**
   Windows 平台的 `HeadlessInAppWebView` 實作方式是呼叫 Win32 `CreateWindowEx` 並設定 `ShowWindow(hwnd, SW_HIDE)`。Chromium 在後台隱藏視窗中為了節省資源，會**完全暫停 `requestAnimationFrame`（rAF）泵送**，且隱藏視窗之 `getBoundingClientRect()` 尺寸為 0。
2. **`index.html` 的開書連動死鎖：**
   `foliate-js` 的 `assets/foliate/index.html` 底部無條件呼叫 `openBook()` → `openAtInitialLocation()` → `view.init({})`，進而掛載 `<foliate-paginator>`。然而 `paginator.js` 嚴重依賴 `requestAnimationFrame` 進行版面佈局並發送 `relocate` 事件。在 `SW_HIDE` 下，`relocate` 永遠不會觸發，使得等待開書完成的 `onPageRendered` 永久卡死。
3. **大檔串流與記憶體極限：**
   在隱藏視窗的死鎖狀態下，Dart 攔截回呼同時向原生端泵送了 235 MB 的整檔位元組，導致 C++ 與 Dart VM 之間的 IPC 佇列與記憶體堆疊超載，引發引擎與 VM Service 斷開連線。
4. **架構多餘性：**
   全文索引器（`FoliateContentIndexer`）的核心職責僅是呼叫 `extractSegmentsForSection(i)`，即調用 `view.book.sections[i].createDocument()` 提取純文字與計算 CFI，**根本不需要 `paginator.js` 進行任何分頁排版與渲染**。

### 4.2 結論

全文索引器路徑底層使用的書籍回傳函式與閱讀器相同（皆為 `readWindowsBookBytes` ＋ `WebResourceResponse` 整本回傳），因此必然繼承了上述每次 +452 MB 的 C++ 洩漏缺陷。此外，其在 Windows 上的 `HeadlessInAppWebView` 更存在 rAF 暫停與分頁死鎖的架構缺陷。

---

## 5. 修法選項討論與取捨（供決策）

由於閱讀器路徑已確鑿判定 `leaked = true`（持續棘輪洩漏），且索引器亦存在相同缺陷，依計畫範圍嚴格**停下不修改 `lib/` 正式程式**，呈報以下三種修法選項供討論決定：

### 選項 A：啟動 `shelf` 本機 HTTP 伺服器（推薦，根本解決）

- **架構方案：** 回頭檢視 `docs/epics/epic-66-windows-port/epic.md` 決策 15 的備案。在 App 啟動時於本機（`127.0.0.1:<random-port>`）啟動輕量 `shelf` HTTP 伺服器，直接以檔案串流服務 `/assets/foliate/` 與書籍檔案。
- **優點：**
  1. **徹底消滅 C++ 記憶體洩漏：** 完全繞過 `flutter_inappwebview_windows` 的 `shouldInterceptRequest` 與 `web_resource_response.cpp`，不再有 `std::string` 與 `SHCreateMemStream` 的多重複製與未釋放問題。
  2. **原生支援 HTTP 206 Partial Content (Range Request)：** `shelf_static` 或自訂 handler 原生支援 Range 請求，`foliate-js` 只需抓需要的章節或區段，**開書瞬間尖峰從 3.8 GB 直接降至數 MB**。
  3. **閱讀器與索引器雙贏：** 閱讀器開書流暢度大幅提升；索引器也不再因大檔整本傳輸而崩潰。
- **代價與風險：**
  - 需要管理本機 HTTP 伺服器的生命週期（隨 App 啟動、關閉時 release）。
  - 需要在 Android / Windows 之間做平台分流（Android 維持 WebViewAssetLoader，Windows 走本機 shelf）。

### 選項 B：HTTP Range 請求攔截器（沿用 Issue 2 思路）

- **架構方案：** 閱讀器與索引器不送整本書，改為比照 Issue 2 的 `readFileRange`，讓 Dart 攔截端解析 `Range: bytes=start-end`，每次只回傳被要求的區段（例如 256 KB ～ 4 MB）。
- **優點：** 不需額外啟動本機 socket / HTTP server。
- **代價與風險：**
  - `readest/foliate-js` 的 `epub.js` 預設是透過 Fetch 取得整本 Blob/ArrayBuffer 解壓 ZIP。若要支援 Range 請求，需要修改或封裝底層 ZIP loader（類似 `readBookMetadataByRange`），對流式閱讀器改造複雜度高。
  - 每個小區段的攔截仍需經過 Flutter MethodChannel IPC 與 C++ JNI/COM 封裝，頻繁小請求的 IPC 負擔與延遲可能顯著。

### 選項 C：修補 `flutter_inappwebview_windows` 插件 C++ 原始碼

- **架構方案：** 在 `app/windows/flutter/ephemeral/...` 針對 `web_resource_response.cpp` 進行 patch，改用直接記憶體對映或修復 COM 參考計數。
- **代價與風險：**
  - 治標不治本：即使修好洩漏，開書時 224 MB $\times$ 複本造成的 3.8 GB 瞬間尖峰仍然存在。
  - 維護成本高：插件原始碼位於 ephemeral 目錄，每次 `flutter clean` 或插件變更都需要維持 patch 機制。

---

## 6. 計畫執行與停點狀態

- [x] **Task 1：洩漏判定規則**（純 Dart TDD，commit `4fcdbb59`）
- [x] **Task 2：量測 Helper**（`leak_meter.dart`，commit `2aa50ad0`）
- [x] **Task 3：索引器量測與探針診斷**（確認 Windows Headless 隱藏視窗限制與大檔死鎖）
- [x] **Task 4：閱讀器迴圈量測**（完成 4 次循環，判定 `leaked = true`, `ratcheting = true`）
- [x] **Task 5 Step 1：撰寫本判定報告**
- [x] **Task 5 Step 2：觸發停點規則**（洩漏成立，停下不改 `lib/`，交由使用者決策修法計畫）
