# Issue 19：EPUB 目錄「目前章節」判定在開書當下不可靠——改以 spine index 判定 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:executing-plans` 逐 Task 執行本計畫（**使用者明確要求嚴禁 subagent**，不要用 `subagent-driven-development`）。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 讓 EPUB「目前章節」判定（目錄預設展開／高亮、書籤章節名、頁首章節名）在開書當下就命中正確章節，並把 `epub_toc_test` 改回斷言「開書時第二章預設收合」。

**Architecture：** 問題出在 `TocNavigator.findCurrentPath` 只用「全書 progression」比對：(a) 無頁內錨點的頂層章節 `TocEntry.progression` 結構性為 `null`，永遠不會被選中；(b) 開書初始的全書 fraction 偏高（foliate 位元組估計含當前頁 double-count，`TCL 14` 實測 0.554＝2×1763／6362），使後面章節的子節被誤判為「已通過」。`TocEntry.locatorJson` 與 `EpubPositionInfo.locatorJson` **都已含 spine `index`**（`main.js buildTocEntry` 與 `relocate` 回報皆為 `{cfi, index, fraction}`）。改法：`findCurrentPath` 新增可選參數 `currentSpineIndex`，**先比 spine index（章節層級，精確），同一 spine 內才用 progression 判先後**；節點或目前位置缺 index 時，退回舊的純 progression 規則（向下相容，PDF 與既有測試不受影響）。**不改 `main.js`、不改 foliate vendor 程式**，只改 Dart。

**Tech Stack：** Flutter／Dart、`flutter_test`、`integration_test`、`adb`、Node（既有守衛腳本）。指令一律在 `app/` 目錄下執行（除非另有標明），以 **Bash 工具（Git Bash）** 為準。

**Spec：** 沒有獨立 `spec.md`。缺陷描述見 `docs/epics/epic-54-architecture-optimization/issues.md` 第 19 列；證據見 `epic.md`「Issue 18 實作完成與真機驗證結果」(1)；`reviews/triage-issue-18.md` §(1)（gitignore，本機 worktree 才有）。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **向下相容**：`TocNavigator.findCurrentPath(entries, progression)` 兩參數呼叫的行為必須與現況**逐案相同**（`test/reader/toc_navigator_test.dart` 既有 6 案不得修改、不得放寬）。`PdfTocNavigator` 不在範圍。
- **不放寬測試**：不得為了通過而刪斷言／加 `skip`／弱化 matcher。`epub_toc_test` 是**收緊**（改回斷言初始收合），不是放寬。
- **不改 vendor／JS**：`app/android/app/src/main/assets/foliate/` 與 `main.js` 不動（ADR 0011：釘定版本）。
- **使用者決定**：任何寫入文件的「使用者決定」必須是對話中真有的原話（Issue 17 程式審查 M-1 教訓）；本計畫第 2 項「演算法取捨」須在 Task 0 取得使用者回答後才實作。
- **真機**：`TCL 14`（序號 `3CEF42ECD491687`，Android 15）。結果只宣稱此裝置通過。執行前須向使用者確認可清除該裝置上 `cc.ugotit.elinkbook` 資料。`adb` 路徑 `/c/Users/fycdc/AppData/Local/Android/Sdk/platform-tools/adb.exe`（Git Bash 先 `export MSYS_NO_PATHCONV=1`）。
- **測試範圍**（`CLAUDE.md`）：單一 Task 只跑異動觸及的測試；完整 `flutter test` 只在最後一個 Task 跑一次（`run_in_background`，在 `app/` 下）。
- **提交前**：`flutter analyze` 必須 "No issues found!"；改了 `integration_test/` 後跑 `node tool/check_integration_keys.js`；改了畫面字串或測試後跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：多數原始檔是 CRLF，`Edit` 定位字串不要含換行。提交一律明確路徑 `git add`。Commit 結尾須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：本計畫先審查再動手；程式審查先出報告（存 `reviews/`），審查者不直接改程式。Epic 54 的進度同步為純文件，直接 commit＋push `main`（不開 PR）；程式變更走分支＋PR。

