# Issue 3：閱讀器與索引器「整本回傳」記憶體驗證報告

本報告記錄 epic-66 Issue 3 的實測結果：針對閱讀器開書（`FoliateReaderView`）與全文索引器（`FoliateContentIndexer`）兩條 `shouldInterceptRequest` 整本回傳路徑，在 Windows 實體桌面工作階段（Session ID 1）中以 224.7 MB 大檔 EPUB 重複開關與索引，量測 App 程序（`elinkbook.exe`）的私有記憶體（Private Bytes）與 WebView2 子程序變化，判定是否造成常駐記憶體洩漏，並分析可能成因與修法選項。

**結論先看（已量測 vs. 推論）：**

| 項目 | 狀態 |
|:---|:---|
| 閱讀器路徑：4 次正式開關私有記憶體逐次棘輪上升、關閉後不回落、WebView2 子程序穩定 | **已量測**（debug 版、單本書、單一程序，見 §2） |
| 閱讀器路徑：iter2～4 每次約 +452 MB，與 Issue 2 未修前 metadata 路徑數量級相近 | **已量測**（相近，非完全一致，見 §3） |
| 閱讀器路徑：Release 版同樣逐次累加（每次約 +452 MB） | **已量測**（見 §7.1，推翻「只有 debug 版」的疑慮） |
| 洩漏與 Dart 端保留無關（每次回傳同一個 `Uint8List` 仍逐次累加） | **已量測**（見 §7.1） |
| 每次開書只有 1 次整本攔截（5 輪皆 1 次、235,583,038 位元組） | **已量測**（見 §7.1） |
| 首次幾輪的額外增量（debug 測試 iter1 +1,131 MB；release 首次開書 +1,370 MB） | **已量測但原因未查明**（見 §3.2、§7.1） |
| 根因是 C++ 多重複製且未釋放 | **假設，未驗證**（見 §3.4） |
| 索引器路徑會洩漏 | **未量測**；索引器無法跑完任何一輪（見 §4） |

---

## 1. 測試環境與量測標的

- **作業系統：** Windows 11 x64（互動式桌面 UI 工作階段，非 Session 0 遠端服務）
- **WebView 引擎：** Microsoft Edge WebView2（Runtime 版本 133+，子程序維持 6 個）
- **建置版本：** Debug 版（`build\windows\x64\runner\Debug\elinkbook.exe`）；表 §2.1 為 debug 版，Release 版另見 §7.1
- **量測標的書檔：** `../tmp/AI世界的底層邏輯與生存法則.epub`（可用環境變數 `ELINK_LEAK_EPUB` 覆寫路徑）
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

- **`leaked = true`**：4 次正式迭代增量全部遠大於門檻值（11.23 MB）。
- **`ratcheting = true`**：4 次增量恆大於 0，私有記憶體由開書前 251 MB 一路爬升至 **3,222 MB**，且在卸載畫面並等待 6 秒後**不回落**。
- **快取清理確認（Review Focus 2）：** 測試於卸載 Widget 後斷言 `book_cache` 實例子目錄為空（目錄不存在視為已清理），並印出 `[leak] book_cache 目錄存在=… 剩餘項目=…` 以區分實際走了哪個分支，排除磁碟或檔案把持因素。**註：** 原始量測（§2.1）當時的測試版本在目錄不存在時會略過斷言、且未保留輸出；改良後的版本已在 §7.1 的三次 debug 實驗中重跑，輸出為 `本輪新增殘留=0`。
- **程序歸屬：** WebView2 子程序在整段量測中始終維持 6 個，記憶體總和維持在 **138～146 MB** 之間微幅震盪；增加的記憶體在 `elinkbook.exe` 自身程序（私有記憶體）內。注意 `elinkbook.exe` 內同時包含 Dart VM 堆積與原生堆積，**「在 App 程序內」不等於「在原生端」**（見 §3.3）。

---

## 3. 與 Issue 2（Metadata 解析未修前）之數據對比

