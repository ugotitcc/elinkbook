# Epic 27 Issue 4 程式碼審查報告

**審查對象：** commit `fe42dd7`＋`b898d81`（分支 `feat/epic-27-issue-4`，worktree `.worktrees/epic-27-issue-4`），對照基準 `main`（`226e53c`）
**審查目標：** 審查「`_handleSaveAsPreset()` 補上 repository 為 null 與例外攔截的使用者可見提示」實際程式碼變更是否忠實對應 `plans/plan-issue-4.md` 與 `issues.md` Issue 4 的驗收標準，並驗證不引入回歸。
**審查標準：** 計畫對齊度、程式碼品質、`mounted`/`context` 使用時機正確性、測試有效性（含實際執行 `flutter analyze`／`flutter test`，並比對 base／head 兩邊全專案測試結果）。
**審查狀態：** ✅ **通過（Ready to merge）**（0 Critical / 0 Important / 3 Minor）

---

## 1. 優點與亮點 (Strengths)

1. **實作與計畫逐字一致**：`app/lib/screens/reader_screen.dart:774-832` 的最終程式碼與 `plan-issue-4.md` Step 3＋Step 7 合併後的目標程式碼完全相同（含中文註解文字），未發現任何未經說明的偏離。
2. **`mounted` 判斷正確依 `await` 邊界分流**：`repository == null` 分支（無任何前置 `await`）不做 `mounted` 判斷即用 `context`，合乎計畫規劃；`catch` 分支則先 `debugPrint` 再 `if (!mounted) return;` 才用 `context`，與計畫規則一致。
3. **SnackBar 慣例正確比照 `remote_server_list_screen.dart:151-159`**：`ScaffoldMessenger.of(context).showSnackBar(SnackBar(key: ...))` 寫法一致，未引入新元件。
4. **測試假物件範圍精準**：`_ThrowingLayoutPresetRepository`（`reader_screen_test.dart`）只覆寫 `insert()`，`listAll()`／`replace()`／`delete()` 均未動，確保 `initState()` 內的 `_loadLayoutPresets()` 不受影響——已用實際測試執行驗證此假設成立。
5. **`pumpReaderScreen()` helper 向後相容確認無誤**：兩個新具名參數皆有預設值，現有 7 個呼叫點逐位元組行為不變。
6. **測試真正驗證「失敗模式」而非只驗證 Key 存在**：
   - null-repository 測試額外斷言 `layout_preset_name_dialog_field` **findsNothing**，明確區分「靜默失敗被提示取代」與「誤開對話框」兩種不同語意，並斷言 `tester.takeException()` 為 `isNull`。
   - 例外測試走完整 UI 互動（點擊開啟→輸入名稱→點擊確認）觸發真正的 `repository.insert()` 拋錯，貼近真實使用者操作路徑，而非直接呼叫私有方法。
7. **既有 7 則同 group 測試斷言完全未變**，新測試以插入方式加入，不影響既有測試。
8. **範圍嚴格受控**：diff 只涉及 `reader_screen.dart`、對應測試檔、計畫 checkbox 更新，無越界修改。
9. Commit message 格式正確：`fix(epic-27): Issue 4——...`。

---

## 2. 實際驗證結果

| 檢查項目 | 執行方式 | 結果 |
| :--- | :--- | :--- |
| `flutter analyze`（head `b898d81`） | worktree 內執行 | ✅ **No issues found!** |
| `flutter test test/screens/reader_screen_test.dart`（head） | worktree 內執行 | ✅ **169/169 全數通過**，含新增 2 則測試；`debugPrint` 例外訊息（`另存為新預設集失敗：Exception: 模擬 insert 失敗（測試用）` + stack trace）於 log 中正確輸出 |
| 全專案 `flutter test`（base `226e53c`） | worktree 內背景執行 | ✅ **1647 項全數通過** |
| 全專案 `flutter test`（head `b898d81`） | worktree 內背景執行 | ✅ **1649 項全數通過** |

Head 較 base 多 2 項測試，與計畫 Step 10 預期（「多 2 項，Step 1、Step 5 新增的 2 則測試」）完全吻合，零回歸。

---

## 3. Issues

### Critical (Must Fix)
無。

### Important (Should Fix)
無實質發現。

### Minor (Nice to Have)

1. **`catch (e, stackTrace)` 攔截範圍寬泛**
   - 檔案：`app/lib/screens/reader_screen.dart:826`
   - 說明：會攔截所有 `Exception`／`Error`，包含 `StateError`／`AssertionError` 等一般不建議吞掉的嚴重錯誤。
   - 影響評估：這是計畫與 `issues.md` Issue 4 明確要求的「整個方法本體包一層 try/catch」防禦性設計，是刻意的「提高可觀測性優先於精確分類」權衡，非疏忽，故不建議現在改動；僅供未來若要精確化錯誤分類時參考。

2. **錯誤 SnackBar 直接顯示原始例外字串**
   - 檔案：`app/lib/screens/reader_screen.dart:828`
   - 說明：`content: Text('另存為新預設集失敗：$e')` 會把含 `Exception:` 前綴的原始例外字串直接顯示給終端使用者，UX 文案不夠友善。
   - 影響評估：這是計畫 Step 7 明確指定的內容（`plans/plan-issue-4.md:459`），非實作偏離，僅供未來 UX 優化時參考，不影響本次驗收。

3. **例外測試未斷言 `_layoutPresets` 維持原狀**
   - 檔案：`app/test/screens/reader_screen_test.dart`（「寫入過程拋出例外時顯示提示，不被靜默吞掉」測試）
   - 說明：測試只驗證 SnackBar 出現與無未捕捉例外，未額外斷言 insert 失敗後 `_layoutPresets` 沒有被異常寫入。
   - 影響評估：超出計畫明訂的驗收範圍，屬於錦上添花的建議，非缺陷。

---

## 4. Recommendations

- 無需修改即可合併；上述 Minor 項目均為觀察性建議，可留待後續 Issue 或使用者體驗優化時處理，不建議為此延遲本 Issue。
- 若未來使用者仍於真機回報同樣症狀，`debugPrint` 訊息應已足夠協助判斷是 `repository == null`（需再往上追查建構時序，`issues.md` 已記載為後續工單）還是其他例外，屬計畫已言明的範圍外事項。

---

## 5. Assessment

**Ready to merge？** ✅ **Yes**

**Reasoning：** 程式碼變更精準對應計畫與 `issues.md` Issue 4 驗收標準，`mounted`／`context` 使用時機正確、SnackBar 慣例與既有程式碼一致；`flutter analyze` 全專案乾淨，base／head 全專案 `flutter test` 分別為 1647／1649 項全數通過（零回歸，精準符合預期新增 2 項），新增測試確實驗證「失敗模式被使用者可見提示取代」而非僅驗證 Key 存在。未發現 Critical 或 Important 等級問題，3 項 Minor 建議均為觀察性、非阻斷合併之缺陷。
