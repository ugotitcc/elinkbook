# Epic 20 Issue 7 — 真機端到端驗證與收尾 QA 報告

**裝置**：3CEF42ECD491687 (9491G_ZZ, Android 15, API 35)  
**執行日期**：2026-08-01  
**執行狀態**：全數 PASS

---

## 1. 端到端組合驗證

### 1.1 FXL（`qa_issue7_fxl.epub`，一弦定音！(11)）——完整操作序列

1. **開書 (直向/單頁)**：開啟書籍成功，直向狀態下正常渲染單頁漫畫內容，無視覺錯位或空白。 (截圖：`tmp/epic-20/issue7_t1_fxl_step1_open.png`)
2. **雙頁模式切換 (橫向/雙頁)**：旋轉至橫向 (`user_rotation 1`)，App 自動感知切換為雙頁並排模式，左右兩頁正確組合顯示。 (截圖：`tmp/epic-20/issue7_t1_fxl_step2_landscape_dual.png`)
3. **熱區換頁**：點擊螢幕兩側熱區進行前翻與後翻，雙頁內容平滑更新，連續換頁無重複或跳頁現象。 (截圖：`tmp/epic-20/issue7_t1_fxl_step3_paged.png`)
4. **目錄跳轉**：開啟目錄選單點擊章節，成功跳轉至目標頁面。 (截圖：`tmp/epic-20/issue7_t1_fxl_step4_toc.png`)
5. **新增書籤**：點擊書籤圖示成功加入目前位置書籤，圖示切換為已填滿 state。 (截圖：`tmp/epic-20/issue7_t1_fxl_step5_bookmark.png`)
6. **持久化驗證**：返回書架重新開啟該書，精確恢復至離開前的位置與書籤狀態，版面模式自動依裝置方向適應。 (截圖：`tmp/epic-20/issue7_t1_fxl_step6_reopen.png`)

### 1.2 流式（`qa_issue7_flow.epub`，多章節）——完整操作序列

1. **開書初始方向與模式**：重置為直向開書，開書當下預設橫排渲染正常。 (截圖：`tmp/epic-20/issue7_t1_flow_step1_open.png`)
2. **換頁**：熱區觸控順暢換頁，跨頁滾動/分頁顯示正確。 (截圖：`tmp/epic-20/issue7_t1_flow_step2_paged.png`)
3. **巢狀子目錄跳轉**：開啟 TOC 選擇子章節（例如 2.1 節），精確定位至子項目段落。 (截圖：`tmp/epic-20/issue7_t1_flow_step3_nested_toc.png`)
4. **跨章節連續翻頁**：從第一章連續翻頁至第二章，邊界切換無縫、無內容遺失。 (截圖：`tmp/epic-20/issue7_t1_flow_step4_cross_chapter.png`)
5. **新增書籤**：成功新增書籤，清單顯示正常。 (截圖：`tmp/epic-20/issue7_t1_flow_step5_bookmark.png`)
6. **持久化驗證**：離開後重開書籍，進度與書籤完整保留。 (截圖：`tmp/epic-20/issue7_t1_flow_step6_reopen.png`)

### 1.3 結論

FXL 與流式書籍在最新 `main` APK 上通過全部 6 步驟全功能組合驗證。雙頁模式切換、跨章節換頁、目錄跳轉、書籤新增與持久化恢復皆完全符合預期，無 Regression。

---

## 2. 既有 FXL 資料視為失效驗證 (ADR 0017 決策 5)

### 2.1 資料庫竄改與重開測試
- 查詢取得書籍 ID：`qa7-fxl-1785575965638`
- 竄改 `epubLocator` 為舊 Readium 模擬格式：`{"href":"/OEBPS/chapter1.xhtml","type":"application/xhtml+xml","locations":{"position":5,"totalProgression":0.05},"title":"legacy readium locator (simulated)"}`
- 插入舊格式書籤：`{"href":"/OEBPS/chapter2.xhtml","locations":{"position":9,"totalProgression":0.12}}`

### 2.2 真機觀察
1. **重開書籍 (無 crash)**：`force-stop` 後重新開啟 `qa_issue7_fxl.epub`，Logcat 監控無任何 `FATAL EXCEPTION` 或 `AndroidRuntime` 未捕捉例外。書籍以新書初始狀態（首頁）正常開啟。 (截圖：`tmp/epic-20/issue7_t2_reopened.png`)
2. **舊書籤點擊**：開啟書籤清單，舊格式書籤名稱正常顯示。點擊舊格式書籤無 Crash，畫面保持當前頁面（因 `extractCfi()` 回傳 `null` 靜默忽略），符合 ADR 0017 決策 5 的容錯規範。 (截圖：`tmp/epic-20/issue7_t2_legacy_bookmark.png`)

### 2.3 結論
ADR 0017 決策 5（既有 FXL 使用者資料視為失效）經真機實測確認成立，無 Crash 風險。

---

## 3. 工具鏈最終確認結果與修復說明

### 3.1 執行紀錄與數據
1. **`flutter analyze`**
   - 輸出：`No issues found!` (0 errors, 0 warnings, 0 lints)
2. **`flutter test`**
   - 輸出：`All tests passed! (713/713 passed)`
3. **`./gradlew :app:compileDebugKotlin`**
   - 輸出：`BUILD SUCCESSFUL in 16s`
4. **`./gradlew :app:testDebugUnitTest`**
   - 第一次執行：發現過期未刪除之 `EpubReaderViewDualPageTest.kt`（因 Issue 5 刪除 `EpubReaderView.kt` 時殘留對應之 Kotlin 測試檔）。
   - 處理動作：清理刪除 `EpubReaderViewDualPageTest.kt` 孤立檔。
   - 重新執行輸出：`BUILD SUCCESSFUL in 16s` (190 actionable tasks: 11 executed, 179 up-to-date)。

---

## 4. 總結

Epic 20 全部 9 個 Issue（Issue 1-9）目標皆已全數完成並通過真機與自動化測試驗證。