### 3.1 數量級相近的部分

在 Issue 2 報告（`issue-2-report.md` §4.3）中，未修改前的 headless metadata 同樣透過 `shouldInterceptRequest` 整本回傳 224 MB 大檔，同一程序、debug 版、每次後等 6 秒，量得 359 → 816 → 1,268 → 1,722 → 2,173 MB（每次約 +452 MB）。

| 比較項目 | Issue 2 Metadata 未修前（debug 版） | Issue 3 閱讀器開關（debug 版） | 說明 |
|:---|:---:|:---:|:---|
| iter 1 增量 | 約 +457 MB（359→816） | **+1,130.96 MB** | **不相近，見 §3.2** |
| iter 2 增量 | 約 +452 MB | +445.77 MB | 相近（差約 6 MB） |
| iter 3 增量 | 約 +454 MB | +460.79 MB | 相近（差約 7 MB） |
| iter 4 增量 | 約 +451 MB | +451.74 MB | 相近（差約 1 MB） |
| iter 2～4 平均 | 約 +452 MB | 約 +452.8 MB | 約為書檔大小（224.7 MB）的 2.0 倍 |
| 關閉後是否回落 | 不回落 | 不回落 | 一致 |

**這裡能說的：** 閱讀器開書路徑在 iter2～4 呈現與 Issue 2 未修前 metadata 路徑**數量級相同、約為書檔 2 倍**的逐次累加。**不能說的：** 兩者「完全一致」、「精確吻合」或必然同一成因——兩條路徑的程式碼、請求次數與量測 harness 都不同，本 Issue 沒有做任何能證明同源的實驗。

Issue 1 當初手動觀察得出「離開閱讀器後 App 沒有多出兩份書的大小」；本 Issue 的自動化迴圈與其不符，Issue 1 的觀察應視為被推翻（手動觀察無法分辨逐次累加）。

### 3.2 首次幾輪的額外增量：原因未查明

測試（debug）的 iter1 增量是書檔大小的約 **5.0 倍**（1,130.96 / 224.7），遠大於 iter2～4 的約 2 倍；工作集 iter1 增量為 +677.8 MB（573.74→1,251.51），也大於其後的約 +222 MB。iter0（暖身）從 before 到 after_wait 是 +481 MB。

**後續排除實驗的發現（§7.1）：**

- **不是額外請求：** 每次開書只有 **1 次**整本攔截（5 輪皆 1 次、235,583,038 位元組）。
- **可重現、不是雜訊：** 再跑兩次 debug 測試，iter1 分別為 +1,128.4 與 +1,131.5 MB。
- **與 harness 有關：** 以獨立的 Release 版 App 迴圈量測時，首次開書（iter0）就多了約 +1,370 MB（84.5→1,454.2），之後 iter1～4 都穩定在約 +452 MB，**沒有**出現 iter1 的 +1,131 MB。可見「額外增量」在 debug 測試落在 iter1，在 Release 版則落在首次開書。

**目前能說的：** 前兩輪合計比穩態多出約 700～900 MB 的一次性成本，確定存在、可重現，但**成因未查明**（候選：WebView2／Chromium 首次配置的一次性成本、配置器擴張，皆未驗證）。這不影響「穩態每次約 +452 MB 逐次累加」的結論。

### 3.3 Dart 端保留：已在本路徑排除

本 Issue 重做了 Issue 2 的排除實驗（§7.1）：閱讀器攔截每次都回傳**同一個** `Uint8List`，5 輪仍每次逐次累加約 +452 MB（iter1 +1,131、其後 +450.0、+453.2、+454.0）。因此洩漏**不是 Dart 端每次新配置的位元組陣列被保留**。

另觀察：每次迭代私有記憶體增量（約 +452 MB）約為工作集增量（約 +222～228 MB）的 2 倍，表示約一半是已提交但未使用（未常駐）的堆積。這與「物件仍被參考」或「配置器保留未歸還」兩種解釋都相容，本報告無法區分。每次累加且 6 秒內不回落，**符合洩漏特徵**，但 6 秒等待與未主動觸發 Dart GC 仍不足以排除配置器延遲歸還（§7.2 待補實驗 3）。

