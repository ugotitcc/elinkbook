# foliate-js paginator.js 上游同步（設計文件）

**狀態：** 待人類審閱
**對應工單：** `epic-32-foliate-js-paginator-sync`（新 Epic，見 `docs/epics/epic-32-foliate-js-paginator-sync/issues.md`）
**診斷依據：** `docs/research/foliate_js_sync_update_strategy.md`（既有同步 SOP）＋本次 Discovery 階段對上游 diff 的實測分析

## 背景

`epic-31-touch-intent-unification` 規劃階段，發現上游 `readest/foliate-js` 目前落後我們釘定版本（`dd71f2be356563c16a23272686189fcfb45d0b82`，2026-07-19）**23 個 commit**。其中最大宗改動集中在 `paginator.js`（`main` 分支累計 +494/-75 行），且**光是一個 commit「改善分層翻頁反應性」（`6c6a491`）就佔了 +321/-53**，直接重寫了 `#onTouchStart`／`#onTouchMove`／`#touchState` 這幾個觸控核心機制——正是 Epic 31 要收斂的 main.js 5 個觸控機制所依賴、也是 Epic 18 Issue 47／Epic 25 Issue 1／Epic 27 Issue 9 三個歷史修法賴以攔截/校準的同一段程式碼。

Epic 31 目前只有規劃文件、尚未開始實作（一行程式都還沒動），現在調整順序（先同步、再回頭做 Epic 31）成本最低。

## 目標

1. 同步 `paginator.js` 至上游 commit `6c6a491`（合併 `f94b251`「fix: guard invalid paginator loads」與 `6c6a491`「feat(paginator): improve layered turn responsiveness」兩個 commit 的內容）。
2. 修復 `app/tool/check_foliate_es_compat.js` 的過時檔案路徑參照（`foliate_epub_reader_view.dart` → 現行的 `foliate_reader_view.dart`），否則 SOP 要求的 ES 相容性掃描這步跑不動——這是本次同步的先決條件，不是附帶事項。
3. 依既有 SOP 完成 ES 相容性掃描、Bridge 對齊檢查、`flutter analyze`／`flutter test` 基準線驗證。
4. **真機重測 3 個依賴 `paginator.js` 觸控內部行為的歷史修法**，逐項記錄結果：
   - Epic 18 Issue 47：長按候選期間 `touchmove` 攔截（`{ passive: false }`），避免誤判滑動。
   - Epic 25 Issue 1：`_NavZoneTapDetector._tapMaxDurationMs`（700ms）與九宮格熱區的快速點擊判定，避免選字時誤觸翻頁。
   - Epic 27 Issue 9：`no-swipe` 屬性設定，阻止特定情境下的滑動手勢。
5. 更新版本紀錄文件（`docs/research/foliate_js_sync_update_strategy.md` 的「當前 Pinned Commit」、`docs/epics.md`）。

## 非目標

- **不同步到上游最新 HEAD**（`2b6ea0a`，2026-08-24，全部 23 個 commit）——後續 21 個 commit 多數與本次動機無關（`fixed-layout.js` 的 FXL 大改動 +248/-77、`pdf.js`／`footnotes.js`／`tts.js`／`opds.js` 這些我們目前完全沒有釘定使用的上游新檔案、WebKit 專屬修法），刻意縮小這次同步範圍與真機驗證負擔。之後若要繼續往後同步，另立新的同步工作，SOP 本來就支援逐次鎖定新 commit。
- **不新增上游的新功能檔案**（`footnotes.js`／`pdf.js`／`tts.js`／`opds.js`）——這些是上游新增、我們目前完全沒有釘定也沒有使用的功能（PDF 我們自己走 pdfrx，不用 foliate-js 的 pdf.js）。是否採用 TTS 相關上游程式碼是完全獨立的未來決策，不在本次同步範圍內。
- **不修改任何 vendored 檔案內容**（只整份替換 `paginator.js`，不手動修改其原始碼），符合 ADR 0011。
- **不順便處理 Epic 31 的任何工作**——Epic 31 待本 Epic 完成、確認新版 `paginator.js` 行為後再回頭視需要調整其 design.md。

## 整體機制

### 同步範圍確認（Discovery 階段已用 GitHub API 驗證）

比對 `dd71f2b...6c6a491` 只有 **`paginator.js`** 變動（+338/-55，合併兩個 commit），其餘 11 個釘定檔案（`comic-book.js`／`construct-style-sheets-polyfill.js`／`epub.js`／`epubcfi.js`／`fixed-layout.js`／`mobi.js`／`overlayer.js`／`progress.js`／`text-walker.js`／`vendor/zip.js`／`view.js`）逐位元組相同，不需要替換。

### `#touchState` 結構變動摘要（供 Bridge 對齊檢查參考）

