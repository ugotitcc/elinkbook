# Epic 11 — 多格式閱讀擴充（KF8/CBZ/TXT/MD）：Issue 追蹤

## Issue 1：Spike——`mobi.js`／`comic-book.js`（`readest/foliate-js` 釘定 commit）能否正確開啟 KF8 (AZW3) 與 CBZ，KF8 DRM 位元組偵測可行性驗證

**Status:** `completed`（2026-08-16，GO——完整證據見 `reviews/spike-issue1-kf8-cbz-drm.md`）。

**判準分類：**
| 驗證項目 | 結果 |
|---|---|
| KF8 開書/渲染/導覽 | 通過 ✓ |
| KF8 × 直排覆蓋組合性 | 通過 ✓ |
| CBZ 開書/渲染（`pre-paginated`） | 通過 ✓ |
| CBZ 零填補頁序 | 正確 ✓ |
| CBZ 非零填補頁序 | 錯誤（預期）— 字典序排序 |
| CBZ RTL 覆蓋可行性 | 可行 ✓（僅驗證 `book.dir` 覆寫傳遞，導覽方向未驗證，見下方待落實事項 #2） |
| DRM 位元組偵測可行性 | 可行 ✓ |

**Architecting 階段待落實事項：**
1. CBZ 自然排序：需在匯入管線（Dart 端）對 CBZ 內部圖片檔名做自然排序後重新命名/重建索引
2. CBZ RTL 覆寫：需在 `main.js` 整合層依使用者偏好（PRD FR-43）於 `makeComicBook()` 之後設定 `book.dir`，**並確認 `goLeft()`/`goRight()`（或本專案既有 3×3 熱區 `ZoneAction` 分派邏輯）在 `book.dir='rtl'` 時實際回傳正確的翻頁方向**——Spike 的 Harness 熱區按鈕硬編碼呼叫 `view.prev()`/`view.next()`，並未走 `view.js` 真正處理 RTL 語意的 `goLeft()`/`goRight()`，只驗證了 `book.dir` 覆寫值能正確傳遞到 `view.book.dir`，尚未驗證使用者實際點擊熱區時 RTL 模式下翻頁方向是否正確（見 `reviews/review-issue-1-spike-execution.md` Important #1），此點在 Architecting／Issue 實作階段仍需補測
3. KF8 DRM 偵測：Dart 端直接採用 Task 5 驗證過的 offset（`ByteData.getUint16(record0Offset + 12, Endian.big)`），偵測到非 0 即拋出 `DrmProtectedException`

**測試素材補充說明**：KF8 測試未使用真實繁中直排公版書，改用 Standard Ebooks 英文公版樣本（The Time Machine）＋ CSS `transformTarget` 覆蓋模擬直排——理由是 KF8 特有風險在於容器解析（`mobi.js`），CJK 直排排版品質已由 `epic-17`/`epic-20` 用真實中文書證實、與格式來源無關，見 `plan-issue-1.md` Task 3「背景說明」。

**依賴：** 無（起始工單）。

**背景：** 見 `design.md`「Issue 1：前置驗證 Spike」。已用 GitHub API 查證本專案釘定的 `readest/foliate-js` commit（`dd71f2be356563c16a23272686189fcfb45d0b82`）確實包含 `mobi.js`／`comic-book.js`／`vendor/fflate.js` 三個檔案（production `app/android/app/src/main/assets/foliate/` 目前僅 vendor 既有 EPUB 所需的 10 個檔案，尚未包含這三個）。已逐一讀取這三個檔案原始碼，確認以下技術事實（供 Task 撰寫依據，非憑空假設）：
- `view.js` 的 `makeBook(file)` 對 KF8/MOBI／CBZ 皆為**全自動格式偵測**（KF8/MOBI 靠 magic bytes `file.slice(60,68) === 'BOOKMOBI'`，CBZ 靠副檔名/MIME `isCBZ()`），呼叫端不需要自己判斷格式。
- `mobi.js` 的 `MOBI` class 有自己獨立的 `transformTarget = new EventTarget()`（與 `epub.js` 同一機制），代表 `epic-17` Issue 1 已驗證過的「CSS 資源解析前注入 `writing-mode: vertical-rl`」技術應同樣適用於 KF8 內容。
- `comic-book.js` 的 `makeComicBook()` 對圖片檔名用**純字典序 `.sort()`**，**不是自然排序**（`design.md`/研究報告原先假設的「自然排序」並非 `comic-book.js` 內建能力）——若 CBZ 內部圖片檔名未零填補（例如 `1.jpg`…`10.jpg` 而非 `01.jpg`…`10.jpg`），頁序會出錯。
- `comic-book.js` 回傳的 `book` 物件**未設定 `book.dir`**，而 `fixed-layout.js` 的 RTL 判定完全依賴 `book.dir === 'rtl'`——代表 CBZ **沒有**任何內建/自動的 RTL 偵測，翻頁方向必須由呼叫端（我們的 `main.js`）在 `makeComicBook()` 之後、`view.open(book)` 之前手動設定 `book.dir`，不存在「讀取 CBZ 檔案本身判斷出這是日漫」這種機制。
- `mobi.js` 的 `PALMDOC_HEADER.encryption` 欄位位於 MOBI record 0 的 offset 12（2 bytes，`DataView` 未指定 `littleEndian` 引數，故為 **big-endian**），對照公開的 PalmDOC/MOBI 格式規格（0=無加密／1=舊版 Mobipocket 加密／2=Mobipocket 加密），`mobi.js` 本身**不會**因此欄位非 0 而拒絕開啟——DRM 偵測必須是我們自己獨立實作的檢查，不能依賴 `mobi.js` 拋出的例外。

