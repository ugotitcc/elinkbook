# Epic 28 Issue 6 程式碼審查報告——複審

**審查對象：** `reviews/review-issue-6.md`（對 `epic-28-issue-6-book-picker-refactor` 分支 commit 範圍 `e4f64cd..33e61be` 的程式碼審查報告）
**審查目標：** 驗證 `review-issue-6.md` 各項審查結論的事實基礎是否正確——包括測試計數、程式碼描述、git diff 摘要、計畫對齊度宣稱——是否忠實反映分支上的實際程式碼變更。
**審查標準：** 逐項核對 review 的每一個事實宣稱（測試數量、Key 名稱、方法簽章、參數值、文件描述）是否與分支 `33e61be` 的實際程式碼完全一致，不接受「大致相同」或「合理推測」。
**審查狀態：** 已完成（本人在本機 git 環境直接核對分支程式碼，未派出子代理）

---

## 1. 優點與亮點 (Strengths)

1. **審查範圍界定清晰且正確**：`review-issue-6.md` 正確指出審查對象為 `e4f64cd..33e61be`（3 個 commit），與 `git log --oneline e4f64cd..33e61be` 的實際輸出完全吻合——`6f4ef03`（格線化＋統一機制）、`fb3a1aa`（搜尋）、`33e61be`（reader_screen_test 補上確定按鈕）。commit 訊息順序與描述皆正確。

2. **git diff --stat 宣稱的 3 個檔案異動正確**：`git diff --stat e4f64cd..33e61be` 顯示 `layout_preset_book_picker_screen.dart`（+243/-51）、`layout_preset_book_picker_screen_test.dart`（+314/-1）、`reader_screen_test.dart`（+3/-0），確實只有 3 個檔案。Global Constraints 規定不修改的 `library_screen.dart`／`reader_screen.dart`／`reader_settings_sheet.dart` 確實未被觸碰，宣稱正確。

3. **Grid 佈局參數逐值核對正確**：分支程式碼 `_buildGrid()` 的 `MediaQuery.orientationOf(context)` 判斷、直向 3 欄／橫向 4 欄、`childAspectRatio: 0.62`、`crossAxisSpacing: 8`、`mainAxisSpacing: 12`、`padding: EdgeInsets.all(8)`，與 review 宣稱及 `library_screen.dart:834-844` 既有可能例完全一致，逐值核對通過。

4. **單選模式「點擊即觸發」移除的描述正確**：分支程式碼 `_handleItemTap()` 確認 `Navigator.pop` 已完全移出 item 的 `onTap` 路徑，改為 `_selected..clear()..add(book.id)`；`AppBar` 的「確定」按鈕（`layout_preset_book_picker_confirm`）現在單選/多選皆顯示（`actions:` 不再有 `widget.multiSelect ? [...] : null` 的條件分支），未選取時 `onPressed: null` 停用。描述正確。

5. **Radio 語意測試的斷言描述正確**：分支程式碼的「單選模式（Radio 語意）」測試確實透過 `tester.widget<Icon>(find.byKey(...)).icon` 斷言 `Icons.check_circle`／`Icons.radio_button_unchecked`，不是弱斷言。描述正確。

6. **2 則「取消返回回傳 null」回歸測試的描述正確**：單選與多選模式的兩則測試都確實透過 `Navigator.of(context).push<List<String>?>(...)` 推入路由、`tester.pageBack()` 觸發返回，並斷言 `result` 為 `isNull`；多選模式那則確實在返回前先點擊過一個項目。描述正確。

7. **reader_screen_test.dart 的修正描述正確**：`git diff` 顯示在第 6859 行的 `tester.tap(find.byKey(const Key('layout_preset_book_picker_item_b_other')))` 之後，確實插入了 3 行——`tester.tap(find.byKey(const Key('layout_preset_book_picker_confirm')))`＋`await tester.pump()`，與計畫 Task 3 Step 1 的程式碼逐字相符。描述正確。

