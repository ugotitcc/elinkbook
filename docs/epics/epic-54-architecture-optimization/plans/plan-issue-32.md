# Issue 32：`AnnotationController.reload()` 世代保護實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 修掉 `AnnotationController.reload()` 的亂序覆寫：先發出的舊 `reload` 比後發出的新 `reload` 晚完成時，不得把劃線與備註清單蓋回過期值。

**Architecture：** 在 `AnnotationController` 內加遞增序號 `_reloadSeq`。每次 `reload()` 取得自己的序號；劃線與備註兩個查詢都完成後只檢查一次，序號不是最新就丟掉兩份結果。對外介面不變，呼叫端不改。與 Issue 30 同型，但錯誤行為不變（不加 `try/catch`）。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 32 設計決策」（決策 1～9）。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **只改 `AnnotationController.reload()`**（決策 1）：不改 `createHighlight`、`saveNote`、`deleteExisting`、`existingItem`，不改呼叫端（`ReaderScreen`），不改 `BookmarkController`。
- **不排隊、不加鎖**（決策 2）。
- **錯誤行為不變**（決策 3）：不加 `try/catch`；查詢失敗時例外照舊往外丟，包含「已過期的那次」。
- **兩份清單一起套用或一起丟掉**（決策 2）：序號只在兩個 `await` 都結束後檢查一次。
- **不抽共用工具**（決策 4）。
- **測試原則**：既有 `annotation_controller_test.dart` 案例全部保留；只新增案例與測試用假 repository。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，只跑一個）。
- **每個 Task／commit 結束都必須可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**。
- **提交前**：`flutter analyze` 必須 "No issues found!"；`node tool/check_l10n_hardcoded_strings.js`、`node tool/check_integration_keys.js`（本機 nvm 沒裝 Node 則無法執行，記錄在 `epic.md`）。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔；不要對整個檔案跑 `dart format`（會改到舊程式與換行字元）。
- **Commit**：不加 `Co-Authored-By`；結尾加 `Claude-Session: https://claude.ai/code/session_019bmfxQJ1gaKoHGoWH7gJwD`。每個 Task 一個 commit。
- **不要提交** `app/android/gradle.properties`（使用者擱置的未提交變動）。
- **計畫與實作同分支同 PR**，不另開文件分支。

## Review Focus

1. **序號丟掉了不該丟的結果。** 單獨一次 `reload()`、依序完成的兩次 `reload()`、以及 `createHighlight`／`saveNote`／`deleteExisting` 結尾的 `reload()` 都必須照常更新清單。→ 既有 28 個案例全綠，另有「舊的先完成、新的後完成」案例。
2. **半套用。** 劃線已更新、備註還是舊的（或相反）。→ 檢查點只在兩個 `await` 之後，且有「兩份一起丟掉」案例。
3. **失敗路徑。** 例外必須照舊往外丟（含過期那次）；失敗那次不得改動清單。→ 失敗案例。
4. **寫入流程的收尾欄位。** `createHighlight` 結尾 `_pendingHighlightId = id`、`saveNote` 結尾清 `_selection`／`_pendingHighlightId`，與清單是否被丟棄無關，行為不變。→ 不新增程式，確認這兩處維持原樣。
5. **呼叫端不依賴 `reload()` 是否改了清單。** `_reloadAnnotations()` 完成後無條件 `setState` 並重畫（`reader_screen.dart` 約 1677 行）。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/annotation_controller.dart` | 修改 | `reload()` 加 `_reloadSeq`，過期結果丟棄 |
| `app/test/reader/annotation_controller_test.dart` | 修改 | 新增可手動控制完成順序的假 repository 與亂序案例 |
| `CONTEXT.md` | 不動 | 無新詞彙 |

---

### Task 0：提交設計文件與計畫

- [x] **Step 1：** 分支 `epic-54/issue-32-annotation-reload-generation`（已從含 PR #368 的 `main` 建立）。
- [x] **Step 2：** 提交 `epic.md`、`issues.md`、`docs/epics.md`、本計畫（純文件，一個 commit）。不提交 `app/android/gradle.properties`。

### Task 1：世代保護與亂序測試

**Files：** `annotation_controller.dart`、`test/reader/annotation_controller_test.dart`。

測試用假 repository 草案（以實際編譯為準）。比照 Issue 30：閘門與快照都在第一個 `await` 之前同步取得，並提供 `releaseAll()`：

```dart
/// 可手動控制 listByBook 完成順序，模擬「較舊的查詢比較新的查詢晚回來」。
/// 繼承 [FakeHighlightsRepository]：儲存與 insert／delete 都沿用，只覆寫 listByBook。
class _GatedHighlightsRepository extends FakeHighlightsRepository {
  final List<Completer<void>> _gates = [];
  final List<bool> _failures = [];

  /// 下一次 listByBook 要等這個閘門；fail 為 true 時，放行後丟例外。
  Completer<void> gateNext({bool fail = false}) {
    final gate = Completer<void>();
    _gates.add(gate);
    _failures.add(fail);
    return gate;
  }

  /// 放行所有尚未完成的閘門；tearDown 呼叫，避免斷言失敗時遺留未完成的 Future。
  void releaseAll() {
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
    _gates.clear();
    _failures.clear();
  }

