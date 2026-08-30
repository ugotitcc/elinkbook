# Review — Epic 27 Issue 11：長按已畫線區域改由畫線工具列統一處理

**審查對象：** 分支 `feat/epic-27-issue-11`，`eee2567117cd9425f0b7c52dbd294f5c58010a33`（base）→ `177145756ed7cd868682afb196544d18d9f690e0`（head），共 8 個 commit（Task 1～Task 8，逐一對應 `plans/plan-issue-11.md`）。
**對應工單：** `docs/epics/epic-27-reader-device-compat/issues.md` Issue 11。
**審查日期：** 2026-08-25
**審查性質：** 程式碼／測試審查（逐一比對 `plan-issue-11.md` 每個 Task 的預期程式碼片段與實際 diff、追查 `main.js` 呼叫的 `view.js`/`overlayer.js` 既有公開 API 是否真的如註解所述存在並語意正確、實際建立獨立 worktree 執行 `flutter pub get`／`flutter analyze`／`flutter test`（全專案，非僅子集），驗證完畢後已移除該暫時 worktree，未變動主要 checkout 的 HEAD／index／working tree／任何既有 branch 或 worktree。

---

## Strengths

1. **實作與計畫逐字相符。** Task 1（`percentRectToPdfRect`）、Task 2（`text`/`existingAnnotationId` 欄位）、Task 3（`main.js` hit-test）、Task 5（`annotation_resolution.dart`／`PercentRect.overlaps`）、Task 6（`AnnotationToolbar` 雙列改版）逐行比對，程式碼與計畫內指定的片段幾乎完全一致，沒有偷改範圍。Task 4／7／8 有少數必要的技術性偏離（見下方 Recommendations），皆有正當理由，非隨意變動。
2. **JS 端 hit-test 邏輯實際查證正確、未動到任何 vendored 檔案。** 已追進 `view.js`/`overlayer.js` 原始碼確認：`view.addAnnotation({ value: cfi, ... })` 內部呼叫 `overlayer.add(value, ...)`，即 `Overlayer` 內部 Map 的 key 就是 `cfi`，與 `decorationIdByCfi`（同樣以 cfi 為 key）語意一致；`hitTest()` 回傳的 `[key, range, rect]` 中 `key` 正是這個 cfi，因此 `main.js` 新增的 `decorationIdByCfi.get(hitCfi)` 反查邏輯技術上正確。`overlayer.js` 的 `#zoom` 只在非 Chrome/Android 的 Safari 系瀏覽器才會 ≠ 1.0，App 實際跑在 Android WebView（Chromium 核心），故 `reportSelection()` 用未經 zoom 縮放的 `rect` 與已縮放的 `overlayer` 內部 rects 比對不會有座標落差風險。`git diff --stat` 確認整個 range 只動了 `assets/foliate/main.js`，`paginator.js`/`view.js`/`epub.js`/`overlayer.js`/`fixed-layout.js` 完全未觸碰，符合 ADR 0011。
3. **PDF 座標反函式與非同步競速防護皆有效驗證，直接對應前次審查報告的兩個 Important 風險。** 已交叉核對 `pdfrx_engine` 套件原始碼（`PdfRect` 建構子確實有 `assert(top >= bottom)`），`percentRectToPdfRect` 的公式（`(1.0 - percentTop) * pageHeight`）確實會讓換算結果滿足這個 assert，且 Task 1 的 3 則測試明確驗證了「互為反函式」與「不觸發 assert」兩件事。Task 4 新增的 `_selectionDragGenerationId` 世代編號防護搭配「框選完成後文字萃取尚未完成前又開始下一次框選，只有最後一次結果生效」這則測試，是真正利用真實 FFI 呼叫時序（刻意不用 `tester.runAsync` 讓第一次萃取卡住）構造出競速情境後斷言 `results.length == 1`，不是靠 mock 空轉，驗證力道足夠。
4. **向後相容性確實有處理，非僅口頭宣稱。** `EpubSelectionInfo`/`PdfSelectionInfo` 的 `text`/`existingAnnotationId` 皆為具名參數並有預設值（`''`/`null`），`foliate_reader_view.dart` 用 `args.length > 6`/`args.length > 7` 防禦性解析，`main.js` 新增的 2 個位置參數放在既有 6 個參數之後，不會破壞舊有呼叫順序。已用 `flutter analyze` 確認全專案（含既有呼叫端）零錯誤。
5. **邊界情境判斷與既有慣例一致，且皆有測試覆蓋。** `resolvePdfExistingAnnotation`／`resolveEpubExistingAnnotation` 對「命中畫線＋依附備註」「純備註」「已依附畫線的備註不算獨立命中」「不同頁不命中」「純重疊比對」等情境的處理，皆有意識地比照 `_sendDecorationsToNative`/`_sendPdfAnnotationsToNative` 既有的 `highlightId == null` 判斷慣例，`annotation_resolution_test.dart` 逐一以獨立單元測試覆蓋，不需要 `testWidgets` 就能驗證核心邏輯，測試成本低、訊號直接。
6. **測試品質高，多處用真實時序而非過度 mock。** 例如 `foliate_reader_view_test.dart` 新增的 regression guard 用實際讀取 `main.js` 原始碼文字（並補上 `.replaceAll('\r\n', '\n')` 正規化，較計畫原文更周全，避免 Windows checkout CRLF 造成字串比對誤判——這是實作過程中主動發現並修正的合理強化，值得肯定）比對呼叫順序，而非對 JS runtime 做黑箱假設。
7. **實際驗證結果：`flutter analyze` 全專案乾淨（`No issues found!`），`flutter test` 全專案 1,690 則測試全數通過（零失敗），親自在獨立 worktree 執行確認，不是只採信 commit message 的宣稱。**

