# `epic-56-pdf-paginated-reading` PDF 逐頁閱讀

**狀態：** 🟡 開發中 (Active)（Issue 1、2 已合併，其餘待寫計畫）
**存放路徑：** `docs/epics/epic-56-pdf-paginated-reading/`
**關聯 PRD 章節：** PDF 閱讀（預設 page-fit、影像濾鏡、裁切）、互動模式（E-Ink 減少過渡動畫、3×3 熱區、音量鍵翻頁）
**關聯 ADR：** 0022（PDF 引擎改用 `pdfrx`）
**規格：** `spec.md`（介面、型別、導覽規則與測試接縫）

## 背景

使用者回報（2026-10-03）：目前 PDF 閱讀時沒有辦法一次看到整頁，上下頁都還連著；換頁感覺像是一頁一頁往上滑動後才切到下一頁。希望有一種方式一次只看到該頁的全部，換頁就是一頁一頁切換。

查證結果（2026-10-03，`/grill-with-docs`）：

- `PdfReaderView` 底層是 `pdfrx` 的 `PdfViewer`，預設把所有頁面直向疊成連續捲動，所以鄰頁會露出。
- 換頁是 `goToPage()`／`goToArea()` 帶動畫捲過去（既有「PDF 翻頁動畫」設定：滑動／無，只控制動畫時長），這是「往上滑」感覺的來源。
- 設定面板有「Fit 模式」（Page-fit／Fit Width／真實比例），也會單書存檔，但 `pdf_reader_view.dart` 完全沒有讀取 `pdfFitMode`，目前實際行為只是 `pdfrx` 預設，並非詞彙表所述的「Page-fit 整頁完整顯示」。
- `pdfrx` 2.4.7 提供 `normalizeMatrix`、`panAxis` 掛鉤，可以限制平移範圍；但 `pdfrx` 會繪製所有與可視矩形相交的頁面（快取外擴另外決定哪些頁面被預先渲染，不影響可見性，見 `spec.md` 幾何隔離）。Page-fit 下頁面在螢幕的另一個維度會有留白，連續排列時留白處必然露出鄰頁，所以**單靠 `normalizeMatrix` 無法達成「鄰頁不可見」**，必須在 `layoutPages` 做幾何隔離（見設計決策；計畫審查 C-1 查證成立）。

## 目標

PDF 新增「翻頁模式」：**逐頁**（一次只顯示一頁，鄰頁不可見，瞬間切換）與**連續捲動**（現況）。逐頁為預設。同時把三種 Fit 模式真正接上渲染。

## 設計決策（`/grill-with-docs` 定案）

