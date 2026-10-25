# Issue 31：單書偏好寫入失敗提示實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** `ReaderScreen._handlePrefsChanged` 寫入單書偏好失敗時，不再變成沒人接的非同步錯誤：寫 Console Log，並在每次開書最多提示使用者一次。畫面行為與寫入時機不變。

**Architecture：** 新增私有方法 `_persistBookPrefs(prefs)`（`try/catch` ＋ `unawaited`）取代 `_handlePrefsChanged` 內直接呼叫 `saveBookPrefs` 的那一行。第一次失敗用 `SnackBar` 提示（旗標 `_prefsSaveFailureNotified`），之後只寫 Console Log。新增一個 l10n key。

**Tech Stack：** Flutter／Dart、`flutter_test`、`flutter gen-l10n`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 31 設計決策」（決策 1～11）。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **只改單書偏好的持久化那一行**（決策 1）：5 個呼叫端不改；`setState`、`_applyScreenOrientation()`、`_applySystemUiMode()` 的順序與行為不變。
- **仍不 `await` 寫入**（決策 2）：畫面即時回饋不等資料庫。
- **不回復畫面**（決策 4）、**不合併連續寫入**（決策 5）。
- **每次開書最多提示一次**（決策 3）：旗標隨 State 生命週期，不跨書、不持久化。
- **`mounted` 檢查**（決策 3）：離開畫面後的失敗不得觸碰 `context`。
- **Console Log 不放例外全文**（決策 3）：只放 `runtimeType`。
- **範圍外**：`saveGlobalPrefs`、`LibraryPreferences`、其他偏好寫入（決策 8）。
- **l10n**：新 key 同時加進 4 個 `.arb`（`app_en`、`app_zh`、`app_zh_CN`、`app_zh_TW`），並用 `flutter gen-l10n` 重新產生 `app_localizations*.dart`（生成檔進版控）。不得在 Widget 內硬編碼中文字串。
- **測試原則**：既有案例全部保留；只新增案例與假 manager 的失敗開關。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，只跑一個）。
- **每個 Task／commit 結束都必須可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**。
- **提交前**：`flutter analyze` 必須 "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`（本機 nvm 沒裝 Node 則無法執行，記錄在 `epic.md`；本張新增使用者可見字串，未執行的風險要寫清楚）。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔；不要對整個既有檔案跑 `dart format`。
- **Commit**：不加 `Co-Authored-By`；結尾加 `Claude-Session: https://claude.ai/code/session_019bmfxQJ1gaKoHGoWH7gJwD`。每個 Task 一個 commit。
- **不要提交** `app/android/gradle.properties`（使用者擱置的未提交變動）。
- **計畫與實作同分支同 PR**，不另開文件分支。

## Review Focus

