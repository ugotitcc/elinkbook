# Epic 11 — 多格式閱讀擴充（KF8/CBZ/TXT/MD）：設計 (Design)

> 本文件由 `/grill-with-docs` 2026-08-16 逐項確認產生。原 `epic-11-txt-engine`（TXT 直排引擎，Backlog，未開始 Discovery）於本次評估後改弦更張並擴大範圍，見 `docs/epics.md` 條目說明。

## 問題陳述

`docs/prd.md` FR-01 現行僅列 ePub3/PDF/TXT 為 P0 格式。人類提供外部研究報告《elinkBook 全格式閱讀擴充綜合研究報告》（`docs/research/comprehensive_format_expansion_research.md`），評估將支援格式擴充至 KF8 (AZW3)、CBZ、TXT、MD、MOBI、FB2 六種。報告核心論點：除 PDF 外的所有格式皆可透過既有 `readest/foliate-js`（釘定 commit）管線渲染——EPUB／KF8 原生為 HTML/CSS 衍生格式；CBZ 為圖像 ZIP，可用 `comic-book.js` 解出圖片序列後走既有的 `fixed-layout.js`（`epic-20-fxl-foliate-migration` 已為 EPUB FXL 引入並打磨過雙頁/RTL/封面獨立顯示）；TXT／MD 可預處理為 XHTML 相容結構後直接餵入既有 `paginator.js`。

這與現行 `epic-11-txt-engine` 原案（TXT 自建一套獨立的輕量直排 CJK 排版引擎，明確排除 WebView/Readium）直接衝突。`/grill-with-docs`（`/grilling` + `/domain-modeling`）逐項確認後，正式推翻 `epic-11` 原案，改採本文件記錄的方案；核心架構決策已同步記錄於 **`docs/adr/0023-multi-format-foliate-pipeline-txt-route-reversal.md`**（本次 Discovery 因議題高度集中且與既有 `epic-17`/`epic-20` 的成熟先例強相關，Discovery 與部分 Architecting 決策於同一次 `/grill-with-docs` 會談中一併產出，比照 `epic-20` 先例——見其 `design.md` 「Architecting 決策紀錄」與 Discovery 同檔並存的既有寫法）。PRD 已同步修訂：新增 **FR-43**（P1），並擴充 FR-05/06/07/27/41 之格式清單（見 `docs/prd.md` 2026-08-16 editHistory）。

## 範圍界定

### 包含範圍

