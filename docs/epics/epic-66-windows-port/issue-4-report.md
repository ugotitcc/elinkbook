# Epic 66 Issue 4 驗證報告：Windows 書檔改由本機 Loopback HTTP 伺服器服務

## 1. 摘要

- **目標：** 消除 Windows 閱讀器開書時以 `shouldInterceptRequest` 整本回傳造成的 `elinkbook.exe` 私有記憶體永久累積洩漏（Issue 3 實證：每次開關約 +452 MB，4 輪累積 +1808 MB，瀕臨崩潰）。
- **解法：** Windows 書檔改由本機 Loopback HTTP 伺服器（`LocalBookServer`，基於 `shelf` / `shelf_io`）以串流與 HTTP Range 服務；`foliate/main.js` 新增 `bookBaseUrl` 查詢參數支援。
- **結論：**
  - **Debug 整合測試（`reader_leak_test.dart`）：** 5 輪開關 224 MB 大檔 EPUB，4 次迭代私有記憶體增量為 `[6.99, 0.53, 2.92, -0.54] MB`，`leaked=false`，`ratcheting=false`；快取目錄殘留為 0；`expect(verdict.leaked, isFalse)` 正式加入回歸斷言。
  - **Release 模式（`probe_main.dart`）：** 5 輪開關 224 MB 大檔 EPUB，4 次迭代私有記憶體增量為 `[4.17, -1.00, 5.01, 0.03] MB`，4 輪累積增量僅 +8.21 MB（對比 Issue 3 的 +1808 MB）；`leaked=false`。
  - **索引器（`FoliateContentIndexer`）：** 亦已改接 `LocalBookServer`，徹底移除 Windows `/book/` 的 `shouldInterceptRequest` 攔截路徑。

---

## 2. 測試環境與設定

- **作業系統：** Windows 11 Pro 64-bit
- **WebView2 執行期版本：** Evergreen 135+
- **測試樣本：** `tmp/AI世界的底層邏輯與生存法則.epub`（真實大檔樣本，大小 224.67 MB，235,583,038 位元組）
- **判定門檻：** 5% 書檔大小 = 11.23 MB
- **迴圈次數：** 暖身 1 輪（iter 0）+ 正式量測 4 輪（iter 1~4），每輪開書後等待渲染完成、卸載 Widget、等待 6 秒記憶體回落

---

## 3. 量測數據

### 3.1 Task 1 拋棄式原型數據（閘門 A 與 B）

#### 閘門 A（Debug 原型）

| 迭代 | Phase | Private Bytes (MB) | Working Set (MB) | WV2 Private (MB) | WV2 程序數 | 增量 (MB) |
|---|---|---|---|---|---|---|
| iter 0 (暖身) | before | 252.21 | 300.58 | 102.87 | 6 | — |
| | after_run | 294.32 | 345.52 | 150.52 | 6 | — |
| | after_wait | 281.21 | 345.59 | 139.76 | 6 | — |
| iter 1 | after_wait | 282.71 | 348.90 | 147.43 | 6 | +1.50 |
| iter 2 | after_wait | 293.20 | 360.16 | 146.02 | 6 | +10.49 |
| iter 3 | after_wait | 292.72 | 360.73 | 147.55 | 6 | -0.48 |
| iter 4 | after_wait | 291.63 | 358.83 | 140.63 | 6 | -1.09 |

- **判定：** `leaked=false`, `ratcheting=false`, `deltas=[1.50, 10.49, -0.48, -1.09]`（門檻 11.23 MB）。

#### 閘門 B（Release 原型）

| 迭代 | Phase | Private Bytes (MB) | Working Set (MB) | WV2 Private (MB) | WV2 程序數 | 增量 (MB) |
|---|---|---|---|---|---|---|
| iter 0 (暖身) | before | 87.70 | 107.97 | 100.21 | 6 | — |
| | after_run | 120.07 | 127.49 | 120.15 | 6 | — |
| | after_wait | 106.18 | 127.38 | 119.69 | 6 | — |
| iter 1 | after_wait | 110.91 | 132.03 | 129.61 | 6 | +4.73 |
| iter 2 | after_wait | 112.18 | 133.09 | 135.89 | 6 | +1.27 |
| iter 3 | after_wait | 114.79 | 135.09 | 135.34 | 6 | +2.61 |
| iter 4 | after_wait | 115.06 | 136.19 | 140.66 | 6 | +0.27 |

