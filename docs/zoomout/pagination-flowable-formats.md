# 流式格式（EPUB 流式／TXT／MD）頁碼與進度計算——模組地圖與深度報告

> 產出方式：`/zoom-out` 技能，透過子代理（subagent）閱讀原始碼、foliate-js 演算法與 git 歷史彙整而成。
> 涵蓋範圍：Dart 端頁碼/進度顯示、foliate-js JS 端分頁引擎、CFI 定位、`totalCharacterCount` 孤兒程式碼案例。
> 產出日期：2026-08-20。

---

## 第一部分：模組地圖（Overview）

### 0. 全局架構前提

- 目前**唯一**的流式渲染路徑是 `FoliateReaderView`（`app/lib/reader/foliate_reader_view.dart`）。程式碼裡仍有大量提到「`EpubReaderView`（Readium）」「舊版估算」的歷史殘留，這些是 epic-17（EPUB 渲染引擎遷移到 foliate-js）之後留下的死路徑，非誤導性文字。
- TXT/MD 匯入後合成的 EPUB（`app/lib/library/txt_epub_synthesizer.dart`、`md_epub_synthesizer.dart`）會產生 `OEBPS/nav.xhtml`，因此在 foliate-js 眼中和一般 EPUB 完全相同 → **三種格式的頁碼/進度/TOC/CFI 邏輯沒有格式專屬分支，全部共用同一套 Dart 與 JS 程式碼**。

### 1. 資料流向總覽

```
foliate-js (SectionProgress, 1500 bytes/location)
   → main.js: onLocatorChanged(cfiJson, fraction, pageIndex, totalPages)
   → flutter_inappwebview callHandler
   → foliate_reader_view.dart: EpubPositionInfo
   → reader_screen.dart: _epubPositionInfo (state)
   → ReaderFooter（頁碼顯示）／TocNavigator（章節高亮）／
     ReadingPositionRepository（離開時持久化 progress）／
     Bookmark/Highlight/Note（新增當下讀取 epubLocatorJson+progression）
```

### 2. Dart 端現行路徑

- **`EpubPositionInfo`**（`app/lib/reader/epub_position_info.dart`）：`locatorJson`（CFI JSON）、`progression`（0.0-1.0）、`pageIndex`/`totalPages`（來自 foliate-js `SectionProgress.getProgress()` 的 `location.current`/`location.total`）。
- **`foliate_reader_view.dart:648-666`** `onLocatorChanged` JS handler：把 JS 端 4 個參數組成 `EpubPositionInfo` 往上回呼。
- **頁尾顯示**：`reader_screen.dart` 的 `_buildFoliateEpubFooter()`/`_buildFoliateProgressText()` 直接用 `EpubPositionInfo.pageIndex+1`/`totalPages`，不做額外估算；`app/lib/screens/reader_footer.dart` 為格式無關的頁尾 UI（頁碼文字、跳頁輸入框、可拖曳進度條，1-indexed）。
- **頭部章節名稱**：`_buildFoliateHeaderText()` 用 `TocNavigator.findCurrentPath(_tocEntries, _epubPositionInfo?.progression)`。
- **書庫進度百分比**：`library_screen.dart:1356` `_progressText()`，資料來自 `Book.progress`。

### 3. Dart 端死路徑（Readium 時代殘留）

- **`EpubPageEstimator`**（`app/lib/reader/epub_page_estimator.dart`）：純函式估算器，`estimateCharsPerScreen()`/`estimateTotalPages()`/`estimateCurrentPage()`/`estimateProgression()`，靠 `totalCharacterCount` 換算頁碼。
- **`reader_screen.dart` `_buildEpubFooter()`**：呼叫 `EpubPageEstimator`，程式碼註解明講「post-epic-17 對流式書籍已是死路徑」；因 `_totalCharacterCount` 恆為 `null`，此頁尾實質上永遠不出現。
- **`toc_bottom_sheet.dart:210-243`**：EPUB 目錄項目頁碼標籤仍走 `EpubPageEstimator` + `totalCharacterCount`，因欄位恆為 `null`，**目前 TOC 清單裡 EPUB 章節的頁碼欄位恆顯示佔位符「…」**——與 CLAUDE.md「目錄須顯示標題+頁碼」的要求有落差（第三部分深入追查此案例）。

### 4. `BookTocItem` 目錄與 CFI

