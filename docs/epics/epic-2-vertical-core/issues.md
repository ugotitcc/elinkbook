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
