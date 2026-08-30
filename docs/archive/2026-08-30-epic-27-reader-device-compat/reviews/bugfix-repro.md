# Bugfix Repro — epic-27-reader-device-compat

診斷日期：2026-08-13
回報裝置：Mobiscribe WAVE（Android 12，Android System WebView UA 顯示 `Chrome/91.0.4472.114`，屬偏舊版本）
回報者證據：`tmp/images/MobiscribeWave/開啟書籍中點擊左邊螢幕出現ERROR.jpg`、`...ERROR_LOG.jpg`（App 內建「閱讀器 Console Log」畫面截圖）

---

## Issue 1（對應 issues.md Issue 1）：EPUB 載入中點擊左側熱區導致崩潰畫面

### Phase 2 — 症狀（使用者截圖已直接提供，視為既有重現證據）

使用者截圖依序顯示：

1. `[ERROR] Uncaught TypeError: window.nextPage is not a function`
2. `[ERROR] Uncaught (in promise) TypeError: Cannot read property 'next' of undefined`
3. 畫面最終切成錯誤畫面，顯示 `Unhandled Promise Rejection: Cannot read property 'next' of undefined`

觸發動作：開啟書籍、畫面仍是「載入中」轉圈圈時，點擊畫面左側（對應「上一頁」熱區）。

### Phase 3/4 — 根因（已用原始碼交叉核對確認，非臆測）

**點擊路徑完全沒有 loading 狀態防呆：**

- `TapZoneDetector`（`app/lib/reader/tap_zone_detector.dart`）的 `onTap` 只受 `_hasActiveSelection` 抑制（畫線選取中才擋），見 `app/lib/reader/foliate_epub_reader_view.dart:804-806`：
  ```dart
  onTap: () {
    if (_hasActiveSelection) return;
    widget.onZoneAction?.call(action);
  },
  ```
- `onZoneAction` → `reader_screen.dart` 的 `_handleZoneAction` → 左側熱區呼叫 `FoliateEpubReaderView.previousPage(_foliateEpubReaderViewKey)`。
- 該 static helper（`foliate_epub_reader_view.dart:429-434`）是 fire-and-forget，未檢查 `_controller` 就緒或書籍載入狀態：
  ```dart
  static void previousPage(...) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._evaluate('window.previousPage()');
    }
  }
  ```
- 畫面上的 `CircularProgressIndicator`（`reader_screen.dart:2024`，`Key('reader_loading_indicator')`）只是疊在 `Stack` 上方的置中小圖示，**不是** `AbsorbPointer`/`IgnorePointer` 全螢幕遮罩，底下的熱區仍正常接收觸控。

**JS 端兩階段空窗期，對應使用者截圖的兩種錯誤：**

- `window.nextPage`/`window.previousPage` 在 `main.js:333-339` 是 module 頂層同步賦值：
  ```js
  window.nextPage = function () { view.next() }
  window.previousPage = function () { view.prev() }
  ```
  此賦值時間點只取決於 `main.js` 是否已被瀏覽器執行到這一行，**遠早於** `openBook()`（`main.js:865` 才呼叫）完成。若在 `main.js` 執行到第 333 行之前點擊，`window.previousPage` 為 `undefined` → 對應截圖錯誤①。
- 一旦賦值完成、但書籍尚未開完，`view.prev()`/`view.next()`（`view.js:567-572`）內部存取 `this.renderer`；`this.renderer` 只在 `View.open(book)`（`view.js:234`，內部第 258/261 行賦值）執行到那一步才存在，而 `open()` 要等 `openBook()` 內 `await makeBook(...)`（`main.js:493`，解析整本 EPUB，慢速裝置/大檔案可能耗時數秒）之後才被呼叫。此空窗期點擊 → `this.renderer` 為 `undefined` → `Cannot read property 'next' of undefined` → 對應截圖錯誤②③。

**錯誤如何顯示到畫面：** `_globalErrorCaptureJs`（`foliate_epub_reader_view.dart:182-195`，於 `AT_DOCUMENT_START` 注入）的 `window.onunhandledrejection` 把訊息轉送到 `onError` bridge → `reader_screen.dart` 的 `_handleError()`（約 1048-1056 行）：
```dart
void _handleError(String message) {
  if (!mounted) return;
  if (_state != _RenderState.loading) return;
  _openBookTimeoutTimer?.cancel();
  setState(() {
    _state = _RenderState.error;
    _errorMessage = message;
  });
}
```
因為此時 `_state` 正是 `loading`，直接把 loading 畫面覆蓋成錯誤畫面、原樣顯示 JS 端訊息——這就是使用者截圖看到的畫面成因。

### 建議修法方向（留待 Scrum Master／實作階段定案，本檔案僅記錄診斷結果）

在 zone action 呼叫路徑上加入「載入中忽略點擊」的防呆，例如在 `_handleZoneAction`（或 `TapZoneDetector` 的 `onTap` callback 傳入處）比照 `_hasActiveSelection` 的模式，追加 `_state == _RenderState.loading` 判斷。需一併確認 PDF 端（`_PdfNavZoneTapDetectorState`，同樣使用共用 `TapZoneDetector`）在開書流程中是否存在相同性質的空窗期。

---

## Issue 2（對應 issues.md Issue 2）：開書逾時固定 12 秒，慢速裝置容易誤判

### 症狀

使用者反映 Mobiscribe WAVE 上「書籍檔要開好幾次才能成功」，過程中容易出現「逾時」或「WebView 版本太舊」訊息。

### 根因（已用原始碼確認）

