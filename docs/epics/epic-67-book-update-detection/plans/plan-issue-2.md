# Issue 2：本機匯入入口與彙整清單 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 本機「選擇檔案／選擇資料夾」匯入完成後，若結果含更新候選（`ImportResult.updateCandidates`），彈出一份彙整清單讓使用者逐本選「取代／並存／跳過」（含「全部取代」「全部跳過」），並在任何離開路徑上丟棄暫存檔；取代成功後 evict 該書封面圖片快取。

**Architecture:** 不改服務端（Issue 1 已完成）。新增三個單位：①純 Dart 的 `applyBookUpdateChoices`（依使用者決定呼叫 `replaceBook`／`importCandidateAsNewBook`／`discardUpdateCandidate`，可脫離畫面測試）；②`BookUpdateSummaryDialog` 彙整清單元件；③`handleImportUpdateCandidates`（放在既有 `book_import_picker_helper.dart`，串起「顯示清單 → 套用 → 結果 SnackBar」並保證候選一定被丟棄）。`SourcesHomeScreen` 在既有「匯入結果 SnackBar」之後呼叫它，兩者分開呈現。

**Tech Stack:** Flutter／Dart、`flutter_test` widget test、ARB 在地化（`flutter gen-l10n`）。

**Spec:** `docs/epics/epic-67-book-update-detection/spec.md`（「各入口的互動」「取代的語意」「在地化」）；工單見同目錄 `issues.md` Issue 2；Issue 1 介面見 `plans/plan-issue-1.md` 與 `app/lib/library/book_update_models.dart`、`book_import_service.dart`；ADR 0040。

**分支建議：** `epic-67/issue-2-local-import-summary`（從最新 `main` 切出）。

## 已查證事實（2026-11-04 讀程式所得）

