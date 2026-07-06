# Epic 2 — 排版切換與直排核心：工單清單 (Issues)

依 `spec.md`（搭配 `design.md`、`docs/adr/0003-epub-reader-writing-mode-contract.md`）拆解出的細粒度垂直切片工單。Issue 1 為起始工單，Issue 2、3 皆依賴 Issue 1 完成，彼此可平行進行。

---

## Issue 1：`EpubReaderView` 契約擴充——`setWritingMode` + `onLayoutResolved`

**Status:** ✅ 已完成並合併回 `main`（PR #18，merge commit `c150442`）。4 個 task（`WritingMode`/`EpubLayoutInfo` 值型別、測試 fixtures、`onLayoutResolved`、`setWritingMode`）皆由 subagent 依 `plans/plan-issue-1.md` 實作、個別審查通過，最終整體審查結論 Ready to merge: Yes。已知的文件同步待辦：`spec.md`/ADR 0003 對原生實作細節的描述（`EpubSettingsResolver`/`Publication.metadata.presentation.layout`、`onWritingModeResolved` 回呼名稱與形狀）與實際採用的簡化寫法（`Metadata.layout`、`EpubNavigatorFragment.settings.value.verticalText`、`onLayoutResolved({isFixedLayout, writingMode})`）有落差，尚未回頭同步。

**依賴：** 無（起始工單）

**描述：**
依 `docs/adr/0003-epub-reader-writing-mode-contract.md` 與 `spec.md`「介面」章節，擴充既有的 per-instance method channel（`cc.ugotit.elinkbook/epub_reader_view_$id`）：

- **原生端（`EpubReaderView.kt`）**：新增 `setWritingMode` 處理，接收 `{'mode': 'horizontal' | 'vertical'}`，組出 `EpubPreferences(verticalText = mode == 'vertical')` 並呼叫目前 navigator 的 `submitPreferences()` 即時套用（不重新開書）。新增 `onLayoutResolved` 回呼，在 `openBook` 完成後觸發一次，回傳 `{'isFixedLayout': bool, 'writingMode': 'horizontal' | 'vertical'}`：`isFixedLayout` 讀取 `Publication.metadata.presentation.layout`；`writingMode` 讀取 `EpubSettingsResolver.resolveVerticalText(null, publication.metadata.language, publication.metadata.readingProgression)` 的解析結果。原生端需持有目前開啟中的 navigator 實例參照，供 `setWritingMode` 呼叫時使用。
- **Dart 端（`app/lib/reader/epub_reader_view.dart`）**：新增 `writingMode: WritingMode?` 建構參數與 `onLayoutResolved: ValueChanged<EpubLayoutInfo>?` 回呼；`didUpdateWidget` 中比較 `writingMode` 是否變動，變動且非 null 時呼叫原生 `setWritingMode`；`_handleMethodCall` 新增 `onLayoutResolved` case。
- **新增 `app/lib/reader/writing_mode.dart`**：定義 `enum WritingMode { horizontal, vertical }` 與 `class EpubLayoutInfo { final bool isFixedLayout; final WritingMode writingMode; }`（見 `spec.md`）。
- **測試 fixture**：確認 `app/test/fixtures/sample.epub` 是否已具備可讓 Readium 判斷出直排的語言/閱讀方向中繼資料（`lang="zh-TW"` 或等效）；不符合則另尋或製作一本語言中繼資料完整的直排 CJK 範例 EPUB，作為本 issue 與 Issue 3 共用的測試 fixture。

**單元測試要求：**
- Widget test：`writingMode` 由 `null` 變為非 `null`／由一個值變為另一個值時，會透過 mock `MethodChannel` handler 驗證原生端收到正確的 `setWritingMode` 呼叫與參數
- Widget test：模擬原生端觸發 `onLayoutResolved` 呼叫，驗證 `onLayoutResolved` callback 以正確解析出的 `EpubLayoutInfo`（`isFixedLayout`、`writingMode`）觸發
- 純 Dart 單元測試：`WritingMode`／`EpubLayoutInfo` 的建構與相等性
- `integration_test`（真實裝置，必要）：
  - 對範例直排 CJK EPUB 呼叫 `openBook`，斷言 `onLayoutResolved` 有觸發且 `isFixedLayout == false`、`writingMode == WritingMode.vertical`
  - 開書成功後呼叫 `setWritingMode(horizontal)` 再呼叫 `setWritingMode(vertical)`，斷言畫面持續渲染成功（沿用既有「loading indicator 消失且無 error」斷言模式），驗證即時切換不會導致崩潰或錯誤狀態
  - 對一本非 CJK 語言（如英文）的既有 `sample.epub` 呼叫 `openBook`，斷言 `onLayoutResolved` 的 `writingMode == WritingMode.horizontal`（回歸驗證，確保自動判斷不會誤判非 CJK 書籍）

