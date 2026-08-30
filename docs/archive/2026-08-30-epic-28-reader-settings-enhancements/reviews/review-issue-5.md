# Epic 28 Issue 5 程式碼審查報告

**審查對象：** commit 範圍 `b3a958a..367e02c`（分支 `epic-28-issue-5`，2 個 commit：`2e1b730` 主體變更——Tab 容器骨架＋4 個頁籤內容分配＋視覺密度調整＋既有測試遷移；`367e02c` `reader_screen_test.dart` 9 則間接測試補上頁籤切換步驟）
**審查目標：** 審查「`ReaderSettingsSheet` 從單一 `ListView(shrinkWrap: true)` 重構為 4 個 Tab 頁籤」實際程式碼變更是否忠實對應 `plans/plan-issue-5.md` 六個 Task、`issues.md` Issue 5 的 Solution 與驗收標準，以及 `design.md`「2026-08-15 追加」的設計決策（尤其 `TabBarView` 手勢衝突防護與狀態穩定性兩項不可逆決策）。
**審查標準：** 計畫對齊度（逐字核對 Task 1-6，包含計畫明確點名的高風險測試遷移項目）、程式碼品質（既有 Key 是否逐位元組保留、有無殘留死碼）、測試有效性（實機執行 `flutter pub get`／`flutter analyze`／`flutter test`，非僅閱讀程式碼推測）、架構合理性（`Expanded` 有界高度依賴是否在實際呼叫端成立）、文件完整性。
**審查狀態：** 已完成（本人親自逐行核對 diff＋在專屬 worktree `U:\MyDeveloper\AI\elinkBook-epic-28-issue-5` 實機執行測試驗證，未派出子代理）

---

## 1. 優點與亮點 (Strengths)

1. **Task 2 的 Tab 容器骨架與計畫程式碼逐字相符**：`build()` 方法的 `mainAxisSize: MainAxisSize.min` 確實被移除（`reader_settings_sheet.dart` diff `-mainAxisSize: MainAxisSize.min` 那一行），舊有 `Flexible(child: ListView(shrinkWrap: true, ...))` 整段被 `Expanded(child: DefaultTabController(length: 4, child: Column([TabBar(...), Expanded(child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [...]))])))` 取代，`TabBarView` 的 `physics` 確實設為 `const NeverScrollableScrollPhysics()`（`reader_settings_sheet.dart:264`）——這是 `design.md` 審查 Important #1 點出、`issues.md` Issue 5 Solution 第 5 點明訂的硬性要求，逐字核對後完全正確。新增的 4 個 `_buildTextContentTab()`／`_buildBoundaryTab()`／`_buildPresentationTab()`／`_buildPreferencesTab()` 方法與計畫 Task 2 給出的程式碼片段（含每個 `ListView` 的 padding `EdgeInsets.fromLTRB(16, 12, 16, 16)`）逐字相符。

2. **欄位分配與 `issues.md` Issue 5 Solution 第 2 點完全一致**：「文字內容」（字型下拉＋5 個 Slider＋停用書本 CSS）、「邊界首尾」（4 個邊界 Slider＋頁首/頁尾開關＋文字對齊）、「版面呈現」（全螢幕＋欄數＋排版方向／螢幕方向／翻頁模式三個覆寫列）、「設定喜好」（版面設定預設集區塊）——逐一比對程式碼與 `issues.md:115-119`，欄位歸屬、方法呼叫順序皆一致，沒有任何欄位被遺漏或分配到錯誤頁籤。

3. **4 個頁籤確實只是 `_ReaderSettingsSheetState` 的 `build()` 分支，沒有被抽成獨立 `StatefulWidget`**：這是 `design.md` 審查 Important #3、`issues.md` Issue 5 Solution 第 6 點特別強調的狀態穩定性要求（避免 Issue 4 新增的 5 個「是否已覆寫」旗標在頁籤切換時被意外重建遺失）。逐行核對 4 個 `_buildXxxTab()` 方法，皆為回傳 `Widget` 的私有方法、直接讀寫同一個 State 物件的欄位，沒有任何 `class _XxxTab extends StatefulWidget` 之類的抽出，符合要求。