| # | 事實 | 對設計的影響 |
|---|---|---|
| F1 | 本機匯入入口只有 `SourcesHomeScreen._handlePickFiles`／`_handlePickFolder`（`lib/screens/sources_home_screen.dart:41-62`），都是 `pickAndImport*` → `showImportResultSnackBar`。`LibraryScreen` 沒有匯入入口（epic-36 已搬走） | 接線只動 `SourcesHomeScreen` 與 `book_import_picker_helper.dart` |
| F2 | 書架為 `IndexedStack` 常駐，切回書架時靠 `refreshSignal` 重載（`library_screen.dart:156-160`） | 取代後書架清單由既有機制重載，本 Issue 不新增重載邏輯；只需處理圖片快取（F4） |
| F3 | `ImportResult` 已有 `updateCandidates`（`stagedPath` 皆已填入）；`BookImportService` 已有 `replaceBook`／`importCandidateAsNewBook`／`discardUpdateCandidate` | 本 Issue 只呼叫，不改服務 |
| F4 | `BookCover` 以 `Image.file(File(coverPath))` 顯示，取代後封面路徑不變（`covers/<id>.png`），Flutter 圖片快取可能仍顯示舊封面（Issue 1 F8） | 取代成功後須 `PaintingBinding.instance.imageCache.evict(FileImage(File(coverPath)))`，由 `applyBookUpdateChoices` 負責 |
| F5 | `replaceBook(..., candidate:)` 成功時自行丟棄候選暫存檔；**失敗時暫存檔保留**，且 `importCandidateAsNewBook` 無論成敗都自行丟棄 | 取代失敗後本 Issue 沒有「重試」，須由 `applyBookUpdateChoices` 在失敗分支補呼叫 `discardUpdateCandidate` |
| F6 | 資料夾匯入時 `ImportResult` 不帶資料夾分類名，`importCandidateAsNewBook(folderName:)` 無從得知 | 「並存」的新書一律落在「未分類」（已知限制，記入 `epic.md`） |
| F7 | 雲端／Calibre／WiFi 三處也呼叫 `importFiles` 但會忽略 `updateCandidates`（`cloud_download_job.dart:79`、`remote_download_job.dart:88`、`wifi_transfer_service.dart:135`） | **Issue 1 合併後、Issue 4 完成前**，這三條路徑遇到更新版時該檔既不匯入也不會被處理，暫存檔殘留至 App 啟動清掃（Issue 4 範圍）。本 Issue 不處理，列入風險並請人類確認（見最後一節） |
| F8 | 測試用 `FakeBookImportService`（`test/support/fake_book_import_service.dart`）已有 `replaceResult`／`replaceCalls`／`importCandidateResult`／`importCandidateCalls`／`discardedCandidates`，但 `replaceResult` 只有單一值，且無法回傳更新候選 | Task 1 擴充：`importFiles`／`importFolder` 可回傳預設 `ImportResult`；`replaceBook` 可依 `bookId` 指定結果 |
| F9 | ARB 四份：`app_zh_TW.arb`（template）、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`；`app_localizations*.dart` 已進版控，需 `flutter gen-l10n` 重產；`test/l10n/arb_consistency_test.dart` 檢查四份鍵一致 | Task 2 新增字串後須重產並跑該測試 |

## 已確認決策（本計畫自行定案，待人類審閱）

- **D1：選項模型。** 每筆候選一個決定：`ReplaceChoice(bookId)`（取代指定候選書）／`CoexistChoice`（並存，亦即候選清單中的「當成新書」）／`SkipChoice`。單一候選與多候選用同一份 UI：選項列表＝每本候選書一個「取代《書名》」選項（識別碼命中者排最前，即 `candidateBooks` 順序）＋「並存」＋「跳過」。預設選第一個「取代」（spec 故事 9）。
- **D2：「全部取代」「全部跳過」是選取捷徑，不直接執行。** 它們只改變每列的選取狀態，使用者仍須按「套用」才執行；取代是不可復原操作，且確認文字（偏移提示）必須在執行前可見。「全部取代」對每列選第一個候選書。
- **D3：關閉＝全部跳過。** 對話框不可點外部關閉；「取消」按鈕與系統返回鍵都等同「全部跳過」（丟棄所有暫存檔後關閉）。處理中（套用中）忽略返回與重複點擊。
- **D4：偏移提示常駐。** 只要有任一列選了「取代」，清單底部就顯示「既有註記位置可能因內容改版而偏移」；沒有任何列選取代時隱藏。
- **D5：舊檔讀不到的提示。** 候選書 id 在 `unreadableCandidateBookIds` 內且該列選了取代該書時，該列顯示「舊檔已無法存取，取代後會一併修復檔案連結」（spec 故事 32）。
- **D6：取代失敗不中斷整批。** 逐筆循序處理（大檔避免並行 I/O）；單筆失敗計入失敗數、補丟棄暫存檔後繼續下一筆；全部完成後以一則 SnackBar 彙報（成功取代／並存本數，以及失敗本數）。全為跳過時不顯示 SnackBar。

## Global Constraints

- 所有註解、文件、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文。
- 畫面字串一律走 `AppLocalizations`，四份 ARB（`app_zh_TW`／`app_zh`／`app_zh_CN`／`app_en`）同步；不得硬編碼中文。
- Flutter 3.41.9：不得使用此版本沒有的 API。
- 不改服務端（`book_import_service*.dart`、`book_update_models.dart`）；若發現必須改，停下回報而非自行修改。
- 「N 本已存在，已跳過」的既有 SnackBar（`showImportResultSnackBar`）行為與文字完全不變，更新版清單與它分開呈現（先 SnackBar、後清單）。
- 候選暫存檔的所有離開路徑（跳過、取消、返回、套用失敗、畫面已卸載）都必須呼叫 `discardUpdateCandidate`。
- 提交前：`flutter analyze` 必須 "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`（皆在 `app/` 下）。
- 測試範圍：每個 Task 只跑觸及的測試檔；完整 `flutter test --no-pub` 只在最後一個 Task 執行一次。所有指令工作目錄為 `app/`，測試與 analyze 後以 `git checkout pubspec.lock windows/flutter` 還原工具產生的雜訊。

