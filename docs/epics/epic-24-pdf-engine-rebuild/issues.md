# Epic 24：PDF 渲染引擎重建（遷移至 pdfrx/PDFium）——工單清單

依 `spec.md` 拆解為 8 個垂直切片（tracer bullet），依 spec.md「Further Notes」的優先順序建議排序：Issue 1-4 為「引擎替換＋既有功能對等」批次，確保任何時間點退回現行架構的成本可控；Issue 5-7 為「新增能力」批次；Issue 8（FAB 工具列整合）殿後，因為需要書籤/目錄皆就緒才能一次接上完整 6 顆按鈕。除 Issue 1 外，其餘 7 張皆以 Issue 1 為前置依賴（新 `pdfrx` widget 存在後才有東西可以擴充）。

## Issue 1：PDF 引擎基礎替換——單頁開書/頁碼/跳頁/`content://` 存取

**Status:** ✅ 已完成並合併（2026-08-07，PR #123 合併至 `main`，commit `f4fcb79`）

**合併前審查歷程**（三輪 `/superpowers:requesting-code-review`，報告存於本機 `tmp/epic-24/`，未進版控）：第一輪發現 2 Critical（Android 端 `flutter build apk --debug` 編譯失敗；`flutter analyze` 67 issues，皆與計畫核取方塊自陳「已完成」不符）＋2 Important（`content://` 存取整包讀入記憶體，OOM 風險；音量鍵翻頁測試斷言弱化為恆真式）＋2 Minor，全數修正；第二輪複審確認 5/6 項已用實際指令驗證修復，音量鍵測試修復聲明查證不實；第三輪複審確認斷言已改為驗證真實 `pageIndex` 變化，但發現測試覆蓋範圍語意漂移。合併時的實測結果：`flutter build apk --debug` 成功、`flutter analyze` 0 issues、`flutter test` 966/966 全數通過。

**合併時遺留、移交後續工單／人類決定的已知風險**（非本工單封閉範圍內解決，記錄供後續參考）：
1. `content://` URI 存取最終**未採用** `openCustom` 隨機存取分段讀取（原計畫優先路徑），改走「Kotlin 端串流複製暫存檔＋回傳路徑字串」這條 AC 明確允許的回退路徑（已於 `ReaderResourceChannel.kt` class doc 與對應單元測試記錄）。
2. `ReaderScreen._handleVolumeKeyCall`（音量鍵事件→翻頁）分派邏輯本身，在 widget test 層級缺乏強斷言覆蓋（僅測「停用」分支，斷言僅 `mounted == true`）；`PdfReaderView.nextPage`/`.previousPage` 底層方法本身已有強斷言。
3. `app/integration_test/pdf_nav_zone_test.dart`／`volume_key_test.dart` 斷言的頁尾文字格式 `"第 X/Y"` 疑似已因無關的頁尾重構（`fdd0b05`）過期（現況格式為 `"X/Y"`），可能在真機上逾時失敗——尚未在真機上實測確認，建議近期找機會驗證並視需要修正。

**依賴：** 無，其餘 7 張工單皆依賴本張。

**對應 User Stories（`spec.md`）：** 22, 23, 24

### What to build

新增以 `pdfrx` 為底層的 Dart PDF 閱讀 widget，取代現行以 `android.graphics.pdf.PdfRenderer` 為底層、透過 `AndroidView` `PlatformView` 渲染的既有實作，直接在 Flutter widget 樹中渲染 PDF，不再透過原生端。範圍限定「單頁顯示＋頁碼＋跳頁」這一最小可驗證路徑——雙頁、影像濾鏡、劃線、目錄、搜尋、縮圖、FAB 工具列皆為後續獨立工單，不在本工單範圍內。

新 widget 對外的建構參數（檔案路徑、開書成功/失敗回呼）維持與現行契約語意相容（開書成功一次性回呼、開書失敗攜帶錯誤訊息字串），讓既有的、格式無關的閱讀畫面狀態機（載入中／已渲染／錯誤三態，以及「已成功渲染的畫面不會被之後才發生的錯誤覆蓋」既有守衛邏輯）不需要改動。

檔案存取須解決 `content://` URI 相容性：優先評估透過 `pdfrx` 的自訂讀取來源能力（讀取 callback，可從既有系統檔案描述符存取方式提供位元組），不需要真實檔案系統路徑、也不需要把檔案整包複製到 App 私有目錄——維持既有「不複製、直接引用原始檔案」的架構原則。只有在證實這個橋接方式不可行時，才退回「落地複製到本機快取」，且僅限於這個回退情境下使用，不做為預設路徑。

現行原生 PDF 渲染模組與其對外暴露的 method channel 契約（開書、頁面渲染完成、錯誤回報三個既有呼叫點）本工單內即可開始淘汰——不需要等全部 8 張工單做完才能移除，維持雙套實作並存的時間愈短愈好。清退時須確保 `ReaderScreen` 內部所有對舊原生 View 的呼叫點都已完整改接新 widget，不留下任何仍引用舊路徑的死碼（`spec.md` 審查回應）。

**已知且經人類確認接受的暫時性行為退化**：本工單完成並合併回 `main` 後，直到 Issue 2-4 陸續完成合併前，PDF 閱讀會暫時失去雙頁並列、E-Ink 影像濾鏡/裁切、劃線/備註/書籤這些現行已上線的能力（因為決策 1 是「完全替換、不漸進共存」，舊原生架構不再並存）。這是刻意接受的風險排序，不是遺漏——若之後任何一次真機驗收發現這個退化窗口造成困擾，才需要重新評估是否要把 Issue 1-4 綁定同一次合併，而非逐張個別合併。

### Acceptance criteria

