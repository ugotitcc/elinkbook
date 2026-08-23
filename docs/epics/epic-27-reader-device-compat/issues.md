# Epic 27 — 裝置相容性強化：工單清單 (Issues)

依使用者於 Mobiscribe WAVE 真機回報的兩項問題，2026-08-13 以 `/diagnose` 查證後立案（Issue 1、2）；Issue 3、4 為 2026-08-17 使用者於 Mobiscribe WARE 真機口頭回報後以 `/diagnose` 查證立案。全數皆為既有邏輯的行為修正，不涉及新增介面/型別、無架構異動，依 `epic-26-architecture-hardening` 先例跳過正式 `spec.md`，直接進入本工單清單。診斷過程與程式碼證據見 `reviews/bugfix-repro.md`。

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

---

## Issue 3：開 App／開書時畫面整個黑色一段時間

**Status:** ✅ 已完成並合併回 `main`（PR [#156](https://git.jigong.org/huthief/elinkBook/pulls/156)，分支 `fix/epic-27-issue3-black-screen`，2 個 commit：實作＋審查修正）。程式碼審查歷經兩輪（`reviews/review-plan-issue-3.md` 計畫審查、`reviews/review-issue-3.md` 程式碼審查）：第一輪程式碼審查抓到 1 項 Critical——遮罩以 `ColoredBox` 預設的 `HitTestBehavior.opaque` 吞掉 loading 期間全螢幕觸控，連帶破壞 Issue 1 已定案、loading 中仍應可用的 `menu` 熱區（切換沉浸模式）保證，且被此前變更透過修改既有測試（提早呼叫 `onPageRendered()`）掩蓋；已改用 `IgnorePointer` 讓遮罩只負責視覺覆蓋、不吸收觸控，並還原被掩蓋的既有測試、補上直接的觸控穿透迴歸測試。複審結論：0 Critical／0 Important／0 Minor，可合併。全專案 `flutter analyze` 乾淨、`flutter test`（171 項相關測試）零回歸通過。**真機（Mobiscribe WARE）視覺驗證（黑屏是否真的消失、loading 中選單熱區是否正常）仍待使用者回報，尚未勾選。**

**依賴：** 無

**來源：** 使用者於 Mobiscribe WARE 真機口頭回報，2026-08-17 `/diagnose` 查證，完整診斷見 `reviews/bugfix-repro.md`「Issue 3」。

**背景／症狀：** 冷啟動 App、或開啟書籍時，畫面整個黑色一段時間才進入書架/顯示書籍內容，體驗不佳。已透過對話確認裝置系統與 App 內建主題皆為淺色，排除「深色/夜間模式導致原生啟動畫面變黑」這個假設。

**根因（信心度：開書黑屏「高」、冷啟動黑屏「中」，皆屬有程式碼依據的推論，非真機 log 坐實，見 `reviews/bugfix-repro.md` Issue 3）：**

- `reader_screen.dart` 的 `_buildBody()`（約 2050-2060 行）：原生渲染畫面（`InAppWebView`／`pdfrx`）是 Stack 最底層、`_resolved != null` 就立刻掛載，早於 `_state` 轉為 `rendered`；中間只疊了一顆置中 `CircularProgressIndicator`，沒有任何不透明底色墊著。原生繪圖表面在真正收到第一次繪製結果前，緩衝區預設顯示黑色（Android 平台已知行為）。
- 冷啟動的黑屏無法歸因於原生啟動畫面（已排除深色模式假設），較可能是同一類「Flutter Engine Surface 建立時的首幀黑幀」現象，加上 `main()`（`main.dart:29-108`）在 `runApp()` 前有多個同步 `await` 拉長曝光時間。

**Solution：**

- 在 `_buildBody()` 的 Stack 中，於原生畫面（`_buildNativeView(...)`）與 `CircularProgressIndicator` 之間，補一層不透明的主題背景色（例如 `ColoredBox(color: Theme.of(context).scaffoldBackgroundColor)` 或既有的 `_themedBackgroundColor` getter），把黑遮住、改成與主題一致的過場色。實作者需確認：這層底色只在 `_state == _RenderState.loading` 時需要顯示、或是否需要恆常墊底（避免原生畫面尺寸調整/重建時再次露出黑色），由實作者於 `plans/plan-issue-3.md` 定案並說明理由。
- 評估 `main()`（`main.dart:29-108`）內是否有初始化工作可延後到 `runApp()` 之後非同步進行，縮短冷啟動黑屏的曝光時間；若評估後認為風險/複雜度不成比例，可只處理上述 Stack 補底色，並在計畫中說明理由。

**單元測試要求：**
- 新增/調整 widget test，驗證 `_state == _RenderState.loading` 時，原生畫面底下已有不透明底色 widget（例如透過 `find.byType` 或既有 Key 斷言其存在與疊放順序）。
- 確認既有「載入完成後畫面正常顯示」的回歸測試不受影響、全數通過。
- 真機視覺驗證（黑屏是否真的消失）不在 `flutter test` 範圍內，需留待真機或 `integration_test/` 驗證，比照 Issue 1 先例，於本工單完成後標註使用者確認結果。

**驗收標準：** 開書載入中不再出現全黑畫面（改為主題色過場）；`flutter analyze` 乾淨、`flutter test` 全數通過、零回歸；真機（Mobiscribe WARE）驗證黑屏現象明顯改善或消失。

---

## Issue 4：版面設定「另存為新預設集」點擊後彈窗不會出現

**Status:** `ready-for-agent`

**依賴：** 無（與 Issue 3 互相獨立）

**來源：** 使用者於 Mobiscribe WARE 真機口頭回報，2026-08-17 `/diagnose` 查證，完整診斷見 `reviews/bugfix-repro.md`「Issue 4」。

**背景／症狀：** 於流式 EPUB 的「版面設定」→「設定喜好」分頁點擊「另存為新預設集」按鈕（`reader_settings_sheet.dart:914-918`），預期跳出命名輸入 `AlertDialog`，實際上點擊後畫面完全沒有任何變化（含盲點按鈕周邊區域也沒有反應），已確認排除「彈窗其實有畫出來、只是電子紙沒刷新」的假設（見 `reviews/bugfix-repro.md` Issue 4 說明）。

**根因（信心度：中，尚無法 100% 確認，見 `reviews/bugfix-repro.md` Issue 4）：** 呼叫路徑（`reader_settings_sheet.dart:916` → `reader_screen.dart:750-753` → `_handleSaveAsPreset`，`reader_screen.dart:796-828`）在真正呼叫 `showDialog` 之前，唯一會讓整個流程靜默 `return`（不留任何痕跡）的守門條件是 `widget.layoutPresetRepository == null`；已核對建構路徑，正常執行不應為 `null`，故此假設信心不高但無法完全排除。另一種無法透過靜態分析排除的可能：`_currentDraft` getter 或 `showDialog` 呼叫本身在真機環境拋出未預期例外——Release build 下 Gesture handler 內未捕捉的例外會被 `FlutterError.onError` 攔截但不顯示任何畫面，症狀正好吻合。

**Solution（本工單刻意採取「提高可觀測性＋防禦性」而非直接臆測修復，因根因尚未 100% 確認）：**

- 在 `_handleSaveAsPreset` 的 `if (repository == null) return;` 分支補上使用者可見提示（例如 SnackBar 顯示「暫時無法儲存預設集」），把「靜默失敗」改成「至少使用者知道發生了什麼」。
- 為 `_handleSaveAsPreset` 整個 method body 加上例外攔截（`try`/`catch`），攔截後以 SnackBar／`debugPrint` 呈現例外訊息，避免真機 Release build 下例外被靜默吞掉。
- 實作者需決定 SnackBar 呈現方式是否比照專案既有其他錯誤提示慣例（例如是否有既有的 SnackBar helper/樣式可重用），於 `plans/plan-issue-4.md` 中定案。

**單元測試要求：**
- 新增 widget test：`layoutPresetRepository` 為 `null` 時點擊「另存為新預設集」按鈕，斷言出現對應的使用者可見提示（SnackBar 或等效元件），而非完全無反應。
- 新增 widget test：`_handleSaveAsPreset` 內部（或其呼叫的 repository 方法）拋出例外時，斷言例外被攔截、出現使用者可見提示，且不會讓整個 App 崩潰/無回應。
- 確認既有「存滿 3 組後再次另存跳出覆蓋選單」等既有測試（約 6802 行起）不受影響、全數通過。

**驗收標準：** `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸；若使用者於真機再次遇到本問題，應能看到明確的錯誤/提示訊息而非毫無反應，據此可判斷是否為 `repository == null`（若是，需再往上追查建構時序，另立新工單）或其他例外原因。

---

## Issue 5：E-Ink 高對比模式狀態感知與切換識別強化

**Status:** `ready-for-agent`

**依賴：** 無

**來源：** 使用者回報「無法知道目前是 ELINK 還是非 ELINK 模式」（2026-08-22）。

**背景／症狀：**
1. 書架主畫面（`LibraryScreen`）AppBar 上的 E-Ink 切換按鈕（`Key('library_eink_toggle')`）僅使用 `IconButton` 切換 `Icons.contrast` 與 `Icons.contrast_outlined`。在 E-Ink 模式下 `Theme.of(context).colorScheme.primary` 為 `Colors.black`，未選中與選中時圖示皆為黑色，使用者無法判斷當前模式是開啟還是關閉。
2. 設定頁面（`SettingsScreen`）缺乏獨立的「E-Ink 高對比模式」開關，僅將主題圓點透明度降為 0.4，缺乏主動狀態回饋與說明。

**Solution：**
1. 在 `LibraryScreen` 的 AppBar 中，為 E-Ink 切換按鈕加上具備高對比底色與外框的狀態容器（例如反白黑底膠囊/圓形背景與白圖示），明確標示開啟狀態，Tooltip 顯示「E-Ink 模式：開啟／關閉（點擊切換）」。
2. 在 `SettingsScreen` 中新增「E-Ink 高對比模式」`SwitchListTile`（`Key('settings_eink_mode_switch')`），提供即時開關切換與詳細說明文字，並貫穿 `onEinkModeChanged` 回呼。

**單元測試要求：**
- 新增 widget test：`LibraryScreen` 在 `isEinkMode: true` 與 `false` 下，E-Ink 切換按鈕外觀與 tooltip 具備可鑑別之狀態。
- 新增 widget test：`SettingsScreen` 顯示 E-Ink 模式開關，點擊切換時正確呼叫 `onEinkModeChanged`。

**驗收標準：** `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。

---

## Issue 6：閱讀器版面設定面板（PDF / EPUB / FXL）圖示選項高對比選中狀態重構

**Status:** `ready-for-agent`

**依賴：** 無

**來源：** 使用者回報「白色與 ELINK 模式下，PDF/EPUB 設定面板只要是以 ICON 顯示的，都無法判讀目前是選用哪一種模式」（2026-08-22）。

**背景／症狀：**
1. `PdfSettingsSheet`（Fit 模式、雙頁模式、頁面方向、換頁動畫、裁切模式）、`ReaderSettingsSheet`（文字對齊、排版方向、翻頁模式、螢幕方向、分欄模式）及 `FxlSettingsSheet`（雙頁模式、翻頁方向）使用純 `IconButton`，選中狀態僅透過 `color: selected ? primary : null` 區分。
2. 在 E-Ink 模式下，`primary` 為 `Colors.black`，未選中圖示也是黑色（黑 vs 黑），兩者完全相同無差別。在 Light 白色主題下，紫色與深灰色缺乏背景容器，在電子紙或強光下辨識度極低。

**Solution：**
1. 將所有 ICON 單選項目封裝為高對比選項容器（`ReaderOptionTile` 或高對比 `SegmentedButton` / 帶背景邊框的 Tile）。
2. 選中狀態樣式規則：
   - **E-Ink 主題**：選中為 **純黑實心背景（`Colors.black`）＋ 純白前景色（`Colors.white`）**；未選中為 **純白背景 ＋ 1.5dp 純黑邊框 ＋ 純黑前景色**。
   - **一般主題（Light/Dark/Sepia）**：選中為實心 `primaryContainer` 背景 ＋ 主題色邊框 ＋ `onPrimaryContainer` 前景色；未選中為一般表面背景 ＋ 淺灰外框。

**單元測試要求：**
- 新增 widget test：驗證 `PdfSettingsSheet`、`ReaderSettingsSheet`、`FxlSettingsSheet` 在 E-Ink 與 Light 主題下，選中項目具有明確的選中背景與外框標記。
- 確認既有設定變更回呼與單元測試全數相容通過。

**驗收標準：** `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。

---

## Issue 7：PDF 手動裁切疊加層（PdfCropFrameOverlay）高對比視覺與 FAB 按鈕重構

**Status:** `ready-for-agent`

**依賴：** 無

**來源：** 使用者回報「PDF 裁切模式選擇框為白色，白底書籍無法識別；確認/取消按鈕為白色完全看不到，請比照 FAB 改為有背景的深對比樣式」（2026-08-22）。

**背景／症狀：**
1. `PdfCropFrameOverlay` 裁切框僅有 `Border.all(color: Colors.white, width: 2)`，且外部無遮罩，白底 PDF 頁面上完全隱形。
2. 四角控制點為純白方塊 `Container(color: Colors.white)`。
3. 確認（`pdf_crop_frame_confirm`）與取消（`pdf_crop_frame_cancel`）按鈕使用無背景的 `IconButton(icon: Icon(..., color: Colors.white))`，在白底頁面上不可見。

**Solution：**
1. 裁切區域外部加入 50% 黑半透明挖空遮罩（Cutout Scrim），高亮保留區域、變暗排除區域。
2. 裁切框改用雙色高對比邊框（外黑內白或粗邊對比線），四角控制點改為帶邊框與陰影之圓形手柄。
3. 確認與取消按鈕改為高對比 **FAB 圓形浮動按鈕樣式**（帶 elevation 陰影與實心底色）：
   - 取消按鈕（✕）：深色背景（`Color(0xFF2A2A2E)`）＋ 白色圖示 ＋ 白色細邊框。
   - 確認按鈕（✓）：高對比綠色/主題色背景（`Color(0xFF16A34A)`）＋ 白色圖示 ＋ 白色細邊框。

**單元測試要求：**
- 新增 widget test：驗證 `PdfCropFrameOverlay` 包含遮罩繪製元件與帶背景樣式的確認/取消按鈕。
- 確認既有手勢拖曳調整矩形、確認、取消的 6 則測試全數維持通過。

**驗收標準：** `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。

---

## Issue 8：書架排序選單加入當前模式選中指示

**Status:** `ready-for-agent`

**依賴：** 無

**來源：** 使用者回報「書架排序無法辨識目前是選用哪一種排序模式」（2026-08-22）。

**背景／症狀：**
- `LibraryScreen` 的排序按鈕（`Key('library_sort_button')`）彈出的 `PopupMenuButton<LibrarySortBy>` 中，各選項僅有純文字 `Text(_sortLabel(sortBy))`，無任何圖示、打勾或高亮指示目前生效的排序方式。

**Solution：**
- 將排序選單項目（`PopupMenuItem<LibrarySortBy>`）改造為包含 Checkmark 圖示之佈局：
  - 當前選中的排序方式：顯示 `Icons.check` 圖示、文字設為粗體（`FontWeight.bold`）並使用主題色/高對比色。
  - 未選中的排序方式：前方保留相同寬度之透明佔位（維持文字左對齊一致），文字為一般字重。

**單元測試要求：**
- 新增 widget test：點擊排序按鈕開啟選單後，斷言當前選中的排序方式項目含有 `Icons.check` 圖示與粗體樣式。
- 確認既有排序切換測試（`library_sort_option_title`、`library_sort_option_author` 等）全數通過。

**驗收標準：** `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。

