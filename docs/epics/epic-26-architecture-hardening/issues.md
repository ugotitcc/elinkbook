# Epic 26 — 架構深化機會：工單清單 (Issues)

依 `docs/research/architecture-review-test-suite-epub-pdf.md`（2026-08-11，`/improve-codebase-architecture` 流程產出，7 個候選深化機會）逐項評估後立案。候選 1 經 `/diagnose` 確認為現存 bug並拆為 Issue 1（已修復並合併）；候選 2 經 `/diagnose` 深入查證後拆為 Issue 2（安全的機械式收斂，`ready-for-agent`）與 Issue 3（需真機診斷才能定案的門檻值問題，`needs-info`，見 Issue 3 說明「為何不能直接沿用 Issue 2 的收斂結果」）；候選 6 拆為 Issue 4（已完成並合併）；候選 4 於 2026-08-20 `/zoom-out` 深挖後拆為 Issue 5（人類已決策採選項 A 整批除役，`ready-for-agent`）；其餘候選（3 同類但影響較小、5/7 需要先決策或範圍較大）尚未拆案，視後續優先順序決定是否納入本 Epic。

---

## Issue 1：流式 EPUB 書籤 toggle 快取未載入時，第一次點擊誤判無書籤而重複新增

**Status:** ✅ 已修復。新增純 Dart 共用 module `app/lib/reader/bookmark_toggle.dart`（`toggleBookmark()`，`matches`/`build` 參數化），EPUB `_toggleBookmark()`／PDF `_togglePdfBookmark()` 皆改為呼叫此 module、存在性判斷一律直查 `BookmarksRepository`，不再依賴可能尚未載入的 `_fxlBookmarks` 快取。`bookmark_toggle_test.dart`（3 項純邏輯單元測試）＋ `reader_screen_test.dart` 新增的永久回歸測試（重現「重開已加書籤的流式 EPUB、未開過筆記面板時第一次點擊誤新增重複書籤」symptom，修復後轉為不再誤觸發）皆通過；既有 EPUB／PDF 書籤 toggle 測試零回歸；`flutter analyze` 乾淨。

**依賴：** 無

**來源：** `docs/research/architecture-review-test-suite-epub-pdf.md` 候選 1（強度 Strong，「現存 bug，非假設性風險」）。診斷過程與重現測試詳見 `reviews/bugfix-repro.md`。

**背景／症狀：** 使用者重新開啟一本先前已在目前位置加過書籤的**流式（reflowable）EPUB**，在本次閱讀 session 尚未打開過筆記面板（NotesBottomSheet）的情況下，第一次點擊浮動書籤 toggle 按鈕（星星圖示），預期應是「刪除既有書籤」，實際卻是「新增一筆重複書籤」——同一位置最終出現 2 筆書籤記錄。

**根因（已用原始碼交叉核對＋widget test 重現確認，非臆測）：**

`_toggleBookmark()`（`app/lib/screens/reader_screen.dart:736`）用 `_bookmarkAtCurrentPosition` getter（`:714`）判斷目前頁是否已有書籤，該 getter 只讀記憶體快取 `_fxlBookmarks`（初始值 `[]`），不查 repository。EPUB 開書流程中沒有任何一處會在使用者**第一次點擊書籤按鈕之前**把既有書籤預先載入這個快取：

- `_loadFxlBookmarks()`（`:680`）只在以下時機被呼叫：`_toggleBookmark()`／`_togglePdfBookmark()` 自己執行完 insert/delete **之後**（`:755`、`:786`，用來刷新 UI，不影響本次判斷）；Notes 面板關閉時（`:1002`），但條件是 `_isFixedLayout || format == BookFormat.pdf`——**純流式（非 FXL）EPUB 被排除在外**；PDF 開書流程（`:1040`，`epic-24-pdf-engine-rebuild` Issue 8 補上的預先載入），**EPUB 沒有對應呼叫**。
- 對照 PDF 端：`_togglePdfBookmark()`（`:762-787`）明確不依賴 `_fxlBookmarks`，改為直接 `await repository.listByBook(widget.bookId)` 查詢，程式碼註解記載這正是為了「避免快取尚未載入時導致重複新增」（`epic-24-pdf-engine-rebuild` 該工單已修過的同一類 bug）。EPUB 端的 `_toggleBookmark()` 從未收到這個修復。