- [x] 開啟一個真實 PDF 檔案（本機路徑）成功顯示第一頁，`onPageRendered`／`onError` 語意等價回呼皆正確觸發。
- [x] 開啟一個以 `content://` URI 表示的 PDF 檔案（模擬 SAF 匯入情境）成功顯示，且**不會**在裝置儲存產生該檔案的完整複本（除非已證實 `openCustom` 橋接不可行、明確走文件記錄的回退路徑，此情境須有對應測試與文件註記）。——最終走的是文件記錄的回退路徑（見上方「已知風險」第 1 點），符合本條允許的例外。
- [x] `pageCount`／`jumpToPage(index)` 正確運作，含邊界情況（跳到最後一頁、跳到超出範圍的頁碼須有合理防呆）。
- [x] 開啟失敗（檔案不存在／損毀）時觸發等價於現行 `onError` 語意的回呼，閱讀畫面正確顯示錯誤狀態。
- [x] 新增一份內容更豐富的 PDF 測試 fixture（多頁，取代現行僅 345 bytes、單頁、無內容的 `sample.pdf`），提交進版控供本工單與後續 7 張工單共用。
- [x] 單元測試：直接用 `flutter test`（非 `integration_test/`）對新 fixture 驗證開書／頁數／跳頁行為，比照 spec.md 測試策略——不透過真機/模擬器。
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過（含既有測試零回歸）。
- [x] 確認 `ReaderScreen` 與相關模組中沒有任何殘留對舊原生 PDF View／method channel 的引用（`grep` 驗證），避免死碼或執行期空參考例外。

### Blocked by

None - can start immediately.

---

## Issue 2：雙頁並列（Facing Spread）

**Status:** ✅ 已完成並合併（2026-08-09，PR #124 合併至 `main`，commit `dcb7a67`）

**合併前審查歷程**：`/superpowers:requesting-code-review` 一輪即通過（0 Critical／0 Important／3 Minor），報告存於本機 `tmp/epic-24/review-issue-2.md`（未進版控）。審查另開獨立 git worktree 實測，`pdf_spread_layout_test.dart`／`pdf_reader_view_dual_page_test.dart`／`pdf_reader_view_test.dart` 41 項全數 PASS，全專案 1002 項測試全數 PASS（`pdf_reader_view_test.dart` diff 為空，零回歸宣稱屬實），`flutter analyze` 乾淨；並對照 `pdfrx` 套件原始碼確認 `calculateCurrentPageNumber` 覆寫的設計理由（`_guessCurrentPageNumber` 行為）並非臆測。3 項 Minor（`PdfReaderView` 類別文件註解過時、計畫文件一則測試範例算式誤差、`dualPageDirection` 執行期切換測試時序穩健度）已於合併前修正（commit `40ab20d` 於分支、`65c69b0` 於 `main`）。

**依賴：** Issue 1（需要新 `pdfrx` widget 已能開書顯示）。

**對應 User Stories（`spec.md`）：** 8, 9

### What to build

雙頁模式沿用既有的「雙頁模式（Dual-Page Mode）」三態設計（自動/永遠雙頁/永遠單頁，`CONTEXT.md` 既有詞彙，單書持久化於既有偏好設定），語意與資料層不變，底層改由 `pdfrx` 原生的雙頁排版能力實作，取代現行自行拼接點陣圖的作法。雙頁配對規則（封面獨立顯示、之後兩兩配對）與既有「Spread（跨頁）」既有詞彙定義一致。

### Acceptance criteria

- [x] 三態雙頁模式（自動/永遠雙頁/永遠單頁）皆正確驅動 `pdfrx` 的雙頁排版，「自動」模式下橫向時雙頁、直向時單頁。
- [x] 封面獨立顯示、之後兩兩配對的既有 Spread 規則正確重現。
- [x] 單元測試：`flutter test` 對多頁 fixture 驗證各雙頁模式下的頁面配對結果。
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過（含 Issue 1 既有測試零回歸）。

### Blocked by

- Issue 1

---

## Issue 3：E-Ink 影像濾鏡/裁切功能對等

**Status:** ✅ 已完成並合併（2026-08-09，PR #125 合併至 `main`，commit `a5fbea7`）

**與 spec.md 的刻意偏離（經人類確認採用）**：對比度/亮度改用 Flutter 內建 `ColorFiltered`（`ColorFilter.matrix`，格式與 Android `ColorMatrix` 完全相同）即時包住整個 `PdfViewer`，GPU 合成、不需要背景 Isolate/debounce——比字面規格更簡單且效能更好，並非規避規格意圖。防手震延遲（`PdfFilterDebouncer`）改為只作用於加粗強度（真正連續拖曳觸發背景像素運算的欄位），詳見 `plans/plan-issue-3.md`「與 spec.md 的偏離」段落與 `docs/research/pdfrx-and-saber-image-filter-architecture.md`（調查同樣使用 `pdfrx` 的開源專案 `saber-notes/saber`，其深色模式反相功能採用相同的 `ColorFiltered` 技術，佐證此架構決策）。

**合併前審查歷程**（兩輪 `/superpowers:requesting-code-review`，報告存於本機 `tmp/epic-24/`，未進版控）：第一輪發現 3 Critical（新增的 `flutter_test_config.dart` 造成 `flutter test` 全量回歸失敗；Critical 2/4 專屬回歸測試被整批刪除且未記錄；`reader_screen_test.dart` 對 `PdfCropFrameOverlay` 接線零測試覆蓋）＋2 Important（靜默吞例外；測試基礎設施缺乏文件），修正後複審確認前兩項 Critical 已修正、第三項部分修正並發現一個新阻塞項（孤立殘留測試檔案讓 `flutter analyze` 不乾淨）。處理殘餘測試缺口時進一步發現一個真正的實作缺陷（非測試環境限制）：`_recomputeOverlay`/`_detectCropRect` 把 `Isolate.run()` 的 closure 定義在 State 方法內部時，Dart VM 會把該 closure 所在整個詞法作用域（含 `PdfPage` 參數，牽連 pdfrx 內部不可跨 isolate 傳遞的 rxdart `BehaviorSubject`）一併打包，執行期必定擲出 unsendable 例外並被 `.catchError` 靜默吞掉——**代表加粗/裁切合併前實際上完全不會在真機上產生任何視覺效果**，已改為呼叫獨立於 State 之外、參數列僅含可傳遞型別的頂層函式（`_isolateProcessOverlayPixels`/`_isolateDetectCropRect`）修正，並補回原本因誤判為「環境限制」而省略的測試。合併時 `flutter analyze`／`flutter test`（1045/1045）皆綠燈。

