# Epic 22 — 閱讀主題真正接上書本內容：Spec

本文件為 `epic-22-reader-theme-integration` 的 Architecting 階段產出，自本文件起成為本 Epic 的唯一事實來源（取代 `design.md`「待 Architecting 階段決定的實作細節」中列出的未定案項目）。背景與已確認的範圍決策見 `design.md`。

## Problem Statement

使用者在「設定 → 佈景」把主題切成深色（或羊皮紙）之後，只有書架、設定畫面等 App 外殼變色；一旦點進書本開始閱讀，流式 EPUB 的頁面背景/文字顏色，以及頁首（章節名稱）/頁尾（頁碼進度）疊加文字，完全沒有跟著變——目前頁首/頁尾文字色甚至是寫死的黑色。深色主題下使用者看到的閱讀畫面，仍然是白底黑字（頁首/頁尾）疊在書本原本的顏色上，跟使用者選的主題完全脫節，深色主題原本該有的「降低夜間閱讀刺眼感」效果完全沒有實現。

## Solution

使用者選擇深色／羊皮紙／預設淺色主題（或另外開啟 E-Ink 高對比模式）之後，開啟一本流式 EPUB 閱讀時，書頁背景色與內文文字色、以及頁首/頁尾疊加文字色，會一律套用與書架/設定畫面相同的主題配色——不論該本書自己的 CSS 宣告了什麼顏色。EPUB 固定版面（漫畫）與 PDF 因為是圖片內容，本次不套用內容變色；但固定版面的頁首/頁尾文字維持現有寫死顏色，不會因為套用主題色而在圖片頁面上變得不可讀。

## User Stories

1. 身為選擇深色主題的讀者，我希望流式 EPUB 頁面背景變深、文字變淺，這樣我才能在低光源環境下舒適閱讀而不刺眼。
2. 身為選擇羊皮紙主題的讀者，我希望流式 EPUB 頁面背景變成暖色米黃、文字變成深棕色，讓閱讀畫面跟我在其他畫面選的主題視覺一致。
3. 身為維持預設淺色主題的讀者，我希望流式 EPUB 頁面維持白底黑字（與目前既有行為相同），這樣沒有主動切換主題的使用者不會感受到任何變化。
4. 身為深色主題下的讀者，我希望頁首（章節名稱）與頁尾（頁碼進度）疊加文字是淺色、在深色頁面上看得清楚，這樣我才能持續掌握閱讀位置，不會因為文字融入背景而看不到。
5. 身為開啟一本自己 CSS 寫死特定顏色（例如作者自製「夜間模式」黑底、或彩色標題）的書的讀者，我希望我選的 App 主題色優先於書本自己宣告的顏色，這樣不論書本原始設計為何，我都能得到一致的閱讀體驗。
6. 身為開啟 E-Ink 高對比模式的讀者，我希望流式 EPUB 頁面套用固定黑白高對比（不論我底層選的是深色/羊皮紙/淺色哪一個），與書架/設定畫面既有的 E-Ink 行為一致，確保無障礙/減少殘影的效果延伸到書本內容本身。
7. 身為閱讀 EPUB 固定版面（漫畫）的讀者，我希望頁面圖片本身完全不受主題強制上色影響（圖片沒有文字層，硬上色沒有意義且可能扭曲原始美術），漫畫原本的色彩維持不變。
8. 身為在深色主題下閱讀 EPUB 固定版面（漫畫）的讀者，我希望頁首/頁尾疊加文字維持現有安全可讀的顏色（不要切成給深色頁面用的淺色），這樣文字才不會疊在通常是白底的漫畫頁面上而看不見。
9. 身為閱讀 PDF 的讀者，我希望這次的變更完全不影響我的閱讀體驗（維持現況），因為 PDF 的深色模式需要全新的色彩反轉濾鏡，是另一個獨立的、量級不同的功能，不在本次範圍。
10. 身為維護這個專案的工程師，我希望書本內容顏色與頁首/頁尾顏色來自完全同一個來源（`Theme.of(context)`），這樣未來不會有人只改了 `ThemeData` 沒改 CSS（或反之），導致兩邊顏色不同步。
11. 身為維護這個專案的工程師，我希望顏色強制覆蓋透過既有的 `main.js` CSS 注入機制達成（不修改 vendored `foliate-js` 檔案），符合 ADR 0011，並與既有的 `fontWeight`/`lineHeight` 強制覆蓋寫法保持一致的實作風格。
12. 身為驗證這個功能的人，我希望有 widget test 直接斷言傳給 `FoliateEpubReaderView` 的顏色參數、以及頁首/頁尾 `TextStyle` 的顏色值，涵蓋每種主題/E-Ink/固定版面組合，這樣往後的回歸不需要每次都用真機才能發現。
13. 身為完全沒動過主題設定的既有使用者（維持預設淺色主題、E-Ink 關閉），我希望這次改動上線後我看到的閱讀畫面顏色維持與 App 既有淺色主題視覺一致的近白背景／近黑文字（`AppTheme.light` 既有的 `#F8F8FA`／`#1A1A2E`），不會出現任何我沒預期到的色彩突兀變化——**註：這與「書本改動前完全不受任何顏色覆蓋、實際渲染色可能是書本 CSS 或瀏覽器預設的純白/純黑」存在細微但真實的差異，見下方「Further Notes」與程式碼審查記錄**。

