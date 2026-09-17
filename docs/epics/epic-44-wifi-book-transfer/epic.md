# `epic-44-wifi-book-transfer` WiFi 傳書

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-44-wifi-book-transfer/`
**關聯 PRD 章節：** 無直接對應 FR（延伸 FR-02 檔案匯入，新增裝置間直接搬移書籍的能力）

## 開發記錄

2026-09-17 使用者提出「新增 WiFi 傳書功能，可以上傳與下載書籍」需求，`/grill-with-docs`（`/grilling`＋`/domain-modeling`）完成 5 輪 Discovery，`design.md` 已產出。**核心決策**：手機端啟動前景限定的本機 HTTP Server（隨畫面開關），對方純用瀏覽器操作、不需安裝任何 App；單一畫面同時提供上傳（對方→手機）與下載（手機→對方），入口位於「來源」畫面；網路先決條件為手機須真的連上 WiFi（涵蓋手機自己開熱點分享），非 WiFi 時停用；存取控制為同區網信任模型、不需密碼。**上傳**：依格式白名單檢查，走既有 `BookImportService.importFiles()` 管線，內容指紋重複偵測命中時靜默略過（不比照既有雲端匯入/遠端書庫的互動式確認，因操作者在 PC 端看不到手機畫面），書籍來源歸類為既有 `local`（不新增第 5 個 `BookSource` 值）。**下載**：PC 端瀏覽書架清單，僅列出 `isDownloaded == true` 的書（排除「待下載」雲朵角標書籍），逐檔下載不打包 zip；TXT/MD 來源書籍下載時給合成後的 `.epub`（原始純文字未保留，無法精確還原）。**過程中發現的關鍵技術縫隙**：TXT/MD 匯入合成的 EPUB 衍生檔案依 `epic-11` 既有決策維持 `.txt`/`.md` 副檔名但內容是二進位 EPUB zip，原樣下載會讓 PC 端拿到「打開是亂碼」的檔案，已在下載流程中改為誠實回傳 `.epub`；以及既有重複匯入確認對話框機制的前提（操作者在手機螢幕前）在本功能不成立，已改為靜默略過。`CONTEXT.md` 新增「WiFi 傳書」詞條、更新「書籍來源」詞條。**2026-09-17 `/superpowers:receiving-code-review` 審查（`reviews/review-epic-and-design.md`，結論 Changes Requested，2 Critical／4 Important／3 Minor）已完成修訂**：C-1（本機選檔書籍 `Book.filePath` 多為 `content://`，`dart:io` 無法直接讀取，下載改為重用既有 `ReaderResourceChannel.kt` 材質化機制）與 C-2（現代 Android 無公開 API 可判定熱點狀態，改採「介面枚舉＋蜂巢式介面黑名單＋手動確認按鈕」分層判定）查證屬實並補進 `design.md`；I-1（上傳暫存檔若落在快取目錄、被系統回收會導致書籍永久遺失，定案落地路徑須為持久化 App 文件目錄）、I-2（`importFiles()` 內部僅比對路徑字串、從未查詢指紋庫，定案內容指紋檢查須在呼叫 `importFiles()` 之前完成）查證屬實並補進設計；I-3（低階 E-Ink 裝置併發傳輸節流）、I-4（PC 端網頁 100% 離線內嵌、中文檔名 RFC 5987 編碼）、M-2（`FLAG_KEEP_SCREEN_ON` 疊加既有文字提示）、M-3（Port 衝突回退系統動態分配）皆採納補入；M-1（`CONTEXT.md` 詞條未寫入）查證為誤判，兩詞條當時已寫入，未做修正。本輪修訂皆為技術可行性補強，未變動任何 `/grilling` 產品決策形狀。