| 決策 | 結論 |
|---|---|
| 設定形態 | 新增「翻頁模式」二選一：逐頁／連續捲動；EPUB 與 PDF 共用「翻頁模式」一詞（詞條見 `CONTEXT.md`） |
| 持久化與預設 | 只放 PDF 設定面板，單書持久化於 `book_reader_prefs`，無全域預設層；沒存過一律視為逐頁（既有 PDF 升級後也變逐頁，閱讀位置照舊） |
| 資料庫 | `book_reader_prefs` 每個偏好是一個欄位（如 `pdf_fit_mode TEXT`），所以須：SQLite schema 由 v27 升到 v28、`_onUpgrade` 新增 `ALTER TABLE book_reader_prefs ADD COLUMN pdf_page_turn_mode TEXT`（比照 `pdf_page_turn_animation` 的追加方式）、初始建表 DDL 補欄位、`BookReaderPrefs` 的 `toMap`／`fromMap`／`copyWith`／`==`／`hashCode`、`ResolvedPreferences.resolve()`，以及所有重建 `BookReaderPrefs` 的呼叫點（`library_screen.dart`、`fxl_settings_sheet.dart`、`pdf_settings_sheet.dart`）都要帶上新欄位；升級路徑需有遷移測試 |
| 設定面板 | 「翻頁模式」放在 `PdfSettingsSheet` 的「顯示」分頁（與 Fit 模式、PDF 翻頁動畫同一分頁，現有三分頁為顯示／濾鏡／裁切）；選逐頁時隱藏「PDF 翻頁動畫」；新增字串須進四份 ARB 並通過 `check_l10n_hardcoded_strings.js` |
| 逐頁幾何隔離 | 逐頁模式的 `layoutPages` 必須把各頁（或 spread）在座標上拉開，間距大於任何合理可視範圍，使相鄰頁不可能同時落入可視矩形；再用 `normalizeMatrix` 把平移鎖在目前這頁。具體間距（固定大值 vs 依 view 尺寸）與兩個風險由第一個 spike 驗證：大座標下的浮點精度（數千頁 × 大間距）、`pdfrx` 在 view 尺寸改變（旋轉、摺疊）時是否重算 layout。雙頁 spread 與裁切版面用同一套隔離規則 |
| 轉場 | 逐頁下瞬間切換、無過渡動畫；「PDF 翻頁動畫」設定只在連續捲動下顯示 |
| 絕對跳轉 | 目錄、書籤、頁碼跳頁、底列進度：瞬間抵達目標頁（spread），視窗對齊該頁頂端，不繼承上一頁的頁內捲動偏移。**例外**：搜尋跳轉帶有高亮矩形時，視窗自動定位到包含該矩形的垂直區間，確保 3 秒暫態高亮看得到（頁面比螢幕高時） |
| 相對步進 | 3×3 熱區與音量鍵的「下一頁／上一頁」：頁面比螢幕高且未到頁底時先頁內步進一個螢幕高度（見下一列），到頁底後才瞬間換頁；單頁（Page-fit）時直接瞬間換頁 |
| 水平滑動 | 純粹的跨頁手勢：直接換頁並對齊新頁頂端（方向依雙頁方向鏡像），不做頁內步進；只在頁面沒有橫向溢出時生效（Page-fit、Fit Width），真實比例橫向可平移時滑動改為平移；頁內垂直移動一律交給垂直拖曳 |
| 閱讀統計 | 頁內垂直拖曳超過門檻（約 20dp）算一次閱讀活動並回報 `ReadingSession.recordActivity()`；否則長頁上專注閱讀、頁碼不變，統計會誤判閒置而凍結計時（現有 PDF 活動只來自頁碼變化、熱區與長按） |
| 框選衝突 | 長按拖曳框選優先，滑動翻頁只在沒有框選拖曳進行中、且為快速水平滑動時觸發（沿用 `_selectionDrag` 守衛） |
| Fit 模式 | 本 Epic 一併接上三種：Page-fit、Fit Width、真實比例 |
| 頁面比螢幕高 | 「下一頁」先往下捲一個螢幕高度（保留少量重疊），捲到頁底後才換到下一頁；「上一頁」對稱，頁內先往上退，到頂端後換到上一頁並落在該頁**底端**（可一屏一屏往回讀，不跳過上一頁尾段；2026-10-03 SPEC 審查 I-1 由使用者決定，取代原本的「落頂端」） |
| 雙頁與裁切 | 與逐頁正交：翻頁單位為一個 spread（或單頁），Page-fit 把整個 spread／裁切後頁面完整放進螢幕 |
| 頁碼與進度 | 逐頁下頁碼就是目前顯示的頁（雙頁為錨點頁），頁內捲動位置不納入；進度仍為（頁碼＋1）／總頁數；不新增儲存欄位、不動同步格式。代價：頁內捲到一半離開，重開回到該頁頂端（與現況相同） |
| E-Ink | 只保證逐頁換頁是單次重繪（無中間幀）；黑白閃爍清屏屬裝置相關能力，另立工單 |
| 對外介面 | `PdfReaderView` 新增 `pdfPageTurnMode`（`PdfPageTurnMode.paginated／scroll`）；widget 層預設連續捲動，產品預設的逐頁由 `reader_screen.dart` 明確傳入（比照 `dualPageMode`），避免既有 `PdfReaderView` widget 測試因預設改變而失效 |
| 測試 | 可視範圍、頁高於螢幕時的步進與換頁判定，抽成不依賴 Widget 的純 Dart 模組做單元測試；widget 層只留接線案例 |
| 詞彙 | `CONTEXT.md` 新增「翻頁模式」詞條（Avoid：分頁模式、翻頁模式）；「智慧自動裁切」詞條的「逐頁各自計算」改為「每頁各自計算」以免與新值「逐頁」混淆 |

## 範圍外

- E-Ink 整頁黑白閃爍清屏（另立工單，需真機調校）。
- 頁內捲動位置的儲存與同步。
- PDF 以外格式（EPUB 的翻頁模式維持現狀）。
- PDF Page Label、手寫標註（既有已知限制，不變）。

## 風險與待真機確認

- 滑動翻頁的手感，以及與長按框選、縮放平移的手勢衝突（`pdfrx` 以 `Listener` 驅動平移縮放，不參與手勢競技場，見 `pdf_reader_view.dart` 的 Epic 24 Issue 9 註解）。
- 限制可視範圍後，雙頁 spread、裁切版面、縮放後的邊界行為。
- Fit Width／真實比例下「先捲一個螢幕高度再換頁」的重疊量與頁底判定。
- 升級後既有 PDF 一律變逐頁，需讓使用者能一眼找到切回連續捲動的設定。

## 建議拆分方向（已於 Scrum Master 階段正式拆成 `issues.md` 的 6 個 Issue：原第 3 項再分出「幾何 spike」，其餘依序對應）

計畫審查 I-4 認為原「逐頁渲染＋Fit 模式」單一 Issue 太大，已拆開：

1. **Fit 模式接上**：先在既有連續捲動路徑下，讓 `pdfFitMode`（Page-fit／Fit Width／真實比例）真正驅動 `PdfReaderView` 的縮放基準。
2. **偏好與設定面板**：`PdfPageTurnMode`、`book_reader_prefs` 新欄位與 SQLite v28 遷移、設定面板（顯示分頁）、ARB、預設逐頁（此時逐頁尚無渲染，產品預設先不切換）。
3. **逐頁幾何與瞬間換頁（含 spike）**：先驗證幾何隔離的兩個風險，再做 `layoutPages` 隔離、`normalizeMatrix` 鎖定、Page-fit 下瞬間換頁、絕對跳轉與熱區／音量鍵接線、產品預設切到逐頁。
4. **長頁步進與跨頁接續**：頁面比螢幕高時的頁內步進、到頁底換頁、換上一頁落頂端、搜尋跳轉高亮自動定位、頁內拖曳活動回報。
5. **水平滑動翻頁與框選衝突**：滑動翻頁、與長按框選／縮放平移的衝突處理、真機確認。
純 Dart 規則模組（可視範圍、頁高於螢幕時的步進與換頁判定）在 3、4 內先寫、單元測試先行。