## 已查證的事實（撰寫計畫時對照 `lib/` 所得，執行者開工前須再確認一次）

| 項目 | 事實 | 出處 |
|---|---|---|
| 現行判定 | DFS 前序走訪，節點 `progression != null && progression <= currentProgression` 就更新最佳路徑；`currentProgression == null` 回空 | `lib/reader/toc_navigator.dart:19-38` |
| 呼叫端（4 處） | `_openToc`（1336）、`_openNotesSheet`（1467，取書籤章節名）、`_currentChapterTitle`（2272，目前無呼叫端、`ignore: unused_element`）、`_buildFoliateHeaderText`（3008，頁首取 `currentPath.first`）。皆傳 `_epubPositionInfo?.progression` | `lib/screens/reader_screen.dart` |
| 兩端都有 index | 目錄節點 `locatorJson = {cfi, index, fraction}`（無法解析 href 時為空字串 `''`）；位置回報 `EpubPositionInfo.locatorJson` 同格式。既有 `extractChapterIndex(String?)` 解析之（非 JSON／無 index 回 `null`） | `main.js:720-757`、`lib/reader/foliate_bridge_codec.dart:10-21`、`reader_screen.dart:3158` 已有使用先例 |
| 避免循環 import | `toc_entry.dart` 不要 import `foliate_bridge_codec.dart`（後者已 import 前者）。解析 index 的 helper 放在 `toc_navigator.dart`（它 import codec，codec 不 import navigator） | `foliate_bridge_codec.dart:5` |
| 既有測試 fixture | `toc_navigator_test.dart` 的 `locatorJson` 為 `'l1'` 等非 JSON → index 為 `null` → 走退回路徑，既有 6 案天然相容 | `test/reader/toc_navigator_test.dart` |
| 缺口 | 目前**沒有**任何測試涵蓋「頂層章節 progression 為 null」與「progression 偏高」兩種真實情境 | 同上 |
| 整合測試待收緊處 | `integration_test/epub_toc_test.dart` 約 131-139 行（`TODO(Issue 19)` 註解）與 154-170 行（`if (find.text('第一節').evaluate().isNotEmpty)` 先收起的容錯分支） | `integration_test/epub_toc_test.dart` |

## 演算法（Task 1 實作對象）

`findCurrentPath(entries, currentProgression, {int? currentSpineIndex})`：

```
若 currentProgression == null 且 currentSpineIndex == null → 回空清單（與現況同）
對每個節點（DFS 前序，後者覆蓋前者，與現況同）判斷「已通過」passed：
  nodeIdx = 從 node.locatorJson 解析的 spine index（失敗為 null）
  若 currentSpineIndex != null 且 nodeIdx != null：
      nodeIdx <  currentSpineIndex → passed = true
      nodeIdx >  currentSpineIndex → passed = false
      nodeIdx == currentSpineIndex → 同 spine 內：
            node.progression == null  → passed = true（章節起點，無錨點）
            currentProgression == null → passed = true
            否則 passed = node.progression <= currentProgression
  否則（缺 index，退回舊規則）：
      passed = node.progression != null && currentProgression != null
               && node.progression <= currentProgression
passed 的節點就把「目前累積路徑」更新為該節點；走訪完回傳最後保留的路徑
```

已知取捨（Task 0 須請使用者確認）：同一 spine 內若有多個錨點，仍依 progression 比大小；開書當下 progression 偏高時，可能多選到同章內較後面的子節（只影響「同章內」，不再跨章）。若使用者要求同章內也精確，需改 `main.js` 回報錨點的 section 內 fraction，屬另案。

## Review Focus

最可能咬到使用者的情況，依可能性排序：