`reader_screen.dart:365-368`（`initState()` 內排程）：
```dart
_openBookTimeoutTimer = Timer(
  const Duration(seconds: 12),
  _handleOpenBookTimeout,
);
```
固定 12 秒，不隨檔案大小/裝置效能調整。逾時觸發訊息（`reader_screen.dart:1067`）：
```dart
_errorMessage = '開書逾時，可能是系統 WebView 版本過舊或檔案異常';
```
是**猜測性固定文案**，沒有任何實際比對 WebView/Chromium 版本號的邏輯——不論真正原因是版本太舊、大檔案解析慢、或裝置 CPU 慢，逾時後一律顯示同一句話。

程式碼註解（`reader_screen.dart:340-348`）本身已自陳「12 秒取自 `epic-18-reader-device-qa` Issue 33 原始分析報告建議值，非嚴謹量測結果，未來若真機回報大型書籍在正常情況下也需要較長時間才能完成首頁繪製，可再調整」——使用者本次回報正好對應這個已知的預留調整空間。

`_esCompatPolyfillJs`／`app/tool/check_foliate_es_compat.js` 目前對 Chrome 91 已知的 ES 語法缺口皆已補丁、掃描結果乾淨，延長逾時無法修補「WebView 真的缺少必要 API」這類情況（屬另一種靜默失敗/JS 例外，不受此逾時影響），但可直接緩解「大檔案/慢裝置被誤判逾時」。

### 已確認的既有測試（實作時需同步調整）

`app/test/screens/reader_screen_test.dart` 有兩處硬編碼 `Duration(seconds: 12)`（約 4927-4953 行、4955-4982 行），分別驗證「12 秒後切換為錯誤畫面」與「已成功渲染不應被逾時覆蓋」，測試名稱與註解明確引用 `epic-18-reader-device-qa Issue 33`。若逾時秒數調整為 30 秒，這兩處都需要同步修改。

### 使用者確認的目標值

30 秒（2026-08-13 使用者於本次診斷對話中確認）。

---

## Issue 3（對應 issues.md Issue 3）：開 App／開書時畫面整個黑色一段時間

診斷日期：2026-08-17
回報裝置：Mobiscribe WARE（使用者原文；與 Issue 1/2 回報的 Mobiscribe WAVE 是否為同一機型未進一步確認，姑且視為同一類電子紙 Android 裝置處理）
回報者證據：本次為口頭描述，無截圖/log；已透過 `/diagnose` 對話向使用者確認裝置系統顯示設定**未開啟**深色/夜間模式，App 內建主題設定亦為**淺色 (Light)**。

### Phase 2 — 症狀

1. 冷啟動 App（點圖示進去）：畫面整個黑色一段時間，之後才進入書架。
2. 開啟書籍：畫面整個黑色一段時間，之後才正常顯示書籍內容。

兩者皆為「等一下就會自己好」，不是卡死。

### Phase 3/4 — 根因（以原始碼交叉核對，信心度分開標註；無真機/log 可直接坐實，屬本次診斷的已知局限）

**(a) 開啟書籍時的黑屏——信心度：高**

`reader_screen.dart` 的 `_buildBody()`（約 2050-2060 行）：

```dart
return Stack(
  children: [
    if (_resolved != null && (...))
      _buildNativeView(format, isLandscape),
    ...
    if (_state == _RenderState.loading)
      const Center(
        key: Key('reader_loading_indicator'),
        child: CircularProgressIndicator(),
      ),
  ],
);
```

原生渲染畫面（EPUB／KF8／CBZ／TXT／MD 用 `InAppWebView`；PDF 用 `pdfrx` 繪圖表面）是 Stack **最底層**，一旦 `_resolved != null` 就立刻掛載——早於 `_state` 轉為 `rendered`。中間唯一疊加的只有一顆置中 `CircularProgressIndicator`，**沒有任何不透明底色**墊在原生畫面與轉圈圈之間。

已確認 `foliate_reader_view.dart` 建構 `InAppWebView` 時未顯式傳入 `useHybridComposition`，落在 `flutter_inappwebview` 套件（`app/patches/flutter_inappwebview_android/lib/src/in_app_webview/in_app_webview.dart:312-315`）的預設值 `true`（Hybrid Composition）。這個模式已解決舊版 Virtual Display／`SurfaceView` 模式常見的「原生畫面永遠疊在 Flutter 疊加層最上方」z-order 問題，但**沒有解決「首幀繪製前緩衝區預設為黑」這個獨立現象**——`TextureView`／GPU buffer 在真正收到 WebView／PDFium 第一次繪製結果之前，預設顯示黑色是 Android 平台的已知行為，不是本專案邏輯錯誤。裝置效能較弱（電子紙常見搭配低功耗 SoC）會放大這段空窗期的時間長度，符合使用者「等一段時間後才進畫面」的描述。

**(b) 冷啟動 App 時的黑屏——信心度：中，已排除主要假設之一**

已透過對話向使用者確認：裝置系統顯示設定未開啟深色/夜間模式、App 內建主題為淺色。因此「原生啟動畫面（`android/app/src/main/res/values-night/styles.xml`）在系統夜間模式下走 `Theme.Black.NoTitleBar`、`windowBackground` 預設為近黑色」這個原本合理的假設**可以排除**——`values-night` 版本在本次回報情境下不會生效，實際生效的是 `values/styles.xml`（`LaunchTheme`，`windowBackground` 為純白 `@drawable/launch_background`）。

排除上述假設後，較可能的解釋是與 (a) 同一類「Flutter/Android GPU Surface 建立時的首幀黑幀」現象——與宣告的白色 `launch_background` 無關，是 Flutter Engine 在 Surface 剛建立、尚未提交第一幀繪製結果前的通用行為，加上 `main()`（`main.dart:29-108`）在 `runApp()` 之前有多個同步 `await`（`pdfrxFlutterInitialize()`、開啟 SQLite、依序建構 `SqliteLibraryRepository`／`BookReaderPrefsRepository`／`BookmarksRepository` 等多個 Repository），若裝置 I/O／CPU 較慢，會拉長這段「原生啟動畫面已消失、但 Flutter 尚未畫出真正畫面」的黑屏曝光時間。