- **`BookTocItem`**（`app/lib/reader/book_toc_item.dart`）：格式無關抽象介面。
- **`TocEntry`**（`app/lib/reader/toc_entry.dart`）implements `BookTocItem`：EPUB/TXT/MD 唯一實作，`stableId == locatorJson`（CFI JSON 字串）。
- **`TocNavigator`**（`app/lib/reader/toc_navigator.dart`）：`findCurrentPath(entries, progression)` DFS 找出目前章節祖先路徑。
- **`foliate_bridge_codec.dart`**：`extractCfi()`（拆解 CFI JSON）、`parseTableOfContents()`、`buildDecorationEntries()`。
- 跳轉呼叫鏈：`_openToc()` → `TocBottomSheet` → `_jumpTo(locatorJson)` → `FoliateReaderView.jumpToLocator()` → JS `window.jumpToLocator(cfi)`。全程走 CFI，不涉及頁碼數字。
- **CFI 是唯一真實定位來源**，頁碼/進度都是從它（或伴隨的 `fraction`）換算出的顯示用近似值。書籤/劃線/備註/閱讀位置記憶全部走同一組「`epubLocatorJson` + `progression`」雙欄位模式。

### 5. foliate-js JS 端（`app/android/app/src/main/assets/foliate/`）

| 檔案 | 職責 |
|---|---|
| `progress.js` | `TOCProgress`（TOC↔spine 映射）、`PageProgress`（CFI→字元級 fraction）、`SectionProgress`（真正的「頁碼」引擎） |
| `view.js` | `View extends HTMLElement`，`openBook()` 建構 `new SectionProgress(book.sections, 1500, 1600)`；`resolveNavigation`/`getCFI` |
| `paginator.js` | 實際 DOM 分欄/捲動渲染引擎，產生真正的視覺頁 |
| `epubcfi.js` | CFI 產生/解析/比較純函式庫 |
| `main.js` | JS↔Dart 橋接層 |

JS→Dart 橋接（`callHandler`）：`onPageRendered`、`onLocatorChanged(cfiJson, fraction, pageIndex, totalPages)`、`onTableOfContentsReady`、`onSelectionChanged`/`onSelectionCleared`、`onError`。Dart→JS：`window.jumpToFraction`/`jumpToLocator`/`getTableOfContents`/`setDecorations`/`applyPreferences`/`clearSelection`。

### 6. 測試檔案

`epub_page_estimator_test.dart`、`toc_entry_test.dart`、`toc_navigator_test.dart`、`reader_prefs_manager_test.dart`（含 `EpubCharacterCountRepository`）、`toc_bottom_sheet_test.dart`（EPUB 分支）、`toc_bottom_sheet_pdf_test.dart`（PDF 對照組）、`reader_screen_test.dart`、`library/models/book_test.dart`、`library/sqlite_library_repository_test.dart`、`support/fake_epub_character_count_repository.dart`、`support/fake_reader_prefs_manager.dart`。

---

## 第二部分：深度報告 A——foliate-js 分頁與 CFI 演算法

### A.0 心智模型：三層獨立座標系統

這套系統同時維護三種互不相同、各自獨立計算的「進度」座標，理解它們互不相等是看懂整個設計的關鍵：

| 座標系統 | 產生者 | 依據 | 單位 |
|---|---|---|---|
| **視覺頁碼**（真正渲染出來的頁） | `paginator.js` `#afterScroll()` | 實際 DOM 分欄結果（`columnCount`、`contentPages`） | CSS 欄數 |
| **「Location」估算頁碼**（`location.current/next/total`） | `progress.js` `SectionProgress.getProgress()` | spine 檔案的**位元組數**（非視覺渲染） | 每 1500 bytes 一個 "loc" |
| **CFI 定位**（永久性書籤/劃線座標） | `epubcfi.js` | DOM 樹結構路徑（step indirection） | 與渲染設定無關 |

`view.js` 的 `#onRelocate()` 把三者匯合成一個 `lastLocation` 物件，`main.js` 再拆開送給 Dart。

### A.1 `SectionProgress`（`progress.js`）——「Location 頁碼」引擎

**`sizePerLoc=1500` 是什麼**：**不是**把每個 section 切成一頁一頁的虛擬頁面，而是該 spine item（XHTML 檔案）在 epub 壓縮包內的**未壓縮位元組數**（`view.js:43` `getSize = name => map.get(name)?.uncompressedSize`）。這概念上等同 Adobe Digital Editions 傳統的 "location" 做法：把全書 markup 位元組總數除以 1500，得到一個粗略、與實際排版無關的進度刻度——**是 XHTML 原始檔位元組數（含 HTML 標籤），不是可見文字字元數**。`sizePerTimeUnit=1600` 同理估算剩餘閱讀時間。