1. **同一本書多個目錄項指向同一 spine（單檔多錨點或章節內分節）**：開書在章首時，不得誤展開本章後段子節以外的其他章；章首無錨點的頂層章節要被選中。→ Task 1 測試「同 spine、頂層 progression 為 null」「同 spine、子節 progression 大於目前」。
2. **目錄節點 `locatorJson` 為空字串（href 無法解析）**：不得因 index 為 null 而被誤判為已通過或拋例外。→ Task 1 測試「節點缺 index 退回舊規則」。
3. **目前位置尚無 index（開書瞬間 `locatorJson` 不是 JSON）**：必須與現況行為相同。→ Task 1 測試「currentSpineIndex 為 null 時行為不變」＋既有 6 案。
4. **書籤章節名也走同一函式**：修正後書籤標題不得變成空白或回到書名。→ Task 2 對 `_openNotesSheet` 呼叫點的人工檢視＋既有 `reader_screen_test` 相關案例。
5. **跳轉後（點第三章）判定要跟著更新**：不得只在開書當下正確。→ Task 3 integration 在跳到第三章後再次開目錄，斷言第三章被高亮／第二章收合（見 Step）。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/toc_navigator.dart` | 修改 | `findCurrentPath` 新增 `currentSpineIndex` 與 spine-first 判定 |
| `app/test/reader/toc_navigator_test.dart` | 修改（只新增案例，不動既有 6 案） | 新演算法單元測試 |
| `app/lib/screens/reader_screen.dart` | 修改 | 4 個呼叫點改傳 `currentSpineIndex`（抽 1 個私有 helper） |
| `app/integration_test/epub_toc_test.dart` | 修改 | 改回斷言初始收合、移除 `TODO(Issue 19)` 與容錯分支 |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 結果與狀態（Task 4） |

---

### Task 0：確認前提並取得演算法取捨決定

**Files:** 無程式修改。

- [x] **Step 1: 再確認三項事實**

```bash
cd /c/Users/fycdc/AI/elinkBook/app
git status --short
grep -n "static List<TocEntry> findCurrentPath" -A3 lib/reader/toc_navigator.dart
grep -n "TocNavigator.findCurrentPath" lib/screens/reader_screen.dart
grep -n "int? extractChapterIndex" lib/reader/foliate_bridge_codec.dart
```

Expected：工作樹乾淨；`findCurrentPath` 仍為兩參數；`reader_screen.dart` 恰 4 處呼叫（1336／1467／2272／3008 附近）；`extractChapterIndex` 存在。任何一項不符，先停下回報。

- [x] **Step 2: 向使用者呈報取捨並等待回答（回答前不得改 `lib/`、不得改測試）**

呈報內容：

```
方案：先比 spine index、同 spine 內才比 progression（本計畫「演算法」一節）。
取捨：同一 spine 內若有多個錨點，開書當下 progression 偏高時，可能多選到同章較後的子節
      （不再跨章誤判）。要同章也精確須改 main.js（另案）。
替代：A) 完全不用 progression、只用 spine index（同章多錨點一律只選到第一個）；
      B) 本計畫方案（建議）；
      C) 先改 main.js 讓每個目錄項回報 section 內 fraction（範圍較大）。
