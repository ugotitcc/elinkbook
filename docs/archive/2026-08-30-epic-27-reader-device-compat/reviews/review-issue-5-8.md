# Epic 27 Issue 5~8 程式審查報告

**審查範圍：** 8dc6fc7babdd2e4b0ca1f166fd2ea48bcbc27c59..feat/epic-27-reader-device-compat（分支 feat/epic-27-reader-device-compat）
**審查對象計畫：**
- docs/epics/epic-27-reader-device-compat/plans/plan-issue-5.md
- docs/epics/epic-27-reader-device-compat/plans/plan-issue-6.md
- docs/epics/epic-27-reader-device-compat/plans/plan-issue-7.md
- docs/epics/epic-27-reader-device-compat/plans/plan-issue-8.md
**審查日期：** 2026-08-23

---

## 開頭摘要（Critical，請優先閱讀）

這個分支**目前無法編譯**，`flutter analyze` 產出 **12 個 error**（非 0 warning / 0 error）。根因：`app/lib/screens/reader_settings_sheet.dart` 與 `app/lib/screens/fxl_settings_sheet.dart`（Issue 6 Task 3 的改動）匯入了 `widgets/reader_option_tile.dart`，但這個檔案**從未被建立、也從未被 commit 進這個分支**（Issue 6 Task 1 完全沒有實作）。

分支只有 4 個 commit，對照四份計畫逐一核對後，完成度如下：

| Issue | Task | 完成度 |
|---|---|---|
| Issue 5 | Task 1（SettingsScreen 新增 E-Ink 開關） | **完全未實作**（`settings_screen.dart`／其測試檔完全沒有改動） |
| Issue 5 | Task 2（LibraryScreen AppBar 按鈕視覺強化） | **已實作**，但被誤植（mis-commit）進 Issue 8 的 commit（`2136e86`），沒有自己的 commit |
| Issue 6 | Task 1（建立 `ReaderOptionTile`） | **完全未實作**——沒有這個 commit，檔案不存在（`app/lib/screens/widgets/reader_option_tile.dart` 不存在），對應測試檔也不存在 |
| Issue 6 | Task 2（改造 `PdfSettingsSheet`） | **完全未實作**（`pdf_settings_sheet.dart`／其測試檔完全沒有改動） |
| Issue 6 | Task 3（改造 `ReaderSettingsSheet`／`FxlSettingsSheet`） | **已實作**，程式碼品質大致良好，但因為引用不存在的 Task 1 產物導致**整個專案編譯失敗**；另外發現一個真實的邏輯 bug（見下方 Issue 6 Important #1） |
| Issue 7 | Task 1（`PdfCropFrameOverlay` 遮罩＋FAB 重構） | **已完整實作**，忠實對照計畫（含審查修正版），品質良好 |
| Issue 8 | Task 1（排序選單 Checkmark） | **已完整實作**，忠實對照計畫，品質良好 |

更嚴重的是：`docs/epics.md` 這個分支的變更中，**明確宣稱「Issue 5-8 已全數完成」「`settings_screen.dart` SwitchListTile」「`flutter analyze` 0 warning 0 error，全數相關測試通過」**，以及四份 `plans/plan-issue-*.md` 檔案中**所有 Task 的所有 Step checkbox 全數被打勾（`[x]`）**——包含 Issue 5 Task 1、Issue 6 Task 1、Issue 6 Task 2 這三個完全沒有程式碼的 Task。這些都是與實際程式碼狀態不符的虛假完成聲明，需要在合併前優先處理。

---

## Issue 5：E-Ink 高對比模式狀態感知與切換識別強化

### 完成度總覽

- **Task 1（SettingsScreen 新增 E-Ink 開關）**：❌ 完全未實作。`app/lib/screens/settings_screen.dart`、`app/test/screens/settings_screen_test.dart` 在 `git diff --stat` 中完全沒有出現，與 base commit 逐位元組相同（已用 `git diff` 確認為空 diff）。計畫要求的 `onEinkModeChanged` 參數、`Key('settings_eink_mode_switch')` 的 `SwitchListTile` 完全不存在。
- **Task 2（LibraryScreen AppBar E-Ink 切換按鈕視覺強化）**：✅ 已實作，程式碼忠實對照計畫（`app/lib/screens/library_screen.dart` 第 738-766 行左右，`Container` 外框＋黑底白圖示＋新版 tooltip 文案），對應測試（`library_screen_test.dart` 新增的 `'LibraryScreen 在 E-Ink 模式開啟與關閉時...'` 測試）也完全對照計畫 Step 1 的程式碼。**但這個改動被夾帶進 commit `2136e86`（訊息寫的是「Issue 8」），沒有自己的 commit**，違反了計畫 Task 2 Step 5 要求的獨立 commit 訊息。