- **格式**：KF8 (AZW3)、CBZ (漫畫壓縮檔)、TXT、Markdown (MD)。TXT 維持 FR-01 既有 P0 定位（僅技術路線變更）；KF8/CBZ/MD 為新增 P1（FR-43）。
- **KF8／CBZ**：泛化 `FoliateEpubReaderView` → `FoliateReaderView`；vendor 對應解析資產（`mobi.js`/`fflate.js` 供 KF8，`comic-book.js` 供 CBZ，實際檔案清單待 Issue 1 Spike 查證）；KF8 走既有 EPUB 相容路徑（直排/避頭尾/CFI/劃線/書籤/目錄/同步全數繼承）；CBZ 復用既有 `isFixedLayout=true` 分派路徑與 `FxlSettingsSheet`（`epic-20` 產物），新增翻頁方向切換（RTL/LTR）。**KF8 DRM 偵測須於純 Dart metadata 擷取階段（讀取 PDB header／EXTH record 406 加密旗標）完成，偵測到即拋出專用例外（例如 `DrmProtectedException`）中止該書匯入、不寫入 `Book` 記錄**——比照 `book_import_service_impl.dart:270-274` 現有「單本 metadata 擷取失敗（`PlatformException`）不中斷整批匯入、降級處理」的批次容錯慣例，但 DRM 屬於「明確不支援、不該讓使用者以為匯入成功」的情況，不可比照降級為「無封面/檔名為標題」繼續建立書籍記錄。
- **TXT／MD**：匯入時落地轉換為「合成書籍結構」（EPUB/XHTML 相容，衍生檔案存於 App 私有目錄，`Book.filePath` 改指向），恆為流式（`isFixedLayout = false`）；MD 需解析 YAML Frontmatter（標題/作者/封面）與標題階層生成目錄；TXT 需 Big5 優先梯隊的編碼偵測（純 Dart 自建對照表，不依賴原生 platform channel）與章節正則 TOC 抽取。**TXT 預處理器須具備雙重分塊防護**：優先依正則 TOC 切分章節，若無 TOC 或單一章節超過閾值（建議 300~500KB）須再依段落邊界次級分塊，避免單一巨大 XHTML section 造成 WebView DOM 節點過大／記憶體暴增（常見於缺乏規範章節標記的網路小說 TXT）。**`contentFingerprint` 必須對「原始輸入檔案」計算，且此計算須早於／獨立於合成轉換步驟**——`book_content_fingerprint.dart` 現行 `computeBookContentFingerprint(filePath, ...)` 對傳入的 `filePath` 逐位元組雜湊，`book_import_service_impl.dart:279-283` 目前是用 `resolvedUri`（匯入當下的原始路徑）呼叫；Architecting 階段串接 TXT/MD 合成步驟時，**不可**讓 `resolvedUri`／傳入指紋計算的路徑先被覆寫成合成後的衍生檔案路徑，否則不同裝置/轉換器版本產出的合成檔案（zip 時間戳、內部檔案順序等非決定性因素）會讓 SHA-256 不一致，導致 `epic-8-sync` 的跨裝置「同一本書」比對失效。**合成檔案生命週期須納入既有刪除清理路徑**：比照 `library_screen.dart:422-436`（`coverPath` 於批次刪除書籍時以 `try`/`deleteSync()` 清理、單筆失敗不中斷批次迴圈、`content://` URI 因 `existsSync()` 恆為 `false` 天然免疫）的既有模式，TXT/MD 的合成檔案需在刪除書籍時一併清理，避免孤兒檔案殘留。
- **資料模型**：`Book.isFixedLayout` 欄位語意由「EPUB 專屬」廣義化為跨格式旗標（EPUB/KF8 依 metadata、CBZ 恆 `true`、TXT/MD 合成後恆 `false`、PDF 恆 `null`）；`BookFileFormat`（`library_enums.dart`）新增列舉值，命名依現有慣例採副檔名（`azw3`，非 `kf8`——`epub`/`pdf`/`txt` 皆以副檔名命名，非格式正式名稱），並確認 SQLite `books.format` 字串儲存與既有升級測試涵蓋新值。`Book.epubLocator` 欄位（現有 doc 註解仍描述為「EPUB 序列化後的 Readium Locator」，實際上自 ADR 0011/0017 起已是 Foliate CFI/Locator JSON——此為與本 Epic 無關的既有文件落差，不在本次修正範圍）語意隨 KF8/TXT/MD 加入將進一步廣義化為「Foliate 閱讀位置」；Architecting 階段僅需更新註解說明，**不需要**欄位改名或 SQLite 搬遷。CBZ 的目錄／進度回報格式（頁碼虛擬目錄？百分比？）待 Architecting 階段確認，`fixed-layout.js` 既有機制是否可直接複用需查證。
- **Metadata／封面擷取**：新格式一律純 Dart 實作（`archive`＋`xml`＋自建 Big5 對照表），不引入原生 platform channel 依賴；EPUB 既有 Readium 路徑不動。

### 明確排除

- **MOBI／FB2**：經評估後排除，列為未來獨立 Backlog 項目，不在本 Epic 開 Issue。
- **Readium 完全退場**（`BookMetadataChannel.kt` 遷移純 Dart）：與新格式上線無必要關聯，另立獨立技術債 Epic，不併入本次範圍。
- **CBZ 劃線／備註**：比照既有 FXL 圖像無文字節點的既定限制，不支援。
- **PRD 未涵蓋之驗收門檻**：CBZ 不適用「零排版缺陷」，改用「圖片正確顯示＋翻頁方向正確」（PRD 成功準則 #6）。

## 決策紀錄（Discovery 逐項確認，`/grill-with-docs` Q1-Q18）