**驗證範圍：**

1. **KF8 開書/渲染/導覽**：以 Standard Ebooks 提供的真實、DRM-free、公版授權 AZW3 檔案（已驗證下載連結有效，見 `plans/plan-issue-1.md` Task 2）驗證 `makeBook()` 能正確自動分派至 `mobi.js`、開書成功、`relocate` 事件正確觸發、`view.next()`/`view.prev()` 內容連續無跳過/重複（比照 `epic-17` Issue 1 判準）。
2. **KF8 × 直排 CSS 覆蓋組合性**：對 KF8 來源內容套用與 `epic-17` Issue 1 完全相同的 `transformTarget` 直排覆蓋技術，驗證能正確生效——目的是驗證「KF8 内容能否正確composed進已證實可用的直排管線」，**不是**重新驗證中文直排排版品質本身（該品質已由 `epic-17`/`epic-20` 用真實中文書籍證實，`paginator.js` 本身未因格式來源不同而有差異）。
3. **CBZ 開書/渲染/頁序**：以兩份自製 CBZ（零填補檔名 `001.jpg`…`010.jpg` 與非零填補 `1.jpg`…`10.jpg`）驗證實際頁面顯示順序，確認/推翻「純字典序排序在未零填補情境下會出錯」的既有查證結論；驗證 `book.rendition.layout === 'pre-paginated'` 確實觸發 `fixed-layout.js` 渲染路徑。
4. **CBZ RTL 覆蓋可行性**：驗證在 `makeComicBook()` 之後手動設定 `book.dir = 'rtl'`（模擬未來 `main.js` 依使用者偏好覆寫）能讓 `fixed-layout.js` 正確採用 RTL 翻頁行為。
5. **KF8 DRM 位元組偵測可行性**：以 Python 建構兩份合成的最小 PDB/MOBI 位元組緩衝區（`encryption=0` 與 `encryption=2`，**非真實/非受版權保護的書籍內容**，純粹是符合 PDB 標頭規格的最小可解析結構），驗證依 `mobi.js` 原始碼查證得出的 offset 邏輯（PDB header → 首筆 record offset → `+12` 兩位元組大端序）能正確且穩定地區分兩者。本項僅驗證位元組解析邏輯的可行性，**不驗證真實 Kindle DRM 檔案的端到端行為**（無法合法取得真實受 DRM 保護的樣本），正式 Dart 實作與真實檔案的端到端驗證留待 Architecting／後續 QA 階段。

**明確不在本 Issue 範圍**：完整遷移架構設計（`FoliateEpubReaderView` → `FoliateReaderView` 泛化重構、`Book.isFixedLayout`/`BookFileFormat` schema migration、TXT/MD 合成書籍結構匯入管線、`main.js` 正式整合 KF8/CBZ 分派邏輯）——這些留待 GO 之後的 Architecting 階段（`spec.md`）。

**GO/NO-GO 決策路徑：**
- **GO**（驗證範圍 1-4 全數通過；驗證範圍 5 的位元組解析邏輯驗證通過即可，不要求真實 DRM 檔案端到端驗證）：記錄結果，進入 Architecting 階段，`design.md`「GO 後續步驟」段落所列工作項目正式排入 Scrum Master 拆解。
- **NO-GO**（KF8 或 CBZ 開書/渲染核心判準任一失敗）：記錄具體失敗證據與根因，評估是否降級為「僅 CBZ 上線、KF8 另尋替代解析路徑」的縮小範圍方案（`design.md`「NO-GO」段落）。

**單元測試要求：** 無（研究/驗證性質，比照 `epic-17`/`epic-20` Issue 1 先例）。過程中產生的 harness 專案與素材（截圖/log/合成測試檔）驗證後需清理，不進版控（放 `tmp/`，已 gitignore）。

**驗收標準：**
- 真機以真實 KF8 樣本與自製 CBZ 樣本驗證，明確記錄各驗證項目的通過/失敗判定與依據（截圖或 log 佐證）。
- 明確記錄 CBZ 排序行為與 RTL 覆蓋可行性的實測結論（不論結果是否符合預期假設）。
- 依結果更新 `design.md`／本檔案對應狀態。

**相關佐證：**
- `docs/epics/epic-11-multi-format-reader/design.md`「問題陳述」「Issue 1：前置驗證 Spike」
- `docs/archive/2026-07-24-epic-17-epub-render-migration/plans/plan-issue-1.md`（Spike harness 既有先例，方法論參考，`transformTarget` 直排覆蓋技術原始出處）
- `app/android/app/src/main/assets/foliate/`（現有已 vendor 之 10 個檔案，本 Issue 新增 `mobi.js`／`comic-book.js`／`vendor/fflate.js` 三個）
- Readest `foliate-js` fork（`https://github.com/readest/foliate-js`），釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`：`view.js`（格式分派邏輯）、`mobi.js`（PALMDOC_HEADER／transformTarget）、`comic-book.js`（排序/RTL 行為）、`fixed-layout.js`（`book.dir` RTL 讀取點）