## 開發記錄

**2026-10-03 Epic 設計審查與修訂**（審查報告在 `reviews/review-epic.md`，不進版控；2 Critical／4 Important／3 Minor）

- 已採納並修進本文件：C-1（逐頁必須在 `layoutPages` 做幾何隔離，已用 `pdfrx` 原始碼查證）、C-2（導覽語意拆成絕對跳轉／相對步進／水平滑動）、I-1（SQLite v28 與遷移，已查證 `book_reader_prefs` 為一偏好一欄位）、I-2（頁內拖曳回報閱讀活動）、I-3（搜尋跳轉高亮自動定位）、I-4（拆分方向由 4 項改為 5 項）、M-1（ARB 納入設定面板決策列）。
- 部分採納：M-2 採納「放在設定面板並隱藏翻頁動畫」，但報告所稱「Tab 2 版面與導覽」不實——`PdfSettingsSheet` 實際三分頁為顯示／濾鏡／裁切，Fit 模式與翻頁動畫都在「顯示」分頁，故放「顯示」。
- 不採納：報告提到 `LayoutPreset` 需納入新欄位——查無 PDF 偏好欄位進入該結構，不列入工作項；M-3 序號：看板第 N 列對應 `epic-(N-1)` 是既有慣例（第 56 列為 epic-55），無需更動。
- 審查延伸發現（已決定）：Discovery 時詞彙表曾以「換頁模式」為正式詞，但既有 EPUB 版面覆寫對話框的 ARB 字串與 `CONTEXT.md` 全域預設詞條都用「翻頁模式」。使用者決定統一為「**翻頁模式**」（與現有 UI 一致，不動既有畫面）：`CONTEXT.md` 詞條改名並把「換頁模式」列為 Avoid，本文件與 `docs/epics.md` 同步改寫；`page_turn_mode.dart` 的類別註解仍寫「換頁模式」，日後動到該檔時順手對齊。
- 水平滑動在長頁上的行為（直接跨頁、落新頁頂端）是依審查建議補上的規格，與先前 Q3(d)／Q6(b) 的決定相容但屬新增細節，Issue 拆分時請使用者確認。

**2026-10-03 SPEC 審查與修訂**（審查報告在 `reviews/review-spec.md`，不進版控；0 Critical／3 Important／3 Minor）

- 已採納並修進 `spec.md`：I-2（連續捲動下 Fit 模式以開書當下的目前頁尺寸換算、捲動中不重算）、M-1（TTS 在長頁上同頁內不做句級追蹤捲動）、M-2（資料庫存有未知名稱時安全降級為逐頁的測試案例）、M-3（spike 以 32 位元浮點的次像素對位為驗證焦點，Dart 端 64 位元不是問題）。
- 部分採納：I-3 報告主張「必須把快取外擴設為 0，否則間距要拉大到 3 倍螢幕高」。查證 `pdfrx` 原始碼：快取外擴（可視矩形外擴 1 倍）只決定哪些頁面被預先渲染，不影響可見性，所以不變式只需針對可視矩形；且保留預設外擴可讓鄰頁被預先渲染、使瞬間換頁真正瞬間（設 0 則換頁時要現場渲染，E-Ink 上可能先看到低解析預覽）。因此 spec 不強制設 0，改把「外擴 0 或保留預設＋間距落在可視矩形之外、快取矩形之內」列為 spike 要用真機驗證的取捨，同時也降低了間距與座標總長度的壓力。
- 已決定（I-1）：使用者選擇改為「相對步進換到上一頁時落在上一單元底端」，與往下的逐屏步進對稱；`spec.md` 規則 4、使用者故事 19 與測試範例已修改，上方設計決策表同步更新。滑動翻頁與絕對跳轉仍落頂端。

**2026-10-03 Scrum Master 階段**：`issues.md` 拆成 6 個 Issue（1 Fit 模式接上、2 偏好＋設定面板＋SQLite v28、3 幾何 spike〔需真機〕、4 逐頁幾何＋瞬間換頁、5 長頁步進＋高亮跳轉＋活動回報、6 滑動翻頁＋框選衝突）。依賴：1、2、3 可平行，4 依賴前三者，5、6 依賴 4。Issue 1～6 須同一版本發布（Issue 2 合併後設定面板即出現尚無作用的選項，直到 Issue 4）。

**2026-10-03 Issue 拆分審查與修訂**（審查報告在 `reviews/review-issues.md`，不進版控；0 Critical／3 Important／3 Minor；40 則使用者故事與 10 條規則經矩陣核對無遺漏）