**依賴：** Issue 1。

**對應 User Stories（`spec.md`）：** 13, 14, 15, 16

### What to build

對比度/亮度濾鏡、型態學膨脹加粗（PDF 加粗）、智慧自動裁切、手動選區裁切，四項現行由原生端直接操作點陣圖完成的影像處理，改在 Dart 端對 `pdfrx` 輸出的頁面點陣圖資料重新實作，達到功能與可用效能對等（同樣的濾鏡參數範圍、同樣的裁切互動方式），不接受功能退化。

影像處理運算（尤其型態學膨脹屬於逐像素運算）一律於背景 Isolate 執行，不佔用 UI 主執行緒。對比度/亮度等濾鏡參數若由使用者拖曳 Slider 連續調整，須加上防手震延遲（debounce）或可取消的運算排程，避免拖曳過程中連續派送大量背景 Isolate 運算工作造成佇列塞車、UI 反應遲鈍（`spec.md` 審查回應）。若背景 Isolate 效能仍無法達成功能對等的可用效能，保留封裝原生（C/C++ FFI）影像處理模組作為備案。

智慧自動裁切維持現行「取樣偵測邊界後全書統一套用同一比例」的既有語意（非逐頁各自計算）；手動選區裁切維持「使用者框選矩形後全書統一套用」的既有語意。

### Acceptance criteria

- [x] 對比度/亮度濾鏡對已知輸入產生與現行原生實作相當的輸出（像素取樣比對或等價的斷言方式）——改用 `ColorFiltered`/`ColorFilter.matrix`，矩陣公式與原生 `ColorMatrix` 逐行移植，`contrastBrightnessColorMatrix()` 純函式單元測試涵蓋已知輸入輸出配對。
- [x] 型態學膨脹加粗濾鏡正確運作，於背景 Isolate 執行、不阻塞 UI（`_isolateProcessOverlayPixels` 頂層函式，修正 Isolate unsendable 例外後實測可正常產生覆蓋圖）。
- [x] 智慧自動裁切、手動選區裁切維持既有「全書統一套用」語意，非逐頁各自計算。
- [x] Slider 連續調整時有防手震延遲，不會對每一個中間值都觸發一次完整背景運算——**刻意偏離**：對比度/亮度已無背景運算可言（見上方偏離說明），實際需要 debounce 的是加粗強度，`PdfFilterDebouncer` 已改為只作用於此欄位。
- [x] 單元測試：`flutter test` 驗證各濾鏡函式的輸入輸出配對、Isolate 呼叫時機、debounce 行為。
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過（含 Issue 1/2 既有測試零回歸）。

### Blocked by

- Issue 1

---

## Issue 4：書籤/劃線/備註遷移（矩形選取機制保留，新增 PDF 書籤 toggle）

**Status:** ✅ 已完成並合併（2026-08-10，PR #126 合併至 `main`，commit `43af3f3`）

**合併前審查歷程**（一輪＋一輪複審 `/superpowers:requesting-code-review`，報告存於本機 `tmp/epic-24/`，未進版控）：初輪發現 0 Critical／2 Important／4 Minor。Important #1（「PDF 書籤 toggle：目前頁已有書籤時呼叫後移除該筆」測試約 1/3 機率間歇性擲出 `!timersPending`）根因為測試省略了本檔案其餘真實載入 PDF 測試皆遵循的 30 次輪詢等待慣例，補回後經多次重跑驗證修復。Important #2（Task 6 選取測試改用直接呼叫 callback 而非真實手勢模擬，程式碼註解宣稱「`ReaderScreen` widget 樹會截斷手勢／`pdfrx` 在 widget test 環境下攔截手勢」）經人類指示「查雙頁模式下手勢為什麼觸發不了」後實測追查：以獨立診斷探針證實該說法為假，真正原因是 (1) 等待不足與 (2) `flutter test` 預設橫向視窗誤觸產品預設 `dualPageMode: auto`、雙頁模式下頁面位置與測試原本「左上角固定偏移量」假設不符——改回真實手勢模擬＋沿用既有直向視窗慣例強制單頁模式後，額外浮現一則因此才被真正執行到的錯誤斷言（誤以為選色後 Toolbar 應消失），追查確認 `_handlePdfHighlightStyleSelected` 選色後刻意保留選取狀態以便續加備註、與 EPUB 對應邏輯行為對稱，修正的是測試斷言本身而非產品程式碼。4 項 Minor 中 3 項審查報告已標註「純記錄、無需處理」，剩餘 1 項（`firstWhere`/`cast` 迂迴寫法）隨 Important #1 修正順手改為簡單 for 迴圈。合併時 `flutter analyze` 乾淨、`reader_screen_test.dart`（135/135）與既有 PDF 測試（61/61）皆綠燈。

**依賴：** Issue 1。

**對應 User Stories（`spec.md`）：** 10, 11, 12, 25

### What to build

保留現行「長按拖曳框選矩形」的選取互動模式作為主要機制，不改為純文字選取——理由：現行選取以頁面座標（相對頁面內容範圍的百分比矩形）為資料模型，不依賴 PDF 是否有可抽取的文字層，對掃描件（純圖片）PDF 與一般數位原生 PDF 都能一致運作；若改為完全依賴文字定位的文字選取，掃描件 PDF 會直接失去劃線能力，是真實的功能倒退。