### 3.4 根因機制：僅為程式碼審視下的假設

外掛 `flutter_inappwebview_windows` 0.6.0 的 C++ 原始碼 [`web_resource_response.cpp`](../../../app/windows/flutter/ephemeral/.plugin_symlinks/flutter_inappwebview_windows/windows/types/web_resource_response.cpp)（行 46～50；該路徑位於 ephemeral 目錄，需先 `flutter pub get` 才存在）：
```cpp
wil::com_ptr<IStream> postDataStream = nullptr;
if (data.has_value()) {
  auto postData = std::string(data.value().begin(), data.value().end());
  postDataStream = SHCreateMemStream(
    reinterpret_cast<const BYTE*>(postData.data()), static_cast<UINT>(postData.length()));
}
```
從程式碼可以**確認**的是：一次回傳 N 位元組，會在原生端同時存在 `std::vector`、`std::string` 與 `SHCreateMemStream` 的緩衝區（理論上 2～3 份副本的瞬間尖峰）。

**無法確認**的是：為何實測每次**持續**留下約 2 倍而非 3 倍、持續留存的是哪些副本、為何 `postData` 釋放後仍不回落。「WebView2 內部或 Stream COM 物件未在頁面關閉時析構」只是推測，沒有任何實驗支持。

Issue 2 §4.3 已實驗：補上外掛少的 `Release()` 後數字**完全不變**，並明確寫「更細的根因沒有查明」。本 Issue 沒有新實驗推翻或補強這點，因此**根因維持未查明**，且此處的 C++ 機制描述**不應作為選擇修法的依據**，只能作為方向線索。

---

## 4. Task 3 全文索引器路徑：未取得量測數據

### 4.1 執行現象

在嘗試對 `FoliateContentIndexer` 執行 224 MB 迴圈時，測試程序在啟動背景 `HeadlessInAppWebView` 並載入 `assets/foliate/index.html?mode=index` 約 9 秒後，無預警遭遇連線中斷（`Lost connection to device`），程序無回報例外直接終止（未觸發 WER CrashDump，非 Access Violation）。**索引器沒有完成任何一輪，因此沒有任何 `[leak]` 數據，也沒有 `[leak-verdict]`。**

> **更正（2026-11-06，Issue 8）：** 下列「rAF 暫停」推論不成立。實測根因是索引器沒登錄 JS 會呼叫的處理器，Windows 外掛因此結束整個 App 程序；隱藏視窗的 rAF 正常。見 `issue-8-report.md`。

### 4.2 診斷（僅為推論）

以下為除錯時以臨時探針得到的**推論**；該探針程式**未進版控**，輸出未保存，無法重現，應視為待驗證的線索，而非結論：

1. **背景隱藏視窗：** Windows 的 `HeadlessInAppWebView` 推測以 `CreateWindowEx` + `ShowWindow(SW_HIDE)` 建立視窗（**未查證外掛視窗建立程式碼**）；Chromium 在隱藏視窗可能暫停 `requestAnimationFrame` 並使 `getBoundingClientRect()` 為 0。
2. **`index.html` 開書連動：** `assets/foliate/index.html` 底部無條件呼叫 `openBook()`，進而掛載依賴 rAF 的 `<foliate-paginator>`；若 rAF 暫停，`relocate` 不會觸發，等待 `onPageRendered` 會卡住。
3. **大檔傳輸與斷線的關聯：** 推測隱藏視窗卡住時整本位元組仍被泵送，造成斷線。**此項證據偏弱**：同一個程序在閱讀器路徑可連續傳輸 4 次（每次 235 MB）而不斷線，所以「235 MB 傳輸本身導致斷線」並不成立，斷線成因其實**不明**。
4. **架構觀察：** 索引器核心只需呼叫 `extractSegmentsForSection(i)` 提取純文字與 CFI，理論上不需要 `paginator.js` 版面排版；這是設計層面的觀察，不是量測結果。