**`getProgress(index, fractionInSection, pageFraction)` 完整公式**：
```
sizeInSection = sizes[index]
sizeBefore    = 前面所有 section 的 size 總和
size          = sizeBefore + fractionInSection * sizeInSection
nextSize      = size + pageFraction * sizeInSection

fraction               = nextSize / sizeTotal      // 用 nextSize（頁尾）而非 size（頁首），避免翻到最後一頁時卡在 <1
section.{current,total}= index, sizes.length
location.current        = Math.floor(size / sizePerLoc)
location.next            = Math.floor(nextSize / sizePerLoc)
location.total           = Math.ceil(sizeTotal / sizePerLoc)
time.section             = (1-fractionInSection)*sizeInSection / sizePerTimeUnit
time.total                = (sizeTotal - size) / sizePerTimeUnit
```

**`getSection(fraction)` 反函式**：給定全書進度百分比，用累積比例陣列 `sectionFractions` 找出所在 section index，再算出 `fractionInSection`；跳過 `size=0`（非線性/隱藏章節）的 section。用途：進度條拖曳時 `resolveNavigation({fraction})` 反推跳轉目標。

**`TOCProgress` 與 `PageProgress` 分工**：
- `TOCProgress`：給定目前 CFI/range，回答「現在讀到 TOC 哪個條目」，用於章節標題顯示；`view.js` 用同一個 class 建構出 `#tocProgress`（真正目錄）和 `#pageProgress`（EPUB `page-list`，出版社標定的實體書頁碼）。
- `PageProgress`：給定 CFI，算出它在該 section 內以**可見文字字元數**（非位元組）為基準的精確 fraction，用 `TreeWalker(SHOW_TEXT)` 建立文字節點累積偏移快取＋二分搜尋定位——這是全系統**唯一真正做字元計數**的地方，且只在單一 section 範圍內，不是全書字元數。

### A.2 「Location 頁碼」與真實視覺頁面不一致——專案自己已記錄此限制

視覺翻頁的真實頁數來自 `paginator.js` 的 DOM 分欄結果，完全取決於當下字型大小/行距/邊距/欄寬/直橫排設定。而 `location.current/total` 是拿視覺 `fraction` 去乘 spine 檔案位元組數、除以固定常數 1500 算出——**與實際渲染欄數毫無關聯**。`main.js` 的專案自建註解明講：

> 「location.current／location.total 為 foliate-js `SectionProgress.getProgress()` 既有輸出，**近似頁碼概念，非精確渲染頁數**。」

FXL（固定版面）書籍完全繞開這套估算：若 `location.current/total` 不存在，改用 renderer 的 `page/pages`。

### A.3 CFI 演算法（`epubcfi.js`）

CFI 用一串 `/index` 的「step」路徑從文件根走到目標節點，可插入 `:offset`（文字節點內字元偏移）、`[id;s=side]`（id 斷言+side-bias）、`!`（**step indirection**，切換到另一份文件，例如從 package document 跳進某個 spine item）、`,start,end`（range CFI）。

**`compare(cfiA, cfiB)`**：判斷兩個 CFI 的文件順序，回傳 `-1/0/1`，供書籤/劃線排序、選取範圍比較使用。逐段比較 indirection 路徑的 step index，同段最後一個 step 額外比較 `:offset`。**目前 grep 全 repo 沒有找到任何地方實際呼叫 `CFI.compare`**——這是保留供未來排序功能使用的公開 API，尚未被 elinkBook 橋接層用上。

**CFI 如何處理跨 spine item 定位**：CFI 第一段（`!` 之前）指向 **package document（OPF 檔）中某個 `<itemref>` 元素**的路徑，`epub.js` 的 `resolveCFI()` 把這段路徑解回 OPF 文件節點，讀出 `idref`，再查出對應 spine index——**CFI 不直接編碼「第 N 個 section」這個數字，而是編碼「OPF 裡第幾個子節點」，需重新解析 OPF 才能換算**。若沒有真正的 package document（如非 EPUB 格式），走 `fake` 機制：直接把 spine index 編碼成假路徑 `/6/${(index+1)*2}`，不需 OPF 解析。

### A.4 `view.js` 的 `getCFI`/`resolveNavigation`——正向與反向轉換的對稱設計