## Review Focus

1. **畫面已卸載時不留暫存**（Task 3）：選檔／選資料夾期間使用者離開 `SourcesHomeScreen`，`context.mounted == false` 時不得彈清單，須直接丟棄所有候選。
2. **返回鍵與重複點擊**（Task 2）：系統返回＝全部跳過並丟棄；套用中再按「套用」或返回不可重入、不可重複呼叫 `replaceBook`。
3. **單筆失敗不拖累其他列，且失敗列暫存檔被丟棄**（Task 1）：`replaceBook` 回傳失敗或拋例外、`importCandidateAsNewBook` 回 null，都要繼續處理下一列。
4. **大量候選與長檔名**（Task 2）：50 列清單可捲動、長檔名／長書名不溢位（窄螢幕、E-Ink 修飾子）。
5. **封面快取**（Task 1）：取代成功才 evict（新舊封面路徑皆處理），失敗與跳過不 evict。

---

### Task 1：套用決定的純邏輯 `applyBookUpdateChoices` 與假服務擴充

**Files:**
- Create: `app/lib/screens/support/book_update_resolver.dart`
- Create: `app/test/screens/support/book_update_resolver_test.dart`
- Modify: `app/test/support/fake_book_import_service.dart`

**Interfaces（Produces）：**

```dart
/// 使用者對一筆更新候選的決定。
sealed class BookUpdateChoice { const BookUpdateChoice(); }
final class ReplaceChoice extends BookUpdateChoice { final String bookId; const ReplaceChoice(this.bookId); }
final class CoexistChoice extends BookUpdateChoice { const CoexistChoice(); }
final class SkipChoice extends BookUpdateChoice { const SkipChoice(); }

class BookUpdateDecision {
  final BookUpdateCandidate candidate;
  final BookUpdateChoice choice;
  const BookUpdateDecision(this.candidate, this.choice);
}

/// 套用結果：只計數，使用者可見文字由呼叫端在地化。
class BookUpdateApplyResult {
  final int replaced, coexisted, skipped, failed;
  const BookUpdateApplyResult({this.replaced = 0, this.coexisted = 0, this.skipped = 0, this.failed = 0});
}

/// 預設的封面快取失效：PaintingBinding.instance.imageCache.evict(FileImage(File(path)))。
void evictCoverImageCache(String coverPath);

/// 逐筆循序套用決定。永不拋例外。
Future<BookUpdateApplyResult> applyBookUpdateChoices(
  BookImportService service,
  List<BookUpdateDecision> decisions, {
  void Function(String coverPath) onCoverChanged = evictCoverImageCache,
});
```

**語意：** `SkipChoice` → `discardUpdateCandidate`；`ReplaceChoice(bookId)` → `replaceBook(bookId, candidate.sourceUri, displayName: candidate.displayName, candidate: candidate)`，成功則對「舊書 `coverPath`（取自 `candidate.candidateBooks` 中同 id 者）」與「`updatedBook.coverPath`」（非 null 者、去重）各呼叫一次 `onCoverChanged`；失敗或拋例外 → 補 `discardUpdateCandidate`、`failed++`；`CoexistChoice` → `importCandidateAsNewBook(candidate)`，回 null 或拋例外 → `failed++`（服務已自行丟棄暫存檔，不再重複丟棄）。

