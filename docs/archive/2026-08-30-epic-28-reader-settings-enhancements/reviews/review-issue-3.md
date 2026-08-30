# Epic 28 Issue 3 — Task 1~11（全範圍）程式碼審查報告

**審查範圍**：`c9719121e2904cc8d43e9965f2d610964dedf72a..908fc24`（分支 `feat/epic-28-issue-3-layout-presets`），涵蓋計畫文件 Task 1 至 Task 11 全部——資料層（Task 1-7，第一輪審查範圍）＋ UI 層與 App 層貫穿（Task 8-11，本輪新增範圍）。共 25 個檔案、+2184/-93 行。

**驗證方式**：使用既有 worktree `U:/MyDeveloper/AI/elinkBook/.worktrees/epic-28-issue-3`（已確認精確位於 head SHA `908fc24`，working tree clean），在 `app/` 目錄下實際執行 `flutter analyze`／`flutter test`（非分批抽查，逐一讀完全部 25 個變更檔案的 diff，含 lib 與 test 兩側）。

**與第一輪審查（Task 1-7）的銜接**：第一輪報告的 2 則 Important（`fromMap()` 與 `reflowableEpubFields()` 兩則測試遺漏第 10/11 個欄位 `pdfPageTurnAnimation` 的斷言）已在 commit `329446f` 修正——已核對 `app/test/reader/book_reader_prefs_test.dart` 該次 diff，確認兩則測試皆已補上 `pdf_page_turn_animation`/`pdfPageTurnAnimation` 的覆寫與斷言，**視為已解決，不重複列入本報告**。第一輪 3 則 Minor 維持原判定不要求修改，此處不重複列出。

---

## Strengths

1. **`isCurrentBookOnly` 覆蓋確認對話框的觸發邏輯完全正確落實計畫的關鍵修正**——`app/lib/screens/reader_screen.dart` 的 `_handleApplyPreset`／`_handleApplyFromBook` 兩處皆為 `targetBookIds.length == 1 && targetBookIds.single == widget.bookId`，而非計畫特別警告過的錯誤版本 `targetBookIds.length > 1`。這點在 `app/test/screens/reader_screen_test.dart` 的「套用預設集到其他書籍（多本）」測試中被實質驗證：測試流程透過「套用到其他書籍」picker **只勾選一本書**（`b_other`），程式仍必須跳出「即將覆蓋 N 本書」確認對話框（`layout_preset_apply_confirm`）才能繼續，測試中確實有對應的 `tap`——若實作誤用 `length > 1`，這個 `tap` 會找不到該 Key 而拋出例外、測試失敗。這是測試層面對此陷阱邏輯的有效防線，不只是程式碼審查層面的目視確認。
2. **UI 層正確銜接資料層既有設計、沒有繞過任何一道防護**：「另存為預設集」（`_handleSaveAsPreset`）與「複製其他書籍設定」（`_handleApplyFromBook`）在寫入 `LayoutPresetRepository`／`BookReaderPrefsRepository` 前都正確呼叫了 `reflowableEpubFields()`；`LayoutPresetRepository` 本身確實不做過濾、也不做「最多 3 組」上限檢查，上限判斷（`_layoutPresets.length < 3`）與命名驗證（`validateLayoutPresetName()`）都正確留在 `ReaderScreen`／Dialog 層，與計畫設計一致。批次寫入正確依目標數量分流（單一書籍走既有 `save()`，多本書籍才走 `saveMultiple()`）。
3. **Bottom Sheet 開啟中即時同步的補強是計畫外但正確必要的工程判斷**：`_openLayoutSettings()` 額外引入 `StatefulBuilder` 並在 5 個 callback 完成後呼叫 `setSheetState?.call(() {})`，確保「刪除預設集」「套用到目前書籍」等操作後，已經開啟的 Bottom Sheet 能立即反映新的 `_layoutPresets`／`_prefs`（單純依賴 `_ReaderScreenState.setState()` 不會自動觸發已開啟 Modal Route 內容重建）。這點被 `reader_screen_test.dart`「套用預設集到目前書籍」測試中對 `sheetAfterApply.prefs.fontSize` 的斷言實際驗證，而非只是理論推測。
4. **`LayoutPresetBookPickerScreen` 精確落實計畫的單選/複選規格**：單選點擊立即 `pop([book.id])`；複選用 `CheckboxListTile` ＋ AppBar「確定」按鈕，且按鈕在 `_selected.isEmpty` 時 `onPressed: null` 正確停用；空清單顯示提示文字而非崩潰或空白畫面。三種情境（單選/複選/空清單）皆有對應 widget test，且皆用 `find.byKey(...)` 而非文字比對，符合「Key-based lookup」要求。
5. **App 層貫穿（Task 11）完整且有專門的回歸測試**：`main.dart`／`ElinkBookApp`／`LibraryScreen`／`ReaderScreen` 四層皆正確傳遞 `layoutPresetRepository`／`bookReaderPrefsRepository`，`library_screen_test.dart` 新增的貫穿測試用 `same()` 斷言＋明確的失敗訊息（說明「未貫穿會導致哪個功能完全無法使用」），對後續維護者非常友善。
6. **`FakeLibraryRepository`／`FakeBookReaderPrefsRepository` 兩個測試替身都同步更新**，避免「新增抽象成員後其他呼叫端編譯失敗」的常見回歸問題；`FakeLibraryRepository.listReflowableEpubBooks()` 的判斷邏輯（副檔名 `.epub` + `isFixedLayout != true`）與正式 `SqliteLibraryRepository` 實作語意一致。
7. **測試涵蓋真實行為而非純 mock**：`reader_screen_test.dart` 新增的「版面設定預設集」測試群組使用真實 in-memory SQLite（`LayoutPresetRepository`／`BookReaderPrefsRepository` 皆連到同一個 `SqliteLibraryRepository.database`），驗證的是「UI 操作 → 實際資料庫寫入/讀出」的端到端行為，而非只驗證 callback 有沒有被呼叫。
8. **`flutter analyze` 乾淨、`flutter test` 全數通過**（詳見下方「Testing 附錄」），零回歸。

