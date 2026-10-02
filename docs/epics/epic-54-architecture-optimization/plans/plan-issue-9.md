# Issue 9：跳轉保護不被「同位置重複回報」提早解除 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 修正缺陷——帶跳轉目標（搜尋結果、書籤）開書時，Foliate 重排產生的「位置相同的重複回報」不得讓 `ReadingPositionSaver` 判定使用者已離開跳轉目標；只有 cfi 或 index 真的改變才算。

**Architecture：** 把目前 `ReadingSession` 私有的「位置鍵」（只取 `cfi｜index`、忽略會抖動的 fraction，解析失敗退回整段字串）提升成 `EpubPositionInfo.positionKey` getter，讓「閱讀活動判定」（session）與「跳轉保護的已重新定位旗標」（saver）共用同一條比較規則，不再各存一份。`ReadingPositionSaver.onEpubLocated` 改為「與上一筆的 `positionKey` 不同」才把 `_hasRelocatedEpub` 設為 true；`_epubInfo` 仍每次都更新成最新一筆（儲存時要用最新的 fraction／progression）。PDF 路徑不動。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`。缺陷描述見 `docs/epics/epic-54-architecture-optimization/epic.md`「待處理缺陷（Issue 9）」；詞彙見 `CONTEXT.md`「位置儲存規則」「閱讀會話」；前置實作見 `plans/plan-issue-7.md`（saver）與 `plans/plan-issue-8.md`（session）。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **只改「已重新定位」旗標的成立條件**：位置寫入與統計 flush 仍都不 await；`save()` 的格式分派、`progression ?? initialProgress` 回退、`paused` 不觸發 Checkpoint、離開五步順序，一律不動。
- **閱讀活動判定行為零變化**：session 改用 `positionKey` 後，既有 `reading_session_test.dart` 全部案例必須不改而通過（含「cfi 無法解析時退回整段字串比較」）。
- **旗標仍是單向轉換**（false → true）：位置 A→B→A 之後旗標維持 true（使用者確實移動過）。
- **範圍外**：不動 PDF 路徑（頁碼回報不會無故重複）；不動 `ReaderScreen`（它只轉發回報）；不新增 `ReaderScreen` 建構參數；不動 `main.js`／Foliate 端為何重複回報。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 6 分鐘，用 `run_in_background`，**且必須在 `app/` 目錄下執行**）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：用 Bash 工具（Git Bash）；`python` 不可用來編輯檔案；多數原始檔是 CRLF，Edit 的定位字串不要含換行。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：計畫先審查再動手；程式審查先出報告（存於 `reviews/`，gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。

## 已決定／需使用者確認的前提

`epic.md` 要求動手前先決定「要不要先用真機日誌確認重複回報確實發生」。本計畫的假設是**不先做真機確認，直接修**，理由：(1) 「同一 cfi 的 fraction 會來回微幅抖動、同位置重複回報」已由閱讀活動判定的真機日誌實證（見 `reading_session.dart` `onEpubLocated` 註解）；(2) 修法只是讓旗標更保守（需要位置真的改變才成立），最壞情況是少數「使用者其實移動了但回到原位」的情形不受影響（旗標單向，A→B→A 仍成立），不會造成多存或丟失既有行為；(3) 修正由單元測試守住，不依賴真機。若審查計畫時使用者希望先取得真機日誌，須在 Task 1 之前另行處理。

## Review Focus

最可能咬到使用者的情況（依可能性排序），每條都有對應測試：

1. **帶跳轉目標開書，Foliate 重排派發同位置重複回報，使用者什麼都沒做就離開，卻把跳轉落點存成新進度（本缺陷本身）。** → Task 1 測「同 cfi＋index、fraction／progression 抖動的重複回報，離開不儲存」；Task 2 在 session 層端到端再測一次。
2. **修過頭：使用者真的翻頁或跳轉後卻仍不儲存，進度停在舊位置。** → Task 1 測「cfi 改變後儲存、且存的是最新一筆（含最新 progression）」「index 改變但 cfi 相同也算移動」「A→B→A 仍算已移動」。
3. **重複回報之間 progression 被抖動值改寫，儲存時用到舊值。** → Task 1 測「重複回報後（旗標已因真移動成立）仍以最後一筆的 locatorJson 與 progression 儲存」。
4. **locatorJson 不是合法 JSON（或沒有 cfi／index 欄位）時誤判。** → Task 1 測「無法解析時退回整段字串比較」：字串相同不算移動、不同才算；`'{}'` 與 `'{"cfi":"a"}'` 視為不同位置（沿用既有鍵語意）。
5. **一般開書（沒有跳轉目標）被新規則影響。** → Task 1 測「沒有跳轉目標時第一次回報就儲存，與重複回報無關」。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/epub_position_info.dart` | 修改 | 新增 `String get positionKey`（cfi＋index，忽略 fraction；解析失敗退回整段 `locatorJson`） |
| `app/test/reader/epub_position_info_test.dart` | 新增 | `positionKey` 規則單元測試 |
| `app/lib/reader/reading_position_saver.dart` | 修改 | `onEpubLocated`：只有 `positionKey` 改變才設 `_hasRelocatedEpub` |
| `app/test/reader/reading_position_saver_test.dart` | 修改 | 新增「同位置重複回報」等案例 |
| `app/lib/reader/reading_session.dart` | 修改 | 刪私有 `_locatorPositionKey` 與 `dart:convert`，改用 `positionKey` |
| `app/test/reader/reading_session_test.dart` | 修改 | 新增 session 層端到端案例 |
| `CONTEXT.md` | 修改 | 「位置儲存規則」補上「重新定位＝位置真的改變，重複回報不算」 |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 開發記錄、狀態 |

