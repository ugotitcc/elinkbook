# Issue 26：harness `scenario-cross-mechanism-tap-boundary.mjs` 失敗診斷與穩定化 Plan（輕量）

**Goal：** 讓 `app/tool/foliate_touch_harness/scenario-cross-mechanism-tap-boundary.mjs` 在這台 Windows 上穩定通過，且仍能抓到「選取收尾保護期」的兩個回歸（保護期內不折疊、保護期後折疊）與「時鐘原點錯位」這個原始 bug；不改產品的 `main.js`。

> 修訂記錄（2026-11-13，依 `reviews/review-plan-issue-26.md`）：變異 (a) 改用負值門檻（`+10000` 讓差值約 −9900，門檻改 0 仍成立）；刪除情境 C（只是比 Chromium 自己的兩個時鐘，沒碰產品程式，時鐘混用這個原始 bug 改由情境 B 守護，變異 (d) 失敗的是情境 B）；補 `resetHarnessEvents`、`performance.now.bind(performance)` 與還原方式；補兩種 shell 的指令；補「門檻數值本身沒被驗證」的限制。

## 已定共識（2026-11-13 grilling，Q1～Q4）
- **只修測試場景，不動產品：** 不改 `main.js` 的 `SELECTION_RELEASE_GUARD_MS = 150`（註解寫明尚未經真機校準，是另一件事）。
- **修法選 B（時間差可控）：** 在場景裡把 iframe 的 `performance.now` 暫時換成「真實時間 + 10 秒」（保護期必定生效）或「真實時間 − 10 秒」（保護期必定已過），分別驗證兩條分支。**不再驗證「150 ms 在實際時間上剛好夠用」**，情境 A 用「＋10 秒」時差值約 −9900 ms，任何非負門檻都成立，所以門檻數值本身不會被驗證（那要靠真機校準）。原始的「時鐘原點錯位」bug（iframe 時鐘與最外層相差約 850 ms）改由**情境 B** 守護：若記錄時間誤用最外層時鐘，差值恆為負、保護期恆生效，期望折疊的情境 B 會失敗。
- **約 100 ms 的延遲不追根究底：** 只記錄在報告；若日後懷疑真機也有類似的觸控回應變慢，另立項目。
- **驗收：** (a) 單獨跑 `tap-boundary` 連續 30 次全過；(b) 整個 `run-all.mjs` 連續 3 次沒有失敗；(c) 人為把 CDP 觸控往返拖慢（例如每個 `client.send` 加 200 ms）時仍通過，證明不再受延遲影響。

## 現況與已查證的事實（2026-11-13 量測，診斷腳本為拋棄式，未進版控）
- 失敗是**系統性**的，不是看板寫的「負載相關偶發」：單獨跑，修改前（還原 `main.js`）8/11 失敗、修改後 18/19 失敗；與 Issue 24 無關。
- 場景流程：注入選取 → `cdpTap`（`touchStart`、按住 80 ms、`touchEnd`）→ 要求選取仍在。`main.js` 的 `mousedown` 監聽器（`main.js` 約第 1900 行）在「`evt.timeStamp - lastNonCollapsedSelectionAtMs ≤ 150`」時 `preventDefault`；`lastNonCollapsedSelectionAtMs` 由 `selectionchange` 處理用 `doc.defaultView.performance.now()` 記錄。
- **注入選取後立刻按下，`Input.dispatchTouchEvent touchStart` 往返約 86～103 ms**；注入後等 500 ms 再按、或沒有選取時只要約 3 ms；空白頁 2～12 ms。所以選取到 `mousedown` 的間隔變成 150～195 ms，超過保護期。按住 80 ms 時 1/14 通過（間隔 90～196 ms）；按住 20 ms 時 14/14 通過（間隔 29～145 ms，最高一次離 150 只差 5 ms）。
- 重試 5 次沒用：每次嘗試帶著同樣的約 100 ms 延遲。
- 那約 100 ms 花在哪**未查明**：`onSelectionChanged` 回呼在注入後 1～9 ms 內送出，主視窗無 longtask，所以不是 JS 回呼本身。
- 試過「先按下、再注入選取、立刻放開」：選取維持，但 `mousedown` 比選取處理早約 99 ms，保護期根本沒觸發，是靠運氣通過，**不採用**。
- 原始 bug 背景（`main.js` 註解）：iframe 的時鐘與最外層頁面的時鐘原點相差近 850 ms，若混用會讓「時間差 ≤ 門檻」恆成立、保護期形同虛設。