---

## Issues

### Critical (Must Fix)

無。

### Important (Should Fix)

1. **刪除預設集沒有任何確認機制，與同一功能內其他破壞性操作的既定模式不一致**
   - 檔案：`app/lib/screens/reader_screen.dart` 的 `_handleDeletePreset()`；`app/lib/screens/reader_settings_sheet.dart` 的 `_buildPresetSlot()`（`reader_settings_preset_slot_${index}_delete` `IconButton`）。
   - 問題：`onPressed: () => widget.onDeletePreset(preset.id!)` 點擊後直接呼叫 `_handleDeletePreset(id)`，內部只有 `await repository.delete(id); await _loadLayoutPresets();`，沒有任何 `showDialog` 確認步驟。相對地，同一支程式碼內「覆蓋既有預設集」（`_confirmOverwrite`）與「套用到其他書籍」（`_confirmApplyToOtherBooks`）都明確有二次確認對話框。
   - 為何重要：刪除是不可逆操作（`LayoutPresetRepository.delete()` 沒有回收機制），使用者一次誤觸 `IconButton` 就會直接遺失一組已調校好的版面設定，且此按鈕與「套用到本書」「套用到其他書籍」三顆圖示按鈕並排在同一列（見 `_buildPresetSlot()`），誤觸機率不低。這也與專案既有慣例不一致——`CLAUDE.md` 明確記載劃線/備註的「一鍵全刪」都需要確認對話框；`design.md` 雖只列出「新增/命名/刪除」三項管理能力字面上沒有明確要求刪除要二次確認，但從產品一致性與資料保護角度看，這是一個值得在合併前確認是否為刻意決定的缺口，而非單純的 nice-to-have。
   - 建議修法：比照既有 `_confirmOverwrite()`/`_confirmApplyToOtherBooks()` 的 `showDialog<bool>` 模式，在 `_handleDeletePreset()` 呼叫 `repository.delete()` 前插入一個「確認刪除預設集『{name}』」的 `AlertDialog`。

2. **`_loadLayoutPresets()` 缺少 try/catch，與同檔案內兩個姊妹載入方法的既有慣例不一致**
   - 檔案：`app/lib/screens/reader_screen.dart:949-955`
   - 問題：
     ```dart
     Future<void> _loadLayoutPresets() async {
       final repository = widget.layoutPresetRepository;
       if (repository == null) return;
       final presets = await repository.listAll();
       if (!mounted) return;
       setState(() => _layoutPresets = presets);
     }
     ```
     同一個檔案裡結構幾乎一模一樣的 `_loadFxlBookmarks()`（829 行附近）與 `_loadCustomFonts()`（880 行附近）都用 `try { ... } catch (e) { debugPrint(...); }` 包裹核心讀取邏輯，唯獨這次新增的 `_loadLayoutPresets()` 沒有。
   - 為何重要：`LayoutPresetRepository._fromRow()`（`app/lib/reader/layout_preset_repository.dart`）內部對 `prefs_json` 呼叫 `jsonDecode()` 且沒有自己的例外處理；一旦資料庫裡出現任何一列毀損的 `prefs_json`（例如未來版本升級、資料同步、或人工資料庫操作造成的異常資料），`listAll()` 會直接拋出未捕捉例外。因為 `_loadLayoutPresets()` 是在 `initState()` 內以 fire-and-forget 方式呼叫（不 `await`），這個例外會變成未捕捉的 async 例外交給 Zone 處理，且沒有任何降級行為——不像 `_loadCustomFonts()` 失敗時至少會設定 `_customFontsLoaded = true` 讓後續流程不被卡住。目前程式碼下這不影響開書流程本身（預設集功能本來就是可選的），但相較於同檔案內兩個姊妹方法明確示範的容錯模式，這裡的不一致值得補上，避免未來維護者誤以為「這個模式在這支檔案裡不需要」。
   - 建議修法：比照 `_loadCustomFonts()`，加上 `try { ... } catch (e) { debugPrint('Failed to load layout presets: $e'); }`。

