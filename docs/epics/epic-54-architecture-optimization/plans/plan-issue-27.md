# Issue 27：引擎分派判斷純函式實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤。

**Goal：** 把 `ReaderScreen._resolveEpubEngineDispatch`（`reader_screen.dart` 524–588，4 個近乎相同的防禦分支）與 `_handleFoliateLayoutResolved` 內「宣告為固定版面時忽略回報」的規則，抽成兩個純函式，集中在 `lib/reader/engine_dispatch.dart` 並以表格測試。純重構、零行為變化。

**Architecture：** 新增 `app/lib/reader/engine_dispatch.dart`：`sealed class EngineDispatch`（三態）、`resolveEngineDispatch`、`reconcileFixedLayoutFlag`。`ReaderScreen` 兩個欄位 `_dispatchedIsFixedLayout`（`bool?`，開書前結果）與 `_isFixedLayout`（`bool`，FXL 外觀開關）**都保留**——它們是兩個不同概念（`CONTEXT.md`「引擎分派判斷」）。補判斷的非同步呼叫、`setState`、重新連結後重跑解析留在 `ReaderScreen`。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`，設計依據是 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 27 設計決策」（決策 1～10）；詞彙見 `CONTEXT.md`「引擎分派判斷」「人工版面覆蓋」。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **純重構、零行為變化**（決策 1）。
- **兩個欄位都保留**（決策 2）：不合成、不改名、不改型別。`_dispatchedIsFixedLayout` 仍是 `bool?`，`_isFixedLayout` 仍是 `bool` 初值 `false`。
- **宣告值非 `null` 時，任何格式都直接採用**（含 PDF／unknown）：原碼 `_dispatchedIsFixedLayout = widget.isFixedLayout; if (!= null) return` 不看格式。
- **宣告值為 `true` 時外觀開關立刻設 `true`；為 `false` 時不碰外觀開關**（原碼只有 `== true` 才賦值）。
- **補判斷回來為 `true` 時不立刻設外觀開關**（決策 5，不對稱逐字保留）：只有 `_dispatchedIsFixedLayout` 被賦值。
- **「宣告為 `true` 時忽略回報」的 `true` 包含「強制 FXL」與 CBZ**（CBZ 的 `Book.isFixedLayout` 為 `true`）。
- **不新增 `ReaderScreen` 建構參數、不改 `isFixedLayoutHint` 傳遞**（`_dispatchedIsFixedLayout ?? widget.isFixedLayout`）、**不動重新連結後的重跑條件**（`_dispatchedIsFixedLayout == null && format == epub`）。
- **範圍外**：「人工版面覆蓋」（書架端，`library_batch_actions.dart`）、`detectAndCacheEpubLayout` 的實作、`EpubLayoutInfo`、ADR 0017／0023。
- **測試原則**：既有畫面測試**全部保留**（決策 7）；只新增純函式表格測試與一個不對稱記錄案例。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（`run_in_background`，不要同時跑第二個；系統記憶體吃緊時請先關閉其他程式）。
- **每個 Task／commit 結束都必須可編譯、`flutter analyze` 乾淨、被觸及的測試全綠**。
- **提交前**：`flutter analyze` 必須 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：多數原始檔是 CRLF，Edit 的定位字串不要含換行；`python` 編輯以 `newline=''` 開檔。
- **Commit**：不加 `Co-Authored-By`；依本 session 的歸屬規則，commit 結尾加 `Claude-Session:` 行。每個 Task 一個 commit。
- **不要提交** `app/android/gradle.properties`（使用者擱置的未提交變動）。
- **計畫與實作同分支同 PR**，不另開文件分支。

## Review Focus

最可能咬到使用者的情況（依可能性排序）：

1. **開書後畫面永遠停在載入中。** `_buildBody` 對 Foliate 格式要求 `_dispatchedIsFixedLayout != null`；若某格式在新函式裡誤回「需補判斷」或「不適用」，`_dispatchedIsFixedLayout` 會停在 `null`。→ Task 1 表格測試涵蓋每個格式；既有 AZW3／CBZ／TXT／MD 防禦案例（約 1432、1466、1621、1648）必須維持綠。
2. **EPUB 補判斷沒發起或發起兩次。** → 既有約 1375、1404 案例（`detectAndCacheEpubLayoutCalls == ['b1']`）與約 989、1024（宣告值非 `null` 時 `detectAndCacheEpubLayoutCalls` 為空）維持綠。
3. **強制 FXL 被 foliate 回報蓋掉**，或宣告為 `false` 時回報被忽略。→ 約 1939–1946 的 6 列矩陣與約 2245 案例維持綠；Task 1 對 `reconcileFixedLayoutFlag` 做 3 × 2 × 2 全組合表。
4. **不對稱被「順手修掉」**：補判斷回 `true` 就立刻設外觀開關。→ Task 2 新增記錄案例。
5. **宣告為 `false` 時 `_isFixedLayout` 被誤設成別的值。** 原碼只在宣告為 `true` 時賦值。
6. **PDF／unknown 格式的 `_dispatchedIsFixedLayout` 不再是 `null`。**
7. **重新連結後重跑解析失效。** → 重跑條件不動，函式名 `_resolveEpubEngineDispatch` 保留。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/engine_dispatch.dart` | 新增 | `EngineDispatch`（三態）、`resolveEngineDispatch`、`reconcileFixedLayoutFlag` |
| `app/lib/screens/reader_screen.dart` | 修改 | `_resolveEpubEngineDispatch` 改用 `resolveEngineDispatch`；`_handleFoliateLayoutResolved` 改用 `reconcileFixedLayoutFlag`；欄位註解同步 |
| `app/test/reader/engine_dispatch_test.dart` | 新增 | 兩個純函式的表格測試 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 新增 1 個不對稱記錄案例；既有案例不動 |
| `CONTEXT.md`、`epic.md`、`issues.md`、`docs/epics.md` | 已完成 | 設計定案時已更新 |