4. **既有控制項 Key 逐位元組保留**：抽查與全量核對（`reader_settings_font_size_slider`／`reader_settings_margin_top_slider`／`reader_settings_fullscreen`／`reader_settings_save_as_preset` 等）皆未變動字串內容，只是被搬進不同的 `ListView` 容器，符合計畫 Global Constraints 的硬性要求。

5. **Task 1 的兩則「橫向拖曳不誤觸切頁」測試確實命中風險核心，不是虛應故事**：兩則測試都透過 `DefaultTabController.of(tester.element(...))` 取得真實 `TabController`，`drag()` 後斷言 `tabController.index` 不變，而不是只斷言某個 Widget 還在畫面上——這正是 `NeverScrollableScrollPhysics` 這項要求存在的理由（`PageView` 誤判横向拖曳為切頁手勢），測試設計確實對應到了真正的風險，並非被稀釋成弱斷言。

6. **Task 4 的「刻意行為反轉」測試被誠實地正面處理，而非迴避**：舊測試「內容小於可用高度時，Bottom Sheet 保持緊湊包裹」被改寫為「Bottom Sheet 一律撐到近全螢幕高度」，斷言從 `lessThan(2500)` 正確反轉為 `greaterThan(2500)`，且測試描述與 `reason:` 皆清楚說明這是刻意的設計變更、比照 `TocBottomSheet` 既有先例，而非需要被掩蓋的回歸——與計畫 Task 4 Step 6 逐字相符。

7. **計畫特別點名「容易被遺漏」的測試確實沒有被漏掉**：計畫 Task 3 開頭特別強調「『只切換「顯示頁首」開關』…這則測試不屬於此類…處理方式見 Task 4 Step 3」，實際核對 `reader_settings_sheet_test.dart:275-302`，該則測試確實存在且正確插入了 `switchToTab(tester, '邊界首尾')`，沒有被誤刪或遺漏。

8. **實測結果乾淨，零回歸**：詳見下方「2. 問題與疑慮」前的測試執行記錄。

---

## 2. 問題與疑慮 (Issues)

實際於專屬 worktree `U:\MyDeveloper\AI\elinkBook-epic-28-issue-5\app` 執行：

- `flutter pub get`：成功（僅既有的套件版本落後提示，與本次變更無關）
- `flutter test test/screens/reader_settings_sheet_test.dart`：**53/53 全數通過**（基準分支為 49 則，本次新增 4 則：Task 1 的 3 則 + Task 5 的 1 則）
- `flutter test test/screens/reader_screen_test.dart`：**162/162 全數通過**（含「版面設定預設集」測試群組 7 則）
- `flutter test`（全專案）：**1280/1280 全數通過**
- `flutter analyze`：**"No issues found!"**

未發現任何導致功能錯誤或測試無法反映真實行為的 Critical 等級問題，但發現 1 項計畫明確要求、實際被漏做的測試強化項目，以及文件完整性上的落差。

### Critical (必須修正)
*無*

### Important (應該修正)

#### 【Important #1】計畫 Task 4 Step 3 明確要求的測試修正實際上完全沒有落地——「5 個受本 Issue 影響欄位皆為 null 時」測試仍是舊版本，對邊界欄位的斷言是巧合通過，而非真正驗證（**已於 commit `19fa28a` 採納修正**）