## Implementation Decisions

- **`ReaderScreen`（`lib/screens/reader_screen.dart`）**：`build(BuildContext context)` 內直接讀取 `Theme.of(context).scaffoldBackgroundColor`（頁面背景色）與 `Theme.of(context).colorScheme.onSurface`（文字色），**不新增任何建構子參數**（`ReaderScreen` 本來就掛載於 `MaterialApp` 之下，`Theme.of(context)` 免費可用；已解析好 `AppTheme` + E-Ink 狀態的最終 `ThemeData` 由既有的 `resolveThemeData()` 提供，`ReaderScreen` 不需要重新知道 `AppTheme`/`isEinkMode` 原始值）。
  - 顯示流式 EPUB（`format == BookFormat.epub && !_isFixedLayout`）時，把這組顏色以新的建構子參數傳給 `FoliateEpubReaderView`，並用於頁首/頁尾 `TextStyle`。
  - 顯示 EPUB 固定版面（`_isFixedLayout == true`）時，傳給 `FoliateEpubReaderView` 的顏色參數為 `null`（比照 `fontWeight`/`lineHeight` 等既有欄位「FXL 不適用」時傳 `null` 的既有慣例），頁首/頁尾 `TextStyle.color` 維持寫死 `Colors.black`（與目前既有行為相同，不受本 Epic 影響）。
  - PDF 完全不受影響——頁首/頁尾 widget 呼叫點既有的 `format == BookFormat.epub` 判斷式已天然排除 PDF，不需新增任何判斷。
- **`FoliateEpubReaderView`（`lib/reader/foliate_epub_reader_view.dart`）**：新增兩個 nullable 建構子參數 `Color? textColor`／`Color? backgroundColor`，比照既有 `fontWeight`/`lineHeight` 的既有傳遞路徑：
  - `buildFoliatePreferencesMap()` 新增這兩個欄位（`null` 時不出現在 map 中，比照既有慣例），轉換為 CSS 合法的 6 位十六進位色碼字串（`#RRGGBB`）——**不可直接對 `Color.value` 呼叫 `toRadixString(16)`**：`Color.value` 是 32 位 `AARRGGBB`（alpha 在前），CSS 標準的 8 位十六進位色碼是 `#RRGGBBAA`（alpha 在後），順序相反，直接轉換會產生錯誤顏色而非只是格式問題；正確作法是取 `Color.value.toRadixString(16).padLeft(8, '0')` 後**捨棄前 2 碼 alpha**、保留後 6 碼 RGB，再補上 `#` 前綴（已用小腳本驗算 `0xFF121214`／`0xFF010203` 兩種案例，含 RGB 帶前導零的邊界情況，確認此轉法皆正確）。
  - `foliatePreferencesChanged()` 新增這兩個欄位的比對（`oldView.textColor != newView.textColor || oldView.backgroundColor != newView.backgroundColor`）——此函式目前窮舉比對每一個既有欄位以決定 `didUpdateWidget()` 要不要重新呼叫 `window.applyPreferences()`，新欄位須比照既有欄位一併加入，即使「閱讀中即時換主題」本身不是本 Epic 保證測試的情境（見 Out of Scope），仍應維持此函式「窮舉比對」的既有不變性，避免留下與其他欄位不一致的遺漏。
  - 轉換為十六進位色碼字串後併入既有送往 `main.js` 的 `prefs` 物件（同一個既有橋接呼叫，不新增橋接管道）。
