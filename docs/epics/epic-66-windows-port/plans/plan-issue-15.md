# Issue 15：加粗覆蓋圖測試偶發失敗查根因 Plan（輕量）

**Goal：** 查出 `app/test/reader/pdf_reader_view_filters_test.dart`「pdfBoldStrength > 0 時，第一頁疊加一張處理後的 RawImage 覆蓋層」整批跑 `test/reader` 約 1/3 機率失敗的根因；不再放寬等待輪數。

**已定共識（2026-11-11 grilling）：**
- 只處理加粗覆蓋圖；`download_queue_controller_test` 不併入。
- 先診斷、不改正式程式；診斷輸出只留工作樹，不進 commit。
- 根因確定後，先把修法選項與取捨回報人類，由人類選，再動手。
- 只在這台 Windows 機器驗證，報告註明未跨平台。

**假設（待驗證）：** `_buildProcessedOverlay` 登記的 job 被無聲丟棄且無人重新登記——(a) `_isOverlayJobStillWanted` 為 false（版面／visibleRect 尚未就緒）、(b) `page.render()` 回 null、(c) 渲染後再檢查為 false。替代假設：平行負載下 Isolate／PDFium 排程延遲。

## Tasks

- [ ] **Task 1：基準。** 未改程式的分支上，`flutter test test/reader` 重跑 10 輪（背景、輸出存 scratchpad），記錄每輪加粗案例成敗與耗時。
- [ ] **Task 2：診斷。** 在 `pdf_reader_view.dart` 三個丟棄點與 Isolate 耗時加臨時 `debugPrint`；重跑直到取得失敗樣本，判斷屬哪一條路徑。同時單獨重跑該檔案，判斷是否只在整批負載下才失敗。
- [ ] **Task 3：回報。** 還原診斷改動，寫 `issue-15-report.md`（根因、證據、修法選項與取捨），停下等人類選修法。
- [ ] **Task 4：修復（待人類選定後）。** 依選定修法實作並先寫能重現的測試。

## 過關條件
1. 根因有證據支持（失敗樣本的診斷輸出），或明確記錄「無法確定」與原因。
2. 修完後連續 15 輪整批 `test/reader` 全過，且該檔案單獨重跑全過。
3. `flutter analyze` 乾淨；最終 commit 不含診斷輸出。