- 已採納並修進 `issues.md`：I-1（Issue 5 補 `onReadingActivity` 回呼接線合約，`ReadingSession` 由 `ReaderScreen` 私有持有、`PdfReaderView` 不得自行引用）、I-2（Issue 4 明訂暫態降級：長頁的相對步進先一律整頁換頁，頁內步進與上一頁落底端留待 Issue 5）、M-1（發版限制統一為「1～6 全數完成才可發布」）、M-2（逐頁下所有導覽動畫時長強制為零）、M-3（Issue 6 手勢時間戳用 `clock.now()`）。
- 部分採納：I-3 採納「補參數與縮放機制」——`pdfrx` 2.4.7 確有 `sizeDelegateProvider`（不可與已棄用的 `minScale`、`calculateInitialZoom` 並用），Issue 1 改為透過它提供初始與最小縮放；但報告建議的 `pdfFitMode` 非空預設為 Page-fit 不採納，改為可為空、`null` 表示沿用 `pdfrx` 現有預設，理由是 widget 層預設要保守以保護既有大量 `PdfReaderView` 測試（與 `pdfPageTurnMode` 同一原則），產品預設一律由 `ReaderScreen` 傳入。

**2026-10-03 Issue 1 計畫審查與修訂**（審查報告在 `reviews/review-plan-issue-1.md`，不進版控；0 Critical／3 Important／3 Minor；計畫見 `plans/plan-issue-1.md`）

- 已採納並修進計畫：I-1（`_applyFitZoom` 補版面為空與頁碼超界的防呆）、I-3（`goToPosition` 的水平對齊說明改為依 `pdfrx` 的文件層級 `underflowAnchor`，不自行算置中；Page-fit 在可視範圍較寬時的左右留白位置列為待真機確認，逐頁置中留給 Issue 4）、M-1（`didUpdateWidget` 補縮放與 reanchor 同時發生的時序註解）、M-2（測試補 fixture 尺寸前提說明）。
- 部分採納：I-2 報告建議 `_unitRectFor` 對超界頁碼回傳 `Rect.zero` 並多層範圍檢查。查證後不採納：`PdfSpreadLayout.spreadIndexOf` 已對超界 clamp、空陣列回 0（原始碼註解寫明呼叫端不需自行防呆）；且回傳 `Rect.zero` 經 `fitZoomForUnit` 加邊距後會算出 16×16 的內容而得到上限縮放 8 倍，比拋例外更糟。改採「spread 版面頁數與 `pdfrx` 目前版面不一致（雙頁／裁切切換的暫態）時退回該頁矩形」，頁碼超界一律由呼叫端（delegate 的 `_zoomFor`、`_applyFitZoom`）提前返回。

**2026-10-03 Issue 1 實作完成**（分支 `epic-56/issue-1-fit-mode`；計畫見 `plans/plan-issue-1.md`）

- 做法：新增純 Dart `pdf_paginated_rules.dart`（規則 1 縮放基準／對齊、規則 2 頁內捲動範圍；Issue 4～6 擴充）；`PdfFitSizeDelegate` 繼承 `pdfrx` 公開的 `PdfViewerSizeDelegateLegacy`，只覆寫最小縮放與開書初始縮放，其餘行為沿用；`PdfReaderView` 新增可為空的 `pdfFitMode`（`null`＝完全不干預，沿用 `pdfrx` 現行預設），`ReaderScreen` 一律傳入解析後的值；執行期切換經 `invalidate`＋兩層 postFrameCallback 以 `goToPosition` 重套新基準。
- 測試：新增 38 例（規則 19＋delegate 9＋widget 8＋reader_screen 2），既有測試一字未改；主線全套基準 3407 通過＋1 略過，分支全套 3445 通過＋1 略過（＋38、0 失敗）；`flutter analyze` 乾淨，l10n 硬編碼字串檢查 PASS。
- 與計畫的差異（Task 2 Ruling）：`onLayoutInitialized` 在同步 `setZoom` 之外，另排 `scheduleMicrotask` 以 `goToPosition`（單元含邊距左上＋基準縮放）重新定位。原因：`pdfrx` 在 delegate 之後同步 `_goToPage` 把初始頁帶進視野，其縮放取「錨定矩形 fit 值」與「目前縮放」較小者——計畫「翻頁不會破壞基準」的假設只在基準小於等於該 fit（Page-fit／Fit Width）時成立；真實比例 1.0 會被縮到 Fit Width（實測 0.637）。microtask 保證排在那次 `_goToPage` 之後、下一幀繪製前完成。若真機開書閃爍，再改為只在基準大於錨定 fit 時延遲套用。
- 需要知道的事：(1) 修改前 `pdfrx` 預設實際是 Fit Width 起始而非 Page-fit，現在產品預設（`ReaderScreen` 傳 Page-fit）會讓所有 PDF 開書變成整頁放進螢幕，是刻意的行為變更；(2) Fit 基準只在開書與切換 Fit 模式時套用，雙頁／裁切切換時沿用 `pdfrx`「保留縮放並夾最小縮放」行為（本 Issue 範圍外，Issue 4 處理）。
- 待真機確認：三種 Fit 模式在實機的初始畫面與旋轉後的表現；Page-fit 在可視範圍較寬時的左右留白位置（目前以 `pdfrx` 行為為準）。

**2026-10-03 Issue 1 程式審查**（獨立審查員，範圍 `24e0fdae..9a1c75fa`；審查報告在 `reviews/review-code-issue-1.md`，不進版控；0 Critical／3 Important／4 Minor，結論 Changes requested）

