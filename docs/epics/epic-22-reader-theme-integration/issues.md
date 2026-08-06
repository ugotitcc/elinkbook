# Epic 22：閱讀主題真正接上書本內容——工單清單

依 `spec.md` 拆解為 2 個垂直切片（tracer bullet），依賴關係與拆分理由見 `docs/epics.md`/對話記錄：書頁內容變色（Dart→原生橋接→JS CSS 三層缺一都無法觀察到效果，須合併成同一張票）與頁首/頁尾文字變色（純 Flutter `TextStyle` 屬性，與內容變色走完全不同的程式路徑，可獨立完成與驗證）是兩條不相交的路徑，各自拆成一張票。

## Issue 1：流式 EPUB 內容強制套用主題色（背景色＋文字色）

**Status:** ✅ 已完成並合併（2026-08-06，分支 `epic-22-issue-1`，4 個 commit，依 `plans/plan-issue-1.md` Task 1-4 實作；`/superpowers:requesting-code-review` 審查 With fixes → 0 Critical／2 Important／2 Minor，真機視覺驗證已完成通過，`spec.md`/本檔案「零視覺變化」措辭已修正，詳見 `tmp/epic-22/review-issue-1-implementation.md`；已透過 **PR #119** 合併回 `main`，merge commit `62d60da`）

**依賴：** 無，可立即開始。

**對應 User Stories（`spec.md`）：** 1, 2, 3, 5, 6, 7, 9, 10, 11, 13

### What to build

`ReaderScreen` 顯示流式（reflowable）EPUB 時，讀取當下 `Theme.of(context)` 的頁面背景色與文字色，透過既有的 `main.js` CSS 覆蓋機制強制套用到書頁內容——不論書本自己的 CSS 宣告了什麼顏色。三種 `AppTheme`（深色/羊皮紙/預設淺色）與 E-Ink 高對比模式皆自動涵蓋（`Theme.of(context)` 已是解析後的最終結果，不需額外分支）。EPUB 固定版面（漫畫）與 PDF 完全不受影響，維持現狀。

端到端路徑：`ReaderScreen.build()` 讀 `Theme.of(context)` → 以新建構子參數傳給 `FoliateEpubReaderView` → 併入既有 `prefs` 物件送往 `main.js` → `buildOverrideCss()` 產生對應 CSS 規則、透過既有 `setStyles()` 機制套用到書頁。全程沿用既有的 `fontWeight`/`lineHeight` 強制覆蓋管線與风格，不新增橋接管道，不修改 vendored `foliate-js` 檔案（ADR 0011）。

**已知的關鍵實作細節（來自 spec.md 審查回應，務必落實）：**

- `Color` → CSS 十六進位色碼轉換**不可直接對 `Color.value` 呼叫 `toRadixString(16)`**：`Color.value` 是 `AARRGGBB`（alpha 在前），CSS 8 位色碼標準是 `#RRGGBBAA`（alpha 在後），順序相反，直接轉換會產生錯誤顏色。正確作法：`Color.value.toRadixString(16).padLeft(8, '0')` 後捨棄前 2 碼 alpha、保留後 6 碼 RGB，補上 `#` 前綴。
- `FoliateEpubReaderView` 新增的 `textColor`/`backgroundColor` 欄位須同步加入 `buildFoliatePreferencesMap()`（`null` 時不出現在 map 中）**與** `foliatePreferencesChanged()`（該函式窮舉比對每個既有欄位以決定是否重新呼叫 `applyPreferences()`，新欄位須一併加入比對，維持既有的窮舉不變性）。
- `main.js` `buildOverrideCss()` 新增規則須比照 `fontFamily`/`textAlign` 既有寫法，用 `if (prefs.textColor)`/`if (prefs.backgroundColor)` 真值檢查才 push 規則。
- 文字色沿用既有廣選取器 `body, p, div, li, span, td, th, blockquote, dd, dt, a, h1-h6` 套用 `color !important`。
- 背景色**僅套用 `html, body { background-color: ... !important; }`**，不使用上述廣選取器（避免圖片外層容器出現色塊，`spec.md` 已定案的取捨）。
- 顯示 EPUB 固定版面（`_isFixedLayout == true`）時，傳給 `FoliateEpubReaderView` 的 `textColor`/`backgroundColor` 為 `null`（`main.js` 的 `view.isFixedLayout` 分支本就完全跳過 `setStyles()`/`buildOverrideCss()`，此為既有架構限制而非本票新增邏輯）。

