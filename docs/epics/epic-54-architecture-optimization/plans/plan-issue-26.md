# Issue 26：版面預設集流程 module 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 把 `ReaderScreen` 裡約 355 行的版面預設集流程（另存、套用、從其他書複製、刪除，加三個確認對話框、一個覆蓋目標選單、4 份重複的錯誤處理、4 個 `setSheetState` 包裝）收成 `LayoutPresetFlow`。純重構、零行為變化。

**Architecture：** 新增 `app/lib/reader/layout_preset_flow.dart`（`LayoutPresetOutcome`、`LayoutPresetPrompts`、`LayoutPresetFlow extends ChangeNotifier`）與 `app/lib/screens/layout_preset_dialogs.dart`（把 `LayoutPresetPrompts` 接到真實對話框的畫面端實作）。`ReaderScreen` 以 `late final LayoutPresetFlow _presetFlow` 持有；`_openLayoutSettings` 改用 `ListenableBuilder`。`layout_preset_actions.dart` 併入後刪除。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 26 設計決策」（決策 1～12）；詞彙見 `CONTEXT.md`「版面設定預設集」。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **純重構、零行為變化**（決策 1）：對話框出現順序、寫入時機、`mounted` 檢查結果、失敗時的 SnackBar 鍵與訊息逐字保留。`_handlePrefsChanged` 一個字都不改（那是 Issue 31）。
- **對話框順序**：另存 = 取名 →（已滿 3 組才）選覆蓋目標 → 覆蓋確認 → 寫入；套用 = （目標不是「只有目前書籍」才）確認 → 寫入 →（目標含目前書籍才）呼叫 `onCurrentBookPrefsApplied`。
- **「只有目前書籍」的判斷刻意不是 `targetBookIds.length > 1`**：用 `targetBookIds.length == 1 && targetBookIds.single == currentBookId`（原 `layoutPresetTargetsCurrentBookOnly`，併入後保留同一語意與單元測試）。
- **從其他書複製有兩層獨立保護**：讀取來源書籍設定失敗，與後續套用失敗，各自 try／catch，同一次失敗只回報一次 `failed`，不重複顯示兩次 SnackBar。
- **過濾責任**：寫入預設集或從其他書複製前，必須先 `reflowableEpubFields()` 過濾（原行為）。
- **`mounted` 檢查移出 flow**：flow 不知道 `mounted`。畫面端實作在**顯示對話框之前與每個對話框關閉後**都檢查 context，已卸載就回傳取消（`null`／`false`）。flow 自己的 `dispose` 旗標管三件事：「寫入完成後不再 `notifyListeners`」「不再呼叫 `onCurrentBookPrefsApplied`」「從其他書複製在 `load` 完成後被 dispose 則回 `cancelled`、不寫入」。現況每個 `mounted` 檢查點的新歸屬見下方「`mounted` 檢查點對照表」。
- **通知規則（計畫審查 C-1）**：現況 4 個預設集回呼處理完都無條件 `setSheetState`，面板「套用後」靠它才拿到新 `_prefs`（`ReaderSettingsSheet.didUpdateWidget` 同步草稿）。所以 flow 四個操作**結束時不論 `done`、`cancelled`、`failed` 都 `notifyListeners()` 一次**（dispose 後不通知）；套用／複製成功且目標含目前書籍時，**先**呼叫 `onCurrentBookPrefsApplied(prefs)`，**再**通知，面板重畫時 `_prefs` 已是新值。
- **`dispose` 冪等**（M-4）：比照 `OpenBookFlow.dispose`：`if (_disposed) return; _disposed = true; super.dispose();`，測試同時 `addTearDown(flow.dispose)` 與手動 dispose 不會拋錯。
- **載入失敗**只 `debugPrint`，清單保持空（原行為）。
- **不碰 `BuildContext`、不新增 `ReaderScreen` 建構參數、不做工廠**。
- **範圍外**：`_handlePrefsChanged` 與 `saveBookPrefs`（Issue 31）；`_handleRequestBookPicker` 留在 `ReaderScreen`；兩份 `_buildSliderRow`；`ReaderSettingsSheet` 本身與其本地狀態（草稿具現化原則）；三個 SnackBar 鍵與文案。
- **測試原則（replace, don't layer）**：`layout_preset_actions_test` 遷移進 `layout_preset_flow_test`，舊檔刪除；`reader_screen_test.dart` 只刪「純邏輯、已被 flow 測試完整涵蓋」的案例。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，不要同時跑第二個）。
- **每個 Task／commit 結束都必須可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**。
- **提交前**：`flutter analyze` 必須 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔。
- **Commit**：不加 `Co-Authored-By`。每個 Task 一個 commit。
- **不要提交** `app/android/gradle.properties`、`app/analysis_options.yaml`（`flutter analyze` 會自動改寫它；提交前 `git checkout app/analysis_options.yaml`，不要夾帶）。
- **計畫與實作同分支同 PR**，不另開文件分支。