- **`main.js` 的 `buildOverrideCss()`**：新增對 `prefs.textColor`／`prefs.backgroundColor` 的處理：
  - 比照既有 `fontFamily`／`textAlign` 等字串型欄位的既有寫法，用 `if (prefs.textColor)`／`if (prefs.backgroundColor)` 真值檢查才 push CSS 規則，避免 `undefined`/空字串污染產生的 CSS 字串（與函式內其餘欄位的既有風格一致）。
  - 文字色沿用既有廣選取器（`body, p, div, li, span, td, th, blockquote, dd, dt, a, h1-h6`）套用 `color`，與既有 `fontWeight`/`lineHeight` 強制覆蓋邏輯一致——確保書本在 `p`/`div`/`span` 等元素直接宣告的文字顏色也會被蓋過（沿用 Issue 34 已驗證過的「繼承值會輸給具體選取器」教訓）。
  - 背景色**僅套用 `html, body { background-color: ... !important; }`**，不使用上述廣選取器——避免在包裹圖片的 `div`/`span` 等元素上逐一畫出不協調的背景色塊（真實可見的視覺瑕疵，優先權高於「保證覆蓋書本每個區塊自訂背景色」這個較不常見的情境）。已知取捨：若書本在特定區塊（例如自訂樣式的引言框）直接宣告背景色，該區塊背景可能維持原色不被覆蓋——這是刻意接受的視覺瑕疵，不視為 bug。
  - `view.isFixedLayout` 分支（FXL）維持現狀，完全不呼叫 `setStyles()`/`buildOverrideCss()`（既有架構限制，見 `design.md`「範圍界定」）。
- **`app/lib/theme/` 目錄不變**：`app_theme.dart`／`app_theme_data.dart`／`app_theme_preferences.dart` 皆不修改——現有 `ColorScheme`/`ThemeData` 已透過標準 `Theme.of(context)` 存取子公開所需顏色，不需要新增顏色常數、查表或任何 theme 模組的新匯出。
- **`ResolvedPreferences`／`BookReaderPrefs`／`GlobalReaderPrefs` 不變**：主題顏色資料流獨立於這條既有的單書/全域偏好解析管線之外，不新增欄位、不持久化（`AppTheme`/`isEinkMode` 本身已由既有 `AppThemePreferences` 持久化，本 Epic 不重複儲存）。
- **E-Ink 高對比模式**：不需要在 `ReaderScreen` 內任何特殊分支處理——`Theme.of(context)` 已經是 `resolveThemeData()` 解析後的最終結果（E-Ink 開啟時已經是 `buildEinkThemeData()` 的白底黑字），`ReaderScreen` 讀到的就是正確的最終值。

## Testing Decisions

