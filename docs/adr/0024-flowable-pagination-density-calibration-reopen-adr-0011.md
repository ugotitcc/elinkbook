# ADR 0024：流式 EPUB 頁碼估算改用已渲染 section 密度校正（重新開放 ADR 0011 取捨）

## 狀態

已採納

## 背景

ADR 0011 決策項「頁碼估算改用 foliate-js `SectionProgress.getProgress()`」明確接受一項取捨：「換算出的總頁數估算值與使用者原本看到的數字可能不同，但兩者本來就都只是估算值，不影響正確性」——固定用「1500 bytes（XHTML 原始檔位元組數）＝ 1 個 location」的全書統一常數換算頁碼，完全不管使用者當下實際的字體大小／行距／段落間距／邊距／單雙欄設定。

`docs/research/flowable_pagination_precision_architecture_review.md`（候選 2）指出：`paginator.js` 的 `View.expand()` 對每一個已渲染 section 都精確算得出 `contentPages`（`Math.ceil(contentSize / columnSize)`），但這個數字從未回饋給 `SectionProgress`，兩套計算永不交會。`/grill-with-docs` 會談（Epic 26 Issue 11 規劃階段）逐一查證：`contentPages` 完全隨使用者排版設定變動、預載範圍有上限（同時最多渲染 8 個 section）、目前的捲動模式完全不計算這筆資料。即便有這些限制，只要能抓到使用者當下正在看的 section 的真實密度、套用回全書估計，精準度也會比「完全忽略使用者排版設定」的現狀好上不少，經權衡後決定投入，正式重新開放 ADR 0011 這項取捨。

## 決策

- **正式重新開放 ADR 0011 該項取捨**：`SectionProgress` 仍是唯一頁碼引擎（不做候選 1 之外的架構變動），但改吃「已知 section 用實測密度、未知 section 用最近鄰已知密度外插」，取代全書統一常數 1500。
- **密度資料串接點**：`paginator.js` 計算 `detail.fraction`／`detail.size` 的同一處，多帶一個 `detail.contentPages` 欄位進 `relocate` 事件 detail；`view.js` 的 `#onRelocate()` 直接把這個現成數字轉呼叫 `SectionProgress` 新增的密度紀錄方法，不透過既有 `fraction`／`size` 反推——避免 `View` 額外耦合 `Paginator` 內部欄數／預設值細節。
- **範圍侷限分頁（無捲動）模式**：`Paginator` 只在非捲動分支才計算 `contentPages`；捲動模式下「頁」本來就不是有意義的離散概念，維持原本純位元組估計不變，本次不處理。
- **密度快取只存在單次開書 session，不持久化**：純 JS 記憶體內的 Map，跟著 `View`／`SectionProgress` 的生命週期走，不新增 JS↔Dart↔SQLite 的序列化/還原管線。使用者正常一次坐下讀一本書，讀到的章節自然就會累積密度，不需要跨 session 保留也能拿到大部分好處。
- **快取失效策略：`applyPreferences()` 被呼叫時整包清空重算**。已查證字體大小／行距／段落間距／邊距／單雙欄／螢幕方向／直排橫排切換全部流經這個唯一入口（`main.js` 的 `window.applyPreferences`），掛一處即可涵蓋所有排版變因，不做依排版指紋分開保留多份快取的加法。
- **外插策略：章節索引距離最近的已知 section，索引距離相等時取索引較小者**。不做全域簡單平均、也不做「時間上最近瀏覽過」的替代方案。
- **不新增校正可信度旗標**：呼叫端（`reader_screen.dart` 的 `displayPageIndex`／`displayTotalPages`）完全無感沿用既有 `EpubPositionInfo` 欄位名，不新增型別或 UI 上「這是校正過的估計值」標示；`docs/research/...` 候選 3（三層座標重新分層）在此決定下不需要獨立工作。

## 後果

- `SectionProgress`（`progress.js`）需要新增一個密度紀錄方法與內部 Map 狀態，從無狀態純函式類別變成有狀態、跟隨 `View` 生命週期的類別。
- 使用者剛打開一本長篇書時，總頁數顯示仍是粗略估計（外插自僅有的少數已知章節），會隨著繼續閱讀逐漸變準——這是刻意接受的漸進式精準化，非缺陷。
- 捲動模式（換頁模式：捲動）的頁碼／進度顯示精準度不受本次改動影響，維持 ADR 0011 原本的位元組估計現狀。

## 曾考慮的替代方案

- **持久化密度快取到 SQLite，跨 session 沿用**：精準度可以更快收斂，但需要新增序列化格式、資料表、開書時讀取還原的流程，複雜度明顯提高，予以排除。
- **依排版指紋（fontSize／lineHeight／margins／columnCount 組合）分開保留多份密度快取**：可以在使用者反覆切換排版設定時保留舊校正結果，但需要額外設計 key 正規化與多份 Map 的記憶體管理，且使用者一次閱讀 session 內反覆切換排版組合的情境本來就少見，效益不成比例，予以排除。
- **捲動模式也納入密度校正**：需要另外定義「捲動模式下的頁密度」是什麼（例如改用可視範圍高度校正），範圍與複雜度大幅增加，且候選 2 原始研究報告本身也未涵蓋這塊，予以排除。
