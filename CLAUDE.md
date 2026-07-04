# CLAUDE.md

本檔案為 Claude Code（claude.ai/code）在此儲存庫中工作時的指引文件。

## 儲存庫現況

`epic-0-skeleton`（Flutter + Android 技術骨架）已完成並合併回 `main`：`app/` 目錄下是可執行、可測試的 Flutter Android App，已驗證「書架 → 點開一本書 → 原生渲染出內容」的端到端流程（EPUB 用 Readium、PDF 用 `PdfRenderer`）。`docs/prd.md` 描述的其餘功能（真正的圖書庫管理、直排/橫排排版、字型與版面客製化、註記、雲端同步、全文檢索、閱讀統計等）皆尚未實作，屬於後續 Epic（現況與優先順序見 `docs/epics.md`）。

`prototype/index.html` 是一份獨立、依需求文件製作的 HTML/CSS/JS UI/UX 原型（手機外殼模擬器），後續功能性 Epic 設計畫面時應先參考它，細節見下方「UI/UX 原型參考」。

## 常用指令

所有指令皆在 `app/` 目錄下執行。

```bash
# 安裝/更新相依套件
flutter pub get

# 執行所有 widget/unit test（純 Dart，不需裝置/模擬器）
flutter test

# 執行單一測試檔
flutter test test/screens/reader_screen_test.dart

# 靜態分析——提交前必須乾淨（"No issues found!"）
flutter analyze

# 列出可用的真實裝置/模擬器 id
flutter devices

# integration_test：驗證原生 PlatformView 是否真的渲染出內容，
# 必須指定真實裝置/模擬器（見下方「兩層測試架構」，一般 flutter test 做不到這件事）
flutter test integration_test/reader_screen_test.dart -d <device-id>

# 建置 debug APK
flutter build apk --debug
```

## 高層架構

### `ReaderScreen`：唯一的閱讀器 seam

`app/lib/screens/reader_screen.dart` 是格式無關的統一入口：`ReaderScreen(filePath: String)` 依 `detectBookFormat()`（`app/lib/reader/book_format.dart`，依副檔名判斷 `epub`/`pdf`/`unknown`）分派到對應的原生渲染 widget：

- `EpubReaderView`（`app/lib/reader/epub_reader_view.dart`）——包裝 Readium `kotlin-toolkit`
- `PdfReaderView`（`app/lib/reader/pdf_reader_view.dart`）——包裝 `android.graphics.pdf.PdfRenderer`

兩者是刻意對稱的 `AndroidView` 包裝：Dart 端建構參數固定為 `filePath`/`onPageRendered`/`onError`；原生端（`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/`）皆實作同一組 method channel 契約 `openBook(path)` → `onPageRendered()`/`onError(message)`，並用對稱的檔名（`EpubReaderView.kt`+`EpubReaderViewFactory.kt`／`PdfReaderView.kt`+`PdfReaderViewFactory.kt`），在 `MainActivity.configureFlutterEngine()` 中註冊各自的 `PlatformView` 類型字串。未來新增格式（例如 TXT）應延續同一組三段式契約。

`ReaderScreen` 對外的公開建構參數只有 `filePath`——載入中／錯誤狀態是內部實作細節，透過固定的 `Key('reader_loading_indicator')`／`Key('reader_error_text')` 暴露給測試觀察，刻意不新增公開 callback 參數。

### `MainActivity` 為何是 `FlutterFragmentActivity`

`EpubReaderView` 需要把 Readium 的 `EpubNavigatorFragment`（建構子為 `internal`，只能透過 Readium 自己的 `FragmentFactory` 建立）掛載到 Activity 層級的 `supportFragmentManager`，因此 `MainActivity` 從 Flutter 預設的 `FlutterActivity` 改為 `FlutterFragmentActivity`。`PdfReaderView` 不涉及 Fragment（純 `ImageView` 點陣圖渲染），不受此影響。

### 兩層測試架構