---

### Task 0：提交計畫、建立 worktree

**Files：**
- Commit：本計畫檔與 `issues.md` 狀態更新（在 `main` 上，純文件）
- 建立 worktree：`.worktrees/epic-54-issue-9-relocate-dedup`（`.worktrees/` 已 gitignore）

**Interfaces：**
- Consumes：無。
- Produces：分支 `epic-54/issue-9-relocate-dedup`，後續 Task 都在這個 worktree 的 `app/` 下執行。

- [ ] **Step 1：在 `main` 提交計畫**

先把 `issues.md` 第 9 列狀態由「⚪ 待處理（見 `epic.md`）」改為「🟡 進行中（計畫已寫）」，然後：

（在儲存庫根目錄執行，不需要 `cd`。）

```bash
git add docs/epics/epic-54-architecture-optimization/plans/plan-issue-9.md docs/epics/epic-54-architecture-optimization/issues.md
git commit -m "docs(epic-54): Issue 9 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2：建立 worktree 並安裝依賴**

```bash
git worktree add .worktrees/epic-54-issue-9-relocate-dedup -b epic-54/issue-9-relocate-dedup
cd .worktrees/epic-54-issue-9-relocate-dedup/app && flutter pub get
```

預期：`Got dependencies!`。

- [ ] **Step 3：確認基準測試通過並記下數字**

```bash
flutter test test/reader/reading_position_saver_test.dart test/reader/reading_session_test.dart test/screens/reader_screen_test.dart
```

預期：全數通過。記下通過數（Task 2 結束時應為此數加上新增案例數）。

---

### Task 1：`positionKey` 與 `ReadingPositionSaver` 修正

**Files：**
- Modify：`app/lib/reader/epub_position_info.dart`（`EpubPositionInfo` 類別內、`displayTotalPages` 之後；檔頭加 `import 'dart:convert';`）
- Modify：`app/lib/reader/reading_position_saver.dart:49-52`
- Create：`app/test/reader/epub_position_info_test.dart`
- Modify：`app/test/reader/reading_position_saver_test.dart`（在「有跳轉目標」group 內與「沒有跳轉目標」group 內新增案例）

**Interfaces：**
- Consumes：`EpubPositionInfo.locatorJson`（`{"cfi":...,"index":...,"fraction":...}`）。
- Produces（Task 2 依賴）：`String get positionKey`——合法 JSON 物件時回傳 `'${map['cfi']}|${map['index']}'`；非物件或解析失敗時回傳整段 `locatorJson`。語意與現有 `ReadingSession._locatorPositionKey` 逐字相同。

- [ ] **Step 1：寫 `positionKey` 的失敗測試**

建立 `app/test/reader/epub_position_info_test.dart`：

```dart
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('positionKey：只代表「位置」，忽略會抖動的 fraction', () {
    test('同 cfi 與 index、fraction 不同，鍵相同', () {
      const a = EpubPositionInfo(
        locatorJson: '{"cfi":"x","index":2,"fraction":0.10}',
      );
      const b = EpubPositionInfo(
        locatorJson: '{"cfi":"x","index":2,"fraction":0.11}',
      );
      expect(a.positionKey, b.positionKey);
    });

    test('cfi 不同，鍵不同', () {
      const a = EpubPositionInfo(locatorJson: '{"cfi":"x","index":2}');
      const b = EpubPositionInfo(locatorJson: '{"cfi":"y","index":2}');
      expect(a.positionKey, isNot(b.positionKey));
    });

    test('cfi 相同但 index 不同，鍵不同', () {
      const a = EpubPositionInfo(locatorJson: '{"cfi":"x","index":2}');
      const b = EpubPositionInfo(locatorJson: '{"cfi":"x","index":3}');
      expect(a.positionKey, isNot(b.positionKey));
    });

    test('不是合法 JSON 時退回整段字串（字串相同鍵相同、不同鍵不同）', () {
      const a = EpubPositionInfo(locatorJson: 'not json');
      const same = EpubPositionInfo(locatorJson: 'not json');
      const other = EpubPositionInfo(locatorJson: 'other');
      expect(a.positionKey, 'not json');
      expect(a.positionKey, same.positionKey);
      expect(a.positionKey, isNot(other.positionKey));
    });

    test('合法 JSON 但不是物件（例如陣列）時退回整段字串', () {
      const a = EpubPositionInfo(locatorJson: '[1,2]');
      expect(a.positionKey, '[1,2]');
    });

    test('locatorJson 為空字串時退回空字串，不拋例外', () {
      const a = EpubPositionInfo(locatorJson: '');
      expect(a.positionKey, '');
    });

    test('locatorJson 為空物件時鍵為 null|null，且彼此相同', () {
      const a = EpubPositionInfo(locatorJson: '{}');
      const b = EpubPositionInfo(locatorJson: '{}');
      expect(a.positionKey, 'null|null');
      expect(a.positionKey, b.positionKey);
    });
  });
}
```

- [ ] **Step 2：確認失敗**

Run：`flutter test test/reader/epub_position_info_test.dart`
Expected：編譯失敗，`The getter 'positionKey' isn't defined for the class 'EpubPositionInfo'`。

