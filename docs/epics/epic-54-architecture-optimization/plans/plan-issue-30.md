# Issue 30：`BookmarkController.load()` 世代保護實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 修掉 `BookmarkController.load()` 的亂序覆寫：先發出的舊 `load` 比後發出的新 `load` 晚完成時，不得把清單蓋回過期值。

**Architecture：** 在 `BookmarkController` 內加一個遞增序號 `_loadSeq`。每次 `load()` 取得自己的序號；`await` 回來後，序號不是最新就丟掉結果。對外介面（`load`／`at`／`toggle`／`bookmarks`）不變，呼叫端不改。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 30 設計決策」（決策 1～8）。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **只改 `BookmarkController.load()`**（決策 1）：不改 `toggle`、`at`、`bookmarks`、`isSameBookmarkPosition`，不改呼叫端（`ReaderScreen`、`NotesBottomSheet`）。
- **不排隊、不加鎖**（決策 2）：用序號丟棄過期結果，不序列化 `load`。
- **最新那次失敗時，舊結果也不套用**（決策 3）：失敗只 `debugPrint`，清單維持現狀；舊的那次失敗同樣只 `debugPrint`，不影響較新的結果。
- **不動 `AnnotationController.reload()`**（Issue 32）。
- **測試原則**：既有 `bookmark_controller_test.dart` 案例全部保留；只新增案例與一個測試用假 repository。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，只跑一個）。
- **每個 Task／commit 結束都必須可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**。
- **提交前**：`flutter analyze` 必須 "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`（本機 nvm 若沒裝 Node 則無法執行，記錄在 `epic.md`）。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔。
- **Commit**：不加 `Co-Authored-By`；結尾加 `Claude-Session: https://claude.ai/code/session_019bmfxQJ1gaKoHGoWH7gJwD`。每個 Task 一個 commit。
- **不要提交** `app/android/gradle.properties`（使用者擱置的未提交變動）。
- **計畫與實作同分支同 PR**，不另開文件分支。

## Review Focus

1. **序號丟掉了不該丟的結果。** 單獨一次 `load()`、依序完成的兩次 `load()` 都必須照常更新清單。→ 既有案例全綠，另有「舊的先完成、新的後完成」案例。
2. **失敗路徑吞掉較新的結果。** 舊的那次失敗不能把已套用的新結果洗掉；新的那次失敗不能讓舊結果被套用。→ 兩個失敗案例。
3. **`toggle` 結尾的 `load()` 被取代後，呼叫端看到過期清單。** 這是決策 4 接受的副作用：呼叫端每次 `load` 完成都 `setState`，最終畫面是最新清單。→ 不新增程式，確認呼叫端不依賴 `load()` 是否改了清單（`ReaderScreen` 約 500、1206 行；`NotesBottomSheet._loadBookmarks` 約 147 行）。
4. **序號溢位或與實例共享。** 序號是實例欄位（不是靜態），每本書各自一個 `BookmarkController`，互不影響；Dart `int` 不會在實務上溢位。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/bookmark_controller.dart` | 修改 | `load()` 加 `_loadSeq`，過期結果丟棄 |
| `app/test/reader/bookmark_controller_test.dart` | 修改 | 新增可手動控制完成順序的假 repository 與亂序案例 |
| `CONTEXT.md` | 不動 | 無新詞彙 |

---

### Task 0：提交設計文件與計畫

- [x] **Step 1：** 分支 `epic-54/issue-30-bookmark-load-generation`（已從含 PR #367 的 `main` 建立）。
- [x] **Step 2：** 提交 `epic.md`、`issues.md`、`docs/epics.md`、本計畫（純文件，一個 commit）。不提交 `app/android/gradle.properties`。

### Task 1：世代保護與亂序測試

**Files：** `bookmark_controller.dart`、`test/reader/bookmark_controller_test.dart`。

測試用假 repository 草案（以實際編譯為準）：

```dart
/// 可手動控制 listByBook 完成順序：呼叫當下先取資料快照，再等閘門放行，
/// 模擬「較舊的查詢比較新的查詢晚回來」。
class _GatedBookmarksRepository implements BookmarksRepository {
  final FakeBookmarksRepository inner = FakeBookmarksRepository();
  final List<Completer<void>> _gates = [];   // 依呼叫順序排隊的閘門
  final List<bool> _failures = [];           // 對應閘門放行後是否丟例外