8. **封面圖測試用真實暫存檔案的描述正確**：分支程式碼確實用 `tester.runAsync(() => Directory.systemTemp.createTemp(...))` 建立暫存目錄、寫入 base64 解碼的最小 1×1 PNG、`addTearDown` 清理，並斷言 `find.byType(Image)` 存在。描述正確。

9. **搜尋篩選邏輯的描述正確**：`_filteredBooks` getter 確實對書名/作者做 `toLowerCase().contains()` 子字串比對，`_selected` 集合獨立於篩選結果。「篩選隱藏已選取項目後清空搜尋詞仍保留選取狀態」的三步驟測試確實存在。描述正確。

10. **`Expanded` 包裹的結構性測試描述正確**：`find.ancestor(of: gridFinder, matching: find.byType(Expanded))` 在分支程式碼中確實存在。描述正確。

11. **dartdoc 更新描述正確**：分支程式碼的 `LayoutPresetBookPickerScreen` 類別 dartdoc 確實已更新為描述格線化＋統一確認機制（Radio 語意＋確定按鈕＋null 回傳契約），不再殘留舊版「點擊項目立即以 `[book.id]` 關閉畫面」的描述。Strength #10 宣稱正確。

12. **`_BookCover` 註解理由的描述正確**：分支程式碼 `_BookCover` 類別上方的 dartdoc 確實說明「本畫面書籍恆為流式 EPUB，不需要 `LibraryScreen._BookCover` 依 `book.format` 選格式專屬圖示的完整邏輯」，可追溯回計畫 Architecture 段落。描述正確。

---

## 2. 問題與疑慮 (Issues)

### Critical (必須修正)

*無*

### Important (應該修正)

#### 【Important #1】測試計數宣稱錯誤——「16/16 全數通過」實際應為「15/15」

- **位置：** `review-issue-6.md` 第 39 行
- **說明：** review 宣稱「`flutter test test/screens/layout_preset_book_picker_screen_test.dart`：**16/16 全數通過**」，並在括號內列出計數明細「Task 1 既有 6 則改寫後測試 + Task 1 新增 2 則 [Radio 語意、單選取消回傳 null] + 既有多選測試改寫 + 多選取消回傳 null 新增 1 則 + 封面圖 2 則 + Task 2 搜尋/Expanded 新增 6 則」。但實際以 `git show 33e61be:app/test/screens/layout_preset_book_picker_screen_test.dart | grep -c "testWidgets"` 核對，分支上的測試檔只有 **15** 個 `testWidgets`，非 16 個。逐一盤點分支程式碼的每一則 `testWidgets`：
  1. 單選模式：點擊項目後選取但不立即關閉，點擊「確定」才回傳該書 id
  2. 單選模式（Radio 語意）：選取書一後再選取書二，最終只有書二保持選取狀態
  3. 單選模式：未點擊「確定」、直接返回時，回傳 null
  4. 複選模式：點擊兩本書的格子後點擊確定，回傳兩個 id 的清單
  5. 複選模式：未勾選任何項目時，確定按鈕停用
  6. 複選模式：未點擊「確定」、直接返回時，回傳 null（即使已選取項目）
  7. 書籍清單為空時顯示提示文字
  8. 格線正確顯示有 coverPath 且檔案存在的書籍封面圖片
  9. 格線對無 coverPath 的書籍以通用書本圖示佔位
  10. 輸入書名子字串，格線即時篩選為符合的書籍
  11. 輸入作者子字串，格線即時篩選為符合的書籍
  12. 搜尋查無符合結果時顯示提示文字，與「無可選書籍」提示不同
  13. 清空搜尋詞後，格線恢復顯示完整清單
  14. 多選模式下，篩選隱藏已選取項目後清空搜尋詞，該項目選取狀態仍保留
  15. GridView 由 Expanded 包裹（避免軟體鍵盤彈出時版面溢位）
  
  review 括號內的明細也與實際不符——「Task 1 既有 6 則改寫後測試」的分類方式暗示存在 6 + 2 + 多選改寫 + 1 + 2 + 6 = 17 則（含多選改寫未明確計數），與宣稱的 16 則自相矛盾。正確的計數應為：Task 1 改寫後的 7 則（#1-#7）＋ Task 1 新增的 1 則（#2 Radio 語意，已計入前述 7 則）＋ Task 1 新增的 1 則（#3 單選取消 null，已計入前述 7 則）＋ Task 1 新增的 1 則（#6 多選取消 null，已計入前述 7 則）＋封面圖 2 則（#8-#9）＋ Task 2 搜尋/Expanded 新增 6 則（#10-#15）= 合計 15 則。