- **`getCFI(index, range)`**：「渲染結果 → 永久座標」正向轉換（存檔用）。優先用開書時 `CFI.fromElements()` 預先算好、快取在每個 section 上的真正 package-doc CFI；若有 `range`（選字/劃線），用 `CFI.fromRange(range)` 轉成相對 CFI 再 `CFI.joinIndir` 接起來。每次 `#onRelocate()`（渲染器捲動/翻頁回報位置）都會呼叫，寫入 `lastLocation.cfi` 並 `history.replaceState`。
- **`resolveNavigation(target)`**：「永久座標 → 渲染可用的 index+anchor」反向轉換（跳轉用），依 `target` 型別分四種來源：數字（spine index）、`{fraction}`（呼叫 `SectionProgress.getSection()`）、CFI 字串（`resolveCFI`）、一般 href（`book.resolveHref`）。

---

## 第三部分：深度報告 B——`totalCharacterCount` 孤兒程式碼案例（技術債溯源）

### B.1 結論先講：已知並記錄，但「記錄」與「行動」之間反覆脫節

這不是單純的「規劃疏漏、沒人注意到」，而是一個**多次被看見、每次都被有意識地延後、最終累積成孤兒程式碼**的案例。

### B.2 檔案 commit 歷史

`epub_page_estimator.dart`／`epub_character_count_repository.dart`：

| Commit | 日期 | 摘要 |
|---|---|---|
| `23495b3` | epic-5 期間 | 誕生 commit：`EPUB 背景字數統計 + 分頁估算 + 頁尾 + 跳頁`，當時字元數來源是 Readium 原生端 `onCharacterCountReady` 回呼 |
| `17e969e` | 2026-08-05 | `epic-18` Issue 25 審查修正——行高 0.0 導致除以零崩潰 |
| `c4b3b76` | 2026-08-11 11:43 | `epic-18` Issue 46——改用幾何模型精修頁次估算 |
| `7dd27df` | 2026-08-11 13:43 | `epic-18` Issue 46 審查修正——fontSize/paragraphSpacing 防護 |
| `ed5b221` | 2026-08-14 07:30 | `epic-28` Issue 1 審查修正——納入 letterSpacing 版面密度變數 |

**關鍵時間點**：`c4b3b76`（08-11 11:43）與後續兩筆修正都**晚於或緊接在**同一天發布的架構檢視報告 `bc06de6`（08-11 12:36）前後——團隊在明確記錄「這條管線不可觸達」的報告發布前後，仍持續對死路徑投入功能性修正，顯示發現當時未被交叉連結到進行中的工作流。

### B.3 移除來源

- `cc1d5a5`（2026-07-31）`epic-20` Issue 5 Task 1——刪除 `epub_reader_view.dart`（`onCharacterCountReady`/`totalCharacterCount` 定義處），同時從 `reader_screen.dart` 移除唯一呼叫 `saveTotalCharacterCount()` 的 `_handleCharacterCountReady()`。
- `3e76c69`（2026-07-31）`epic-20` Issue 5 Task 2——原生端 Kotlin `EpubReaderView`／`readium-navigator` 對應清理。

`saveTotalCharacterCount()` 自 `cc1d5a5` 起即是孤兒方法，`git grep` 全庫確認正式程式碼零呼叫點。

### B.4 規劃文件中的決策紀錄（證明「已記錄」）

- **ADR 0011**：「`EpubCharacterCounter.kt`／`EpubPageEstimator` 兩個模組僅在 FXL 路徑（仍是 Readium）繼續視需要保留，流式路徑不再呼叫；**是否連 FXL 路徑也一併清理，留待未來 Epic 評估**（不阻塞 Phase 1）。」
- **epic-17 spec.md**：明文規定 `openBook`/`setPreferences` 不送出 `totalCharacterCount`，原生端不呼叫任何字數統計，頁碼改用 foliate-js `relocate` 事件的 `location.current`/`location.total`。
- **epic-17 issues.md**（Issue 6）：「不送出 `totalCharacterCount`、不呼叫任何字數統計。」
- **epic-20 plan-issue-4.md**：審查時已明確查證「`_buildEpubFooter`/`onCharacterCountReady`/`_totalCharacterCount` 此路徑自 `epic-17` 起即已是死碼，與本 Issue 無關，**如需清理留給 Issue 5 或另立工單評估**」；Global Constraints 明文「不擴大範圍去清理……預設維持現狀不動」。
- **epic-20 issues.md**（Issue 5）：實際範圍只列刪除 `EpubReaderView.kt`／`epub_reader_view.dart`／原生 Gradle 依賴，**並未包含**三者的清理——被 Issue 4「甩鍋」給 Issue 5，但 Issue 5 未接手，形成一次規劃階段層層轉手、最終沒人拿起來做的落空。