  /// 下一次 listByBook 要等閘門；回傳該閘門。
  Completer<void> gateNext({bool fail = false});

  // listByBook：有排到閘門就先取快照、await 閘門、再依 fail 丟例外或回傳快照；
  // 沒排到閘門就直接回傳（等同 FakeBookmarksRepository）。
}
```

- [ ] **Step 1（紅）：** 在 `bookmark_controller_test.dart` 新增 `group('load 世代保護')`，先寫測試、確認失敗：
  - 先發的舊 `load`（快照 `[A]`）、後發的新 `load`（快照 `[A, B]`）；新的先完成，舊的後完成 → `bookmarks` 為 `[A, B]`（目前會被蓋回 `[A]`，紅燈）。
  - 舊的先完成、新的後完成 → `bookmarks` 為新值（正常順序，目前就會綠）。
  - 新的失敗、舊的成功（舊的後完成）→ 清單維持載入前的值，舊結果不套用，不丟例外。
  - 舊的失敗、新的成功 → 清單為新值，不丟例外。
  - 開書第一次 `load`（快照 `[]`）還沒回來，`toggle`（新增書籤並自己 `load`）先完成，之後第一次 `load` 才完成 → `bookmarks` 含新書籤，`at(位置)` 非 null。
  - 單獨一次 `load` 照常更新（既有案例已涵蓋，不重複）。
  - 每個案例結束前讓所有閘門放行，避免遺留未完成的 `Future`。
- [ ] **Step 2（綠）：** `BookmarkController` 加 `int _loadSeq = 0;`。`load()` 改為：

  ```dart
  Future<void> load() async {
    final seq = ++_loadSeq;
    try {
      final loaded = await _repository.listByBook(_bookId);
      // 有較新的 load 已發出：這次結果過期，丟掉（Issue 30）。
      if (seq != _loadSeq) return;
      _bookmarks = loaded;
    } catch (e) {
      debugPrint('Failed to load bookmarks: $e');
    }
  }
  ```

  更新 `load()` 的 doc 註解：說明世代保護規則與「失敗只 `debugPrint`、清單維持現狀」。`toggle` 不動。
- [ ] **Step 3：** `flutter analyze`；跑 `test/reader/bookmark_controller_test.dart` 與 `test/screens/notes_bottom_sheet_test.dart`（若存在，使用同一個 controller）；`reader_screen_test.dart --plain-name "書籤"`；commit。

### Task 2：收尾

- [ ] **Step 1：** `epic.md` 開發記錄；`issues.md` Issue 30 狀態；`docs/epics.md` 同步。
- [ ] **Step 2：** 驗收：`grep -n "_loadSeq" app/lib/reader/bookmark_controller.dart` 有序號宣告與兩處使用；呼叫端檔案沒有差異（`git diff main --stat -- app/lib` 只有 `bookmark_controller.dart`）。
- [ ] **Step 3：** `flutter analyze`；兩個 `check_*.js`（沒有 Node 則記錄未執行）；完整 `flutter test`（`run_in_background`，只跑一個）。
- [ ] **Step 4：** 程式審查（報告存 `reviews/review-code-issue-30.md`，不進版控）。
- [ ] **Step 5：** WAVE 真機抽驗（風險低，抽驗一輪即可）：開 EPUB 一本，開書後立刻連點星號 5～6 次，星號狀態與最後一次點擊一致；到書籤清單確認資料正確；再開一本 PDF 做同樣操作。
- [ ] **Step 6：** 開 PR；PR 開出後把 Issue 29／30 的狀態同步。