- **為什麼重要：** 測試計數是審查報告的核心量化指標，錯誤的數字會影響後續審查者對覆蓋範圍的判斷。若有人依「16 則」這個數字去核對，會產生困惑。
- **如何修正：** 將「16/16 全數通過」改為「15/15 全數通過」；括號內明細改為正確的分類計數。

#### 【Important #2】Strength #10 對 dartdoc 的描述與實際分支程式碼有細節落差

- **位置：** `review-issue-6.md` 第 30 行（Strength #10）
- **說明：** review 宣稱「`_BookCover` 註解明確說明『本畫面書籍恆為流式 EPUB，不需要 `LibraryScreen._BookCover` 依格式選圖示的完整邏輯』這個刻意簡化的理由」。分支程式碼的 `_BookCover` dartdoc 實際文字為「本畫面書籍恆為流式 EPUB（呼叫端已用 `LibraryRepository.listReflowableEpubBooks()` 過濾），不需要 `LibraryScreen._BookCover` 依 `book.format` 選格式專屬圖示的完整邏輯」。review 省略了「（呼叫端已用 `LibraryRepository.listReflowableEpubBooks()` 過濾）」與「格式專屬圖示」中的「格式專屬」四字。這不是嚴重錯誤（語意方向正確），但作為「逐字核對」等級的審查報告，與「不需要 `LibraryScreen._BookCover` 依格式選圖示的完整邏輯」的引述有偏差——實際文字是「依 `book.format` 選格式專屬圖示」。
- **為什麼重要：** 屬於精確度問題，不影響審查結論的正確性，但與審查標準宣稱的「逐字核對」有落差。
- **如何修正（非阻塞）：** 可選擇性修正引述使其與實際 dartdoc 一致，或保留現狀（語意無誤）。

---

## 3. 實作建議 (Recommendations)

1. **優先修正 Important #1**：測試計數從 16 改為 15，括號內明細同步修正。這是客觀事實錯誤，修正成本極低（改一個數字）。
2. Minor #1（單選停用狀態無專屬測試）、Minor #2（搜尋欄位無清除按鈕）、Minor #3（`_BookCover` 不抽出為共用元件）三個 Minor 項目在本次複審中核對後，其技術判斷與建議方向皆正確，不需要修正。
3. 實作建議段落與評估結論段落在修正測試計數後，其餘內容與分支實際程式碼完全吻合。

## 4. 評估結論 (Assessment)

- **是否可合併 (Ready to merge)？** 修正後可合併
- **評估理由：** `review-issue-6.md` 的審查品質整體紮實——所有 Strength 的技術描述（Grid 參數、Radio 語意、Navigator.pop 移除、搜尋邏輯、Expanded 結構、dartdoc 更新）經逐一核對分支程式碼後確認正確，3 個 Minor 的技術判斷與建議方向皆合理，架構合理性（對外參數與回傳值零異動）的宣稱經核對呼叫端原始碼確認正確。唯一一項事實錯誤是測試計數（宣稱 16 實為 15），屬於量化指標的筆誤，修正後不影響審查結論的正確性與完整性。