請選 A／B／C。
```

把使用者原話記入計畫「附錄 A」（Step 3 才補），不得改寫。

- [x] **Step 3: 建立分支**

```bash
git switch -c epic-54/issue-19-toc-current-chapter
```

---

### Task 1：`findCurrentPath` 的 spine-first 判定（純函式，TDD）

**Files:**
- Modify: `app/lib/reader/toc_navigator.dart`
- Test: `app/test/reader/toc_navigator_test.dart`（檔尾 `group` 之後新增第二個 `group`，**不動**既有 `group('findCurrentPath')`）

**Interfaces:**
- Consumes：`extractChapterIndex(String? locatorJson) -> int?`（`lib/reader/foliate_bridge_codec.dart`）、`TocEntry`（`title`／`locatorJson`／`progression`／`children`）。
- Produces：`static List<TocEntry> findCurrentPath(List<TocEntry> entries, double? currentProgression, {int? currentSpineIndex})`——Task 2 的呼叫端使用這個簽章。回傳語意不變（根到目前章節的祖先路徑，含自身；無命中回空 `const []`）。

- [x] **Step 1: 寫失敗測試**

在 `test/reader/toc_navigator_test.dart` 檔尾 `}` 之前、既有 `group` 之後新增（需補 `import 'dart:convert';`）：

```dart
  /// 產生與 main.js buildTocEntry 同格式的 locatorJson：{cfi, index, fraction}。
  String loc(int index, [double? fraction]) =>
      jsonEncode({'cfi': 'epubcfi(/6/${index * 2 + 2})', 'index': index, 'fraction': fraction});

  group('findCurrentPath（spine index 優先，Issue 19）', () {
    // 重現 TCL 14 真機：三個頂層章節各佔一個 spine，頂層 progression 結構性為 null，
    // 第二章有兩個子節（同 spine 1，帶錨點 progression）。
    final c1 = TocEntry(title: '第一章', locatorJson: loc(0), progression: null);
    final c2s1 = TocEntry(title: '第一節', locatorJson: loc(1, 0.30), progression: 0.30);
    final c2s2 = TocEntry(title: '第二節', locatorJson: loc(1, 0.45), progression: 0.45);
    final c2 = TocEntry(
      title: '第二章',
      locatorJson: loc(1),
      progression: null,
      children: [c2s1, c2s2],
    );
    final c3 = TocEntry(title: '第三章', locatorJson: loc(2), progression: null);
    final toc = [c1, c2, c3];

    test('開書在第一章、全書 progression 偏高（0.554）時，仍判定為第一章（不誤展開第二章）', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.554, currentSpineIndex: 0),
        [c1],
      );
    });

    test('頂層章節 progression 為 null 也能靠 spine index 被選中', () {
      expect(
        TocNavigator.findCurrentPath(toc, null, currentSpineIndex: 2),
        [c3],
      );
    });

    test('位於第二章章首（尚未到任何子節錨點）時，只選第二章本身', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.10, currentSpineIndex: 1),
        [c2],
      );
    });

    test('位於第二章且已過第一節錨點時，回傳第二章→第一節的完整路徑', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.35, currentSpineIndex: 1),
        [c2, c2s1],
      );
    });

    test('位於第二章且已過第二節錨點時，回傳第二章→第二節的完整路徑', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.50, currentSpineIndex: 1),
        [c2, c2s2],
      );
    });

    test('跳轉至第三章且帶有全書 progression 時，精確判定為第三章', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.90, currentSpineIndex: 2),
        [c3],
      );
    });

    test('節點 locatorJson 為空字串（href 無法解析）時退回 progression 規則，不拋例外', () {
      final broken = TocEntry(title: '壞節點', locatorJson: '', progression: 0.2);
      expect(
        TocNavigator.findCurrentPath([c1, broken], 0.5, currentSpineIndex: 0),
        [broken],
        reason: '缺 index 的節點沿用舊規則：progression 0.2 <= 0.5 視為已通過',
      );
    });

    test('currentSpineIndex 為 null 時行為與舊規則相同（向下相容）', () {
      expect(TocNavigator.findCurrentPath(toc, 0.35), [c2, c2s1],
          reason: '頂層 progression 全為 null，舊規則下只有子節 0.30 <= 0.35 命中');
    });

    test('currentProgression 與 currentSpineIndex 皆為 null 時回傳空清單', () {
      expect(TocNavigator.findCurrentPath(toc, null), isEmpty);
    });
  });