## Interface 草案（以實際編譯與既有型別為準）

```dart
/// 開書前解析的結果（CONTEXT「引擎分派判斷」的「開書前解析規則」）。
sealed class EngineDispatch {
  const EngineDispatch();
}

/// 已知：宣告值直接採用，或依格式的預設值。
final class EngineDispatchKnown extends EngineDispatch {
  const EngineDispatchKnown(this.isFixedLayout);
  final bool isFixedLayout;
}

/// 需補判斷：EPUB 且宣告值為 null；補判斷期間畫面維持載入。
final class EngineDispatchNeedsDetection extends EngineDispatch {
  const EngineDispatchNeedsDetection();
}

/// 不適用：PDF 等不套用固定版面旗標的格式，且宣告值為 null。
final class EngineDispatchNotApplicable extends EngineDispatch {
  const EngineDispatchNotApplicable();
}

EngineDispatch resolveEngineDispatch({
  required BookFormat format,
  required bool? declared,
});

/// 開書後回報如何改寫「FXL 外觀開關」：宣告為 true（含強制 FXL、CBZ）時忽略回報，
/// 保持 [current]；其餘以 [reported] 為準。
bool reconcileFixedLayoutFlag({
  required bool? declared,
  required bool reported,
  required bool current,
});
```

**解析表（`resolveEngineDispatch`）：**

| declared | format | 結果 |
|---|---|---|
| 非 null | 任何 | `Known(declared)` |
| null | epub | `NeedsDetection` |
| null | azw3 | `Known(false)` |
| null | cbz | `Known(true)` |
| null | txt | `Known(false)` |
| null | md | `Known(false)` |
| null | pdf／unknown | `NotApplicable` |

---

### Task 0：提交設計文件與計畫

- [x] **Step 1：** 分支 `epic-54/issue-27-engine-dispatch`（已從含 PR #365 的 `main` 建立）。
- [x] **Step 2：** 提交 `CONTEXT.md`、`epic.md`、`issues.md`、`docs/epics.md`、本計畫（純文件，一個 commit）。不提交 `app/android/gradle.properties`。

### Task 1：純函式與表格測試

**Files：** 新增 `engine_dispatch.dart`、`test/reader/engine_dispatch_test.dart`。

- [ ] **Step 1（紅）：** 寫 `engine_dispatch_test.dart`：
  - `resolveEngineDispatch`：
    - 宣告值非 `null`：對全部 7 種格式（epub／pdf／azw3／cbz／txt／md／unknown）各測 `true` 與 `false`，都回 `Known(declared)`（含 PDF／unknown）。
    - 宣告值為 `null`：依上方解析表逐格一個案例（epub → `NeedsDetection`；azw3／txt／md → `Known(false)`；cbz → `Known(true)`；pdf／unknown → `NotApplicable`）。
  - `reconcileFixedLayoutFlag`：`declared`（`null`／`false`／`true`）× `reported`（`true`／`false`）× `current`（`true`／`false`）共 12 列：`declared == true` → 回 `current`；其餘 → 回 `reported`。
  - 用 `switch` 對三態做窮舉斷言，確保 sealed 型別的窮舉編譯檢查有效。
- [ ] **Step 2（綠）：** 實作 `engine_dispatch.dart`。註解沿用原碼的 `epic-11` Issue 2 C2 教訓說明（防禦預設值是為了避免畫面永遠停在載入）。
- [ ] **Step 3：** `flutter analyze`；跑 `test/reader/engine_dispatch_test.dart`；commit。

### Task 2：`ReaderScreen` 遷移與不對稱記錄案例

**Files：** `reader_screen.dart`、`test/screens/reader_screen_test.dart`。