新版新增私有欄位：`releaseSamples`（速度取樣佇列）、`lastMovementTime`、`active`、`layeredGesture`（`'pending'`/`'rejected'` 等狀態）、`layeredEarlyClaimBlocked`、`layeredEdgeDirection`、`layeredHorizontalDirection` 等，並新增 `#rejectLayeredGesture()` 方法與一個新的 host 可設定屬性 `turn-gesture-left-inset`。這些欄位/方法皆為 `Paginator` 類別的私有實作細節（`#` 前綴），`main.js` 本來就無法、也沒有直接存取，理論上不構成 Bridge 契約層級的破壞性變更——但仍須逐一核對 `main.js` 實際呼叫到的**公開**方法（`view.next()`／`view.prev()`／`view.goToFraction()`／`view.goToCfi()`／`relocate` 事件 payload 等）簽章是否不變，不能只憑「是私有欄位」就跳過檢查。

**`turn-gesture-left-inset` 屬性（設計審查 Important #1，已用 diff 確認具體結論）**：這個新屬性讓 host（我們的 `main.js`）保留左側一塊控制區，不參與翻頁手勢的低位移快速判定路徑（原始 commit 註解舉例：垂直方向的亮度調整手勢）。程式碼是 `reservedLeftRatio = Number(this.getAttribute('turn-gesture-left-inset')) || 0`——屬性未設定時 `Number(null)` 為 `NaN`，`NaN || 0` 結果為 `0`，`earlyClaimBlocked` 恆為 `false`，即**預設狀態下不保留任何區域，不影響現有橫排/直排熱區行為，也不會跟 `main.js` 既有的 `no-swipe` 屬性（Epic 27 Issue 9，語意是完全停用滑動翻頁，跟這個屬性「只保留一塊區域、其餘正常」是不同語意）衝突**。因為 `main.js` 目前不會設定這個新屬性，Bridge 對齊檢查這項只需確認「確實沒有設定」即可，不需要額外開發或測試這個屬性本身的行為。

### 先決條件：修復 ES 相容性掃描工具

`app/tool/check_foliate_es_compat.js` 第 37-40 行寫死參照 `app/lib/reader/foliate_epub_reader_view.dart`，此檔案已在後續 Epic（ADR 0017／0023 統一 Foliate 格式）改名為 `app/lib/reader/foliate_reader_view.dart`，工具現況執行會直接拋出 `ENOENT` 例外（Discovery 階段已實測驗證此例外，並確認暫時替換 `paginator.js` 測試後已用 `git checkout` 乾淨還原，未留下任何異動）。本次同步的第一個工單必須先修這一行路徑，否則後續掃描步驟無法執行。

## 測試策略

**基準線**：`flutter analyze` 需為「No issues found!」，`flutter test` 全數通過。

**ES 相容性掃描**：`node app/tool/check_foliate_es_compat.js`（修復路徑後）結束碼須為 0；若非 0，依腳本列出的清單在 `_esCompatPolyfillJs`（`foliate_reader_view.dart`）補齊 polyfill，硬性規範（與 `docs/research/foliate_js_sync_update_strategy.md` 階段 3 一致，設計審查 Important #2 採納）：

1. 僅在 `if (!TargetAPI)` 缺席時才定義，不可覆寫瀏覽器原生實作。
2. **嚴禁使用 ES2021+ 語法糖**（禁止 `??=`、`||=`、`&&=`、可選鏈 `?.`、標籤模板等），本體必須為 ES5/ES2020 相容語法，確保能在 Chromium 83 上被正確解析。

**Puppeteer 自動化測試不是本次驗收的主要手段**：`epic-31` 規劃階段已實測確認，這個環境的 Chromium 版本（`151.0.7922.77`）下 CDP `touchmove` 事件送達 iframe 不可靠，這是與 `paginator.js` 版本無關的環境限制，換了新版一樣測不準。

**真機重測**（本次同步的核心驗收，不可省略，逐項記錄於該 Issue 的 review 報告）：

- Issue 47：橫排/直排長按選字前幾影格畫面不暴跳。
- Epic 25 Issue 1：畫線選取已確立時不誤觸跳頁（真機比對 Air Reader Pro C／TCL 14 吋兩種機型，比照原始 Issue 記錄的驗證方式）。
- Epic 27 Issue 9：特定情境下滑動手勢確實被 `no-swipe` 屬性正確阻止。
- 額外基本 smoke（設計審查 Minor #1，採納，改用客觀判準）：直排 EPUB 連續往前翻頁 5 次、再反向翻頁 5 次，比對是否精確回到原始文字錨點（不只是「感覺無縫」，而是往返後畫面內容/位置與出發點一致），確認這次同步至少沒有引入全新的、既有 3 個修法之外的回歸。

## 已知風險

- 只同步到 `6c6a491`（非最新 HEAD）代表之後若還要繼續跟上游同步，仍需再走一次完整 SOP（含真機重測），這是刻意的範圍取捨，不是遺漏。
- 若真機重測發現無法在合理時間內修復的回歸，直接 `git revert` 這次同步的 commit，退回 `dd71f2b`，不在時間壓力下硬修——Epic 31 本來就可以繼續等，不構成無法接受的阻塞。