選取範圍的資料模型（頁碼＋相對頁面內容範圍的百分比矩形＋相對整個 widget 尺寸的百分比矩形，用於浮動工具列定位）維持現行語意不變，僅底層渲染來源改變。**雙頁模式下，「相對頁面內容範圍的百分比矩形」須明確定義為相對單一頁面本身的邊界，不是相對包含左右兩頁的整個雙頁 viewport**（`spec.md` 審查回應）——否則單頁/雙頁模式切換（或雙頁模式下裝置旋轉）時，既有劃線的百分比座標基準會不一致，導致高亮筆劃拉伸或錯位。

劃線/備註的持久化（`Highlight`／`Note`／`Bookmark` 資料模型，含 `pdfPageIndex` 定位）不需要 schema 遷移，直接沿用既有資料層。

新增書籤 toggle（星號圖示）：比對目前頁碼與既有書籤清單，行為比照 EPUB 既有的書籤 toggle 邏輯（有則移除、無則新增），資料模型使用既有的 `pdfPageIndex` 欄位，不需要新的資料層設計。本工單只需要完成 toggle 邏輯本身（可透過既有測試 seam 觸發驗證）；toggle 對應的 FAB 按鈕留給 Issue 8 統一接線。

### Acceptance criteria

- [x] 長按拖曳框選矩形的選取互動在新引擎上正確運作，選取範圍資料模型（頁碼＋兩種百分比矩形）語意與現行一致。
- [x] 雙頁模式下，選取矩形正確以「所在的單一頁面」為座標基準，不受另一頁存在與否影響；單/雙頁切換後既有劃線位置正確、不拉伸錯位。
- [x] 劃線/備註可正確新增、持久化、重新開書後正確還原顯示於對應頁面。
- [x] 書籤 toggle：目前頁有書籤時圖示狀態正確反映「已加入」，切換行為（新增/移除）正確寫入/刪除 `Bookmark`（`pdfPageIndex` 定位）。
- [x] 單元測試：`flutter test` 對多頁 fixture 驗證選取矩形座標換算（含雙頁情境）、劃線/備註持久化往返、書籤 toggle 邏輯。
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過（含既有測試零回歸）。

### Blocked by

- Issue 1

---

## Issue 5：目錄（TOC）解析與 UI（`BookTocItem` 抽象介面）

**Status:** ✅ 已完成並合併（2026-08-10，PR #127 合併至 `main`，commit `66ceab5`）

**合併前審查歷程**（三輪 `/superpowers:requesting-code-review`／`/superpowers:receiving-code-review` 循環，報告存於本機 `tmp/epic-24/review-issue-5-independent.md`，未進版控）：初輪發現 0 Critical／2 Important／4 Minor。Important #1（PDF 目錄跳轉測試斷言被移除，且留下「pdfrx 在測試環境中有點擊跳轉限制」的註解）經審查者在獨立暫存 worktree 實測證實這段主張是**假的**——tap／`Navigator.pop`／頁面跳轉在 `flutter test` 下皆真實可運作，只是退場動畫需要多等 500ms，屬於本 Epic 已在 Issue 4 出現過一次的「未經覆查的錯誤技術主張被合併」同類型問題。Important #2（`issues.md` 明確要求的 PDF 分頁籤殼層，`plan-issue-5.md` 規劃階段遺漏未納入）經人類確認後正式納入本工單範圍，補上 `TocBottomSheet` 的 `format` 參數＋`DefaultTabController`（章節目錄可用、縮圖/搜尋分頁預留佔位文字，EPUB 路徑零回歸）。過程中曾發生一次修正意外遺失——4 項已驗證修正（Important #1＋3 個 Minor）當時只存在於未提交的工作目錄異動，後續疊加分頁籤功能時被靜默覆蓋，經複審抓出後改為逐項獨立 commit 重新套用並確認進入 commit history。合併時 `flutter analyze` 乾淨、全專案 `flutter test` 1094/1094 通過，PDF 目錄跳轉測試重複執行 3 次穩定無間歇性失敗。

**依賴：** Issue 1。

**對應 User Stories（`spec.md`）：** 1, 2, 3

### What to build

新增一個格式無關的目錄項目抽象介面（`BookTocItem`：標題、定位點、子項清單、巢狀層級），EPUB 既有的目錄 Bottom Sheet UI 元件改為消費這個抽象介面，而非直接依賴 EPUB 專屬的目錄項目型別；PDF 端把 `pdfrx` 的大綱解析結果（標題、目的頁碼、子項層級）轉換為同一介面的實例。

本工單會異動 EPUB 既有程式碼（抽出抽象介面），範圍嚴格限定為「抽出介面、EPUB 行為保持逐位元組不變、PDF 提供新實作」，不對 EPUB 目錄既有互動行為做任何調整。

目錄項目點擊後的行為（跳轉、目前所在章節高亮、巢狀展開狀態）與 EPUB 既有目錄 Bottom Sheet 行為一致。目錄按鈕的啟用時機比照 EPUB 既有慣例：書籍尚未成功開啟、或目錄背景載入尚未完成前停用。本工單只需完成目錄資料解析與 Bottom Sheet 顯示邏輯本身；對應的 FAB 按鈕接線留給 Issue 8。

**PDF 目錄 Bottom Sheet 的 UI 入口決策（`spec.md` 審查回應）**：Issue 8 只收斂 6 顆 FAB，沒有獨立的「搜尋」「縮圖」按鈕位置——PDF 版本的目錄 Bottom Sheet 須設計為可容納分頁籤（章節目錄／縮圖／搜尋三個分頁），本工單先建立「章節目錄」分頁與承載分頁籤的殼層結構；縮圖分頁（Issue 7）、搜尋分頁（Issue 6）之後各自把內容掛進同一個殼層，三者共用同一顆「目錄」FAB 觸發。EPUB 目錄 Bottom Sheet 維持現行單一內容、不需要分頁籤（EPUB 沒有縮圖/搜尋功能）。

### Acceptance criteria