### 4.3 結論

索引器與閱讀器共用同一個回傳函式（`readWindowsBookBytes` + `WebResourceResponse` 整本回傳），**因此預期會有相同的逐次累加風險**，但這是由共用程式碼推得的**預期**，**不是量測結果**。索引器在 Windows 上目前**根本無法跑完**（原因不明，rAF 暫停是其中一個待驗證假設），這是獨立於洩漏的另一個問題，需另行追查。

---

## 5. 修法選項討論與取捨（供決策）

閱讀器路徑已判定 `leaked = true`（持續棘輪），依計畫範圍嚴格**停下不修改 `lib/` 正式程式**，呈報以下選項供討論。需要先說明的背景：

- `epic.md` 決策 6／15（2026-11-03）曾判斷 `shelf` 伺服器**不需要**，並接受「224 MB 書開書瞬間 App 與 WebView2 合計尖峰約 3.8 GB（release 版，持續約 3 秒後回落）」為已知代價，改善留給後續 Issue（出處：`spike-report.md` 結論 1，release 版僅量一次）。**本 Issue 帶來的新事實是：不只是瞬間尖峰，而是逐次累加不回落的洩漏（debug 版）**，這是重新檢討決策 6／15 的理由。
- 以下各項的好處是**預期**，除選項 B 的 metadata 部分外**皆未經本專案實測**。

### 選項 B：HTTP Range 請求攔截（Issue 2 已驗證有效的路線，建議優先評估）

- **架構方案：** 比照 Issue 2 的 `readFileRange`，Dart 攔截端解析 `Range: bytes=start-end`，只回傳被要求的區段；閱讀器改用類 Blob 的 ZIP loader（Issue 2 的 `readBookMetadataByRange` 已是同一類做法：256 KB 區塊快取，13 份 fixture 與整檔結果一致）。
- **已有證據（Issue 2 §4.4，debug 版、metadata 用途）：** 4 次解析後私有記憶體 2,173 → 381 MB，每次殘餘約 +3～5 MB；224 MB 解析耗時 9,019 → 約 2,500 ms。這同時回應「頻繁小請求的 IPC 負擔」的疑慮——至少在 metadata 場景並未造成明顯延遲。
- **未知／風險：**
  - 閱讀器需要讀的章節內容與資源遠多於 metadata，請求次數與延遲未實測。
  - `foliate-js` 的 `epub.js` 預設從整本 Blob 解壓 ZIP；改為 Range 版 loader 的改造範圍尚未估算（Issue 2 已有可借鏡的類 Blob 實作，複雜度可能低於先前預期，但這是推測）。
  - 仍經過外掛的 MethodChannel／COM 路徑；Issue 2 結論是「繞開洩漏」而非「修好」，殘餘約 3～5 MB／次與傳輸量成正比。

### 選項 A：本機 `shelf` HTTP 伺服器

- **架構方案：** App 啟動時於 `127.0.0.1:<random-port>` 起輕量 `shelf` 伺服器，以檔案串流服務 foliate 資產與書檔（即 `epic.md` 決策 6 原預設，後因攔截可用而擱置）。
- **預期好處（未實測）：** 繞開外掛 `shouldInterceptRequest` 的 `web_resource_response.cpp` 路徑；`shelf_static` 等支援 Range，`foliate-js` 可只抓需要的區段；閱讀器與索引器可能同時受益。
- **代價與風險：** 需管理伺服器生命週期；需 Android／Windows 平台分流（Android 維持 `WebViewAssetLoader`，**此點未逐一核對現行程式碼**）；本機 socket 的權杖與防外部存取設計；索引器的 rAF 問題與傳輸方式無關，**本選項不能解決索引器的 Headless 卡住問題**。
- 注意：「從 3.8 GB 降至數 MB」是**預期**，本專案沒有量過 `shelf` 方案。

