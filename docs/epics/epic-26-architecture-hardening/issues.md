# Epic 26 — 架構深化機會：工單清單 (Issues)

依 `docs/research/architecture-review-test-suite-epub-pdf.md`（2026-08-11，`/improve-codebase-architecture` 流程產出，7 個候選深化機會）逐項評估後立案。候選 1 經 `/diagnose` 確認為現存 bug並拆為 Issue 1（已修復並合併）；候選 2 經 `/diagnose` 深入查證後拆為 Issue 2（安全的機械式收斂，`ready-for-agent`）與 Issue 3（需真機診斷才能定案的門檻值問題，`needs-info`，見 Issue 3 說明「為何不能直接沿用 Issue 2 的收斂結果」）；候選 6 拆為 Issue 4（已完成並合併）；候選 4 於 2026-08-20 `/zoom-out` 深挖後拆為 Issue 5（人類已決策採選項 A 整批除役，`ready-for-agent`）；其餘候選（3 同類但影響較小、5/7 需要先決策或範圍較大）尚未拆案，視後續優先順序決定是否納入本 Epic。

**2026-08-21 併入第二份架構檢視報告的候選深化機會：** `docs/research/architecture-review-library-remote-screens.md`（2026-08-19，`/improve-codebase-architecture` 流程產出，範圍為 `LibraryScreen`／`RemoteCatalogScreen` 熱點區域，6 個候選）。原報告候選 1（抽出 `RemoteBookDownloader` 深模組）已於報告發布後由 `epic-30` Issue 6 獨立完成並合併（`downloadToTempFile()`／`promoteToPermanent()` 已被兩個畫面共用，非本次新增範圍）；其餘候選經現況複核（`epic-29`／`epic-30` 兩個仍在開發中的 Epic 持續為 `LibraryScreen` 增加參數與穿透依賴，數字已比報告當時惡化）後依建議處理順序拆為 **Issue 6**（候選 3，`ComputeRemoteFingerprint` 穿透）、**Issue 7**（候選 5，`LibraryScreen` 建構子參數膨脹）、**Issue 8**（候選 2，`LibraryScreen` God-Widget 拆分）、**Issue 9**（候選 4，`Book.copyWith()` shallow interface），皆標記 `ready-for-agent`。候選 6（5 個批次操作方法骨架重複，Speculative）暫不拆案，預期在 Issue 8 拆分時被自然吸收進 `LibraryBatchActions` module。

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

