# Epic 28 Issue 6 程式碼審查報告

**審查對象：** commit 範圍 `e4f64cd..33e61be`（分支 `epic-28-issue-6-book-picker-refactor`，3 個 commit：`6f4ef03` 格線化＋單選/多選統一為選取＋確定按鈕、`fb3a1aa` 新增書名/作者即時搜尋、`33e61be` `reader_screen_test.dart` 補上單選模式的確定按鈕點擊）
**審查目標：** 審查「`LayoutPresetBookPickerScreen` 從純文字 `ListView` 重構為封面格線＋統一選取/確定機制＋即時搜尋」的實際程式碼變更是否忠實對應 `plans/plan-issue-6.md` 三個 Task、`issues.md` Issue 6 的 Solution 與驗收標準，以及 `design.md`「2026-08-15 追加」的設計決策（尤其單選模式「點擊即觸發」零確認機制的移除）。
**審查標準：** 計畫對齊度（逐字核對 Task 1-3，包含計畫明確點名的高風險回歸測試項目）、程式碼品質（既有 Key 是否逐位元組保留、Radio 語意是否正確、有無殘留死碼）、測試有效性（實機執行 `flutter pub get`／`flutter analyze`／`flutter test`，非僅閱讀程式碼推測）、架構合理性（對外建構參數與回傳值契約是否真的零異動）、文件完整性。
**審查狀態：** 已完成（本人親自逐行核對 diff，並在專屬 worktree `U:\MyDeveloper\AI\elinkBook\.worktrees\epic-28-issue-6-book-picker-refactor\app` 實機執行測試驗證，未派出子代理）

---

## 1. 優點與亮點 (Strengths)

1. **檔案異動範圍與計畫 Global Constraints 完全一致**：`git diff --stat` 顯示本次變更僅觸及 3 個檔案——`app/lib/screens/layout_preset_book_picker_screen.dart`、`app/test/screens/layout_preset_book_picker_screen_test.dart`、`app/test/screens/reader_screen_test.dart`。`library_screen.dart`／`reader_screen.dart`／`reader_settings_sheet.dart` 三個計畫明文規定「不修改」的檔案，逐一核對後確認一行未動，符合計畫 Architecture 段落「刻意不抽出共用元件」的決策與 Global Constraints 的硬性限制。

2. **Grid 佈局參數與 `library_screen.dart:833-848` 逐值相符**：`_buildGrid()`（`layout_preset_book_picker_screen.dart:117-139`）的 `MediaQuery.orientationOf(context)` 判斷、直向 3 欄／橫向 4 欄、`childAspectRatio: 0.62`、`crossAxisSpacing: 8`、`mainAxisSpacing: 12`、`padding: EdgeInsets.all(8)`，逐一比對 `library_screen.dart:834-844` 後完全一致，不是「大致相同」而是逐值相同。

3. **單選模式真正移除「點擊即觸發」，且 Radio 語意的實作與測試皆正確、非虛應故事**：`_handleItemTap()`（`layout_preset_book_picker_screen.dart:55-71`）確認 `Navigator.pop` 已完全移出 item 的 `onTap` 路徑，改為 `_selected..clear()..add(book.id)`；`AppBar` 的「確定」按鈕（`layout_preset_book_picker_confirm`）現在單選/多選皆顯示，未選取時 `onPressed: null` 停用。計畫給的「單選模式（Radio 語意）」測試（`layout_preset_book_picker_screen_test.dart` 選取書一後再選取書二）實際斷言兩個 Icon widget 的 `.icon` 屬性分別變為 `radio_button_unchecked`／`check_circle`，不是只斷言某個 widget still exists 的弱斷言，確實驗證了「選新項目會取消舊選取」這個核心行為。

4. **2 則「取消返回回傳 `null`」回歸測試是真實的、非空洞的**：單選與多選模式的兩則測試都透過 `Navigator.of(context).push<List<String>?>(...)` 真正推入路由、用 `tester.pageBack()` 觸發真實的 `MaterialPageRoute` 返回手勢（而非直接呼叫某個內部方法），並斷言 `result` 為 `isNull`；多選模式那則額外在返回前先點擊過一個項目，確認「即使已選取仍回傳 `null`」，精準對應計畫與 `design.md` 審查 Important #2 點出的既有契約風險。

