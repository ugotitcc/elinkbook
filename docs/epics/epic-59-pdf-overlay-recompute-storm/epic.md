# `epic-59-pdf-overlay-recompute-storm` （缺陷）PDF 開啟手動裁切／加粗後，翻頁產生「覆蓋圖計算風暴」，頁面長時間全白

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-59-pdf-overlay-recompute-storm/`
**關聯 PRD 章節：** PDF 影像濾鏡（加粗）、智慧／手動裁切；關聯已歸檔 `epic-24-pdf-engine-rebuild` Issue 3

## 背景

使用者回報：閱讀頁數多的 PDF，翻頁到一定頁數後頁面全白，連翻好幾頁都是；退出重開第一次打不開、第二次正常。手機、平板、電子紙閱讀器都會發生，**開啟手動裁切時最嚴重**。

## 根因（2026-10-04 真機 adb 實測確認）

測試裝置：1600x2400 平板、debug 版、範例 `2015_仙佛聖訓_一本萬利.pdf`（306 頁整頁掃描圖，已設定手動裁切）。

- 未開裁切／加粗時，連翻 350 頁（兩本書）零白頁、Native Heap 穩定、無 OOM／lmkd／ANR。
- 開啟裁切後：
  - 單純開書，第 55 頁的覆蓋圖被重複計算 9 次、第 54 頁 7 次，同時進行最多 17 個。
  - 連翻 30 頁：`_recomputeOverlay` 開始 888 次、完成 244 次，同時排隊 644 個；**停手後 30 秒仍從 388 增加到 644**。截圖 81KB（白頁）。
  - 白頁期間 App CPU 持續 214～274%，`DartWorker` 執行緒不斷新增（`Isolate.run` 連續開新 isolate）。
  - 約 20～30 秒後畫面才自行恢復。

機制（`app/lib/reader/pdf_reader_view.dart` 的 `_buildProcessedOverlay`／`_recomputeOverlay`）：

1. 某頁覆蓋圖快取尚未填好（`_overlayCacheKey[page] != cacheKey`）時，**每次重繪都會再發一次** `_recomputeOverlay`（整頁 `page.render()`＋`Isolate.run` 裁切／加粗），沒有「進行中」去重。
2. 每個計算完成都會 `setState`，觸發全部可見頁重繪，使尚未完成的頁再發一批新計算 → 正回饋迴圈。
3. 翻過去、已不可見的頁面，其計算不會被取消。
4. PDFium 渲染序列化，積壓後新開書的渲染也排在後面 → 解釋「重開第一次打不開」。

## 決策

1. **去重**：同一頁、同一組 `cacheKey` 只允許一個計算進行中；後續重繪不再發。
2. **略過過期工作**：計算開始前與渲染完成後，若該頁已不在可見／附近範圍，或設定（裁切、加粗）已變，直接放棄，不做 Isolate 運算。
3. **回歸測試**：重繪 N 次，同頁同設定只發 1 次計算。

## 處理方式

缺陷修復，直接 TDD，不寫 `plan-issue-N.md`；保留程式審查（報告存 `reviews/`，不進版控）。

## 開發記錄

**2026-10-04** 登錄 Epic。診斷記錄如上（暫時診斷程式已還原，工作區乾淨）。開始以 TDD 修復。

**2026-10-04 實作（直接 TDD）**

- 新增 `app/lib/reader/pdf_overlay_job_queue.dart`：
  - `PdfOverlayJobQueue`：同頁同設定去重、一次只跑 1 個、排隊中最新登記者優先、輪到時再問 `stillWanted`（已翻走則丟棄）、工作丟例外不卡佇列。
  - `pdfOverlayPageWanted`：頁面落在「可視範圍外擴一個畫面高度」內才算需要。外擴是預取，讓緊鄰的前後頁先算好；一開始只算「正在看到的頁」會讓既有測試（多頁覆蓋圖同時產生）失敗，也會讓翻頁時閃出未裁切原圖，故放寬。
- `pdf_reader_view.dart`：`_buildProcessedOverlay` 改為只向佇列登記；新增 `_isOverlayJobStillWanted`（元件仍在、設定沒變、頁面仍在範圍內）；`_recomputeOverlay` 渲染完成後、進 Isolate 前再確認一次。
- 紅燈：`test/reader/pdf_overlay_job_queue_test.dart`（編譯失敗）。其中「風暴情境」案例：30 頁各重繪 30 次，每頁只能執行 1 次。
- 驗證：`flutter analyze` 乾淨；佇列＋`pdf_reader_view_filters/paginated/dual_page_test`＋`pdf_crop_frame_overlay_test` 共 126 項通過；l10n 硬編碼字串雙檢查 PASS。全套 `flutter test` 與程式審查尚未執行（發 PR 前補）。

**2026-10-04 真機驗證**（同一台平板、同一本書、同樣手勢）

| | 修復前 | 修復後 |
|---|---|---|
| 連翻 30 頁後 | 開始 888 次、排隊 644 個、停手後還在增加 | CPU 0%，畫面已有內容 |
| 連翻 100 頁後 | （未測，已嚴重） | 第 1 個樣本仍白（CPU 117%），約 1 秒後樣本 2 完整顯示、CPU 0% |
| 恢復時間 | 20～30 秒以上 | 約 1～2 秒 |
| Native Heap | 168MB | 約 113MB |

- 畫面內容與裁切結果正確（第 183 頁截圖確認）。

**2026-10-04 電子紙真機驗證**（Mobiscribe WAVE，1404x1872，4GB RAM，Android 12，同一本 `一本萬利` 306 頁，手動裁切已套用）

| | 修復前（21:18 debug 版） | 修復後 |
|---|---|---|
| 從第 1 頁連翻 40 頁 | **App 閃退**：`Dart … allocation.cc: 22: error: Out of memory`（22:49:25，行程 `has died`） | 存活；翻完當下白、CPU 228%，3 秒內畫面出現、CPU 0% |
| 連翻 120 頁（第 41→161 頁） | （已閃退，無法測） | 存活；翻完當下白、CPU 200%，約 2～4 秒內畫面出現、CPU 0%；Native Heap 93MB、PSS 462MB |
| OOM／FATAL／`has died` 紀錄 | 有 | 0 |

- 修復前的閃退證實了假設 2（原生記憶體）在電子紙上成立，但**起因是計算風暴**：數百個排隊的覆蓋圖計算各自持有整頁像素緩衝，4GB 機器配置失敗。去重＋序列化後，同時持有的緩衝降到 1 份。
- 這同時解釋使用者「手機、平板、電子紙都會發生」：記憶體越小，越早從「白頁」惡化為「閃退」。
- 未做：手機實機；「連續捲動」模式；加粗開啟時的同樣驗證。

**2026-10-04 程式審查修訂**（`reviews/review-code.md`：0 Critical／1 Important／3 Minor，結論可合併）

- **Important（測試缺口）成立，已補**：新增 4 個案例——「正回饋迴圈」（每個工作完成就寫快取並觸發全部頁面重繪，30 頁每頁仍只算 1 次）、執行中同頁同設定再登記不重複、執行中同頁換設定舊的結束後新的補跑、`maxConcurrent=2`。這些案例一寫就綠（描述既有行為，非先紅後綠）。改以**變異檢查**確認有效：只拿掉執行中去重 → 1 個案例失敗；完全移除去重 → 5 個失敗（含迴圈案例）；還原後 15 項全過。
- **Minor 2 成立，已修**：`_recomputeOverlay` 的 `rendered != null` 但 `!mounted` 時，`return` 在 `try/finally` 之外，漏呼叫 `rendered.dispose()`。改為只在 `rendered == null` 時提早 return，其餘一律經 `finally` 釋放；卸載由 `_isOverlayJobStillWanted`（`!mounted` → false）涵蓋。這行是既有程式，但位於本次已修改的函式內，故一併修。
- **Minor 1 不改**：`isReady == false` 時放行是刻意取捨（佇列只在 pdfrx 呼叫 overlay builder 時才被填入，此時控制器通常已就緒；多做一次渲染不會卡佇列）。
- **Minor 3 不改**：推測性，電子紙與平板實測連翻 120 頁未見抖動；若日後真機回報再依資料調整 `_maxCachedOverlayImages`。
- **殘餘風險不處理**：丟棄／渲染為 null 後不主動要求重繪，恢復依賴下一次重繪。真機未遇到；若遇到再另案。
- **未補**：`PdfReaderView` 接線層的 widget 測試。既有 `pdf_reader_view_filters_test` 的「多頁各自完成」案例會間接經過這條路徑（126 項通過），但沒有專測「翻走的頁被丟棄」。
- 驗證：`flutter analyze` 乾淨；佇列＋濾鏡／逐頁／雙頁／基本測試共 126 項通過；l10n 雙檢查 PASS。

**附帶觀察（不屬本缺陷，未處理）**

- 安裝新版後第一次啟動停在黑屏：`main()` 的 `AudioService.init`（`main.dart:219`）丟出 `PlatformException: Unable to bind to AudioService` 且未被接住，`runApp` 沒執行到。強制停止後重開即正常，推測是安裝後系統忙碌（同時有「Failed to read WebView version: TimeoutException」）造成的一次性失敗。但「啟動時一個未接住的例外就黑屏」本身是脆弱點，值得另立 Issue 評估是否要包 try/catch 讓 App 仍能進書架。
- 在電子紙上驗證到 Epic 58 手動裁切的部分行為：進入後無框＋提示文字、✓ 灰色停用；手指拖拉出框後 ✓ 變綠；套用後全書統一裁切。尚未驗證：輕點不變暗／殘影、系統中斷放棄選取、起點偏移手感、雙頁並列。
- 已知殘留：連翻停手後，最後一頁的覆蓋圖仍需約 1 秒計算，這段時間畫面是白的（覆蓋圖尚未出來）。這是單頁計算本身的耗時，不屬於本缺陷；若要消除需另案（例如先顯示低解析預覽）。
