# epic-2-vertical-core 排版切換與直排核心 —— Design（Discovery 階段產出）

## 對應 PRD 需求

FR-05（橫直排一鍵切換；直排模式圖片/標題不得跨頁切斷）、FR-06（開啟 ePub3 時自動偵測排版方向）、FR-32（直排標點轉向/置中與避頭尾規則，符合 CNS 11643 或同等標準）。

## 目標

把目前 `EpubReaderView` 固定橫排渲染的行為，擴充為可自動偵測、可即時手動切換的橫排／直排（vertical-RL）閱讀體驗，並確保直排模式下的標點符號轉向/置中與避頭尾換行規則符合中文直排排版慣例。

## 範圍與排除項目

**本 epic 涵蓋：**
- 僅處理**流式（reflowable）EPUB**的橫直排一鍵切換
- 開啟 EPUB 時的自動偵測（FR-06）
- 直排標點與避頭尾規則（FR-32）
- 直排模式下圖片與標題不得跨頁切斷（FR-05 後半句）
- 擴充 `EpubReaderView` 的 method channel 契約，支援開書後即時切換橫直排

**明確排除，留給後續 Epic：**
- **TXT 格式的橫直排**——TXT 閱讀器本身尚未存在（`detectBookFormat()` 目前只認 `epub`/`pdf`），FR-05 提到的 TXT 部分全數延後到 `epic-11-txt-engine` 一併實作
- **定樣式（fixed-layout）EPUB**——切換橫直排概念上對固定版面書籍意義不大且可能破版，偵測到 fixed-layout 時直接隱藏切換 UI，維持書本原始版面
- **PDF**——無 writing-mode 概念，不適用
- 版面其餘控制項（行距、段落間距、邊距、字型、換頁模式等）——屬 `epic-3-fonts-layout`
- 九宮格導航熱區在直排模式下的左右鏡像映射邏輯——屬 `epic-7-interaction`（`prototype/index.html` 已有雛型可參考）
- **橫直排切換選擇的持久化，以及「採用書籍排版／強制直排／強制橫排」三態覆寫 UI**——這是 PRD FR-10 明確定義的需求（「排版方向提供三種模式並以圖示呈現……後兩者為使用者手動覆寫，優先於自動偵測」），FR-10 整個歸在 `epic-3-fonts-layout`（與行距、邊距、對齊、換頁模式、螢幕方向等版面控制項綁在一起規劃），故持久化與三態覆寫 UI 一併留給 `epic-3` 實作。本 epic 的切換按鈕（Issue 2）僅止於**當次閱讀 session 內的即時切換**，關閉重開後一律回到 FR-06 自動偵測結果，不記憶使用者的手動選擇。Issue 1 建立的 `setWritingMode`/`onLayoutResolved` 契約已足夠支撐 `epic-3` 未來讀取持久化設定後直接呼叫套用，不需要為此再擴充原生契約。

## 架構異動：擴充 `EpubReaderView` 契約以支援即時偏好設定

epic-0 建立的契約是單次靜態開書：`openBook(path)` → `onPageRendered()`/`onError(message)`，開書後無法再傳遞任何設定給原生端。

本 epic 需要擴充為雙向、可在開書後隨時呼叫的契約：

- **Dart → 原生**：新增 `setWritingMode(mode: horizontal | vertical)` 指令，可在書本開啟後任何時間點呼叫。
- **原生端**：收到指令後組出 Readium 的 `EpubPreferences(verticalText = mode == vertical)`，呼叫 navigator 的 `submitPreferences()` 套用。
- **初次開書的預設值**：刻意**不**主動設定 `verticalText`（保持 `null`），交由 Readium 內建的 `EpubSettingsResolver.resolveVerticalText(null, language, readingProgression)` 依書本語言與閱讀方向自動判斷初始模式（見下方 FR-06 說明）。
- **原生 → Dart**：新增一次性回呼（例如 `onWritingModeResolved(mode)`），在開書解析完成後告知 Dart 端「自動判斷出的初始模式」，讓切換 UI 能正確顯示目前狀態，而不是預設顯示橫排。

此契約擴充屬架構層級改動——把契約從「單次靜態開書」擴充為「可雙向通訊的即時偏好設定」，需在 Architecting 階段（`spec.md`）補一份 ADR 記錄此決定與理由（比照 ADR 0002 擴充 content URI 契約的先例）。

## FR-06：自動偵測排版方向

**不自行解析** EPUB 的 OPF metadata 或內嵌 CSS。專案依賴的 `readium-navigator:3.3.0`（見 `app/android/app/build.gradle.kts`）已內建：

- `EpubPreferences.verticalText: Boolean?`——使用者偏好，可為 `null`（表示「未手動指定，交給系統判斷」）
- `EpubSettingsResolver.resolveVerticalText(verticalText, language, readingProgression): Boolean`——當 `verticalText` 為 `null` 時，依書本語言＋閱讀方向自動解析出應採用的橫直排