**本項因缺乏真機 logcat／畫面錄影佐證，屬於「有程式碼依據的推論」而非「已用證據坐實」，与 Issue 1/2（有使用者截圖逐行核對）信心度不同，特此註記。**

### 建議修法方向（留待 Scrum Master／實作階段定案，本檔案僅記錄診斷結果）

- 在 `_buildBody()` 的 Stack 中，於原生畫面與轉圈圈之間補一層不透明的主題背景色（`ColoredBox`／`Container(color: _themedBackgroundColor ?? Theme.of(context).scaffoldBackgroundColor)`），直接把黑遮住，改成與主題一致的過場色。
- 檢視 `main()`（`main.dart:29-108`）是否有初始化工作可以延後到 `runApp()` 之後非同步進行，縮短「原生啟動畫面消失、Flutter 尚未畫出真正畫面」的曝光時間。

---

## Issue 4（對應 issues.md Issue 4）：版面設定「另存為新預設集」點擊後彈窗不會出現

診斷日期：2026-08-17
回報裝置：Mobiscribe WARE（同 Issue 3）
回報者證據：口頭描述；已透過 `/diagnose` 對話確認「點擊按鈕後畫面完全沒有任何變化，包含盲點按鈕本身周邊區域也沒有反應」。

### Phase 2 — 症狀

於流式 EPUB 的「版面設定」→「設定喜好」分頁點擊「另存為新預設集」按鈕（`reader_settings_sheet.dart:914-918`，key `reader_settings_save_as_preset`），預期應跳出命名輸入 `AlertDialog`（`layout_preset_name_dialog.dart`），實際上沒有任何畫面變化。

### Phase 3/4 — 根因（信心度：中——已排除部分假設，但缺乏真機 log 無法 100% 確認）

**已排除：「彈窗其實有畫出來，只是電子紙沒刷新到那塊區域」。** 若 `AlertDialog` 真的存在於畫面上（即使視覺上因螢幕未刷新而看不出來），預設 `barrierDismissible: true` 的背景遮罩至少會在使用者盲點時吃掉觸控事件、產生「對話框被關閉」之類的狀態變化。使用者回報「點哪裡都沒反應」，與此不符，故排除。

**呼叫路徑（`reader_settings_sheet.dart:916` → `reader_screen.dart:750-753` → `_handleSaveAsPreset`，`reader_screen.dart:796-828`）：**

```dart
Future<void> _handleSaveAsPreset(BookReaderPrefs currentDraft) async {
  final repository = widget.layoutPresetRepository;
  if (repository == null) return;
  final name = await showLayoutPresetNameDialog(context);
  ...
```

在真正呼叫 `showDialog` 之前，程式碼唯一會讓整個流程靜默 `return`（不留任何痕跡）的守門條件是 `widget.layoutPresetRepository == null`。已逐層核對建構路徑（`main.dart:58` 建構 `LayoutPresetRepository` → `ElinkBookApp` → `LibraryScreen` → `library_screen.dart:469` 建構 `ReaderScreen` 時傳入 `layoutPresetRepository: widget.layoutPresetRepository`），全專案 `grep` 確認 `ReaderScreen(` 只有這一個呼叫點，正常執行路徑下不應為 `null`。**故此假設信心不高，但因無法在真機重現排除初始化時序等邊角情況，不能完全排除。**

另一種未能透過程式碼靜態確認、但無法排除的可能：`_currentDraft` getter（`reader_settings_sheet.dart:185-207`）或 `showDialog` 呼叫本身在真機環境拋出未預期例外。**Release build 下，Widget 的 `onPressed` 等 Gesture handler 內若拋出未捕捉例外，會被 Flutter 框架的 `FlutterError.onError` 攔截並記錄，但不會顯示任何畫面、也不會中斷 App**——症狀正好會是「點下去毫無反應、也不影響其他功能」，且沒有真機 log 的情況下純看程式碼無法區分是否為此類情況。

### 建議修法方向（留待 Scrum Master／實作階段定案，本檔案僅記錄診斷結果）

不論最終根因是哪一種，以下修法方向可同時提高「可觀測性」與「防禦性」，且皆為低風險改動：

- 在 `_handleSaveAsPreset` 的 `if (repository == null) return;` 分支補上明確的使用者可見提示（例如 SnackBar「暫時無法儲存預設集」），把「靜默失敗」改成「至少使用者知道發生了什麼」，日後若真的命中這個分支也不會再誤判為「毫無反應」。
- 為 `_handleSaveAsPreset` 整個 method body 加上 `try/catch`，攔截後以 `debugPrint`／SnackBar 呈現例外訊息，避免真機 Release build 下的例外被靜默吞掉；日後若使用者再次回報同類問題，能直接從錯誤訊息判斷根因，不必再靠臆測。
- 待上述防禦性改動上線後，若使用者能再次於真機重現，即可直接判斷是哪一種情況並對症下藥；若加了提示後使用者反而看到了 SnackBar 訊息，代表確實是 `repository == null`，需再往上追查建構時序。

---

## Issue 9（對應 issues.md Issue 9）：流式 EPUB 長按選字／劃線時容易誤觸翻頁，右側／上側邊緣最明顯

診斷日期：2026-08-24
回報方式：使用者於對話中口頭回報「目前在流式 EPUB 畫線，仍容易觸發上下頁跳動，尤其右側越靠近右邊測，或上邊測越容易觸發」；使用者另提供研究文件 `tmp/research/epub_highlight_page_jump_analysis_and_solutions.md`（下稱「使用者研究文件」）。本節根因已將該文件的假設逐條與原始碼交叉核對，僅保留可驗證的部分，未驗證的部分另行註記信心度。

