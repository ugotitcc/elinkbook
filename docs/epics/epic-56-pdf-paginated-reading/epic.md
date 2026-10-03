# `epic-56-pdf-paginated-reading` PDF 逐頁閱讀

**狀態：** 🟡 開發中 (Active)（Discovery、SPEC、Issue 拆分已完成，待逐 Issue 寫計畫）
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
- 驗證：修正後（含 Minor）`pdf_paginated_rules`／`pdf_fit_size_delegate`／`pdf_reader_view_*`／`reader_screen_test` 共 407 個通過、`flutter analyze` 乾淨、兩個 l10n 檢查 PASS；全套 `flutter test` 尚未重跑。