- [x] **Step 1：擴充 `FakeBookImportService`**：新增 `ImportResult importFilesResult`／`importFolderResult`（預設空結果，兩個方法在無 `pendingCompleter` 時回傳它）、`Map<String, BookReplaceResult> replaceResultsByBookId`（有對應 key 時優先於 `replaceResult`）、`Object? replaceThrows`。既有測試行為不變。
- [x] **Step 2：寫失敗測試**（`book_update_resolver_test.dart`，用上述假服務與 `onCoverChanged` 記錄器）：
  - `跳過`：`SkipChoice` → `discardedCandidates` 含該候選、`replaceCalls`／`importCandidateCalls` 皆空、`skipped == 1`、`onCoverChanged` 未被呼叫。
  - `取代成功`：`ReplaceChoice('b1')` 且 `replaceResultsByBookId['b1'] = BookReplaceSuccess(updatedBook)` → `replaceCalls == [('b1', sourceUri)]`、`replaced == 1`；舊書 `coverPath` 與新書 `coverPath` 皆傳給 `onCoverChanged`（兩者相同時只呼叫一次）；成功分支不補丟棄（服務已自行丟棄，`discardedCandidates` 為空）。
  - `取代失敗`：回傳 `BookReplaceFailure(newFileParseFailed)` → `failed == 1`、`discardedCandidates` 含該候選、`onCoverChanged` 未被呼叫；`replaceThrows` 拋例外時同樣計失敗並丟棄。
  - `並存`：`importCandidateResult` 為書 → `importCandidateCalls` 含該候選、`coexisted == 1`；為 null → `failed == 1`。
  - `單筆失敗不中斷`：三筆 `[取代失敗, 跳過, 並存成功]` → 結果 `failed 1／skipped 1／coexisted 1`，三筆都被處理。
  - `多候選取代指定書`：候選書 `[b1, b2]`、`ReplaceChoice('b2')` → `replaceCalls` 的 bookId 為 `b2`，封面失效取自 `b2`。
  - `evictCoverImageCache`：先用 `PaintingBinding.instance.imageCache.putIfAbsent(FileImage(File(p)), …)` 放入一個項目，呼叫後 `imageCache.containsKey(FileImage(File(p))) == false`。
- [x] **Step 3：確認失敗** `flutter test --no-pub test/screens/support/book_update_resolver_test.dart`
- [x] **Step 4：實作** 上述型別與函式；實作時只依賴 `BookImportService` 公開介面。
- [x] **Step 5：確認通過**，並重跑 `test/screens/support/book_import_picker_helper_test.dart` 與 `test/screens/sources_home_screen_test.dart` 確認假服務擴充不回歸。
- [x] **Step 6：`flutter analyze`**；提交 `feat(library): 更新版決定的套用邏輯與封面快取失效（epic-67 Issue 2 Task 1）`。

---

### Task 2：彙整清單元件 `BookUpdateSummaryDialog` 與在地化字串

**Files:**
- Create: `app/lib/screens/widgets/book_update_summary_dialog.dart`
- Create: `app/test/screens/widgets/book_update_summary_dialog_test.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`，並以 `flutter gen-l10n` 重產 `app_localizations*.dart`

**Interfaces：**
- Consumes：Task 1 的 `BookUpdateChoice`／`BookUpdateDecision`／`BookUpdateApplyResult`／`applyBookUpdateChoices`。
- Produces：

```dart
/// 顯示彙整清單；回傳套用結果。取消、返回、全部跳過都會先丟棄暫存檔再回傳（skipped 計數）。
Future<BookUpdateApplyResult> showBookUpdateSummaryDialog(
  BuildContext context, {
  required BookImportService importService,
  required List<BookUpdateCandidate> candidates,
  bool isEinkMode = false,
});
```

`showDialog` 必須傳 `barrierDismissible: false`，並以 `animationStyle: isEinkMode ? AnimationStyle.noAnimation : null` 抑制 E-Ink 殘影（沿用 `dictionary_online_consent_dialog.dart:20` 既有做法；審查 M-2、M-3）。`showDialog` 回傳 null（理論上不會發生）時，以全 `SkipChoice` 呼叫 `applyBookUpdateChoices` 作為保底，確保暫存被丟棄。對話框 `content` 的列表須以 `SizedBox(width: double.maxFinite)` ＋ `ConstrainedBox(maxHeight: 螢幕高度 × 0.6)` 包裹 `ListView`，避免 `AlertDialog.content` 的無界高度例外（審查 M-1）。