### B.5 2026-08-11 架構檢視報告：問題被完整重新發現

`bc06de6`（2026-08-11）`docs/research/architecture-review-test-suite-epub-pdf.md` 的「候選 4：收斂已死的 EPUB 頁次估算管線」章節，逐字命中這個落差：

> 「`totalCharacterCount` 的唯一寫入來源（Readium 的 `onCharacterCountReady`）已隨 epic-20 移除，`FoliateEpubReaderView` 從未實作替代回呼——`_buildEpubFooter()`、整個 `EpubPageEstimator`、`EpubCharacterCountRepository` 在生產環境對目前唯一的渲染路徑全部不可觸達。與 `epic-18-reader-device-qa` Issue 46 發現的 `pageMargins` 死欄位同源，但範圍比單一欄位大得多。」

報告列出兩個選項：(a) 確認估算頁碼已被 foliate-js 原生 `location.current`/`location.total` 取代、整批除役；或 (b) 重新設計 foliate-js 版字元數回報管道。標記強度「Worth exploring（需要人類先決策範圍，非機械式重構）」。

**但這份報告的建議至今未被落地**：對照 `docs/epics.md`，報告 7 個候選項目中只有「候選 1」（書籤 toggle 競態）被實際立案處理，「候選 4」沒有對應的 epic/issue 立案紀錄。報告發布後 3 天內，`epic-28` Issue 1 審查修正（`ed5b221`，08-14）仍繼續在 `EpubPageEstimator`／`_buildEpubFooter`／`TocBottomSheet._buildEntryRow` 上新增 `letterSpacing` 版面密度計算——持續往一條已知不可觸達的路徑投入開發資源。

### B.6 現狀遺留問題

`Book.totalCharacterCount` schema 欄位、`EpubCharacterCountRepository`、`EpubPageEstimator`（含其 `letterSpacing`/`lineHeight`/`paragraphSpacing` 等精修過的幾何模型）、`reader_screen.dart` 的 `_buildEpubFooter()`、`toc_bottom_sheet.dart` 的 TOC 頁碼標籤計算，全部依賴一個永遠是 `null` 的 `_totalCharacterCount`。正式環境對外觀察到的行為是「頁尾頁碼／TOC 頁碼標籤永遠顯示「…」佔位符」，且工程師仍持續維護、測試、審查這條使用者永遠看不到效果的路徑。

**若要處理，決策點在於**：
1. 目前實際生效的頁碼來源是 foliate-js `SectionProgress`（1500 bytes/location 的近似估算，非精確視覺頁），已足以支撐頁尾顯示；真正的缺口只在 TOC 頁碼標籤（`toc_bottom_sheet.dart`）。
2. 選項 (a)：確認 `location.current`/`totalPages` 已可涵蓋顯示需求，整批移除 `EpubPageEstimator`/`EpubCharacterCountRepository`/`totalCharacterCount` schema 欄位與相關遷移、`_buildEpubFooter()`、TOC 頁碼估算分支。
3. 選項 (b)：若堅持要在 TOC 顯示頁碼標籤，需另立管道讓 foliate-js 回報字元數（目前 JS 端完全沒有字元計數邏輯，`PageProgress` 的字元計數僅限單一 section 內部，非全書）。

---

## 附錄：本次研究涉及的 commit / 文件索引

- `23495b3`、`17e969e`、`c4b3b76`、`7dd27df`、`ed5b221`（`EpubPageEstimator`/`EpubCharacterCountRepository` 功能修正歷程）
- `cc1d5a5`、`3e76c69`（epic-20 Issue 5，移除 Readium `EpubReaderView`）
- `bc06de6`（架構檢視報告發布）
- `cd9d699`（架構檢視報告候選 1 立案，對照候選 4 未立案）
- `docs/adr/0011-epub-reflowable-migrate-to-foliate-js.md`
- `docs/epics/epic-17-*/spec.md`、`issues.md`（Issue 6）
- `docs/epics/epic-20-*/plans/plan-issue-4.md`、`issues.md`（Issue 5）
- `docs/research/architecture-review-test-suite-epub-pdf.md`（候選 4）
