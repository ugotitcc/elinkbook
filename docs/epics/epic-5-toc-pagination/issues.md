# Epic 5 — 目錄與頁碼：工單清單 (Issues)

依 `spec.md`（搭配 `design.md`，`/grill-with-docs` Discovery + `/superpowers:requesting-code-review` 審查修正）拆解出的細粒度垂直切片工單。Issue 1（PDF 頁碼/跳頁）與 Issue 2（本機位置記憶）可立即平行開始；Issue 3 依賴 Issue 1；Issue 4 依賴 Issue 3；Issue 5 依賴 Issue 1、Issue 4。

---

## Issue 1：PDF 頁碼顯示 + 跳頁

**Status:** ✅ 已完成

**依賴：** 無（起始工單，可與 Issue 2 平行）

**What to build：**

在 PDF 閱讀畫面新增頁尾元件，顯示閱讀進度（百分比）與目前頁碼／總頁數，沿用既有已完備的精確頁碼基礎設施（現有的頁索引／總頁數追蹤，不需新增估算邏輯）。同時建立跳頁互動元件——輸入框與滑桿雙向同步：拖曳滑桿即時更新輸入框顯示的數字，輸入框確認輸入後同步更新滑桿位置，任一方觸發最終跳頁動作。此元件須設計為可被後續工單（Issue 3）複用於 EPUB，不要寫死成 PDF 專屬。

**介面契約（審查修正）**：跳頁 UI 元件須為與格式無關的通用元件，只接收以下最小屬性，不得接收任何 PDF 專屬的 controller 或底層讀取器物件：
- `currentPage`（int，目前頁碼）
- `totalPages`（int，總頁數）
- `onPageChanged`（`ValueChanged<int>`，使用者確認跳頁時的回呼）

呼叫端（PDF 專屬的頁碼取得/跳頁邏輯）負責把這三個值餵給元件、並在 `onPageChanged` 回呼中執行實際的原生跳頁呼叫，元件本身不知道呼叫端是 PDF 還是 EPUB。

本工單完成時，頁尾為一律顯示（顯示／隱藏開關留給 Issue 5），且僅套用於 PDF；EPUB 讀取畫面本工單不動它。

**單元測試要求：**

- widget test：頁尾正確顯示目前頁碼／總頁數／進度百分比文字，數值與底層讀取器回報的頁碼一致。
- widget test：輸入框輸入合法數字並確認後，觸發跳頁至該頁；輸入超出範圍（負數、大於總頁數）需有合理防呆（不觸發跳頁或箝制在合法範圍內）。
- widget test：拖曳滑桿時輸入框顯示數字即時同步更新；輸入框輸入並確認後滑桿位置同步更新。
- 既有涉及 PDF 閱讀畫面的測試（`ReaderScreen`／`PdfReaderView` 既有測試）須維持全數通過，確認本工單未影響既有翻頁／設定功能。

**驗收標準：**

- [x] PDF 閱讀畫面底部顯示頁尾，含進度百分比與「目前頁碼／總頁數」
- [x] 頁尾提供跳頁輸入框，輸入合法頁碼並確認後正確跳轉
- [x] 頁尾提供跳頁滑桿，拖曳後正確跳轉，且與輸入框數字雙向同步
- [x] 跳頁 UI 元件只接收 `currentPage`／`totalPages`／`onPageChanged` 三個與格式無關的屬性，不含任何 PDF 專屬的頁碼取得邏輯或 controller 寫死在元件內部（審查修正）
- [x] 上述測試皆通過，`flutter analyze` 乾淨，既有測試無回歸
- [x] 真機整合測試涵蓋跳頁的實際渲染結果（跳轉後畫面確實顯示目標頁）——已於裝置上執行 `integration_test/reader_footer_test.dart`，`All tests passed!`

**Blocked by：** None - can start immediately

---

## Issue 2：本機閱讀位置記憶（EPUB + PDF）

**Status:** ✅ 已完成並合併（PR #45，`feat/epic-5-issue2-reading-position` → `main`）——含程式碼審查修正 C1（FXL 位置記憶改用 `currentLocator` StateFlow）／C2（補上 EPUB reflowable 端到端整合測試）／C3（恢復 `onPageLoaded` 原生觸發路徑；另外反編譯確認並修正一個 `epic-16-dual-page` 既有的橫排雙頁 FXL 排版問題——中縫空白與 RTL 頁序顛倒，經真機驗證有效，一併納入本次合併）／I2（EPUB 進度 `null` 防呆）／M1／M2。真機測試（EPUB／PDF 位置記憶、FXL 雙頁排版）皆已由人類與 `adb` 直接操作雙重驗證。