1. **畫面行為被改動。** `_handlePrefsChanged` 的 `setState` 與其後兩個呼叫必須維持原順序。→ 既有 `reader_screen_test.dart` 偏好相關案例全綠。
2. **失敗時沒有任何提示或重複提示。** 第一次失敗要提示，連續失敗只提示一次。→ 新增案例。
3. **離開畫面後的失敗。** 寫入尚未完成時 State 已 dispose，catch 區塊不得呼叫 `ScaffoldMessenger.of(context)`。→ `mounted` 檢查＋新增案例。
4. **成功路徑被打擾。** 正常寫入不得出現提示。→ 新增案例。
5. **l10n 完整性。** 4 個 `.arb` 都有新 key，生成檔已更新，沒有硬編碼字串。→ `flutter gen-l10n` 無錯誤、`flutter analyze` 乾淨。
6. **Console Log 洩漏。** 例外全文可能含路徑或資料庫細節。→ 只寫 `runtimeType`。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/screens/reader_screen.dart` | 修改 | `_persistBookPrefs`、旗標、`SnackBar` 提示 |
| `app/lib/l10n/app_en.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_zh_TW.arb` | 修改 | 新 key `readerPrefsSaveFailedMessage` |
| `app/lib/l10n/app_localizations*.dart` | 重新產生 | `flutter gen-l10n` |
| `app/test/support/fake_reader_prefs_manager.dart` | 修改 | `saveBookPrefs` 失敗開關 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 新增失敗提示案例 |
| `CONTEXT.md` | 不動 | 無新詞彙 |

---

### Task 0：提交設計文件與計畫

- [x] **Step 1：** 分支 `epic-54/issue-31-prefs-write-failure`（已從含 PR #370 的 `main` 建立）。
- [x] **Step 2：** 提交 `epic.md`、`issues.md`、`docs/epics.md`、本計畫（純文件，一個 commit）。不提交 `app/android/gradle.properties`。

### Task 1：失敗處理與提示

**Files：** `reader_screen.dart`、4 個 `.arb`、生成檔、`fake_reader_prefs_manager.dart`、`reader_screen_test.dart`。

- [x] **Step 1：** 假 manager 加失敗開關。`FakeReaderPrefsManager` 新增欄位（名稱以實作為準，例如 `Object? saveBookPrefsError`）；`saveBookPrefs` 在欄位非 null 時 `throw` 該物件，且**不寫入、不加進 `savedBookPrefsCalls`**。預設 null，既有測試不受影響。
- [x] **Step 2（紅）：** 在 `reader_screen_test.dart` 新增案例，先寫測試、確認失敗。觸發偏好變更的方式：沿用既有測試中「開啟設定面板並改一個值」或 PDF 裁切完成等已能觸發 `_handlePrefsChanged` 的路徑（先 `grep -n "savedBookPrefsCalls"` 找一個現成路徑照做，不另發明）：
  - 寫入失敗：出現 `Key('reader_prefs_save_failed_snackbar')`，且畫面設定（以既有斷言方式確認）維持新值。
  - 連續兩次失敗：`SnackBar` 只出現一次（第二次失敗後仍只有一個）。
  - 寫入成功：沒有該 `SnackBar`。
  - 寫入失敗但 State 已 dispose：不拋例外（以 `tester.takeException()` 為 null 確認）。可讓 fake 的失敗用 `Completer` 延後，先離開畫面再讓它失敗。
  - 因 `l10n` key 尚未存在，此時先讓測試用字面文字以外的方式斷言（只斷言 `Key`），避免與 Step 3 循環依賴。
- [x] **Step 3：** l10n。4 個 `.arb` 加 `readerPrefsSaveFailedMessage`（文字見 `epic.md` 決策 6；`app_zh_TW.arb` 同 `app_zh.arb`；`app_zh_CN.arb` 用簡體；`app_en.arb` 為英文翻譯）；執行 `flutter gen-l10n`，確認 `app_localizations*.dart` 有對應 getter 且沒有其他不相關差異。
- [x] **Step 4（綠）：** 修改 `reader_screen.dart`：
  - 新增欄位 `bool _prefsSaveFailureNotified = false;`（附 doc 註解：每次開書最多提示一次，epic-54 Issue 31）。
  - 新增私有方法：

    ```dart
    /// 寫入單書偏好；失敗時記 Console Log，並在每次開書第一次失敗時提示使用者
    /// （epic-54 Issue 31）。不 await：畫面即時回饋不等資料庫，畫面也不回復。
    Future<void> _persistBookPrefs(BookReaderPrefs prefs) async {
      try {
        await widget.dependencies.prefsManager.saveBookPrefs(widget.bookId, prefs);
      } catch (e) {
        ReaderConsoleLog.add('[ReaderScreen] 閱讀設定儲存失敗：${e.runtimeType}');
        if (_prefsSaveFailureNotified || !mounted) return;
        _prefsSaveFailureNotified = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('reader_prefs_save_failed_snackbar'),
            content: Text(AppLocalizations.of(context)!.readerPrefsSaveFailedMessage),
          ),
        );
      }
    }
    ```

  - `_handlePrefsChanged` 內 `widget.dependencies.prefsManager.saveBookPrefs(widget.bookId, prefs);` 改為 `unawaited(_persistBookPrefs(prefs));`，其餘行不動；更新該方法 doc 註解，補一句「寫入失敗的處理見 [_persistBookPrefs]」，不要刪除既有的設計說明。
- [x] **Step 5：** `flutter analyze`；跑 `test/screens/reader_screen_test.dart --plain-name` 對應新案例名稱關鍵字、再跑整份 `reader_screen_test.dart`（偏好變更路徑多，整份跑一次最安全）；commit。

### Task 2：收尾

- [ ] **Step 1：** `epic.md` 開發記錄；`issues.md` Issue 31 狀態；`docs/epics.md` 同步。
- [ ] **Step 2：** 驗收：`grep -n "saveBookPrefs" app/lib/screens/reader_screen.dart` 只剩 `_persistBookPrefs` 內一處；`git diff main --stat -- app/lib` 只有 `reader_screen.dart`、4 個 `.arb` 與 `app_localizations*.dart`。
- [ ] **Step 3：** `flutter analyze`；兩個 `check_*.js`（沒有 Node 則記錄未執行）；完整 `flutter test`（`run_in_background`，只跑一個）。
- [ ] **Step 4：** 程式審查（報告存 `reviews/review-code-issue-31.md`，不進版控）。
- [ ] **Step 5：** WAVE 真機抽驗（風險低，一輪即可）：EPUB 與 PDF 各開一本，拖動字級、行距等滑桿並調整幾個設定，確認畫面即時反應、**沒有**出現儲存失敗提示；離開後重新開書，設定仍保留。
- [ ] **Step 6：** 開 PR；PR 開出後把 Issue 31 的狀態同步（Issue 28 已在 Task 0 同步）。