| # | 決策點 | 採用結果 |
|---|---|---|
| 1 | PRD 是否需先修訂 | 是，先修訂 `docs/prd.md`（FR-01/05/06/07/27/41/43、成功準則 #6），已完成 |
| 2 | Epic 編號與 `epic-11-txt-engine` 定位 | 沿用 `epic-11`，slug 重新命名為 `epic-11-multi-format-reader`；原案作廢並吸收進本 Epic |
| 3 | 最終格式範圍 | KF8/CBZ/TXT/MD 四種；MOBI/FB2 排除，列未來 Backlog |
| 4 | TXT 技術路線 | 改採 Foliate 管線，推翻原「自訂輕量排版引擎」案（ADR 0023 核心決策） |
| 5 | Readium 退場是否併入 | 否，另立獨立技術債 Epic |
| 6 | `epic-11` slug 最終命名 | `epic-11-multi-format-reader` |
| 7 | `FoliateEpubReaderView` 是否泛化改名 | 是，改名 `FoliateReaderView`，`CLAUDE.md` 同步更新（Architecting 階段執行） |
| 8 | `BookFormat`／`BookFileFormat` 是否整併 | 否，兩個 enum 各自維持完整列舉值；`book_format.dart` 內部分派邏輯簡化為 pdf/foliate 二元判斷 |
| 9 | TXT/MD 轉換時機 | 匯入時落地轉換為合成書籍結構，`Book.filePath` 指向衍生檔案（比照 `coverPath` 既有慣例） |
| 10 | CBZ 設定面板 | 復用/擴充既有 `FxlSettingsSheet`，不另建獨立面板 |
| 11 | 解析套件路線 | 純 Dart only（`archive`＋`xml`＋自建 Big5 對照表），不引入原生 platform channel 依賴 |
| 12 | Issue 順序 | KF8+CBZ 先（低風險驗證泛化管線），TXT+MD 後（需新寫 Dart 預處理器） |
| 13 | 測試 fixture 來源 | 由執行方準備（公版書籍轉檔／手工組裝最小合法檔案） |
| 14 | PRD 優先級與驗收門檻 | 新格式 P1；CBZ 驗收門檻與「零排版缺陷」脫鉤，改為「圖片正確顯示＋翻頁方向正確」 |
| 15 | KF8 DRM 偵測 | 納入範圍：解析 PDB/EXTH 加密旗標，偵測到即顯示友善錯誤訊息，不嘗試解密 |
| 16 | CBZ 是否需新 PRD FR | 否，延伸既有 FXL 相關 FR（FR-41）格式清單 |
| 17 | `isFixedLayout` 欄位語意範圍 | 廣義化為跨格式通用旗標（選項 A，見「範圍界定」與 ADR 0023） |
| 18 | （同上，`isFixedLayout`）確認 | 選項 A 拍板 |

完整問答脈絡見本 Epic 對應之 `/grill-with-docs` 對話記錄；核心架構決策的理由、替代方案、後果見 `docs/adr/0023-multi-format-foliate-pipeline-txt-route-reversal.md`。

## Issue 1：前置驗證 Spike（建議，待 Architecting 階段拍板細節）

比照 `epic-17-epub-render-migration` Issue 1／`epic-20-fxl-foliate-migration` Issue 1 先例——本 Epic 雖已在 Discovery 階段完成大量架構決策，但**兩個具體技術環節尚無 production 證據**：(1) `mobi.js`／`fflate.js`（KF8 解析）是否確實存在於本專案已釘定的 `readest/foliate-js` commit（`dd71f2be356563c16a23272686189fcfb45d0b82`）且可正確解出 PDB/EXTH 容器內的 HTML sections 與封面；(2) `comic-book.js`（CBZ 解析）是否能正確處理自然排序與大尺寸圖片。這兩者風險程度遠低於 `epic-17`/`epic-20` 當初面對的「CJK 直排分頁完全失效」等級問題（Foliate 的直排/CFI/劃線機制本身已 production 驗證兩年），但仍屬於「未經本專案實際驗證的第三方 vendor 資產整合」，故建議沿用本專案一貫的 Spike-first 風險管理慣例，不直接跳過驗證進入多 Issue 平行實作。

**驗證項目（待 Architecting 階段正式化為判準表）**：
- 確認 upstream `readest/foliate-js` 釘定 commit 是否含 `mobi.js`／`fflate.js`（或相容解壓模組）／`comic-book.js`（若缺漏需評估升版影響範圍，比照 `epic-20` Issue 1 對 `fixed-layout.js` 的查證方法）。
- 以至少一本真實 KF8 (AZW3) 繁中直排公版書驗證：開書成功、標點避頭尾與注音/旁註正確、字型放大縮小正常。
- 以一份自製 CBZ 驗證：自然排序正確（`1.jpg, 2.jpg ... 10.jpg` 非字典序）、RTL 右翻模式正常。
- KF8 DRM 偵測：以一份加密 AZW3 樣本驗證 Dart 端偵測準確度（不產生未捕獲例外／崩潰），友善錯誤訊息正確觸發、不嘗試解密。