- I-1（已修）：單頁模式下 pdfrx 的 `goToPage` 縮放取「目前縮放」與「頁寬 fit」較小者，真實比例 1.0 遇到比螢幕寬的頁，翻一次頁就被縮成頁寬（實測 0.637）；之後雙指一碰又彈回。改為 Fit 模式啟用時單頁導覽走 `_goToUnitAtFitZoom`（`goToPosition`＋單元 Fit 基準縮放）。測試先紅（0.637≠1.0）後綠；另加 Page-fit 翻頁、Fit Width 跳頁兩個守衛測試。
- I-2（已修）：雙頁模式的 `_goToSpread` 用 `goToArea(anchor: all)`，一律把整個 spread 放進螢幕，Fit Width／真實比例翻第一頁就失效。同樣改走 `_goToUnitAtFitZoom`；測試用 800×240 讓 Fit Width（約 1.30）與 Page-fit（約 0.60）明顯不同，先紅後綠。`didUpdateWidget` 中不再成立的註解已更正。
- I-3（使用者決定選 B，放寬規格）：`pdfrx` 每次矩陣變動都用目前頁重算最小縮放，原實作取「目前單元基準」，捲到尺寸不同的頁面時最小縮放可能大於目前縮放，雙指縮放會彈跳。決定不凍結基準，改為最小縮放＝min(pdfrx 原本的最小縮放, 目前單元基準)——只會比 pdfrx 原本更寬鬆；`spec.md` 規則 1 與 `issues.md` Issue 1 已同步改為「連續捲動不強制不可縮到基準以下，逐頁模式才強制」。代價：Fit Width／真實比例下旋轉螢幕時沿用 pdfrx 的「保留目前縮放」，不會自動套用新基準（只有 Page-fit 會跟隨）；Issue 4 的逐頁模式需要「每個單元各自的最小縮放」，屆時 delegate 再加模式旗標。
- Minor 已全數修正（使用者決定）：M-1 裁切測試加上與未裁切 Page-fit 的比較（變異驗證：暫時關掉裁切版面時新斷言失敗、舊斷言仍通過）；M-2 delegate 測試名稱改為「退回 pdfrx 原本的指標，不丟例外」；M-3 移除永遠不會成立的頁數比對，註解改寫為 `_spreadLayout` 與 pdfrx 排版同步更新的真正保證；M-4 `_applyFitZoom` 在頁碼為 null 時直接返回，不再跳到第 1 頁。
- 驗證：修正後（含 Minor）`pdf_paginated_rules`／`pdf_fit_size_delegate`／`pdf_reader_view_*`／`reader_screen_test` 共 407 個通過、`flutter analyze` 乾淨、兩個 l10n 檢查 PASS；全套 `flutter test` 3450 通過、1 略過、0 失敗（在最終實作 commit 上跑）。

**2026-10-03 PR 合併（Issue 1）**

- PR #313（`epic-56/issue-1-fit-mode` → `main`）已合併，合併 commit `b92582c9`。Issue 1 完成。全套 `flutter test` 3450 通過、1 略過、0 失敗（發 PR 前在最終實作 commit 上跑）。
- 待真機確認：三種 Fit 模式在直向與橫向（雙頁 auto）下開書、翻頁、跳目錄後縮放是否維持；旋轉後的表現（Fit Width／真實比例沿用 pdfrx 保留縮放，不自動套新基準）；Page-fit 在可視範圍較寬時的左右留白位置。
- 後續：Issue 2（偏好＋設定面板＋SQLite v28）與 Issue 3（幾何 spike，需真機）互相獨立，可平行；Issue 4 依賴 1、2、3。Issue 4 的逐頁模式需要「每個單元各自的最小縮放」，屆時 `PdfFitSizeDelegate` 要加模式旗標。

**2026-10-03 Issue 2 實作完成**（分支 `epic-56/issue-2-page-turn-mode`；計畫見 `plans/plan-issue-2.md`，Native 內聯執行、未用 subagent）