5. **Task 3 的既有測試修正精準命中、且經獨立覆核未遺漏其他真實渲染點**：我自行對 `reader_screen_test.dart`（base commit）執行 `grep -n "layout_preset_book_picker_item_"`，結果同樣是 2 處（約第 6761 行、第 6860 行），與計畫「已用 Grep 核對……確認只有 2 處」的宣稱完全吻合。多選模式那則（第 6736 行測試）原本就已有 `layout_preset_book_picker_confirm` 點擊，未被改動；單選模式那則（第 6836 行測試）正確地在項目點擊後插入 `tester.tap(find.byKey(const Key('layout_preset_book_picker_confirm')))`，與計畫 Task 3 Step 1 給出的程式碼逐字相符。

6. **封面圖測試確實用真實暫存檔案＋`Image.file` 路徑，比照 `library_screen_test.dart` 既有先例**：`格線正確顯示有 coverPath 且檔案存在的書籍封面圖片` 測試（`layout_preset_book_picker_screen_test.dart`）透過 `tester.runAsync(() => Directory.systemTemp.createTemp(...))` 建立暫存目錄、寫入最小合法 1×1 PNG（base64 解碼），`addTearDown` 清理，並實際斷言 `find.byType(Image)` 存在、`Icons.menu_book` 不存在——這是真正走過 `File.existsSync()` 判斷分支與 `Image.file` 解碼路徑的測試，不是走捷徑繞過。

7. **搜尋篩選邏輯正確、且「篩選隱藏已選取項目後清空搜尋詞仍保留選取狀態」測試確實命中該行為的核心風險**：`_filteredBooks` getter（`layout_preset_book_picker_screen.dart:45-53`）對書名/作者做 `toLowerCase().contains()` 子字串比對，`_selected` 集合本身完全獨立於 `_filteredBooks` 的篩選結果、不會因為項目被篩選隱藏而被清空，測試也確實透過先選取、再輸入篩選詞使其消失、再清空篩選詞看它是否重新出現且仍為已選取狀態三步驟完整驗證。

8. **`Expanded` 包裹的驗證方式與計畫要求的結構性測試（而非模擬鍵盤 inset）完全一致**：`find.ancestor(of: gridFinder, matching: find.byType(Expanded))` 精準對應計畫 Task 2 的測試設計意圖。

9. **實測結果乾淨，零回歸**：詳見下方測試執行記錄。

10. **Dartdoc 更新誠實、無誤導**：`LayoutPresetBookPickerScreen` 類別上方的 dartdoc（`layout_preset_book_picker_screen.dart:7-17`）與 `_BookGridItem`／`_BookCover` 的類別註解都準確反映了新的格線＋確認機制，未殘留舊「點擊即觸發」設計的誤導性描述；`_BookCover` 註解明確說明「本畫面書籍恆為流式 EPUB，不需要 `LibraryScreen._BookCover` 依格式選圖示的完整邏輯」這個刻意簡化的理由，可追溯回計畫 Architecture 段落。

---

## 2. 問題與疑慮 (Issues)

實際於專屬 worktree `U:\MyDeveloper\AI\elinkBook\.worktrees\epic-28-issue-6-book-picker-refactor\app` 執行：

- `flutter pub get`：成功（僅既有套件版本落後提示，與本次變更無關）
- `flutter test test/screens/layout_preset_book_picker_screen_test.dart`：**16/16 全數通過**（Task 1 既有 6 則改寫後測試 + Task 1 新增 2 則 [Radio 語意、單選取消回傳 null] + 既有多選測試改寫 + 多選取消回傳 null 新增 1 則 + 封面圖 2 則 + Task 2 搜尋/Expanded 新增 6 則）
- `flutter test test/screens/reader_screen_test.dart`：**162/162 全數通過**（含「版面設定預設集」測試群組，Task 3 修正的兩則測試皆在其中）
- `flutter test`（全專案）：**1292/1292 全數通過**
- `flutter analyze`：**"No issues found!"**

未發現任何導致功能錯誤、契約破壞、或測試無法反映真實行為的問題。

### Critical (必須修正)
*無*

### Important (應該修正)
*無*

### Minor (建議與注意事項)

#### 【Minor #1】單選模式下「確定」按鈕的停用狀態沒有專屬測試，僅由多選模式的對應測試間接覆蓋