本 epic 的自動偵測完全委由 Readium 這套內建解析邏輯負責：初次開書不設定 `verticalText`，直接使用解析結果作為初始模式。若某本書缺乏語言中繼資料導致解析結果不理想，屬於 Readium 本身的已知限制，本 epic 不額外開發偵測補強邏輯，僅在 `spec.md` 中記錄為已知限制。

## FR-32：直排標點與避頭尾規則

**不自行注入客製 CSS**。`readium-navigator:3.3.0` 的 AAR 內建打包了官方維護的 `cjk-vertical` ReadiumCSS 樣式表（`Layout.Stylesheets.CjkVertical`），當 `EpubSettings.verticalText` 解析為 `true` 時會自動切換載入，涵蓋直排標點轉向/置中與基本換行規則。

Architecting 階段需以實際範例書驗證這套內建樣式表是否完全符合 CNS 11643 的避頭尾字元集合（Readium 的 CJK 樣式可能較偏日文排版慣例，繁體中文的避頭尾字元集合與日文不完全相同）。若發現落差：
1. 在 `spec.md` 中列出具體差異字元
2. 確認 Readium 是否有提供 user stylesheet 或等同的樣式覆寫擴充點；若有，設計最小化的覆寫方案；若沒有這樣的擴充點，需另立 ADR 決定注入方式（避免與「不自行注入 CSS」的預設路線互相矛盾）

## FR-05：圖片與標題不得跨頁切斷

沿用 Readium 既有的分頁（pagination）渲染機制。Architecting 階段需先以實際範例書測試 Readium 的預設分頁 CSS 對 `img`/標題元素是否已有等同 `break-inside: avoid` 的效果。若已足夠，本項不需額外開發；若不足，需在 `spec.md` 中找出 Readium 是否提供對應的覆寫點並記錄採用的方案。

## UI

**修正**：原先計畫沿用的 `prototype/index.html:1481-1482`（「⬇ 直排」／「➔ 橫排」按鈕）經查證後，其實是 FR-10 三態覆寫設定面板（📖 預設／⬇ 直排／➔ 橫排）的其中兩顆按鈕，屬於「範圍與排除項目」一節已排除給 `epic-3-fonts-layout` 的持久化覆寫 UI，並非本 epic 適用的簡易即時切換按鈕。Prototype 另有 `toggleWritingMode()` 這個 JS 函式，但沒有被任何可見元素呼叫（死程式碼），並非可沿用的既有 UI。因此本 epic 的閱讀畫面切換按鈕改為獨立設計：`ReaderScreen` AppBar 新增一顆單一 `IconButton`（沿用 `LibraryScreen` 既有的「圖示顯示切換後目標狀態＋tooltip 說明」慣例，例如 `library_view_mode_toggle` 的做法），不重新設計整體介面風格，只是不直接照搬那兩顆按鈕的既有視覺。按鈕真正呼叫 `setWritingMode` method channel 指令，並依 `onLayoutResolved` 回呼正確反映自動偵測後的初始狀態。

## 測試考量

- **Dart widget test**：驗證切換按鈕點擊會觸發 `setWritingMode` 呼叫；驗證 `onWritingModeResolved` 回呼能正確更新按鈕顯示狀態
- **`integration_test`（真實裝置）**：驗證橫直排切換後畫面確實重新渲染（沿用「等待 loading indicator 消失且無 error」的既有斷言模式；若切換情境需要新的可觀察斷點，於 Architecting 階段一併設計）
- 需要至少一本語言中繼資料完整、適合驗證直排/CJK 排版的範例 EPUB fixture；現有 `app/test/fixtures/sample.epub` 是否符合需求待 Architecting 階段確認，若否需另尋或製作新 fixture

## 已知限制與待驗證項目

1. Readium `resolveVerticalText` 對缺語言中繼資料書本的判斷品質未知（待實機驗證）
2. **（已於 Architecting 階段解析）** FR-05 圖片/標題不跨頁：解壓 `readium-navigator-3.3.0.aar` 檢查內建 `ReadiumCSS-before.css` 後確認，`img/svg/audio/video` 與 `h1-h6/figure/dt/tr` 皆已內建 `break-inside: avoid`，**不需要額外開發**
3. **（已於 Architecting 階段部分解析）** FR-32 避頭尾：ReadiumCSS 對 `:lang(zh)`（含 ja/ko）已內建 `line-break: strict`，會啟用瀏覽器引擎的嚴格換行邏輯；但（a）僅在書本 XHTML 正確標記 `lang="zh"` 時生效，(b) Chromium `line-break:strict` 的實際避頭尾字元表是否精確對齊 CNS 11643（而非泛用東亞規則）無法透過靜態檢查解決，仍待實機視覺驗證
4. Readium 是否提供 user stylesheet／樣式覆寫擴充點（若 FR-32 實機驗證後發現落差需要覆寫）尚待確認