### Minor (Nice to Have)

1. **「選擇要覆蓋的預設集」`SimpleDialog` 沒有明確的「取消」選項**
   - 檔案：`app/lib/screens/reader_screen.dart` 的 `_selectPresetToOverwrite()`
   - 說明：`SimpleDialog` 的 `children` 只列出 3 個預設集選項本身，使用者若要放棄「另存為新預設集」流程，只能依賴點擊對話框外部遮罩或系統返回鍵（`showDialog` 預設 `barrierDismissible: true`，回傳 `null` 後 `_handleSaveAsPreset` 正確以 `if (target == null || !mounted) return;` 處理，功能上沒有問題），但畫面上沒有顯式的「取消」文字選項，對不熟悉手勢的使用者不夠直覺。不影響功能正確性，純 UX 打磨建議。

2. **「為預設集命名」Dialog 對驗證失敗（trim 後為空字串）沒有任何錯誤提示**
   - 檔案：`app/lib/screens/layout_preset_name_dialog.dart`
   - 說明：使用者若只輸入空白字元後點擊「儲存」，`validateLayoutPresetName()` 回傳 `null`，`Navigator.pop(null)` 直接關閉對話框，`_handleSaveAsPreset` 因 `name == null` 靜默 return——使用者不會看到任何「名稱不可為空」之類的提示，只會發現「儲存」按鈕點了但畫面上什麼都沒發生，可能誤以為是操作失敗或沒反應。計畫本身也沒有要求這裡要有錯誤訊息（純粹視為「拒絕儲存」的降級行為），不要求本次修改，但值得記錄供後續 UX 打磨參考。

---

## Recommendations

- Important 1、2 兩則都是小改動（前者需要新增一個確認對話框，後者只需要包一層 try/catch），若團隊認為值得在合併前處理，工作量都不大；若判斷「單一使用者本機應用、資料庫毀損機率極低、刪除誤觸影響有限」在目前產品階段可以接受，也可以有意識地記錄為已知取捨後合併，不強制視為阻擋合併的理由。
- `_openLayoutSettings()` 新增的 `StatefulBuilder` + `setSheetState` 手動觸發重建模式，是一個對「Bottom Sheet 內容不會隨外層 State 自動重建」這個 Flutter 常見陷阱的正確修法，但目前只在這一個呼叫點使用；如果後續其他 Bottom Sheet（`PdfSettingsSheet`／`FxlSettingsSheet`）也有類似「開啟中需要即時反映外部資料變化」的需求，可以考慮沿用同一個模式，值得記錄在該檔案的類別文件或 ADR 中，避免下一次遇到類似情境時重新摸索。

## Assessment

**Ready to merge？** With fixes（建議：Important 1「刪除無確認」建議在合併前處理，因為它是一個會直接造成使用者資料遺失、且與同功能其他破壞性操作行為不一致的落差；Important 2「載入缺 try/catch」風險較低，可視團隊風險偏好決定是否在合併前一併補上或留待後續小 commit）。

**Reasoning：** Task 1-11 全範圍的資料層與 UI 層實作與計畫高度一致，尤其是本輪審查重點關注的 `isCurrentBookOnly` 覆蓋確認邏輯、`reflowableEpubFields()` 過濾時機、UI 對資料層既有設計（`saveMultiple()`／`listReflowableEpubBooks()`／不做上限檢查的責任劃分）的呼叫方式，全部正確無誤且有對應測試防線；`flutter analyze` 乾淨、`flutter test` 全數 1263 則通過，沒有發現 Critical 或架構層級問題。兩則 Important 皆屬「已知風險可控、但值得修正」等級（分別是缺少刪除確認的資料保護落差、以及一處與姊妹方法不一致的錯誤處理落差），不影響核心功能正確性，是否阻擋合併可由團隊風險偏好決定。

---

## Testing 附錄

- `flutter analyze`（於 `U:/MyDeveloper/AI/elinkBook/.worktrees/epic-28-issue-3/app`，head SHA `908fc24`）：**No issues found!**（61.8s）
- `flutter test`（同上路徑，全專案）：**All tests passed!**（1263 則，含本輪新增的 `reader_screen_test.dart`「版面設定預設集」測試群組、`reader_settings_sheet_test.dart`／`layout_preset_book_picker_screen_test.dart`／`library_screen_test.dart` 新增測試，零回歸）。
