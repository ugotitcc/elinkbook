# Epic 22 — 閱讀主題真正接上書本內容：Discovery

## 背景

使用者提出需求：「新增深色/夜間主題（Dark Mode）時，書本與頁首頁尾配合 `Theme.of(context)` 動態調整前景文字顏色」。`/grill-with-docs` Discovery 前先盤點既有程式碼，發現關鍵事實：

- 專案已有 `AppTheme` enum（`app/lib/theme/app_theme.dart`，`light`/`dark`/`sepia` 三選一），`CONTEXT.md` 也已定義「主題（Theme）」為「三選一的全域閱讀色彩配置」——`dark` 本來就是既有選項之一，**不是全新概念**。
- 這個 `AppTheme` 目前**只接到 `MaterialApp(theme:)`**（`main.dart:189-210`），只影響 App chrome（`LibraryScreen`／`SettingsScreen` 等用 `Theme.of(context)` 的畫面）。`ReaderScreen`（`app/lib/screens/reader_screen.dart`）完全沒有 import `theme/app_theme.dart`，也沒有任何 `Theme.of(context)` 用例——**書本內容（EPUB WebView／PDF）目前完全不受主題設定影響**。
- 頁首/頁尾文字顏色（`reader_screen.dart:1826, 1847`，`_buildFoliateHeaderText()`／`_buildFoliateEpubFooter()`）是本次 Discovery 前一輪 `/diagnose`（epic-18 Issue 43）才剛修過，目前**寫死 `Colors.black`**，理由是「拿掉按鈕底色後，白色文字疊在淺色書頁背景上看不到，改用與書本內文一致的黑色」——這個假設在深色主題下會立即失效（黑字疊黑底）。

`docs/prd.md` FR-31「主題外觀」原文：「支援深色 (Dark)、羊皮紙 (Sepia)、預設 (Light) 等多種閱讀主題切換，並可與現有 E-Ink 高對比模式並存」——本 Epic 的範圍是**補齊這條需求一直沒做到的部分**（書本內容/頁首頁尾從未跟著主題變），不是新增需求，`docs/prd.md` 本身無需修改。

## 決策（`/grill-with-docs` 逐項確認）

1. **範圍定位**：把既有 `AppTheme` 真正接上書本內容與頁首/頁尾，不引入第二套獨立機制（例如跟隨系統 OS 深色模式的 `ThemeMode.system`）。
2. **格式範圍**：僅**流式（reflowable）EPUB**。
   - PDF 排除：原生點陣圖渲染（`PdfRenderer` 產生的圖片），沒有獨立「文字顏色」可調，唯一能做深色效果的方式是新增色彩反轉（invert）濾鏡——目前完全沒有這個機制（只有既有的對比度/亮度/加粗濾鏡），是另一塊全新的原生功能，另案評估。
   - EPUB 固定版面（FXL，如漫畫）排除：內容本質是圖片，沒有可重新上色的文字層，強制覆蓋文字/背景色對圖片內容本身沒有意義；圖片四周的信件夾（letterbox）背景色維持 foliate-js 既有機制不變。
   - TXT 引擎尚未開始開發（Backlog），天然排除。
3. **顏色策略**：強制覆蓋——不論書本自己的 CSS 宣告什麼顏色，主題色一律覆蓋文字色與背景色（前景+背景一起改，不是只改文字色）。
4. **主題範圍**：三種主題（深色/羊皮紙/預設淺色）一併修正，不只深色——避免日後羊皮紙主題也要再補一次。
5. **顏色來源（單一來源常數）**：頁首/頁尾的 Dart `TextStyle` 與 EPUB CSS 注入都從同一組顏色值取值，保證兩邊視覺永遠一致，不會因為只改了 `ThemeData` 沒改 CSS（或反之）而漂移。
   - `app/lib/theme/app_theme_data.dart` 現有的 `background`／`onSurface` 私有常數（例如深色主題 `#121214`／`#E8E8EC`、羊皮紙主題 `#F4ECD8`／`#5B4636`）本身已是取自 `prototype/index.html` 設計、適合長時間閱讀的配色，且已經是建構 `ThemeData`/`ColorScheme` 的來源。**這組值本身就是唯一來源，不需要另外新增一個平行的 `AppTheme → {前景色, 背景色}` 對照表**（設計文件初版規劃了一份獨立查表，經審查與覆核後確認多餘，見下方「審查回應」）。
   - `background` vs `surface` 兩個 Material color role 該用哪一個代表閱讀頁背景，留給 `spec.md` 決定（視覺微調，非本次 grilling 需要卡住的分支）。
