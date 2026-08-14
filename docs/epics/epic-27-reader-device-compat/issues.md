# Epic 27 — 裝置相容性強化：工單清單 (Issues)

依使用者於 Mobiscribe WAVE 真機回報的兩項問題，2026-08-13 以 `/diagnose` 查證後立案。兩者皆為既有邏輯的行為修正，不涉及新增介面/型別、無架構異動，依 `epic-26-architecture-hardening` 先例跳過正式 `spec.md`，直接進入本工單清單。診斷過程與程式碼證據見 `reviews/bugfix-repro.md`。

---

## Issue 1：EPUB 載入中點擊左側熱區導致崩潰畫面（loading 狀態缺乏點擊防呆）

**Status:** ✅ 已完成並合併回 `main`（PR [#147](https://git.jigong.org/huthief/elinkBook/pulls/147)，分支 `epic-27-issue1-loading-guard`，2 個 commit：實作＋計畫勾選收尾）。程式碼審查（本機審查報告，依專案慣例不進版控）結論為可以合併——0 Critical／0 Important，僅 2 項 Minor（真機驗證已於 2026-08-14 在 Mobiscribe WAVE 完成，確認不再出現崩潰畫面；既有註解掛載位置為延續既有慣例，非本次引入的新問題）。全專案 `flutter analyze` 乾淨、`flutter test` 零回歸通過。

**依賴：** 無

**來源：** 使用者於 Mobiscribe WAVE 真機回報（附截圖 `tmp/images/MobiscribeWave/開啟書籍中點擊左邊螢幕出現ERROR.jpg`／`...ERROR_LOG.jpg`），2026-08-13 `/diagnose` 確認根因，完整診斷見 `reviews/bugfix-repro.md`。

**背景／症狀：** 開啟 EPUB、畫面仍是「載入中」轉圈圈時點擊畫面左側（上一頁熱區），依序出現 `window.nextPage is not a function` → `Cannot read property 'next' of undefined` → 畫面切成崩潰錯誤畫面。

**根因（已用原始碼交叉核對確認，見 `reviews/bugfix-repro.md` Issue 1 段落）：** `TapZoneDetector`／`_handleZoneAction`／`FoliateEpubReaderView.previousPage`/`nextPage` 這條呼叫路徑完全沒有檢查 `_RenderState`（loading/rendered/error），唯一的抑制條件是 `_hasActiveSelection`（畫線選取中才擋）。JS 端 `window.previousPage`/`nextPage` 賦值時間點（`main.js:333-339`，module 頂層同步執行）早於 `view.renderer` 真正賦值（需等 `openBook()` 內 `await makeBook()` + `await view.open(book)` 完成），中間存在可被點擊命中的空窗期；畫面上的載入指示器只是疊加圖示、不是觸控遮罩。

**Solution：** 在 zone action 呼叫路徑加入 loading 狀態防呆，比照現有 `_hasActiveSelection` 的抑制模式：

- 於 `reader_screen.dart` 的熱區點擊處理（`_handleZoneAction` 或更上層的 `onZoneAction` callback 傳入處）追加 `_state == _RenderState.loading` 時直接 return 的判斷，涵蓋 EPUB 與 PDF 兩條路徑的共用呼叫點（若該點本身非共用，需各自確認）。
- 需交叉檢查 PDF 端（`_PdfNavZoneTapDetectorState`，同樣使用共用 `TapZoneDetector` module）在開書流程中是否存在相同性質的空窗期，若有則一併納入本 Issue 修復範圍，不需另立工單（同一個防呆邏輯應同時涵蓋兩者）。
- 是否額外在 `FoliateEpubReaderView.previousPage`/`nextPage` 這兩個 static helper 內加第二層防禦，或維持「呼叫端已擋、單一權責」的設計，由實作者於 `plans/plan-issue-1.md` 中定案並說明理由。

**單元測試要求：**
- 新增 widget test：`_state == _RenderState.loading` 時點擊導覽熱區，斷言不觸發 `evaluateJavascript`／`onZoneAction`（可透過 fake controller 或既有測試替身觀察呼叫次數）。
- 確認既有「載入完成後點擊熱區正常翻頁」的回歸測試（EPUB／PDF 各自既有 nav-zone 測試）不受影響、全數通過。
- 若 PDF 端也需要修復，比照同樣的 loading-guard 測試模式補一份。

**驗收標準：** EPUB／PDF 在載入中點擊導覽熱區不再觸發任何 JS 呼叫或崩潰畫面；`flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。

---

## Issue 2：開書逾時時間由固定 12 秒延長為 30 秒

**Status:** ✅ 已完成並合併回 `main`（PR [#148](https://git.jigong.org/huthief/elinkBook/pulls/148)，分支 `fix/epic-27-issue2-open-book-timeout`，2 個 commit：實作＋計畫勾選收尾）。程式碼審查（本機審查報告，依專案慣例不進版控）結論為可以合併——0 Critical／0 Important／0 Minor。計畫刻意將「開書逾時自動切換錯誤畫面」測試拆成「29 秒仍載入中」＋「滿 30 秒才逾時」兩段斷言，確保測試能真正鑑別「逾時值恰為 30 秒」而非「任何大於舊值 12 秒的時間點」；全專案 `flutter test`（162 項相關測試）與 `flutter analyze` 零回歸通過。

**依賴：** 無（與 Issue 1 互相獨立）

**來源：** 使用者於 Mobiscribe WAVE 真機回報「書籍檔要開好幾次才能成功，常出現逾時或 WebView 版本太舊訊息」，2026-08-13 `/diagnose` 查證確認為固定 12 秒逾時（`reader_screen.dart:365-368`）在慢速裝置＋大型 EPUB 組合下容易誤判；目標值 30 秒已由使用者於本次診斷對話中確認，完整診斷見 `reviews/bugfix-repro.md`。

**背景／症狀：** `reader_screen.dart:365-368` 固定 `Duration(seconds: 12)`，逾時觸發時顯示「開書逾時，可能是系統 WebView 版本過舊或檔案異常」（`reader_screen.dart:1067`）——此文案為猜測性固定文字，並無實際版本比對邏輯。程式碼註解（`reader_screen.dart:340-348`）本身已預留「未來若真機回報大型書籍需要較長時間可再調整」的空間。

**Solution：** 將 `_openBookTimeoutTimer` 的 `Duration(seconds: 12)` 改為 `Duration(seconds: 30)`；同步更新 `reader_screen.dart:340-348` 附近的說明註解，反映本次調整的依據（真機回報＋使用者確認值），避免下一位讀者誤以為 12 秒仍是唯一依據。逾時提示文案是否需要一併調整措辭（目前仍會不分原因一律顯示「版本過舊或檔案異常」）由實作者評估，非本 Issue 強制要求。

**單元測試要求：**
- `app/test/screens/reader_screen_test.dart` 現有兩處硬編碼 `Duration(seconds: 12)`（約 4927-4953 行「開書逾時...12 秒內未收到 onPageRendered」、4955-4982 行「逾時計時器不應覆蓋既有成功狀態」）須同步改為 30 秒，含測試名稱裡的秒數描述與 `tester.pump()` 的推進時長。
- 確認調整後兩則既有測試語意不變（逾時後切換錯誤畫面／成功渲染不被逾時覆蓋），僅數值改變。

**驗收標準：** 開書 30 秒內未完成才顯示逾時錯誤畫面；`reader_screen_test.dart` 相關測試更新為新數值並通過；`flutter analyze` 乾淨、`flutter test` 全數通過。