- 做法：新增 `PdfPageTurnMode { paginated, scroll }`；`BookReaderPrefs.pdfPageTurnMode`（可為空，`null`＝逐頁，`toMap` 鍵 `pdf_page_turn_mode`，`fromMap` 經 `enumByNameOrNull` 使未知名稱降級為 `null`）；`ResolvedPreferences.pdfPageTurnMode`（非空，建構子預設 `paginated`，`resolve()` 取「單書值，否則逐頁」，無全域預設層）；`book_reader_prefs` 表加 `pdf_page_turn_mode TEXT`，schema 27→28（建表 DDL 同步，`onUpgrade` 的 `else` 分支內 `if (oldVersion < 28)` 追加，比照 `pdf_page_turn_animation` 既有慣例以避開 v1 跳級 `duplicate column name`）；書架版面覆寫、固定版面設定面板、PDF 設定面板三處整列重建皆帶上新欄位；`PdfSettingsSheet`「顯示」分頁在 Fit 模式之後、雙頁模式之前新增翻頁模式二選一 chip（`EBOptionChipGroup<PdfPageTurnMode>`，鍵 `pdf_settings_page_turn_mode_{paginated,scroll}`），選逐頁時隱藏「換頁動畫」（條件 `...[` 包裹，隱藏不清除其值）；四份 ARB 新增 `readerPdfPageTurnMode*` 5 鍵並 `flutter gen-l10n`；`PdfReaderView.pdfPageTurnMode`（widget 層預設連續捲動，保護既有測試，widget 內不讀取），`ReaderScreen` 傳入 `resolved.pdfPageTurnMode`。本 Issue 不改變任何渲染行為。
- 提交清單：`1bc14ce4` 偏好欄位與解析（Task 1）、`fdb1b11a` schema 27→28（Task 2）、`10900142` 書架＋固定版面重建保留（Task 3）、`3f6caccf` 設定面板＋ARB（Task 4）、`ff627e1b` `PdfReaderView` 參數與接線（Task 5）。
- 測試：新增 21 例（偏好模型 4＋解析 1、SQLite 遷移 3＋倉儲讀寫 2、書架 1＋固定版面 1、面板 6、`PdfReaderView` 預設 1＋`ReaderScreen` 接線 2）；全套 `flutter test` 3471 通過、1 略過、0 失敗（2026-10-03，在最終實作 commit 上跑；Issue 1 合併基準 3450＋21＝3471，吻合）；`flutter analyze` 乾淨，l10n 硬編碼字串雙檢查 PASS。每個 Task 皆做突變檢查（改壞後確認變紅再還原）。
- 與計畫的差異（Ruling）：(1) Task 1 Step 5「全部 PASS」預期不成立——`reader_prefs_manager_test` 的 DB-backed 測試因 `toMap` 先加鍵而需 Task 2 schema，純 Dart 全綠後先行，schema 落地後全綠，已記入 SDD ledger；(2) Task 4 計畫 Step 2 只列 4 個需改測試，實作發現第 5 個既有測試「關閉封面獨立開關後」因新增 chip 列把開關擠出 800×600 可視區而 tap 落空，加 `dragUntilVisible` 捲入可視區（顯示分頁本就有 `SingleChildScrollView`，非行為回歸）；(3) 面板條件顯示採直接多行 Edit（做法 B），一次成功，無需 Node 腳本。
- 提醒：本 Issue 合併後設定面板會出現「翻頁模式」，但選逐頁尚無作用，須待 Issue 4（逐頁幾何與瞬間換頁）；Epic 56 的 Issue 1～6 須同一個版本一起發布，中途不可切出發行版。
- 待真機確認：PDF 設定面板「顯示」分頁在小螢幕／E-Ink 下新增一列 chip 後是否仍可捲到最底（面板已用 `SingleChildScrollView`，widget 測試已證無 overflow）；選逐頁時「換頁動畫」是否確實消失、切回連續捲動時原值是否保留。
- 發現但未處理：`library_screen.dart` 書架版面覆寫 `_save` 整列重建時漏帶 `textConversionOverride`（既有缺陷，與本 Issue 無關，會把簡繁轉換覆寫清成 null），由使用者決定是否另開工單。
- PR #314（`epic-56/issue-2-page-turn-mode` → `main`）已合併，合併 commit `f3bc7b3f`。Issue 2 完成。程式審查：0 Critical／0 Important／3 Minor，結論可合併。上一項既有缺陷已另立 `epic-57-layout-override-save-drops-fields` 處理。

**2026-10-03 Issue 3 幾何 spike 完成**（計畫見 `plans/plan-issue-3.md`；實驗程式碼在未合併的 spike 分支，不進 `main`；本節為實驗記錄）

- 裝置：`WAVE`（E-Ink），Android 12，解析度 1872×1404，density 300。視窗（Flutter 邏輯像素）直放 748.8×692.3、橫放 998.4×442.7。無摺疊裝置，摺疊未測。
- 測試檔（以 `node tool/spike/make_spike_pdf.js <輸出檔> <頁數> <a4|mixed>` 在 `app/` 產生，細格線 0.25 pt、50 pt 一格、1 pt 邊框、對角線、頁碼）：`spike_a4_3000.pdf`（3000 頁 A4）、`spike_mixed_300.pdf`（300 頁混合：每 10 頁循環 A4 直式、A4 橫式、spread 1190×842、小頁 300×420、寬扁 1200×300、長頁 595×3000 等）、`spike_a4_2.pdf`（2 頁）。
- 實驗分支：`worktree-epic-56-issue-3-spike`（本機，不推送、不發 PR），最後 commit `034ee78d`。實驗畫面 `app/lib/spike/pdf_geometry_spike.dart`，入口 `flutter run -t lib/spike/spike_main.dart --dart-define=SPIKE_DIR=<目錄>`。
- 實驗程式缺陷（已修於 `034ee78d`，記錄以免誤判先前截圖）：「掃描」結尾原本還原到掃描的最後一個單元而非掃描前的單元，所以先前部分截圖的單元顯示為最後一頁；不影響掃描結果本身。
- 電腦端推算（`flutter test tool/spike/geometry_check.dart`，在 `app/` 執行；純 `dart run` 因引用 `dart:ui` 不可用）：