- **位置：** `app/test/screens/layout_preset_book_picker_screen_test.dart`（「複選模式：未勾選任何項目時，確定按鈕停用」測試）
- **說明：** `_selected.isEmpty ? null : ...` 這段停用判斷邏輯不分 `multiSelect` 分支、單選/多選共用同一份程式碼（`layout_preset_book_picker_screen.dart:82-84`），因此邏輯風險其實很低，測試只用多選模式驗證一次在工程上是合理的取捨。但計畫「單元測試要求」第 2 點明確寫著「『確定』按鈕未選取時停用，選取後啟用」是針對單選模式描述的驗收語意，目前沒有一則單選模式下直接斷言 `TextButton.onPressed` 為 `null`/非 `null` 的測試——第一則測試雖然間接證明了「未點確定不會關閉」，但沒有直接斷言 disabled 狀態本身。
- **為什麼重要：** 屬於測試覆蓋率上的小缺口，不是功能缺陷；萬一未來有人誤把停用邏輯改成依 `multiSelect` 分支處理（例如恢復「單選模式恆啟用」的舊行為），現有測試不會抓到。
- **如何修正（非阻塞）：** 可選擇性補一則單選模式下、未選取任何項目時斷言 `button.onPressed` 為 `isNull` 的測試，或視為可接受風險保留現狀。

#### 【Minor #2】搜尋欄位沒有清除（X）按鈕

- **位置：** `app/lib/screens/layout_preset_book_picker_screen.dart:93-103`
- **說明：** `TextField` 的 `InputDecoration` 只有 `prefixIcon`（搜尋圖示），沒有 `suffixIcon` 一鍵清空。這不在計畫或 `issues.md` 驗收標準要求範圍內，純屬鍵盤友善度的錦上添花建議。
- **為什麼重要：** 不影響功能正確性，僅為可選的 UX 提升，不阻塞合併。

#### 【Minor #3】`design.md`「2026-08-15 追加」Minor #2 建議抽出 `_BookCover` 為共用元件一事，計畫與實作都明確選擇不做，屬已知且有文件依據的偏離，非缺陷

- **說明：** `design.md` 第 103 行寫「已改為明確建議（非強制）抽出至 `app/lib/library/widgets/book_cover.dart`」；`issues.md` Issue 6 Solution 第 1 點同樣寫「建議，非強制……若實作當下評估抽出成本不划算，維持獨立複製一份亦可接受」。計畫 Architecture 段落已列出三點具體理由選擇不抽出，實作也確實只在本檔案內建立精簡版 `_BookCover`。此為經過授權的、有文件記錄的設計選擇，非審查發現的偏差，僅在此記錄供未來若真的出現第三個呼叫端需要共用封面容錯邏輯時參考。

---

## 3. 實作建議 (Recommendations)

- 若團隊在意測試覆蓋的完整度，可考慮補上 Minor #1 提到的單選模式停用狀態測試，成本很低（3-4 行）。
- 其餘無額外建議——本次實作與計畫的吻合度非常高，三個 Task 的程式碼與測試幾乎逐字對應計畫給出的程式碼片段，未發現任何實質性偏離。

## 4. 評估結論 (Assessment)

- **是否可合併 (Ready to merge)？** 是
- **評估理由：** 三個 Task 的程式碼變更與 `plans/plan-issue-6.md`、`issues.md` Issue 6 的 Solution／驗收標準逐項核對後完全吻合，無任何 Critical 或 Important 等級問題。既有測試 Key（`layout_preset_book_picker_item_<id>`／`layout_preset_book_picker_confirm`）逐位元組保留，新增 Key（`_selected`／`_search_field`／`_grid`）皆存在且用途正確；單選模式的「點擊即觸發」零確認風險已徹底移除，改為與多選模式統一的「選取＋確定」語意，且 Radio 語意（清空後只保留最新選取）實作與測試皆正確；2 則「取消返回回傳 `null`」回歸測試是真實的端對端 Navigator 測試，非空洞斷言；`reader_screen_test.dart` 的既有測試修正精準命中計畫指出的唯一需要修改處，且經本人獨立 `grep` 覆核確認沒有遺漏其他真實渲染此畫面的測試；`LayoutPresetBookPickerScreen` 對外建構參數與回傳值契約經讀取 `reader_screen.dart:941-957`／`reader_settings_sheet.dart:987-1005` 兩處呼叫端原始碼確認完全未變。實測 `flutter analyze` 乾淨、`layout_preset_book_picker_screen_test.dart` 16/16、`reader_screen_test.dart` 162/162、全專案 `flutter test` 1292/1292 全數通過，零回歸。僅發現 2 項不影響合併的 Minor 建議（測試覆蓋率小缺口、UX 錦上添花），可直接合併。