  @override
  Future<List<Highlight>> listByBook(String bookId) async {
    // 閘門與快照都在第一個 await 之前同步取得：快照定格在「呼叫當下」，
    // 閘門依「呼叫順序」分配。
    final snapshotFuture = super.listByBook(bookId);
    final gate = _gates.isEmpty ? null : _gates.removeAt(0);
    final fail = gate == null ? false : _failures.removeAt(0);
    final snapshot = await snapshotFuture;
    if (gate == null) return snapshot;
    await gate.future;
    if (fail) throw StateError('查詢失敗');
    return snapshot;
  }
}
```

備註端另寫對稱的 `_GatedNotesRepository extends FakeNotesRepository`（審查 I-2）：

```dart
/// 可手動控制 listByBook 完成順序；與 [_GatedHighlightsRepository] 對稱。
class _GatedNotesRepository extends FakeNotesRepository {
  final List<Completer<void>> _gates = [];
  final List<bool> _failures = [];

  Completer<void> gateNext({bool fail = false}) {
    final gate = Completer<void>();
    _gates.add(gate);
    _failures.add(fail);
    return gate;
  }

  void releaseAll() {
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
    _gates.clear();
    _failures.clear();
  }

  @override
  Future<List<Note>> listByBook(String bookId) async {
    final snapshotFuture = super.listByBook(bookId);
    final gate = _gates.isEmpty ? null : _gates.removeAt(0);
    final fail = gate == null ? false : _failures.removeAt(0);
    final snapshot = await snapshotFuture;
    if (gate == null) return snapshot;
    await gate.future;
    if (fail) throw StateError('查詢失敗');
    return snapshot;
  }
}
```

`group('reload 世代保護')` 的 `setUp` 統一建立 `_GatedHighlightsRepository` 與 `_GatedNotesRepository` 並注入 controller，每個案例依需求呼叫 `gateNext()`。

注意：`reload()` 先查劃線，劃線查詢完成後才查備註，所以備註閘門是在「劃線那一步結束後」才被取走，順序仍依呼叫順序分配。「舊的卡在備註」案例中，兩次 `reload()` 必須在同一個同步區段內先後發出（中間不 `await`），實作時先確認該案例在沒有 `_reloadSeq` 時確實是紅燈。

- [ ] **Step 1（紅）：** 在 `annotation_controller_test.dart` 新增 `group('reload 世代保護')`，先寫測試、確認失敗：
  - 先發的舊 `reload`（劃線快照 `[h1]`）、後發的新 `reload`（快照 `[h1, h2]`）；新的先完成、舊的後完成 → `highlights` 為 `[h1, h2]`（目前會被蓋回 `[h1]`，紅燈）。
  - 循序兩次：第一次 `reload()` 完成後才發第二次 → 兩次都依序套用，`highlights` 依序為舊值、新值（目前就會綠）。
  - 並行兩次、舊的先完成：兩次 `reload()` 都已發出，舊的先放行 → 當下 `highlights` 不變（舊結果因序號過期被丟掉），新的放行後才變成新值（審查 M-1；目前會在舊的完成當下被蓋成舊值，紅燈）。
  - 舊的卡在第二個查詢（備註）時，新的整個完成；放行舊的 → 劃線與備註都維持新值（一起丟掉，不半套用，目前紅燈）。
  - 新的那次查詢失敗 → `await` 該次 `reload()` 丟例外，清單維持原值。
  - 舊的那次查詢失敗 → `await` 該次 `reload()` 照舊丟例外，已套用的新值不變。
  - 開書第一次 `reload`（快照空）還沒回來，`createHighlight`（自己 `reload`）先完成，之後第一次 `reload` 才完成 → `highlights` 含新劃線，`pendingHighlightId` 為新劃線 id（目前紅燈）。
  - 在 `group` 內宣告 `tearDown`，同時放行兩個 repository 的閘門（審查 I-1）：

    ```dart
    tearDown(() {
      highlightsRepository.releaseAll();
      notesRepository.releaseAll();
    });
    ```
- [ ] **Step 2（綠）：** `AnnotationController` 加 `int _reloadSeq = 0;`。`reload()` 改為：

  ```dart
  Future<void> reload() async {
    final seq = ++_reloadSeq;
    final highlights = await highlightsRepository.listByBook(bookId);
    final notes = await notesRepository.listByBook(bookId);
    // 有較新的 reload 已發出：這次結果過期，兩份一起丟掉（Issue 32）。
    if (seq != _reloadSeq) return;
    _highlights = highlights;
    _notes = notes;
  }
  ```

  為 `reload()` 加 doc 註解：說明世代保護規則、「兩份清單一起套用或一起丟掉」與「查詢失敗時例外照舊往外丟」，並標註 `（epic-54 Issue 32）`。其餘方法不動。
- [ ] **Step 3：** `flutter analyze`；跑 `test/reader/annotation_controller_test.dart`、`test/screens/reader_screen_test.dart --name="劃線|備註"`（多個 `--plain-name` 會要求同時符合，所以改用正則，審查 M-2）；commit。

### Task 2：收尾

- [ ] **Step 1：** `epic.md` 開發記錄；`issues.md` Issue 32 狀態；`docs/epics.md` 同步。
- [ ] **Step 2：** 驗收：`grep -n "_reloadSeq" app/lib/reader/annotation_controller.dart` 有序號宣告與兩處使用；`git diff main --stat -- app/lib` 只有 `annotation_controller.dart`。
- [ ] **Step 3：** `flutter analyze`；兩個 `check_*.js`（沒有 Node 則記錄未執行）；完整 `flutter test`（`run_in_background`，只跑一個）。
- [ ] **Step 4：** 程式審查（報告存 `reviews/review-code-issue-32.md`，不進版控）。
- [ ] **Step 5：** WAVE 真機抽驗（風險低，一輪即可）：開 EPUB 一本，連續建立 3～4 筆劃線（快速操作），再刪除其中一筆；畫面上的劃線與清單一致；再開一本 PDF 做同樣操作。
- [ ] **Step 6：** 開 PR；PR 開出後把 Issue 32 的狀態同步（Issue 30 已在 Task 0 同步）。
