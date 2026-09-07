# Epic 38 — 閱讀器 Chrome／TTS 重構：Discovery

## 緣起與範圍界定

`DESIGN.md` §19「階段二：閱讀器 UI 與 TTS 重構」自 `eink-redesign-rebuild-plan.md` 階段 A/B 起就已規劃，但 `epic-35`／`epic-36` 皆明確排除（「既有 2b/2c 閱讀器、2d 版面設定四分頁：邏輯與版面都不動」）。本 Epic 是這個既定路線圖的正式立案，透過 `/grill-with-docs` 完成 Discovery，依據兩份文件：

- `docs/research/uiux/elinkBook-eink-redesign.dc.html`（Turn 2 的 2b「閱讀器」／2c「朗讀中」分節）——最初的視覺方向稿。
- `prototype/eink_redesign_prototype.html`——使用者提供的「最後修訂結果」，實際可互動的 HTML 原型，**本 Epic 按鈕配置與互動細節一律以此為準**，dc.html 與 `DESIGN.md` §12.1 舊文字規格在有出入時皆讓位。

同一輪 Discovery 另外處理了書架每頁列數的調整，因為範圍（單一畫面、小改動）與本 Epic（多檔案、大改動）差異太大，已拆開追蹤——見 `docs/epics/epic-36-adaptive-shelf-navigation/issues.md` Issue 7，不屬於本 Epic。

## 現有程式碼現況（決定了本 Epic 是「收斂三份」還是「重寫一份」）

實際查證 `app/lib/screens/reader_screen.dart` `_buildBody()`，現況是**三種並存的 Chrome 風格**，不是「EPUB/PDF 兩份重複」這麼單純：

1. **流式 EPUB**：`_buildAppBarActions()` 回傳標準 `AppBar` 動作圖示（目錄 `Icons.menu_book`／版面設定 `Icons.settings`／筆記 `Icons.bookmarks`，各自呼叫 `_openToc`／`_openLayoutSettings`／`_openNotesSheet`）——相對乾淨，不在 `DESIGN.md` §12.1 點名的問題之列。
2. **FXL（固定版面 EPUB/CBZ）**：`_buildAppBarActions()` 對此格式回傳 `null`，改用約 20 處 `Positioned` 浮動圓鈕。
3. **PDF**：同樣回傳 `null`，也是浮動圓鈕，跟 FXL 各自一份、非共用程式碼。

`TtsMiniPlayer`（`app/lib/screens/tts_mini_player.dart`）已存在——膠囊型浮動列（上一句/播放暫停/下一句/語速/關閉），比新設計簡單很多：沒有句數進度文字、沒有語音顯示、沒有睡眠定時器。且其 `onClose` 目前**只隱藏面板、不停止播放**（原始碼註解明講「不影響 `TtsController` 的播放狀態」），這跟 `DESIGN.md` §13.1 文字本身（「點擊「✕ 關閉」必須停止 TTS 播放並釋放音訊焦點」）已經有既有落差——不是本 Epic 造成的回歸，是本來就有的落差，本 Epic 順手修正。

`TtsController`（`app/lib/reader/tts_controller.dart`）已有 `segments`（`List<TtsSegmentCfi>`）與 `currentIndex`，句數進度（「3 / 41 句」）可以直接算出，**底層真的已經有**；但**完全沒有睡眠定時器的任何欄位或邏輯**，2c 稿子這部分是新功能，不是既有狀態曝光。

`NotesBottomSheet`（`app/lib/screens/notes_bottom_sheet.dart`）維持既有雙分頁結構（🔖 書籤／✏️ 劃線與備註，見 `CONTEXT.md`「筆記（Notes Entry）」詞條），本 Epic 不拆開它，只是新的底部「劃線筆記」按鈕改為預設停在劃線分頁開啟。

`_toggleBookmark()` 既有的一鍵新增/切換當前位置書籤邏輯已存在且完整，底列「書籤」按鈕直接沿用，不用重做。

## 本次落地範圍

### Chrome 統一（對應 `DESIGN.md` §12）

- **範圍**：流式 EPUB／FXL／PDF **三種風格全部收斂**成同一套自訂上下 Chrome Bar，共用同一份 widget——維持三套外觀不同會違背「統一」的初衷，之後任何 Chrome Bar 改動還是得在三處各做一次（比照 `epic-36` Issue 3 之前分頁狀態散落各處的教訓）。
- **邊界（不可動搖的架構限制）**：僅 Chrome（按鈕列）這一層合併；`PdfReaderView`／`FoliateReaderView` 底層渲染內容維持 `CLAUDE.md` 記載的「兩條完全獨立渲染路徑」不合併——Isolate closure、Tap Zone Detector 等既有「不可逆的技術決策」不受本 Epic 影響。
- **按鈕配置**（以 `prototype/eink_redesign_prototype.html` 為準）：
  - **頂部列**：‹ 返回 ／ 標題與章節 ／ ⌕ 搜尋 ／ ⬓ 沉浸模式切換 ／ ☰ 目錄。
  - **底部列（4 顆）**：⚑ 書籤（一鍵新增/切換當前位置書籤，沿用既有 `_toggleBookmark()`）／ ✎ 劃線筆記（開啟既有 `NotesBottomSheet`，預設停在「劃線與備註」分頁）／ Aa 版面 ／ ◗ 朗讀。
  - **不採用**：dc.html 2b 視覺稿頂部列最後一顆圖示曾被誤讀為「書籤 Toggle」或「選單」；`DESIGN.md` §12.1 文字規格寫的順序、底部兩列結構（頁碼列＋4圖示列）也跟 prototype 有出入。**一律以 prototype 為準**，`DESIGN.md` §12 需在 Architecting 階段同步訂正。