## Review Focus

最可能咬到使用者的情況（依可能性排序）：

1. **面板在預設集變動後沒重畫**（改成 `ListenableBuilder` 後）。→ Task 3 Step 6 在「另存」「刪除」案例**新增**槽位出現／消失斷言（現有案例只查資料庫，抓不到不重畫）；「套用到目前書籍」案例（約 10257）斷言面板的 `prefs.fontSize` 已是新值，是通知規則（C-1）的守門案例。
2. **`dispose` 後仍 `notifyListeners` 而拋例外**，或寫入完成後呼叫已卸載畫面的回呼。→ Task 1 測「`dispose` 後完成的寫入不通知、不呼叫 `onCurrentBookPrefsApplied`」。
3. **對話框順序或次數改變**，例如「只有目前書籍」誤跳確認，或已滿 3 組時沒跳覆蓋選單。→ Task 1 用假對話框記錄呼叫順序。
4. **同一次失敗 SnackBar 顯示兩次**（從其他書複製的兩層保護）。→ Task 1 測讀取失敗只回傳一次 `failed`；`reader_screen_test.dart` 約 10578 案例維持綠。
5. **使用者在對話框開著時退出閱讀器**，之後仍寫入。→ Task 2 測畫面端實作在 context 為 null 時回傳取消；flow 在 `cancelled` 時不寫入。
6. **目標含目前書籍時畫面沒即時刷新**（`onCurrentBookPrefsApplied` 沒被呼叫或順序錯）。→ `reader_screen_test.dart` 約 10257 案例維持綠。
7. **預設集清單在開書時沒載入**。→ `initState` 呼叫 `_presetFlow.load()`，面板開啟時應有既有預設集。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/layout_preset_flow.dart` | 新增 | `LayoutPresetOutcome`、`LayoutPresetPrompts`、`LayoutPresetFlow` |
| `app/lib/reader/layout_preset_actions.dart` | 刪除 | 併入 flow |
| `app/lib/screens/layout_preset_dialogs.dart` | 新增 | `LayoutPresetPrompts` 的畫面端實作（覆蓋選單、三個確認對話框、取名對話框接線；context 為 null 即取消） |
| `app/lib/screens/reader_screen.dart` | 修改 | 用 `_presetFlow`；刪 `_layoutPresets`、`_loadLayoutPresets`、五個處理方法、三個確認對話框、覆蓋選單；`_openLayoutSettings` 改 `ListenableBuilder`；`dispose` 釋放 flow |
| `app/test/reader/layout_preset_flow_test.dart` | 新增（由 `layout_preset_actions_test.dart` 改名） | flow 契約、各情境 |
| `app/test/screens/layout_preset_dialogs_test.dart` | 新增 | 畫面端實作的取消語意 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 刪「刪除確認取消不刪除」案例（移到 flow 測試）；另存、刪除案例新增面板槽位斷言；同步修改 112、10307–10308 行註解中的舊名稱；其餘預設集案例保留 |
| `app/test/support/fake_layout_preset_repository.dart`、`fake_book_reader_prefs_repository.dart` | 修改 | 新增 `failOn` 參數（注入例外） |
| `CONTEXT.md`、`epic.md`、`issues.md`、`docs/epics.md` | 已完成 | 設計定案時已更新 |

## Interface 草案（以實際編譯與既有型別為準）

```dart
enum LayoutPresetOutcome { done, cancelled, failed }