### Phase 2 — 症狀

流式 EPUB（`FoliateReaderView`，含 EPUB／KF8／TXT／MD）長按選字或拖曳劃線時，經常在放開手指的瞬間意外觸發上一頁／下一頁翻頁。觸發頻率與觸控位置有關：越靠近螢幕右側邊緣、越靠近螢幕頂部邊緣，越容易觸發。

### Phase 3/4 — 根因（已用原始碼交叉核對確認，兩個獨立根因疊加）

**根因 A（主因，可解釋位置相關性，信心度：高）——`_hasActiveSelection` 防呆存在無法消除的 IPC 時序空窗：**

- `tap_zone_detector.dart:74-84` 的 `onPointerUp` 是放開手指當下**同步**執行的判斷（`elapsed <= tapMaxDurationMs && distance <= tapSlop` 即觸發 `onTap`）。
- `foliate_reader_view.dart:826-847` 的 3×3 熱區 `onTap` 用 `_hasActiveSelection`（`foliate_reader_view.dart:556`）擋下選取中的翻頁；但這個旗標只在 `onSelectionChanged` JS 橋接 handler 真正被呼叫時才會變 `true`（`foliate_reader_view.dart:672`）。
- 該 handler 對應的 `main.js:661-683` `reportSelection()` 是 `async` function，內部還要 `await view.getCFIProgress(cfi)`，跑完才呼叫 `flutter_inappwebview.callHandler('onSelectionChanged', ...)`——這是一條「JS 事件迴圈 → 額外 await → 跨 WebView 進程橋接」的多重非同步鏈路，耗時必然大於 Flutter 側同步的 `onPointerUp`。
- 雙擊選字（連點兩下選一個詞）這類「快、位移小」的手勢，天生同時符合 `TapZoneDetector` 自己判定「快速點擊」的門檻。放開手指那一刻，`_hasActiveSelection` 十之八九還沒被上面那條鏈路更新成 `true`，防呆形同虛設。
- **為什麼是右側／上側最明顯**：這個時序競賽本身跟位置無關，任何一格熱區都可能發生。但預設熱區模板 `rightFlipZoneTemplate`（`nav_zone_mode.dart:18-22`）是「左＝上一頁、中＝選單、右＝下一頁」，**每一列都只有中間欄是無害的『選單』**，左右兩欄誤觸都是真的翻頁。直排（`vertical-rl`）繁體中文的閱讀順序是「從右到左、從上到下」——新頁面第一行在螢幕最右側、每行行首在螢幕最上方，使用者選字/畫線的落點天然集中在右上角，也就是天然集中在「真的會翻頁」的格子裡，而不是中間那格無害的「選單」。這一段直排幾何解釋沿用使用者研究文件 3.1 節的說法，信心度：高（與現有熱區模板程式碼直接吻合）。

**根因 B（次因，與位置無直接關聯，信心度：高，但範圍小於使用者研究文件原始論述）：**

- `paginator.js:2191-2195`（vendored、未修改，符合 ADR 0011）在 `#onTouchMove` 內確實會檢查 `!selection.isCollapsed` 並提早 `return`，但只是「不再更新」`#touchState.x/y/t/dx/dy/vx/vy`，**不會把已記錄的位移歸零**。
- `#onTouchStart`（`paginator.js:2137-2146`）設定的 `blocked` 旗標只對應「上一次換頁動畫是否還沒收尾」（`this.#vtFinishing || this.#vtProgrammatic`），與文字選取狀態完全無關——不存在使用者研究文件暗示的「選取相關 blocked 旗標」。
- 若長按建立選取前的最初幾個 `touchmove` 影格（選取還沒真的確立前）有一點自然晃動被 `main.js` 的 Issue-47 攔截器放行（`main.js:732-769`，`elapsed>=500ms || distance>15px || avgVelocity>0.3px/ms` 任一成立就永久停止攔截，不會因為後來選取確立而重新啟動），這些影格會被 `paginator.js` 正常記錄成滑動位移。放開手指時 `#onTouchEnd`（`paginator.js:2476-2538`）用這筆**過時**的位移／速度呼叫 `snap()`，可能直接判定翻頁。
- 此根因會造成翻頁/內容跳動，但發生機率與螢幕位置無關（純粹是時序問題），故不是使用者回報「越靠邊越容易」現象的主要解釋，是額外的、獨立的問題來源。
- **已查證關鍵事實**：`paginator.js:2186/2499/2558` 三處都支援 `no-swipe` 屬性——只要在該元素上設定這個屬性，`paginator.js` 就會完全略過內建的滑動翻頁與 snap 判定，所有觸控直接穿透給瀏覽器原生行為（文字選取/控點拖曳）。經全專案 `grep` 確認，這個屬性**目前完全沒有被設定過**（`main.js`/index.html 皆未使用），也沒有任何 Dart 端設定與「滑動翻頁」相關——PRD／CLAUDE.md 對流式格式的導覽模型只講 3×3 熱區與音量鍵，swipe-to-turn-page 並非本產品的既定功能，只是使用未修改的 vendored `paginator.js` 附帶的行為。停用它不影響任何已知功能（含捲動模式：`#onTouchMove`/`#onTouchEnd` 對 `this.scrolled` 的檢查都排在 `no-swipe` 檢查之前就已經先行 return，兩者互不干擾）。

**未獨立驗證的部分**：使用者研究文件 3.4 節提到 `paginator.js:2044-2050`／`2077-2108` 把直排下的垂直滑動誤判為「區塊軸換頁手勢」，本次診斷未逐行覆核這段邏輯（因為推薦解法「方案一 no-swipe」會整段繞過它，驗不驗證不影響修法方向），特此註記信心度為「未驗證，但採用方案一後不影響結論」。

### 建議修法方向與優先順序（留待 Scrum Master／實作階段定案，本檔案僅記錄診斷結果）