6. **E-Ink 高對比模式**：開啟時比照 App chrome 既有行為——不論底層選哪個 `AppTheme`，EPUB 內容也強制變成固定黑白高對比（沿用 `buildEinkThemeData()` 既有的白底黑字定義），與頁首/頁尾一致。
7. **顏色取得方式**：`ReaderScreen` 掛載於 `LibraryScreen`（在 `MaterialApp.home` 底下）之下，`ReaderScreen.build(context)` 本來就拿得到已解析好 `AppTheme`＋E-Ink 狀態的 `Theme.of(context)`（`resolveThemeData()` 的輸出），**不需要新增 `AppTheme`／`isEinkMode` 建構參數**，直接讀取即可，比原規劃更簡單（見下方「審查回應」）。因為 `Theme.of(context)` 是 `InheritedWidget`，`ReaderScreen` 若在祖先 `Theme` 改變時仍掛載於樹上，會自動 rebuild 反映新顏色，不需另外設計即時通知機制——但此為附帶效果，不是本 Epic 主動追求的目標（`SettingsScreen` 目前無法從 `ReaderScreen` 內部進入，「閱讀中即時換主題」實務上不會發生）。
8. **Epic 歸屬**：另立新 Epic `epic-22-reader-theme-integration`，不併入 `epic-18-reader-device-qa`——後者定位是「真機 UI 精修」，本 Epic 是 FR-31 的完整能力缺口，性質不同。
9. **FXL 頁首/頁尾**：`_buildFoliateHeaderText()`／`_buildFoliateProgressText()`（頁首/頁尾文字）目前的呼叫點只用 `format == BookFormat.epub` 判斷（`reader_screen.dart:1658-1694`），**流式 EPUB 與 FXL 目前共用同一組頁首/頁尾**，沒有排除 FXL。由於本 Epic 的內容強制上色範圍不含 FXL（圖片頁面，顏色不可預期，通常維持白底），若頁首/頁尾顏色改為跟隨 `AppTheme`，深色主題下會在 FXL 頁面上出現淺色文字疊淺色/白色頁面、看不見的問題。**決策：頁首/頁尾跟隨 `AppTheme` 的範圍需額外加上 `!_isFixedLayout` 判斷，僅在顯示流式 EPUB 時生效；顯示 FXL 時頁首/頁尾維持現況（寫死 `Colors.black`，不受本 Epic影響）**，與內容範圍保持一致（見下方「審查回應」）。

## 範圍界定

- 僅涵蓋流式 EPUB 的內文文字色/背景色，以及**僅在顯示流式 EPUB 時**的頁首/頁尾文字色（見決策 9）。
- 不涵蓋：PDF（需要全新色彩反轉濾鏡，另案評估；PDF 亦不會顯示這組頁首/頁尾 widget，`format == BookFormat.epub` 判斷式已天然排除，見下方「審查回應」）、EPUB FXL（圖片內容無文字層，且 `main.js:152` 的 `view.isFixedLayout` 分支已明確跳過 `setStyles()`／`buildOverrideCss()`，呼叫甚至會拋 `TypeError`——FXL 排除不只是本 Epic 的範圍選擇，是既有架構的硬限制）、TXT（引擎未開始開發）。
- 不修改 `readest/foliate-js` 釘定版本本身（見 ADR 0011）——顏色覆蓋透過本專案自己的 `main.js` CSS 注入機制達成，比照既有 `fontWeight`/`lineHeight` 強制覆蓋的既有作法（`main.js` 共用 selector 直接覆蓋，見 epic-18 Issue 34 診斷紀錄），不改 vendored 檔案。
- 不修改 `docs/prd.md`——FR-31 原文本來就涵蓋這個範圍，本 Epic 是實作缺口的補齊，非需求變更。

