# Issue 3：縮排排除置中與無文字段落實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 首行縮排只套用到「有文字、且實際顯示不是置中」的段落；置中段落與沒有文字的段落（空白、只有圖片）不縮排。使用者自己選了「文字對齊」時不做置中排除。

**Architecture：** 純 `main.js` 變更。新增 `markNoIndentParagraphs(doc, prefs)`：章節載入時與 `applyPreferences` 時，對符合條件的 `p` 加上 `data-elink-no-indent` 屬性；縮排 CSS 改為 `p:not([data-elink-no-indent]) { text-indent: Nem !important; }`。Dart 端、資料庫、l10n 都不改。

**Tech Stack：** foliate-js（`main.js`）、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-65-reader-indent-and-colors/epic.md`「Issue 3 設計決策」（決策 1～9）。

## Global Constraints

- **語言**：文件、註解一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **只改 `main.js`**（及測試、文件）：不新增 `BookReaderPrefs` 欄位、不動資料庫、不動 l10n。
- **排除條件**（決策 1、4）：
  - 置中：`getComputedStyle(p).textAlign` 含 `center`。
  - 沒有文字：`(p.textContent || '').trim() === ''`（空白、只有圖片、只有空白字元）。
  - 不排除靠右對齊。
  - `prefs.textAlign` 有值（使用者選了統一對齊）時，**只**套用「沒有文字」這一條，不判斷置中。
- **何時標記**（決策 3）：章節載入事件（含預讀章節，`isIndexMode` 時不處理）與 `window.applyPreferences`（對 `view.renderer.getContents()` 所有已載入章節重新標記）。`firstLineIndent` 不是數字時：移除既有標記、不做 `getComputedStyle` 計算。
- **`0` 仍是合法值**：`firstLineIndent === 0` 時仍輸出 `text-indent: 0em !important`（用 `typeof … === 'number'` 判斷，不可用 truthy），也要做標記（沒差別但保持邏輯一致）；若實作上 `0` 時略過標記更簡單，需在註解說明理由。
- **`!important` 與 `publisherStyles` 的獨立性不變**：規則仍放在 `publisherStyles` 分支之外。
- **不得影響其他 CSS 與 `paragraphSpacing`、`textAlign` 規則**。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試；完整 `flutter test` 只在最後一個 Task 跑一次（`run_in_background`，只跑一個）。
- **本機沒有 Node**（nvm 沒有安裝任何版本）：`main.js` 的測試台與兩支 `check_*.js` 預設跑不了。若使用者在這個 Issue 期間裝好 Node（`node --version` 能執行），則必須跑 `app/tool/foliate_touch_harness/` 全部情境與兩支檢查腳本，並新增本 Issue 的測試台情境；仍沒有 Node 則不提交跑不了的腳本，在 `epic.md` 記錄未執行。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔；`git add` 一律明確列檔，**不得** `git add app`（會夾帶使用者擱置的 `app/android/gradle.properties`）。
- **Commit**：不加 `Co-Authored-By`；結尾加 `Claude-Session: https://claude.ai/code/session_019bmfxQJ1gaKoHGoWH7gJwD`。每個 Task 一個 commit。
- **不要提交** `app/android/gradle.properties`。
- **計畫與實作同分支同 PR**，不另開文件分支。

## Review Focus