**驗證（已用 widget test 重現，見 `reviews/bugfix-repro.md`）**：預先在 `FakeBookmarksRepository` 塞入一筆與即將回報的 `locatorJson` 完全相同的書籤，模擬「重開已加過書籤的書」，不開 Notes 面板、直接點擊書籤 toggle 按鈕一次——結果 repository 從 1 筆變成 2 筆（應為 0 筆，因為預期行為是刪除既有書籤），確認重現。

**Solution（比照架構檢視報告候選 1 的建議方向）：** 抽出一個共用 module（`bool Function(Bookmark) matches` / `Bookmark Function() build` 參數化「查 repository → 比對 → insert/delete → reload」），`_toggleBookmark()`／`_togglePdfBookmark()` 皆改用此 module、直接查 repository 而非依賴 `_fxlBookmarks` 快取判斷存在性；EPUB 傳入 `epubLocatorJson` 比對邏輯、PDF 傳入 `pdfPageIndex` 比對邏輯。`_fxlBookmarks` 快取本身可繼續保留供 UI 顯示用（星星圖示狀態、Notes 面板書籤分頁），只是不再用它做 toggle 當下的存在性判斷。

**單元測試要求：**
- 把 `reviews/bugfix-repro.md` 的重現測試轉為永久回歸測試（流式 EPUB，開書後未開過 Notes 面板、目前位置已有書籤，第一次點擊 toggle 應刪除該書籤、repository 剩 0 筆、圖示變回 `star_border`）。
- 既有測試（`reader_screen_test.dart` line 3681 起「點擊浮動書籤 toggle 按鈕可新增/移除目前頁書籤」、PDF 對應測試）須繼續全數通過，確認重構未破壞既有行為。
- 確認 EPUB／PDF 兩邊呼叫共用 module 後，其中一邊修過的競態測試對另一邊同樣有效（可比照候選 1 文件的「刪除測試」精神：把其中一份 adapter 實作刪掉、改呼叫共用 module，行為不變）。

**驗收標準：** 流式 EPUB 重開已加過書籤的書、未開過 Notes 面板時，第一次點擊書籤按鈕正確判斷為「刪除」而非「新增」；EPUB／PDF 書籤 toggle 邏輯收斂為同一個共用 module；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 2：收斂 nav-zone 熱區點擊偵測成一個共用 module（補上 EPUB 缺少的 `onPointerCancel`）

**Status:** ✅ 已修復。新增共用 `app/lib/reader/tap_zone_detector.dart`（`TapZoneDetector`，`nowMs`/`tapMaxDurationMs`/`tapSlop` 皆為呼叫端注入參數，內建 `onPointerCancel` 防禦性清理），EPUB `_NavZoneTapDetector`／PDF `_PdfNavZoneTapDetector` 兩份私有實作整段刪除、呼叫端皆改用此共用 module，各自維持現行數值不變（EPUB 700ms／PDF 400ms，皆 18.0 slop）。EPUB 端新增 `onPointerCancel` 特徵測試鎖定新行為（原本缺少此保護；誠實記錄：單指循序操作情境本來就會因狀態欄位被下一次合法按下覆寫而自我修復，此測試不是重現一個先前可觀察的 bug，價值在於防止未來重構時意外移除這層防禦），PDF 端既有 600ms 排除測試與 `onPointerCancel` 測試皆不需修改斷言即全數通過，證明收斂後兩邊行為零改變。`tap_zone_detector_test.dart`（4 項純邏輯單元測試）＋`flutter test` 全量通過、`flutter analyze` 乾淨。`_tapMaxDurationMs` 數值本身是否需要調整見 Issue 3（獨立範圍，不受本次收斂影響）。

**依賴：** 無（與 Issue 3 互相獨立，`_tapMaxDurationMs` 的實際數值本身不在本 Issue 變更範圍內，見下方）。

**來源：** `docs/research/architecture-review-test-suite-epub-pdf.md` 候選 2（強度 Strong）。