- **位置：** `app/test/screens/reader_settings_sheet_test.dart:328-357`（測試描述：「5 個受本 Issue 影響欄位皆為 null 時，顯示「原樣式」禁止圖示取代數字；邊界 4 個欄位不受影響，仍顯示具體數字，也不出現重置按鈕」）
- **說明：** 用 `git diff` 逐行核對，這則測試的內容與 base commit（`b3a958a`）**完全逐位元組相同**（比對 base 與 head 的對應區塊，字元級別一致），從未被本次 diff 觸碰過。但計畫 `plan-issue-5.md` Task 4 Step 3 明確要求把它改寫為在檢查完文字內容頁籤的 5 個欄位後，插入 `await switchToTab(tester, '邊界首尾');`，再檢查邊界 4 個欄位的 `_unset_indicator`/`_reset` 斷言，理由是計畫作者已經預先指出：分頁之後，若從未真的切換到「邊界首尾」頁籤，該頁籤內容（`margin_top_slider` 等）根本不會被掛載進畫面樹，此時 `findsNothing` 斷言會「因為頁籤根本沒被切換過而巧合通過」，並不是真的驗證「邊界欄位不支援這個機制」這個語意。
- **已實機驗證這個巧合確實成立，不是理論推測**：Task 1 新增的第一則測試（「4 個頁籤皆可切換...」）在只停留於預設「文字內容」頁籤（未呼叫 `switchToTab`）的情況下，明確斷言 `find.byKey(const Key('reader_settings_margin_top_slider'))` 為 `findsNothing`，且該斷言確實通過（見上方測試執行記錄）。這證明「邊界首尾」頁籤的 `ListView`（含 4 個邊界 Slider）在未切換頁籤時確實未被掛載進畫面樹，`TabBarView` 底層 `PageView` 的 `cacheExtent` 沒有把該頁籤預先建構出來。因此「5 個受本 Issue 影響欄位皆為 null 時」這則測試中對邊界 4 個欄位 `_unset_indicator`/`_reset` 皆 `findsNothing` 的斷言，目前依然是「因為畫面上根本沒有這些 widget」而通過，而不是「這些 widget 存在、且正確地不顯示禁止圖示」——與計畫作者原本要防範的情境完全吻合。
- **為什麼重要：** 這是計畫作者在撰寫計畫階段就已經明確辨識、並要求修正的一個具體風險，屬於「明知有坑、且已經寫好正確作法」但實作階段被跳過的項目，不是隱晦的邊角案例。目前測試對「邊界欄位不適用『未覆寫顯示原樣式圖示』機制」這個語意完全沒有實質驗證力，一旦未來有人不慎讓邊界欄位也套用了這個機制，這則測試不會抓到。
- **如何修正：** 依計畫 Task 4 Step 3 給出的程式碼，在檢查完文字內容 5 個欄位後插入 `await switchToTab(tester, '邊界首尾');`，再檢查邊界 4 個欄位。修正後應重新確認測試仍為 PASS（邊界欄位本來就不支援這個機制，語意不變，只是驗證方式從「巧合」變成「真實」）。

#### 【Important #2】本次引入的兩項「不可逆技術決策」在程式碼中沒有任何一句在地註解說明理由，僅存在於外部文件（**已於 commit `19fa28a` 採納修正**）

- **位置：** `app/lib/screens/reader_settings_sheet.dart:262-268`（`TabBarView` 區塊）與整個 `build()` 方法（4 個 Tab 內容方法周邊）
- **說明：**
  1. `TabBarView(physics: const NeverScrollableScrollPhysics(), ...)`（`reader_settings_sheet.dart:264`）沒有任何行內註解說明「為什麼」——而這個決策明確是為了避免與頁籤內大量橫向拖曳型 `Slider` 搶手勢競技場（`design.md` 審查 Important #1）。更值得注意的是，計畫文字明確宣稱本次重構「比照既有 `TocBottomSheet` 先例」（`toc_bottom_sheet.dart:178-202`），但實際查證 `toc_bottom_sheet.dart` 的 `TabBarView` **並未**設定這個 `physics` 參數（其頁籤內容是章節清單/縮圖格/搜尋結果，沒有橫向拖曳型控制項，不需要這道防護）。也就是說這其實是本 Issue 新引入、且與被引用的先例不同的獨立決策，卻沒有任何行內文字提示未來讀者「這裡刻意不用預設值，別因為要跟 `TocBottomSheet` 對齊或覺得多餘就拿掉」。
  2. 4 個頁籤必須維持為同一個 `_ReaderSettingsSheetState` 的 `build()` 分支、不得抽成獨立 `StatefulWidget` 這項狀態穩定性約束（`design.md` 審查 Important #3），同樣完全沒有反映在程式碼註解裡。