1. **閃爍。** 標記晚於顯示，章節會先縮排、再消失。→ 在 `load` 事件內同步標記；WAVE 用探針書觀察。
2. **新章節與預讀章節漏標。** 只在 `applyPreferences` 標記，翻頁到新章節時沒有標記。→ `load` 事件內標記；WAVE 翻到第二章驗證。
3. **偏好切換不重標。** 使用者在面板切換「文字對齊」或縮排開關，已載入章節的標記沒更新。→ `applyPreferences` 對所有已載入章節重標；WAVE 驗證。
4. **使用者統一對齊時誤判。** `p { text-align: … !important }` 會讓 computed 值全部相同；若仍判斷置中，統一選「置中」會讓整本書不縮排。→ `prefs.textAlign` 有值時不判斷置中。
5. **關閉縮排後殘留標記與效能。** 縮排關閉時不得做 `getComputedStyle`，並移除舊標記。
6. **只有圖片的段落與含有文字節點的混合段落。** `textContent.trim() === ''` 對「圖片加文字」的段落為 false（仍縮排，合理）；對只有 `<br>` 的段落為 true（排除）。
7. **對其他規則的影響。** 新增屬性選擇器不得改變 `p` 的其他規則。→ 讀 diff 確認只動縮排那一段。
8. **既有測試。** 若有 Dart 測試掃描 `main.js` 字串（`text-indent`），要更新。→ `grep -rn "text-indent\|first_line_indent" app/test`。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/android/app/src/main/assets/foliate/main.js` | 修改 | `markNoIndentParagraphs`、章節載入與 `applyPreferences` 呼叫、縮排 CSS 改用 `:not([data-elink-no-indent])` |
| `app/tool/foliate_touch_harness/scenario-first-line-indent-exclusions.mjs` | 條件性新增 | 僅在有 Node 時新增並實際跑過 |
| `docs/epics/epic-65-reader-indent-and-colors/*`、`docs/epics.md`、`CONTEXT.md` | 修改 | 決策、工單、狀態、詞條 |

---

### Task 0：提交設計文件與計畫

- [x] **Step 1：** 分支 `epic-65/issue-3-indent-exclusions`（已從 `main` 建立）。
- [x] **Step 2：** 提交 `epic.md`（Issue 3 設計決策、修訂決策 3）、`issues.md`、`docs/epics.md`、`CONTEXT.md`、本計畫（純文件，一個 commit）。不提交 `app/android/gradle.properties`。

### Task 1：`main.js` 標記與 CSS

**Files：** `main.js`；條件性新增測試台情境。

- [ ] **Step 1：** 先讀 `main.js` 的 `buildOverrideCss`（縮排規則一段）、`applyTextConversion` 及其兩個呼叫點（`load` 事件內、`applyPreferences` 內 `getContents()` 迴圈），確認這兩處是合適的掛勾位置；`grep -rn "text-indent\|first_line_indent" app/test` 確認有沒有掃描 `main.js` 字串的 Dart 測試。
- [ ] **Step 2：** 若有 Node（`node --version` 能執行）：先寫測試台情境 `scenario-first-line-indent-exclusions.mjs`，比照 `scenario-vertical-paragraph-spacing.mjs` 的寫法，涵蓋：一般段落縮排、行內置中不縮排、`align="center"` 不縮排、書本 class 置中不縮排、空段落不縮排、只有圖片的段落不縮排、`prefs.textAlign` 有值時置中段落也縮排（但空段落仍排除）、縮排關閉時沒有 `data-elink-no-indent` 屬性、`firstLineIndent: 0` 時 `text-indent` computed 為 `0px`；先確認紅燈（目前沒有排除邏輯）。沒有 Node 則跳過本步驟，改以 Step 5 的探針書驗證。
- [ ] **Step 3：** 實作 `markNoIndentParagraphs(doc, prefs)`：

  ```js
  /**
   * 標記不該縮排的段落（epic-65 Issue 3）：實際顯示為置中的 p，以及沒有文字的 p
   * （空白、只有圖片）。縮排 CSS 以 :not([data-elink-no-indent]) 跳過它們。
   * 使用者選了「文字對齊」（prefs.textAlign 有值）時，所有 p 都被 App 強制成同一種
   * 對齊，computed 值不再反映書本原貌，只排除沒有文字的段落。
   * 縮排關閉時移除標記、不做 getComputedStyle 計算。
   */
  function markNoIndentParagraphs(doc, prefs) {
    const paragraphs = doc.querySelectorAll('p')
    if (typeof prefs.firstLineIndent !== 'number') {
      for (const p of paragraphs) p.removeAttribute('data-elink-no-indent')
      return
    }
    const skipCentered = !prefs.textAlign
    const win = doc.defaultView
    for (const p of paragraphs) {
      const empty = (p.textContent || '').trim() === ''
      const centered = skipCentered && win.getComputedStyle(p).textAlign.includes('center')
      if (empty || centered) p.setAttribute('data-elink-no-indent', '')
      else p.removeAttribute('data-elink-no-indent')
    }
  }
  ```

  （草案，以實際程式為準。）縮排 CSS 改為 ``p:not([data-elink-no-indent]) { text-indent: ${prefs.firstLineIndent}em !important; }``，並更新該段註解（刪除「含置中、空白、只含圖片的段落」的舊說明，改寫成新規則）。在 `load` 事件（`isIndexMode` 之後）呼叫 `markNoIndentParagraphs(doc, <目前生效的偏好>)`，並在 `applyPreferences` 對 `view.renderer.getContents()` 逐一重新標記。「目前生效的偏好」需用既有的「最後一次完整套用的偏好物件」變數，不要新增第二份狀態；先確認 `load` 事件觸發時該變數已有 `initialPrefs` 的值。
- [ ] **Step 4：** 若有 Node：跑 Step 2 的情境確認綠燈，再跑 `app/tool/foliate_touch_harness/` 的 `run-all.mjs` 確認既有情境沒壞。沒有 Node 則跳過。
- [ ] **Step 5：** 探針書。用 scratchpad 目錄建立 `sample_indent_exclusions.epub`（不進版控）：多章節（至少 2 章，驗證翻章）；章節 1 含一般段落、行內 `style="text-align:center"`、`align="center"`、書本 class `.c { text-align:center }`、空 `<p></p>`、`<p><br/></p>`、只有 `<img>` 的 `<p>`；章節 2 含一般與置中段落；另做一個直排版本。用 `adb push` 放到裝置。
- [ ] **Step 6：** `flutter analyze`；`flutter test test/reader/foliate_reader_view_test.dart`（若 Step 1 找到掃描 `main.js` 字串的測試則一併更新並跑）；commit（明確列檔）。

### Task 2：收尾

- [ ] **Step 1：** `epic.md` 開發記錄；`issues.md` Issue 3 狀態；`docs/epics.md` 備註；`CONTEXT.md` 詞條已於 Task 0 更新。
- [ ] **Step 2：** 驗收：`git diff main --stat -- app/lib app/android` 只有 `main.js`（以及條件性的測試台情境）；`grep -n "data-elink-no-indent" main.js` 有標記、移除、CSS 三處。
- [ ] **Step 3：** `flutter analyze`；兩個 `check_*.js`（先 `node --version`，能執行就跑，不能才記錄未執行）；完整 `flutter test`（`run_in_background`，只跑一個）。
- [ ] **Step 4：** 程式審查（報告存 `reviews/review-code-issue-3.md`，不進版控）。
- [ ] **Step 5：** WAVE 真機抽驗，用探針書：(1) 開縮排 2 字：一般段落縮排；行內置中、`align="center"`、class 置中的段落**都不縮排**且維持置中；空段落與只有圖片的段落沒有偏移。(2) 翻到第二章：同樣規則，不閃爍（沒有先縮排再消失）。(3) 在面板拖縮排滑桿到 4 字：置中段落仍不受影響、沒有被擠成多行。(4) 關閉縮排開關：全部恢復書本原貌。(5) 在「呈現」分頁選「文字對齊：置中」：所有有文字的段落依統一對齊顯示且仍有縮排規則作用（接受此組合的視覺結果）；再改回「靠左」。(6) 直排探針書重做 (1)(3)。(7) 開一本長篇真實 EPUB（段落很多的章節），翻頁與切換縮排時沒有明顯卡頓。(8) 離開重開，設定保留。
- [ ] **Step 6：** 開 PR；PR 開出後把 Issue 3 的狀態同步。