### Strengths

- Task 2 的實作本身正確：拿掉了計畫審查階段就已指出是死碼的 `brightness == Brightness.dark` 判斷，固定黑底白圖示；tooltip 文案改為「E-Ink 模式：已開啟（點擊切換）」／「已關閉」，符合計畫 Step 3 程式碼片段逐字對照。
- 新增測試斷言 `tooltip` 含有「開啟」關鍵字、點擊後正確回呼 `false`（即從 `isEinkMode: true` 切換為 `false`），邏輯正確且能鑑別「按鈕確實反映/切換 E-Ink 狀態」。

### Issues

#### Critical (Must Fix)

1. **`app/lib/screens/settings_screen.dart`：Task 1 完全未實作。**
   計畫要求的「設定頁面獨立 E-Ink 高對比模式開關」（`SwitchListTile`、`onEinkModeChanged` 貫穿參數）完全不存在。使用者在設定頁面目前仍然無法檢視/切換 E-Ink 模式，這是 Issue 5 的核心驗收項目之一，未完成。
   **修正方式**：需要實際依照 `plan-issue-5.md` Task 1 的 Step 1-5 補上實作與測試，並補上獨立 commit。

#### Important (Should Fix)

2. **Task 2 的程式碼與測試被夾帶進 Issue 8 的 commit（`2136e86 feat(epic-27): Issue 8——書架排序選單加入選中 Checkmark 與粗體指示`），commit 歷史與訊息失真。**
   這個 commit 實際上同時包含 Issue 5 Task 2（AppBar E-Ink 按鈕）與 Issue 8 Task 1（排序選單 Checkmark）兩個不相關 Issue 的改動，但 commit 訊息只提到「Issue 8」。這會讓之後想要 `git revert`／`git bisect` 個別 Issue 的維護者誤判範圍，也讓「Issue 5 是否完成」這件事單看 commit log 完全查不出來（必須實際比對程式碼才會發現）。
   **修正方式**：不強制要求现在拆分歷史 commit（拆分歷史有其風險），但至少應在 PR 描述／`docs/epics.md` 中明確註記這個事實，不要讓文件宣稱「Issue 5 已完成並有獨立 commit」。

---

## Issue 6：閱讀器版面設定面板圖示選項高對比選中狀態重構

### 完成度總覽

- **Task 1（建立 `ReaderOptionTile<T>`）**：❌ 完全未實作。`app/lib/screens/widgets/reader_option_tile.dart`、`app/test/screens/widgets/reader_option_tile_test.dart` 在整個分支的 `git ls-tree -r` 輸出中完全不存在，沒有任何 commit 建立過這個檔案。
- **Task 2（改造 `PdfSettingsSheet`）**：❌ 完全未實作。`app/lib/screens/pdf_settings_sheet.dart`、`app/test/screens/pdf_settings_sheet_test.dart` 與 base commit 完全相同（空 diff）。PDF 設定面板（Fit 模式、雙頁模式、方向、換頁動畫、裁切模式）目前仍是原本純圖示、選中狀態幾乎無法辨識的 `IconButton`。
- **Task 3（改造 `ReaderSettingsSheet` 與 `FxlSettingsSheet`）**：✅ 已實作（commit `322e475`），程式碼架構與計畫（含審查修正後版本）高度吻合：`ReaderOptionTile<T>` 的呼叫方式、既有 Key 全數保留、E-Ink 顏色特徵判斷的技術折衷（`primary==black && scaffoldBackgroundColor==white`）與計畫描述一致。**但因為引用了 Task 1 未曾建立的 `reader_option_tile.dart`，整個檔案（連帶 `fxl_settings_sheet.dart`）無法編譯**，且過程中發現一個真實的邏輯 bug（見下方 Important #1）。