## Tasks
- [x] **Task 1：重寫場景（先確認會紅再轉綠）。** `scenario-cross-mechanism-tap-boundary.mjs` 改為兩個情境：
  - **情境 A（保護期內快速點擊，選取應維持）：** `resetHarnessEvents(page)` 清空事件；在 iframe 內把 `performance.now` 換成 `原值 + 10000`；注入選取；**等 `onSelectionChanged` 事件出現**（保證 `lastNonCollapsedSelectionAtMs` 已被記錄；輪詢上限約 2 秒，逾時明確失敗）；再 `cdpTap`；斷言選取維持。
  - **情境 B（保護期已過，選取應折疊）：** **先 `resetHarnessEvents(page)`**（否則會立刻命中情境 A 殘留的舊事件）；換成 `原值 − 10000`；同樣流程；斷言選取被折疊（證明快速點擊分類機制本身沒被卡死，也守護時鐘混用 bug）。
  - **換時鐘的寫法：** `const orig = win.performance.now.bind(win.performance)`（不綁定 `this` 會 `Illegal invocation`）；`win.performance.now = () => orig() + OFFSET`；還原用 `delete win.performance.now`（移除實例上的覆寫，露出原型上的原生方法），放在 `finally`，且兩個情境之間也要還原再換，避免累加漂移。
  - 不再用重試迴圈與固定 `setTimeout(250)`；不要情境 C。
  - 更新檔內過時註解（原「已知計時脆弱性」段與對 `reviews/review-code-issue-1.md` Important #1 的引用）。
- [x] **Task 2：變異驗證（證明新場景能抓到回歸）。** 暫時修改 `main.js`（每次驗完還原，不進 commit；每項用 `diff` 對照乾淨版確認變異真的生效），預期失敗的情境如下：
  - (a) 把 `SELECTION_RELEASE_GUARD_MS` 改成 `-20000`（**不能改 0**：情境 A 的差值約 −9900，`≤ 0` 仍成立）→ **情境 A 必須失敗**（保護期失效，選取被折疊）。
  - (b) 把 `mousedown` 監聽器的 `preventDefault` 拿掉 → **情境 A 必須失敗**。
  - (c) 把保護期條件改成恆真 → **情境 B 必須失敗**（選取永遠折疊不了）。
  - (d) 把 `lastNonCollapsedSelectionAtMs` 的記錄改用最外層 `window.performance.now()`（時鐘混用，原始 bug）→ **情境 B 必須失敗**（差值恆為負，保護期恆生效）；情境 A 仍會通過。
- [x] **Task 3：驗收。** (a) 單獨跑 30 次；(b) 在 `app/tool/foliate_touch_harness` 下 `node run-all.mjs` 連續 3 次（這台的 `node` 要先把 pnpm 內建的 Node 排到 PATH 前面：bash 用 `export PATH="$PNPM_HOME:$PATH"`，PowerShell 用 `$env:PATH = "$env:PNPM_HOME;$env:PATH"`）；(c) 暫時在 `client.send` 前後各加 200 ms 延遲（拋棄式、不進 commit）跑場景，須仍通過。
- [x] **Task 4：報告與收尾。** 寫 `issue-26-report.md`：量測表、根因（約 100 ms 的觸控回應延遲，原因未查明）、為什麼舊場景系統性失敗、新場景設計取捨、變異驗證結果、驗收結果、限制；**更正 `issues.md` 第 26 列的描述**（原寫「負載相關偶發」，實測為系統性的約 100 ms 延遲）；更新 Issue 24 報告第 4.1 節的註記；`app/tool/foliate_touch_harness/README.md` 對此場景的說明若有過時處一併更正。`node tool/check_l10n_hardcoded_strings.js` 不涉及；`flutter analyze` 與全套 `flutter test` 本 Issue 不涉及 Dart，仍在合併前確認一次。

## 過關條件
1. 新場景單獨連續 30 次全過；`run-all.mjs` 連續 3 次沒有失敗；人為拖慢 CDP 往返時仍通過。
2. 變異驗證 (a)～(d) 全部使新場景失敗，且失敗的情境與預期一致（(a)(b) 為情境 A，(c)(d) 為情境 B）。
3. `main.js` 與其他產品檔 0 行改動。
4. 報告誠實記載：約 100 ms 延遲原因未查明；新場景不再驗證實際時間上 150 ms 是否夠用。
5. `issues.md` 第 26 列描述已更正。

## Review Focus
1. **有分辨力：** 場景不能只是「改到一定會過」。變異驗證要證明保護期被移除、被反向、或時鐘混用時都會失敗，而且**失敗的情境要與預期一致**（見 Task 2）；每個變異都要用 `diff` 證明確實套用。
2. **競態：** 情境 A 必須等到 `lastNonCollapsedSelectionAtMs` 已被記錄（`onSelectionChanged` 事件）才送觸控，否則 `mousedown` 可能早於記錄而保護期沒生效；等待要有上限並明確失敗。
3. **還原：** 被換掉的 `performance.now` 必須在 `finally` 還原，不得影響後續場景或同一頁面其他計時。
4. **取捨：** 情境 A、B 不再驗證實際時間差，這是有意的；**門檻數值本身（150 ms）不會被任何情境驗證**（A 用 +10 秒、B 用 −10 秒），真實時間下夠不夠用要靠真機校準（`main.js` 註解已寫），報告要寫明。
5. **不要順手改產品：** 即使發現那約 100 ms 延遲可能是產品行為，也只記錄，不在本 Issue 修。

## 待人類確認
1. 計畫是否同意？同意後我從 Task 1 開始（只用 harness，不動平板、不動 Windows 桌面視窗；Puppeteer 會開 headless Chromium）。