```

- [x] **Step 2: 跑測試確認失敗**

Run：`flutter test test/reader/toc_navigator_test.dart`
Expected：新 group 因 `currentSpineIndex` 命名參數不存在而編譯失敗（`No named parameter with the name 'currentSpineIndex'`）；既有 6 案暫時也無法執行（同檔編譯失敗）。

- [x] **Step 3: 實作**

`lib/reader/toc_navigator.dart` 頂端新增 `import 'foliate_bridge_codec.dart';`，並把 `findCurrentPath` 改為：

```dart
  /// 找出讀者目前所在（或剛通過）的章節，回傳從樹根到該章節的完整祖先
  /// 路徑（含自身）。演算法：對整棵樹做深度優先前序走訪（此順序即為書本
  /// 閱讀順序——子章節緊接在父章節標題之後，早於下一個同層級兄弟節點），
  /// 逐一判斷每個節點「是否已被讀者通過」，只要通過就把「目前累積路徑」
  /// 更新為目前為止最新符合的一筆；走訪結束時保留的即為讀者目前最深、最新
  /// 通過的章節。
  ///
  /// 「已通過」的判定（epic-54 Issue 19）：
  /// - 節點與目前位置都有 spine index（[extractChapterIndex]）時，**先比
  ///   spine index**：節點在目前 spine 之前＝已通過、之後＝未通過；同一個
  ///   spine 內，節點沒有 progression（章節起點、無頁內錨點）視為已通過，
  ///   有 progression 才與 [currentProgression] 比大小。
  /// - 任一方缺 index（例如目錄節點 href 無法解析、locatorJson 為空字串，
  ///   或 [currentSpineIndex] 為 `null`）則退回舊規則：節點 progression
  ///   與 [currentProgression] 皆非 null 且 `<=` 才算通過。
  ///
  /// 為什麼不能只靠全書 progression：頂層章節沒有頁內錨點，`TocEntry
  /// .progression` 結構性為 `null`；而開書當下 foliate 的全書 fraction 估計
  /// 偏高（小章節單頁時位元組估計 double-count），兩者疊加會讓開書當下命中
  /// 後面章節的子節。spine index 是章節層級的精確資訊，不受此影響。
  ///
  /// [currentProgression] 與 [currentSpineIndex] 皆為 `null`（例如尚未收到
  /// 任何 `onLocatorChanged` 回報）或沒有任何節點通過時，回傳空清單——
  /// 呼叫端據此不預設展開任何層級、不高亮任何項目。
  static List<TocEntry> findCurrentPath(
    List<TocEntry> entries,
    double? currentProgression, {
    int? currentSpineIndex,
  }) {
    if (currentProgression == null && currentSpineIndex == null) {
      return const [];
    }
    List<TocEntry>? bestPath;
    void walk(List<TocEntry> nodes, List<TocEntry> path) {
      for (final node in nodes) {
        final newPath = [...path, node];
        if (_hasPassed(node, currentProgression, currentSpineIndex)) {
          bestPath = newPath;
        }
        walk(node.children, newPath);
      }
    }

    walk(entries, const []);
    return bestPath ?? const [];
  }

  /// 單一節點是否已被讀者通過，規則見 [findCurrentPath] 的文件註解。
  ///
  /// 每個節點都會重新解析一次 locatorJson（[extractChapterIndex] 內含
  /// `jsonDecode`）：EPUB 目錄規模小（數十至數百節點）、解析為微秒級，刻意
  /// 維持純函式、不加快取，避免引入物件狀態。
  static bool _hasPassed(
    TocEntry node,
    double? currentProgression,
    int? currentSpineIndex,
  ) {
    final nodeIndex = extractChapterIndex(node.locatorJson);
    if (currentSpineIndex != null && nodeIndex != null) {
      if (nodeIndex < currentSpineIndex) return true;
      if (nodeIndex > currentSpineIndex) return false;
      // 同一個 spine 內：無錨點的章節起點視為已通過。
      final progression = node.progression;
      if (progression == null || currentProgression == null) return true;
      return progression <= currentProgression;
    }
    final progression = node.progression;
    return progression != null &&
        currentProgression != null &&
        progression <= currentProgression;
  }