**新增 ARB 鍵**（四份同步；文字以 zh_TW 為準，其餘語系同義翻譯；含 `@key` 描述與 placeholders）：

| 鍵 | zh_TW 文字 | 參數 |
|---|---|---|
| `bookUpdateSummaryTitle` | 發現書籍更新版 | — |
| `bookUpdateSummaryIntro` | 以下檔案看起來是書庫中已有書籍的新版本，請選擇處理方式。 | — |
| `bookUpdateConfidenceHigh` | 高信心：書籍識別碼相同 | — |
| `bookUpdateConfidenceSuspected` | 疑似：書名與作者相同 | — |
| `bookUpdateOptionReplace` | 取代「{title}」 | `title` |
| `bookUpdateOptionCoexist` | 並存（當成新書匯入） | — |
| `bookUpdateOptionSkip` | 跳過 | — |
| `bookUpdateReplaceAll` | 全部取代 | — |
| `bookUpdateSkipAll` | 全部跳過 | — |
| `bookUpdateApply` | 套用 | — |
| `bookUpdateReplaceNotice` | 取代後，既有的書籤、劃線與備註位置可能因內容改版而偏移。 | — |
| `bookUpdateOldFileUnreadable` | 「{title}」的舊檔已無法存取，取代後會一併修復檔案連結。 | `title` |
| `bookUpdateApplying` | 處理中… | — |
| `bookUpdateResultBothMessage` | `{replaced, plural, =1{已更新 1 本} other{已更新 {replaced} 本}}，{coexisted, plural, =1{已並存 1 本} other{已並存 {coexisted} 本}}` | `replaced`、`coexisted`（int） |
| `bookUpdateResultReplacedOnlyMessage` | `{replaced, plural, =1{已更新 1 本} other{已更新 {replaced} 本}}` | `replaced` |
| `bookUpdateResultCoexistedOnlyMessage` | `{coexisted, plural, =1{已並存 1 本} other{已並存 {coexisted} 本}}` | `coexisted` |
| `bookUpdateFailedMessage` | `{count, plural, =1{1 本更新失敗，書籍沒有任何變動} other{{count} 本更新失敗，書籍沒有任何變動}}` | `count` |
| `bookUpdateResultWithFailedMessage` | `{successText}；{failedText}`（各語系用自己的分隔標點，不在 Dart 內硬編碼） | `successText`、`failedText`（String） |

（拆成三個成功訊息鍵是沿用既有 `libraryImportResultBothMessage`／`…ImportedOnly…`／`…SkippedOnly…` 的慣例，避免巢狀 ICU plural 在 `gen-l10n` 的剖析風險；審查 I-2。）

**SnackBar 組合規則（審查 I-3）：** 依 `replaced > 0`／`coexisted > 0` 選三個成功鍵之一得 `successText`；`failed > 0` 得 `failedText = bookUpdateFailedMessage(failed)`。兩者皆有 → 單一 SnackBar 顯示 `bookUpdateResultWithFailedMessage(successText, failedText)`；只有其一 → 直接顯示該字串；兩者皆無（全為跳過）→ 不顯示。永遠只彈一則 SnackBar。

取消按鈕沿用既有 `cancel` 鍵。