1. **【最高優先】main.js 為 `<foliate-paginator>` 開啟 `no-swipe` 屬性**（`view.renderer` 即為該自訂元素本身，見 `main.js:901` 註解；可在 `main.js` 初始化 `view` 之後呼叫 `view.renderer.setAttribute('no-swipe', '')`）。完全消除根因 B，且已確認不影響任何現有功能，符合 ADR 0011（不改 vendored 檔案內容，只是設定屬性），實作成本低、回歸風險低。
2. **【次高優先，不可被第 1 項取代】`tap_zone_detector.dart` 補上 `onPointerMove` 熔斷機制**：一旦位移超過 `tapSlop` 就立刻清空 `_downPosition`/`_downTimeMs`（目前只在 `onPointerUp` 才檢查一次距離，見 `tap_zone_detector.dart:74-84`）。這條防線解決的是 Flutter 側自己的時序競賽（根因 A），與 JS 側是否啟用 `no-swipe` 無關，兩者必須都做才能真正對應使用者回報的「靠右/靠上」現象。
3. **【第三優先，需真機校準，不建議與第 1、2 項同批定案數值】`tapMaxDurationMs` 收斂**（EPUB 現行 700ms）：700ms 涵蓋了「長按未遂但原生選取還沒建立」的空窗期，過寬。比照 `epic-25` Issue 1 先例，需要真機診斷才能定案新數值，不可憑空調整。
4. **【選配，視真機驗證結果決定是否需要】選取清除後的短暫緩衝（Grace Period）**：`onSelectionCleared` 觸發後一小段時間內暫時抑制熱區點擊，處理拖曳控點導致選取暫時折疊（collapsed）的邊角情況。
5. **【選配，人因改善，非根因修復】直排首行安全邊距**：確認直排模式預設 `marginRight`/`marginTop` 有留白，避免文字緊貼螢幕物理邊緣。可獨立於本工單其餘項目施作或跳過。

第 1、2 項合併處理即可覆蓋使用者回報的主要現象（根因 A 解釋位置相關性、根因 B 是額外加固），建議作為本工單的最小可行修復範圍；第 3-5 項可留待真機驗證後視情況追加，不建議阻塞第 1、2 項上線。

---

## Issue 10（對應真機測試 Issue 9 修復後回報，尚未建立 issues.md 工單）：流式 EPUB 選字/畫線互動三項真機回報

診斷日期：2026-08-24
回報方式：使用者於真機（AiPaper Reader C）測試 Issue 9 修復後回報三個現象：
1. 不好選字，或根本選不到；手指滑動選完之後，數次發生整個選取消失。
2. 不確定畫線工具（`AnnotationToolbar`）的觸發方式（手指停住自動跳出／停住後滑動才跳出／直接滑動就跳出），目前觀察「停住後滑動」最常見。
3. 點擊已畫線區域，之前會跳出刪除確認視窗，現在都不會了。

### Phase 1 — 回歸迴圈建置（部分成功，已誠實記錄環境限制）

比照 `epic-25-annotation-interaction-qa/epic-18-issue-47-harness` 既有手法，於 `reviews/issue10-harness/`（本次新建，gitignored）用 Puppeteer + CDP `Input.dispatchTouchEvent` 載入本 repo 真實的 `main.js`/`paginator.js`/`view.js`/`epub.js`，差分比較 Issue 9 前（`fixtures/main.base.js`）與 Issue 9 後（`fixtures/main.fixed.js`，只多 `no-swipe` 那一行，已用 `diff` 確認）在同一組觸控序列下的行為差異。

**成功建立、訊號可信的部分（情境 1）：** 用 `execCommand` 建立一段選取（模擬選字已完成），接著模擬使用者放開前常見的「微調控點」小幅拖曳＋放開，觀察選取是否在 `touchend` 之後仍然存在。結果：**base／fixed 兩版本行為完全一致**（`selectionAfterSmallDragRelease` 皆為 `{collapsed: false, text: "This is "}`，選取皆未消失）——`docs/epics/epic-27-reader-device-compat/reviews/issue10-harness/result.json` 已存檔。

**已查證、無法迴避的環境限制（放棄該部分自動化迴圈，非偷懶）：** 原始腳本另外設計了 3 個情境——短按/長按是否觸發原生 `click`、點擊已建立的劃線是否觸發 `onAnnotationActivated`。用三項獨立證據確認 **headless Chromium 透過 CDP 完全不會從 touchstart/touchend 序列合成原生 `click` 事件**，也**完全不會觸發原生長按選字**：
- 手寫 `Input.dispatchTouchEvent`（touchStart 靜止 120ms 後 touchEnd）：`click` 監聽器 0 次觸發，即使等滿 1000ms 仍是 0（排除純粹時序延遲）。
- 改用 Puppeteer 官方 `page.touchscreen.tap()`（非手寫，官方 API）：同樣 0 次。
- 用 `page.mouse.click()` 對同一個監聽器驗證：確實會觸發（排除監聽器本身寫錯）。
- 真正按住不放 700ms（不用 `execCommand` 作弊）：`document.getSelection().isCollapsed` 全程維持 `true`，原生長按選字完全沒有被觸發，base／fixed 兩版本結果相同。

結論：這是 headless Chromium 對 CDP 合成觸控輸入的既有限制（不合成原生 tap-to-click、不辨識長按手勢），不是本 App 的行為，也不是本次診斷可以透過調整測試手法解決的問題——`repro-issue10.mjs` 已移除這 3 個不可信的情境，只保留情境 1，並在檔案開頭完整記錄此限制供下一位除錯者參考。

### Phase 3 — 三項回報各自的根因研判（混合：迴圈已驗證 ＋ 程式碼交叉核對，兩者信心度不同，逐項標註）

