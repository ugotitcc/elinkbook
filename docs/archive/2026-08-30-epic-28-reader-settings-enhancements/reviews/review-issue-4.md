# Epic 28 Issue 4 程式碼審查報告

**審查對象：** commit 範圍 deb1359..41c147b（分支 `epic-28-issue4`，2 個 commit：`d7c8a5b` 資料層修正、`41c147b` UI 圖示/重置按鈕）
**審查目標：** 審查「`ReaderSettingsSheet` 5 個版面欄位停止無條件具現化覆寫書本原生 CSS」實際程式碼變更是否忠實對應 `plans/plan-issue-4.md` 與 `issues.md` Issue 4 的分析與範圍界定。
**審查標準：** 計畫對齊度、程式碼品質（單一權責、邊界情境）、與同一 Epic 內 Issue 3（版面設定預設集）的互動安全性、測試有效性（實際執行 `flutter test`／`flutter analyze`，非僅閱讀程式碼推測）。
**審查狀態：** 已完成（本人親自逐行核對＋實機執行測試驗證，未派出子代理）

---

## 1. 優點與亮點 (Strengths)

1. **與計畫逐字對齊，零範圍外變更**：`git diff --stat` 顯示本次變更只觸及計畫宣告的 3 個檔案（`reader_settings_sheet.dart` +94 行、`reader_screen_test.dart` +12/-6、`reader_settings_sheet_test.dart` +195 行）。逐一比對 `reader_settings_sheet.dart` 的 diff（狀態欄位、`initState()`/`didUpdateWidget()`、`_currentDraft` getter、5 個 `_buildSliderRow` 呼叫點、`_buildSliderRow` 方法本體）與 `plan-issue-4.md` Task 1/Task 2 給出的程式碼片段，**逐字相符**，包含我在撰寫計畫時特別要求把 `else if (isOverridden)` 改寫為 `else if (isOverridden == true)`（避免依賴 collection-if 巢狀 else 分支的 null 型別提升）這個細節也如實採用。

2. **範圍界定精準，未誤觸邊界欄位**：計畫明確要求上/下/左/右邊界 4 個欄位的呼叫點「維持逐位元組不變」——diff 中完全沒有這 4 個呼叫點的異動，且新增測試「5 個受本 Issue 影響欄位皆為 null 時...邊界 4 個欄位不受影響」明確斷言邊界欄位不出現 `_unset_indicator`/`_reset`，正面驗證了範圍界定確實生效，不是單純沒改到而已。

3. **核心 bug 修法正確且完整**：`_currentDraft` 的 5 個欄位皆正確依對應 `_XOverridden` 旗標決定送出具體數字或 `null`；5 個 `_buildSliderRow` 呼叫點的 `onChanged` 閉包皆正確補上 `_XOverridden = true;`（逐一核對 5 處，無遺漏、無寫錯欄位名稱這種複製貼上常見錯誤）；`initState()`／`didUpdateWidget()` 兩處旗標初始化邏輯逐位元組相同，維持既有「外部 prefs 變動時重新同步 UI state」的既有慣例不變。

4. **測試設計精準命中原始回報症狀**：Task 1 第一則新測試（「只切換『顯示頁首』開關」）直接對應 `issues.md` 描述的真實回報場景，是最有說服力的回歸測試；「依序調整 5 個受影響欄位…不互相污染」這則測試巧妙地在單一測試內同時證明「圖示正確切換」與「欄位互不污染」兩件事，測試設計效率高；`letterSpacing`／`fontSize` 兩個重置測試分別涵蓋了「直接透傳」與「`_toMultiplier` 倍率換算」兩種不同程式碼路徑，不是每個欄位都測、但挑選的兩個代表性欄位涵蓋了關鍵性的邏輯分支差異，是合理的測試取捨。

5. **誠實修正過時註解，而非略過**：`reader_screen_test.dart` 那則會被本次修復影響「說明文字準確性」（但不影響斷言本身）的既有測試註解，確實依計畫 Task 1 Step 6 的要求同步更新，並保留了對 `EpubPageEstimator` 獨立 fallback 機制的正確技術說明，避免未來讀者誤以為行高也還被具現化。

---

## 2. 問題與疑慮 (Issues)

實際於本機（非隔離 worktree，因為 `epic-28-issue4` 已存在專屬 linked worktree `U:\MyDeveloper\AI\elinkBook\.worktrees\epic-28-issue4`，直接在該既有 worktree 內執行，未動到 `main` checkout）執行：
- `flutter analyze`：**"No issues found!"**
- `flutter test test/screens/reader_settings_sheet_test.dart`：**49/49 全數通過**（含本次新增 6 則）
- `flutter test test/screens/reader_screen_test.dart --plain-name "頁尾"`：**18/18 全數通過**（含註解被更新的那一則）
- `flutter test`（全專案）：**1276/1276 全數通過**，含 Epic 28 Issue 3（版面設定預設集）的全部既有測試

未發現任何 Critical 或 Important 等級問題。

### Critical (必須修正)
*無*

### Important (應該修正)
*無*

### Minor (建議與注意事項)