- [x] `BookTocItem` 抽象介面定義完成，EPUB 既有目錄 Bottom Sheet 改為消費該介面，EPUB 既有目錄相關測試全數維持通過（零回歸）。
- [x] PDF 端正確解析大綱（`loadOutline()`），轉換為 `BookTocItem` 樹狀結構，巢狀層級正確保留。
- [x] 點擊 PDF 目錄項目正確跳轉至對應頁面。
- [x] 目錄背景載入完成前，目錄相關互動正確停用（防呆）。
- [x] 無大綱的 PDF（例如掃描件）目錄為空清單時，UI 有合理呈現（非例外崩潰）。
- [x] 單元測試：`flutter test` 對含大綱的 fixture 驗證解析結果與跳轉行為；對既有 EPUB 目錄測試確認零回歸。
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過。
- [x] PDF 目錄 Bottom Sheet 分頁籤殼層（章節目錄／縮圖／搜尋）——原規劃階段遺漏，經人類確認納入本工單範圍後補上（見上方合併前審查歷程）。

### Blocked by

- Issue 1

---

## Issue 6：內文搜尋

**Status:** ✅ 已完成並合併（2026-08-10，PR #128 合併至 `main`，commit `645fdde`）

**合併前審查歷程**（`/superpowers:requesting-code-review` 獨立審查，報告存於本機 `tmp/epic-24/review-issue-6-independent.md`，未進版控；另有一份參考審查報告 `tmp/epic-24/code_review_issue_6.md` 作為對照輸入，非本審查作者所寫）：獨立驗證後確認參考報告宣稱的 Important #1（`_goToPdfSearchMatch` 於首筆結果按「上一個」，因 Dart `%` 對負數取模產生 `RangeError` 崩潰）為**誤判**——已用 `dart` 直譯器實測 `(0 + -1) % 5 == 4`，Dart 的 `%` 為 Euclidean modulo（對正除數恆傳回非負值），語意與 C/Java/JavaScript「符號跟隨被除數」不同，程式碼原樣沒有這個 bug。獨立審查另外發現參考報告未提及的問題：計畫 Task 6 Step 5 明確要求 3 則 `ReaderScreen` 端對端搜尋測試（找到結果並跳轉／循環導覽／查無結果），實際只落實 1 則，且計畫檔案已將全部 Step 標記為完成——這是本 Epic 第三次出現「未經覆查的錯誤/不完整主張被合併或標記完成」（第一次見 Issue 4，第二次見 Issue 5）。依報告補齊缺漏的 2 則測試後修正：補測試過程中額外發現，透過 `ReaderScreen` 的 `TocBottomSheet`（Modal Route）呼叫 `PdfReaderView.jumpToPage()` 時，reader footer 實際頁碼在測試環境下有不可靠的更新時序，即使搭配 `runAsync` 真實延遲等待數秒仍可能停在目標頁前一頁；已用獨立情境（裸 `PdfReaderView`，無 `ReaderScreen`/Modal 包裹）重現驗證 `jumpToPage()` 本身連續呼叫皆能正確落點，且證實**既有、已合併的 Issue 5 TOC 跳頁測試也有相同現象**（該測試從未真正斷言過頁碼，只斷言 Sheet 關閉），判定為與本工單邏輯無關的既有測試環境時序問題，非新增回歸；新增測試改為斷言不受此時序影響的搜尋面板計數器（`_pdfSearchStateNotifier` 驅動）。另同意參考報告 Minor 建議，`PdfSearchPanel` 補上 `textInputAction: TextInputAction.search`。合併時 `flutter analyze` 乾淨、全專案 `flutter test` 1124/1124 通過（較 Issue 5 基準 1094 增加 30 項，與計畫彙總數字一致）。

**依賴：** Issue 1、Issue 5（搜尋分頁掛載於 Issue 5 建立的目錄 Bottom Sheet 分頁籤殼層內，共用同一顆「目錄」FAB 觸發，見 Issue 5「UI 入口決策」）。

**對應 User Stories（`spec.md`）：** 4, 5, 6

### What to build

搜尋範圍限定單一已開啟 PDF 文件內（in-document search），與全書庫全文檢索（FTS5，Backlog，尚未開始）是不同功能，不整合。搜尋結果須支援：以高亮標示所有符合位置、可逐一跳轉至下一個/上一個符合結果。掃描件（無文字層）PDF 無法搜尋到內容——這是格式本身的限制，非實作缺陷，UI 上須有合理的空結果呈現。

UI 入口為 Issue 5 建立的目錄 Bottom Sheet「搜尋」分頁，不新增獨立按鈕（見 Issue 5「UI 入口決策」）。

### Acceptance criteria

- [x] 輸入關鍵字後，正確找出文件內所有符合位置並以高亮標示。
- [x] 「下一個/上一個」導覽正確依序跳轉至各符合位置對應頁面（跳轉本身經獨立審查於裸 `PdfReaderView` 情境下重現驗證正確；整合層級測試改以不受 Modal 場景既有時序影響的搜尋面板計數器斷言索引數學，見上方合併前審查歷程）。
- [x] 對無文字層的 PDF（掃描件）搜尋時，UI 顯示合理的「無結果」而非錯誤或無回應。
- [x] 搜尋分頁正確掛載於 Issue 5 的目錄 Bottom Sheet 殼層內，透過既有「目錄」FAB 開啟後可切換至此分頁。
- [x] 單元測試：`flutter test` 對含可搜尋文字的 fixture 驗證搜尋結果數量、位置、導覽行為。
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過。

### Blocked by

- Issue 1
- Issue 5

---

## Issue 7：頁碼縮圖（Thumbnails）

**Status:** ✅ 已完成並合併（2026-08-10，PR #129 合併至 `main`，commit `0d54a58`）