- `app/test/`——純 Dart／widget test，`flutter test` 即可執行，不需裝置。適用於格式偵測邏輯，以及不涉及原生 `PlatformView` 渲染的畫面行為。
- `app/integration_test/`——**必須**在真實 Android 裝置/模擬器上執行（`-d <device-id>`）。一般 widget test 無法觀察 `PlatformView` 內部的真實渲染結果，因此「原生渲染是否真的成功」一律由這裡驗證：斷言方式是等待 `Key('reader_loading_indicator')` 消失且無 `Key('reader_error_text')`，而非直接掛 callback（`ReaderScreen` 對外沒有暴露 callback，見上方）。
- 已提交版本控制的範例測試檔：`app/test/fixtures/sample.epub`／`sample.pdf`（在 `pubspec.yaml` 宣告為 asset），同時供上述測試與 `LibraryScreen` 的範例書架項目共用。

### `LibraryScreen` 與範例書籍

`app/lib/screens/library_screen.dart` 目前顯示固定的範例書籍清單（定義於 `app/lib/screens/sample_books.dart`：一本 EPUB、一本 PDF）——真正的圖書庫管理（匯入、詮釋資料、封面產生）屬於尚未開始的 `epic-1-library`。點擊範例項目時，`stageSampleBookFile()` 會把 Flutter asset 複製為裝置暫存目錄中的真實檔案，再導航至 `ReaderScreen`，因為原生渲染引擎需要真實的裝置檔案系統路徑、無法直接讀取 Flutter asset。

## 這是什麼產品

elinkBook（全能跨平台電子書閱讀器）是一款跨平台電子書閱讀器，核心差異化在於正確、高品質支援**直排（Vertical Writing）繁體中文排版**——包含正確的標點符號位置（破折號、引號）與避頭尾（換行規則）——並提供深度排版客製化與無縫跨裝置同步。

完整需求請見 `docs/prd.md`。實作前需要知道的重點：

### 支援格式與渲染方式
- **ePub3**（流式與定樣式）、**PDF**、**TXT** 為三大核心格式（P0）。
- ePub：自動偵測排版方向（見 FR-06）；偵測方法本身尚未決定。渲染架構已定案——見下方「技術棧（已決策）」（Readium）。
- PDF：目標為 100MB 以上檔案開啟速度小於 2 秒；支援影像濾鏡（對比度/亮度/加粗）、智慧/手動裁切，預設採用 page-fit。渲染架構已定案——見下方「技術棧（已決策）」（平台原生 API）。
- TXT：自動偵測編碼與章節標題，合成具估算頁碼的階層式目錄（固定字元數量的分頁換算啟發式）。
- 檔案匯入：本機檔案選擇器，並支援 Google Drive 與 OneDrive 雲端存取。Google Drive 登入/驗證/下載須在無 Google Play Services 的裝置上（例如部分 E-Ink 閱讀器）持續正常運作。

### 版面與排版
- ePub3/TXT 支援橫排與直排(vertical-RL) 一鍵切換。
- 內建預設字型皆完全離線渲染（本地 `@font-face`）：思源黑體與思源宋體（開源 SIL OFL 基礎字型），加上三款商用授權字型——原俠正楷、台灣圓體、源流明體。刪除目前使用中的自訂字型時須自動退回預設字型。
- 版面控制項：行距、段落間距、獨立的上/下/左/右邊距滑桿、換頁模式（捲動 vs. 無）、文字對齊、螢幕方向鎖定（0/90/180/270°）、「停用書本 CSS」開關。每個數值型控制項（字體大小、字重、行距/段落間距、邊距）除滑桿外都需要 +/- 微調按鈕。當螢幕方向未鎖定時，裝置旋轉須為新的可視範圍重新計算分頁。
- 直排(vertical-RL) 模式不得讓圖片或標題被切斷至跨頁。
- 標點符號在直排中文排版中必須正確轉向/置中，換行須遵守避頭尾規則（禁止特定字元出現於行首/行尾），符合 CNS 11643 或同等標準（FR-32）。
- 主題切換：深色、羊皮紙色、預設淺色主題，並與獨立的 E-Ink 高對比模式並存。

