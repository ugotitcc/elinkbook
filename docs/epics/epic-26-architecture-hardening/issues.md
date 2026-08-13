# Epic 26 — 架構深化機會：工單清單 (Issues)

依 `docs/research/architecture-review-test-suite-epub-pdf.md`（2026-08-11，`/improve-codebase-architecture` 流程產出，7 個候選深化機會）逐項評估後立案。候選 1 經 `/diagnose` 確認為現存 bug並拆為 Issue 1（已修復並合併）；候選 2 經 `/diagnose` 深入查證後拆為 Issue 2（安全的機械式收斂，`ready-for-agent`）與 Issue 3（需真機診斷才能定案的門檻值問題，`needs-info`，見 Issue 3 說明「為何不能直接沿用 Issue 2 的收斂結果」）；其餘候選（3/6 同類但影響較小、4/5/7 需要先決策或範圍較大）尚未拆案，視後續優先順序決定是否納入本 Epic。

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

**Status:** `ready-for-agent`——安全的機械式收斂，範圍已明確排除有爭議的門檻值變更（見下方「刻意排除的範圍」），無需真機驗證即可實作與驗收。

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