**背景／症狀：** `app/lib/reader/foliate_epub_reader_view.dart` 的 `_NavZoneTapDetectorState`（`:875-918`）與 `app/lib/reader/pdf_reader_view.dart` 的 `_PdfNavZoneTapDetectorState`（`:1235-1276`）是兩份「刻意各自獨立實作」（見 PDF 端 class doc 註解）、邏輯逐字幾乎相同的九宮格熱區點擊偵測器：皆用 `Listener`（不參與手勢競技場）觀察 `onPointerDown`/`onPointerUp`，以「耗時 `≤ _tapMaxDurationMs` 且位移 `≤ _tapSlop`」判定是否為一次快速點擊。查證目前程式碼（非文件既有描述，屬本次 `/diagnose` 新查證結果）發現兩者實際上**已經產生分歧**：PDF 端有 `onPointerCancel` 處理（`:1269-1272`，清除暫存的 `_downPosition`/`_downTimeStampMs`，避免殘留舊值），EPUB 端**完全沒有**對應處理（`onPointerDown`/`onPointerUp` 是僅有的兩個 handler）。

**根因（已用原始碼交叉核對確認）：**

`_PdfNavZoneTapDetectorState` 的 `onPointerCancel` 是先前一輪獨立審查（原始碼註解明確引用「審查意見 Minor 1」）新增的防禦性清理，理由是「系統層級手勢中斷（例如滑出螢幕邊緣觸發 OS 系統手勢）會送出 `PointerCancelEvent` 而非 `PointerUpEvent`，須主動清除暫存狀態，避免殘留舊值」。這個審查意見從未回頭套用到 `_NavZoneTapDetectorState`（EPUB 端）——兩份實作本來就是各自獨立維護（見 Global Constraints），一邊的審查發現天生不會自動同步到另一邊，這正是候選 2 文件描述的核心問題（「已經各自被 review 抓到過幾乎一樣的 bug」）的具體實例。

**風險評估（誠實記錄，非誇大）：** 已追蹤 `_downPosition`/`_downTimeMs` 皆為單一（非依 pointer id 區分的）欄位，下一次合法的 `onPointerDown` 會直接覆寫這兩個欄位——單一手指循序操作（放開/取消→下一次按下）的情況下，殘留的舊值會在下一次合法按下時被覆寫，不會造成永久性誤判，屬於自我修復類別（比照 `epic-25` Issue 4 review Minor #1 對 `annotationClickTouchStartTime` 的相同定性）。真正有風險的情境是**同一個熱區格子被兩個 pointer 幾乎同時觸碰**（例如另一手指在操作別處手勢時無意間掃過同一格熱區）——由於狀態不分 pointer id，後到的 `onPointerDown` 會覆寫先到的按壓時間，可能讓原本一次持續中的長按被誤判成剛按下、進而在原按壓手指放開時用錯誤的 elapsed 時間計算——**但此風險 EPUB／PDF 兩者現況皆存在**（狀態欄位本來就不分 pointer id，`onPointerCancel` 補的只是 cancel 事件的清理，不解決多指狀態覆寫問題），不屬於本次候選 2／Issue 2 的範圍，記錄於此供未來參考，不在本 Issue 修復。

**Solution（比照架構檢視報告候選 2 的建議方向，並依本次查證結果調整範圍）：** 抽出共用 `TapZoneDetector` module，`Listener` 的 `onPointerDown`/`onPointerUp`/`onPointerCancel`（**新增，兩邊共用同一份**）由 module 統一實作；「計時來源」（`nowMs: int Function()`，EPUB 傳入 `() => DateTime.now().millisecondsSinceEpoch`、PDF 傳入 `() => clock.now().millisecondsSinceEpoch`）維持候選 2 文件建議的注入參數設計。

**刻意排除的範圍（本次 `/diagnose` 新查證發現，比計畫階段原始候選 2 文件更嚴謹）：** `_tapMaxDurationMs`／`_tapSlop` **不收斂成共用常數，維持各自呼叫端注入的參數**（例如 `tapMaxDurationMs: 700` / `tapMaxDurationMs: 400`）——查證目前程式碼發現 EPUB 現行值 700ms 是 `epic-25` Issue 1 經六輪真機診斷才校準出的結果，PDF 現行值 400ms 是原始未調校值；`pdf_reader_view_nav_zone_test.dart:126-155`（「按壓超過快速點擊時長判定門檻不觸發 onZoneAction，避免與長按選取手勢衝突」）以 600ms 按壓驗證「600ms 應被排除」，這項驗證在門檻值維持 400ms 時成立，若不經真機驗證就直接把此值改成 700ms，此既有測試按目前程式碼行為推算會反轉為「600ms 卻觸發」而失敗——是否應調整 PDF 門檻值本身是另一個獨立問題，見 **Issue 3**，本 Issue 刻意不處理，避免在沒有真機資料佐證的情況下貿然變更一個已被驗證測試鎖定的行為。