```

- [x] **Step 4: 跑測試確認通過**

Run：`flutter test test/reader/toc_navigator_test.dart`
Expected：全部通過（既有 6 案＋新 9 案）。

- [x] **Step 5: 突變驗證（證明新測試會咬人）**

暫時把 `_hasPassed` 內 `if (nodeIndex > currentSpineIndex) return false;` 改為 `return true;`，跑同一檔，Expected：「開書在第一章…0.554」等案失敗；還原後再跑一次確認全過。

- [x] **Step 6: Commit**

```bash
flutter analyze
git add lib/reader/toc_navigator.dart test/reader/toc_navigator_test.dart
git commit -m "fix(epic-54): Issue 19 findCurrentPath 改以 spine index 優先判定目前章節" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：`ReaderScreen` 四個呼叫點改傳 `currentSpineIndex`

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`（約 1336、1467、2272、3008 的四處 `TocNavigator.findCurrentPath(...)`）
- Test: 既有 `test/screens/reader_screen_test.dart`、`test/screens/toc_bottom_sheet_test.dart`（只確認未回歸，不新增）

**Interfaces:**
- Consumes：Task 1 的 `TocNavigator.findCurrentPath(entries, progression, {currentSpineIndex})`；`extractChapterIndex(String?)`（`reader_screen.dart` 已 import `foliate_bridge_codec.dart`，3158 行已使用，若無則補 import）。
- Produces：私有 helper `List<TocEntry> _currentEpubTocPath()`，四處共用。

- [x] **Step 1: 新增 helper，並替換四處呼叫**

在 `_openToc()` 正上方新增：

```dart
  /// EPUB 目前章節路徑（epic-54 Issue 19）：同時傳入全書 progression 與
  /// spine index，後者讓開書當下的判定不受 progression 偏高／頂層章節
  /// progression 為 null 影響，見 `TocNavigator.findCurrentPath`。
  /// 開書極早期尚未收到位置回報（`_epubPositionInfo == null`）時，兩個參數
  /// 皆為 null，`findCurrentPath` 自然回傳空清單（不預設展開、不高亮）。
  List<TocEntry> _currentEpubTocPath() => TocNavigator.findCurrentPath(
        _tocEntries,
        _epubPositionInfo?.progression,
        currentSpineIndex: extractChapterIndex(_epubPositionInfo?.locatorJson),
      );
```

四處改法（每處三行→一行；`_currentChapterTitle` 與 `_buildFoliateHeaderText` 同理）：

```dart
    final currentPath = _currentEpubTocPath();
```

`_currentChapterTitle`（2272）原本是 `final currentPath = TocNavigator.findCurrentPath(_tocEntries, _epubPositionInfo?.progression);`，同樣換成 `_currentEpubTocPath()`。**注意：PDF 分支（`PdfTocNavigator`）一行都不要動。**

- [x] **Step 2: 靜態檢查與殘留搜尋**

```bash
flutter analyze
grep -n "TocNavigator.findCurrentPath" lib/screens/reader_screen.dart
```

Expected：analyze 乾淨；`grep` 只剩 `_currentEpubTocPath` 內那 1 處（`PdfTocNavigator` 的呼叫不含 `TocNavigator.` 前綴以外字串，若 grep 同時列出 `PdfTocNavigator.findCurrentPath` 兩處屬正常）。

- [x] **Step 3: 跑受影響的既有測試**

```bash
flutter test test/screens/reader_screen_test.dart test/screens/toc_bottom_sheet_test.dart test/reader/toc_navigator_test.dart
```

Expected：全過。若 `reader_screen_test` 有案例因開書當下章節判定改變而失敗，**先判斷是測試過期還是新缺陷**，不得直接改斷言；回報使用者決定（全域 CLAUDE.md 第 8 條）。

- [x] **Step 4: Commit**

```bash
git add lib/screens/reader_screen.dart
git commit -m "fix(epic-54): Issue 19 ReaderScreen 目前章節判定傳入 spine index" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：`epub_toc_test` 改回斷言「開書預設收合」並在 `TCL 14` 驗證

**Files:**
- Modify: `app/integration_test/epub_toc_test.dart`（約 131-139 行註解與 `TODO(Issue 19)`；154-170 行 `if (find.text('第一節')…)` 容錯分支）

**Interfaces:**
- Consumes：Task 1／2 的行為（開書在第一章時，第二章預設收合）。

- [x] **Step 1: 先在**未收緊**的測試上於真機觀察修復效果（紅綠對照的「綠」前置）**

向使用者確認可清除 `TCL 14` 的 App 資料後：

```bash
export MSYS_NO_PATHCONV=1
ADB=/c/Users/fycdc/AppData/Local/Android/Sdk/platform-tools/adb.exe
$ADB devices -l
$ADB shell pm clear cc.ugotit.elinkbook
cd /c/Users/fycdc/AI/elinkBook/app
flutter test integration_test/epub_toc_test.dart -d 3CEF42ECD491687
```

