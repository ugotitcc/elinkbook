# Epic 21：PDF 匯入封面產生管線卡住修復（技術債）——工單清單

## Issue 1：匯入極簡/無內容流 PDF 導致書架卡片永久停在 0% 進度

**Status:** needs-triage，尚未進行完整 Discovery。

**依賴：** 無。

**背景：** `epic-4-pdf-enhance` Issue 7 收尾驗證時發現（2026-07-14），原記錄於 `docs/epics.md` 獨立 Backlog 列。2026-08-02 `/diagnose` 確認 `epic-18-reader-device-qa`／`epic-20-fxl-foliate-migration` 皆未涵蓋此問題（詳見 `reviews/bugfix-repro.md`），正式立案獨立追蹤。

**描述：** 真實「匯入書籍」UI 流程匯入既有測試共用的極簡 PDF fixture（`app/test/fixtures/sample.pdf`，345 bytes、`MediaBox [0 0 200 200]`、無任何內容流的空白頁）後，書架卡片永久停在 0% 進度、無法完成匯入（等待 15 秒以上、App 程序仍存活、logcat 無例外訊息）。疑似封面產生管線對無內容流 PDF 缺乏逾時/錯誤處理。

**現況程式碼指認（供 Discovery 起點，非正式根因，完整脈絡見 `reviews/bugfix-repro.md`）：**
- `app/lib/library/book_import_service_impl.dart:247-266`：`_channel.invokeMapMethod('extractMetadata', ...)` 對原生呼叫沒有逾時保護，只 catch `PlatformException`；若原生端永遠不回應，`await` 會無限期卡住且不拋出例外。
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt:327-379`（`extractPdfMetadata()`）：`PdfRenderer` 開檔/渲染邏輯，尚未實測確認畸形 PDF 是否真的在此掛住。

**範圍：** 待正式 Discovery 確認根因後定案，初步方向：
1. 用插樁或除錯器對 `sample.pdf` fixture 重現，定位確切卡住位置。
2. 視根因決定修復點：Dart 端 `Future.timeout()` 降級為「無封面」匯入（比照既有 `on PlatformException` 降級模式）、原生端補上逾時/例外處理，或兩者皆做。

**單元測試要求：** 待 Discovery 確認修復方向後補上；至少須涵蓋「匯入無內容流 PDF 不再卡住、最終以無封面狀態完成匯入」的迴歸測試。

**驗收標準：** 匯入 `app/test/fixtures/sample.pdf` 或等效的無內容流 PDF，書架卡片在有限時間內完成匯入（無論有無封面），不再永久停在 0% 進度。

**相關佐證：**
- `docs/epics/epic-21-pdf-import-cover-fix/reviews/bugfix-repro.md`（本次 `/diagnose` 查證過程）
- `docs/archive/2026-07-14-epic-4-pdf-enhance/`（原始發現脈絡）