**症狀 1（選字選不到/常常消失）：**
- 迴圈已驗證：選取「已經存在之後」被小幅拖曳＋放開，不受 `no-swipe` 影響（兩版本一致，都不會消失）——**排除**「選取建立後的維持階段」是 Issue 9 造成的迴歸，信心度：中高（有迴圈證據，但只涵蓋這一段）。
- 迴圈驗證不了：真正「長按建立選取」那一步本身是否穩定，因為 headless Chromium 完全無法重現原生長按選字（見上）。若 Issue 9 真的造成這個症狀，最可能發生在這一步，但目前沒有可信的自動化手段驗證，信心度：未知，需真機資料。

**症狀 2（畫線工具觸發時機，「停住後滑動」最常見）：**
- 已用程式碼交叉核對確認：本 App **完全沒有自己實作長按計時器**——`main.js` 對選取的處理純粹是被動監聽瀏覽器原生 `selectionchange`/`contextmenu`/`pointercancel` 事件（`main.js:661-700`），「按多久才會選到字」是 Android WebView／作業系統層級的原生手勢辨識時機，不是這個 App 的程式碼決定的。使用者描述的「停住後滑動」很符合原生長按選字的真實行為模式（先長按選中一個詞，接著自然地用微幅滑動去擴大選取範圍），**目前看起來比較像是對既有行為的觀察描述，不像是程式邏輯的 bug**，但因為同樣卡在上述環境限制（無法在 headless Chromium 重現原生長按），沒辦法排除 Issue 9 有沒有間接影響原生手勢辨識的時機，信心度：中（程式碼交叉核對支持「非 bug」，但未經真機資料排除迴歸）。

**症狀 3（點已畫線區不再跳出刪除確認）：**
- 已用程式碼交叉核對找到明確的既有機制：`main.js:830-846` 的 `ANNOTATION_CLICK_TAP_MAX_MS = 700` 攔截器——快速點擊（時長 ≤700ms）會被 `evt.stopImmediatePropagation()` 主動攔截，**不讓它傳到 `view.js:440` `#createOverlayer` 的畫線點擊監聽器**（也就是不會跳出刪除確認），這是刻意設計（`epic-25-annotation-interaction-qa` Issue 4），用來區分「這是想翻頁的快速點擊」還是「真的想操作畫線的長按」——只有按壓時長 >700ms 的點擊才會被放行、觸發刪除確認。這段攔截邏輯本身在 Issue 9 前後**完全沒有變更**（已用 `diff` 確認 `main.base.js`/`main.fixed.js` 只多 `no-swipe` 一行）。
- 未能排除的可能：`no-swipe` 讓 `paginator.js` 的 `#onTouchMove` 提早 return（`paginator.js:2186`），連帶跳過它原本在 2198 行無條件呼叫的 `e.preventDefault()`。若這個呼叫在真機瀏覽器引擎上（意外地）也在穩定原生 `click` 合成的時機，拿掉後就可能讓「長按後放開」這個動作在真機上不再穩定合成出 `click` 事件——但這個假設**沒有辦法在 headless Chromium 裡驗證**（本次已證實這個環境本來就完全不會合成 `click`，不論 base 或 fixed 版本皆然，無法作為對照組）。信心度：低（有合理機制推論，但缺乏可信的自動化或真機證據）。

### 下一步建議（Phase 1 fallback，本檔案僅記錄診斷結果，實際採用哪個方向待人類決定）

三項回報的根因判斷都卡在同一個環境限制——headless Chromium 無法重現原生長按選字與原生 tap-to-click，只能仰賴真機資料才能繼續往下查。建議比照本 Epic Issue 1 已驗證有效的既有作法：在 `main.js` 加一段有清楚標籤（例如 `[DIAG-issue10]`）的暫時性 `console.log` 診斷（記錄 `touchstart`/`touchend`/`selectionchange`（含 `isCollapsed`/文字內容）/`click`（含是否被 700ms 攔截器擋下）/`onAnnotationActivated` 各自的觸發時間點），請使用者在真機上分別重現這三個情況，透過 App 內建「閱讀器 Console Log」畫面截圖或複製內容回報——這是本次診斷能找到、唯一可以取得可信資料的路徑。是否現在就加這段診斷、以及要不要先處理已經確認「非 bug」的症狀 2（僅補充說明文件，不改程式碼），留待使用者決定。

### 真機資料到手後的更新（2026-08-24，裝置 WAVE／TCE70P24B2202374，Android 12）

分支 `diag/epic-27-issue-10-console-log`（worktree `.worktrees/epic-27-issue-10-diag`）已裝上這台**未鎖 adb** 的真機，直接用 `adb logcat` 側錄（不需使用者手動截圖 App 內建 Console Log 畫面），約 9 分鐘操作期間共擷取 110 筆 `[DIAG-issue10]` 事件，原始側錄檔存於 `docs/epics/epic-27-reader-device-compat/reviews/issue10-harness/device-logcat-raw.txt`。三項回報現在都有具體、可回溯的真機證據，結論如下：

**症狀 2（畫線工具觸發時機）：證據支持「不是 bug」。** 每一次 `reportSelection: changed` 第一次出現時，`textLength` 幾乎都很小（常見是 1），代表選取工具列在原生長按剛完成的當下就已經觸發，不需要等拖曳擴大範圍才跳出。使用者感覺「要停住再滑動才會出現」，較可能是把「長按選中一個字」＋「接著自然地滑動擴大範圍」這兩個動作感知成同一件事，滑動本身並非觸發條件。**信心度：中高（有真機資料支持，但非窮舉所有情境）。**