**畫面規格：**
- 標題＋說明＋可捲動的列表（`ListView`）；每筆候選一個區塊：顯示名稱（`displayName ?? sourceUri 的最後一段`，單行可截斷）、信心等級文字、選項（單選 `RadioListTile`：每本候選書一個「取代」＋「並存」＋「跳過」，順序同 `candidateBooks`）。
- 舊檔讀不到的提示（D5）、常駐偏移提示（D4）、底部「全部取代」「全部跳過」（D2）、「取消」「套用」按鈕。
- 套用中顯示 `bookUpdateApplying` 與進度指示，所有按鈕與返回失效（D3）。
- Keys：`book_update_row_<i>`、`book_update_confidence_<i>`、`book_update_option_replace_<i>_<bookId>`、`book_update_option_coexist_<i>`、`book_update_option_skip_<i>`、`book_update_unreadable_<i>`、`book_update_replace_notice`、`book_update_replace_all`、`book_update_skip_all`、`book_update_apply`、`book_update_cancel`、`book_update_applying`。
- 不可點外部關閉；以 `PopScope(canPop: false)` 攔截系統返回，視同取消（D3）。

- [x] **Step 1：新增 ARB 字串**至四份檔案並執行 `flutter gen-l10n`；跑 `flutter test --no-pub test/l10n/arb_consistency_test.dart test/l10n/app_localizations_generated_test.dart` 確認一致。
- [x] **Step 2：寫失敗測試**（`book_update_summary_dialog_test.dart`，以 `pumpLocalizedWidget` 包裝並點按鈕開啟；使用 `FakeBookImportService` 與 `BookUpdateCandidate` 夾具）：
  - `顯示每本的選項與信心`：兩筆候選（高信心／疑似）→ 各列顯示對應信心文字；單一候選列有「取代」「並存」「跳過」三個選項，預設選取「取代」。
  - `多候選`：一筆候選有書 `[b1, b2]` → 該列有 `book_update_option_replace_0_b1`、`_b2`、並存、跳過；`b1` 預設被選；改選 `b2` 後套用 → `replaceCalls` 的 bookId 為 `b2`。
  - `全部跳過`：按 `book_update_skip_all` 後所有列顯示「跳過」被選；按套用 → 所有候選被丟棄、`replaceCalls` 為空。
  - `全部取代`：先全部跳過再按 `book_update_replace_all` → 每列回到第一個候選書的取代；套用後 `replaceCalls` 長度等於候選數。
  - `偏移提示`：預設有取代選項 → `book_update_replace_notice` 可見；全部跳過後消失；再選回取代後出現。
  - `舊檔無法存取提示`：候選 `unreadableCandidateBookIds = {b1}` 且該列選取代 b1 → `book_update_unreadable_0` 可見；改選並存後隱藏。
  - `取消與返回都丟棄暫存`：按 `book_update_cancel` → 所有候選被丟棄且對話框關閉；另一案例以系統返回（`tester.binding.handlePopRoute()`）得相同結果；兩者回傳的 `skipped` 等於候選數。
  - `套用中不可重入`：以 `pendingCompleter`／可控 `replaceBook` 延遲完成，套用中連按兩次 `book_update_apply` 與返回 → `replaceCalls` 只有一次、對話框仍開啟、`book_update_applying` 可見；完成後對話框關閉。
  - `點外部遮罩不關閉（審查 M-2）`：點擊對話框外的遮罩位置 → 對話框仍在、`discardedCandidates` 仍為空。
  - `大量候選`：50 筆候選、長檔名（80 字）→ 不拋 overflow 例外，捲到最後一列可點到其選項；窄螢幕（寬 320）與 E-Ink 修飾子（`isEinkMode: true`）各 pump 一次無例外。
- [x] **Step 3：確認失敗 → Step 4：實作** `showBookUpdateSummaryDialog` 與 `_BookUpdateSummaryDialog`（狀態：每列目前選項、`_applying`）；套用時組出 `List<BookUpdateDecision>` 交給 `applyBookUpdateChoices`，完成後 `Navigator.pop(result)`；取消／返回則以全 `SkipChoice` 呼叫同一函式後 pop。
- [x] **Step 5：確認通過**；`node tool/check_l10n_hardcoded_strings.js`。
- [x] **Step 6：`flutter analyze`**；提交 `feat(library): 更新版彙整清單與在地化字串（epic-67 Issue 2 Task 2）`。

