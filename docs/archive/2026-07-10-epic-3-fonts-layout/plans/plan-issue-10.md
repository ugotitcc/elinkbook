# Issue 10：漫畫（固定版面 EPUB）奇數頁與偶數頁縮放大小不一致 — 實作計劃

**Goal:** 確認使用者回報「奇數頁與偶數頁縮放比例不一致」的真正根因，若可行則在本 epic 階段一併修正；若根因超出本 epic 範圍，記錄結論並另立追蹤項目。

**目前狀態（承接自 issues.md）：**
- 已排除「奇偶頁本身版面尺寸不同」——解壓縮使用者提供的 `葬送的芙莉蓮 11.epub`，p-001 至 p-014 全數宣告相同的 `<meta name="viewport" content="width=1066, height=1600">` 與 SVG `viewBox="0 0 1066 1600"`。
- `EpubReaderView.kt` 的 `applyFxlFitScale()` 內已加上暫時性除錯日誌（`Log.d("DEBUG-oddeven", ...)`，含 `webView` identity hash、`url`、`contentWidth`/`contentHeight`、`fitScale`），尚未在真機上實際擷取執行。
- 本計劃即是把「擱置」狀態往下推進：先完成根因確認，才能判斷後續 Task 是否需要、以及需要哪些改動。

**與 Issue 8 的關聯：** `applyFxlFitScale()` 是 Issue 8 根因四／五修正時新增的邏輯——「View 樹中同時存在多個 WebView（`R2ViewPager` 為求翻頁流暢，預先保留相鄰頁）」與「pivot 縮放的置中位移校正」都是奇偶頁縮放比對時第一輪要檢查的候選根因，見下方假設 H1。

---

### Task 1：真機擷取 `DEBUG-oddeven` 日誌，建立可重現的觀察資料

**Files:**
- 無程式碼變更（現有除錯日誌已就緒）

**Description:**
在使用者提供的真實檔案（`U:\MyDeveloper\AI\elinkBook\tmp\葬送的芙莉蓮 11.epub`）上，於真機依序連續翻閱至少 10 頁（涵蓋封面＋奇數頁＋偶數頁交錯），透過 `adb logcat` 擷取 `DEBUG-oddeven` 標籤的輸出，整理成「頁碼 → `availableWidth`/`availableHeight`/`containerLoc`/`contentWidth`/`contentHeight`/`fitScale`」的對照表。

**日誌格式（已於程式碼中補齊，執行 Task 1 前先確認）：** `DEBUG-oddeven` 除了原有的 `contentWidth`/`contentHeight`/`fitScale`，已額外輸出 `container=[availableWidth x availableHeight]` 與 `Loc=(containerLoc.x,containerLoc.y)`，讓 H1（時序）與 H2（container 尺寸波動）兩個假設能在同一輪真機擷取中一併驗證，避免 H1 被證偽後還要重新改程式碼、重新建置安裝、重新翻頁擷取一次。

- [ ] **Step 1：清空 logcat 緩衝並啟動過濾擷取**

```bash
adb -s <device-id> logcat -c
adb -s <device-id> logcat -s "DEBUG-oddeven:D" > oddeven_capture.txt &
```

- [ ] **Step 2：於裝置上開啟該書、依序翻頁**

從封面開始，連續翻 10-14 頁（涵蓋使用者原始回報的「第 7, 8, 9 頁」），每頁翻頁後停留約 1 秒（確保 `ViewTreeObserver.OnGlobalLayoutListener` 觸發完成、日誌寫入）。

- [ ] **Step 3：整理輸出，比對相鄰頁 `fitScale` 差異**

依 `webView` identity hash 分組（`R2ViewPager` 同時保留多個 WebView 實例，同一頁在翻頁前後可能被多個不同 hash 的 WebView 處理過，需要對照 `url` 欄位還原「這一筆日誌對應哪一頁」），確認：
- 同一頁在不同時間點（例如剛翻到、翻頁動畫結束後）算出的 `fitScale` 是否有變化（時序問題）
- 奇數頁與偶數頁的 `fitScale` 數值本身是否真的不同（若 `contentWidth`/`contentHeight` 已確認全書一致，理論上 `fitScale` 應該也全書一致，除非 `availableWidth`/`availableHeight`——即 `container` 的量測尺寸——本身因某種原因隨頁碼變動）

---

### Task 2：依據 Task 1 資料，鎖定候選根因並驗證

**Description:**
根據既有 Issue 8 的除錯經驗，以下為分級後的候選假設（依可能性排序）。每項假設需先由 Task 1 資料證實或證偽，才進入對應修正。

**假設 H1（最可能）：`R2ViewPager` 相鄰頁預載入時序，導致「這一頁」量到的其實是另一個 WebView 的殘留/過期 `fitScale`**
`applyFxlFitScale()` 掛在 `container`（穩定不重建）的 `OnGlobalLayoutListener` 上，每次全域版面變化就對「當下 View 樹中找到的每一個 WebView」重新計算縮放。若翻頁動畫進行中，前後相鄰頁的 WebView 交替觸發 layout callback，可能出現「當下正在顯示的頁面」與「剛好觸發這次 callback 的 WebView」不是同一個，讀到的 `contentWidth`/`contentHeight` 若在該次觸發時還沒完全撐開（例如剛換頁、圖片尚未渲染完成），算出的 `fitScale` 會偏大（縮得不夠）。
- **預測：** 若成立，同一頁在 log 中應出現多筆時間點相近但 `fitScale` 不同的紀錄，且最終穩定值應該全書一致；「奇偶不一致」實際上是「使用者截圖到了尚未穩定的中間狀態」。
- **驗證方式：** Task 1 log 若同一 `webView` hash／`url` 有多筆時間相近但 `fitScale` 不同的紀錄，此假設成立。