**驗收標準：**
- 上述測試皆通過
- `flutter analyze` 乾淨
- 這條切片本身可獨立展示：即使還沒有 UI 按鈕，透過 `integration_test` 或手動呼叫也能證明「開書後即時切換橫直排」與「自動判斷初始模式」均正確運作

---

## Issue 2：`ReaderScreen` 橫直排切換按鈕 UI 串接

**依賴：** Issue 1

**描述：**
在 `app/lib/screens/reader_screen.dart` 中，格式為 EPUB 時內部管理 `WritingMode? _writingMode`（初始 `null`）與 `bool _isFixedLayout`（初始 `false`）狀態：收到 `EpubReaderView` 的 `onLayoutResolved` 後更新這兩個狀態；`_isFixedLayout == false` 時在 AppBar 顯示橫直排切換按鈕（單一 `IconButton`，見 `design.md`「UI」一節——`prototype/index.html:1481-1482` 實際上屬於 FR-10／`epic-3` 的持久化覆寫面板，本 issue 改為獨立設計的簡易切換鈕），按下時翻轉 `_writingMode` 並 `setState`，驅動 `EpubReaderView` 以新的 `writingMode` 值重建。`ReaderScreen(filePath: String)` 對外建構參數維持不變，不新增公開建構參數/callback。

**單元測試要求：**

**修正（依 Issue 1 的實測經驗）：** `ReaderScreen` 直接建構真正的 `EpubReaderView`（無法替換成假物件，見 `CLAUDE.md`「唯一閱讀器 seam」約定），其 `onLayoutResolved`／`onError` 等回呼只有在真實原生 `PlatformView` 建立後才會觸發，一般 `flutter test`（無裝置）無法驅動。但實測確認：純粹把 `ReaderScreen(filePath: 'test/fixtures/sample.epub')` `pumpWidget` 進 `flutter test`（無裝置）並不會卡住或報錯（`AndroidView` 在無原生引擎時單純不觸發回呼、不影響 widget 樹建構），因此「初始狀態」（`onLayoutResolved` 觸發前）仍可用一般 `flutter test` 驗證；只有「`onLayoutResolved` 觸發後的狀態轉換」需要 `integration_test` 真機驗證。

- Widget test（`flutter test`，不需裝置）：EPUB 格式初始顯示切換按鈕，但因 `_writingMode` 仍為 `null`（尚未收到 `onLayoutResolved`）而處於停用狀態（`onPressed == null`）
- Widget test（`flutter test`，不需裝置）：PDF 格式不顯示切換按鈕
- `integration_test`（真機，使用 Issue 1 已建立的三本 fixture）：
  - 開啟 `sample.epub`（自動判斷為直排）後，按鈕轉為啟用狀態，`tooltip` 顯示「切換為橫排」
  - 開啟 `sample_horizontal.epub`（自動判斷為橫排）後，`tooltip` 顯示「切換為直排」
  - 開啟 `sample_fixed_layout.epub` 後，按鈕最終不顯示（`isFixedLayout` 回報為 `true`）
  - 開啟 `sample.epub` 後點擊切換按鈕，`tooltip` 反轉為「切換為直排」且不觸發 `onError`

**驗收標準：**
- 上述測試皆通過
- 手動驗證：開啟一本 reflowable EPUB，畫面上按下切換按鈕能立即看到橫直排視覺切換；開啟一本 fixed-layout EPUB，切換按鈕不顯示

---

## Issue 3：FR-32 避頭尾符合度驗證（CNS 11643）

**依賴：** Issue 1（需要直排渲染已可運作才能檢視）

**描述：**
使用 Issue 1 準備的直排 CJK 範例 EPUB fixture，在真實裝置上開啟並切換為直排模式，人工視覺比對 Readium 內建 `cjk-vertical` ReadiumCSS（`line-break: strict` 等規則，見 `spec.md`「已驗證的技術基礎」）的標點轉向/置中與避頭尾換行表現，是否符合 CNS 11643 或同等標準所定義的避頭尾字元集合。