#### 【Minor #1】本次修復會讓「另存為新預設集」／「複製設定到其他書籍」把 `null`（未覆寫）狀態透過全列覆寫語意傳播出去，屬於未被計畫或工單明確記錄的跨 Issue（3／4）互動後果（**已於 commit `929b4c8` 採納修正**）
- **說明：** `BookReaderPrefs.reflowableEpubFields()`（`book_reader_prefs.dart:375-390`）對這 5 個欄位是直接透傳，不做任何 `?? 預設值`；`onSaveAsPreset(_currentDraft)`（`reader_settings_sheet.dart:735`）與 `_handleApplyFromBook`（`reader_screen.dart:874-`）皆會把（可能含 `null` 的）`BookReaderPrefs` 原封不動存進 `LayoutPreset.prefs`／直接寫入目標書籍；而 `BookReaderPrefsRepository.save()`／`saveMultiple()`（`book_reader_prefs_repository.dart:25-50`）的既有語意是 **`INSERT OR REPLACE`「整列覆寫」**（該檔案自己的 docstring 已明確記載）。也就是說：本次修復生效後，若使用者存一個「只調整過字級」的預設集（其餘 4 個受影響欄位仍是 `null`），套用到另一本原本已經有自訂行高的書籍時，該書的行高會被整列覆寫清空回 `null`（改為跟隨該書自己的原生樣式），而不是維持原本的自訂行高不變。
- **這不是本次修復引入的新缺陷**——「套用預設集＝整列覆寫」是 Epic 28 Issue 3 既有、刻意的設計（docstring 原文即為證），本次修復只是改變了「哪些欄位在什麼情況下會是 `null`」，而 `null` 在整列覆寫語意下本來就會清空目標欄位，這個特性從 Issue 3 上線那天就存在。而且新行為（未觸碰的欄位不強制帶入某個 UI 預設數字）比修復前的行為（未觸碰的欄位會強制帶入當時滑桿顯示的預設數字，例如行高 1.0）更符合直覺、更不容易在使用者沒有察覺的情況下污染其他書籍的設定——可以視為一次連帶的正面改善，而非退步。
- **建議：** 不需要在本 Issue 範圍內處理（全專案測試已證實現有 Issue 3 相關測試皆通過、無回歸），但建議之後找個地方（例如 `onSaveAsPreset`／`_currentDraft` 上方補一句 dartdoc，或在 `issues.md` Issue 4 完成後的備註補述）明確記下這個「預設集只會忠實保存使用者實際調整過的欄位；套用時對方書籍未被此預設集涵蓋到的欄位會回到該書自己的原生樣式」的行為，避免未來有人真機測試時看到「套用預設集後某本書的行高變了」誤以為是回歸，浪費時間重新排查一次已知的既有設計。
- **後續狀態：** 已採納，於 `_currentDraft` getter 上方補上 dartdoc（commit `929b4c8`），逐字說明「整列覆寫」語意與本次修復疊加後的行為，`flutter analyze`／`test/screens/reader_settings_sheet_test.dart`（49/49）重跑皆通過，純文件註解變更、無邏輯異動。

#### 【Minor #2】圖示/重置按鈕的實際視覺效果尚未經真機或截圖驗證
- **說明：** 與 Issue 1 的先例相同，`flutter test` 純 widget test 環境可以驗證 `Key` 是否存在、`Tooltip`/`Icon`/`IconButton` 邏輯分支是否正確渲染出對應元件樹，但無法驗證 `Icons.block` 在實際畫面上是否如使用者所期待的「圈圈裡一條斜線」視覺效果在深色/淺色主題、E-Ink 高對比模式下皆清晰可辨識，也無法驗證 `iconSize: 18`／`VisualDensity.compact` 這組數值在真實螢幕密度下是否會讓重置按鈕的可點擊熱區過小。
- **建議：** 合併前後找機會在模擬器或真機上開一次版面設定畫面，目視確認圖示辨識度與點擊熱區大小，非阻塞項目。

---

## 3. 實作建議 (Recommendations)

1. 採納 Minor #1 的建議，找機會在程式碼或 `issues.md` 補一句話記錄「預設集套用時，未涵蓋欄位會清空回書本原生樣式」這個既有＋本次強化後更明顯的行為，avoid 未來排查成本。
2. 其餘無額外建議——本次變更範圍精簡、與計畫的對齊程度是我目前在本專案審查過的變更中數一數二精準的（開放式的 `else if (isOverridden)` → `else if (isOverridden == true)` 這種計畫撰寫階段就特別交代的實作細節都被逐字採用），可作為後續小範圍 UI 狀態修正型 Issue 的良好參考範本。

---

## 4. 評估結論 (Assessment)

- **是否可合併 (Ready to merge)？** 是
- **評估理由：**
  程式碼變更與 `plan-issue-4.md` 逐字對齊，未發現任何範圍外改動或偏離計畫的設計決策；範圍界定（只處理 5 個真正受影響欄位、明確排除邊界 4 個欄位與「停用書本 CSS」開關）確實在程式碼與測試中如實落實。實際執行 `flutter analyze`（乾淨）與全專案 `flutter test`（1276/1276 全數通過，含本次新增 6 則與 Epic 28 Issue 3 全部既有測試），非僅憑閱讀程式碼推測。深入查證與 Issue 3 預設集功能的互動（`save()`「整列覆寫」語意）後，確認本次修復不會造成任何測試層級的回歸，唯一發現的 Minor #1 是一個值得記錄、但不阻塞合併的跨 Issue 行為說明缺口。剩餘事項皆為 Minor 等級的文件/真機驗證收尾，不構成合併阻礙。