- **Seam 1**：`app/test/screens/reader_screen_test.dart`（既有檔案，既有 `tester.widget<FoliateEpubReaderView>(find.byType(FoliateEpubReaderView))` 斷言模式，比照既有 `fontWeight`/`lineHeight` passthrough 測試與 Issue 43 `expect(headerText.style?.color, Colors.black)` 的既有寫法）。驗證「`Theme.of(context)` → 正確的顏色物件」這一段。
- **Seam 2**：`app/test/reader/foliate_epub_reader_view_test.dart`（既有檔案，已有 `buildFoliatePreferencesMap`／`foliatePreferencesChanged` 兩個既有 `group`，這兩個函式本身就是「改為公開頂層純函式以便不透過 `InAppWebView` 直接單元測試」設計的，見既有檔案文件註解）。驗證「`Color` 物件 → 正確的 CSS 十六進位字串」與「新欄位是否正確併入 `foliatePreferencesChanged()` 的窮舉比對」這兩段，不需要透過 widget test 間接驗證。兩個 seam 涵蓋不同層次（widget 樹顏色解析 vs. 純函式資料轉換），皆為既有檔案既有 seam，不新增測試檔案。
- **要測的行為**（純外部可觀察行為，不測 `main.js` 內部字串拼接細節）：
  - 流式 EPUB：`AppTheme.light`／`dark`／`sepia` × `isEinkMode` 開/關，共 6 種組合下，`FoliateEpubReaderView.textColor`／`backgroundColor` 與頁首/頁尾 `TextStyle.color` 皆等於當下 `Theme.of(context)` 對應值。
  - EPUB 固定版面：不論 `AppTheme`/`isEinkMode` 為何，`FoliateEpubReaderView.textColor`／`backgroundColor` 皆為 `null`，頁首/頁尾 `TextStyle.color` 皆為 `Colors.black`（維持既有行為的回歸測試）。
  - 預設情境（`AppTheme.light`、E-Ink 關閉）：顏色值須等於 `AppTheme.light` 既有的 `scaffoldBackgroundColor`（`#F8F8FA`）／`colorScheme.onSurface`（`#1A1A2E`）——這是與 App 既有淺色主題殼層視覺一致的回歸保證，**不是**與「書本改動前完全不受任何顏色覆蓋的原始渲染色（可能是書本自己 CSS 或瀏覽器預設的純白/純黑）」逐位元組相同（程式碼審查發現的措辭精確度落差，見 Further Notes）。
- **明確不測的部分**：
  - WebView 實際渲染出來的像素顏色——`flutter test` 無法觀察 `InAppWebView` 內部渲染結果（比照本專案既有兩層測試架構慣例），留給真機/`integration_test` 人工視覺確認。
  - `main.js` `buildOverrideCss()` 產生的 CSS 字串本身的正確性——本專案目前沒有任何 JS 自動化測試框架（`check_foliate_es_compat.js` 是純文字掃描腳本，非單元測試），不在本 Epic 新增；若實作階段需要驗證邏輯正確性，比照 Issue 34 既有做法用臨時 headless Chromium 腳本驗證後即刪除，不留下永久測試資產。

## Out of Scope

- PDF 深色模式（需要全新原生色彩反轉濾鏡，量級與本次不同，另案評估）。
- EPUB 固定版面（漫畫）內容本身上色（圖片無文字層；letterbox 背景色維持 foliate-js 既有機制）。
- TXT 引擎（尚未開始開發）。
- 閱讀中即時換主題的響應式基礎建設（`SettingsScreen` 目前無法從 `ReaderScreen` 內部進入，此情境實務上不會發生；即使 `Theme.of(context)` 的 `InheritedWidget` 特性順帶讓這個情境「恰好也能動」，也不是本 Epic 主動設計或測試保證的行為）。
- 修改 `docs/prd.md`（FR-31 原文已涵蓋此範圍）。
- 修改 `readest/foliate-js` 釘定版本本身（ADR 0011）。
- 超連結（`<a>` 元素）顏色的特別處理——強制文字色覆蓋後，連結會與內文同色、失去預設藍色視覺區隔，這是既有強制覆蓋機制（`fontWeight`/`lineHeight` 已有的既定行為模式）延伸到 `color` 屬性後的自然結果，不視為本 Epic 需要另外解決的新問題。

## Further Notes

