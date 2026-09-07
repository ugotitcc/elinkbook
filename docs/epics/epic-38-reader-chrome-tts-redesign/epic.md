# `epic-38-reader-chrome-tts-redesign` 閱讀器 Chrome／TTS 重構

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-38-reader-chrome-tts-redesign/`
**關聯 PRD 章節：** 無新增 FR，屬於 `DESIGN.md` §12（閱讀器專屬元件與介面）／§13（語音朗讀 TTS 元件）／§19「階段二：閱讀器 UI 與 TTS 重構」規範落地。
**依循規則：** `UI_DESIGN_RULES.md`；`CLAUDE.md`「不可逆的技術決策」——`PdfReaderView`／`FoliateReaderView` 底層渲染維持兩條完全獨立路徑，本 Epic 僅合併 Chrome（按鈕列）這一層。
**依賴：** 無阻擋，可立即進入 Architecting。

## 開發記錄

2026-09-07 由 `/grill-with-docs` 規劃（依 `docs/research/uiux/elinkBook-eink-redesign.dc.html` Turn 2 的 2b/2c 分節，以及使用者提供的 `prototype/eink_redesign_prototype.html`「最後修訂結果」原型）。這是 `DESIGN.md` §19「階段二：閱讀器 UI 與 TTS 重構」的正式立案——`epic-35`／`epic-36` 皆明確排除閱讀器 Chrome／TTS UI 重構於範圍外（「既有 2b/2c 閱讀器、2d 版面設定四分頁：邏輯與版面都不動」），本 Epic 是承接的下一步。

**查證現況（非憑印象）**：`reader_screen.dart` `_buildBody()` 實際上有三種並存的 Chrome 風格，不是單純「EPUB/PDF 兩份重複」——(1) 流式 EPUB 已用標準 `AppBar`＋3 個動作圖示（目錄／版面設定／筆記），相對乾淨；(2) FXL（固定版面 EPUB/CBZ）與 (3) PDF 皆用約 20 處 `Positioned` 浮動圓鈕（`_buildAppBarActions()` 對這兩種格式回傳 `null`）——這才是 `DESIGN.md` §12.1「七顆浮動圓鈕」問題描述的對象。`TtsMiniPlayer`（`app/lib/screens/tts_mini_player.dart`）已存在，但功能遠比新設計簡單（無句數進度、無語音顯示、無睡眠定時器），且其「✕ 關閉」目前只隱藏面板、不停止播放——跟 `DESIGN.md` §13.1 文字本身（「必須停止並釋放音訊焦點」）已經有既有落差，本 Epic 順手修正。

**Discovery grilling 定案**（完整問答見 `design.md`）：
- Chrome 統一範圍：流式 EPUB／FXL／PDF **三種風格全部收斂**成同一套上下 Chrome Bar，共用同一份 widget；僅按鈕列合併，`PdfReaderView`／`FoliateReaderView` 底層渲染維持完全獨立（`CLAUDE.md` 硬限制）。
- 按鈕配置以 `prototype/eink_redesign_prototype.html` 為準（非 `DESIGN.md` §12.1 舊文字規格、非最初 dc.html 視覺稿的猜測）：頂列 ‹返回／標題章節／⌕搜尋／⬓沉浸模式切換／☰目錄；底列 ⚑書籤（一鍵切換）／✎劃線筆記（開啟既有雙分頁 `NotesBottomSheet`）／Aa版面／◗朗讀。
- 沉浸模式（既有 `CONTEXT.md` 詞條）新增第二個觸發方式（⬓ 按鈕，與既有熱區「選單」動作並存），且 Chrome 統一後不再依格式而有差異——`CONTEXT.md` 已同步更新。
- TTS 面板（2c）取代既有 `TtsMiniPlayer`／規劃中未落地的「TTS Expanded Sheet」：新增「TTS 常駐面板」概念，內部「展開／收合成細列」子狀態獨立於外層「沉浸模式」（⬓ 收掉整個面板）之外；「收合成細列」與「停止朗讀」拆成兩個不同動作，修正既有 `onClose` 語意含糊的落差。
- 睡眠定時器：新做後端功能（既有 `TtsController` 只有 `segments`/`currentIndex`/`speed`/`status`，沒有任何睡眠定時器邏輯），固定選項清單（15/30/45/60 分＋不限時），時間到「暫停」而非「停止」。
- 判斷**不需要 ADR**：本 Epic 是落實 `DESIGN.md` §19 既有路線圖，非推翻既有架構決策；Chrome 合併的邊界（渲染層不合併）本身已是 `CLAUDE.md` 明文的既定限制，不是本 Epic 新做的取捨。

`CONTEXT.md` 已同步新增/更新詞條：沉浸模式（雙觸發方式）、Chrome Bar、TTS 常駐面板、收合成細列/停止朗讀、睡眠定時器。

下一步：Architecting（`spec.md`），定義 `ReaderChromeBar`／`TtsPanel` 等核心元件介面，再進 Scrum Master 階段拆 `issues.md`。