### 導航、註記、書籤
- 跨三種格式的通用目錄元件，顯示標題+頁碼，須於 200ms 內跳轉至目標位置。
- 書籤儲存一個定位點（EPUB：CFI；PDF：頁碼；TXT：字元偏移量）+ 章節名稱；支援重新命名、單筆刪除、「刪除該書所有書籤」。書籤管理屬於 MVP 範圍，並非後續階段項目。
- 劃線與備註是各自獨立的物件類型（備註不會覆蓋劃線）；兩者在直排/橫排切換時都須保持視覺一致。支援單筆編輯/刪除，以及劃線與備註各自的一鍵全刪（批次刪除前需經確認對話框）。
- 劃線支援多種顏色，加上獨立的「螢光筆」子類型。劃線/備註的定位精度須高於書籤：EPUB 用 CFI，PDF 用頁碼+頁內座標（不只是頁碼），TXT 用字元偏移量。
- 統一側邊欄列出所有劃線與備註（不含書籤，書籤有自己獨立的清單/畫面），點擊可跳轉至該位置。
- Markdown 導出涵蓋劃線、個人備註與書籤清單。

### 搜尋
- 全書庫全文檢索（書名、作者、書內內容），即使在約 1,000 本書規模下也要於 500ms 內出結果。建議做法：SQLite FTS5（或同等方案）索引。搜尋結果須支援跳轉至章節，並須將書名/作者匹配與書內內容匹配分開呈現。

### 同步
- 同步後端決策：**PocketBase**（曾考慮 Firebase/Supabase 作為替代方案）。
- 閱讀位置（EPUB：CFI；PDF：頁碼；TXT：字元偏移量）在 App 關閉/切換書籍時自動同步，並正確處理直排/橫排模式間的轉換；目標延遲 <2 秒，衝突解決成功率 99.9%。若開啟書籍時雲端同步的位置與本機位置不一致，須先詢問使用者確認才跳轉——絕不可靜默覆蓋。
- 閱讀時長統計每日儲存於本機，彙整成約 365 天規模的熱點圖/貢獻圖（參考模式：Readest）；點擊方格顯示當日詳情。計時須基於偵測到的實際閱讀活動（翻頁/捲動/長按），排除閒置或背景狀態的時間。

### 圖書庫管理
- 書架視圖：每列 6 本封面；另有含元數據+進度百分比的列表視圖。App 須記住使用者上次選擇的檢視模式。
- 封面產生策略：ePub → 內嵌封面圖；PDF → 首頁渲染；TXT → 依書名文字動態產生封面。
- 排序方式：最後閱讀（預設）、建立時間、作者或書名。

### 明確排除範圍（Out of scope）
- 不支援解除 DRM（例如 Adobe DRM）。
- 不提供電子書商店/購買或租閱流程。
- 不支援 PDF 內容編輯（文字/圖片修改）。
- 不含完整社交平台（動態牆、好友）——僅支援單向分享劃線/統計圖片。

### 互動模式
- 極簡、低干擾 UI；核心導航、目錄、基礎調整都須可透過可自訂的熱區單手操作。
- 導航區域：可自訂的 3×3 點擊九宮格，提供多種對應模式（傳統/單手/類 Kindle）；直排(RTL) 模式下，熱區映射須左右鏡像以符合由右至左的翻頁邏輯。
- 需支援音量鍵翻頁；離開閱讀畫面後，音量鍵須恢復正常系統音量控制。
- E-Ink 友善的高對比模式，並減少過渡動畫（避免殘影）。
- 手機版與桌面版應維持相近的按鈕/選單佈局邏輯，降低跨裝置重新學習的成本。

## 目前在此儲存庫中的工作方式