**Status:** ✅ 已完成並合併回 `main`（PR [#173](https://git.jigong.org/huthief/elinkBook/pulls/173)，分支 `epic-26-issue-5`，5 個 commit：Task 1–4 各一個＋審查修正一個）。審查（`reviews/review-issue-5.md`）逐 Task 對照 `plan-issue-5.md` 的 old_string/new_string 核對，還原度極高，`Task 5` 全域殘留掃描（`totalCharacterCount`／`EpubPageEstimator`／`EpubCharacterCountRepository`）確認乾淨；發現 1 項 Important（`epub_pagination_test.dart` 跳頁測試斷言格式與 `ReaderFooter` 實際輸出不符）與 3 項 Minor（殘留空行、過時測試標題、中繼 commit 資源釋放時序），Important 與可處理的 Minor 已修正並隨 PR 合併，`flutter analyze` 乾淨、`reader_screen_test.dart` 167 項測試零回歸。

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

---

## Issue 6：收斂 `ComputeRemoteFingerprint` 在多個畫面之間的穿透

**Status:** ✅ 已完成並合併回 `main`（PR [#174](https://git.jigong.org/huthief/elinkBook/pulls/174)，分支 `epic-26/issue-6`，5 個 commit：Task 1–4 各一個＋Task 4 移除未使用 import 一個）。新增不可變資料類別 `RemoteCatalogDependencies`（`app/lib/remote/remote_catalog_dependencies.dart`），`RemoteServerListScreen`／`RemoteCatalogScreen`（含自我遞迴 `_openSubsection()`）皆改用單一 `dependencies` 參數取代原本 3 個獨立具名參數；範圍刻意侷限這兩個畫面，`LibraryScreen`／`main.dart`／`CloudBrowserScreen`／`CloudDownloadQueueDialog` 完全未動（僅 `library_screen.dart` 一處呼叫點多做一次 bundle 組裝，見計畫書「規劃階段查證」段落）。審查（`reviews/review-issue-6.md`）確認最終狀態與計畫完全吻合、範圍邊界確實守住，`flutter analyze` 乾淨、`flutter test` 1607 項測試全數通過，自我遞迴 `same()` 回歸測試（鎖定 `925703f` 那類漏轉送事故不再重演）確認存在且正確。審查發現 1 項 Important（過渡期 commit `fb999e9` 混入部分 Task 3 改動、單獨 checkout 無法編譯，違反計畫「每個 commit 皆可編譯」原則）與 1 項 Minor（Task 1 測試留有未使用 import 直到 Task 4 才清除）——因最終合併狀態無功能性問題，經人類確認接受現況，不另補修正 commit。

**依賴：** 無（建議與 Issue 7 一併規劃——本 Issue 收斂出的依賴 bundle，Issue 7 可望直接沿用來瘦身 `LibraryScreen` 建構子，但兩者可獨立驗收）。

**來源：** `docs/research/architecture-review-library-remote-screens.md` 候選 3（強度 Strong）。2026-08-21 提出處理順序建議時重新核對現況，發現報告完成後短短兩天內已從 5 個檔案惡化為 7 個檔案，且已經真的因此發生過一次生產 bug（見下方），風險已從報告當時的「假設性」變成「已驗證發生」，故列為本次併入候選中優先序最高者。

**背景／症狀（已用原始碼交叉核對確認，非報告原文推論）：** `ComputeRemoteFingerprint`（型別定義＋真身實作於 `app/lib/library/book_content_fingerprint.dart:9-21,47-67`，用 `Isolate.run()` 執行以避開已知的 `testWidgets()` 假時間 zone 死鎖問題，見 `review-issue-2.md`）目前以建構子參數逐層宣告／轉送的方式，穿透以下 7 個彼此業務邏輯無關的檔案：`main.dart`（組裝根）→ `library_screen.dart`／`cloud_browser_screen.dart`／`remote_server_list_screen.dart`／`remote_catalog_screen.dart`（皆為純轉送）→ `cloud_download_queue_dialog.dart:111`／`remote_catalog_screen.dart:559`（僅此兩處為實際呼叫點）。`remote_catalog_screen.dart` 甚至需要宣告兩次（畫面本體＋內部 `_DownloadQueueDialog` state 各一份）。

**已發生的真實事故（報告完成後新增證據）：** commit `925703f`（`fix(epic-29): Issue 5——修復 _openGroupFilteredView() 未轉發 computeFingerprint`）——`LibraryScreen` 內部一個導覽路徑（依分類篩選開啟的畫面）建構下一層畫面時漏轉送這個參數，直到審查才發現。這正是候選 3 描述的核心風險（「每多一層轉送，就多一個可能漏轉送的機會」）從理論變成事實的具體案例。

**與候選 1（`RemoteBookDownloader`）的關係——先確認過、非重工：** 候選 3 原文建議「讓指紋比對成為候選 1 提議的 `RemoteBookDownloader` deep module 的內部細節」，但候選 1 已於 `epic-30` Issue 6 完成（`app/lib/remote/remote_book_downloader.dart`），經查證 `downloadToTempFile()`／`promoteToPermanent()` 兩個函式簽章完全不含指紋比對邏輯——原文建議的收斂路徑並未被採納，`ComputeRemoteFingerprint` 至今仍是獨立穿透的參數，本 Issue 是獨立未償還的技術債，不是候選 1 的殘留尾巴。另外指紋比對的兩個真實呼叫點（下載後比對，供「重複下載偵測」使用）本來就不完全等於「下載」這個動作本身（例如 `CloudBrowserScreen._toggleSelection()` 的選檔前置比對是用 `cloudFileId` 而非內容指紋，是另一層獨立檢查），機械式塞進 `RemoteBookDownloader` 未必是正確邊界，需要規劃階段重新評估。

**Solution（方向）：** 抽出一個獨立、與具體畫面無關的 seam（例如封裝為一個小型不可變資料類別，內含 `computeFingerprint`／`createOpdsClient`／`thumbnailCache`——這三者在現行程式碼中經常一起穿透、生命週期與用途高度相關），畫面建構子只接這一個物件，往下層轉送時同樣只轉送這一個物件，取代目前 3 個獨立具名參數各自宣告/轉送的做法；具體型別/命名/是否額外納入 `remoteServerRepository` 由規劃階段定案，需維持 ADR 0007「平行建構子參數、不用 service locator」的既有組裝哲學，只是把「一堆散落參數」收斂成「一個具名 bundle 參數」，不是引入 service locator。

**單元測試要求：**
- 既有 `library_screen_test.dart`／`cloud_browser_screen_test.dart`／`remote_catalog_screen_test.dart`／`remote_server_list_screen_test.dart`／`cloud_download_queue_dialog_test.dart`（若存在）等測試改用新 bundle 建構，斷言邏輯本身不變（純重構，零行為變化）。
- 新增一項回歸測試，鎖定「新畫面/新轉送路徑只需要傳遞一個 bundle 參數，不會重演 `925703f` 那類漏轉送」的意圖（例如驗證 bundle 物件本身不可變、無法只轉送部分欄位）。
- `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。

**驗收標準：** `ComputeRemoteFingerprint` 不再以獨立具名參數形式穿透 7 個檔案，收斂為單一 bundle 物件的一部分；`main.dart` 組裝點與所有下游畫面建構子皆改用新介面；既有下載/重複偵測行為零改變；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 7：收斂 `LibraryScreen` 建構子的參數膨脹（22→27 個，持續增加中）

**Status:** `ready-for-agent`。

**依賴：** 建議待 Issue 6 完成後再進行（可直接沿用 Issue 6 收斂出的 bundle 物件處理其中 3 個參數），但若優先順序需要也可獨立先行，兩者驗收標準互不重疊。

**來源：** `docs/research/architecture-review-library-remote-screens.md` 候選 5（強度 Worth exploring）。2026-08-21 現況複核發現報告當時的 22 個參數已增至 27 個（新增 `cloudAccountRepository`／`googleDriveOAuthClient`／`oneDriveOAuthClient`／`googleDriveStorageClient`／`oneDriveStorageClient`，皆為 `epic-29` 雲端匯入貫穿注入的產物），且 `epic-29`／`epic-30` 兩個來源 Epic 目前皆仍是 🟡 開發中，會持續增加，越晚處理牽涉範圍越大。

**背景／症狀：** `app/lib/screens/library_screen.dart:32-58`（`_LibraryScreenState` 建構子）目前 27 個具名參數中，絕大多數只是原樣往下轉送給 `ReaderScreen`（12 參數）／`RemoteServerListScreen`（6 參數）／`SettingsScreen`，`LibraryScreen` 自身邏輯並不直接使用。報告原文的「刪除測試」已驗證：這份建構子沒有藏任何複雜度，純粹是轉送管線——合理但 low-leverage 的角色，且驗證方式已證明分拆不會讓複雜度轉移到別處，只會讓可讀性提升。

**Solution（方向）：** 依用途將同質參數分組打包為 2-3 個小型不可變 bundle 物件（例如：既有 repository 群組——`bookmarksRepository`／`highlightsRepository`／`notesRepository`／`customFontsRepository`／`layoutPresetRepository`／`bookReaderPrefsRepository`／`syncAccountRepository`；雲端/遠端群組——`cloudAccountRepository`／`googleDriveOAuthClient`／`oneDriveOAuthClient`／`googleDriveStorageClient`／`oneDriveStorageClient`／`remoteServerRepository`，可與 Issue 6 的 bundle 整合；主題/顯示控制群組——`currentTheme`／`isEinkMode`／`onThemeChanged`／`onEinkModeChanged`），具體分組方式與是否保留 `repository`／`importService`／`prefsManager`／`groupFilter` 等核心參數獨立（不打包）由規劃階段定案。刻意不等候選 2（Issue 8）的 God-Widget 拆分才處理——報告原文預期候選 2 完成後參數會「自然收斂」，但 `epic-29`／`epic-30` 仍在持續增加參數，等待只會讓 Issue 8 的起始狀態更差；本 Issue 完成後，Issue 8 拆分內部 module 時可直接接手這些 bundle，兩者不衝突。

**單元測試要求：**
- `library_screen_test.dart` 既有全部案例改用新 bundle 建構，斷言邏輯不變（純重構）。
- `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。

**驗收標準：** `LibraryScreen` 建構子的具名參數數量明顯減少（27 個收斂為個位數的 bundle＋少數核心參數）；所有既有呼叫點（`main.dart`／測試）更新為新介面；行為零改變；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 8：拆分 `LibraryScreen` God-Widget（1504 行，持續增長中）

**Status:** `ready-for-agent`（範圍較大，建議規劃階段拆成多個循序 Task，比照本 Epic 其他多 Task Issue 慣例）。

**依賴：** 建議待 Issue 6／Issue 7 完成後再執行——外部依賴介面先收斂乾淨，內部 module 拆分阻力較小；非強制順序。

**來源：** `docs/research/architecture-review-library-remote-screens.md` 候選 2（強度 Strong）。2026-08-21 現況複核：`app/lib/screens/library_screen.dart` 從報告當時的 1410 行增至 1504 行（短短兩天內 +94 行），持續是全專案 commit 頻率最高的熱點檔案，佐證報告「沒有內部 module 邊界可以吸收新複雜度，只能往同一層堆」的診斷仍然成立且未緩解。

**背景／症狀：** `_LibraryScreenState` 單一 class body 同時裝載：書籍載入／排序／分類篩選狀態機、匯入對話框、5 個批次操作（候選 6，`:353-508`，重複骨架見報告）、導覽樞紐（建構 `ReaderScreen`／`RemoteServerListScreen`／`SettingsScreen`，見 Issue 7）、拼貼格 footer 非線性字級縮放數學，全部同一扁平深度，沒有任何內部 module 邊界。候選 1（`RemoteBookDownloader`）已由 `epic-30` Issue 6 抽出，證明「抽出獨立 module」這個方向本身可行且已有先例可循。

**Solution（依報告 Before/After，並吸收候選 6）：**
- 抽出 `LibraryBookListController`：書籍載入／排序／分類篩選狀態機。
- 抽出 `LibraryBatchActions`：現行 5 個批次操作（搬移分類／強制 FXL／恢復自動判斷／刪除／移除本機快取），順帶收斂候選 6 描述的重複骨架（`capture 選取狀態 → 提早退出選取模式 → 過濾迴圈 → repository 呼叫 → _loadBooks()`）為共用 `runBatchAction(action)`，5 種操作各自只提供差異化的「單本書該做什麼」。
- 抽出 `BookGridTileMetrics`：拼貼格 footer 非線性字級縮放數學（純函式，與 widget 生命週期無關，應可獨立單元測試）。
- `LibraryScreen` 收斂為呈現＋委派，`RemoteBookDownloader`（候選 1，已完成）與 Issue 6／7 收斂出的 bundle 維持不變、原樣使用。
- 具體 module 邊界切法、是否需要額外拆出「匯入對話框」「導覽樞紐」為獨立 module，由規劃階段依實際切分後的檔案大小/職責清晰度定案。

**單元測試要求：**
- 新增 module 各自的獨立單元測試（`LibraryBookListController`／`LibraryBatchActions`／`BookGridTileMetrics`），特別是 `BookGridTileMetrics` 的縮放數學應可脫離 widget 樹直接測試。
- `library_screen_test.dart` 既有 12 個 fake 依賴／既有案例確認拆分後零回歸；報告已指出「需要 12 個 fake 依賴才能立起一個畫面測試」本身是 low leverage 的證據，拆分後應可觀察到部分測試改為直接測試新 module、不再需要完整 `LibraryScreen` 畫面環境。
- `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。

**驗收標準：** `LibraryScreen` 內部關注點依 module 邊界拆分完成，`_LibraryScreenState` 顯著變薄（不要求特定行數門檻，但應可觀察到書籍清單狀態機／批次操作／版面數學不再與呈現邏輯混雜在同一個 class body）；候選 6（批次操作骨架重複）隨本 Issue 一併收斂，不需另立工單；`flutter analyze` 乾淨、`flutter test` 全數通過。

---

## Issue 9：`Book.copyWith()` 全欄位開放為具名參數（shallow interface，已有真實事故佐證）

**Status:** `ready-for-agent`。

**依賴：** 無，範圍侷限 `app/lib/library/models/book.dart` 單一檔案，可獨立於 Issue 6/7/8 任何時間點處理，不阻塞、也不被阻塞。

**來源：** `docs/research/architecture-review-library-remote-screens.md` 候選 4（強度 Worth exploring，已有真實事故佐證）。2026-08-21 現況複核：`Book` 模型自報告完成後新增 `cloudFileId` 欄位（`epic-29` Issue 0，`db08c4d`），該次新增正確依照既有模式把新欄位排除在 `copyWith()` 具名參數之外、於函式本體原樣帶入（`cloudFileId: cloudFileId`），沒有重演事故，但也代表候選 4 描述的「只開放 4/21 欄位、其餘 17（現 18）欄位需手動逐一背」這個結構性風險本身沒有被順手處理，仍然存在。

**背景／症狀：** `app/lib/library/models/book.dart:201-231`（`copyWith()`）目前僅 4 個欄位（`groupName`／`isFixedLayout`／`filePath`／`isDownloaded`）為具名參數，其餘欄位（現為 18 個）在函式本體逐一手動 `fieldName: fieldName` 原樣帶入——寫漏一個不會編譯錯誤，只會在執行期靜默清空該欄位。2026-08-04 曾因此漏帶 `positionSyncedServerUpdatedAt`／`positionUpdatedAt`，任何呼叫 `copyWith()` 的批次操作（例如 `_moveSelectedBooksToGroup`）都會靜默清空同步進度資料，直到後續審查才發現修正（詳見報告候選 4 段落）。

**Solution：** 21 個欄位全部開放為具名參數（`String? id, String? title, ... `），函式本體改為 `field: field ?? this.field` 逐一覆寫，取代目前「4 個具名參數 + 17 個原樣帶入」的不對稱寫法；遺漏欄位會直接編譯失敗（未在新建構子參數列宣告的欄位無法被覆寫也無法被遺漏，因為所有欄位都會出現在同一份參數列，複查即可發現遺漏）。現有 4 個呼叫點（`app/lib/screens/library_screen.dart` 等）呼叫方式不變，純粹是介面擴寬，不需要修改既有呼叫端程式碼。

**單元測試要求：**
- `book_test.dart` 新增涵蓋「呼叫 `copyWith()` 覆寫先前只能透過建構子設定的欄位（例如 `positionUpdatedAt`／`cloudFileId`）」的案例，證明新開放的具名參數確實可用。
- 既有 `copyWith()` 相關測試（4 個既有具名參數的行為）零回歸。
- `flutter analyze` 乾淨、`flutter test` 全數通過。

**驗收標準：** `Book.copyWith()` 21 個欄位全數開放為具名參數；既有 4 個呼叫點行為零改變；`flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。