Expected：通過（容錯分支此時應**不會**進入，因為第二章已不預設展開；可在分支內暫加 `debugPrint` 確認，確認後移除）。

- [x] **Step 2: 收緊測試（先改斷言、再確認有咬力）**

把 131-139 行的「已知限制」註解與 `TODO(Issue 19)` 整段替換為：

```dart
    // epic-54 Issue 19 修復後：目前章節改以 spine index 判定，開書在第一章時
    // 第二章必須預設收合（保護「開書預設收合」，本測試曾於 Issue 18 為繞過
    // 已知缺陷而放寬，現已改回）。
```

並把 154-170 行的容錯分支（`if (find.text('第一節').evaluate().isNotEmpty) { … }`）整段刪除，在 `expandButton` 之後改為先斷言初始收合、再展開：

```dart
    // 開書預設只展開目前章節（第一章）；第二章的子節此時不得出現。
    expect(find.text('第一節'), findsNothing, reason: '開書在第一章，第二章應預設收合');
    expect(find.text('第二節'), findsNothing);
    await tester.tap(expandButton);
    await tester.pump();
    expect(find.text('第一節'), findsOneWidget);
    expect(find.text('第二節'), findsOneWidget);
```

（保留其後「再收合」若原本有的步驟；若原檔沒有則不新增，維持最小改動。）

- [x] **Step 3: 補「跳轉後判定跟著更新」斷言（Review Focus 5）**

在「點選第三章、`_pumpUntilProgressChanged` 之後」、檔尾 `expect(find.byKey(Key('reader_error_text'))…)` 之前，新增：

```dart
    // 跳到第三章後再開目錄：目前章節應為第三章，第二章子節不得展開
    // （驗證判定不只在開書當下正確，epic-54 Issue 19）。
    await _pumpUntilTocButtonEnabled(tester);
    await tester.tap(find.byKey(const Key('reader_chrome_toc_button')));
    await tester.pumpAndSettle();
    expect(find.byType(TocBottomSheet), findsOneWidget);
    expect(find.text('第一節'), findsNothing, reason: '跳到第三章後第二章應維持收合');
    expect(find.text('第二節'), findsNothing);
    // 第三章應被標示為目前章節（TocBottomSheet 以 ListTile.selected 表示）。
    final ch3Tile =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '第三章：結局'));
    expect(ch3Tile.selected, isTrue, reason: '跳轉後第三章應標示為目前章節');

    // 測試自行清理：關閉目錄，避免懸置的 Modal 影響 teardown 或後續案例。
    await tester.tap(find.byKey(const Key('toc_bottom_sheet_close_button')));
    await tester.pumpAndSettle();
    expect(find.byType(TocBottomSheet), findsNothing, reason: '目錄驗證完成後應正常關閉');
```

若 `tester.tap(find.text('第三章：結局'))` 後工具列已隱藏導致找不到 `reader_chrome_toc_button`，先沿用本檔既有的叫出工具列寫法（見檔內第一次開目錄前的步驟）；不要新增計時型等待。

- [x] **Step 4: 突變驗證（證明收緊後的測試會咬人）**

暫時把 `_currentEpubTocPath()` 內 `currentSpineIndex: …` 那行註解掉（等同回到修復前），在 `TCL 14` 跑：

```bash
flutter test integration_test/epub_toc_test.dart -d 3CEF42ECD491687
```

Expected：失敗於 `expect(find.text('第一節'), findsNothing, reason: '開書在第一章，第二章應預設收合')`；還原後再跑，Expected：通過（`+1`）。把兩次輸出摘要記入 `epic.md`。

- [x] **Step 5: 守衛腳本與提交**