/// flow 需要問使用者的事；畫面端以真實對話框實作，測試以假的實作。
abstract interface class LayoutPresetPrompts {
  Future<String?> askName();
  Future<LayoutPreset?> pickOverwriteTarget(List<LayoutPreset> presets);
  Future<bool> confirmOverwrite(String presetName);
  Future<bool> confirmApplyToOthers(int bookCount);
  Future<bool> confirmDelete(String presetName);
}

/// 版面設定預設集 module：持有清單，ChangeNotifier。不碰 BuildContext。
class LayoutPresetFlow extends ChangeNotifier {
  LayoutPresetFlow({
    required LayoutPresetRepository presetRepository,
    required BookReaderPrefsRepository prefsRepository,
    required String currentBookId,
    required LayoutPresetPrompts prompts,
    required void Function(BookReaderPrefs prefs) onCurrentBookPrefsApplied,
  });

  List<LayoutPreset> get presets;

  /// 載入失敗只 debugPrint，清單保持原樣。
  Future<void> load();

  Future<LayoutPresetOutcome> saveAsPreset(BookReaderPrefs currentDraft);
  Future<LayoutPresetOutcome> applyPreset(LayoutPreset preset, {required List<String> targetBookIds});
  Future<LayoutPresetOutcome> applyFromBook(String sourceBookId, {required List<String> targetBookIds});
  Future<LayoutPresetOutcome> deletePreset(int id);