**依賴：** 無（可與 Issue 1 平行）

**What to build：**

在書籍資料模型新增「上次閱讀位置」欄位：EPUB 用 Readium 定位資訊的序列化字串，PDF 用頁索引；並活化既有長期恆為 0、從未被寫入過的閱讀進度欄位。資料庫須有對應的 schema migration（比照既有偏好設定資料表的累加式升級模式：版本判斷用 `if` 而非互斥 `if/else if`，確保裝置從任何舊版本跳級升級時不遺漏任何一段遷移）。

開啟書籍時，若該書已有既有位置資料，原生端須以此為起始位置渲染（而非固定從頭開始）。寫入時機：使用者離開閱讀畫面時，以及 App 進入背景時，各觸發一次寫入——刻意不逐次翻頁／捲動即時寫入，避免捲動翻頁模式下頻繁寫庫。

此為單書本機資料，不涉及帳號或雲端請求；位置資料須存放於書籍本身的資料模型，而非既有的版面偏好設定資料模型（域模型考量：閱讀位置是系統持續追蹤的「狀態」，非使用者主動選擇的「顯示設定」，兩者不應混在同一組欄位裡）。

**單元測試要求：**

- 純 Dart unit test：書籍資料模型新欄位的序列化／反序列化 round-trip。
- repository 層測試：既有裝置跳級升級到最新 schema 版本時，新欄位正確補上、既有書籍資料不受影響（比照既有偏好設定資料表 migration 測試的既有先例）。
- widget/整合層測試：模擬「開書 → 移動到某個位置 → 觸發離開／背景生命週期事件 → 驗證位置已寫入資料庫」的流程。

**驗收標準：**

- [x] 書籍資料模型新增位置相關欄位，既有恆為 0 的進度欄位正式活化
- [x] 資料庫 schema migration 正確處理跳版升級情境，不影響既有書籍資料
- [x] 開啟已有位置記錄的書籍時，自動跳轉至上次位置（EPUB／PDF 皆須驗證）
- [x] 離開閱讀畫面、App 進入背景兩個時機皆正確觸發寫入
- [x] 上述測試皆通過，`flutter analyze` 乾淨
- [x] 真機整合測試涵蓋「開書、翻頁、離開、重新開啟同一本書，確認回到離開前位置」的端到端流程（EPUB 與 PDF 各一次）

**Blocked by：** None - can start immediately

---

## Issue 3：EPUB 頁碼顯示 + 跳頁（含全書字元數背景計算基礎設施）

**Status:** ✅ 已完成並合併（PR #46，`feature/epic-5-issue3-toc-pagination` → `main`）——依 `plans/plan-issue-3.md` 8 個 Task 實作：原生端 `EpubReaderView.kt` 新增背景協程（`Dispatchers.IO`）走訪 `Publication.readingOrder`，透過純 Kotlin `EpubCharacterCounter` 計算全書字元數並快取於 `books.totalCharacterCount`（累加式 schema migration 至 version 6）；Dart 端純函式 `EpubPageEstimator` 依版面參數換算估計總頁數／目前頁碼；跳頁沿用 Readium 既有 `Publication.positions()` 新增 `jumpToProgression` method channel 指令；`ReaderScreen` 複用 Issue 1 的格式無關 `ReaderFooter` 元件，使其也能顯示 EPUB 估算頁碼與跳頁。經計畫審查（Critical：Kotlin non-local `continue` 編譯錯誤；Important：原生 `Resource` 未關閉洩漏檔案描述符；已對照 `BookMetadataChannel.kt` 既有先例修正並簡化/移除原本的反編譯驗證 Task）與分支程式碼審查（Critical：Task 8 真機整合測試僅手動跑過即刪除、未入版控；Important：第一版 `jumpToProgression()` 有實際編譯錯誤〔第二個 commit 修正〕、版面設定重算測試被靜默替換成繞過 Bottom Sheet 互動的較弱版本〔查明真正根因為漏呼叫 `onPageRendered()` 與連續點擊未逐次 `pump()`，非原註解宣稱的 viewport 限制〕）兩輪修正；`flutter test`（全專案 302 個）全過、`flutter analyze` 乾淨、原生 JUnit（`EpubCharacterCounterTest`）全過、真機整合測試（`3CEF42ECD491687`，Android 15）`All tests passed!`（2/2，涵蓋大型 EPUB 開書不卡頓、快取重用、跳頁後畫面確實顯示目標頁）。