**合併前審查歷程**（`/superpowers:requesting-code-review` 一輪＋一輪複審，報告存於本機 `tmp/epic-24/review-issue-7.md`／`review-issue-7-followup.md`，未進版控）：第一輪審查 0 Critical／0 Important／5 Minor，判定可合併（Minor 項目：整合層級端對端測試遺漏一則邊界斷言、`_renderThumbnail()` 未防禦 `page.width == 0` 退化情境、縮圖快取不跨 Bottom Sheet 開合週期持久化、`GridView` 固定 `childAspectRatio` 未依實際頁面比例調整、新常數與 App Bar 常數混放）；作者針對 Minor 1 修復後（`reader_screen_test.dart` 補上 `pdf_thumbnail_tile_5 findsNothing` 斷言）請求複審，複審發現該修復本身因所用 fixture（`sample_multi_page.pdf`，僅 5 頁）頁數過少而成為恆真命題（index 5 本來就超出 `itemCount` 邊界，與「僅可視範圍延遲建構」的邏輯是否正確無關），未能真正提供整合層級的獨立證據——但「僅可視範圍渲染、不一次渲染全書」這項 Global Constraint 本身已由 Task 3 單元測試（`totalPages: 50` 情境，`expect(requested.length, lessThan(30))`）有效覆蓋，不構成合併阻礙，複審結論仍為可以合併。其餘 4 項 Minor 維持原狀（作者未表示要修復，原本即定性為非合併阻礙的建議性質項目）。合併時測試數量精確 +22（`PdfThumbnailCache` +7、`renderThumbnail()` +4、`PdfThumbnailPanel` +7、`TocBottomSheet` +2、`ReaderScreen` +2），與計畫彙總數字一致。

**依賴：** Issue 1、Issue 5（縮圖分頁掛載於 Issue 5 建立的目錄 Bottom Sheet 分頁籤殼層內，共用同一顆「目錄」FAB 觸發，見 Issue 5「UI 入口決策」）。

**對應 User Stories（`spec.md`）：** 7

### What to build

以頁碼列表/格狀呈現整本書每一頁的縮小預覽圖，點擊縮圖跳轉至對應頁面。縮圖產生方式須避免一次性渲染全書縮圖造成的效能/記憶體問題（可視範圍內才產生、有上限的快取策略）。滑出可視範圍外而被快取淘汰的縮圖影像資源須明確釋放（`dispose()`），避免大量頁數書籍快速捲動縮圖面板時發生記憶體洩漏（`spec.md` 審查回應）。

UI 入口為 Issue 5 建立的目錄 Bottom Sheet「縮圖」分頁，不新增獨立按鈕（見 Issue 5「UI 入口決策」）。

### Acceptance criteria

- [x] 縮圖面板正確顯示整本書頁碼縮圖，點擊後正確跳轉至對應頁面。
- [x] 縮圖僅於可視範圍內產生，不一次性渲染全書（單元測試以 `totalPages: 50` 驗證；整合層級端對端測試因 fixture 頁數過少而未能提供獨立證據，見上方合併前審查歷程，非合併阻礙）。
- [x] 縮圖分頁正確掛載於 Issue 5 的目錄 Bottom Sheet 殼層內，透過既有「目錄」FAB 開啟後可切換至此分頁。
- [x] 淘汰快取的縮圖資源正確釋放（`dispose()`），大量頁數書籍快速捲動不造成記憶體持續成長。
- [x] 單元測試：`flutter test` 驗證縮圖產生/快取/釋放邏輯（可透過可觀察的快取狀態或資源計數斷言，不需要真機記憶體量測）。
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過。

### Blocked by

- Issue 1
- Issue 5

---

## Issue 8：閱讀工具列 FAB 化（6 顆按鈕整合）

**Status:** ✅ 已完成並合併（2026-08-11，PR #130 → `main`，分支 `feature/epic-24-issue-8-fab`）

**實作與審查歷程**：依 `docs/epics/epic-24-pdf-engine-rebuild/plans/plan-issue-8.md`（Task 1-3）實作，規劃階段經 `AskUserQuestion` 確認兩項範圍決策：(a) Page Label（PDF 邏輯頁碼標籤，例如封面羅馬數字）因查證 `pdfrx` 公開 API 未暴露底層 PDFium 的 `FPDF_GetPageLabel`，本工單先做純數字頁碼、Page Label 移出範圍另立後續工單；(b) PDF 版 3×3 導覽熱區（NavZone）一併實作（新增 `_PdfNavZoneTapDetector`，比照 EPUB 既有 `_NavZoneTapDetector` 手勢隔離策略，刻意獨立複製不共用模組）。計畫文件經 `/superpowers:receiving-code-review` 兩輪審查修正（書籤快取初次載入時序缺口、`onPointerCancel` 防禦性清理）後定案。程式碼實作完成後經**兩輪獨立程式碼審查**（`tmp/epic-24/code_review_issue_8.md`／`tmp/epic-24/review-code-issue-8.md`），第二輪發現並修復：**Critical**——`library_screen_test.dart`／`integration_test/` 多檔案因按鈕 Key 改名（`reader_notes_button`→`reader_pdf_notes_button`、`reader_layout_settings_button`→`reader_pdf_settings_button`）未同步更新導致既有 PDF 測試斷裂，其中 `library_screen_test.dart` 兩則另有更深層問題（FAB 與 `PdfReaderView` 同層疊放於 Stack，非同步渲染時序下 `PdfReaderView` 版面大小為 0 導致 `tester.tap()` 座標命中失敗，改採分支既有先例直接呼叫 `.onPressed!()` 繞過）；**Important**——`_PdfNavZoneTapDetector` 改用 `package:clock` 的 `clock.now()` 取代 `SchedulerBinding.currentSystemFrameTimeStamp` 量測按壓時長，修正正式裝置上靜止區域長按可能誤判為快速點擊的風險，同時維持 `flutter_test` FakeAsync 相容性。合併時 `flutter test` 1152/1152 全數通過、`flutter analyze` 乾淨。