### 沉浸模式雙觸發（更新既有機制，非新機制）

`CONTEXT.md` 既有「沉浸模式（Immersive Mode）」詞條原本只有熱區「選單」動作一種觸發方式，且明文寫 EPUB流式/PDF 與 FXL 行為不同（因為當時 Chrome 還沒統一）。本 Epic：

- 新增第二個觸發方式：頂部列 ⬓ 按鈕。兩種觸發方式**並存**，都切換同一個狀態——不拿掉熱區「選單」動作，使用者既有的九宮格自訂設定（`Nav Zone Mode`）不受影響。
- Chrome 統一後，此切換**不再依格式而有差異**（三格式共用同一套邏輯）。
- 朗讀（TTS）進行中時，此切換收合/顯示的對象是「TTS 常駐面板」整體——這是疊加在外層的獨立狀態，跟面板自己的「收合成細列」子狀態是兩層不同機制。

`CONTEXT.md` 已同步更新（見該檔案「沉浸模式」詞條）。

### TTS 常駐面板重構（對應 `DESIGN.md` §13）

新的「TTS 常駐面板」取代既有 `TtsMiniPlayer`＋規劃中未落地的「TTS Expanded Sheet」兩層舊設計：

- 與一般閱讀 Chrome 底列**完全互斥**（`isTtsActive` 狀態切換兩者，非疊加顯示）。
- 面板本身兩排：
  - 展開控制列（52dp/56dp 大按鈕）：⏮ 上一句／播放暫停／⏭ 下一句／語速／語音。
  - 底層動作列：睡眠定時器／收合成細列／停止朗讀。
- **「收合成細列」**：只隱藏展開控制列那一排，底層動作列（睡眠/收合/停止）維持顯示——面板從兩排收成一排，不是縮成一個小膠囊。
- **「停止朗讀」**：真正停止播放＋釋放音訊焦點＋還原播放鍵狀態，回到一般閱讀 Chrome（2b）。
- **⬓ 全收（沉浸模式）**：整個 TTS 面板（含底層動作列）一起消失，只留頂列＋內文，播放繼續但畫面上無任何朗讀中指示——**新增一個小喇叭圖示放在 ⬓ 旁邊**，提示朗讀仍在進行中（呼應 `DESIGN.md` §13.1 對「背景播放需要視覺提示」的既有精神，即使這裡是前景收合而非真正背景化）。
- 這三層收合狀態彼此獨立，`CONTEXT.md`「TTS 常駐面板」詞條已記錄，避免未來討論時把「收合成細列」跟「沉浸模式收合」混為一談。

### 睡眠定時器（新功能，非既有狀態曝光）

- 固定選項清單：15／30／45／60 分＋「不限時」還原選項（不採用自由輸入分鐘數——E-Ink 電子紙不利於輸入數字）。
- 時間到時**暫停**朗讀（保留進度，可再按繼續），不是停止朗讀、不清空任何朗讀狀態——比照使用者睡前設定定時器、不小心睡著的常見情境，隔天還能從原位置接著聽。

## 明確排除於本 Epic 之外

- `DESIGN.md` §12.2「直排頁面標題與頁尾自適應」——`RotatedBox` 轉向問題，本輪 Discovery 未觸及，Architecting 階段需確認是否併入或另立工單。
- `DESIGN.md` §14（劃線與備註元件）、§15（圖書庫）、§16（來源管理）、§17（設定畫面）——皆與本 Epic 無關，各自獨立範圍。
- 2d 版面設定四分頁（字級/行距/字重等 Stepper、換頁模式、欄數、書寫方向等）——`eink-redesign-rebuild-plan.md` 已明記「邏輯與版面都不動，只需要能跟著新主題換色」，這些既有功能已經是 Stepper 樣式（非本 Epic 新做），不在本次範圍。
- 書架每頁列數動態計算——已拆到 `epic-36` Issue 7，不在本 Epic。

## 已解決的規格矛盾（Architecting 階段無需再確認，直接照此執行）

1. **Chrome 按鈕配置以 prototype 為準，非 dc.html 視覺稿、非 `DESIGN.md` §12.1 舊文字**——三者三種說法，逐一核對後 prototype 是使用者確認過的「最後修訂結果」，具最高權威。
2. **合併只限 Chrome 層，不含底層渲染**——`CLAUDE.md` 已有明文的架構限制，不是本 Epic 需要重新論證的取捨。
3. **沉浸模式是既有機制的擴充（新增觸發點），不是新機制**——避免 Architecting 階段誤判成要設計一個全新的顯示/隱藏系統。
4. **「收合成細列」與「停止朗讀」是兩個不同動作，不可合併成一顆按鈕**——這正是本 Epic 要修正的既有 `TtsMiniPlayer.onClose` 語意含糊問題，Architecting 階段不應該為了簡化又把它們合併回去。
5. **不需要 ADR**——本 Epic 是落實 `DESIGN.md` §19 既有路線圖，沒有推翻任何已文件化的架構決策；渲染層不合併的邊界本身已是既有硬限制，不是本 Epic 的新取捨。

## 下一步

Architecting（`spec.md`）：定義 `ReaderChromeBar`（或類似命名，統一元件）、`TtsPanel` 等核心元件介面與狀態機，訂正 `DESIGN.md` §12/§13 對應段落，確認 §12.2 直排頁首頁尾自適應是否併入範圍。之後進 Scrum Master 階段拆 `issues.md`（初步預估至少 3 個垂直切片：Chrome Bar 統一＋沉浸模式雙觸發／TTS 常駐面板重構＋收合分層／睡眠定時器新功能，實際切法留待 Architecting 完成後依 `spec.md` 決定）。