請將此處的任務視為：(a) 修訂 `docs/prd.md` 本身，或 (b) 透過下方的 SDD 工作流程進行後續 Epic 的開發（下一個里程碑：`epic-1-library`，現況見 `docs/epics.md`）。

### UI/UX 原型參考

`prototype/index.html` 是依需求文件製作的獨立 HTML 原型（手機外殼模擬器 + 控制面板，涵蓋書架視圖、直排/橫排排版切換、多主題、版面客製化、九宮格導航熱區等）。`epic-0-skeleton` 之後的所有功能性 Epic（`epic-1` 起）在設計畫面 UI/UX 時，須先參考此原型既有的視覺與互動設計，作為 Flutter 實作的依據起點，而非重新發明。

### 技術棧（已決策）

- **App 外殼**：Flutter，跨平台共用。
- **手機優先，Android 先於 iOS。** 初期幾波不含桌面版目標（見 `docs/epics.md` 的 epic-13）。
- **Android 最低支援版本：Android 11 (API 30)**（見 `docs/prd.md` NFR-6）——不得將 Android 專案的 `minSdk`/相容性設定限制在比 API 30 更新的門檻。實際 `minSdk` 目前是 `24`（比政策門檻寬鬆；由 Readium `kotlin-toolkit`〔要求 23〕與 `integration_test` 外掛〔要求 24〕兩者疊加後的真實下限決定，見 `app/android/app/build.gradle.kts`），不是刻意收緊。
- **EPUB**：Readium 官方原生工具包（Android 用 `readium-kotlin-toolkit`、iOS 用 `readium-swift-toolkit`）——不是自訂解析器，也不是像 epub.js 這種 WebView 函式庫。透過 Flutter 的 `PlatformView` 渲染，使用 Readium 的 Locator（等同 CFI）與 Decorator（劃線/備註疊加）API。
- **PDF**：各平台內建 API（Android 用 `PdfRenderer`、iOS 用 `PDFKit`），不使用 PDFium，透過 `PlatformView` 渲染。
- **TXT**：自訂的輕量直排 CJK 排版引擎（獨立 epic —— `epic-11-txt-engine`），不採用 Readium/WebView 方案，因為純文字沒有 HTML/CSS 那層需要重新實作。
- 理由：先前以 WebView 為主的嘗試（Capacitor + epub.js）在直排文字跳轉導航與劃線/備註一致性上反覆出現缺陷（見專案歷史）。完全自寫 EPUB 的 XHTML/CSS reflow 引擎（以徹底避開 WebView）被判定對此團隊規模不可行——那等同於重新實作一個瀏覽器排版引擎。Readium 是折衷路線：內部仍是 WebView，但是成熟、專門打造的 SDK，而非自己拼裝的膠水程式碼。

## Spec-Driven Development (SDD) 工作流程

本儲存庫採用結合 BMad Method 角色分工、Matt Pocock 規格先行嚴謹度、以及 Superpowers 審查機制的規格驅動開發工作流程。可執行實作工作的有兩個角色：**Claude Code** 與 **Antigravity CLI**。切換到 Antigravity CLI 一律由人工手動指定——絕不可自行假設或觸發。若需要派出「實作者」子代理但人類尚未明確指定使用 Antigravity CLI，一律使用 Claude Code 的 subagent（也就是目前正在使用的同一個 LLM/工具），不可模擬呼叫 Antigravity。

**審查一律先產出報告，嚴禁直接修改。** 不論是文件審查（`design.md`/`spec.md`/`plans/plan-issue-N.md`）或程式審查，審查者（Claude Code）必須先產出審查報告（存於該 Epic 的 `reviews/`），列出發現的問題，交由人類或原作者決定如何處理；審查者本身不得在審查當下直接修改被審查的文件或程式碼。

### 目錄結構