- [ ] **Step 3：實作 `positionKey`**

在 `epub_position_info.dart` 檔案最上方加 `import 'dart:convert';`，並在 `displayTotalPages` getter 之後加入：

```dart
  /// 代表「位置」的比較鍵：取 [locatorJson] 中的 cfi 與 index，忽略會因重排而
  /// 來回微幅抖動的 fraction（真機日誌實證）。解析失敗或不是 JSON 物件時退回
  /// 整段字串。用來判斷兩次回報是不是「同一個位置的重複回報」。
  String get positionKey {
    try {
      final map = jsonDecode(locatorJson);
      if (map is Map) return '${map['cfi']}|${map['index']}';
    } catch (_) {}
    return locatorJson;
  }
```

- [ ] **Step 4：確認 `positionKey` 測試通過**

Run：`flutter test test/reader/epub_position_info_test.dart`
Expected：7 個全數 PASS。

- [ ] **Step 5：寫 saver 的失敗測試**

在 `reading_position_saver_test.dart` 的 `group('有跳轉目標（例如從搜尋結果開書）'` 內（最後一個 test 之後）加入：

```dart
    test('Foliate：同位置重複回報（fraction 抖動）不算重新定位，離開不儲存', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"j","index":1,"fraction":0.20}', progression: 0.2));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"j","index":1,"fraction":0.21}', progression: 0.21));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"j","index":1,"fraction":0.20}', progression: 0.2));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('Foliate：locatorJson 完全相同的重複回報也不算重新定位', () {
      final saver = buildSaver(hasJumpTarget: true);
      const info = EpubPositionInfo(locatorJson: 'opaque', progression: 0.2);
      saver.onEpubLocated(info);
      saver.onEpubLocated(info);
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('Foliate：cfi 相同但 index 不同算已移動，儲存', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"j","index":1}', progression: 0.2));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"j","index":2}', progression: 0.3));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, hasLength(1));
    });

    test('Foliate：重複回報夾雜真移動，儲存最後一筆的定位點與進度', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"j","index":1,"fraction":0.20}', progression: 0.2));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"k","index":1,"fraction":0.30}', progression: 0.3));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"k","index":1,"fraction":0.31}', progression: 0.31));
      saver.save(BookFormat.epub);
      expect(
        prefs.savedReadingPositionCalls.single.value,
        const ReadingPosition(
          epubLocatorJson: '{"cfi":"k","index":1,"fraction":0.31}',
          progress: 0.31,
        ),
      );
    });

    test('Foliate：A→B→A 仍算已移動（旗標單向）', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"a","index":0}', progression: 0.1));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"b","index":0}', progression: 0.2));
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"a","index":0}', progression: 0.1));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, hasLength(1));
    });

    test('Foliate：locatorJson 無法解析時退回整段字串比較（不同才算移動）', () {
      final saver = buildSaver(hasJumpTarget: true);
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: 'p1', progression: 0.1));
      saver.onEpubLocated(const EpubPositionInfo(locatorJson: 'p1', progression: 0.1));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);

      saver.onEpubLocated(const EpubPositionInfo(locatorJson: 'p2', progression: 0.2));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, hasLength(1));
    });
```