這是一項**驗證/研究性質**的工單，不預先假設一定要動到程式碼：

- 若驗證結果符合預期：在本 issue 的驗收記錄中說明比對方法與結論，不需修改程式碼。
- 若發現落差：記錄具體差異字元（哪些標點在行首/行尾出現了不該出現的斷行），評估最小化覆寫方案的可行性（是否有 Readium 提供的 user stylesheet／樣式覆寫擴充點可用），並在 `spec.md`「範圍外」章節提到的「另立後續 issue」原則下，視落差嚴重程度決定是否需要新增一筆後續 issue 處理，不在本 issue 內展開覆寫實作。

**單元測試要求：**
- 無自動化測試（人工視覺 QA 性質）；驗證方法與比對結果需記錄成書面紀錄（例如附截圖或逐字元比對表），供後續複查

**驗收標準：**
- 產出一份驗證紀錄，明確結論「符合 CNS 11643」或「發現以下落差：...」
- 若有落差且需要後續處理，已建立對應的後續 issue 追蹤（不阻塞本 epic 其餘 issue 的合併）

---

## Issue 4：直排分頁「欄位高度非行高整數倍」導致文字上下裁切——暫行方案評估

**Status:** ⚪ 未開始

**依賴：** Issue 3（本 issue 的根因分析與重現記錄）

**背景：** Issue 3 的實機驗證與根因調查（見 `qa-issue-3-writing-mode-verification.md`）研判：直排（vertical-RL）閱讀模式下，`readium-navigator:3.3.0` 內建的 `cjk-vertical` ReadiumCSS 把每一欄（頁）的高度設為 CSS `100vh`，未確保其為行高（line-height）的整數倍，可能導致某些頁面的最後一行文字被物理裁切於欄位邊界（畫面上緣或下緣出現半個字）。此為 Readium/CSS 多欄分頁機制在直排書寫模式下的已知上游限制（`readium/swift-toolkit#804`、`readium/readium-css#141`——後者顯示上游團隊已將直排分頁的完整支援 park），並非本專案 `EpubReaderView.kt`/`EpubReaderView.dart` 的程式碼缺陷，因此無法透過本專案自行維護的 user stylesheet 覆寫徹底修復（CSS Fragmentation 規格層級限制，非樣式覆寫可解決）。此段落的確切信心等級（尚未經實機交叉確認）見下一段。

**信心等級說明（誠實揭露）：** 上述根因判定主要依據為靜態分析（親自重新解壓 `readium-navigator:3.3.0` AAR 讀取 `ReadiumCSS-after.css` 內容）與 upstream issue 交叉比對，並有 Task 5 緩解方案實驗佐證（`EpubPreferences(scroll = true)` 後，同一拖曳手勢可從書首一路推進到書尾，證實渲染/互動行為確實從分頁改為捲動，且捲動模式下未觀察到裁切）。但由於 Task 3 的實機重現嘗試因翻頁手勢未能成功觸發 Readium 底層翻頁，始終沒有在分頁模式下實際觀察到真正的欄位邊界，因此本結論屬於「靜態分析支持、緩解實驗佐證，但未經『分頁模式下裁切現象本身』的實機交叉確認」信心等級，細節見 `qa-issue-3-writing-mode-verification.md`「四、根因分析」結尾段落。本 issue 的測試要求（見下）在落地暫行方案時，會一併補上這項尚缺的交叉驗證。

**描述：** 評估並決定下列其中一種（或組合）解決方向，與 `epic-3-fonts-layout` 既有規劃的「換頁模式（捲動 vs 無）」控制項整合（不要為此另外新增一套獨立的模式切換 UI）：

- **方案一（已驗證可行）：** 依 Issue 3 Task 5 已驗證可行的暫行方案（`EpubPreferences(scroll = true)`），直排模式預設或提供選項改用捲動渲染，避免分頁欄位裁切。
- **方案二（尚未評估，`qa-issue-3-writing-mode-verification.md`「四、根因分析」已記錄此選項）：** 移植 `readium/swift-toolkit#804` 回報者提出的修法——在字型載入完成後，用 JavaScript 把欄位容器的 `height` 對齊到行高整數倍（`Math.floor(clientHeight/lineHeight)*lineHeight`），讓分頁模式本身不再產生裁切，不需改用捲動。此方案需要額外評估是否能透過 Readium 提供的擴充點（例如 user script／CSS 注入）在不修改 Readium 原始碼的前提下實作。

