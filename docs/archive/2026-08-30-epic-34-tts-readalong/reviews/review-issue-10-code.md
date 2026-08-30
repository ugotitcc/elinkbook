# Epic 34 Issue 10 程式審查報告——CBZ 朗讀停用按鈕視覺區隔

**審查範圍：** `bcdaf47b..HEAD`（分支 `feat/epic-34-issue-10-cbz-disabled-icon`）
**審查方式：** `git diff`／`git show` 靜態審閱 + 實際執行 `flutter test test/screens/reader_screen_test.dart`／`flutter analyze`／`dart format` 對照基準版本，全程未變更此 checkout 的工作樹或 HEAD（僅另建立臨時 worktree `bcdaf47b` 供格式化基準比對，審查後已 `git worktree remove`）。
**變更檔案：** `app/lib/screens/reader_screen.dart`（+16/-1）、`app/test/screens/reader_screen_test.dart`（+47）、`docs/epics/epic-34-tts-readalong/issues.md`（勾選驗收標準）、`docs/epics/epic-34-tts-readalong/plans/plan-issue-10.md`（新增計畫檔）。

---

## Strengths

1. **精準對症下藥、範圍極小。** 整個修復只動了兩處程式碼：新增一個 getter（`reader_screen.dart:2696-2709`）+ 一個呼叫點的參數替換（`reader_screen.dart:2261`，`iconColor: _themedFabIconColor` → `_themedTtsDisabledIconColor`）。完全符合計畫 Global Constraints「純視覺調整，不得修改 `TtsController`／`SystemTtsProvider`」與「僅限 CBZ 停用按鈕本身」，`grep` 確認 `TtsMiniPlayer(` 全檔僅兩個呼叫點，非 CBZ 分支（`reader_screen.dart:2271`）維持使用 `_themedFabIconColor` 完全未受影響。
2. **alpha 透明度的架構理由查證屬實。** 計畫與程式碼 doc comment 皆引用「epic-22-reader-theme-integration Issue 4」作為不使用 `Color.withValues(alpha: ...)` 的依據，我實際讀取了同檔案 `_themedFabBackgroundColor` 上方的既有 doc comment（`reader_screen.dart:2678-2690`），內容確實記載「原本沿用 `Colors.black54` 的 54% 透明度……真機電子紙硬體肉眼實測發現，這個『即時運算出來的中間灰』正好落在電子紙灰階抖動渲染最弱的區間，圖示完全無法辨識形狀；改用不透明實色色塊後……」——引用準確，且新增的 `Colors.grey` 確實是完全不透明的實色（`0xFF9E9E9E`），推理站得住腳：alpha 混合產生的顏色是「執行期運算結果」，其抖動渲染行為不可預期；`Colors.grey` 是固定 RGB 值，OS 灰階抖動演算法能穩定處理。這個工程判斷合理，且與 Issue 10 原始 `issues.md` 設計要點第 1 點字面建議（「降低透明度」）的刻意偏離，計畫已明確揭露理由（Global Constraints 第 3 點），屬於有正當理由的偏離，不是隨意繞過規格。
3. **新測試精準複用既有測試模式。** 新測試（`reader_screen_test.dart` 新增段落）與緊鄰在前的既有測試「CBZ 格式提供 ttsProvider 時，TTS 按鈕顯示但為停用狀態」在 `pumpWidget`／`onLayoutResolved`／`FakeTtsProvider` 等建構流程上完全一致，只是多斷言了 `icon.color`，降低了審查與維護的認知負擔。
4. **doc comment 品質高。** 新 getter 的 doc comment 說明了「為何不比照 `_themedFabIconColor` 依 `_isFixedLayout` 分支」（CBZ 恆為固定版面，分支永遠不會走到另一邊，因此故意不加），這是很細緻、避免死碼的判斷，且交代清楚。
5. **驗證確實執行且通過。** 我重跑了 `flutter test test/screens/reader_screen_test.dart`（192 個測試全數通過，含新測試於第 177 項）與 `flutter analyze`（`No issues found!`），與計畫聲稱的結果一致。

---

## Issues

### Critical (Must Fix)

無。

### Important (Should Fix)

無。

### Minor (Nice to Have)

1. **`dart format` 顯示兩個變更檔案「非標準格式」，但這是既有基準狀態，非本次引入。**
   - 檔案：`app/lib/screens/reader_screen.dart`、`app/test/screens/reader_screen_test.dart`
   - 我在基準版本（`bcdaf47b`，另建立臨時 worktree 比對）跑了 `dart format --output=none --set-exit-if-changed`，這兩個檔案在改動前就已經不是目前本機 Dart SDK 版本認定的標準格式（推測是專案釘住的 Dart SDK 版本與本機全域 `dart format` 版本之間的「tall style」格式化規則差異，而非本次改動造成）。本次新增的 `testWidgets(...)` 區塊格式與檔案其餘既有測試風格一致，並未讓問題惡化。
   - 不影響本次審查結論，僅記錄供後續有人整體修一次格式化落差時參考，不需為本 Issue 單獨處理。
2. **新測試中 `expect(icon.color, isNot(Colors.white))` 屬於冗餘斷言。**
   - 檔案：`app/test/screens/reader_screen_test.dart`（新測試倒數第 2、3 行）
   - 緊接著的 `expect(icon.color, Colors.grey)` 已經蘊含「不是 `Colors.white`」，前一行純粹是文件性斷言，無害但技術上多餘。不影響正確性，純風格意見，不需修改。
3. **`Colors.grey`（`0xFF9E9E9E`）尚未經過真機電子紙硬體複測。**
   - 這個修復的動機正是「Issue 9 真機驗收發現顏色不可辨識」，但 `issues.md` Issue 10 的驗收標準與本計畫皆未列「真機再次驗收」項目，只要求 widget test + `flutter analyze`/`flutter test`。實作完全依計畫執行，這不是實作偏離，而是計畫本身在驗收標準設計上的一個可以更嚴謹之處（模擬器/單元測試無法斷言 E-Ink 灰階抖動下 `Colors.grey` 與背景 `Colors.black54` 是否確實清楚可辨）。建議後續若有機會排入真機驗收（可比照 Issue 9 的方式），非本次合併的阻擋條件。

---

## Recommendations

- 若未來要對 `reader_screen.dart`／`reader_screen_test.dart` 執行一次全面 `dart format`，建議另開獨立、非功能性的 Issue／PR 處理，避免和功能性變更的 diff 混在一起難以審查（本次審查已確認此次改動未讓既有落差惡化，不建議在本 PR 順手處理）。
- 若之後有機會取得 Air Reader C／AiPaper Reader C 等 E-Ink 裝置，建議把「CBZ 停用按鈕的 `Colors.grey` 在真機灰階抖動下是否確實與白色圖示可辨」補一次真機檢查，形成 Issue 9→10 這條真機發現鏈的完整閉環（非阻擋項目）。

---

## Assessment

**Ready to merge？** Yes

**Reasoning：** 改動範圍精準對應計畫與 Issue 10 規格，四條驗收標準全數達成；alpha 透明度規避的架構理由經查證屬實且推理合理；新增測試邏輯正確、與既有測試模式一致；`flutter test test/screens/reader_screen_test.dart`（192 項全過）與 `flutter analyze`（`No issues found!`）皆已實際重跑確認無誤。僅有的三項 Minor 備註均為既有基準狀態或風格性意見，不構成合併阻擋條件。