### Strengths

- `fxl_settings_sheet.dart` 的兩處替換（雙頁模式、翻頁方向）非常乾淨，`IconButton` → `ReaderOptionTile<T>` 一對一直接替換，`value`/`groupValue` 語意清楚，`itemKey` 完整保留既有 Key（`fxl_settings_dual_page_mode_*`、`fxl_settings_direction_*`）。
- `reader_settings_sheet.dart` 中「文字對齊」（`_buildTextAlignRow`）與「分欄」（欄數 Row→Wrap 改造）兩處也是乾淨的直接替換，沒有引入額外複雜度。
- 新增的 E-Ink 高對比測試（`ReaderSettingsSheet 文字對齊與排版方向在 E-Ink 模式下具備高對比選中底色`、`FxlSettingsSheet 在 E-Ink 模式下雙頁模式選項具備高對比選中底色`）確實改用 `tester.widget<Container>(find.byKey(...))` 直接斷言 `BoxDecoration.color`，完全對照計畫審查修正後的「不用 `.first Container` 脆弱寫法」要求，測試品質良好。
- 既有「版面呈現頁籤圖示列皆使用緊湊視覺密度」測試被正確地改寫為改用 `find.byType(ReaderOptionTile)` 逐一斷言 `visualDensity`，而非依賴子樹結構，屬於合理调整。

### Issues

#### Critical (Must Fix)

1. **`app/lib/screens/widgets/reader_option_tile.dart` 不存在，導致 `fxl_settings_sheet.dart:6`、`reader_settings_sheet.dart:14` 的 `import 'widgets/reader_option_tile.dart';` 找不到目標，`flutter analyze` 報 `uri_does_not_exist`，兩個檔案內對 `ReaderOptionTile<T>` 的全部呼叫（`fxl_settings_sheet.dart:88,112`、`reader_settings_sheet.dart:555,744,783,825,878`）皆為 `undefined_method`。**
   這是本次審查中「表面上有 commit，但實際上專案編譯不過」的直接證據——Task 3 的 commit 訊息（`feat(epic-27): Issue 6 Task 3——ReaderSettingsSheet 與 FxlSettingsSheet 圖示選項升級為 ReaderOptionTile`）暗示已完成，但沒有配套的 Task 1 commit，導致這個 commit 本身就是一個編譯失敗的狀態，不應該被獨立提交。
   **修正方式**：立刻依 `plan-issue-6.md` Task 1 的 Step 1-5 補上 `ReaderOptionTile<T>` 元件與其測試。

2. **`pdf_settings_sheet.dart` 完全未改造（Task 2 未實作）。**
   PDF 設定面板的 Fit 模式、雙頁模式、頁面方向、換頁動畫、裁切模式選項全部維持原本純 `IconButton`，白色/E-Ink 主題下選中狀態依然無法辨識——這正是 Issue 6 要解決的核心問題，PDF 這條格式完全沒有被涵蓋到。
   **修正方式**：依計畫 Task 2 補上實作與測試。

#### Important (Should Fix)

