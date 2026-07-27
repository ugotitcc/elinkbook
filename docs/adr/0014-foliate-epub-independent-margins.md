# ADR 0014：流式 EPUB（foliate-js）邊距改為上/下/左/右 4 個獨立欄位，縮小 ADR 0005 適用範圍

## 狀態

已採納

## 背景

ADR 0005 決定 EPUB 邊距採單一數值、四邊同步變動，理由是反編譯 `readium-navigator:3.3.0` 的 `EpubPreferences` 確認其原生只有 `pageMargins: Double?` 這一個純量欄位，若要四邊獨立必須自建 CSS 覆寫層，成本與風險當時判斷過高，故 Epic 3（`EpubReaderView`／Readium kotlin-toolkit，供 `_isFixedLayout == true` 的固定版面 EPUB 使用）不採用。

`epic-18-reader-device-qa` 第三輪真機使用回報（2026-07-28）指出流式 EPUB（`FoliateEpubReaderView`）左右留白過多，且目前單一「邊距」滑桿（`BookReaderPrefs.pageMargins`）同時驅動兩種不相干的機制：

1. `main.js` 的 `buildOverrideCss()`：`body { padding: 0 ${1.5 * prefs.pageMargins}em }`（左右留白，`em` 單位、隨字級等比例放大，所有排版方向皆生效）。
2. `epic-18` Issue 4 引入的 `main.js` 機制：直排模式下 `view.renderer.setAttribute('margin-top'/'margin-bottom', ...)`（px 單位，僅直排生效；橫排永遠固定 `paginator.js` 內建 48px，完全不受這個滑桿影響）。

重新檢視 ADR 0005 的調查範圍：**該 ADR 的技術結論只針對 Readium 原生 `EpubPreferences`（供 FXL 使用的 `EpubReaderView`）**，成書於 `epic-17-epub-render-migration`（foliate-js 遷移）**之前**。確認目前 `FxlSettingsSheet`（`app/lib/screens/fxl_settings_sheet.dart`）完全沒有邊距滑桿 UI——`pageMargins` 這個欄位在目前產品中，實際上只由流式 EPUB 專用的 `ReaderSettingsSheet` 寫入、FXL 從未透過任何 UI 設定它。而流式 EPUB 走的正是 Epic 17 為了 `main.js` 而自建的 CSS 覆寫層（`buildOverrideCss()`）——這正是 ADR 0005 當初認定「自建 CSS 覆寫層成本過高」所以不採用的那個方案；但這一層對流式 EPUB 而言**早已存在**（Epic 17 為了字級/行高/段落間距等其餘覆寫需求而蓋好），額外新增 `padding-top`/`padding-right`/`padding-bottom`/`padding-left` 四個獨立 CSS 屬性，只是在既有覆寫層上多加幾行 `rules.push(...)`，並非重新建置一整層機制。ADR 0005 認定的技術障礙，對流式 EPUB 這條路徑已經不成立。

## 決策

**僅限流式 EPUB（`FoliateEpubReaderView`／`main.js`）**，`BookReaderPrefs` 新增 4 個獨立欄位：`marginTop`、`marginBottom`、`marginLeft`、`marginRight`（型別皆為 `double?`，語意與既有 `pageMargins` 一致，皆為使用者可調的邊距倍率/數值，實作階段依 `plans/plan-issue-14.md` 定案實際單位換算公式）。`ReaderSettingsSheet` 既有的單一「邊距」滑桿，改為 4 個獨立滑桿（上/下/左/右）。`main.js` 的 `buildOverrideCss()` 與 Issue 4 的 margin-top/margin-bottom 機制皆改吃這 4 個新欄位，且**不再限制上下邊距僅直排生效**——橫排模式下 `margin-top`/`margin-bottom` 也改為依 `marginTop`/`marginBottom` 動態設定（取代目前橫排永遠固定 48px 的既有行為），四個方向在兩種排版方向下皆一致生效。

**既有 `pageMargins` 欄位維持不變、不刪除、不做資料遷移**：繼續透過 `EpubReaderView.pageMargins` 屬性傳遞給 Readium 原生 `EpubPreferences.pageMargins`，供 FXL 路徑使用。**ADR 0005 對 FXL/Readium 路徑依然完全有效**——本決策不是推翻 ADR 0005，而是確認其適用範圍原本就僅限 Readium 原生渲染路徑，新增一條範圍明確排除在外的路徑（流式 EPUB／foliate-js 自建 CSS 覆寫層）。

## 曾考慮的替代方案

- **同步幫 FXL／Readium 路徑也做四邊獨立**：技術上仍受 ADR 0005 當初的限制（Readium 原生 `EpubPreferences` 沒有四邊獨立欄位，需要自建 CSS 覆寫層或原生容器層級 padding），且目前 FXL 完全沒有邊距 UI（`FxlSettingsSheet` 無此控制項），使用者也未對 FXL 提出留白過多的回報。本次不採用，維持 ADR 0005 對此路徑的既有結論。
- **廢棄 `pageMargins` 欄位、四個新欄位同時取代兩條路徑**：會強迫 FXL 路徑跟著改變既有行為（即使目前它甚至沒有 UI 可調整這個欄位），且需要處理「Readium 原生只吃單一值」的既有限制（例如四個新欄位在 FXL 情境下如何合併回一個 `pageMargins` 值餵給 Readium），增加不必要的複雜度。本次不採用。

## 後果

- `BookReaderPrefs` 新增 4 個持久化欄位，需要 SQLite schema migration（累加式 `if (oldVersion < N)`，比照既有慣例）。
- `pageMargins` 欄位成為「事實上僅供 FXL 路徑使用」的欄位（流式 EPUB 改用新的 4 個欄位），但欄位本身與其既有語意不變，不需要任何遷移或刪除動作。
- 未來若要幫 FXL／Readium 路徑補齊四邊獨立控制，仍需先解決 ADR 0005 記載的原生 `EpubPreferences` 限制（自建 CSS 覆寫層或原生容器 padding 兩條路線之一），本 ADR 不影響、不預先決定該路線。