- **判定：** `leaked=false`, `deltas=[4.73, 1.27, 2.61, 0.27]`, 4 輪合計增量僅 8.88 MB。

---

### 3.2 Task 6 正式落地驗證數據

完整日誌已存於：
- Debug：`docs/epics/epic-66-windows-port/assets/issue-4-debug.log`
- Release：`docs/epics/epic-66-windows-port/assets/issue-4-release.log`

#### 3.2.1 Debug 整合測試（`reader_leak_test.dart`）

```
[leak] path=reader iter=0 phase=before private_mb=255.73 ws_mb=303.07 wv2_private_mb=99.77 wv2_count=6
[OpenBook#802711870] 已渲染 距開書 6942 ms
[leak] book_cache 輪前=12 輪後=12 本輪新增殘留=0
[leak] path=reader iter=0 phase=after_wait private_mb=287.96 ws_mb=350.90 wv2_private_mb=134.18 wv2_count=6

[leak] path=reader iter=1 phase=before private_mb=287.96 ws_mb=351.02 wv2_private_mb=134.18 wv2_count=6
[OpenBook#439477781] 已渲染 距開書 4800 ms
[leak] book_cache 輪前=12 輪後=12 本輪新增殘留=0
[leak] path=reader iter=1 phase=after_wait private_mb=294.95 ws_mb=358.83 wv2_private_mb=139.82 wv2_count=6 (delta: +6.99 MB)

[leak] path=reader iter=2 phase=before private_mb=294.95 ws_mb=359.02 wv2_private_mb=139.61 wv2_count=6
[OpenBook#406206303] 已渲染 距開書 4161 ms
[leak] book_cache 輪前=12 輪後=12 本輪新增殘留=0
[leak] path=reader iter=2 phase=after_wait private_mb=295.48 ws_mb=359.88 wv2_private_mb=139.88 wv2_count=6 (delta: +0.53 MB)

[leak] path=reader iter=3 phase=before private_mb=295.48 ws_mb=360.06 wv2_private_mb=139.87 wv2_count=6
[OpenBook#448668442] 已渲染 距開書 4466 ms
[leak] book_cache 輪前=12 輪後=12 本輪新增殘留=0
[leak] path=reader iter=3 phase=after_wait private_mb=298.40 ws_mb=364.32 wv2_private_mb=140.41 wv2_count=6 (delta: +2.92 MB)

[leak] path=reader iter=4 phase=before private_mb=298.90 ws_mb=364.45 wv2_private_mb=140.40 wv2_count=6
[OpenBook#228164381] 已渲染 距開書 4466 ms
[leak] book_cache 輪前=12 輪後=12 本輪新增殘留=0
[leak] path=reader iter=4 phase=after_wait private_mb=297.86 ws_mb=363.07 wv2_private_mb=131.36 wv2_count=6 (delta: -0.54 MB)

[leak-verdict] path=reader leaked=false ratcheting=false deltas=[6.99, 0.53, 2.92, -0.54] exceeded=[] threshold_mb=11.23
All tests passed!
```

#### 3.2.2 Release 實測（`probe_main.dart`）

| 迭代 | Phase | Private Bytes (MB) | Working Set (MB) | WV2 Private (MB) | WV2 程序數 | 增量 (MB) |
|---|---|---|---|---|---|---|
| iter 0 (暖身) | before | 88.70 | 107.54 | 98.71 | 6 | — |
| | after_run | 130.29 | 130.55 | 306.65 | 7 | — |
| | after_wait | 109.95 | 126.78 | 141.00 | 6 | — |
| iter 1 | after_wait | 114.12 | 131.44 | 142.30 | 6 | +4.17 |
| iter 2 | after_wait | 113.12 | 130.45 | 143.60 | 6 | -1.00 |
| iter 3 | after_wait | 118.13 | 135.27 | 138.35 | 6 | +5.01 |
| iter 4 | after_wait | 118.16 | 136.54 | 143.40 | 6 | +0.03 |