### 選項 C：修補外掛 C++ 原始碼

- **架構方案：** patch `web_resource_response.cpp`（改用直接記憶體對映或修正 COM 參考計數）。
- **代價與風險：** 根因未查明（見 §3.4），Issue 2 已證實補 `Release()` 無效，patch 方向沒有依據；即使修好洩漏，整本回傳的瞬間尖峰（spike-report 的 release 版 3.8 GB）仍在；原始碼位於 ephemeral 目錄，`flutter clean` 或外掛升級會使 patch 失效，維護成本高。

### 選項 D：其他尚未評估的方案（至少需說明排除理由）

- **WebView2 虛擬網域對應**（`SetVirtualHostNameToFolderMapping`）：`epic.md` 決策 6 原本要求實測，但 `spike-report.md` 的驗證只記錄請求攔截。在本機 ephemeral 外掛的 Windows 原始碼中**搜尋不到**對應呼叫，推測外掛未暴露此 API，若要用需自寫原生 C++（或 fork 外掛）。**這個方案能讓 WebView2 直接由檔案系統串流，理論上避開 Dart 端與 `WebResourceResponse` 整本複製，值得在決策前先確認可行性。**
- **分塊串流回應：** 外掛的 `WebResourceResponse.data` 是整包 `Uint8List`，推測無法分塊，需確認。
- **`file://` 或暫存路徑導向：** 受 WebView 同源與安全限制，可行性待確認。

### 建議的決策順序

1. §7.1 的排除實驗已完成並支持「洩漏在原生端、Release 版同樣存在」，可進入修法選擇。
2. 評估選項 B（已有 Issue 2 驗證）與選項 D 的虛擬網域（確認外掛能否使用）。
3. 選項 A 作為 B／D 不可行時的備案；選項 C 不建議。
4. 索引器的 Headless 卡住問題需獨立追查，不論採用哪個方案都不會自動解決。

---

## 6. 計畫執行與停點狀態

- [x] **Task 1：洩漏判定規則**（純 Dart TDD，commit `4fcdbb59`）
- [x] **Task 2：量測 Helper**（`test/support/leak_meter.dart`，commit `2aa50ad0`；後續審查修正見 §8）
- [ ] **Task 3：索引器量測：未完成。** 索引器在 Windows `HeadlessInAppWebView` 下無法跑完任何一輪，**沒有 `[leak]` 數據、沒有判定**；僅有推論性診斷（§4），被阻擋原因不明。
- [x] **Task 4：閱讀器迴圈量測**（完成 4 次循環，判定 `leaked = true`, `ratcheting = true`）
- [x] **Task 5 Step 1：撰寫本判定報告**
- [x] **Task 5 Step 2：觸發停點規則**（洩漏成立，停下不改 `lib/`，交由使用者決策修法計畫）
- [ ] **Task 5 Step 3、4（完整 `flutter test` 與最終 commit）：** 因觸發停點而未執行；修法計畫確定後於該 Issue 補做。

---

## 7. 排除實驗結果、限制與待補

### 7.1 排除實驗（已執行，2026-11-05）

以暫時的探針（改 `foliate_reader_view.dart` 攔截處加計數與環境變數開關，量測後已還原，**未進版控**）執行。原始輸出見 `assets/issue-3-probe-{default,same,release}.log`（只含 `[leak]` 行；`[probe]` 攔截計數行出現在 console，摘要如下）。