- **為什麼重要：** 本專案 `CLAUDE.md`／既有程式碼慣例（例如 PDF `Isolate.run()` closure 的「不可逆的技術決策，改動前務必知悉」註解、`TapZoneDetector` 建構參數不收斂為模組常數的理由註解）已經確立了「重要但反直覺的架構限制要留在原始碼裡，而非只寫在 `design.md`」這個慣例，理由是未來的維護者/重構者不太可能在改動前先去翻 Epic 的 `design.md`。目前這兩項決策皆只存在於 `design.md`／`issues.md`／本次的 plan 文件，一旦未來有人做「簡化 `TabBarView` 設定」或「把某個頁籤抽成獨立元件方便重用」這類乍看合理的重構，極可能在不知情的情況下重新引入 Issue 4／Issue 5 已經修過的手勢衝突或狀態遺失問題。
- **如何修正：** 在 `TabBarView` 的 `physics:` 那一行上方補一句簡短行內註解（例如：「必須為 `NeverScrollableScrollPhysics`——頁籤內含多個橫向拖曳 `Slider`，預設 `PageView` 滑動手勢會與其搶手勢競技場，見 epic-28 design.md『2026-08-15 追加』"）；在 `_ReaderSettingsSheetState` class doc 或 4 個 `_buildXxxTab()` 方法群組上方補一句說明「4 個頁籤僅為本 State 的展示分支，不得抽出獨立 StatefulWidget，避免 Issue 4 的 `_XxxOverridden` 旗標在頁籤切換時被重建遺失」。

### Minor (建議與注意事項)

#### 【Minor #1】兩個 commit 的訊息與其實際 diff 內容對不上

- **說明：** `git log` 顯示分支上有 2 個 commit：`2e1b730`（訊息為「版面呈現頁籤圖示列改用緊湊視覺密度」）與 `367e02c`（訊息為「ReaderSettingsSheet 改為 4 個 Tab 頁籤，減少捲動需求」）。但實際用 `git show --stat` 核對，`2e1b730` 的 diff 其實同時包含了 Task 1-5 的**全部**變更（`reader_settings_sheet.dart` 的完整 Tab 容器重構 + `reader_settings_sheet_test.dart` 的全部測試遷移），而 `367e02c` 的 diff **只**包含 `reader_screen_test.dart` 的 9 處 `switchToTab` 插入（即 Task 6）。兩個 commit 的訊息實際上對調了——`2e1b730` 的訊息聽起來像只做了視覺密度這一小塊，實際上做了整個大重構；`367e02c` 的訊息聽起來像是整個大重構的落地，實際上只是收尾的間接測試修正。
- **為什麼重要：** 不影響最終合併結果（兩個 commit 疊加後的完整 diff 是正確的），但未來若有人用 `git bisect` 或只看單一 commit 訊息＋diff 摘要（不展開全文）去理解變更歷史，會被誤導。
- **建議：** 非阻塞項目，若尚未推送/合併，可考慮用 `git commit --amend`／`git rebase` 調整 commit 訊息使其對應各自實際的 diff 內容；若已推送到共用分支則不需要為此重寫歷史。

#### 【Minor #2】計畫本身在 Task 6 Step 3 的測試計數與實際測試檔案不符