- **判定：** `leaked=false`, `ratcheting=false`, `deltas=[4.17, -1.00, 5.01, 0.03]`, 4 輪累計增量僅 **+8.21 MB**。

---

## 4. 尖峰記憶體與 Issue 3 基準對照

| 指標 | Issue 3 基準（`shouldInterceptRequest` 全讀） | **Issue 4（Loopback HTTP 串流）** | 效益 |
|---|---|---|---|
| **每輪開書私有記憶體增量** | 約 **+452 MB / 輪** | **-1.00 ~ +5.01 MB / 輪** | 徹底杜絕階梯累積 |
| **4 輪開關後累積私有記憶體** | 累計增加 **+1808 MB**（自 ~250MB 暴增至 >2000MB） | 累計增加 **+8.21 MB**（Release 穩定在 118MB） | 減少 **99.5%** 記憶體殘留 |
| **開關 5 輪後存活狀態** | 記憶體耗盡閃退或瀕臨系統崩潰 | 記憶體完全回落，程序常態平穩運行 | 系統穩定性大幅躍升 |
| **開書渲染耗時** | 約 4.5~5.0 秒 | 約 4.1~4.8 秒（快取複製 ~1.4s，渲染 ~3s） | 開書流暢度維持一致 |

---

## 5. 過關條件逐項檢核

- [x] **過關條件 1（洩漏消除）：**
  `reader_leak_test.dart -d windows` 與 Release 模式實測下，4 次迭代增量均遠低於 11.23 MB 門檻，`leaked=false`，`ratcheting=false`。長期回歸防線斷言 `expect(verdict.leaked, isFalse)` 已啟用且測試全綠。
- [x] **過關條件 2（快取無殘留）：**
  每次卸載閱讀器後，`book_cache` 目錄新增殘留為 0（輪前 12、輪後 12，差集為空）。
- [x] **過關條件 3（功能完整性）：**
  - Foliate `openBook()` 順暢載入 HTTP 書檔，無混合內容或 CORS 阻擋。
  - EPUB 橫排/直排、目錄、劃線、翻頁正常。
  - 書檔伺服器支援 HTTP Range 隨需讀取與中途 dispose 取消釋放 handle。
  - Android 端與既有行為逐字相同、完全不受影響。

---

## 6. 其他資源與字型攔截說明

自訂字型（`FoliateRequestKind.customFont`）目前仍維持由 `shouldInterceptRequest` 攔截提供。實測中未發現自訂字型造成記憶體爬升，主因包括：
1. 字型檔體積通常小於數 MB（相較於動輒數百 MB 的圖文電子書）。
2. 字型在開書當下僅被請求與快取一次，關閉書籍後 WebView 實例銷毀，不會成比例重複累積。
3. 若未來發現自訂字型有類似問題，可直接利用既有的 `LocalBookServer` 擴充靜態資源端點進行服務。

---

## 7. 限制與後續建議

1. **索引器（`FoliateContentIndexer`）Headless 暫停問題：**
   雖然索引器已完成程式碼改接與單元測試（`foliate_index_uri_test.dart`），但 Windows 端 `HeadlessInAppWebView` 在無實體視窗時會因 Chromium 背景 rAF 機制節流而暫停，此問題屬於 Chromium / WebView2 限制，由獨立 Issue 追蹤。
2. **Foliate 內部 Range 分段載入：**
   目前 `foliate-js` 內部仍使用 `fetch().then(r => r.blob())` 載入整本書。若未來要進一步降低 WebView2 渲染器子程序（msedgewebview2.exe）在開啟數百 MB 書籍時的瞬間記憶體峰值，可評估將其改造為 Range-based loader。