| 實驗 | 設定 | 結果 |
|:---|:---|:---|
| 1. 統計攔截次數 | debug 測試，預設行為 | 5 輪各 **1 次**整本攔截（`/book/current.epub`，235,583,038 位元組）；deltas=[1128.4, 453.3, 448.9, 457.1]；iter1 異常可重現 |
| 2. 回傳同一個 `Uint8List` | debug 測試，`ELINK_LEAK_SAME=1`，首次讀入後每次回傳同一物件 | deltas=[1131.5, 450.0, 453.2, 454.0]；**仍逐次累加**，與預設行為相同 → 排除 Dart 端每次新配置的位元組陣列被保留。基線較高（iter0 後 952 MB vs 731 MB）符合多保留一份 225 MB 的預期 |
| 3. Release 版 | 獨立 Release App（`flutter build windows --release`，暫時進入點跑 5 輪開關），不經測試框架 | 私有記憶體 84.5 → 1,454.2（首次）→ 1,907.7 → 2,359.6 → 2,811.0 → 3,263.3 MB；iter1～4 deltas=[453.6, 451.9, 451.4, 452.4]；`leaked=true ratcheting=true`；WebView2 子程序穩定約 127～144 MB |

**結論：**

1. 洩漏在 **Release 版同樣存在**，每次約 +452 MB，與 debug 版數字一致 → Debug 版限制已排除。
2. 洩漏 **與 Dart 端是否每次新配置位元組陣列無關**，傳輸量（每次 1 次整本請求）決定增量；結合 Issue 2 的排除結果，歸屬原生端的證據現在有兩條路徑支持（metadata、閱讀器）。
3. iter1 的額外增量不是額外請求造成，成因仍未查明（§3.2）。
4. 注意實驗 3 的 Release 迴圈是自寫進入點，與正式 App 路徑（`ReaderScreen`、資料庫、字型載入等）不同，只代表 `FoliateReaderView` 開關本身。

### 7.2 剩餘限制與待補

**限制：**

- 單一程序、單一本書（224.7 MB）；每種設定各只跑一次（iter1 異常另外重現兩次）。
- 取樣只有每輪 `before`／`after_run`／`after_wait` 三個點，**未量到真正的尖峰**；報告中任何「尖峰」數字都來自 `spike-report.md`（release 版僅量一次）。
- 6 秒等待與未主動觸發 Dart GC，不能排除配置器延遲歸還（雖然逐次累加仍符合洩漏特徵）。
- 索引器路徑沒有量測數據（§4）。
- 外掛 `SW_HIDE` 與 rAF 暫停的說法未查證外掛視窗建立程式碼。

**待補實驗（尚未執行）：**

1. 拉長 `after_wait`（例如 60 秒）並在量測前主動觸發 Dart GC，區分配置器延遲歸還與真洩漏。
2. 追查前兩輪的一次性額外增量（例如從冷啟動只開一次、與先前開過其他較小書的對照）。
3. 重跑改良後的 `reader_leak_test.dart`（已改為前後差集斷言）時留存原始輸出——本次三個 debug 實驗已附於 `assets/`，其中 `book_cache 輪前=11 輪後=11 本輪新增殘留=0` 證明本輪沒有新增殘留（`book_cache` 內 11 個項目為先前索引器探針當掉留下的孤兒目錄，與閱讀器無關）。

---

## 8. 審查後的程式與文件調整

依程式審查報告所做的修正（僅測試與文件，未動 `lib/`）：

- `leak_verdict.dart` 與 `leak_meter.dart` 移至 `app/test/support/`，`integration_test/` 單向引用 `test/`，不再反向。
- `leak_meter.dart`：PowerShell 輸出改用 `InvariantCulture`，解析失敗改丟例外（不再 `?? 0.0` 靜默吞掉）；大檔路徑移除個人磁碟位置，改用環境變數 `ELINK_LEAK_EPUB`。
- `reader_leak_test.dart`：快取清理斷言改為本輪前後的差集比對（不再因目錄不存在而空過，也不受先前當掉留下的孤兒目錄干擾），並印出前後數量；兩支洩漏測試加註「修法完成後須改為 `expect(verdict.leaked, isFalse)`」。
- 報告：移除「完全一致」、「精確吻合」、「確鑿」、「必然」等過度措辭；補入限制與待補實驗；修正選項評比。
- 補做排除實驗（§7.1）：統計攔截次數、回傳同一個 `Uint8List`、Release 版，原始輸出存於 `assets/issue-3-probe-*.log`；探針程式已還原、未進版控。