### Acceptance criteria

- [x] 流式 EPUB 顯示時，`FoliateEpubReaderView` 收到的 `textColor`/`backgroundColor` 等於當下 `Theme.of(context)` 對應的 `colorScheme.onSurface`/`scaffoldBackgroundColor`，涵蓋 `AppTheme.light`/`dark`/`sepia` × `isEinkMode` 開/關共 6 種組合。
- [x] EPUB 固定版面顯示時，不論 `AppTheme`/`isEinkMode` 為何，`FoliateEpubReaderView.textColor`/`backgroundColor` 皆為 `null`。
- [x] 預設情境（`AppTheme.light`、E-Ink 關閉）下，顏色值等於 `AppTheme.light` 既有的 `scaffoldBackgroundColor`（`#F8F8FA`）／`colorScheme.onSurface`（`#1A1A2E`）——與 App 既有淺色主題殼層視覺一致的回歸保證，非與書本改動前原始渲染色逐位元組相同（程式碼審查發現的措辭精確度落差，已修正 `spec.md`／本檔案用詞，見 `tmp/epic-22/review-issue-1-implementation.md`）。
- [x] `buildFoliatePreferencesMap()`／`foliatePreferencesChanged()` 的既有單元測試 `group`（`app/test/reader/foliate_epub_reader_view_test.dart`）擴充涵蓋新欄位的正確序列化（含十六進位色碼轉換的邊界案例，例如 RGB 帶前導零）與變更偵測。
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過（全專案 990 個測試）。
- [x] 真機人工視覺確認：流式 EPUB 書籍在深色主題下，書頁背景與文字實際變色，已完成並通過。

### Blocked by

None - can start immediately.

---

## Issue 2：頁首/頁尾文字色跟隨主題（流式 EPUB），固定版面維持現況

**Status:** ✅ 已完成並合併（2026-08-06，分支 `epic-22-issue-2`，1 個 commit，依 `plans/plan-issue-2.md` Task 1 實作，重用 Issue 1 既有的 `_themedTextColor`；真機視覺驗證已完成通過，符合計畫；`/superpowers:requesting-code-review` 審查 Ready to merge: Yes，0 Critical／0 Important，`flutter test` 130/130（本檔案）＋ 992/992（全專案）、`flutter analyze` 乾淨，詳見 `tmp/epic-22/review-issue-2-implementation.md`；審查過程中人類真機測試額外回報 3 項 UX 發現，皆與本 Issue 的 diff 無關，已另立 **Issue 3／4／5** 追蹤，見下方；已透過 **PR #120** 合併回 `main`，merge commit `71c81d6`）

**依賴：** 技術上無（不依賴 Issue 1 的任何程式碼變更，純 Flutter widget 屬性，與 Issue 1 走完全不同的程式路徑）。**建議與 Issue 1 一起驗收**——單獨完成本票、Issue 1 尚未完成時，會出現「頁首/頁尾變成深色主題文字、但書頁內容還是白底」的過渡期畫面。

**對應 User Stories（`spec.md`）：** 4, 8, 10, 13

### What to build

`ReaderScreen` 的頁首（章節名稱）與頁尾（頁碼進度）疊加文字顏色，目前寫死 `Colors.black`（epic-18 Issue 43 遺留）。顯示流式 EPUB 時，改為讀取 `Theme.of(context).colorScheme.onSurface`（與 Issue 1 書頁內容色同一來源，保證兩者視覺一致，不會日後只改一邊造成顏色漂移）；顯示 EPUB 固定版面（漫畫）時，維持現有寫死 `Colors.black`，新增 `!_isFixedLayout` 判斷排除——固定版面頁面內容本身不受 Issue 1 影響（維持原有顏色，通常是白底），若頁首/頁尾也跟著主題變成淺色文字，會在深色主題下疊在白底漫畫頁面上看不見。

PDF 不受影響——頁首/頁尾 widget 呼叫點既有的 `format == BookFormat.epub` 判斷式已天然排除 PDF。