```bash
node tool/check_integration_keys.js
node tool/check_l10n_hardcoded_strings.js
flutter analyze
git add integration_test/epub_toc_test.dart
git commit -m "test(epic-54): Issue 19 epub_toc_test 改回斷言開書預設收合並驗證跳轉後判定" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：三項皆乾淨／PASS。

---

### Task 4：完整驗證、文件同步與收尾

**Files:**
- Modify: `docs/epics/epic-54-architecture-optimization/epic.md`、`issues.md`（第 19 列狀態）、`docs/epics.md`（備註只寫「Issue 19 已完成」，不寫歷程）
- Modify: 本計畫檔（勾選 Step、補附錄）

- [x] **Step 1: 完整 `flutter test`（只此一次，背景執行）**

在 `app/` 下以 `run_in_background` 執行 `flutter test`。Expected：除 Issue 18 已記錄的既存失敗（`pdf_reader_view_filters` 加粗 debouncer，乾淨樹同樣失敗）外全過；若出現其他失敗，逐一判定是否為本 Issue 回歸。

- [x] **Step 2: 補 integration 回歸**

在 `TCL 14` 另跑與章節判定相關的檔案，確認無回歸：

```bash
flutter test integration_test/epub_toc_test.dart -d 3CEF42ECD491687
flutter test integration_test/notes_bookmark_test.dart -d 3CEF42ECD491687
flutter test integration_test/reader_header_footer_toggle_test.dart -d 3CEF42ECD491687
```

Expected：皆通過（`notes_bookmark_test` 涉及書籤章節名、`header_footer` 涉及頁首章節文字）。

- [x] **Step 3: 回寫文件**

- `epic.md`：新增「Issue 19 實作完成與真機驗證結果」段（根因、演算法取捨與使用者原話出處、突變驗證結果、斷言強度變化＝收緊）。
- `issues.md` 第 19 列與 `docs/epics.md` 備註的狀態更新，只在 PR 合併後於 `main` 進行（見下方「分支與提交方式」）。
- 第 18 列在 `epic.md` 的 `TODO(Issue 19)` 敘述加註「已於 Issue 19 還原」。
- **分支與提交方式**（比照 Issue 18 先例：實作紀錄隨功能分支、合併後的狀態同步才推 `main`）：
  - 功能分支（`epic-54/issue-19-toc-current-chapter`）：`epic.md` 的實作結果段、本計畫的 checkbox 勾選與附錄、`TODO(Issue 19)` 加註，與程式一起 commit，隨 PR 合併。
  - PR 合併後：`git switch main && git pull`，再把 `issues.md` 第 19 列改 `🟢 已合併（PR #N）`、`docs/epics.md` 備註與 `epic.md` 的「Issue 19 已合併」一行，直接 commit＋push `main`（不開 PR）。
  - 不要在功能分支上用 stash／切分支來搬文件。`issues.md` 第 19 列在功能分支上先維持 `⚪ 待處理`，不提前改 `🟡`。

- [x] **Step 4: 發 PR 前確認並請求程式審查**

```bash
git log --oneline main..HEAD
flutter analyze
```

審查者先產出報告（`reviews/review-code-issue-19.md`，gitignore），不得直接改程式；處理審查後才發 PR（由使用者合併）。

---

## 附錄 A：使用者決定紀錄（Task 0 Step 2 取得後填入原話）

- Task 0 Step 2（演算法取捨，A／B／C）：使用者於 2026-10-07 對話回答原話：`B`（採本計畫方案：先比 spine index、同 spine 內才比 progression）。
- Task 0 Step 2（本次執行確認）：使用者於 2026-10-07 對話回答原話：`B`（採計畫方案：先比 spine index，同 spine 內才比 progression）。

## Self-Review 結果

- **Spec 涵蓋**：issues.md 第 19 列的 (a) 頂層 progression 為 null → Task 1「頂層…靠 spine index 被選中」；(b) fraction 偏高 → Task 1「0.554 仍判第一章」；「修復後須把 `epub_toc_test` 改回斷言初始收合」→ Task 3。修復方向「補 section base 近似 progression」與「改用 CFI／spine index」二選一，本計畫採後者並於 Task 0 讓使用者確認。
- **佔位掃描**：無 TBD。
- **型別一致**：`findCurrentPath(..., {int? currentSpineIndex})`、`_currentEpubTocPath()`、`extractChapterIndex` 在 Task 1／2 一致。
- **Review Focus**：5 項皆對應到 Task 1／2／3 的具體測試或檢視步驟。