- [ ] **Step 1：** `_resolveEpubEngineDispatch` 改為：

  ```dart
  void _resolveEpubEngineDispatch() {
    final dispatch = resolveEngineDispatch(
      format: detectBookFormat(_activeFilePath),
      declared: widget.isFixedLayout,
    );
    switch (dispatch) {
      case EngineDispatchKnown(:final isFixedLayout):
        _dispatchedIsFixedLayout = isFixedLayout;
        // 宣告／預設為固定版面時，同步設外觀開關（不受開書後回報覆蓋）
        if (isFixedLayout) _isFixedLayout = true;
      case EngineDispatchNotApplicable():
        _dispatchedIsFixedLayout = null;
      case EngineDispatchNeedsDetection():
        _dispatchedIsFixedLayout = null;
        // 發起補判斷（原碼 580–587 行），.then 內 mounted 檢查與 setState 逐字保留
    }
  }
  ```

  注意：原碼第一行 `_dispatchedIsFixedLayout = widget.isFixedLayout;` 在 `NotApplicable`／`NeedsDetection` 時等於賦值 `null`，行為相同。**原本 4 個防禦分支的長註解整段刪除**，其內容已搬進 `engine_dispatch.dart`。
- [ ] **Step 2：** `_handleFoliateLayoutResolved` 內 `if (widget.isFixedLayout != true) { _isFixedLayout = info.isFixedLayout; }` 改為 `_isFixedLayout = reconcileFixedLayoutFlag(declared: widget.isFixedLayout, reported: info.isFixedLayout, current: _isFixedLayout);`，其餘（`_autoDetectedWritingMode`、`_resolved`）不動。
- [ ] **Step 3：** 欄位註解同步（`_dispatchedIsFixedLayout` 約 418–428 行、方法 doc 約 514–523 行）：指向 `engine_dispatch.dart` 與 `CONTEXT.md`「引擎分派判斷」，保留「與 `_isFixedLayout` 是不同概念」的說明；加 import `../reader/engine_dispatch.dart`。
- [ ] **Step 4：** 新增不對稱記錄案例，放在約 2003（矩陣迴圈結束）之後，搭建比照矩陣（約 1951–1973）與補判斷案例（約 1375 的 `FakeLibraryRepository(detectedIsFixedLayout: true)`）：
  - 宣告值 `null`、補判斷回 `true`、檔案用 `sample_fixed_layout.epub`；
  - **尚未呼叫 `onLayoutResolved` 時**點版面按鈕，應開啟 `ReaderSettingsSheet`（外觀開關仍為 `false`），不是 `FxlSettingsSheet`；
  - 關閉面板後呼叫 `onLayoutResolved(isFixedLayout: true)`，再點版面按鈕，應開啟 `FxlSettingsSheet`。
  - 案例名稱與註解標明「補判斷回 true 不立刻設外觀開關為既有行為，是否對稱化另議（epic-54 Issue 27 決策 5）」。
  - 若版面按鈕在回報前不可點、無法觀察，改用同一個外觀開關的其他可觀察結果（例如 `onLayoutTap` 以外的 `_isFixedLayout` 分支）並在 `epic.md` 記錄偏差；不可為了讓案例成立而改實作。
- [ ] **Step 5：** 驗證：`flutter analyze`；跑 `reader_screen_test.dart` 中與版面有關的案例（`--plain-name "isFixedLayout"`、`--plain-name "onLayoutResolved"`、`--plain-name "強制 FXL"`、`--plain-name "AZW3"`、`--plain-name "CBZ"`、`--plain-name "TXT 書籍"`、`--plain-name "MD 書籍"`、`--plain-name "FXL"`）、`engine_dispatch_test.dart`、`reader_screen_route_test.dart`；commit。

### Task 3：收尾

- [ ] **Step 1（設計定案時已完成）：** `CONTEXT.md`「引擎分派判斷」詞條補開書前解析規則與兩個值的差別。
- [ ] **Step 2：** `epic.md` 開發記錄；`issues.md` Issue 27 狀態；`docs/epics.md` 對應列同步。
- [ ] **Step 3：** 驗收：`grep -n "防禦性視為\|防禦性補上" app/lib/screens/reader_screen.dart` 應為 0（4 個防禦分支的註解已搬走）；`reader_screen.dart` 的 `_resolveEpubEngineDispatch` 不再出現 `BookFormat.azw3`／`BookFormat.cbz`／`BookFormat.txt`／`BookFormat.md`。
- [ ] **Step 4：** `flutter analyze`；`node tool/check_l10n_hardcoded_strings.js`；`node tool/check_integration_keys.js`；完整 `flutter test`（`run_in_background`，只跑一個）。
- [ ] **Step 5：** WAVE 真機抽驗（備一本流式 EPUB、一本 FXL EPUB、一本 CBZ、一本 PDF、一本 TXT）：每本都能正常開啟（不卡在載入）；FXL EPUB 與 CBZ 的懸浮設定按鈕與 FXL 設定面板正確；流式 EPUB 與 TXT 開版面設定是流式面板；書架對 EPUB 做「強制 FXL」後重開，外觀是 FXL；「恢復自動判斷」後重開，回到原判斷。
- [ ] **Step 6：** 程式審查（報告存 `reviews/review-code-issue-27.md`，不進版控）；開 PR；PR 開出後把 Issue 26 與 Issue 27 的狀態同步。