**GO** 後續步驟：進入完整 Architecting（`spec.md`，含 `FoliateReaderView` 泛化介面、`Book.isFixedLayout`/`BookFileFormat` schema migration、合成書籍結構的匯入管線介面）與 Scrum Master 拆解（TXT/MD 預處理器另立後續 Issue，比照決策 #12 順序）。
**NO-GO**（例如 vendor 資產缺漏且升版風險過高）：記錄理由，評估是否降級為「僅 CBZ 上線、KF8 另尋替代解析路徑」的縮小範圍方案。

> **Spike 結果（2026-08-16）：GO**——完整證據見 `reviews/spike-issue1-kf8-cbz-drm.md`。下一步進入完整 Architecting 階段。

## 審查回應（`reviews/review-design.md`，2026-08-16，結論 APPROVED）

審查結論為核准通過，4 項 Important／3 項 Minor 皆為「Architecting 階段落實建議」而非阻擋 Discovery 成立的缺陷。逐項查證後全數採納並已併入上方「包含範圍」：

| 項目 | 查證結果 | 處置 |
|---|---|---|
| Important #1 內容指紋確定性 | 查證 `book_content_fingerprint.dart`／`book_import_service_impl.dart:279-283`：`computeBookContentFingerprint` 對傳入路徑逐位元組雜湊，現行呼叫用的是匯入當下的原始 `resolvedUri`。合成轉換步驟接上後若未刻意保序，確有可能誤用合成後路徑計算指紋——**發現屬實**，已於「TXT／MD」條目補上明確順序規定 |
| Important #2 合成檔案生命週期 | 查證 `library_screen.dart:422-436`：`coverPath` 清理**不在** `SqliteLibraryRepository.deleteBook()`（僅刪 DB 列），而在 `LibraryScreen` 批次刪除流程另外以 `try`/`deleteSync()` 處理——**審查報告「比照 coverPath 檔案清理流程」的既有慣例本身查證屬實，但流程位置需訂正**（非 repository 層），已於條目中註明正確位置與既有防禦模式（單筆失敗不中斷批次、`content://` URI 天然免疫） |
| Important #3 TXT 分塊防護 | 與外部研究報告既有的「Fallback 字數切片」建議一致，design.md 原文遺漏此細節——已補上雙重分塊防護規則 |
| Important #4 DRM 攔截位置 | 與 ADR 0023 決策 6 方向一致，design.md 原文未明確「中止匯入、不寫入 Book 記錄」這個關鍵行為——已補上專用例外與批次容錯慣例對照 |
| Minor #1 `epubLocator` 語意 | 查證屬實，且發現該欄位現有 doc 註解本身已因 ADR 0011/0017（Readium Locator → Foliate CFI）而過時，此為**與本 Epic 無關的既有文件落差**，不在本次修正範圍——已註明廣義化方向與範圍界線（不改欄位名/不搬遷 schema） |
| Minor #2 CBZ TOC／進度回報 | 合理的開放問題，已列入「資料模型」條目末尾，留待 Architecting 階段確認 |
| Minor #3 `BookFileFormat` 命名 | 已於「資料模型」條目明確拍板採 `azw3`（依現有副檔名命名慣例，非 `kf8`），並註明需確認 schema 升級測試涵蓋 |

## 相關佐證

- `docs/research/comprehensive_format_expansion_research.md`（外部研究報告，本次 Discovery 的技術輸入）
- `docs/adr/0023-multi-format-foliate-pipeline-txt-route-reversal.md`（核心架構決策）
- `docs/adr/0011-epub-reflowable-migrate-to-foliate-js.md`／`0017-fxl-migrate-to-foliate-js.md`（Foliate 管線既有成熟度先例）
- `docs/archive/2026-07-24-epic-17-epub-render-migration/`／`docs/archive/2026-08-02-epic-20-fxl-foliate-migration/`（Spike-first 方法論比照對象）
- `CONTEXT.md`「固定版面（Fixed-Layout, FXL）」「Foliate 格式」「合成書籍結構」詞條
- `docs/prd.md` FR-01/05/06/07/27/41/43，成功準則 #6，2026-08-16 editHistory
- `app/android/app/src/main/assets/foliate/`（現有已 vendor 資產清單，Issue 1 查證基準）
- `reviews/review-design.md`（本文件設計審查報告，2026-08-16，APPROVED with Recommendations）
- `app/lib/library/book_content_fingerprint.dart`／`app/lib/library/book_import_service_impl.dart:244-301`（內容指紋計算與匯入流程現況查證，審查回應 Important #1）
- `app/lib/screens/library_screen.dart:418-441`（`coverPath` 刪除清理既有模式，審查回應 Important #2）