並在 `group('沒有跳轉目標（一般開書）'` 內加入：

```dart
    test('Foliate：第一次回報就可以儲存，不受重複回報規則影響', () {
      final saver = buildSaver();
      saver.onEpubLocated(const EpubPositionInfo(
          locatorJson: '{"cfi":"a","index":0}', progression: 0.4));
      saver.save(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, hasLength(1));
    });
```

- [ ] **Step 6：確認新案例中正確的幾個失敗**

Run：`flutter test test/reader/reading_position_saver_test.dart`
Expected：「fraction 抖動不算重新定位」「locatorJson 完全相同」「無法解析時退回整段字串比較」三個 FAIL（目前第二次回報就把旗標設為 true，所以會多存）；其餘新案例（index 不同、夾雜真移動、A→B→A、一般開書）本來就 PASS，是防修過頭的守衛。

- [ ] **Step 7：修正 saver**

`reading_position_saver.dart` 的 `onEpubLocated` 改為：

```dart
  void onEpubLocated(EpubPositionInfo info) {
    // 只有位置真的改變才算「重新定位」：Foliate 開書後套用樣式重排、圖片／字型
    // 載入後重新對齊錨點，會派發位置相同的重複回報，不是使用者離開了跳轉目標。
    // 旗標只在有跳轉目標、且尚未成立時才有意義，其餘情況略過比較（省下每次
    // 翻頁的 JSON 解析）；_epubInfo 恆常更新，儲存時才有最新的進度。
    if (hasJumpTarget && !_hasRelocatedEpub) {
      final previous = _epubInfo;
      if (previous != null && previous.positionKey != info.positionKey) {
        _hasRelocatedEpub = true;
      }
    }
    _epubInfo = info;
  }
```