1. **`reader_settings_sheet.dart` 中「排版方向覆寫」／「翻頁模式覆寫」／「螢幕方向覆寫」三組含 `null`（代表「採用書籍設定／全域預設」）選項的 `ReaderOptionTile` 群組，存在會讓多個互斥選項同時顯示為「已選中」的邏輯 bug。**

   問題出在 `reader_settings_sheet.dart:779-799`（排版方向，同樣模式在 `818-838` 翻頁模式、`873-893` 螢幕方向重複出現三次）：
   ```dart
   final effectiveValue = mode ?? WritingMode.horizontal;
   final isNullSelected = _writingModeOverride == null;
   return ReaderOptionTile<WritingMode>(
     value: effectiveValue,
     groupValue: isNullSelected
         ? effectiveValue        // ← 問題：直接用「這顆 tile 自己的 effectiveValue」
         : (_writingModeOverride ?? WritingMode.horizontal),
     ...
   );
   ```
   當目前狀態 `_writingModeOverride == null`（即使用者尚未強制覆寫、採用書籍排版，這通常是**預設狀態**）時，`isNullSelected` 為 `true`。此時，**不論正在建構的是哪一顆 tile**（`book`／`vertical`／`horizontal` 任何一顆），`groupValue` 都被設成「該 tile 自己的 `effectiveValue`」，也就是必然等於 `value`——導致 `value == groupValue` 對**全部三顆 tile 同時成立**，三個互斥選項會**同時顯示為選中（黑底白字／`primaryContainer` 底色）**。

   這與 Issue 6 的目標（讓使用者能明確辨識「目前選中哪一個」）直接矛盾：使用者會看到「採用書籍排版」「強制直排」「強制橫排」三顆按鈕全部高亮，反而更難判讀目前真正生效的模式。同樣的邏輯錯誤在「翻頁模式覆寫」（`global`／`paginated`／`scroll`）與「螢幕方向覆寫」（`global`／`auto`／`lock0`／`lock90`／`lock180`／`lock270`，共 6 顆）也存在，螢幕方向這組甚至會出現 6 顆按鈕同時全亮的情況。
   實際點擊行為（`onSelected` 呼叫 `setState(() => _writingModeOverride = mode)`）語意正確、不受此 bug 影響，純粹是「選中狀態的視覺呈現」壞掉。
   **驗證方式**：可寫一個 widget test，在 `_writingModeOverride == null`（預設狀態）下同時斷言 `reader_settings_writing_mode_book`／`_vertical`／`_horizontal` 三個 Key 對應 `Container` 的 `BoxDecoration.color`，會發現三者同時為選中色（而非只有 `book` 為選中色）。目前的新增測試（`ReaderSettingsSheet 文字對齊與排版方向在 E-Ink 模式下具備高對比選中底色`）只測試了「文字對齊」（不含 `null` 分支，天生沒有這個問題），完全沒有覆蓋到這三組含 `null` 選項的群組，因此這個 bug 在目前的測試套件下是不可見的。
   **修正方式**：`groupValue` 不該用「這顆 tile 自己的 `effectiveValue`」，而應該用一個對所有 tile 都相同、且只有「代表 null 的那顆 tile」的 `effectiveValue` 才會相符的值。例如統一導入一個 sentinel（如 `WritingMode.horizontal` 只給 `null` 選項使用、其餘選項改用完全不會與任何真實值衝突的自訂 sentinel，或乾脆讓 `ReaderOptionTile` 支援 nullable 泛型 `T?`），目前這種「用其中一個真實 enum 值同時代表 sentinel」的作法在多個真實 enum 值都可能等於該 sentinel 時就會出錯。

#### Minor (Nice to Have)

2. **`fxl_settings_sheet_test.dart` 兩處既有測試的斷言被弱化，不再能鑑別「選中/未選中」狀態。**
   - `app/test/screens/fxl_settings_sheet_test.dart:63-68`：原本 `expect(button.color, isNotNull, reason: '目前選中的選項應以主題色標示')`，改造後變成 `expect((container.decoration as BoxDecoration).color, isNotNull, ...)`。但 `ReaderOptionTile` 不論選中與否，`BoxDecoration.color` 恆為非 `null`（選中是 `primaryContainer`/黑，未選中是 `surface`/白），所以這個斷言現在**不論選中邏輯對不對都會通過**，等同於失去鑑別力。
   - `app/test/screens/fxl_settings_sheet_test.dart:250-256`（原 `rtlButton.color, isNotNull` 斷言）被直接改成 `findsOneWidget`（只驗證元件存在），完全放棄了「選中狀態」的驗證。
   這兩處都不是計畫要求的改動（計畫沒有要求弱化既有測試），品質上建議補回等價於「選中時背景色為 `primaryContainer`/黑、未選中時為 `surface`/白」的明確斷言，而非用「反正一定非 null」規避。

---

## Issue 7：PDF 手動裁切疊加層高對比視覺與 FAB 按鈕重構

### 完成度總覽

- **Task 1**：✅ 已完整實作（commit `7750cc6`），忠實對照計畫（含計畫審查修正後版本），品質良好，測試通過。

### Strengths