- **說明：** `plan-issue-5.md` Task 6 Step 3 描述「8 則『版面設定預設集（epic-28-reader-settings-enhancements Issue 3）』測試群組」需要補上 `switchToTab`，但實際查證 `reader_screen_test.dart` 的 `group('版面設定預設集...', () {...})` 區塊內只有 **7** 則 `testWidgets`（另存為新預設集、存滿 3 組後再次另存、套用到目前書籍、套用到其他書籍多本、刪除-移除、刪除-取消、複製其他書籍設定到本書），實作也正確地為這 7 則各插入了一次 `switchToTab(tester, '設定喜好')`，沒有遺漏也沒有多插。這是計畫文件本身的計數誤差，不是實作缺陷。
- **建議：** 若之後有人整理 `plan-issue-5.md` 的歸檔版本，可以順手把「8 則」改成「7 則」，避免下次有人依這個數字去核對時產生困惑。

#### 【Minor #3】`TabBar` 維持預設不可捲動（`isScrollable` 未設定），4 個 4 字中文標籤在極窄螢幕上的實際視覺效果未經真機驗證

- **說明：** `issues.md` 與計畫皆未特別要求 `TabBar` 需要可捲動，目前實作維持 Flutter 預設（4 個頁籤平均分配寬度）。「文字內容」「邊界首尾」「版面呈現」「設定喜好」皆為 4 個中文字，理論上應該還在合理範圍內，但這點只能透過真機/模擬器目視驗證，`flutter test` 的 widget test 無法驗證文字是否在極窄裝置寬度下被截斷或擠壓變形。
- **建議：** 非阻塞項目，建議合併前找機會在較窄的實體/模擬裝置（例如 360dp 寬度級別）上開一次版面設定畫面確認頁籤文字排版正常，比照 `review-issue-4.md` Minor #2 對圖示視覺效果的處理方式。

---

## 3. 實作建議 (Recommendations)

1. **優先處理 Important #1**：這是計畫明確寫下、且審查特別要求核對的項目，屬於「已知道怎麼修、只是漏做」的低成本修正，建議直接依計畫 Task 4 Step 3 的程式碼片段補上 `switchToTab(tester, '邊界首尾')`，讓這則測試真正驗證邊界欄位不適用「未覆寫顯示原樣式圖示」機制。
2. **採納 Important #2 的建議，為兩項不可逆決策各補一句行內註解**：這個修正成本極低（兩處各一行註解），但對照本專案既有的「不可逆的技術決策」註解慣例，價值很高——尤其 `NeverScrollableScrollPhysics` 這項與被引用的 `TocBottomSheet` 先例實際上不同的細節，最值得留一句話避免被誤解為「應該跟先例一致而被移除」。
3. Minor #1／#2／#3 皆非阻塞項目，可視情況擇一處理或留待下次維護時順手修正。

---

## 4. 評估結論 (Assessment)

- **是否可合併 (Ready to merge)？** 修正後可合併
- **評估理由：** 本次變更在「計畫對齊度」這個最重要的審查軸上表現紮實——Task 2 的 Tab 容器骨架、欄位分配、`NeverScrollableScrollPhysics`、狀態穩定性約束（4 個頁籤不抽成獨立 `StatefulWidget`）、Task 3 的 31 則機械式測試遷移、Task 4 的 6 則結構性測試修正中有 5 則（含刻意行為反轉那則最容易被投機處理的測試）皆確實正確落地、Task 5 的視覺密度調整、Task 6 的 9 則間接測試修正，皆逐一核對通過，且 `flutter analyze` 乾淨、全專案 1280 則測試（含本次新增與遷移的全部測試）實機執行皆為綠燈，零回歸。唯一一項功能性缺口是 Task 4 Step 3——計畫明確要求、且經實機驗證確實會讓現有斷言淪為「因頁籤未掛載而巧合通過」而非真正驗證的一則測試修正，被完全跳過未實作；另外兩項不可逆技術決策（手勢衝突防護、狀態穩定性約束）目前只存在於外部文件、程式碼本身沒有任何在地提示，存在未來被誤修的風險。這兩項 Important 修正成本都很低（合計數行），建議在合併前一併補上；其餘皆為不影響功能正確性的文件/流程性 Minor 項目。