**單元測試要求：**
- 新增 EPUB 版本的 `onPointerCancel` 回歸測試，比照 `pdf_reader_view_nav_zone_test.dart:157-190`（「`onPointerCancel` 後清除按壓暫存狀態，取消手勢不觸發 onZoneAction，後續正常點擊仍正確判定」）的驗證精神，證明收斂後 EPUB 端也有這層保護（即使風險評估段落已說明此為低風險的防禦性收斂，仍需要測試鎖定新行為，避免未來重構時無聲移除）。
- 既有 EPUB／PDF nav-zone 測試（`foliate_epub_reader_view_test.dart`、`pdf_reader_view_nav_zone_test.dart` 全部既有案例，含上述提到的 600ms 排除測試）須繼續全數通過，逐一確認收斂後 `_tapMaxDurationMs`/`_tapSlop` 數值行為對兩邊分別維持不變（EPUB 仍是 700/18、PDF 仍是 400/18）。

**驗收標準：** EPUB／PDF 熱區點擊偵測邏輯收斂為同一個共用 module，`nowMs` 各自注入、`tapMaxDurationMs`/`tapSlop` 各自維持現行數值不變（不在本 Issue 內調整）；EPUB 端新增 `onPointerCancel` 保護並有對應測試鎖定；`flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。

---

## Issue 3：PDF 熱區快速點擊時長門檻（400ms）是否需要比照 EPUB Issue 1 重新真機診斷校準

**Status:** `needs-info`——需要真機資料才能定案，不可在缺乏真機驗證的情況下逕自把數值改成與 EPUB 相同（見下方「為何不能直接沿用」）；在拿到真機資料前不建議直接動手改值。

**依賴：** 建議待 Issue 2（module 收斂）完成後再進行本 Issue 的真機診斷，理由是 Issue 2 完成後兩邊的計時邏輯已收斂成同一份程式碼，届時真機診斷插樁只需要寫一次、兩邊共用（比照 Issue 2 module 抽出後「一次修復兩邊」的同一個 leverage 效益）；但若優先順序需要，也可以在 Issue 2 之前先對現行 `_PdfNavZoneTapDetectorState` 独立插樁診斷，無強制先後順序。

**來源：** `docs/research/architecture-review-test-suite-epub-pdf.md` 候選 2 的延伸發現——原文件描述「同一組常數（逐字相同）」，但本次 `/diagnose` 查證目前實際程式碼發現此描述已不成立（EPUB 700ms／PDF 400ms），此差異是本次診斷過程中新發現、原文件未預期到的問題。

**背景／症狀（尚未真機驗證，以下為根據既有 Issue 1 證據的合理推論，非確認結論）：** `epic-25` Issue 1 經六輪真機診斷（Air Reader Pro C／AiPaper Reader C）確認 EPUB 的 `_NavZoneTapDetector._tapMaxDurationMs` 原始值 400ms 會導致「使用者長按選字、原生選取辨識還來不及開始生效前放開手指」這個情境被熱區搶先判定成快速點擊而誤觸換頁，須調高（400→500→700ms）才能大幅減少此問題（詳見 `docs/epics/epic-25-annotation-interaction-qa/issues.md` Issue 1）。`_PdfNavZoneTapDetector` 是同一種 `Listener` 機制、同一個目的（避免熱區點擊與 PDF 長按拖曳框選畫線/備註手勢衝突，見 CLAUDE.md「`PdfReaderView`」小節），卻仍停留在未經校準的原始 400ms——PDF 使用者在長按拖曳建立劃線/備註標註時，理論上可能遭遇與 EPUB Issue 1 修復前相同類型的症狀（長按建立標註的手勢被熱區誤判成點擊、觸發換頁）。

**為何不能直接沿用 EPUB 校準出的 700ms（本次 `/diagnose` 查證發現，避免下一位讀者重新推導一次）：** 若假設「PDF 也應該是 700ms」並直接套用，`pdf_reader_view_nav_zone_test.dart:126-155` 既有測試（600ms 按壓應被排除、不觸發 `onZoneAction`）依目前程式碼邏輯（`elapsed <= _tapMaxDurationMs` 才觸發）會反轉為「600ms ≤ 700ms → 觸發」而失敗——這代表沿用 700ms 並非單純「補齊漏掉的修復」，而是會讓一個目前刻意通過、有明確設計意圖（「避免與長按選取手勢衝突」，見該測試命名）的既有驗證失效。EPUB／PDF 兩邊的內容渲染機制完全不同（WebView 原生文字選取 vs. `PdfViewer` 長按拖曳框選矩形，見 CLAUDE.md），兩者的原生手勢辨識延遲、觸控事件傳遞路徑很可能不同，EPUB 校準出的 700ms 沒有理由自動適用於 PDF——正確數值必須依 `epic-25` Issue 1 同樣的真機多輪診斷手法（比照 Issue 1 的 `[DEBUG-e25iN]` 插樁模式）才能確定，`/diagnose` 在沒有真機存取的情況下無法在本次工作階段內定案。

**下一步：**
1. 比照 `epic-25` Issue 1 的真機診斷手法（`plan-issue-1-realdevice-diagnostics.md` 類型的插樁計畫），在 `_PdfNavZoneTapDetectorState`（或 Issue 2 完成後的共用 `TapZoneDetector` module）加上暫時性插樁，量測真機上「長按拖曳建立劃線/備註」手勢與熱區判定之間的實際時序關係。
2. 依真機資料決定 PDF（或收斂後共用邏輯的 PDF 呼叫端注入值）的正確 `tapMaxDurationMs`，可能維持 400、調整到與 EPUB 相同的 700，或是完全不同的第三個數值——三種結果都要用真機資料佐證，不能假設。
3. 調整後需重新確認 `pdf_reader_view_nav_zone_test.dart` 既有的 600ms 排除測試等既有斷言是否需要跟著更新為新數值，並補上真機診斷過程中發現的新情境的回歸測試。

**單元測試要求：**（待真機診斷定案時序後，於實作計畫階段補齊具體斷言）
- 依真機診斷結果，補上或調整涵蓋「PDF 長按拖曳建立標註不應誤觸換頁」的自動化測試。
- 既有 600ms 排除測試等既有斷言需要重新檢視是否仍然正確，不可讓新數值與既有測試互相矛盾卻未察覺。

**驗收標準：** 真機驗證 PDF 長按拖曳建立劃線/備註標註時不再（或顯著減少）誤觸換頁；最終採用的 `tapMaxDurationMs` 數值有真機資料佐證、非憑空沿用 EPUB 數值；相關單元測試與既有測試皆一致、全數通過。

---

## Issue 4：收斂「等待 PDF 就緒」成一個共用測試 adapter

**Status:** ✅ 已完成並合併回 `main`（PR [#143](https://git.jigong.org/huthief/elinkBook/pulls/143)，分支 `epic-26-issue-4-pump-until-pdf-ready`，6 個 commit）。審查（`reviews/review-issue-4.md`）逐檔案核對 104 個編輯點與 `plan-issue-4.md` 完全吻合，條件反轉方向（最容易出錯之處）全數正確，`flutter analyze` 乾淨、全專案 1189 項測試零回歸，僅 1 項不影響行為的殘留註解用詞（Minor，不阻塞）。

**依賴：** 無

**來源：** `docs/research/architecture-review-test-suite-epub-pdf.md` 候選 6（強度 Strong）。2026-08-14 `/diagnose` 重新查證目前程式碼確認候選 6 描述的重複模式依然存在（原文件為 2026-08-11 產出，本次重新核實非直接沿用舊結論）。

**背景／症狀（2026-08-14 撰寫 `plan-issue-4.md` 時，逐檔案逐呼叫點重新核實後修正——原「37 處」低估，只數到函式*定義*、漏算大量呼叫端）：** 「pdfrx 在 widget test 環境下何時真正完成非同步開書」這件事的等待邏輯，以幾乎逐字相同的輪詢迴圈／輔助函式重複散落在 9 個測試檔案，精確統計共 **104 個編輯點**（定義+呼叫點+獨立內嵌迴圈合計）：

```
app/test/screens/reader_screen_test.dart              20 處，皆無 helper、逐一內嵌（1 處帶 renderedCount 條件＋maxIterations=30；16 處無條件＋maxIterations=30；3 處無條件＋maxIterations=10）
app/test/reader/pdf_reader_view_test.dart               5 處，無 helper、逐一內嵌（3 處 renderedCount==0&&errorMessage==null；2 處 renderedCount==0，皆 maxIterations=30）
app/test/reader/pdf_reader_view_filters_test.dart      26 處：6 個 group 內各自重新定義 local `waitRendered`（逐字相同）＋16 處呼叫端＋4 處不經 waitRendered 的獨立內嵌迴圈（2 處等待 RawImage 出現、1 處等待 RawImage 數量 ≥2＝maxIterations 40、1 處等待 computedRect 非 null，皆 delayBetweenPumps=50ms 而非其餘檔案慣用的 10ms）
app/test/reader/pdf_reader_view_dual_page_test.dart    17 處：1 個 local `waitRendered` 定義＋16 處呼叫端
app/test/reader/pdf_reader_view_selection_test.dart    15 處：1 個定義＋14 處呼叫端
app/test/reader/pdf_reader_view_search_test.dart        7 處：1 個定義＋6 處呼叫端
app/test/reader/pdf_reader_view_nav_zone_test.dart      7 處：1 個定義＋6 處呼叫端
app/test/reader/pdf_reader_view_thumbnail_test.dart     4 處：1 個定義＋3 處呼叫端
app/test/reader/pdf_reader_view_toc_test.dart           3 處：1 個定義＋2 處呼叫端
```

**根因（已用原始碼逐檔案交叉核對確認）：** 三種變形，本質是同一段邏輯的三次獨立重新發明：

1. `reader_screen_test.dart`／`pdf_reader_view_test.dart`：無 helper，`tester.runAsync(() async { for (var i = 0; i < N && <條件或無條件>; i++) { await tester.pump(...); await Future.delayed(...); } })` 逐一內嵌，`N` 與條件依測試情境略有不同（`N` 見過 10／30 兩種，條件見過無條件／`renderedCount == 0`／`renderedCount == 0 && errorMessage == null`）。
2. `pdf_reader_view_dual_page_test.dart`／`selection_test.dart`／`search_test.dart`／`nav_zone_test.dart`／`thumbnail_test.dart`／`toc_test.dart`：**逐位元組相同**的 `Future<void> waitRendered(WidgetTester tester, int Function() rendered) { return tester.runAsync(() async { for (var i = 0; i < 30 && rendered() == 0; i++) { await tester.pump(const Duration(milliseconds: 100)); await Future<void>.delayed(const Duration(milliseconds: 10)); } }); }` 各自在 6 個檔案獨立定義一次，呼叫端也逐位元組相同：`await waitRendered(tester, () => renderedCount);`（已用 `grep` 核對 63 處呼叫點文字完全一致，可安全用單一 find-and-replace 規則處理，不需逐一客製）。
3. `pdf_reader_view_filters_test.dart`：同一份 `waitRendered` 函式體在檔案內 6 個 `group` 各自重新定義一次（第 19/117/221/317/384/456 行），另有 4 處不經 `waitRendered`、條件互異的獨立內嵌迴圈（等待特定 widget 出現/數量，`delayBetweenPumps` 用 50ms 而非其餘 8 個檔案慣用的 10ms——需要共用 adapter 支援可調整的 pump 間隔，原設計遺漏此參數）。

**Solution（依本次逐檔案查證結果精確化簽章，較先前版本新增 `delayBetweenPumps` 參數）：** 新增 `app/test/support/pump_until_pdf_ready.dart`：

```dart
Future<void> pumpUntilPdfReady(
  WidgetTester tester, {
  bool Function()? condition,
  int maxIterations = 30,
  Duration delayBetweenPumps = const Duration(milliseconds: 10),
}) {
  return tester.runAsync(() async {
    for (var i = 0;
        i < maxIterations && (condition == null || !condition());
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(delayBetweenPumps);
    }
  });
}
```

`condition` 為 `null`（省略）時等同「無條件跑滿 `maxIterations` 輪」，涵蓋 `reader_screen_test.dart` 的無條件變形；`maxIterations`／`delayBetweenPumps` 皆可覆寫，涵蓋 `filters_test.dart` 的 40 輪／50ms 變形。9 個檔案的所有呼叫點改為呼叫此共用函式；6 個「單一 local `waitRendered`」檔案與 `filters_test.dart` 的 6 份重複定義整段刪除。呼叫端轉換注意「回傳 0 的 int callback」→「回傳 bool 的 condition callback」是介面轉換非單純改名，`rendered() == 0` 繼續等待 → `condition()` 為 true 時停止，對應 `() => renderedCount != 0`，不可寫反。詳細逐檔案轉換規則見 `plans/plan-issue-4.md`。

**單元測試要求：**
- 本身即為測試輔助工具重構，「測試」是確保收斂後 9 個檔案原有的全部測試案例依然全數通過、斷言不變——比照候選 6 文件「刪除測試」判定：把重複迴圈換成共用 helper，行為完全不變。
- 新增 `pump_until_pdf_ready_test.dart`，驗證 `condition` 提前滿足時確實提前跳出、`maxIterations`／`delayBetweenPumps` 覆寫確實生效。

**驗收標準：** 9 個檔案、104 個編輯點的重複等待邏輯全數改用 `test/support/pump_until_pdf_ready.dart` 的 `pumpUntilPdfReady()`；`pdf_reader_view_filters_test.dart` 與其餘 6 個檔案內共 12 份重複的 local `waitRendered` 定義移除；`flutter analyze` 乾淨、`flutter test` 全數通過、零回歸（測試案例數量、斷言內容、通過/失敗結果皆與收斂前一致）。

---

## Issue 5：收斂已死的 EPUB 頁次估算管線（`totalCharacterCount`／`EpubPageEstimator`）

**Status:** `ready-for-agent`——人類已於 2026-08-20 決策採用選項 A（整批除役），規格已完整，可進入規劃階段撰寫 `plans/plan-issue-5.md`。

**依賴：** 無

**來源：** `docs/research/architecture-review-test-suite-epub-pdf.md` 候選 4（強度 Worth exploring）。2026-08-20 `/zoom-out` 針對「流式格式頁碼/進度計算」模組地圖進行深挖時，重新查證 git 歷史與規劃文件，確認此問題並非單純的規劃疏漏，而是三度被看見、三度被有意識延後、始終未被排入任何工單執行，累積至今成為孤兒程式碼；完整溯源見 `docs/zoomout/pagination-flowable-formats.md` 第三部分。

**背景／症狀：** `Book.totalCharacterCount` schema 欄位、`EpubCharacterCountRepository`、`EpubPageEstimator`（用字元數估算頁碼的純函式，含 `letterSpacing`/`lineHeight`/`paragraphSpacing` 等精修過的幾何模型）、`reader_screen.dart` 的 `_buildEpubFooter()`、`toc_bottom_sheet.dart` 的 EPUB 目錄頁碼標籤計算，全部依賴 `totalCharacterCount` 這個欄位——但正式（非測試）程式碼中沒有任何地方呼叫 `saveTotalCharacterCount()` 寫入它，該欄位恆為 `null`。可觀察到的實際行為：

- `_buildEpubFooter()`（`reader_screen.dart`）永遠不會被建構（明確標註的死路徑，現行頁尾走的是 `_buildFoliateEpubFooter()`，資料來自 foliate-js `SectionProgress` 回報的 `pageIndex`/`totalPages`，與此無關）。
- `toc_bottom_sheet.dart:210-243` 的 EPUB 目錄項目頁碼標籤因 `totalCharacterCount` 恆為 `null`，**目前恆顯示佔位符「…」**——與 CLAUDE.md「目錄元件須顯示標題+頁碼」的要求有落差，是此問題目前唯一使用者可見的缺口。

**根因（已用 git 歷史交叉核對確認，非臆測）：** 字元數的唯一寫入來源是 Readium 原生端的 `onCharacterCountReady` 回呼，隨 epic-20 Issue 5（`cc1d5a5`／`3e76c69`，2026-07-31）移除 `EpubReaderView`（Readium 渲染路徑）一併被刪除；接手的 `FoliateReaderView` 從未實作替代回呼。此問題在規劃階段即被明確記載但責任層層轉手未被接手：

1. **epic-17**（ADR 0011、spec.md、issues.md Issue 6）：規劃時已決定流式路徑不再送出/接收字元數，「FXL 路徑是否也一併清理，留待未來 Epic 評估」。
2. **epic-20 Issue 4**（`plan-issue-4.md`）：審查時再次查證確認是死碼，Global Constraints 明文「不擴大範圍清理」，並轉交給 Issue 5。
3. **epic-20 Issue 5**：實際執行範圍只涵蓋刪除 `EpubReaderView.kt`／`epub_reader_view.dart` 本體，未接手 Issue 4 轉交的清理項目——轉手落空。
4. **架構檢視報告**（`bc06de6`，2026-08-11）：獨立重新發現完整問題全貌並記錄為候選 4，但未被轉化為可執行工單；報告發布後 3 天內，`epic-28` Issue 1 審查修正（`ed5b221`）仍持續對這條已知不可觸達的路徑新增 `letterSpacing` 功能。

**已決策範圍（2026-08-20 人類決策：選項 A——整批除役）：** 確認現行 `_buildFoliateEpubFooter()`（頁尾頁碼/進度顯示，資料來自 foliate-js `SectionProgress` 的 `pageIndex`/`totalPages`）已完全取代舊估算管線的顯示需求；唯一遺留缺口（TOC 頁碼標籤恆顯示「…」）接受移除、不再顯示頁碼（僅顯示章節標題）。移除範圍：

- `app/lib/reader/epub_page_estimator.dart`（`EpubPageEstimator`）整檔刪除。
- `app/lib/reader/epub_character_count_repository.dart`（`EpubCharacterCountRepository`）整檔刪除；`reader_prefs_manager.dart`/`reader_prefs_manager_impl.dart` 的 `saveTotalCharacterCount()` 一併移除（正式程式碼已零呼叫點，可安全移除）。
- `Book.totalCharacterCount` 欄位——**規劃階段須先確認處理方式**：新增一筆 schema migration 用 `DROP COLUMN`（SQLite 3.35+ 原生支援，需確認專案目前 sqflite/SQLite 版本是否滿足；不滿足則需改用「建新表搬資料」手法，比照 `sqlite_library_repository.dart` v17 UUID 遷移的既有作法）移除該欄位，或至少從 `Book` 模型的 `toMap()`/`fromMap()`/建構子移除此欄位（schema 欄位本身保留但不再讀寫，作為過渡方案）；兩種作法擇一在 `plans/plan-issue-5.md` 定案並說明理由。
- `app/lib/screens/reader_screen.dart` 的 `_buildEpubFooter()`（死路徑本體）與其呼叫端條件式整段移除。
- `app/lib/screens/toc_bottom_sheet.dart:210-243` EPUB 頁碼估算分支移除，改為 EPUB 目錄項目只顯示標題（比照移除前「無法算出頁碼」的既有 fallback 分支精神，但轉為預設行為而非 fallback）。
- 對應測試：`app/test/reader/epub_page_estimator_test.dart` 整檔刪除；`app/test/support/fake_epub_character_count_repository.dart` 整檔刪除；`app/test/reader/reader_prefs_manager_test.dart` 移除 `saveTotalCharacterCount`/`EpubCharacterCountRepository` 相關案例；`app/test/library/models/book_test.dart`／`app/test/library/sqlite_library_repository_test.dart` 移除 `totalCharacterCount` 相關斷言（若採 `DROP COLUMN` migration，需新增對應 migration 測試）。

**未選用（記錄供未來參考）：** 選項 B——補上 foliate-js 版字元數回報管道，保留 TOC 頁碼顯示需求。理由：`foliate-js` 目前完全沒有全書字元計數邏輯，需另外設計計算與回傳管道且需確認效能（不可阻塞開書流程），工作量明顯大於選項 A；現行頁尾已用 foliate-js 原生 `location` 概念滿足主要頁碼顯示需求，TOC 頁碼標籤非核心需求，不值得為此投入。

**單元測試要求：**
- 確認 `EpubPageEstimator`/`EpubCharacterCountRepository`/`totalCharacterCount` 相關測試隨程式碼一併移除，不殘留引用已刪除型別的測試。
- `toc_bottom_sheet_test.dart` 補上「EPUB 目錄項目不顯示頁碼標籤（僅標題）」的新斷言，取代原本驗證「…」佔位符的既有測試。
- 若採 `DROP COLUMN` migration：新增 migration 測試比照既有 `sqlite_library_repository_test.dart` 慣例（含跳級升級情境）。
- `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸（不含上述刻意移除/取代的案例）。

**驗收標準：** `EpubPageEstimator`、`EpubCharacterCountRepository`、`Book.totalCharacterCount` 相關程式碼（含死路徑 `_buildEpubFooter()`、TOC 頁碼估算分支）全數移除；`Book.totalCharacterCount` 欄位依規劃階段定案的方式處理（`DROP COLUMN` 或至少停止讀寫），不再維持「schema/repository/估算器齊全但恆為 `null`」的孤兒狀態；`flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。