```
=== 表 1：縱向超出量（文件座標 pt）。間距必須大於此值 ===

[pageFit]
視窗 \ 頁面               A4 直 595x842      A4 橫 842x595      spread 1190x842   小頁 300x420        寬扁 1200x300       長頁 595x3000
手機直立 360x800          240               638               901               123               1183              0
手機橫放 800x360          0                 0                 0                 0                 120               0
平板直立 800x1280         55                376               531               30                810               0
摺疊內屏 600x700          0                 194               273               0                 550               0
極長螢幕 360x1000         405               872               1232              207               1517              0

[fitWidth]
視窗 \ 頁面               A4 直 595x842      A4 橫 842x595      spread 1190x842   小頁 300x420        寬扁 1200x300       長頁 595x3000
手機直立 360x800          240               638               901               123               1183              0
手機橫放 800x360          0                 0                 0                 0                 120               0
平板直立 800x1280         55                376               531               30                810               0
摺疊內屏 600x700          0                 194               273               0                 550               0
極長螢幕 360x1000         405               872               1232              207               1517              0

[actualSize]
視窗 \ 頁面               A4 直 595x842      A4 橫 842x595      spread 1190x842   小頁 300x420        寬扁 1200x300       長頁 595x3000
手機直立 360x800          0                 103               0                 190               250               0
手機橫放 800x360          0                 0                 0                 0                 30                0
平板直立 800x1280         219               343               219               430               490               0
摺疊內屏 600x700          0                 53                0                 140               200               0
極長螢幕 360x1000         79                203               79                290               350               0

=== 表 2：Float32 精度（平移量 ty ≈ y × 縮放，單位邏輯像素的 ULP）===
間距候選 × 頁數 → 最後一頁 y（pt）、在縮放 1／4／8 下 ty 的 ULP
gap=     0  n=  300  y=2.53e+5  ULP(z=1/4/8)=1.56e-2 / 6.25e-2 / 1.25e-1
gap=     0  n= 3000  y=2.53e+6  ULP(z=1/4/8)=2.50e-1 / 1.00e+0 / 2.00e+0
gap=     0  n=10000  y=8.42e+6  ULP(z=1/4/8)=1.00e+0 / 4.00e+0 / 8.00e+0
gap=  1000  n=  300  y=5.53e+5  ULP(z=1/4/8)=6.25e-2 / 2.50e-1 / 5.00e-1
gap=  1000  n= 3000  y=5.53e+6  ULP(z=1/4/8)=5.00e-1 / 2.00e+0 / 4.00e+0
gap=  1000  n=10000  y=1.84e+7  ULP(z=1/4/8)=2.00e+0 / 8.00e+0 / 1.60e+1
gap=  4000  n=  300  y=1.45e+6  ULP(z=1/4/8)=1.25e-1 / 5.00e-1 / 1.00e+0
gap=  4000  n= 3000  y=1.45e+7  ULP(z=1/4/8)=1.00e+0 / 4.00e+0 / 8.00e+0
gap=  4000  n=10000  y=4.84e+7  ULP(z=1/4/8)=4.00e+0 / 1.60e+1 / 3.20e+1
gap= 20000  n=  300  y=6.25e+6  ULP(z=1/4/8)=5.00e-1 / 2.00e+0 / 4.00e+0
gap= 20000  n= 3000  y=6.25e+7  ULP(z=1/4/8)=4.00e+0 / 1.60e+1 / 3.20e+1
gap= 20000  n=10000  y=2.08e+8  ULP(z=1/4/8)=1.60e+1 / 6.40e+1 / 1.28e+2
gap=100000  n=  300  y=3.03e+7  ULP(z=1/4/8)=2.00e+0 / 8.00e+0 / 1.60e+1
gap=100000  n= 3000  y=3.03e+8  ULP(z=1/4/8)=3.20e+1 / 1.28e+2 / 2.56e+2
gap=100000  n=10000  y=1.01e+9  ULP(z=1/4/8)=6.40e+1 / 2.56e+2 / 5.12e+2

判讀：ULP 接近或超過 0.1 邏輯像素，肉眼可能看到邊緣模糊或抖動。
```

- 問題 1（間距）：`mixed_300` 30 格掃描（最大相交頁數，1 為合格）：

| 視窗 | Fit | 間距 0 | 1000 | 4000 | 20000 | 自動 |
|---|---|---|---|---|---|---|
| 直放 | pageFit | 3 | 1 | 1 | 1 | 1 |
| 直放 | fitWidth | 3 | 1 | 1 | 1 | 1 |
| 直放 | actualSize | 3 | 1 | 1 | 1 | 1 |
| 橫放 | pageFit | 3 | 1 | 1 | 1 | 1 |
| 橫放 | fitWidth | 3 | 1 | 1 | 1 | 1 |
| 橫放 | actualSize | 3 | 1 | 1 | 1 | 1 |

  與電腦推算對照無矛盾：這台的最壞超出量約 405 pt（直放，寬扁頁）與約 116 pt（橫放），間距 0 小於超出量而失敗、1000 以上大於超出量而通過；截圖中的縮放值（例如 842×595 頁基準 0.889）與 `fitBaseScale` 一致。`a4_2`（2 頁）以自動與 4000 掃描，直放與橫放皆為 1、無崩潰。限制：未碰到電腦推算的最壞值 1517 pt（寬扁頁放進 360×1000 螢幕），固定值是否夠用只靠算式推導。