**假設 H2：`container`（Flutter 給定的可用尺寸）本身在某些頁面量到不同數值**
`availableWidth`/`availableHeight` 來自 Flutter 端傳入、`SafeArea` 排除系統列後的容器尺寸；理論上同一次閱讀 session 內應該固定不變（除非旋轉），但若 Android 系統列（例如導覽列自動隱藏/顯示的手勢模式）在翻頁過程中被觸發顯示/隱藏，可能讓 `container` 尺寸在不同頁面量到的當下有差異。
- **預測：** 若成立，log 中不同頁面即使 `contentWidth`/`contentHeight` 相同，`fitScale` 仍會不同；`availableWidth`/`availableHeight`/`containerLoc` 已補進 Task 1 的日誌格式，同一輪擷取即可直接證實。

**假設 H3：奇偶頁在 View 樹中的巢狀深度或 sibling 順序不同，`findViewsByType` 走訪順序影響到哪個 WebView 被「先」套用縮放，進而影響 `translationX`/`translationY` 校正的正確性（縮放比例本身沒錯，但視覺上位移看起來像是縮放不同）**
使用者觀察到的「縮放大小不同」也可能其實是**置中位移計算錯誤**造成的視覺錯覺（例如某頁四邊留白不對稱，容易被誤判成「這頁縮得比較小」）。
- **預測：** 若成立，log 中 `fitScale` 數值本身在奇偶頁之間相同或極接近，但實際畫面截圖會顯示留白不對稱而非整體縮放比例不同。
- **驗證方式：** 需搭配真機截圖比對（不只看 log 數值），若 `fitScale` 數值一致但畫面觀感不同，改查 `translationX`/`translationY` 的計算（`applyFxlFitScale()` 中 `getLocationOnScreen()` 校正的部分）。

**假設 H4（低可能性，已大致排除）：頁面本身版面尺寸不同**
已在 Issue 10 描述中透過解壓縮比對 OPF/SVG viewBox 排除。

- [ ] **Step 1：依 Task 1 log 資料，逐一檢驗 H1 → H2 → H3，記錄結論**
- [ ] **Step 2：若需要，針對 H2/H3 補充額外除錯欄位（`availableWidth`/`availableHeight`／`translationX`/`translationY`）並重新擷取一輪**
- [ ] **Step 3：在 `issues.md` Issue 10 補上「根因確認」段落，比照 Issue 7/8 既有格式記錄**

---

### Task 3：依根因實作修正（範圍待 Task 2 結論後細化）

**Description:**
本 Task 的具體改動內容取決於 Task 2 找到的根因，暫列可能的修正方向供銜接：

- 若為 H1（時序問題）：可能需要在 `applyFxlFitScale()` 加入「僅對『目前實際顯示中』的 WebView 套用縮放」的判斷（例如比對 `webView` 是否為 `R2ViewPager.currentItem` 對應的 View，而非無差別套用給樹中所有找到的 WebView），或是加入 debounce／穩定後才套用的邏輯。**已查證排除的技術前提：** `R2ViewPager` 反編譯確認繼承自 classic `androidx.viewpager.widget.ViewPager`（非 ViewPager2），且 `pager` package 內無任何 `PageTransformer` 實作——分頁定位純靠原生 `View.layout()`/`scrollTo()`，不依賴 `translationX`/`translationY`，故此處的候選修正純粹是為了避免量到「尚未完成 layout 的預載頁」殘留錯誤縮放，與是否會干擾 ViewPager 本身的滑動動畫無關。
- 若為 H2（container 尺寸波動）：可能需要在系統列顯示狀態變化時也觸發重新計算（額外監聽對應事件），或改為快取「已知穩定」的容器尺寸、忽略短暫波動。
- 若為 H3（位移計算錯誤）：需重新檢視 `getLocationOnScreen()` 校正邏輯，可能與 Issue 8 根因五的既有實作有關，需要更精確的位移公式。

**驗收標準：**
- 若根因可在本 epic 範圍內修正，完成修正並移除除錯日誌（`grep -rn "DEBUG-oddeven"` 確認乾淨）
- 若根因超出本 epic 範圍（例如需要更大幅度重構 Readium 整合方式），在 `issues.md` 記錄結論，視情況另立新 issue／epic 追蹤，不阻塞本 epic 收尾
- 真機重新測試使用者原始回報情境（`葬送的芙莉蓮 11.epub` 連續翻頁），確認奇偶頁視覺上縮放一致
- `flutter test integration_test/epub_reader_view_test.dart` 真機通過、`flutter analyze` 乾淨
- `flutter test`（純 Dart）不迴歸

---

### Task 4：清理與收尾

**Description:**
比照既有 `/diagnose` Phase 6 規範：

- [ ] 移除所有 `DEBUG-oddeven` 除錯日誌
- [ ] 若有新增的臨時除錯欄位（Task 2 Step 2 可能新增），一併移除
- [ ] 確認 `EpubReaderView.kt` 的 `dispose()` 仍正確呼叫 `removeFxlLayoutListener()`（現有程式碼已如此實作，`dispose()` 第 601 行；此處僅作收尾前的迴歸確認，非新增修正）
- [ ] `docs/epics/epic-3-fonts-layout/issues.md` Issue 10 更新為最終狀態（已修復／記錄為超出範圍並另立追蹤）
- [ ] 若本 issue 的除錯過程凸顯了架構性問題（例如 `applyFxlFitScale()` 無法可靠判斷「目前顯示中」的 WebView），評估是否需要交接給 `/improve-codebase-architecture`