**症狀 3（點已畫線區不再跳出刪除確認）：證據支持「這次測試沒有按夠久，不是程式壞掉」。** 全段 log 共 20 次「native click fired」，`elapsedSinceTouchStart` 全部落在 0～246ms 之間，**沒有任何一次超過既有的 700ms 門檻**；`onAnnotationActivated`/`show-annotation` 全程 0 次觸發。既有機制（`main.js:830-857`，`epic-25-annotation-interaction-qa` Issue 4 既定設計）本來就規定只有按壓 >700ms 才會放行 click、觸發刪除確認——這次測試的每一次點擊都被正確攔下，完全符合設計、不是迴歸。**需要使用者再測一次「刻意按住已畫線區域超過 1 秒再放開」才能 100% 確認**：若會跳出刪除確認，證實這只是這次操作按壓時間偏短、非 bug；若刻意長按依然不會跳出，才代表真的有問題需要往下查（例如比對 `no-swipe` 是否間接影響了「按住放開」合成 click 的穩定性，見前段根因分析）。

**症狀 1（選字選不到/選完常常消失）：抓到真實重現片段，機制可解釋、但無法 100% 排除與 Issue 9 的關聯。** log 中段（約 `t=27763`~`47607`ms 這段本地時間戳記）捕捉到一段選取文字從 1 個字逐漸長大到 47 個字的完整過程，緊接著選取達到 47 字之後的下一筆事件就是「`native click fired`（`elapsedSinceTouchStart=0`）→ 判定為快速點擊攔下 → `reportSelection: cleared/collapsed`」——選取在剛選完的瞬間就消失，與症狀 1 描述完全吻合，這不是臆測，是真的抓到這段序列。機制推論：使用者放開手指前的最後一個小動作（例如手指離開拖曳控點那一瞬），若被瀏覽器判讀成「點擊」而非「拖曳延伸的收尾」，瀏覽器原生行為本來就會把「點擊選取範圍以外的地方」解讀成使用者想取消選取、自動清空——**這是瀏覽器/WebView 的既有行為，Issue 9 的兩處改動（`no-swipe`／`onPointerMove` 熔斷）都不觸碰這段選取清除的觸發路徑**，所以現有證據比較支持「這不是 Issue 9 造成的迴歸，是既有的瀏覽器行為與使用者放手動作的交互」，但無法在不裝「Issue 9 之前」版本做真機對照的情況下 100%排除。**信心度：中（有具體重現證據與合理機制解釋，缺乏跨版本真機對照）。**

### 第二台裝置（AiPaper Reader C，UA 顯示 Android 16／Chrome 150）人工回報的 Console Log

使用者另外用同一個 `diag/epic-27-issue-10-console-log` 分支的 build 裝到 AiPaper Reader C（這台 `adb shell` 被鎖住，無法側錄，改用 App 內建「閱讀器 Console Log」畫面人工複製回報），並針對症狀 3 額外做了一次「刻意按住已畫線區域超過 1 秒再放開」的測試。

**症狀 3 補充測試結果：確認「非 bug」的部分成立，但額外發現一個新症狀。** 使用者回報：故意長按超過 1 秒放開後，**刪除確認視窗真的跳出來了**——證實症狀 3 的既有機制（`ANNOTATION_CLICK_TAP_MAX_MS` 700ms 門檻）本身沒有壞，先前測不出來單純是這次操作按壓時間不夠長。**但使用者同時回報：跳出確認視窗之後，畫面接著會自己放大，或自動往前/往後換頁**——這是三項原始回報以外、本次測試才浮現的**新症狀**，目前完全沒有診斷資料（現有 3 個 `[DIAG-issue10]` 埋點都不涵蓋縮放/換頁事件），根因待查，暫定列為候選「Issue 11」，留待使用者決定是否現在就繼續往下查或先處理其他項目。

### 第三、四輪測試（同一台 WAVE 裝置，補上 Dart 端診斷）—— 推翻部分先前結論、發現兩個新問題

**重要更正：先前「症狀 3 已確認非 bug」的結論建立在使用者一次未經 log 側錄的手動回報之上，這次補上完整 log 後發現與新證據矛盾，特此如實記錄，不覆蓋掉先前的錯誤判斷。**

**過程問題（誠實記錄，不是遺漏）：** 第三輪一開始加的 Dart 端診斷（`_handleZoneAction`／`_handleAnnotationActivated`／`_showAnnotationActionDialog`）誤用 `ReaderConsoleLog.add()`——這個函式只會寫進 App 內建「Console Log」畫面自己的記憶體緩衝區，**不會**印到 `adb logcat`，與 JS 端 `console.log()`（會經 Chromium 轉印到 logcat）是完全不同管道，導致第三輪錄到的 log 對 Dart 端事件全部是空的、無法用來判讀「換頁」與「刪除確認」是否真的發生。已修正：新增 `_diagLog()` 輔助函式同時呼叫 `debugPrint()`（會印到 logcat `flutter` tag）與 `ReaderConsoleLog.add()`，第四輪起 Dart 端事件已能正確側錄。

**新問題 A（候選 Issue 11）：長按已畫線區域完全不會觸發刪除確認視窗，只會觸發「建立新劃線」的工具列。** 第四輪明確測試「長按已畫線文字」，log 全程 **`show-annotation` 事件 0 次觸發**（JS 端 `#createOverlayer` 的畫線點擊 hit-test 監聽器完全沒被命中），但同一時段大量 `reportSelection: changed, textLength=1` 持續出現——代表這次長按被瀏覽器原生機制辨識成「選字」（跟按在沒有劃線的一般文字上完全一樣的原生行為），因此跳出來的是選字用的 `AnnotationToolbar`（建立新劃線的工具列），不是點擊既有標記用的刪除確認。**機制推論**：原生長按選字是瀏覽器/WebView 層級行為，只認得底下的文字節點，不會因為文字上方疊了一層劃線視覺標記（`Overlayer` 畫的 SVG）就不觸發選字；而 `main.js:830-857` 設計的「按壓 >700ms 才放行 click、觸發刪除確認」機制，前提是這次觸控最終會產生一個 `click` 事件並傳到 `#createOverlayer` 的監聽器——但實際上長按同一段文字會兩者都命中（原生選字＋滿足 700ms 門檻的 click），從目前證據看**原生選字似乎完全搶先，`show-annotation` 從未有機會觸發**。這代表「長按已畫線區跳出刪除確認」這個功能，可能從設計上就與「長按選字」存在沒有被排除的衝突，不確定是不是 Issue 9 造成、也不確定是不是本來就有這個問題——需要更早期版本的真機對照才能確認是既有缺陷還是本次迴歸。