- 問題 2（快取外擴）：`a4_3000`、間距自動、pageFit、直放。守衛：外擴 1 第 100 頁可視相交頁 `[100]`、快取相交頁 `[99, 100, 101]`；外擴 0 兩者皆 `[100]`（截圖不進版控）。`dumpsys meminfo cc.ugotit.elinkbook`（KB）：

| 順序 | 外擴 | 起點 Native／PSS | 連翻 20 頁後 Native／PSS |
|---|---|---|---|
| 正向（先外擴 1，後 0，未重啟） | 1 | 175,216／449,630 | 173,784／447,887 |
| 正向 | 0 | 208,864／484,174 | 191,796／466,889 |
| 反向（冷啟動後先外擴 0，後 1） | 0 | 34,224／295,606 | 82,700／345,574 |
| 反向 | 1 | 88,020／352,155（含殘留） | 87,288／352,407 |

  連翻 20 頁（每 400 ms 一頁）：外擴 0 中間頁的版面變成白紙，外擴 1 逐頁可見。記憶體差距在兩種順序下正負相反，視為雜訊，外擴 1 的成本最多約 6.8 MB（PSS 約 2%）。未做：慢動作錄影、外擴 1 搭配固定間距 4000 於 3000 頁文件的對照（以 `a4_2` 的快取相交頁退化為單頁代替）。
- 問題 3（精度）：`a4_3000`、`actualSize`、外擴 1、直放；平移分級為人類主觀判斷（拖曳與放大約 4 倍）：

| 間距 | 頁 | 縮放 | 版面最大 y | 可視 y | 分級 |
|---|---|---|---|---|---|
| 自動 | 1 | 2.443 | 2,675,950 | 約 240 | 輕微 |
| 自動 | 1500 | 2.734 | 2,675,950 | 約 1,337,332 | 明顯 |
| 自動 | 3000 | 2.853 | 2,675,950 | 約 2,675,352 | 輕微 |
| 0（連續捲動對照） | 1500 | 2.228 | 2,526,000 | 約 1,262,378 | 輕微 |
| 20000 | 1500 | 2.000 | 62,506,000 | 約 31,242,429 | 輕微 |

  分級不隨理論誤差（0～4 邏輯像素）單調；自動第 1500 頁的「明顯」無法用浮點誤差解釋。未測：4000 的各頁、20000 的第 1／3000 頁、自動的 1500 頁以外其他縮放。靜止截圖的細格線與邊框乾淨。
- 問題 3（視窗尺寸改變）：`mixed_300`、自動、pageFit、外擴 1、第 3 頁（spread 尺寸）：

| 狀態 | 視窗（控制器／閉包） | 單元 | 可視相交頁 | 版面最大 y | `layoutPages` 累計呼叫 |
|---|---|---|---|---|---|
| R1 直放 | 748.8×692.3／748.8×692.3 | 3 | `[3]` | 330,738 | 697 |
| R2 橫放 | 998.4×442.7／998.4×442.7 | 3 | `[3]` | 302,922 | 702 |
| R3 直放 | 748.8×692.3／748.8×692.3 | 3 | `[3]` | 330,738 | 704 |

  旋轉後掃描最大相交頁數 1。「尺寸改變後主動回單元」開關未使用（無舊尺寸造成的不合格）。第 50 頁旋轉未測。觀察：實驗畫面跳到單元後 HUD 縮放為 1.000、可視矩形寬度等於視窗寬度，表示縮放未停在 pageFit 基準（以 spread 頁為例應約 0.63），原因未查證；旋轉後視窗保留原縮放與位置，不自動重新 pageFit。Issue 4 實作時須以測試確認單元切換後的縮放。
- 結論（已補回 `spec.md` 幾何隔離）：(1) 間距＝`max(超出量(前), 超出量(後)) + 50`，依視窗與單元尺寸即時計算；(2) 保留預設快取外擴 1.0，間距須落在 `(o, o + H × 外擴)`；(3) 3000 頁、間距到 20000 在這台 E-Ink 未見穩定退化（不代表萬頁安全），視窗尺寸改變時 `layoutPages` 同一輪用新尺寸重算，不需主動觸發。
- 範圍外發現：(a) 連翻時 E-Ink 外擴 0 的白紙現象在一般閱讀速度下較短，未量化；(b) 實驗用 `flutter run` 在這台 E-Ink 上同步檔案很慢（一次熱重啟 675 秒並因 `HttpException` 失敗），重新啟動後正常。

**2026-10-03 PR 合併（Issue 3）**

- PR #316（`epic-56/issue-3-spike-results` → `main`）已合併，合併 commit `88ec1998`。Issue 3 完成。純文件變更，未執行 `flutter test`。實驗分支 `worktree-epic-56-issue-3-spike`（最後 commit `034ee78d`）留在本機，不推送、不合併。
- 後續：Issue 4（逐頁幾何隔離與瞬間換頁）依賴 1、2、3，三者皆已合併，可開始寫計畫，並以 `spec.md` 幾何隔離段落的新結論為依據。Issue 4 要注意：旋轉後視窗不會自動重新 pageFit；實驗畫面跳到單元後縮放為 1.0 而非 pageFit 基準（原因未查證），須以測試確認；窄長手機、第 50 頁旋轉、摺疊裝置未測。
