# Epic 22：閱讀主題真正接上書本內容——工單清單

依 `spec.md` 拆解為 2 個垂直切片（tracer bullet），依賴關係與拆分理由見 `docs/epics.md`/對話記錄：書頁內容變色（Dart→原生橋接→JS CSS 三層缺一都無法觀察到效果，須合併成同一張票）與頁首/頁尾文字變色（純 Flutter `TextStyle` 屬性，與內容變色走完全不同的程式路徑，可獨立完成與驗證）是兩條不相交的路徑，各自拆成一張票。

## Issue 1：流式 EPUB 內容強制套用主題色（背景色＋文字色）

**Status:** ✅ 已完成（2026-08-06，分支 `epic-22-issue-1`，4 個 commit，依 `plans/plan-issue-1.md` Task 1-4 實作；`/superpowers:requesting-code-review` 審查 With fixes → 0 Critical／2 Important／2 Minor，真機視覺驗證已完成通過，`spec.md`/本檔案「零視覺變化」措辭已修正，詳見 `tmp/epic-22/review-issue-1-implementation.md`）

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

**Status:** ready-for-agent

**依賴：** 技術上無（不依賴 Issue 1 的任何程式碼變更，純 Flutter widget 屬性，與 Issue 1 走完全不同的程式路徑）。**建議與 Issue 1 一起驗收**——單獨完成本票、Issue 1 尚未完成時，會出現「頁首/頁尾變成深色主題文字、但書頁內容還是白底」的過渡期畫面。

**對應 User Stories（`spec.md`）：** 4, 8, 10, 13

### What to build

`ReaderScreen` 的頁首（章節名稱）與頁尾（頁碼進度）疊加文字顏色，目前寫死 `Colors.black`（epic-18 Issue 43 遺留）。顯示流式 EPUB 時，改為讀取 `Theme.of(context).colorScheme.onSurface`（與 Issue 1 書頁內容色同一來源，保證兩者視覺一致，不會日後只改一邊造成顏色漂移）；顯示 EPUB 固定版面（漫畫）時，維持現有寫死 `Colors.black`，新增 `!_isFixedLayout` 判斷排除——固定版面頁面內容本身不受 Issue 1 影響（維持原有顏色，通常是白底），若頁首/頁尾也跟著主題變成淺色文字，會在深色主題下疊在白底漫畫頁面上看不見。

PDF 不受影響——頁首/頁尾 widget 呼叫點既有的 `format == BookFormat.epub` 判斷式已天然排除 PDF。

### Acceptance criteria

- [ ] 流式 EPUB 顯示時，頁首（章節名稱）與頁尾（頁碼進度）`TextStyle.color` 等於當下 `Theme.of(context).colorScheme.onSurface`，涵蓋 `AppTheme.light`/`dark`/`sepia` × `isEinkMode` 開/關共 6 種組合。
- [ ] EPUB 固定版面顯示時，頁首/頁尾 `TextStyle.color` 不論 `AppTheme`/`isEinkMode` 為何皆維持 `Colors.black`（既有行為不變的回歸測試）。
- [ ] 預設情境（`AppTheme.light`、E-Ink 關閉）下，新增本功能前後的顏色值與既有測試（含 Issue 43 既有的 `expect(headerText.style?.color, Colors.black)` 類斷言，此時仍應為黑色，因為預設淺色主題的 `onSurface` 本來就是黑色系）完全相同。
- [ ] `app/test/screens/reader_screen_test.dart` 新增/擴充 widget test 涵蓋上述組合。
- [ ] `flutter analyze` 乾淨、`flutter test` 全數通過。

### Blocked by

None - can start immediately（建議與 Issue 1 一起完成後再一併真機驗收，理由見上方「依賴」）。