- 本 Epic 是 FR-31 既有需求的實作缺口補齊，不是新需求，`docs/prd.md` 維持不變。
- 背景色 CSS 覆蓋範圍限縮為 `html, body`（不用廣選取器）是本文件在 Architecting 階段做出的明確取捨決定；若未來實測發現太多書本因此殘留未被主題化的孤立色塊區塊，應另立後續 Issue 檢討，不影響本 Epic 先以目前方案落地。
- 未新增 ADR：「用共用 CSS 選取器強制覆蓋書本樣式」這個機制本身已是既有先例（epic-18 Issue 34 的 `fontWeight`/`lineHeight` 修法），本 Epic 只是把同一個既有機制延伸套用到 `color`/`background-color` 這兩個新屬性，不是新的架構決定，不符合「意外、需要脈絡才看得懂」的 ADR 門檻。

## 審查回應（`/superpowers:receiving-code-review`，2026-08-06）

`tmp/epic-22/spec_review_report.md` 對本文件初版提出 1 項 Important、2 項 Minor，逐項核實程式碼現況後全數採納：

- **項目 1（`foliatePreferencesChanged()` 需比對新欄位）**：查證 `foliate_epub_reader_view.dart` 現有 `foliatePreferencesChanged()` 窮舉比對每個既有欄位以決定是否重新呼叫 `applyPreferences()`，屬實。已納入 Implementation Decisions，即使目前唯一會讓「只有顏色變、其他都沒變」發生的情境（閱讀中即時換主題）已在 Out of Scope 排除，仍應維持此函式既有的窮舉比對不變性。
- **項目 2（顏色轉十六進位字串格式）**：寫小腳本驗算確認 `Color.value` 是 `AARRGGBB`（alpha 在前），CSS 8 位十六進位色碼標準是 `#RRGGBBAA`（alpha 在後），順序相反——若直接對 `Color.value` 呼叫 `toRadixString(16)`，不只是格式不美觀，會產生錯誤顏色。已納入 Implementation Decisions 並記錄正確轉法（`padLeft(8,'0')` 後捨棄前 2 碼 alpha）。
- **項目 3（`buildOverrideCss()` 真值檢查）**：查證既有 `fontFamily`／`textAlign` 等字串型欄位皆已用 `if (prefs.X)` 真值檢查才 push 規則，新欄位比照既有風格處理即可，已納入。

額外查證發現 `foliate_epub_reader_view_test.dart` 已有 `buildFoliatePreferencesMap`／`foliatePreferencesChanged` 的既有測試 `group`（這兩個函式本身就是為了不透過 `InAppWebView` 直接單元測試而設計的公開頂層純函式），比原規劃的單一 widget test seam 更精確，已補入 Testing Decisions 作為 Seam 2。

## 審查回應（`/superpowers:requesting-code-review`，Issue 1 實作，2026-08-06）

`tmp/epic-22/review-issue-1-implementation.md` 對 Issue 1 實作（分支 `epic-22-issue-1`，4 個 commit）審查為 With fixes（0 Critical／2 Important／2 Minor）。實作程式碼本身無需修改（`foliatePreferencesChanged()` 窮舉比對、`main.js` 背景色 `html,body` 選取器範圍等 spec.md 定案細節皆確認正確落實，全專案 990 個測試與 `flutter analyze` 皆乾淨），2 項 Important 皆已處理：

- **真機視覺驗證**：Task 5 Step 4（深色/羊皮紙/淺色/E-Ink 四種情境開流式 EPUB 實測）已人類確認完成並通過。
- **本文件用詞精確度**：審查指出 User Story 13／Testing Decisions 原文「跟改動前完全一樣」「零視覺變化」的字面承諾，與實際採用 `AppTheme.light` 既有殼層色值（`#F8F8FA`／`#1A1A2E`，近白/近黑而非純白/純黑）之間有微小但真實的落差——**這不是實作缺陷，是本文件當初措辭過於絕對**。已修正 User Story 13 與 Testing Decisions 相關段落，改為精確描述「與 App 既有淺色主題殼層視覺一致」，不再宣稱「完全一樣」。維持既有的「重用同一組殼層色值作為單一來源」設計決策不變（未改變任何程式碼行為），僅修正文件用詞。