**依賴：** Issue 1（複用其頁尾／跳頁 UI 元件，不重新實作）

**What to build：**

為流式 EPUB 建立模擬分頁能力。原生端須在背景執行緒（不得阻塞主執行緒，大書同步計算有 ANR 風險）一次性走訪全書內容加總字元數，計算結果快取於書籍資料模型中的新欄位（含對應 schema migration），僅在該書首次開啟、尚無快取值時才觸發計算，之後每次開書直接讀取快取。

Dart 端依目前生效的版面參數（字體大小、行距、段落間距、邊距、排版方向）估算「每螢幕可容納字元數」，換算出估計總頁數；目前頁碼由書籍引擎提供的全書閱讀進度比例換算而得。任一版面參數變動時須立即重新計算，維持估算值與實際排版狀態一致。

把估算出的頁碼／總頁數接上 Issue 1 建立的頁尾與跳頁 UI 元件，使其也能在 EPUB 上運作——UI 元件本身不須重新實作，只需接上 EPUB 專屬的頁碼資料來源。

同時清理既有的、反解析確認過從未被實際觸發過的分頁回報死程式碼（既有的一個永遠不會被呼叫的分頁監聽覆寫方法），避免死程式碼與本工單新增的正式機制並存造成日後維護混淆。

明確聲明頁碼為模擬估算值，非逐頁精確值。

**單元測試要求：**