**依賴：** Issue 1、3（版面設定面板需要濾鏡控制項）、4（書籤 toggle）、5（目錄）。

**對應 User Stories（`spec.md`）：** 17, 18, 19, 20, 21

### What to build

PDF 頂部工具列（現行傳統 `AppBar`，含系統預設返回箭頭 + 版面設定/筆記兩個按鈕）改為浮動圓形按鈕（FAB），視覺與位置比照 EPUB 既有樣式，重用既有的、跟隨 `Theme.of(context)` 且已考慮電子紙硬體對比的按鈕底色/圖示色邏輯。PDF 最終達到與 EPUB 相同的 6 顆 FAB 按鈕：返回／目錄／版面設定／書籤 toggle／筆記／進度-跳頁。

現行「頁面導覽」（目前頁/總頁數/跳頁）從常駐於畫面底部的既有元件，改為浮動「進度/跳頁」按鈕觸發的 Bottom Sheet 呈現，不再擠壓可視閱讀區域高度，行為比照 EPUB 既有的對應機制。頁碼顯示採雙顯示模式：若 PDF 提供邏輯頁碼標籤（Page Label，例如封面羅馬數字），與實體頁碼/總頁數並列顯示（例如「iii (3/150)」）；若無邏輯頁碼標籤，回退為現行純數字頁碼顯示。跳頁/進度換算邏輯一律以絕對 0-indexed 頁碼為運算基準，不依賴頁碼標籤格式。

沉浸模式（介面收合/展開）行為與 EPUB 既有機制一致。現行 PDF 頂部工具列對應的原生 method channel 契約與其 Dart 端 `AppBar` 相關程式碼隨本工單一併退場。

### Acceptance criteria

- [x] PDF 閱讀畫面顯示 6 顆浮動圓形按鈕（返回／目錄／版面設定／書籤 toggle／筆記／進度-跳頁），底色/圖示色正確跟隨 `Theme.of(context)`。
- [x] 各按鈕功能正確：返回離開閱讀畫面、目錄開啟 Issue 5 的目錄 Bottom Sheet、版面設定開啟含 Issue 3 濾鏡控制項的設定面板、書籤 toggle 正確反映/切換 Issue 4 的書籤狀態、筆記開啟既有筆記面板、進度-跳頁開啟含頁碼顯示與跳頁功能的 Bottom Sheet。
- [x] 跳頁邏輯以絕對頁碼運算。**範圍調整（規劃階段人類決策，見上方實作歷程）**：Page Label 雙顯示（例如「iii (3/150)」）因 `pdfrx` 未暴露對應 API，本工單僅實作純數字頁碼顯示，未做雙顯示；Page Label 移出本工單範圍，待後續另立工單追蹤。
- [x] 沉浸模式收合/展開行為與 EPUB 既有機制一致。
- [x] 現行 PDF `AppBar` 與對應原生 method channel 契約已完全移除，無殘留死碼。
- [x] 單元測試：`flutter test` 驗證 6 顆按鈕的顏色/啟用條件/點擊行為，比照既有 EPUB FAB 相關測試的既有模式。
- [x] `flutter analyze` 乾淨、全專案 `flutter test` 全數通過（1152/1152）。

### Blocked by

- Issue 1
- Issue 3
- Issue 4
- Issue 5

---

## Issue 9-11：真機使用回報後續修正（`/diagnose` 第一輪，PDF 相關）

**背景（2026-08-11）：** 使用者於真機回報 6 項問題（劃線拖曳頁面亂跳附截圖、直排橫排切換後翻頁異常、頁次精準度、PDF 畫線工具列不會隱藏、無法手動關閉畫線工具、PDF 換頁動畫選項）。經 `/diagnose` 逐項查證，其中 4 項為 PDF 專屬問題，歸入本 Epic；EPUB 專屬的 2 項（直排橫排切換翻頁異常、頁次精準度）另立於 `epic-18-reader-device-qa` Issue 45-46。本輪僅完成程式碼層級查證與根因假設，**尚未實作修復**——診斷過程見下方各 Issue 內文，未另外產出獨立 `reviews/bugfix-repro.md`。

**追加回報（2026-08-11 同日）：** 使用者補充 Issue 9「劃線拖曳頁面亂跳」**流式 EPUB 也會發生**，經查證是與本 Issue 完全不同的根因（本 Issue 是 Flutter 手勢競技場層級的衝突；EPUB 是 WebView／`paginator.js` 內部觸控事件時序競賽），已另立 `epic-18-reader-device-qa` **Issue 47** 獨立追蹤，兩者程式碼修復互相獨立、不共用實作。

### Issue 9：PDF 劃線拖曳選取時與 `PdfViewer` 內建 pan/zoom 手勢衝突（頁面隨手指移動亂跳）

**Status:** ready-for-agent

**同症狀跨格式提醒**：使用者已確認流式 EPUB 也有同一種「拖曳選取時頁面亂跳」症狀，但根因不同、另立 `epic-18-reader-device-qa` Issue 47 追蹤，本 Issue 僅處理 PDF 路徑。

**背景**：使用者長按拖曳劃線時，頁面內容會跟著亂跳（附截圖 `tmp/images/畫線亂跳.jpg`）——不是換頁，而是劃線選取範圍突然往前或往後跳一大塊，越靠近畫面右側越嚴重。