```
docs/
├── adr/                    # 全域：架構決定紀錄
├── epics/                  # 進行中的 Epic 沙盒（design.md、spec.md、issues.md、plans/、reviews/）
├── archive/                # 已完成的 Epic，搬移至 <YYYY-MM-DD>-<簡稱>/
├── prd.md                  # 全域：產品需求
├── CONTEXT.md              # 全域：通用語言 + 程式碼限制（尚未建立）
└── epics.md                # 全域：Epic 狀態看板 —— 見下方說明
```

### `docs/epics.md` —— 全域狀態看板

每個 Epic 佔一列：代號/名稱、狀態、目前存放路徑、關聯的 PRD 章節、備註。

- ⚪ **未開始 (Backlog)**——已規劃但尚未啟動，尚無目錄
- 🟡 **開發中 (Active)**——設計/規格/程式撰寫進行中，存放於 `docs/epics/<epic-name>/`
- 🟢 **已歸檔 (Archived)**——已合併且穩定，已搬移至 `docs/archive/<YYYY-MM-DD>-<簡稱>/`

在啟動一個 Epic 的 Discovery 階段*之前*，須先在此登錄該 Epic（狀態設為 `Active`，填入路徑）。歸檔時將狀態/路徑更新為 `Archived`。這份檔案是唯一能查到「我要找的 Epic 在哪裡、目前狀態如何」的地方——目前的 Epic 清單與優先順序請見 `docs/epics.md` 本身。

### 生命週期

1. **任務分類**（人類）：新功能/重構 → 建立新 Epic；Bug 修復 → 找到受影響的 Epic，於其 `reviews/` 目錄下處理。
2. **Discovery**（Claude Code，扮演 PM/Analyst）—— `/brainstorming` + `/grill-with-docs` → `docs/epics/<epic-name>/design.md`。Bug 修復則改用 `/diagnose` → `docs/epics/<epic-name>/reviews/bugfix-repro.md`。
3. **Architecting**（Claude Code，扮演 Architect）—— 若架構有異動則撰寫 ADR，並在 `docs/epics/<epic-name>/spec.md` 中定義核心介面/型別（自此成為該 Epic 的唯一事實來源）。
4. **Scrum Master 階段**（Claude Code）—— 將 Epic 拆解為細粒度的垂直切片工單，寫入 `docs/epics/<epic-name>/issues.md`，每個工單皆須附上所需的單元測試要求。
5. **規劃與審查**（實作者為作者、Claude Code 為審查者）—— 實作者認領工單，撰寫 `docs/epics/<epic-name>/plans/plan-issue-<N>.md`，在開始寫程式碼前發起審查（`requesting-code-review`/`receiving-code-review`）；審查者先產出報告，不得直接修改該計劃。
6. **TDD 實作與 QA**（實作者為作者、Claude Code 為審查者）—— 紅-綠-重構循環，接著進行程式碼審查；審查者先產出報告，不得直接修改程式碼；結果歸檔至 `docs/epics/<epic-name>/reviews/review-issue-<N>.md`；交由人類進行合併。
7. **歸檔**（人類指定）—— 將整個 Epic 目錄搬移至 `docs/archive/<YYYY-MM-DD>-<簡稱>/`，並將其在 `docs/epics.md` 的該列狀態更新為 `Archived`、填入新路徑。

## Agent skills

### Issue tracker（工單追蹤）

本機 markdown，存放於 `docs/epics/<epic-name>/`（SDD Epic 沙盒），非 Gitea。Gitea（`git.jigong.org/huthief/elinkBook`，透過以 `jigong` 登入的 `tea` CLI）僅作為程式碼的 git remote 使用。詳見 `docs/agents/issue-tracker.md`。

### Triage labels（分流標籤）

預設標籤詞彙（`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`）——尚未在此儲存庫上建立。詳見 `docs/agents/triage-labels.md`。

### Domain docs（領域文件）

單一情境（Single-context）——根目錄一份 `CONTEXT.md` + `docs/adr/`（兩者皆尚未建立）。詳見 `docs/agents/domain.md`。