---

## Issues

### Critical (Must Fix)

無。

### Important (Should Fix)

1. **`issues.md` 的 Issue 11 文件同步，未包含在本次審查的分支/commit range 內。**
   `plan-issue-11.md`「完成後的驗證」清單明確要求：「本計畫完成後，同步更新 `docs/epics/epic-27-reader-device-compat/issues.md`『Issue 11』的 `Status`...並在 Solution 段落註記實際採用的機制」，且該項目已勾選 `[x]`。但實際檢查 `eee2567..1771457` 的完整 diff，`docs/` 目錄下沒有任何變動——`git diff --stat` 只列出 `app/` 底下的 19 個檔案。

   進一步追查發現：這項更新其實已經寫好（內容正確，Status 從 `needs-info` 改為「✅ 已完成實作並通過全分支審查」，且引用的分支名稱、commit 數、`flutter test` 通過則數〔1,690〕都與本次實測結果一致），但目前只是主要 checkout（`main`）working tree 上**未提交**的本機修改，既沒有進到 `feat/epic-27-issue-11` 分支，也沒有以任何 commit 的形式存在。

   **為什麼重要：** (a) 從被審查的 commit range 角度看，「文件與程式碼同步」這項計畫承諾的工作實際上尚未完成，`plan-issue-11.md` 內的勾選 `[x]` 與 commit 歷史對不上，日後若有人只看 branch/commit history 稽核，會誤以為這件事還沒做；(b) 未提交的本機修改有遺失風險（換機器、`git clean -fd`、或不小心 `git checkout -- .` 都會讓這些內容消失且無法復原）。

   **建議：** 在 finish 這個分支（或合併前的收尾階段）把 `issues.md`／`plan-issue-11.md` 這兩個檔案的異動提交為一個 commit（可以是 Task 8 之後的第 9 個 commit，或合併前的獨立 docs commit），讓「文件已同步」這件事有可稽核的紀錄。

### Minor (Nice to Have)

1. **多處新增/修改的檔案結尾出現多餘空白行。** `app/lib/reader/percent_rect.dart` 新增的 `overlaps()` 方法與後面的 `@override bool operator ==` 之間多了一行空白（連續兩個空行）；`epub_selection_info.dart`／`pdf_selection_info.dart`／`pdf_search_geometry.dart` 檔案結尾也各多了一行空白。`flutter analyze` 不會標記這類問題（非 lint 規則涵蓋範圍），但下次提交前跑一次 `dart format` 可以順手清掉，維持既有檔案風格一致。
2. **`_annotationToolbarHeight`/`_annotationToolbarWidth` 改為雙列版面後的新估計值（104.0/256.0）在程式碼註解中已誠實標註「這是估計值，不是嚴謹量測結果」**，且明確交代若既有 widget test（如「工具列右緣不應超出畫面寬度」）失敗需以測試回報的真實數值為準調整——這是良好的工程誠實度，非缺陷。目前所有相關測試皆綠燈，但仍建議 Task 完成後如有機會在真機（WAVE／AiPaper Reader C）上目視核對一次雙列工具列的實際外觀與版面是否符合預期（`issues.md` 更新草稿中也已註記類似的真機驗證建議）。

---

## Recommendations

1. **關於 Task 4／7／8 相對計畫的技術性偏離：** 皆為正當、有理由的偏離，不影響功能範圍：
   - Task 4 測試改用 `pumpUntilPdfReady(tester, condition: ...)` 取代計畫原文的固定次數 `tester.pump()`，對 PDF FFI 呼叫的非同步完成時機更穩健，是既有測試 helper 的合理復用。
   - Task 7 的 `initialText: existing?.text ?? ''` 相對計畫原文 `initialText: existing?.text`（可為 `null`）做了必要修正——`showNoteTextDialog` 的 `initialText` 參數型別是不可為 `null` 的 `String`（預設 `''`），若照計畫原文字面寫會是型別錯誤，實作端的修正是正確且必要的。
   - `foliate_reader_view_test.dart` 新增的 CRLF 正規化（`.replaceAll('\r\n', '\n')`）已在 Strengths 提及，是合理的主動強化。
   這些偏離本身不需要修正，但建議在 PR 描述或 commit message 中簡短提一句「相對計畫的必要技術修正」，方便之後對照計畫文件時不會誤以為是遺漏。
2. **關於 Important #1：** 建議把「文件同步」這個步驟明確列為 `plan-issue-11.md` 的其中一個 Task（而非只在「完成後的驗證」清單打勾了事），這樣未來執行 `superpowers:subagent-driven-development`/`executing-plans` 這類流程時，這個步驟會自然落在同一個可稽核的 commit 序列裡，不會變成遊走在主要 checkout 上的未提交修改。

---

## Assessment

**Ready to merge？** With fixes（僅需補上 Important #1：把 `issues.md`／`plan-issue-11.md` 的文件同步異動提交為 commit，程式碼本身可直接合併）。

**Reasoning：** 程式碼實作與計畫高度一致、`main.js` 呼叫的既有公開 API 語意經逐行查證正確、兩個前次審查報告點名的高風險項目（PDF 座標反函式、非同步競速）都有對應且有效的測試覆蓋、`flutter analyze`／`flutter test`（1,690 則，全數通過）皆已親自於獨立 worktree 驗證乾淨，未發現任何 Critical 或會影響功能正確性的 Important 問題；唯一的 Important 項目是文件同步工作尚未落地為可稽核的 commit，屬於收尾動作而非程式碼缺陷，補上即可合併。