  @override
  void dispose(); // 設旗標；之後不再 notifyListeners、不再呼叫 onCurrentBookPrefsApplied
}
```

> 取消 = 任何一個對話框回傳 `null`／`false`；`targetBookIds` 為空也回 `cancelled`（原 `if (targetBookIds.isEmpty) return;`）。失敗 = 見下方「語意釘點」。
> 原 `layout_preset_actions.dart` 的 `layoutPresetTargetsCurrentBookOnly`、`insertNewLayoutPreset`（含 `DateTime.now()`）、`overwriteLayoutPreset`（含 `assert(target.id != null)`）、`deleteLayoutPreset`、`applyLayoutPresetPrefs`（單筆 `save`／批次 `saveMultiple`）併入 flow 的私有方法，語意逐字保留。

### 語意釘點（計畫審查 I-4；執行者不得自行調整）

1. **「是否滿 3 組」在 `askName` 回傳之後才判斷**（原 `reader_screen.dart` 898 行在取名對話框之後才讀 `_layoutPresets.length`），不在方法開頭判斷。
2. **try／catch 範圍**：另存的 `askName`、`pickOverwriteTarget`、`confirmOverwrite` 都在 try 內（prompt 丟例外 → `failed`）；套用的 `confirmApplyToOthers` 在 try 內；**刪除的 `confirmDelete` 在 try 之外**（原 1104 行），它丟例外時直接往上拋，不顯示 SnackBar。
3. **`onCurrentBookPrefsApplied` 在 try 內**（原 1041 行）：回呼丟例外 → `failed`（顯示套用失敗 SnackBar）。
4. **`applyFromBook` 空清單在 `load` 之前就回 `cancelled`**（原 1072 行），不多讀一次來源書籍。
5. **刪除找不到 id**：`presetName` 用空字串，仍跳確認（原 1097–1103 行），不可改成回 `cancelled`。
6. **空清單保護**：`applyPreset`／`applyFromBook` 頂層先判空回 `cancelled`；內層寫入私有函式不再重複判空（併入後變成不可達的死碼，不保留）。「空清單不寫入」由公開 API 測試涵蓋。
7. **log 格式**：載入失敗 `debugPrint('Failed to load layout presets: $e')`（無 stackTrace）；操作失敗 `debugPrint('<訊息>：$e\n$stackTrace')`，三種訊息沿用原文：`另存為新預設集失敗`、`套用版面設定失敗`（套用與從其他書複製共用）、`刪除預設集失敗`。

### `mounted` 檢查點對照表（計畫審查 I-3）

| 現況檢查點 | 新歸屬 |
|---|---|
| 另存：取名後 `name == null` 或 `!mounted` | 畫面端 `askName` 回 `null` |
| 另存：選覆蓋目標後 `target == null` 或 `!mounted` | 畫面端 `pickOverwriteTarget` 回 `null` |
| 另存：覆蓋確認後 `!confirmed` 或 `!mounted` | 畫面端 `confirmOverwrite` 回 `false` |
| 另存：寫入後 `!mounted` 才 `setState` | flow dispose 旗標：寫入已完成，不通知 |
| 套用：確認後 `!confirmed` 或 `!mounted` | 畫面端 `confirmApplyToOthers` 回 `false` |
| 套用：寫入後 `!mounted` 才呼叫 `_handlePrefsChanged` | flow dispose 旗標：不呼叫 `onCurrentBookPrefsApplied` |
| 從其他書：`load` 後 `!mounted`（1076 行） | **flow dispose 旗標：回 `cancelled`、不往下寫** |
| 刪除：確認後 `!confirmed` 或 `!mounted` | 畫面端 `confirmDelete` 回 `false` |
| 刪除：刪除後 `!mounted` 才 `setState` | flow dispose 旗標：不通知 |
| 各 catch 內 SnackBar 前 `!mounted` | `_showPresetError` 內檢查 `mounted` |

---

### Task 0：提交設計文件與計畫

- [x] **Step 1：** 分支 `epic-54/issue-26-layout-preset-flow`（已從含 PR #364 的 `main` 建立）。
- [x] **Step 2（commit `ae26766d`）：** 提交 `CONTEXT.md`、`epic.md`、`issues.md`、`docs/epics.md`、本計畫（純文件，一個 commit）。不提交 `app/analysis_options.yaml`、`app/android/gradle.properties`。

### Task 1：`LayoutPresetFlow` 與測試

**Files：** 新增 `layout_preset_flow.dart`、`test/reader/layout_preset_flow_test.dart`（由 `layout_preset_actions_test.dart` 以 `git mv` 改名後改寫）；暫不刪 `layout_preset_actions.dart`（Task 3 刪）。

- [x] **Step 1：** `git mv test/reader/layout_preset_actions_test.dart test/reader/layout_preset_flow_test.dart`；原有案例改為對 flow 的斷言：
  - `layoutPresetTargetsCurrentBookOnly` 四個案例（`[current]` 為真；多本即使含 current 為假；單本但不是 current 為假；空清單為假）改測 `applyPreset` 的「是否跳確認」：只有目前書籍不跳、其餘跳。
  - `insertNewLayoutPreset` 兩個案例 → 另存未滿 3 組：清單含新預設集且已有 id；清單依插入順序。
  - `overwriteLayoutPreset` 兩個案例 → 另存已滿 3 組：覆蓋後 id／createdAt 不變、name／prefs 更新；`target.id` 為 null 的案例改寫為「`pickOverwriteTarget` 回傳 id 為 null 的預設集 → `saveAsPreset` 回傳 `failed`，repository 沒有任何寫入」（`AssertionError` 會被 flow 的 catch 抓走，與現況在 `_handleSaveAsPreset` try 內顯示失敗 SnackBar 一致；不可寫成 `throwsA(AssertionError)`，也不可為了遷就測試拿掉 catch；I-5）。
  - `deleteLayoutPreset` 一個案例 → `deletePreset`：刪除後清單不含該筆、其餘保留。
  - `applyLayoutPresetPrefs` 三個案例 → 單筆走 `save`、多本走 `saveMultiple`、空清單不寫入且回傳 `cancelled`（語意釘點 6）。
  - **假 repository 來源**（M-3）：資料持久性案例沿用舊測試的 sqlite（`LayoutPresetRepository` 搭 in-memory 資料庫）；需要注入例外的案例用 `FakeLayoutPresetRepository`／`FakeBookReaderPrefsRepository`，**新增 `failOn` 參數**（指定哪個方法丟例外），放在 `test/support/`，不複製 `reader_screen_test.dart` 內私有的 `_Throwing…` 類別。
- [x] **Step 2（紅）：** 新增案例（用假的 `LayoutPresetPrompts` 記錄呼叫順序、假的 repository 可注入例外）：
  - `load()`：載入後 `presets` 為 repository 內容並通知一次；丟例外時清單不變、不丟出。
  - 另存：取名取消 → `cancelled` 且不寫入；已滿 3 組時順序 = 取名 → 選目標 → 覆蓋確認 → 寫入；選目標取消、覆蓋確認取消 → `cancelled` 且不寫入；寫入丟例外 → `failed`；寫入前用 `reflowableEpubFields()` 過濾（斷言寫入的 prefs 不含非流式欄位）；成功後 `presets` 更新並通知。
  - 套用：目標不是「只有目前書籍」時先 `confirmApplyToOthers(count)`，取消 → `cancelled` 且不寫入；寫入丟例外 → `failed`；目標含目前書籍時寫入成功後呼叫 `onCurrentBookPrefsApplied(prefs)` 一次**且先於通知**，不含時不呼叫；`onCurrentBookPrefsApplied` 丟例外 → `failed`（釘點 3）；`confirmApplyToOthers` 丟例外 → `failed`（釘點 2）。
  - 從其他書複製：讀取來源書籍丟例外 → `failed` 且只回報一次（不再往下套用）；成功時以 `reflowableEpubFields()` 過濾後的 prefs 交給套用；`targetBookIds` 為空 → `cancelled` 且來源書籍的 `load` **沒有被呼叫**（釘點 4）；`load` 完成後 flow 已被 dispose → `cancelled` 且不寫入（I-3）。
  - 刪除：確認取消 → `cancelled` 且不刪除（取代 `reader_screen_test.dart` 約 10497 的案例）；刪除丟例外 → `failed`；成功後清單更新並通知；id 不存在 → 仍以空字串名稱呼叫 `confirmDelete`（釘點 5）；`confirmDelete` 丟例外 → 例外往上拋、不回 outcome（釘點 2）。
  - 另存補充：`presets.length` 在 `askName` 回傳**之後**才判斷（釘點 1，測法：`askName` 的假實作在回傳前先讓 repository 多一筆，使長度由 2 變 3，斷言走覆蓋流程）；`askName`／`pickOverwriteTarget`／`confirmOverwrite` 丟例外 → `failed`（釘點 2）。
  - 通知（C-1）：四個操作各測「結束時通知至少一次」（含 `cancelled`、`failed`）；套用含目前書籍時回呼先於通知（用一個記錄事件順序的 list 斷言）。
  - `dispose`：`dispose` 後才完成的寫入不通知、不呼叫 `onCurrentBookPrefsApplied`；連續呼叫兩次 `dispose` 不拋錯（M-4）。
- [x] **Step 3（綠）：** 實作 `layout_preset_flow.dart`。
- [x] **Step 4：** `flutter analyze`；跑 `test/reader/layout_preset_flow_test.dart`；commit。

### Task 2：畫面端對話框實作

**Files：** 新增 `layout_preset_dialogs.dart`、`test/screens/layout_preset_dialogs_test.dart`。

- [x] **Step 1（紅）：** 寫測試（`MaterialApp` 必須帶 `locale` 與 `localizationsDelegates`，直接使用 `test/support/pump_localized_widget.dart`，否則 `check_l10n_hardcoded_strings.js` 會報；M-2）：`BuildContext? Function()` 回傳 `null`（畫面已卸載）時，五個方法都回傳取消（`null`／`false`），不丟例外，且**沒有嘗試顯示對話框**；另用一個可翻轉的 getter 測「對話框開著時畫面被卸載」：對話框顯示後把 getter 翻成 `null`，關閉對話框，回傳值仍為取消；context 有效時各對話框的確認／取消回傳值正確，鍵沿用 `layout_preset_overwrite_option_${id}`、`layout_preset_overwrite_cancel`、`layout_preset_overwrite_confirm`、`layout_preset_apply_confirm`、`layout_preset_delete_confirm`。
- [x] **Step 2（綠）：** 把 `reader_screen.dart` 約 934–1004、1126–1147 的 `_selectPresetToOverwrite`、`_confirmOverwrite`、`_confirmApplyToOtherBooks`、`_confirmDeletePreset` 原樣搬入（文案、鍵、`DateFormat` 不變）；`askName` 呼叫既有 `showLayoutPresetNameDialog`。每個方法在顯示對話框**之前**先取 context（為 `null` 就直接回傳取消，不呼叫 `showDialog`），`await` 對話框**之後**再取一次，已卸載就回傳取消。新檔 import：`package:intl/intl.dart`、`../l10n/app_localizations.dart`、`../reader/layout_preset.dart`、`../reader/layout_preset_flow.dart`、`layout_preset_name_dialog.dart`。**此 Task 不刪 `reader_screen.dart` 的舊方法**（Task 3 才換）。
- [x] **Step 3：** `flutter analyze`；跑 `test/screens/layout_preset_dialogs_test.dart`、`layout_preset_name_dialog_test.dart`；commit。

### Task 3：`ReaderScreen` 遷移（一個 commit）

**Files：** `reader_screen.dart`、`layout_preset_actions.dart`（刪除）、`test/screens/reader_screen_test.dart`。

- [x] **Step 1：** 新增 `late final LayoutPresetFlow _presetFlow = LayoutPresetFlow(presetRepository: widget.dependencies.layoutPresetRepository, prefsRepository: widget.dependencies.bookReaderPrefsRepository, currentBookId: widget.bookId, prompts: <畫面端實作>, onCurrentBookPrefsApplied: _handlePrefsChanged)`；`initState` 內 `_presetFlow.load()` 取代 `_loadLayoutPresets()`；`dispose` 內 `_presetFlow.dispose()`（放在 `super.dispose()` 之前；`ReaderScreen` 沒有自己監聽 flow，不需 `removeListener`）。
- [x] **Step 2：** 刪 `_layoutPresets`、`_loadLayoutPresets`、`_handleSaveAsPreset`、`_handleApplyPreset`、`_handleApplyFromBook`、`_handleDeletePreset`、`_applyPrefsToTargets`、`_selectPresetToOverwrite`、`_confirmOverwrite`、`_confirmApplyToOtherBooks`、`_confirmDeletePreset`，以及下列 import（計畫審查 I-1，已 grep 確認只供被刪程式使用）：`layout_preset_actions.dart`、`layout_preset_name_dialog.dart`、`package:intl/intl.dart`（整檔唯一的 `DateFormat` 在被刪的 `_selectPresetToOverwrite`）、`../reader/layout_preset.dart`（`LayoutPreset` 引用全在被刪程式裡）；新增 `../reader/layout_preset_flow.dart` 與 `layout_preset_dialogs.dart` 的 import。**保留** `_handleRequestBookPicker` 與 `_handlePrefsChanged`。
- [x] **Step 3：** 新增一個私有方法 `_showPresetError(Key key, String message)`（`if (!mounted) return;` 後 `ScaffoldMessenger…showSnackBar`），使用的 `context` 必須是 State 的 `context`，不可誤用 `ListenableBuilder` builder 的參數 `context`（會遮蔽）。三個 SnackBar 鍵與文案不變：另存失敗 → `reader_save_as_preset_error_snackbar`／`readerSaveAsPresetFailedMessage`；套用與從其他書複製失敗 → `reader_apply_preset_error_snackbar`／`readerApplyPresetFailedMessage`；刪除失敗 → `reader_delete_preset_error_snackbar`／`readerDeletePresetFailedMessage`。`l10n` 在 `await` 之前取得的原則照舊。
- [x] **Step 4：** `_openLayoutSettings`：刪 `StateSetter? setSheetState` 與 `StatefulBuilder`，改為 `ListenableBuilder(listenable: _presetFlow, builder: …)` 包住 `ReaderSettingsSheet`；`layoutPresets: _presetFlow.presets`；四個預設集回呼改為 `await` 對應的 flow 方法，若回傳 `failed` 則 `_showPresetError`。其餘參數（`prefs`、`onChanged`、`availableFonts`、`bookId`、`isEinkMode`、`onRequestBookPicker`）不動。
- [x] **Step 5：** `git rm app/lib/reader/layout_preset_actions.dart`；`grep -rn "layout_preset_actions" app/lib app/test` 應為 0（含註解；`layout_preset_flow.dart` 開頭註解若提到舊檔，改字）。
- [x] **Step 6：** `reader_screen_test.dart`：
  - 刪「刪除預設集：確認對話框取消時不刪除」案例（約 10497，已由 Task 1 的 flow 測試取代）。
  - **新增面板重畫斷言**（計畫審查 I-2；在「預設集」分頁狀態下判斷）：「另存」案例（約 10133）結尾斷言 `reader_settings_preset_slot_0_row` 存在、`reader_settings_preset_slot_0_empty` 不存在；「刪除」案例（約 10413）結尾斷言 `_row` 消失、`_empty` 出現。這兩條在 `ListenableBuilder` 沒重畫時必定失敗。
  - 其餘預設集案例（約 10133、10166、10221、10257、10311、10355、10413、10449、10529、10578，以及約 341 的 ARB 驗證）全留——它們驗的是從按鈕到對話框到 SnackBar 的整條接線；約 10257 是通知規則（C-1）的守門案例，不可刪。
  - 同步修改註解中的舊名稱（M-1）：約 112 行的 `_loadLayoutPresets()`、約 10307–10308 行的 `_applyPrefsToTargets` 與 `layout_preset_actions_test.dart`，改指 `LayoutPresetFlow`／`layout_preset_flow_test.dart`。
- [x] **Step 7：** 驗證：`flutter analyze`；跑 `reader_screen_test.dart` 預設集區段（約 10090–10600，用 `--plain-name` 縮小）與約 341 案例、`reader_settings_sheet_test.dart`、`layout_preset_flow_test.dart`、`layout_preset_dialogs_test.dart`、`elinkbook_app_wiring_test.dart`、`fake_reader_feature_dependencies_test.dart`；commit。

### Task 4：收尾

- [x] **Step 1（設計定案時已完成）：** `CONTEXT.md`「版面設定預設集」詞條補一句。
- [x] **Step 2：** `epic.md` 開發記錄；`issues.md` Issue 26 狀態；`docs/epics.md` 對應列同步。
- [x] **Step 3：** 驗收：`grep -n "_handleSaveAsPreset\|_handleApplyPreset\|_handleApplyFromBook\|_handleDeletePreset\|_applyPrefsToTargets\|_confirmOverwrite\|_confirmApplyToOtherBooks\|_confirmDeletePreset\|_selectPresetToOverwrite\|_loadLayoutPresets\|_layoutPresets\|setSheetState" app/lib/screens/reader_screen.dart` 應為 0（含註解；有註解提到舊名稱須同步改字）。
- [x] **Step 4：** `git checkout app/analysis_options.yaml`（若被改寫）；`flutter analyze`；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`；完整 `flutter test`（`run_in_background`，只跑一個）。
- [ ] **Step 5：** WAVE 真機抽驗（流式 EPUB 一本，並另備至少兩本流式 EPUB 供「套用到其他書」）：另存為新預設集（未滿 3 組）；存滿 3 組後再另存，覆蓋選單與覆蓋確認；套用預設集到本書，畫面即時反映；套用到其他書籍，跳確認；書籍設定複製；刪除預設集（確認與取消）；取名、覆蓋、套用、刪除各步驟按取消後不產生變動；每次操作後面板的預設集槽位即時更新；對話框開著時按返回離開閱讀器不閃退。
- [ ] **Step 6：** 程式審查（報告存 `reviews/review-code-issue-26.md`，不進版控）；開 PR。

---

## 計畫審查修訂記錄

審查報告 `reviews/review-plan-issue-26.md`（不進版控）：Critical 1、Important 5、Minor 6，結論 Approved with Fixes。本計畫已全數採納：

- **C-1**：Global Constraints「通知規則」、Task 1 通知案例、Review Focus 1。
- **I-1**：Task 2 與 Task 3 Step 2 補 import 清單。
- **I-2**：Task 3 Step 6 新增槽位出現／消失斷言。
- **I-3**：「`mounted` 檢查點對照表」、`applyFromBook` 在 `load` 後檢查 dispose 旗標、Task 1 對應案例。
- **I-4**：「語意釘點」七條與 Task 1 對應案例。
- **I-5**：Task 1 `target.id == null` 案例改為預期 `failed`。
- **M-1**：Task 3 Step 6 註解同步。**M-2**：Task 2 Step 1 測試細節。**M-3**：Task 1 假 repository 來源（`failOn`）。**M-4**：`dispose` 冪等。**M-5**：Task 3 Step 1／3 的 `dispose` 順序與 `context` 說明。**M-6**：Task 4 Step 1 打勾、補本記錄。