### Acceptance criteria

- [x] 流式 EPUB 顯示時，頁首（章節名稱）與頁尾（頁碼進度）`TextStyle.color` 等於當下 `Theme.of(context).colorScheme.onSurface`，涵蓋 `AppTheme.light`/`dark`/`sepia` × `isEinkMode` 開/關共 6 種組合。
- [x] EPUB 固定版面顯示時，頁首/頁尾 `TextStyle.color` 不論 `AppTheme`/`isEinkMode` 為何皆維持 `Colors.black`（既有行為不變的回歸測試）。
- [x] 預設情境（`AppTheme.light`、E-Ink 關閉）下，既有 Issue 43 測試已更新為明確指定 `theme: buildThemeData(AppTheme.light)` 並比對其實際 `onSurface` 色值（不再依賴 Flutter 隱含預設主題）。
- [x] `app/test/screens/reader_screen_test.dart` 新增/擴充 widget test 涵蓋上述組合。
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過。

### Blocked by

None - can start immediately（建議與 Issue 1 一起完成後再一併真機驗收，理由見上方「依賴」）。

---

## Issue 3：閱讀器浮動按鈕（FAB）顏色未依主題調整

**Status:** ✅ 已完成並合併（2026-08-06，分支 `epic-22-issue3-reader-fab-theme`，1 個 commit，依 `plans/plan-issue-3.md` Task 1 實作；人類決策：底色/圖示色改為跟隨 `Theme.of(context)`〔非維持既有高對比黑底白圖示〕；`/superpowers:requesting-code-review` 審查建議合併，0 Critical／0 Important，`flutter test` 137/137（本檔案），`flutter analyze` 乾淨，詳見 `tmp/epic-22/review-issue-3-implementation.md`；已透過 **PR #121** 合併回 `main`，merge commit `7a23493`）

**依賴：** 無，可獨立排入規劃。

### What to build

流式 EPUB 閱讀畫面的 6 顆浮動圓形按鈕（返回／目錄／版面設定／書籤／筆記／進度-跳頁）原本一律用 `ClipOval(Container(color: Colors.black54, child: IconButton(icon: ..., color: Colors.white)))` 硬編碼樣式，與 `Theme.of(context)` 完全無關。比照 Issue 1/2 已建立的既有模式，新增 `_themedFabBackgroundColor`／`_themedFabIconColor` 兩個 non-nullable getter：顯示流式 EPUB 時，底色取 `colorScheme.onSurface`（54% 透明度）、圖示取 `colorScheme.surface`（角色分配刻意與直覺相反，避免重蹈 Issue 5 修過的「控制元件顏色與頁面背景太接近而失去可視性」問題——`surface` 在各主題下皆接近同主題頁面背景，若拿來當底色會讓按鈕在同色頁面上消失）；顯示 EPUB 固定版面（漫畫）時，維持既有寫死 `Colors.black54`/`Colors.white` 不變（頁面內容通常是白底圖片，不受本 Epic 影響）。PDF 不受影響（顯示條件天然排除）。

### Acceptance criteria

- [x] 流式 EPUB 顯示時，6 顆浮動按鈕的 `Container.color`/`Icon.color` 等於當下 `Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)`/`colorScheme.surface`，涵蓋 `AppTheme.light`/`dark` 主題。
- [x] EPUB 固定版面顯示時，按鈕顏色不論主題為何皆維持 `Colors.black54`/`Colors.white`（既有行為不變的回歸測試）。
- [x] `app/test/screens/reader_screen_test.dart` 新增 4 項測試：深色/淺色主題「返回」按鈕、固定版面黑白不變、深色主題「版面設定」按鈕（驗證有 `onPressed` 分流邏輯的按鈕同樣生效）。
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過（本檔案 137/137）。

### Blocked by

None - 已完成。

---

## Issue 4：深色主題下設定面板 Toggle 開關（關閉狀態）對比不足

**Status:** needs-triage（2026-08-06，`epic-22-issue-2` 審查過程中人類真機測試發現，非本 Epic 迴歸——`/superpowers:requesting-code-review` 查證根因在 `app_theme_data.dart` 既有色票設計，詳見 `tmp/epic-22/review-issue-2-implementation.md` Part 2 第 2 項）