同檔 `_hasRelocatedPdf`／`_hasRelocatedEpub` 上方的註解，把「某格式第二次（含）以後的位置回報才代表……」改為：「PDF 為第二次（含）以後的頁碼回報；Foliate 為『位置鍵與上一筆不同』的回報（重複回報不算，見 [EpubPositionInfo.positionKey]）。」其餘文字保留。

- [ ] **Step 8：確認通過**

Run：`flutter test test/reader/reading_position_saver_test.dart test/reader/epub_position_info_test.dart`
Expected：全數 PASS（saver 原有 16 個＋新增 7 個；`epub_position_info_test` 7 個）。

- [ ] **Step 9：變異驗證（確認測試真的守得住）**

暫時把 `previous.positionKey != info.positionKey` 改成 `true`（等於舊行為），跑 `flutter test test/reader/reading_position_saver_test.dart`，預期 Step 6 列的 3 個案例 FAIL；確認後還原。

- [ ] **Step 10：Commit**

```bash
git add app/lib/reader/epub_position_info.dart app/lib/reader/reading_position_saver.dart app/test/reader/epub_position_info_test.dart app/test/reader/reading_position_saver_test.dart
git commit -m "fix(reader): 跳轉保護不被同位置重複回報提早解除（epic-54 Issue 9）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：`ReadingSession` 共用 `positionKey`、端到端測試、文件與收尾

**Files：**
- Modify：`app/lib/reader/reading_session.dart:2,89-98,159-167`
- Modify：`app/test/reader/reading_session_test.dart`（`hasJumpTarget: true` 案例附近，約第 261 行之後）
- Modify：`CONTEXT.md`「位置儲存規則」段
- Modify：`docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md`

**Interfaces：**
- Consumes：Task 1 的 `EpubPositionInfo.positionKey`。
- Produces：無（最後一個 Task）。

- [ ] **Step 1：新增 session 層端到端回歸守衛測試**（Task 1 已修 saver，這兩個案例寫完即通過，不是 Red 階段）

在 `reading_session_test.dart` 的「有跳轉目標：只有首次回報就離開，不儲存」案例之後加入：

```dart
    test('有跳轉目標：Foliate 同位置重複回報（fraction 抖動）就離開，不儲存', () {
      final session = build(hasJumpTarget: true)..start();
      session.onPrefsLoaded(initialProgress: 0.5);
      session.onEpubLocated(_loc('j', fraction: 0.20));
      session.onEpubLocated(_loc('j', fraction: 0.21));
      session.onEpubLocated(_loc('j', fraction: 0.20));
      session.close(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls, isEmpty);
    });

    test('有跳轉目標：Foliate cfi 真的改變後離開，儲存最新位置', () {
      final session = build(hasJumpTarget: true)..start();
      session.onPrefsLoaded(initialProgress: 0.5);
      session.onEpubLocated(_loc('j', fraction: 0.20));
      session.onEpubLocated(_loc('k', fraction: 0.30));
      session.close(BookFormat.epub);
      expect(prefs.savedReadingPositionCalls.single.value.epubLocatorJson,
          contains('"cfi":"k"'));
    });
```

- [ ] **Step 2：確認端到端測試通過（驗證 Task 1 的 saver 修正在 session 層已生效）**

Run：`flutter test test/reader/reading_session_test.dart`
Expected：全數 PASS（包含新增 2 案例，因 session 轉發給 saver，Task 1 的修正已生效）。

- [ ] **Step 3：session 改用 `positionKey`，刪除重複實作**

`reading_session.dart`：
- 刪除第 2 行 `import 'dart:convert';`（刪後確認檔內已無其他 `jsonDecode` 使用）。
- `onEpubLocated` 內的比較改為：

```dart
    final previous = _lastEpubInfo;
    if (previous != null && previous.positionKey != info.positionKey) {
      _stats?.recordActivity();
    }