---

### Task 3：接線——匯入流程串起清單、結果提示與卸載防護

**Files:**
- Modify: `app/lib/screens/support/book_import_picker_helper.dart`
- Modify: `app/lib/screens/sources_home_screen.dart`（`_handlePickFiles`、`_handlePickFolder`）
- Modify: `app/test/screens/support/book_import_picker_helper_test.dart`
- Modify: `app/test/screens/sources_home_screen_test.dart`

**Interfaces：**
- Consumes：Task 2 的 `showBookUpdateSummaryDialog`、Task 1 的 `BookUpdateApplyResult`。
- Produces（於 `book_import_picker_helper.dart`）：

```dart
/// 匯入完成後處理更新候選。無候選時什麼都不做；畫面已卸載時直接丟棄全部候選；
/// 否則顯示彙整清單，完成後以 SnackBar 彙報（成功本數、失敗本數，全為跳過則不顯示）。
Future<void> handleImportUpdateCandidates(
  BuildContext context,
  BookImportService importService,
  ImportResult result, {
  bool isEinkMode = false,
});
```

**呼叫順序（兩個 handler 皆然）：** `showImportResultSnackBar`（維持原樣）→ `handleImportUpdateCandidates`。`result.failure != null` 時（整次失敗）不處理候選（此時候選必為空）。

**handler 結構（審查 I-1，現行 `if (!context.mounted) return;` 會讓卸載防護失效，必須改）：** `result == null` 才提前 return；`showImportResultSnackBar` 包在 `if (context.mounted)` 內；其後**無條件** `await handleImportUpdateCandidates(context, service, result)`，由它內部判斷 `context.mounted`（未掛載 → 丟棄全部候選後返回）。`_handlePickFolder` 同構。`showBookUpdateSummaryDialog` 的 `isEinkMode` 取自 `appearance.isEinkMode`（`SourcesHomeScreen` 已有該欄位，`handleImportUpdateCandidates` 增加選填參數 `bool isEinkMode = false` 往下傳）。

- [x] **Step 1：寫失敗測試**
  - `book_import_picker_helper_test.dart` 新增 `handleImportUpdateCandidates` 群組（`FakeBookImportService`）：
    - `無候選`：不彈出任何對話框、`discardedCandidates` 為空。
    - `有候選且已掛載`：彈出 `BookUpdateSummaryDialog`（find `book_update_apply`）；按套用（預設取代）→ 出現「已更新 1 本」SnackBar（`bookUpdateResultReplacedOnlyMessage`）。
    - `並存`：改選並存後套用 → 「已並存 1 本」；兩筆分別取代與並存 → `bookUpdateResultBothMessage` 輸出。
    - `部分失敗（審查 I-3）`：2 筆取代成功、1 筆失敗 → 畫面上**只有一則** SnackBar，文字等於 `bookUpdateResultWithFailedMessage(「已更新 2 本」, 「1 本更新失敗，書籍沒有任何變動」)`；全部失敗 → 只顯示失敗文字。
    - `isEinkMode`：`isEinkMode: true` 時對話框無過場動畫（開啟後一次 `pump()` 即可找到 `book_update_apply`）。
    - `全部跳過`：不顯示任何 SnackBar。
    - `卸載防護`（Review Focus 1）：傳入一個 `context.mounted == false` 的 context（先 pump 掉 widget 再呼叫）→ 不彈出對話框，所有候選被丟棄。
  - `sources_home_screen_test.dart`：
    - `選檔匯入含更新候選`：`importFilesResult` 帶 1 筆候選 → 選檔後出現清單；按套用後 `replaceCalls` 有一筆。
    - `純重複只顯示既有提示`：`ImportResult(skippedDuplicateCount: 2)` 無候選 → 只出現「2 本已存在，已跳過」SnackBar，沒有清單。
    - `提示與清單分開`：結果同時有 `skippedDuplicateCount: 1` 與候選 → 先見既有 SnackBar 文字，清單照常彈出，且清單內不含「已存在，已跳過」字樣。
    - `資料夾匯入`同樣路徑一案例。