- `CropOverlayPainter`（`app/lib/reader/pdf_crop_frame_overlay.dart`）**確實改用四個不重疊矩形色帶**繪製半透明遮罩（`drawRect` ×4，上/下/左/右），沒有使用 `Path.combine`，與計畫審查修正後的效能考量完全一致；雙層邊框（外黑 3px／內白 1.5px）也依計畫實作。
- `Positioned.fill(child: CustomPaint(painter: CropOverlayPainter(cropRect: frameRect, canvasSize: size)))` 確實取代了舊有的 `Positioned.fromRect + Container(border: ...)`，沒有出現計畫審查階段警示的「定義了卻沒接進畫面變成死碼」問題——已實際查證接線正確。
- `_buildHandle` 改為 32×32 圓形、黑色 1.5px 邊框、`boxShadow` 陰影，`key` 仍掛在最外層 `GestureDetector` 上（與既有 `tester.drag(find.byKey(...))` 相容）；四個既有 Key（`pdf_crop_frame_handle_top_left`／`top_right`／`bottom_left`／`bottom_right`）全數保留，已用 `grep` 逐一核對存在。
- 底部確認/取消按鈕改為 `Material(elevation: 6, shape: CircleBorder(...))` + `InkWell` 包裹的圓形 FAB 樣式，`pdf_crop_frame_cancel`／`pdf_crop_frame_confirm` 兩個既有 Key 保留，配色（取消 `0xFF2A2A2E`、確認 `0xFF16A34A`）與計畫逐字相符。
- 新增測試不只是機械照抄計畫片段，還**比計畫更嚴謹**：計畫的範例測試只驗證「有 `Material` 祖先」，實作的測試進一步用 `elevation == 6` 精確區分「FAB 樣式 Material」與「`IconButton` 內建的 `elevation: 0` Material」，避免假陽性，是這次審查中測試設計品質最好的一處。
- 實測：`flutter test test/reader/pdf_crop_frame_overlay_test.dart` 獨立執行，7 個測試（6 個既有＋1 個新增）全數通過，且此檔案不依賴 `reader_option_tile.dart`，不受 Issue 6 的編譯錯誤影響。

### Issues

#### Critical (Must Fix)

無。

#### Important (Should Fix)

無。

#### Minor (Nice to Have)

無實質問題；此 Issue 是四個當中執行品質最好的一個。

---

## Issue 8：書架排序選單加入當前模式選中指示

### 完成度總覽

- **Task 1**：✅ 已完整實作（commit `2136e86`，注意此 commit 同時夾帶了 Issue 5 Task 2 的改動，見上方 Issue 5 Important #2），忠實對照計畫，品質良好。

### Strengths

- `app/lib/screens/library_screen.dart` 的 `PopupMenuButton<LibrarySortBy>.itemBuilder` 改造與計畫 Step 3 程式碼片段逐字一致：固定 24dp 寬 `SizedBox` 放置 `Icons.check`（選中時）或 `null`（未選中時，確保左對齊一致），選中文字 `FontWeight.bold` + `primaryColor`。
- 新增測試（`LibraryScreen 點擊排序按鈕，彈出選單中當前選中的排序項目顯示 Checkmark 圖示`）確實遵循計畫審查修正後的 fixture 模式（`FakeLibraryRepository()`／`FakeBookImportService()`／共用 `prefsManager`），不是計畫審查前那種會直接編譯失敗的空建構寫法，已用 `git diff` 核對逐字相符。
- 邏輯正確：`isSelected = currentSort == sortBy`，預設排序 `lastRead` 的測試斷言 `find.descendant(of: lastReadItemFinder, matching: find.byIcon(Icons.check))` 能有效鑑別「有沒有正確標出目前選中項目」，不是空泛的存在性檢查。

### Issues

#### Critical (Must Fix)

無。

#### Important (Should Fix)

1. **本 commit 訊息只提到「Issue 8」，但實際上一併夾帶了 Issue 5 Task 2 的 AppBar E-Ink 按鈕改動（見上方 Issue 5 Important #2）**，導致單看 commit log 會誤判 Issue 5 完全沒有任何程式碼，需要靠實際比對程式碼才查得出來。

#### Minor (Nice to Have)

無。

---

## 全專案驗證結果