- 純 Dart unit test：估算演算法本身（給定字元數、版面參數，驗證估算總頁數與目前頁碼的計算邏輯正確）。
- 原生端單元測試（純邏輯、不需真機，審查修正補上具體慣例）：**先確認**字元加總邏輯是否能抽出為不依賴 Android／Readium 執行環境的無狀態純 Kotlin 函式（走訪 `Publication.readingOrder` 逐一取得 resource 內容涉及 Readium 的 `Resource` API，不確定能否完全脫離真機/模擬器環境，不像 `PdfImageProcessor` 單純是數學運算）。**若可行**，比照專案既有慣例（`PdfImageProcessor`／`EpubFxlScaler` 先例）以 JUnit 撰寫，測試檔放在 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/`，以 `./gradlew :app:testDebugUnitTest` 執行；**若不可行**（必須依賴真實 Readium `Publication` 物件），改以 `integration_test` 涵蓋，於工單完成說明中明確記錄採用哪一種、理由為何。
- widget test：版面設定（字體大小／行距／邊距等）變動時，觸發估算重新計算並反映到頁尾顯示。
- 整合層測試：驗證背景計算不阻塞主執行緒（例如開書後畫面立即可互動，計算結果延後才顯示，不會卡住載入流程）。

**驗收標準：**

- [x] 開啟 EPUB 後，頁尾顯示估算的「目前頁碼／總頁數」
- [x] 全書字元數計算於背景執行緒進行，開書當下畫面不卡頓
- [x] 全書字元數計算結果快取，同一本書第二次開啟不重新計算
- [x] 版面設定變動後，估算頁數／目前頁碼即時重新計算並反映
- [x] EPUB 可透過 Issue 1 的跳頁輸入框／滑桿正確跳轉
- [x] 既有從未被呼叫過的分頁回報死程式碼已清理或替換（查證確認已於 Issue 2 的 C3 審查修正 commit `fe9827a` 移除，本工單不需重複動作）
- [x] 上述測試皆通過，`flutter analyze` 乾淨，既有測試無回歸
- [x] 真機整合測試涵蓋大型 EPUB 素材開書不卡頓、跳頁後畫面確實顯示目標位置

**Blocked by：** Issue 1（已完成）

---

## Issue 4：EPUB 目錄（TOC）樹狀清單 + 跳轉 + 估算頁碼顯示

**Status:** ✅ 已完成並合併（PR #47，`feature/epic-5-issue4-toc-pagination` → `main`）——依 `plans/plan-issue-4.md` 6 個 Task 實作：原生端 `EpubReaderView.kt` 新增 `getTableOfContents`（一次性讀取 `Publication.tableOfContents`，透過 `Publication.locatorFromLink(Link)`〔已反編譯 `readium-shared:3.3.0` 確認存在，解決 design.md 原列為已知風險的不確定性〕為每個節點建構含錨點精度的 Locator，頁碼估算優先取用 Locator 自身 `totalProgression`，缺漏時以 O(1) `positionsMap` 查表比對 `Publication.positions()` 作為近似值）與 `jumpToLocator`（同步呼叫 `Navigator.go()`，落實 FR-08 的 200ms 時限）；Dart 端新增 `TocEntry`／`TocNavigator`（純函式，找出目前章節在樹中的祖先路徑，決定預設展開層級與高亮）與 `TocBottomSheet`（`_FlatTocRow` 攤平清單 + `ListView.builder` 延遲渲染，獨立 `ValueNotifier<int?>` 讓已開啟的目錄能在字元數背景計算完成當下即時更新頁碼）；`ReaderScreen` 新增「目錄」AppBar 按鈕，僅流式 EPUB 顯示（PDF／固定版面 FXL 皆不顯示）。經計畫審查（Critical：`node.progression` 為 `null` 時頁碼誤植為第 1 頁；Important：`buildTocEntries` 的 O(N×M) 線性搜尋、`TocBottomSheet` 缺乏延遲載入；Minor：`getTableOfContents` 缺少 `isDisposed` 防護）與分支程式碼審查（Important：目錄按鈕的啟用時機未與背景抓取完成同步，存在使用者點擊到空白 Bottom Sheet、且無法與「本書真的沒有目錄」區分的競速窗口，已新增 `_tocLoaded` 旗標修正並補上真機整合測試對應等待邏輯；Minor：整合測試檔名與既有 `epub_` 前綴慣例不符，已重新命名）兩輪修正；`flutter test`（全專案 323 個）全過、`flutter analyze` 乾淨、真機整合測試（`3CEF42ECD491687`，Android 15）`All tests passed!`（涵蓋開啟真實多章節 EPUB、展開/收起目錄、點選跳轉的端到端流程）。

**依賴：** Issue 3（目錄項目頁碼顯示需要頁碼估算邏輯已可用，含計算未完成時的降級處理）

**What to build：**

為流式 EPUB 讀取書籍引擎提供的目錄樹狀結構（保留完整巢狀階層，不攤平），並以可展開／收起的層級樹狀清單呈現，比照專案既有 Bottom Sheet 慣例開啟。當前章節所屬層級預設展開，其餘收起；當前章節項目需視覺高亮。

每個目錄項目除標題外，須顯示估算頁碼（沿用 Issue 3 的估算邏輯）。若使用者在全書字元數背景計算尚未完成前就開啟目錄，頁碼區塊須顯示佔位符（例如省略號或小型載入指示）；標題與層級結構本身不受此影響、可立即顯示；背景計算完成後觸發重繪，頁碼補上實際估算值。

點選任一目錄項目後，須於 200ms 內跳轉至該章節起始位置。

PDF 格式下，目錄入口完全不顯示（不是顯示後出現空狀態）——沿用既有依格式動態決定可用功能入口的既有模式，不新增第二套渲染路徑。

**單元測試要求：**

- widget test：目錄 Bottom Sheet 正確渲染多層級結構，展開／收起互動正確；當前章節項目正確高亮。
- widget test：點選目錄項目觸發跳轉呼叫（斷言呼叫參數，不需真機驗證實際渲染結果）。
- widget test：全書字元數尚未計算完成時，目錄項目頁碼顯示佔位符；計算完成事件觸發後，頁碼正確替換為估算值。
- widget test：PDF 格式下，目錄入口按鈕不存在（`findsNothing`）。

**驗收標準：**

- [x] EPUB 閱讀畫面出現目錄入口，點擊開啟樹狀目錄清單
- [x] 目錄正確反映書籍的多層級章節結構，可展開／收起
- [x] 當前章節於目錄中正確高亮
- [x] 每個目錄項目顯示標題與估算頁碼；計算未完成時顯示佔位符，完成後正確更新
- [x] 點選目錄項目後於 200ms 內跳轉至正確位置（真機量測；`jumpToLocator` 同步呼叫，不透過背景協程分派）
- [x] PDF 閱讀畫面完全不出現目錄入口
- [x] 上述測試皆通過，`flutter analyze` 乾淨
- [x] 真機整合測試涵蓋開啟真實多章節 EPUB、展開/收起目錄、點選跳轉的端到端流程

**Blocked by：** Issue 3（已完成）

---

## Issue 5：頁首／頁尾顯示切換設定

**Status:** ready-for-agent

**依賴：** Issue 1（頁尾元件已存在）、Issue 4（目錄已存在，供頁首點擊展開）

**What to build：**

在版面偏好設定資料模型新增頁首／頁尾各自獨立的顯示/隱藏欄位（含對應 schema migration），預設皆為顯示，單書持久化（比照既有版面偏好設定的持久化模式）。**Migration 須維持累加式版本判斷**（`if (oldVersion < N)`，非互斥 `if/else if`，審查修正，比照 Issue 2/3 的既有原則），確保裝置從任何舊版本跳級升級時，本工單新增的欄位遷移不會被跳過。

頁首開啟時取代現有的 App 頂部標題列——標題區改為顯示目前章節名稱，可點擊展開 Issue 4 建立的目錄清單；既有的版面設定入口維持可用。頁首關閉時回到現行的靜態標題列。

頁尾比照同一套顯示/隱藏開關機制，接上 Issue 1（PDF）與 Issue 3（EPUB）已建立的頁尾元件——開啟時顯示，關閉時完全不顯示（不佔版面空間）。

頁首與頁尾皆僅適用流式 EPUB 與 PDF，固定版面（漫畫）完全不套用此功能，維持既有的浮動控制系統不變。

**單元測試要求：**

- widget test：頁首顯示開關開啟時，AppBar 被取代為顯示章節名稱的頁首；關閉時回到現行靜態標題 AppBar。
- widget test：點擊頁首的章節名稱區域，正確觸發開啟目錄清單（呼叫 Issue 4 建立的元件）。
- widget test：頁尾顯示開關獨立於頁首開關運作，任一開關的變動不影響另一個。
- widget test：固定版面（FXL）EPUB 開書後，頁首/頁尾皆不出現，既有浮動控制系統（返回鍵/設定鍵/三欄熱區）不受影響。
- 既有涉及固定版面既有測試（`epub_reader_view_test.dart`／`reader_screen_test.dart` 相關既有案例）須維持全數通過，確認本工單未影響固定版面既有行為。

**驗收標準：**

- [ ] 版面設定新增「顯示頁首」「顯示頁尾」兩個獨立開關，預設皆開啟
- [ ] 開啟頁首時，AppBar 正確被取代為章節名稱列，點擊可展開目錄
- [ ] 關閉頁首時，正確回到現行靜態標題 AppBar
- [ ] 頁尾顯示/隱藏正確反映開關狀態，且與頁首開關互不影響
- [ ] 固定版面（FXL）EPUB 完全不受本功能影響，既有浮動控制系統運作正常
- [ ] 上述測試皆通過，`flutter analyze` 乾淨，既有測試無回歸
- [ ] 真機整合測試涵蓋流式 EPUB／PDF 切換頁首頁尾開關的端到端行為

**Blocked by：** Issue 1（已完成）、Issue 4（已完成，可開始）

---

## 審查修正紀錄（`tmp/epic-5/reviews/issues-review.md`）

- **Important（部分不採納）**：審查建議把 Issue 2、Issue 3 的 `books` 表 schema 變更合併成同一次 migration，避免短期內連續遞增版本號。查證後不採納合併——這個專案既有慣例（`book_reader_prefs` 表過去在不同 Epic/Issue 間，PDF 欄位、雙頁欄位分別各自獨立遞增 schema version）已多次示範「多個獨立工單各自遞增版本」是正常模式，累加式 `if (oldVersion < N)` 機制本來就是為此設計；合併 migration 會讓 Issue 2 無法獨立於 Issue 3 完成合併，破壞刻意設計的垂直切片獨立性（Issue 2 目前對 Issue 3 無相依）。**採納的部分**：「須維持累加式版本判斷、避免跳級升級遺漏遷移」的提醒已於 Issue 2/3 寫明，Issue 5（也異動 schema）先前漏寫，已補上。
- **Important（確認屬實，已修正）**：Issue 1 的跳頁 UI 元件缺乏明確介面契約，有被實作者寫死成 PDF 專屬的風險。已補上具體介面契約（`currentPage`／`totalPages`／`onPageChanged` 三個與格式無關的屬性）。
- **Minor（確認屬實，已修正，保留原有但書）**：Issue 3 原生端單元測試已補上具體慣例（JUnit、`app/android/app/src/test/kotlin/cc/ugotit/elinkbook/`、`./gradlew :app:testDebugUnitTest`），但保留「先確認字元加總邏輯是否真能抽離為不依賴 Readium 執行環境的純函式」的但書——與 `PdfImageProcessor` 單純數學運算不同，此處涉及走訪 `Publication.readingOrder` 的 Resource API，若不可行則改以 `integration_test` 涵蓋。