- [x] **Step 2：確認失敗 → Step 3：實作** `handleImportUpdateCandidates`；兩個 handler 在既有 `showImportResultSnackBar` 之後 `await handleImportUpdateCandidates(...)`（注意兩次呼叫之間再檢查 `context.mounted`——但卸載時仍須丟棄候選，故檢查邏輯放在 `handleImportUpdateCandidates` 內部，handler 不得在其前面提前 `return` 而漏丟棄）。
- [x] **Step 4：確認通過**，並重跑 Task 1、2 的測試檔。
- [x] **Step 5：`flutter analyze`**；提交 `feat(library): 本機匯入接上更新版彙整清單（epic-67 Issue 2 Task 3）`。

---

### Task 4：完整驗證與文件同步

**Files:**
- Modify: `docs/epics/epic-67-book-update-detection/epic.md`（開發記錄）、`issues.md`（Issue 2 狀態與計畫連結）

- [x] **Step 1：** `flutter analyze` 乾淨；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`。
- [x] **Step 2：** 完整 `flutter test --no-pub` 全綠（本計畫唯一一次全套）；之後 `git checkout pubspec.lock windows/flutter`。
- [x] **Step 3：真機／模擬器手動驗證**（`app/` 下 `flutter run`，由人類或執行者實測並記錄結果）：
  1. 書庫預置一本 EPUB，再「選擇檔案」匯入同識別碼、內容不同的新版 → 彈出清單，選取代 → 書架上書名、封面立即更新（驗證 F4 的圖片快取），閱讀進度與書籤仍在。
  2. 同一批含一本全新書、一本整檔重複 → 新書匯入、重複走既有 SnackBar、更新版走清單。
  3. 清單按返回鍵／取消 → 書庫不變，`<documents>/update_staging/` 內無殘留。
- [x] **Step 4：文件同步：** `epic.md` 新增「Issue 2 計畫與實作」段，記錄 D1～D6、F6（並存落在未分類）、F7（雲端／Calibre／WiFi 暫存殘留風險）、手動驗證結果；`issues.md` Issue 2 補計畫連結與狀態。`docs/epics.md` 備註與 PR 欄**合併後**才改。
- [x] **Step 5：提交** `docs(epic-67): Issue 2 實作記錄`。

---

## 不在本 Issue 範圍（避免誤做）

- 手動入口「用新檔案更新此書」與強制重新連結（Issue 3）。
- 下載佇列「待確認更新」、專屬暫存目錄、啟動時清掃（Issue 4）。
- WiFi 傳輸的更新版處理。
- 任何服務端（`BookImportService`）改動；註記／閱讀位置降級（Issue 5，已合併）。
- 「並存」書籍沿用資料夾分類（F6，已知限制）。

## 需要人類確認（審閱本計畫時請回覆）

1. **F7 風險：** Issue 1 已合併，雲端／Calibre／WiFi 在遇到更新版時該檔會被靜默略過且暫存檔殘留，直到 Issue 4 完成。是否要在 Issue 4 之前先做一個最小緩解（例如這三處在收到 `updateCandidates` 時一律 `discardUpdateCandidate` 並當成新書匯入，維持 Issue 1 之前的行為）？此事不在 Issue 2 範圍，需另開工單或併入 Issue 4。
2. **D2：** 「全部取代」「全部跳過」只改選取、須再按「套用」，是否接受？（替代方案：按下即執行，但取代時沒有偏移提示的確認機會。）
3. **D1：** 多候選的呈現採「每本候選書一個取代選項＋並存＋跳過」的單選列，是否符合預期？
