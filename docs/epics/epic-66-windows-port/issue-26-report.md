# Issue 26 報告：harness `scenario-cross-mechanism-tap-boundary.mjs` 失敗診斷與穩定化

日期：2026-11-13　分支：`fix/epic-66-issue-26-tap-boundary-flake`　計畫：[plan-issue-26.md](plans/plan-issue-26.md)

## 1. 結論
- 這個場景在這台 Windows 上的失敗是**系統性的**，不是看板原本寫的「負載相關偶發」。原因是注入選取後立刻送出觸控，CDP 往返被拖慢約 100 ms，使「選取 → `mousedown`」的真實間隔超出 150 ms 保護期。
- 只修測試、**不動產品**（`main.js` 與其他產品檔 0 行改動）：把 iframe 的 `performance.now` 暫時換成「原值 ± 10 秒」，讓保護期兩條分支（生效／已過）由場景決定、與 CDP 延遲無關。
- 新場景：單獨連跑 30/30 通過；人為每個 CDP 呼叫前後各加 200 ms 仍 3/3 通過；`run-all.mjs` 連跑 3 次各 148 PASS、0 FAIL。變異驗證 4 項全部使場景失敗，且失敗的情境與預期一致。

## 2. 診斷（量測，診斷腳本為拋棄式、未進版控）
| 量測 | 結果 |
|---|---|
| 舊場景單獨跑（還原 `main.js`，與 Issue 24 無關） | 8/11 失敗 |
| 舊場景單獨跑（含 Issue 24 修改） | 18/19 失敗 |
| 注入選取後立刻 `touchStart` 往返 | 約 86～103 ms |
| 注入後等 500 ms 再按、或沒有選取時的往返 | 約 3 ms |
| 空白頁的往返 | 2～12 ms |
| 選取 → `mousedown` 間隔（按住 80 ms） | 150～195 ms，1/14 通過 |
| 選取 → `mousedown` 間隔（按住 20 ms） | 29～145 ms，14/14 通過（最高一次離 150 只差 5 ms） |

- 舊場景的 5 次重試沒有用：每次嘗試都帶著同樣的約 100 ms 延遲。
- 試過「先按下、再注入選取、立刻放開」：選取維持，但 `mousedown` 比選取處理早約 99 ms，保護期根本沒被觸發，是靠運氣通過，**不採用**。
- `onSelectionChanged` 回呼在注入後 1～9 ms 內送出、主視窗沒有 longtask，所以延遲不是 JS 回呼本身；**約 100 ms 花在哪裡未查明**（見第 6 節）。

## 3. 新場景設計
- **情境 A（保護期內，選取應維持）**：iframe 的 `performance.now` 換成「原值 + 10000」→ 注入選取 → 等 `onSelectionChanged`（保證 `lastNonCollapsedSelectionAtMs` 已記錄，上限 2 秒，逾時明確失敗）→ `cdpTap` → 選取應維持。
- **情境 B（保護期已過，選取應折疊）**：先清事件佇列，換成「原值 − 10000」，同樣流程 → 選取應被折疊。證明快速點擊分類機制沒被卡死，**同時守護原始 bug**（記錄時間誤用最外層時鐘：兩個時鐘原點差近 850 ms，差值恆為負、保護期恆生效）。
- 換時鐘用 `performance.now.bind(performance)`（不綁 `this` 會 `Illegal invocation`）；還原用 `delete win.performance.now`，放在 `finally`，兩情境之間也先還原再換，避免累加漂移。
- 不再用重試迴圈與固定 `setTimeout(250)`。**刪除原計畫的情境 C**（審查指出它只是在比 Chromium 自己的兩個時鐘，沒碰產品程式）。
- 更新檔頭註解，移除過時的「已知計時脆弱性」段與對 `reviews/review-code-issue-1.md` Important #1 的引用。

## 4. 變異驗證（暫時改 `main.js`，驗完還原，`git status` 確認無殘留）
| 變異 | 預期 | 實際 |
|---|---|---|
| (a) `SELECTION_RELEASE_GUARD_MS = -20000`（不能用 0，A 的差值約 −9900） | 情境 A 失敗 | **A FAIL**（`after.isCollapsed=true`）、B PASS |
| (b) 拿掉 `mousedown` 的 `preventDefault` | 情境 A 失敗 | **A FAIL**、B PASS |
| (c) 保護期條件改為恆真 | 情境 B 失敗 | A PASS、**B FAIL**（`after.isCollapsed=false`） |
| (d) 記錄時間改用最外層 `window.performance.now()` | 情境 B 失敗 | A PASS、**B FAIL** |

- (a)(c)(d) 以 `diff` 證明變異生效。
- (b) 的第一次嘗試其實**沒套上**（多行字串比對遇到 CRLF 行尾，腳本斷言失敗、沒有 diff），那次 PASS 不算數；改用行號替換重做後才得到上表結果。重做時 `sed -i` 把該檔行尾改成 LF，所以 `diff` 顯示全檔不同，內容只動了那一行；驗完用乾淨副本還原，`main.js` 與 git 一致。

## 5. 驗收
- 單獨跑新場景連續 30 次：**30/30 通過**。
- 人為拖慢（拋棄式複本，每次 `touchStart` 前後各加 200 ms，不進版控）：**3/3 通過**。
- `run-all.mjs` 連續 3 次：**每次 148 PASS、0 FAIL**（先前是 147 PASS、1 FAIL）。
- `main.js` 等產品檔 0 行改動；本 Issue 不涉及 Dart，`flutter analyze`／全套 `flutter test` 於合併前確認一次。

## 6. 限制與未解
- **門檻 150 ms 本身不被任何情境驗證**（A 用 +10 秒、B 用 −10 秒）。真實時間下 150 ms 夠不夠用要靠真機校準（`main.js` 註解已寫明）。
- **注入選取後約 100 ms 觸控回應變慢的原因未查明**，也不知道真機是否有同樣現象。若日後懷疑，另立項目；本 Issue 不改產品。
- 不能確認為什麼 Issue 26 登記時（單跑 4 次皆過）與今天（多數失敗）行為不同，可能與重開機後機器狀態有關，**未驗證**。
- 看板第 26 列原本的描述（「負載相關偶發」）已更正；Issue 24 報告第 4.1 節已加註記。