```

- 刪除檔尾私有 `_locatorPositionKey` 方法與其註解；`onEpubLocated` 方法上方註解中「只比 cfi 與 index、忽略 fraction——真機日誌實證……」保留，但在句末補一句「（比較規則見 `EpubPositionInfo.positionKey`，與位置儲存器共用）」。

- [ ] **Step 4：確認 session 與相關測試通過**

```bash
flutter test test/reader/reading_session_test.dart test/reader/reading_position_saver_test.dart test/reader/epub_position_info_test.dart test/screens/reader_screen_test.dart test/screens/reader_screen_stats_activity_test.dart
flutter analyze
```

Expected：全數 PASS；`No issues found!`。`reading_session_test.dart` 原有案例（含「cfi 無法解析時退回整段字串」）不得修改而通過。

- [ ] **Step 5：更新 `CONTEXT.md`**

在「位置儲存規則」段「有『跳轉目標』的開書……在使用者真正移動閱讀位置之前不儲存」之後補一句：「『真正移動』指位置鍵（Foliate 的 cfi 與 index，忽略進度小數；PDF 為頁碼）與開書後第一次回報不同；重排或資源載入造成的同位置重複回報不算移動。」

- [ ] **Step 6：全套測試與檢查（唯一一次）**

```bash
node tool/check_l10n_hardcoded_strings.js
flutter test
```

`flutter test` 以 `run_in_background` 在 `app/` 目錄下執行。預期：全數通過，數量為 Issue 8 合併基準 3391 ＋ 新增案例（`epub_position_info_test` 7 ＋ saver 7 ＋ session 2 ＝ 16）＝ 3407 通過、1 略過、0 失敗；兩行 PASS。

- [ ] **Step 7：更新文件並提交**

- `epic.md`：在最後新增「**日期 Issue 9 實作完成**」段，記錄修法（`positionKey` 共用）、新增測試數、變異驗證結果、全套測試數字、行為變動（旗標成立條件變嚴格，僅影響帶跳轉目標的 Foliate 開書）、待真機確認（可選：帶搜尋跳轉開書後不操作離開，確認進度未被覆蓋）。
- `issues.md` 第 9 列狀態改為「🟡 實作完成，待程式審查與發 PR」。
- `docs/epics.md` Epic 54 備註改為「Issue 9 實作完成」（維持精簡，不寫歷程）。

```bash
git add CONTEXT.md app/lib/reader/reading_session.dart app/test/reader/reading_session_test.dart docs/epics/epic-54-architecture-optimization/ docs/epics.md
git commit -m "refactor(reader): 閱讀會話共用 positionKey，補 Issue 9 端到端測試與文件

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-Review

- **範圍對照**：`epic.md` 缺陷描述的修正方向（旗標只在位置真的改變時成立、沿用 cfi＋index 位置鍵）→ Task 1；測試以 saver 單元測試直接守住 → Task 1 Step 5；「動手前先決定是否真機確認」→「已決定／需使用者確認的前提」。
- **型別一致**：`positionKey`（`String` getter，`EpubPositionInfo`）在 Task 1 定義、Task 2 使用；saver 的 `_hasRelocatedEpub`、`_epubInfo` 名稱與現有程式碼一致；測試輔助 `_loc(cfi, {index, fraction})`、`build(hasJumpTarget:)`、`prefs.savedReadingPositionCalls` 皆為現有檔案中已存在者。
- **預計測試數**：Task 1 Step 8 的 saver「原有 16」係指 Issue 7 記載的 16 個單元測試，實際數字以 Task 0 Step 3 基準為準，執行時以實測為準。
- **無占位**：所有步驟含實際程式碼或指令。