## 待 Architecting 階段（`spec.md`）決定的實作細節

- 背景色採用 `app_theme_data.dart` 現有的 `background` 還是 `surface` 色值。
- CSS 注入的具體實作位置（`main.js` 的 `buildOverrideCss()` 或新增獨立函式）與 selector 設計。
- **背景色 CSS 覆蓋範圍的取捨**：既有 `buildOverrideCss()` 選取器（`body, p, div, li, span, td, th, blockquote, dd, dt, a, h1-h6`）套用文字色可直接沿用（與既有 `fontWeight`/`lineHeight` 覆蓋邏輯一致，確保書本自己在 `p`/`div` 等元素直接宣告的顏色也能被蓋過）；但**背景色**若沿用同一組廣選取器，逐一元素套用 `background-color`，可能在圖片外層容器（`div`/`span` 包裹 `img`）上畫出不協調色塊。兩個選項：(A) 背景色比照文字色套用同一組廣選取器，優先保證覆蓋書本自己宣告的背景色（可能有色塊風險）；(B) 背景色僅套用 `html, body`，避免色塊風險，但代價是書本若在特定區塊（例如 `div.chapter`）直接宣告背景色，該區塊仍可能維持原色不被覆蓋。兩者皆為真實權衡，於 `spec.md` 決定。
- 測試策略：EPUB WebView 實際渲染結果無法在 `flutter test` 觀察（比照既有兩層測試架構慣例），驗證重點放在「JS 橋接呼叫參數是否正確」（widget test 可觀察）與「真機/`integration_test` 視覺確認」兩層。

## 審查回應（`/superpowers:receiving-code-review`，2026-08-06）

`tmp/epic-22/review_design_report.md` 對本文件初版提出 2 項 Important、2 項 Minor。逐項核實程式碼現況後：

- **隱患 1（即時換主題防禦性）＋隱患 4（prop drilling）**：技術結論成立但理由需修正——不是「要防範系統深色模式/未來假設情境」（本 Epic 已明確排除跟隨系統 `ThemeMode`，見決策 1），而是查證後發現 `ReaderScreen` 本來就掛載於 `MaterialApp` 之下，`Theme.of(context)` 免費可用，沒理由新增建構參數多繞一層。已採納，改為決策 7。
- **隱患 2（PDF/FXL 白底白字）**：PDF 部分為誤判——`_buildFoliateHeaderText()`／`_buildFoliateProgressText()` 呼叫點皆以 `format == BookFormat.epub` 判斷式包住（`reader_screen.dart:1658-1694`），PDF 格式不會顯示這組 widget，不受影響。FXL 部分屬實——該判斷式未排除 FXL，流式 EPUB 與 FXL 目前共用同一組頁首/頁尾，而本 Epic 的內容上色範圍不含 FXL，兩者顏色假設會脫節。已採納 FXL 部分，新增決策 9；PDF 部分不採納（已於「範圍界定」註明澄清）。
- **隱患 3（CSS 選取器污染）**：部分成立——查證 `main.js:69-119` 確認既有選取器並非萬用 `*`，且 `main.js:152` 證實 FXL 本就完全跳過 `setStyles()`（強化決策 2 的 FXL 排除理由，不只是偏好）。背景色選取器範圍的真實取捨（廣選取器 vs. `html,body` 限縮）已記錄為 `spec.md` 待決項，不在 Discovery 階段自行拍板。