**依賴：** 無，可獨立排入規劃。

### What to build（待 Discovery/規劃）

版面設定面板（`app/lib/screens/reader_settings_sheet.dart:297-333`）的 `SwitchListTile` 是標準 Flutter 元件，本身無任何硬編碼顏色、理論上應主題感知。真正根因是 `app/lib/theme/app_theme_data.dart` 深色主題的 `colorScheme.outline`（`#2A2A30`）與同主題 `background`（`#121214`）／`surface`（`#1E1E22`）亮度過於接近——Material 3 `Switch` 關閉狀態的 thumb/track 外框正是取自 `outline`，導致對比不足、難以辨識目前是關閉狀態。

需要 Discovery 階段決定：是否調整 `app_theme_data.dart` 深色主題的 `outline` 色值（**注意**：`epic-22` Issue 1/2 的 spec.md 明文決定「不修改 `app_theme_data.dart`」，但那個決定的前提是「這個檔案的色票設計本身沒有問題」——本 Issue 是發現色票設計本身有獨立缺陷，需要另外評估，不受該決定約束）；或改為只調整 `Switch` 元件層級的樣式覆蓋，不動全域色票（避免影響其他也用到 `outline` 的既有 UI）。

### Blocked by

None - can start immediately（規劃階段）。

---

## Issue 5：深色主題下點擊「進度/跳頁」按鈕，書籍內容區變成全黑不可辨識

**Status:** ✅ 已完成（2026-08-06，`/diagnose` 確認根因並修復，詳見 `reviews/bugfix-repro-issue5.md`）

**依賴：** 無。

### 根因（`/diagnose` 確認，非 WebView 合成 bug）

`reader_screen.dart` 全部 6 個 `showModalBottomSheet` 呼叫點（版面設定/PDF 設定/FXL 設定/目錄/筆記/進度）皆未指定 `barrierColor`，用 Flutter 框架預設值 `Colors.black54`——這個值完全沒被 Issue 1/2 改動過。用 Flutter 引擎真正的 `Color.alphaBlend()` 建立確定性驗證迴圈實測：Issue 1 上線前（書本原始背景近似白底）合成結果 RGB≈(117,117,117)，清楚可辨識；Issue 1 上線後（`AppTheme.dark` 背景 `#121214`）合成結果 RGB≈(8,8,9)，一般手機螢幕正常環境光下已與純黑無法區分。另外查證 `flutter_inappwebview`（6.1.5）`useHybridComposition` 預設值為 `true`（正是設計來避免這類半透明疊層合成異常的模式），排除原生合成 bug 的可能性。真正原因純粹是既有不變的遮罩值疊在 Issue 1 新增的深色背景上，數學上必然合成出人眼判讀為全黑的結果。

### 修法（人類確認：深色主題下取消遮罩；6 個彈窗一起修）

新增共用私有方法 `_showThemedModalBottomSheet<T>()`（`app/lib/screens/reader_screen.dart`），依 `Theme.of(context).brightness` 決定 `barrierColor`：深色主題 `Colors.transparent`，其餘（淺色/羊皮紙/E-Ink）維持 Flutter 既有預設值 `Colors.black54` 不變。全部 6 個原本直接呼叫 `showModalBottomSheet` 的地方改用這個共用方法，一次修正（不只 Issue 5 報告的進度面板）。

### Acceptance criteria

- [x] 深色主題下開啟任一 Bottom Sheet（進度／版面設定等），不再出現「真的會遮蔽畫面」的遮罩（`ModalBarrier` alpha > 0 的實例），書籍內容區維持可辨識。
- [x] 淺色/羊皮紙主題下遮罩行為維持 Flutter 既有預設值不變（回歸保證）。
- [x] `app/test/screens/reader_screen_test.dart` 新增 3 項回歸測試（深色主題進度面板、深色主題版面設定面板〔驗證共用 helper 套用到不只一個呼叫點〕、淺色主題回歸保證）。
- [x] `flutter analyze` 乾淨、`flutter test`（本檔案 133/133、全專案 995/995）全數通過。

### Blocked by

None - 已完成。