審查方式：用 `git worktree add --detach` 在獨立目錄（`C:/Users/huthief/AppData/Local/Temp/claude/review-epic27`）checkout 分支 `feat/epic-27-reader-device-compat` 的 HEAD（commit `0b653da`），確認該目錄乾淨、不含任何未提交變更（`git status --short` 為空），並確認 `app/lib/screens/widgets/` 目錄在此乾淨 checkout 中不存在，再執行以下指令。

### `flutter analyze`

**結果：FAIL，12 issues found（12 error，非 0 warning / 0 error）。**

```
error - Target of URI doesn't exist: 'widgets/reader_option_tile.dart' - lib\screens\fxl_settings_sheet.dart:6:8 - uri_does_not_exist
error - The method 'ReaderOptionTile' isn't defined for the type '_FxlSettingsSheetState' - lib\screens\fxl_settings_sheet.dart:88:24 - undefined_method
error - The method 'ReaderOptionTile' isn't defined for the type '_FxlSettingsSheetState' - lib\screens\fxl_settings_sheet.dart:112:24 - undefined_method
error - Target of URI doesn't exist: 'widgets/reader_option_tile.dart' - lib\screens\reader_settings_sheet.dart:14:8 - uri_does_not_exist
error - The method 'ReaderOptionTile' isn't defined for the type '_ReaderSettingsSheetState' - lib\screens\reader_settings_sheet.dart:555:22 - undefined_method
error - The method 'ReaderOptionTile' isn't defined for the type '_ReaderSettingsSheetState' - lib\screens\reader_settings_sheet.dart:744:20 - undefined_method
error - The method 'ReaderOptionTile' isn't defined for the type '_ReaderSettingsSheetState' - lib\screens\reader_settings_sheet.dart:783:20 - undefined_method
error - The method 'ReaderOptionTile' isn't defined for the type '_ReaderSettingsSheetState' - lib\screens\reader_settings_sheet.dart:825:20 - undefined_method
error - The method 'ReaderOptionTile' isn't defined for the type '_ReaderSettingsSheetState' - lib\screens\reader_settings_sheet.dart:878:20 - undefined_method
error - Target of URI doesn't exist: 'package:elinkbook/screens/widgets/reader_option_tile.dart' - test\screens\reader_settings_sheet_test.dart:6:8 - uri_does_not_exist
error - Undefined name 'ReaderOptionTile' - test\screens\reader_settings_sheet_test.dart:1342:29 - undefined_identifier
error - The name 'ReaderOptionTile' isn't a type, so it can't be used as a type argument - test\screens\reader_settings_sheet_test.dart:1344:43 - non_type_as_type_argument
```

這與 `docs/epics.md` 該分支變更中宣稱的「`flutter analyze` 0 warning 0 error」直接矛盾。

### `flutter test`

**結果：FAIL（compile 階段失敗，連帶拖垮多個測試檔）。**

- 全專案 `flutter test`（背景執行，逾時後移至背景，最終完整跑完）：最終彙總為 `+1309 -8`（1309 個測試通過、8 個失敗），因為輸出被 `tail` 截斷，無法確認全部 8 個失敗分別屬於哪些檔案，但已直接觀察到 `test/theme/theme_test.dart`、`test/app_lifecycle_sync_test.dart` 兩個檔案因 `Compilation failed ... Error when reading 'lib/screens/widgets/reader_option_tile.dart': 系統找不到指定的路徑。` 而整檔載入失敗（`[E]`）。
- 另外針對性執行 `flutter test test/screens/reader_settings_sheet_test.dart test/screens/fxl_settings_sheet_test.dart test/reader/pdf_crop_frame_overlay_test.dart test/screens/library_screen_test.dart`：結果 `+7 -3`，確認以下 3 個檔案因同一個編譯錯誤而**完全無法載入、0 個測試被執行**：
  - `test/screens/reader_settings_sheet_test.dart`
  - `test/screens/fxl_settings_sheet_test.dart`
  - `test/screens/library_screen_test.dart`（**重要**：這代表即使是 Issue 5 Task 2／Issue 8 這兩個確實做對的功能，其對應的新增測試也因為 Issue 6 Task 1 的缺失而完全無法執行、無法被驗證為通過——`library_screen.dart` 透過 `reader_screen.dart` 間接匯入了損毀的 `reader_settings_sheet.dart`）。
  - 唯一乾淨通過的是 `test/reader/pdf_crop_frame_overlay_test.dart`（7/7 全過，Issue 7 不依賴 `reader_option_tile.dart`）。