需要決定：(a) 採用方案一、方案二、或兩者並存供使用者選擇；(b) 若最終仍保留分頁模式作為選項，是否需要顯示裁切風險提示；(c) 是否需要監控未來 `readium-kotlin-toolkit`/`readium-css` 版本更新是否修復此上游限制，屆時可移除本暫行方案。

**單元測試要求：**
- `integration_test`（真機）：直排模式下使用捲動渲染時，翻閱 Issue 3 的 `sample_long_vertical.epub` 全書，確認無 `onError` 觸發、`onPageRendered` 正常觸發。
- 人工視覺 QA：比照 Issue 3 Task 3 的重現條件矩陣，確認捲動模式下原本會裁切的頁面不再出現裁切。

**驗收標準：**
- 已決定直排模式的預設渲染方式（分頁或捲動），並有明確理由記錄於本 issue 或對應的 `epic-3-fonts-layout` spec 中。
- 上述測試皆通過。

---

## Issue 5：FR-32 避頭尾換行規則——長段落 fixture 補強與重新驗證

**Status:** ⚪ 未開始

**依賴：** Issue 3（本 issue 為 Issue 3 驗證範圍缺口的後續補強）

**背景：** Issue 3 的 FR-32 驗證（見 `qa-issue-3-writing-mode-verification.md`「一、FR-32 標點轉向與避頭尾比對」）已確認六類常見標點/避頭尾規則中，四類（破折號、刪節號、書名號、一般標點置中）符合 CNS 11643 預期。另外兩類——收尾類標點（」』）］｝、。，；：？！）不可置於行首、起頭類標點（「『（〔［｛《〈）不可置於行尾——**未能在本次測試中被實際觸發驗證**：Issue 1 建立的 `sample_long_vertical.epub` fixture 全書 60 段內容皆為可完整容納於單一欄位（頁）內的短句，段落與欄位邊界永遠精準對齊，從未發生「連續文字因欄高被強制換行」的情形，因此無從觀察 Readium `line-break:strict` 在真正需要避頭尾判斷時的實際渲染表現。這是測試覆蓋範圍的缺口，不是已確認的渲染缺陷——CNS 11643 避頭尾規則本身是否被正確遵守，目前仍是未知數。此項落差與 Issue 4（裁切問題根因已確認，需要的是渲染模式決策）成因與後續處理方式完全不同，故獨立追蹤。

**描述：** 新增（或擴充既有）一份直排 CJK fixture，其中至少包含一段足夠長的連續文字，長度需超過裝置在常見字級/欄寬設定下單一欄位可容納的字數，使 Readium 的分頁引擎必須在段落內部強制換行，且換行點前後鄰接的字元中，刻意安排收尾類標點（例如句尾恰好接一個逗號或句號）與起頭類標點（例如刻意讓左引號/左括號可能落於行尾處）。以此 fixture 重新執行 Issue 3「一、FR-32 標點轉向與避頭尾比對」表格中未能驗證的兩個類別，比對換行後標點實際落點是否遵守避頭尾規則（收尾類標點應被推至下一欄開頭而非留在本欄結尾、起頭類標點應被留在本欄結尾或推至下一欄開頭而非獨自出現在行尾/行首）。

**單元測試要求：**
- 人工視覺 QA（真機）：對照 Issue 3 已用的比對方法（`adb shell screencap` 截圖 + 逐字元比對），針對新 fixture 的強制換行段落，確認收尾類標點不出現在欄位最上方、起頭類標點不出現在欄位最下方。
- 若發現不符合預期的渲染結果，記錄具體差異字元、發生位置、截圖檔名，並依 `spec.md`「範圍外」章節原則評估是否需要 Readium user stylesheet 覆寫或另立修復 issue。

**驗收標準：**
- 產出補充驗證紀錄，針對這兩個先前未能驗證的類別給出明確結論（「符合」或「發現以下落差：...」），不得再次因 fixture 限制而懸而未決。
- 若發現落差，已依 Issue 3 相同原則決定是否需要新增後續修復 issue。