**根因假設（高信心，已查證套件原始碼，未在真機實際重現）**：`_buildSelectionGestureLayer`（`app/lib/reader/pdf_reader_view.dart:1058`）用標準 `GestureDetector`（`onLongPressStart`/`onLongPressMoveUpdate`）實作拖曳框選，會進入 Flutter 手勢競技場。但 `pdfrx` 套件的 `PdfViewer`（`pdfrx-2.4.7/lib/src/widgets/pdf_viewer.dart:609-611`）用 `Listener`（`onPointerDown`/`onPointerMove`）包住內部 `InteractiveViewer` 驅動平移/縮放——`Listener` 完全不參與手勢競技場，代表**不論我方的 `LongPressGestureRecognizer` 是否已經「贏得」該次觸控序列，`PdfViewer` 都會同時、無條件收到同一組原始 pointer 事件並據此平移/縮放內容**。使用者長按拖曳畫線的同時，底層頁面很可能被同時判讀成一次平移手勢而位移，導致：(a) 畫面內容隨手指移動位移；(b) 我方疊加層的 `pageRectInViewer`（決定選取框視覺位置的依據）跟著改變，使用者觀察到選取範圍「跳一大塊」。「越靠近右側越嚴重」與 `InteractiveViewer` 邊界回彈或雙頁模式頁面邊界行為在該側較敏感一致，但此點尚未實機驗證。

**建議修復方向**：`PdfViewerParams` 已提供 `panEnabled`/`scaleEnabled`（`pdfrx-2.4.7/lib/src/widgets/pdf_viewer_params.dart:55-56`）。`PdfReaderView` 建構 `PdfViewer` 時依 `_selectionDrag != null` 動態傳入 `panEnabled: false, scaleEnabled: false`，框選拖曳進行中暫時關閉底層平移/縮放，結束/取消後恢復；需真機驗證修復後長按拖曳不再觸發底層平移，且不影響一般雙指縮放/單指平移的既有手感。

### Issue 10：PDF 劃線工具列缺乏清除機制（選色/換頁後不會自動隱藏、也無手動關閉入口）

**Status:** ready-for-agent

**背景**：使用者回報兩項相關問題：(a) PDF 畫線選完顏色後，浮動工具列（`AnnotationToolbar`）不會隱藏，即使換頁後仍然存在；(b) 沒有任何步驟能讓使用者手動關閉這個工具列。

**根因（高信心，已完整查證程式碼）**：
1. `_handlePdfHighlightStyleSelected`（`app/lib/screens/reader_screen.dart:1345`）新增劃線後不清空 `_currentPdfSelection`（對照 `_handlePdfNotePressed` 新增備註後有明確清空，同檔案 line 1378-1381）。**這是刻意的既有設計**（見本 Epic Issue 4 完成敘述：「選色後 Toolbar 刻意保持開啟以便續加備註（與 EPUB 既有行為對稱，非 bug）」），EPUB 的 `_handleHighlightStyleSelected`（line 1176）同樣不清空 `_currentSelection`，兩者行為對稱，非新問題。
2. 但「換頁後仍然存在」這點兩者**不對稱**：EPUB 選取狀態能在換頁後自然消失，是因為 WebView 原生瀏覽器語意——切換頁面時瀏覽器自動清空 `window.getSelection()`，觸發 JS `selectionchange`，經橋接呼叫 `onSelectionCleared`（`_handleSelectionCleared`，line 1152）。PDF 的框選狀態是純 Dart 端矩形選取，`_handleZoneAction`（line 2353）的 `previousPage`/`nextPage` 分支完全沒有呼叫 `_handlePdfSelectionCanceled()`／清空 `_currentPdfSelection` 的邏輯——PDF 架構上就沒有等價於「換頁自動清除選取」的訊號來源。
3. 「無法手動關閉」對 EPUB／PDF 皆成立：`AnnotationToolbar`（`app/lib/screens/annotation_toolbar.dart`）只有 5 顆按鈕（3 色螢光筆＋底線＋備註），完全沒有關閉／取消按鈕。EPUB 使用者能透過點擊 WebView 內文字以外區域觸發瀏覽器原生取消選取，間接達到相同效果；PDF 的 `_buildSelectionGestureLayer` 只註冊 `onLongPress*` 系列回呼，沒有任何「點擊空白處取消選取」邏輯，使用者完全沒有管道能主動取消已完成的框選。

**建議修復方向**：
- (a) `_handleZoneAction` 的 PDF `previousPage`/`nextPage` 分支呼叫 `PdfReaderView.previousPage`/`nextPage` 後一併呼叫 `_handlePdfSelectionCanceled()`，換頁即清空選取與工具列。
- (b) 在 PDF 閱讀畫面新增「點擊空白處取消目前選取」手勢，或在 `AnnotationToolbar` 新增明確關閉按鈕（若採後者，需一併決定 EPUB 是否同步補上，因為 EPUB 目前也沒有明確關閉按鈕，只是有替代手段）。

### Issue 11：PDF 新增「換頁動畫」選項（滑動／無）

**Status:** ready-for-agent

**背景**：使用者要求 PDF 版面設定新增一個選項：換頁動畫 (1) 滑動 (2) 無。

**現況查證（高信心）**：`PdfReaderView.nextPage`/`previousPage`（`app/lib/reader/pdf_reader_view.dart:132-140`）底層呼叫 `pdfrx` 的 `PdfViewerController.goToPage()`：

```dart
Future<void> goToPage({
  required int pageNumber,
  PdfPageAnchor? anchor,
  Duration duration = const Duration(milliseconds: 200),
})
```

（`pdfrx-2.4.7/lib/src/widgets/pdf_viewer.dart:4156-4160`）——目前呼叫端（`pdf_reader_view.dart:561`／`:577`）皆使用預設 200ms 動畫（「滑動」效果）。`duration: Duration.zero` 即可達到「無動畫、瞬間跳頁」效果，`pdfrx` API 已原生支援，不需額外實作換頁動畫本身。

**建議修復方向**：新增 `PdfPageTurnAnimation`（`slide`/`none`）偏好欄位，比照既有 `dualPageMode`／`pdfCropMode` 等偏好欄位的貫穿模式（`ReaderPrefs` → `ResolvedPreferences` → `PdfReaderView` 建構參數），在 `pdf_reader_view.dart` 呼叫 `_controller.goToPage()` 的兩處依此設定傳入 `duration: Duration.zero` 或預設 200ms；並在 `PdfSettingsSheet` 新增對應 UI 選項。