- 另外針對性執行 `flutter test test/screens/pdf_settings_sheet_test.dart test/screens/settings_screen_test.dart`：全數通過（因為這兩個檔案完全未被改動，本來就是舊測試、舊行為，不代表 Issue 5 Task 1／Issue 6 Task 2 的新驗收標準有被驗證）。

這與 `docs/epics.md` 宣稱的「全數相關測試通過」直接矛盾。

---

## Recommendations

1. **立即補齊 Issue 6 Task 1**（建立 `app/lib/screens/widgets/reader_option_tile.dart` 與對應測試），這是讓專案恢復可編譯狀態的唯一路徑——目前 Task 3 已提交的程式碼本身架構正確、忠實對照計畫，只差這一個檔案。
2. **補齊 Issue 6 Task 2**（`PdfSettingsSheet` 圖示選項改造），否則 Issue 6 的 PDF 這條格式完全沒有涵蓋到。
3. **補齊 Issue 5 Task 1**（`SettingsScreen` 的 E-Ink 開關），這是 Issue 5 兩個 Task 中完全沒有程式碼的一半。
4. **修正 Important #1 的邏輯 bug**（`reader_settings_sheet.dart` 三組含 `null` 選項的 `ReaderOptionTile` 群組會同時全部顯示為選中），並補上能鑑別此 bug 的測試（斷言 `null` 狀態下只有一顆 tile 選中，而非驗證存在性/顏色非空就結束）。
5. 修正後，重新以乾淨 checkout（非目前殘留在 `.worktrees/feat/epic-27-reader-device-compat` 下、含未提交變更的那份工作目錄）跑一次 `flutter analyze`／`flutter test`，確認真的 0 error 且相關測試全過，再更新 `docs/epics.md` 與四份 `plan-issue-*.md` 的 checkbox 狀態——目前這些文件所宣稱的完成度與實際程式碼不符，屬於需要優先修正的問題，不能直接採信後續合併。
6. 補回或至少不繼續使用像 `expect(color, isNotNull)` 這種在新元件下已經失去鑑別力的斷言模式（Issue 6 Minor #2）。
7. 建議之後每個 Issue／Task 維持「一個 Task 一個 commit」的紀律（本次 Issue 5 Task 2 與 Issue 8 被混進同一個 commit），方便之後追蹤與必要時的個別回退。

## Assessment

**Ready to merge? No.**

**各 Issue 完成狀態：**
- **Issue 5**：部分完成（Task 2 完成但未獨立 commit；Task 1 完全未做）。
- **Issue 6**：部分完成，且是導致專案編譯失敗的直接原因（Task 3 完成但依賴的 Task 1 完全未做；Task 2 完全未做）。
- **Issue 7**：完成，品質良好，可視為此分支中唯一「乾淨」的部分。
- **Issue 8**：完成，品質良好（但 commit 邊界不乾淨，夾帶了 Issue 5 Task 2）。

**Reasoning：**
`flutter analyze` 有 12 個 error、專案無法編譯，這本身就是不可合併的絕對阻擋條件，不需要再討論其他細節。往深一層看，這不是單純的「漏了一步」意外，而是 Issue 6 的四個 Task 中有兩個（Task 1、Task 2）完全沒有實作卻讓依賴它們的 Task 3 被單獨提交，且 `docs/epics.md`／四份計畫檔案的 checkbox 都被明確標記為「已全數完成」「`flutter analyze` 0 warning 0 error」——這些文件宣稱與實際程式碼狀態嚴重不符，若未經這次逐項核對直接採信文件說法就合併，會讓一個無法編譯的分支進入 `main`。建議：先依上方 Recommendations 補齊缺漏、修正邏輯 bug，並在提交前**實際執行**（而非僅憑閱讀程式碼或相信先前 commit 訊息）`flutter analyze`／`flutter test` 驗證兩者皆為綠燈後，再重新提出合併。Issue 7 與 Issue 8（獨立來看）的程式碼品質本身是達到可合併標準的，只是被同一個分支中其他未完成的 Issue 6 拖累而無法單獨驗證/合併。
