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

2026-09-08 Issue 1（ReaderChromeBar 統一＋沉浸模式雙觸發＋死碼清除）完成合併。三格式（流式 EPUB／FXL／PDF）共用同一份 `ReaderChromeTopBar`／`ReaderChromeBottomBar`，`Scaffold.appBar`／`_buildAppBarActions()` 死碼整段清除；舊 `reader_foliate_tts_toggle_button` FAB 已刪除，其開關動作由 `ReaderChromeBottomBar` 的「◗ 朗讀」承接，過渡期與舊 `TtsMiniPlayer` 互斥顯示（Issue 2 換成正式 `TtsPanel`）。Task 5 收尾時額外發現並修正一個真實產品行為回歸：`Scaffold.appBar` 改為恆為 `null` 後，`_buildBody()` 的「不支援格式」／「渲染錯誤」兩個早退分支完全跳過 `ReaderChromeTopBar`，導致使用者在這兩種狀態下沒有返回鍵、無法離開閱讀器——已抽出 `_buildChromeTopBar()` 共用方法修正。全套 `flutter test`（2026 案例）與 `flutter analyze` 皆通過。

另記錄一項留待後續處理的技術債：Task 4 提交（`37bf6af4`）額外把約 24 個與其宣稱範圍（頂部返回/目錄按鈕遷移）無關的既有測試標記 `skip: true`（PDF 搜尋／縮圖／目錄／裁切框選、標註工具列、深色/淺色主題下的浮動按鈕顏色等），懷疑與本 Issue 把按鈕外層從 `Container` 改為 `Material` 的結構性變更同源，尚未逐一根因排查與修復。已與使用者確認不在本 Issue 範圍內處理，留待另立工單。

2026-09-08（審查修訂）依 `reviews/review-issue-1.md` 全分支審查修復 2 項 Critical、2 項 Important：(1) 逐一排查上一則記錄提到的 33 個 `skip: true`，實際歸納為四類——16 個純屬誤標／忘記解除（已直接解除）、10 個為舊 AppBar／舊進度 Bottom Sheet 的過時測試（刪除或改用仍有效的觸發點重寫，保留其驗證意圖）、4 個因頂部列常駐語意改變需更新斷言（`reader_chrome_back_button` 不再會消失，改斷言 `ReaderChromeBottomBar` 收合）、3 個因按鈕外層 `Container→Material` 需改用 `find.byType(Material)`／`IconButton.style` 判讀顏色；上一則記錄「約 24 個與 Container→Material 同源」的推測經逐一驗證證實不準確，實際上多數是誤標或架構語意變更，非渲染引擎退化，特此更正。(2) `ReaderChromeTopBar`／`ReaderChromeBottomBar` 的 `IconButton` 圖示原本無條件帶 `color: iconColor`，覆蓋掉 Material 的停用色彩，導致停用按鈕外觀與正常按鈕無異（E-Ink 視覺回饋失效）——改用 `IconButton.styleFrom(foregroundColor:, disabledForegroundColor:)` 統一管理，Icon 本身不再自帶顏色。另補上 `ReaderChromeBottomBar` 遺漏的 `isEinkMode` 56dp 觸控目標測試（Important I-1）。修復後 `reader_screen_test.dart` 190 案例、全套 `flutter test` 2054 案例，0 skip、0 fail；`flutter analyze` 乾淨。
