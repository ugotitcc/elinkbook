# Epic 66 Issue 4 驗證報告：Windows 書檔改由本機 loopback HTTP 伺服器服務

## 1. 摘要

- **目標：** 消除 Windows 閱讀器開書時以 `shouldInterceptRequest` 整本回傳造成的 `elinkbook.exe` 私有記憶體永久累積洩漏（Issue 3 實證：每次開關約 +452 MB）。
- **解法：** Windows 書檔改由本機 loopback HTTP 伺服器（`shelf`）串流服務，支援 HTTP Range；`main.js` 新增 `bookBaseUrl` 參數。
- **結論：** Task 1 拋棄式原型驗證通過兩大閘門：
  - **閘門 A（debug）：** 5 輪開關 224 MB EPUB 均順利完成渲染（約 4.7~5.0 秒），4 次迭代增量為 `[1.50, 10.49, -0.48, -1.09] MB`，`leaked=false`，遠低於門檻 11.23 MB。
  - **閘門 B（Release）：** 5 輪開關 224 MB EPUB，4 次迭代增量為 `[4.73, 1.27, 2.61, 0.27] MB`，`leaked=false`，4 次迭代累積僅增加 8.88 MB（對比 Issue 3 的 +1808 MB）。
  - **混合內容與 CORS：** WebView2 在 `https://appassets.androidplatform.net` 頁面下透過 `fetch` 載入 `http://127.0.0.1:<port>` 書檔完全順暢，未受阻擋。

## 2. Task 1 拋棄式原型數據記錄

### 2.1 閘門 A（debug 版，`reader_leak_test.dart`）

| 迭代 | Phase | Private Bytes (MB) | Working Set (MB) | WV2 Private (MB) | WV2 程序數 | 增量 (MB) |
|---|---|---|---|---|---|---|
| iter 0 (暖身) | before | 252.21 | 300.58 | 102.87 | 6 | — |
| | after_run | 294.32 | 345.52 | 150.52 | 6 | — |
| | after_wait | 281.21 | 345.59 | 139.76 | 6 | — |
| iter 1 | after_wait | 282.71 | 348.90 | 147.43 | 6 | +1.50 |
| iter 2 | after_wait | 293.20 | 360.16 | 146.02 | 6 | +10.49 |
| iter 3 | after_wait | 292.72 | 360.73 | 147.55 | 6 | -0.48 |
| iter 4 | after_wait | 291.63 | 358.83 | 140.63 | 6 | -1.09 |

- 判定：`leaked=false`, `ratcheting=false`, `exceeded=[]`, 門檻 11.23 MB。快取殘留目錄為 0。

### 2.2 閘門 B（Release 版，`probe_main.dart`）

| 迭代 | Phase | Private Bytes (MB) | Working Set (MB) | WV2 Private (MB) | WV2 程序數 | 增量 (MB) |
|---|---|---|---|---|---|---|
| iter 0 (暖身) | before | 87.70 | 107.97 | 100.21 | 6 | — |
| | after_run | 120.07 | 127.49 | 120.15 | 6 | — |
| | after_wait | 106.18 | 127.38 | 119.69 | 6 | — |
| iter 1 | after_wait | 110.91 | 132.03 | 129.61 | 6 | +4.73 |
| iter 2 | after_wait | 112.18 | 133.09 | 135.89 | 6 | +1.27 |
| iter 3 | after_wait | 114.79 | 135.09 | 135.34 | 6 | +2.61 |
| iter 4 | after_wait | 115.06 | 136.19 | 140.66 | 6 | +0.27 |

- 判定：`leaked=false`, 4 輪 deltas `[4.73, 1.27, 2.61, 0.27] MB`（門檻 11.23 MB）。4 輪合計增量僅 8.88 MB。