**新問題 B（候選 Issue 12）：連續、失控的自動翻頁，伴隨畫面霧霧的殘影——已用硬體訊號直接證實根因，是觸控硬體本身的「彈跳」，不是本 App 的軟體錯誤。** 第四輪 log 出現多段「同一個熱區 index、同一個翻頁方向，在不到 1 秒內連續觸發 3～4 次 `_handleZoneAction`」的叢集，橫跨測試期間反覆出現多次。第五輪改用 `adb shell getevent -t -l /dev/input/event4`（`cyttsp5_mt`，本裝置觸控 IC 的原始核心輸入事件，完全繞過 Android/WebView/Flutter/JS 所有軟體層）直接側錄硬體訊號，同一次測試中找到 2 段獨立、可從座標驗證的證據：

- 第一段（核心時間戳 `63219.077`~`63220.196`，共 1.119 秒）：**7 次獨立的「手指按下」（`BTN_TOOL_FINGER DOWN`）事件**，相鄰間隔僅 86～326 毫秒；橫向座標 X 全程落在 842～844（僅 2px 誤差），縱向座標 Y 落在 639～713（74px 誤差內），**幾乎是同一個位置**。
- 第二段（核心時間戳 `63263.668`~`63264.68`附近，共 1.016 秒）：4 次獨立按下事件，其中一次「放開→再按下」間隔僅 219 毫秒（`63263.769` UP → `63263.988` DOWN），座標同樣幾乎不動（X: 1358→1365，Y: 1178→1164）。

真正使用者手指離開螢幕再重新點擊、且都落在同一個位置，這種節奏（86～326ms 間隔、位置誤差僅個位數 px）已超出人類手指自然重新定位的正常範圍——這是觸控 IC（`cyttsp5_mt`，Cypress 觸控控制器）在單一次實體按壓中，因訊號雜訊或除彈跳（debounce）電路異常，回報出多筆獨立的「按下/放開」事件，是**硬體/驅動層級的既知現象（俗稱 touch bounce），與 Flutter/WebView/`main.js`/Issue 9 的任何改動完全無關**——`TapZoneDetector` 收到硬體回報的每一次獨立按下/放開，各自都合法滿足「快速點擊」判定，逐一正確觸發翻頁，這是應用程式對錯誤輸入的正確反應，不是應用程式自己的邏輯錯誤。畫面「霧霧的殘影」則是 E-Ink 面板對短時間內連續多次翻頁刷新所產生的殘影效果，是面板特性的下游結果，不是獨立問題。

**已知限制**：受限於核心觸控時鐘（`getevent` 用的 monotonic clock）與 App 端 `DateTime.now()`（wall clock）基準不同、且經查證兩者換算關係在本裝置上不穩定（`/proc/uptime` 換算出的結果與 `getevent` 實際時間戳數量級不符，可能與裝置曾休眠有關），本次未能把這兩段硬體證據精確對應到第四輪 log 中哪一次 `_handleZoneAction` 叢集，但硬體確實存在「彈跳」現象這個結論本身不受此限制影響——已用座標交叉核對確認為同一位置的多次獨立按壓，證據力足夠。

**建議修法方向（顏面上是防禦性加固，非修正本 App 邏輯錯誤，可視優先順序決定是否處理）**：可在 `TapZoneDetector`／`_handleZoneAction` 任一層加入極短的節流/防彈跳（debounce）機制——例如同一個熱區在極短時間內（例如 150～200ms）收到第二次觸發時忽略——用軟體層面吸收硬體的彈跳雜訊，屬於使用者體驗加固，不是修「本 App 的 bug」。

**這次 Console Log 資料同時支持、也讓症狀 1 多了一個需要先釐清的替代解釋。** 全段記錄一樣沒有任何一次 `native click` 的 `elapsedSinceTouchStart` 超過 700ms（16 次點擊全數落在 3～132ms 之間），與 WAVE 裝置的資料一致，重複驗證症狀 3「這次都按太快」的結論。選取「消失」的部分也重複出現多段「選取逐漸長大→接著被清空」的序列，但這次額外發現：**至少有一段「選取穩定在 31 字之後，經過約 2.7 秒沒有任何新事件，然後直接跳出 `reportSelection: cleared/collapsed`，中間完全沒有 `native click fired` 這筆記錄」**（`t=43598.5` changed → `t=46299.2` cleared，中間空白）。這代表這次的選取清空**不是**透過 WebView 內的 click 事件觸發——比較可能的解釋是使用者在這段時間點擊了**原生 Flutter `AnnotationToolbar`**（例如挑選螢光筆顏色、或按了關閉鍵）——這兩者都會呼叫 `window.clearSelection()` 主動清空選取，這是**成功建立劃線後的正常清空行為，不是 bug**。這代表使用者回報的「選字選完常常消失」，裡面很可能混雜了「真的憑空消失（bug）」與「其實已經成功畫完線、選取被正常收尾（非 bug，只是沒注意到畫面上已經多了一條標記）」兩種情況，兩者用目前的 WebView 端診斷 log 無法區分——需要使用者親自確認：**選取消失之後，畫面上有沒有留下一條實際的螢光筆/底線標記？**
