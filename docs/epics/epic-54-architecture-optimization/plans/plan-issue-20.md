# Issue 20：EPUB 目錄「目前章節」同一 spine 多錨點精確判定——轉發 foliate `tocItem` 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:executing-plans` 逐 Task 執行本計畫（或 `superpowers:subagent-driven-development`，由使用者在計畫審查後指定）。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 讓 EPUB 目錄「目前章節」判定在**同一個 spine 內有多個錨點**時，直接採用 foliate 以 live DOM `Range.comparePoint` 算出的目前目錄項（`relocate` 事件的 `tocItem`），取代對全書 progression 比大小。

**Architecture：** foliate `view.js` 每次 `relocate` 都已算出 `e.detail.tocItem`（`progress.js TOCProgress`，DOM 級命中、零浮點誤差；目錄項帶有 `assignIDs` 以 DFS 前序指派的唯一整數 `id`）。`main.js` 做兩件事：(1) `buildTocEntry` 為每個目錄節點多輸出 `tocId: item.id`；(2) `onLocatorChanged` 第 2 參數 `position` 多帶 `tocItemId: e.detail.tocItem?.id`。Dart 端 `TocEntry.tocId`／`EpubPositionInfo.tocItemId` 接收，`TocNavigator.findCurrentPath` 新增 `currentTocItemId`：**有 id 且在樹中找得到節點就直接回傳該節點的祖先路徑**，否則退回 Issue 19 的 spine index 規則（再退回舊 progression 規則）。**不改釘定 vendor 檔、不改 `locatorJson`（第 1 參數）。**

**Tech Stack：** Flutter／Dart、`flutter_test`、`integration_test`、foliate-js（`main.js`）、`adb`、Node（既有守衛腳本）。指令一律在 `app/` 目錄下執行（除非另有標明），以 **Bash 工具（Git Bash）** 為準。

**Spec：** 沒有獨立 `spec.md`。依據：`docs/epics/epic-54-architecture-optimization/issues.md` 第 20 列、`reviews/review-issue-20.md`（工單審查，gitignore，本機才有）、`epic.md`「Issue 20 決定推動（方案 B）」。前置：`plans/plan-issue-19.md`（已合併，PR #334）。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **`locatorJson` 凍結**：`onLocatorChanged` 第 1 參數 `JSON.stringify({ cfi, index, fraction })` 一個字元都不能改（會持久化到 SQLite 並跨裝置同步）。新欄位只能放第 2 參數 `position`。
- **不改 vendor**：`app/android/app/src/main/assets/foliate/` 內 `view.js`／`progress.js` 等釘定檔不動（ADR 0011）；只改 `main.js` 與 Dart。
- **向下相容**：`TocNavigator.findCurrentPath` 缺 `currentTocItemId` 時行為與 Issue 19 **逐案相同**（`test/reader/toc_navigator_test.dart` 既有 15 案——舊 6 案＋Issue 19 新增 9 案——不得修改、不得放寬）。`PdfTocNavigator` 不在範圍。
- **首個 relocate 之前**（`_epubPositionInfo == null`）：維持「回傳空清單、不展開不高亮」，不得拋例外。
- **不放寬測試**：不得為了通過而刪斷言／加 `skip`／弱化 matcher。
- **JS 的 `0` 陷阱**：`tocItem.id` 的第一個項目 id 為 `0`（falsy）。JS 一律用 `?.`／`??`，Dart 一律判 `!= null`，**不得用 `||`／`if (id)`／`id ?: …` 判斷有無**。
- **真機**：`TCL 14`（序號 `3CEF42ECD491687`，Android 15）。結果只宣稱此裝置通過。執行前須向使用者確認可清除該裝置上 `cc.ugotit.elinkbook` 資料。`adb` 路徑 `/c/Users/fycdc/AppData/Local/Android/Sdk/platform-tools/adb.exe`（Git Bash 先 `export MSYS_NO_PATHCONV=1`）。本計畫所有 shell 指令以 Bash 工具（Git Bash）為準；若改在 PowerShell 執行，adb 等效寫法為 `$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"; & $adb devices -l; & $adb shell pm clear cc.ugotit.elinkbook`（PowerShell 不需 `MSYS_NO_PATHCONV`），搜尋指令改用 `git grep -n`。
- **測試範圍**（`CLAUDE.md`）：單一 Task 只跑異動觸及的測試；完整 `flutter test` 只在最後一個 Task 跑一次（`run_in_background`，在 `app/` 下）。
- **提交前**：`flutter analyze` 必須 "No issues found!"；改了 `integration_test/` 後跑 `node tool/check_integration_keys.js`；改了畫面字串或測試後跑 `node tool/check_l10n_hardcoded_strings.js`；改了 `main.js` 後跑 `node tool/check_foliate_es_compat.js`。
- **Windows 環境**：多數原始檔是 CRLF，`Edit` 定位字串不要含換行。提交一律明確路徑 `git add`。Commit 結尾須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：本計畫先審查再動手（審查者先出報告存 `reviews/`，不直接改計畫）；程式審查同樣先出報告、不直接改程式。Epic 54 進度同步為純文件，直接 commit＋push `main`（不開 PR）；程式變更走分支＋PR。

## 已查證的事實（撰寫計畫時對照原始碼所得，執行者開工前須再確認一次）

| 項目 | 事實 | 出處 |
|---|---|---|
| `tocItem` 來源 | `#onRelocate` 內 `this.#tocProgress?.getProgress(index, range)`，放入 `lastLocation` 後以 `relocate` 事件 detail 派發 | `foliate/view.js:347-353` |
| `tocItem` 判定 | 同 spine 多項目時逐一取錨點元素，`range.comparePoint(el, 0) > 0`（錨點在可視範圍起點之後）→ 回傳前一項；全部通過回傳最後一項；該 spine 無目錄項時回傳 `prev`（前一個 spine 的最後項）；`this.ids` 未初始化回傳 `undefined`；查無回傳 `null` | `foliate/progress.js:38-55` |
| 項目 `id` | `TOCProgress.init` 先 `assignIDs(toc)`：DFS 前序、從 `0` 起遞增，**就地**寫到 `book.toc` 項目物件上；`init` 發生在 `view.open()` 內，早於 `getTableOfContents()` | `foliate/progress.js:1-10,19-21`、`view.js:249-256` |
| `buildTocEntry` 走訪順序 | 遞迴 `item.subitems`，與 `assignIDs` 同為 DFS 前序；傳入的 `item` 就是 `view.book.toc` 內同一批物件，故 `item.id` 可直接讀 | `main.js:720-758,772-778` |
| CBZ | `book.toc` 在 `view.open()` 前由 `main.js` 組出，同樣會被 `assignIDs` 指派 id | `main.js:1542-1547` |
| `onLocatorChanged` 契約 | 第 1 參數 `locatorJson` 凍結；第 2 參數 `position` 為具名 JSON 物件（`fraction`／`locationIndex`／`locationTotal`／`visualPageIndex`／`visualTotalPages`） | `main.js:1122-1166` |
| Dart 解析 | `parseLocatorChanged(List<dynamic>)` 解析 `args[1]` 為 `Map<String,dynamic>`，缺欄位皆回 `null` | `lib/reader/foliate_bridge_codec.dart:87-107` |
| 目錄節點 | `TocEntry.fromWire` 目前不讀 `tocId`；`==` 刻意維持物件識別 | `lib/reader/toc_entry.dart` |
| 目前章節呼叫端 | 4 處呼叫點皆已收斂到 `_currentEpubTocPath()`（`reader_screen.dart:1340`），只需改這一處 | `lib/screens/reader_screen.dart:1340,1347,1475,2276,3012` |
| 現有 fixture 缺口 | `sample_multi_chapter.epub` 是一章一 spine（第二章的兩子節在同一個 `chapter2.xhtml`，但全書有多 spine），無法排除「靠 spine index 就答對」；需要**單一 spine 內多錨點**的書 | `test/fixtures/sample_multi_chapter.epub` |
| 工具 | Git Bash 無 `zip`／`7z`／`python`；EPUB fixture 用 PowerShell `System.IO.Compression` 產生 | 環境 |

## 演算法（Task 2 實作對象）

`findCurrentPath(entries, currentProgression, {int? currentSpineIndex, int? currentTocItemId})`：

```
若 progression、spineIndex、tocItemId 三者皆為 null → 回空清單（與現況同）
若 currentTocItemId != null：
    在樹中 DFS 找 node.tocId == currentTocItemId 的節點
    找到 → 回傳「根到該節點」的祖先路徑（含自身），結束
    找不到（書本目錄與回報不一致，或節點缺 tocId）→ 繼續往下
否則／繼續：沿用 Issue 19 的 spine index 優先規則（程式不變）
```

「`tocItem` 為 `prev`（目前 spine 沒有目錄項，回報的是前一個 spine 的最後項）」天然正確：該項仍在樹中，路徑即為「剛通過的章節」。

## Review Focus

最可能咬到使用者的情況，依可能性排序：

1. **`tocItem.id === 0`（書中第一個目錄項）被當成「沒有 id」**：開書在第一章、第一個項目 id 為 0，若用 falsy 判斷會整個退回舊規則，修了等於沒修。→ Task 1 codec 測試「`tocItemId: 0` 要保留為 0」、Task 2 navigator 測試「`currentTocItemId: 0` 命中第一個節點」。
2. **`tocItem` 為 `null`／`undefined`（書無目錄、位置落在第一個目錄項之前、FXL 無 range）**：不得拋例外，須退回 Issue 19 規則。→ Task 1 測試「`tocItemId` 缺席／null 為 null」、Task 2 測試「id 為 null 行為不變」。
3. **回報的 id 在 Dart 目錄樹中找不到**（目錄載入尚未完成、書本目錄為空、id 過期）：不得空白或拋例外，須退回 spine index 規則。→ Task 2 測試「id 查無節點退回 spine 規則」。
4. **目前 spine 沒有任何目錄項（`tocItem` 為前一 spine 的最後項）**：路徑應是那個前章節點，不是空清單。→ Task 2 測試「回傳前章節點的完整祖先路徑」。
5. **`locatorJson` 被污染**：新欄位不得出現在第 1 參數，否則跨裝置同步與書籤還原的格式會變。→ Task 1 測試「`locatorJson` 原樣不變、不含 `tocItemId`」。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/toc_entry.dart` | 修改 | `TocEntry` 新增 `final int? tocId`；`fromWire` 讀 `tocId` |
| `app/lib/reader/epub_position_info.dart` | 修改 | `EpubPositionInfo` 新增 `final int? tocItemId`（含 `==`／`hashCode`／`toString`） |
| `app/lib/reader/foliate_bridge_codec.dart` | 修改 | `parseLocatorChanged` 讀 `position['tocItemId']` |
| `app/lib/reader/toc_navigator.dart` | 修改 | `findCurrentPath` 新增 `currentTocItemId` 優先判定 |
| `app/android/app/src/main/assets/foliate/main.js` | 修改 | `buildTocEntry` 輸出 `tocId`；`onLocatorChanged` 的 `position` 帶 `tocItemId` |
| `app/lib/screens/reader_screen.dart` | 修改 | `_currentEpubTocPath()` 傳入 `currentTocItemId` |
| `app/test/reader/toc_entry_test.dart`、`epub_position_info_test.dart`、`foliate_bridge_codec_test.dart`、`toc_navigator_test.dart` | 修改（只新增案例） | 單元測試 |
| `app/test/fixtures/sample_single_spine_multi_anchor.epub` | 新增 | 單一 spine、三個目錄錨點的合成 EPUB |
| `app/pubspec.yaml` | 修改 | 宣告新 fixture asset |
| `app/integration_test/epub_toc_test.dart` | 修改（新增第二個 `testWidgets`） | 真機驗證同 spine 多錨點 |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 結果與狀態（Task 5） |

---

### Task 0：確認前提並建立分支

**Files:** 無程式修改。

- [x] **Step 1: 再確認事實**

```bash
cd /c/Users/fycdc/AI/elinkBook/app
git status --short
git log --oneline -3
grep -n "assignIDs(toc)" android/app/src/main/assets/foliate/progress.js
grep -n "const tocItem = this.#tocProgress" android/app/src/main/assets/foliate/view.js
grep -n "_currentEpubTocPath" lib/screens/reader_screen.dart
grep -n "currentSpineIndex" lib/reader/toc_navigator.dart
```

Expected：工作樹乾淨；`HEAD` 含 Issue 19 合併（PR #334）；`assignIDs(toc)` 與 `const tocItem` 各 1 處；`_currentEpubTocPath` 共 5 處（定義＋4 呼叫）；`toc_navigator.dart` 已有 `currentSpineIndex`。任何一項不符，先停下回報。

- [x] **Step 2: 建立分支**

```bash
git switch -c epic-54/issue-20-toc-tocitem-forward
```

---

### Task 1：資料契約——`TocEntry.tocId`、`EpubPositionInfo.tocItemId`、`parseLocatorChanged`（TDD）

**Files:**
- Modify: `app/lib/reader/toc_entry.dart`、`app/lib/reader/epub_position_info.dart`、`app/lib/reader/foliate_bridge_codec.dart`
- Test: `app/test/reader/toc_entry_test.dart`、`app/test/reader/epub_position_info_test.dart`、`app/test/reader/foliate_bridge_codec_test.dart`

**Interfaces:**
- Produces：`TocEntry({…, int? tocId})`（具名可選，預設 `null`）；`EpubPositionInfo({…, int? tocItemId})`（具名可選，預設 `null`，納入 `==`／`hashCode`／`toString`）；`parseLocatorChanged` 填入 `tocItemId`。Task 2、3 使用。

- [x] **Step 1: 寫失敗測試**

`test/reader/toc_entry_test.dart` 的 `group('TocEntry.fromWire', …)` 內新增：

```dart
    test('解析 tocId（含第一個目錄項的 id 為 0，不得被當成缺席）', () {
      final entry = TocEntry.fromWire({
        'title': '第一章',
        'locatorJson': '',
        'progression': null,
        'tocId': 0,
        'children': <Object?>[
          {'title': '第一節', 'locatorJson': '', 'tocId': 1, 'children': <Object?>[]},
        ],
      });
      expect(entry.tocId, 0);
      expect(entry.children.single.tocId, 1);
    });

    test('缺 tocId 欄位時為 null（向下相容舊資料）', () {
      final entry = TocEntry.fromWire({
        'title': '第一章',
        'locatorJson': 'l1',
        'children': <Object?>[],
      });
      expect(entry.tocId, isNull);
    });
```

`test/reader/foliate_bridge_codec_test.dart` 的 `group('parseLocatorChanged', …)` 內新增：

```dart
    test('position 帶 tocItemId：解析為整數，locatorJson 原樣不變（不含 tocItemId）', () {
      const locator = '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}';
      final info = parseLocatorChanged([
        locator,
        '{"fraction":0.1,"locationIndex":9,"locationTotal":100,'
            '"visualPageIndex":null,"visualTotalPages":null,"tocItemId":2}',
      ]);
      expect(info.tocItemId, 2);
      expect(info.locatorJson, locator);
      expect(info.locatorJson, isNot(contains('tocItemId')));
    });

    test('tocItemId 為 0（第一個目錄項）要保留為 0，不得變成 null', () {
      final info = parseLocatorChanged([
        '{"cfi":"epubcfi(/6/4)"}',
        '{"fraction":0.0,"locationIndex":1,"locationTotal":10,'
            '"visualPageIndex":null,"visualTotalPages":null,"tocItemId":0}',
      ]);
      expect(info.tocItemId, 0);
    });

    test('tocItemId 缺席或為 null（無目錄／位置在第一個目錄項之前）：為 null，不拋例外', () {
      final absent = parseLocatorChanged([
        '{"cfi":"epubcfi(/6/4)"}',
        '{"fraction":0.1,"locationIndex":9,"locationTotal":100,'
            '"visualPageIndex":null,"visualTotalPages":null}',
      ]);
      final explicitNull = parseLocatorChanged([
        '{"cfi":"epubcfi(/6/4)"}',
        '{"fraction":0.1,"locationIndex":9,"locationTotal":100,'
            '"visualPageIndex":null,"visualTotalPages":null,"tocItemId":null}',
      ]);
      expect(absent.tocItemId, isNull);
      expect(explicitNull.tocItemId, isNull);
      expect(parseLocatorChanged(const []).tocItemId, isNull);
    });
```

`test/reader/foliate_bridge_codec_test.dart` 另在 `group('parseTableOfContents', …)` 內新增（補橋接反序列化入口的閉環覆蓋）：

```dart
    test('含 tocId 的目錄 JSON：巢狀節點的 tocId（含 0）皆被解析', () {
      final entries = parseTableOfContents(
        '[{"title":"單檔範例","locatorJson":"","progression":null,"tocId":0,'
        '"children":[{"title":"第一節","locatorJson":"","progression":null,'
        '"tocId":1,"children":[]}]}]',
      );
      expect(entries.single.tocId, 0);
      expect(entries.single.children.single.tocId, 1);
    });
```

`test/reader/epub_position_info_test.dart` 新增（沿用該檔既有 import，若無 `epub_position_info.dart` 則補）：

```dart
  group('EpubPositionInfo.tocItemId', () {
    test('tocItemId 納入 == 與 hashCode；預設為 null', () {
      const a = EpubPositionInfo(locatorJson: 'l', tocItemId: 1);
      const b = EpubPositionInfo(locatorJson: 'l', tocItemId: 1);
      const c = EpubPositionInfo(locatorJson: 'l', tocItemId: 2);
      const d = EpubPositionInfo(locatorJson: 'l');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
      expect(d.tocItemId, isNull);
      expect(a.toString(), contains('tocItemId: 1'));
    });

    test('positionKey 不受 tocItemId 影響（位置去重鍵只看 cfi 與 index）', () {
      const json = '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}';
      const a = EpubPositionInfo(locatorJson: json, tocItemId: 1);
      const b = EpubPositionInfo(locatorJson: json, tocItemId: 2);
      expect(a.positionKey, b.positionKey);
    });
  });
```

- [x] **Step 2: 跑測試確認失敗**

Run：`flutter test test/reader/toc_entry_test.dart test/reader/epub_position_info_test.dart test/reader/foliate_bridge_codec_test.dart`
Expected：編譯失敗（`tocId`／`tocItemId` getter 不存在）。

- [x] **Step 3: 實作**

`lib/reader/toc_entry.dart`：在 `progression` 欄位之後新增欄位，並更新建構子與 `fromWire`：

```dart
  /// foliate 為目錄項指派的唯一整數 id（`progress.js assignIDs`，DFS 前序、
  /// 從 0 起）。`main.js buildTocEntry` 輸出；供 [TocNavigator] 與
  /// `EpubPositionInfo.tocItemId`（foliate 以 live DOM 判定的目前目錄項）
  /// 直接比對，免除同一 spine 多錨點時依 progression 猜測的不精確
  /// （epic-54 Issue 20）。舊資料或非 foliate 來源為 `null`。
  final int? tocId;
```

建構子加入 `this.tocId,`（放在 `this.progression,` 之後）；`fromWire` 的 `TocEntry(...)` 加入 `tocId: (map['tocId'] as num?)?.toInt(),`。

`lib/reader/epub_position_info.dart`：新增欄位與註解，並納入建構子、`==`、`hashCode`、`toString`：

```dart
  /// foliate `relocate` 事件的 `tocItem.id`：目前位置所屬目錄項的唯一 id
  /// （live DOM 判定，epic-54 Issue 20）。只供即時 UI（目錄展開／高亮）使用，
  /// **不屬於** [locatorJson]、不持久化、不跨裝置同步。書無目錄或位置落在
  /// 第一個目錄項之前時為 `null`。注意 `0` 是合法 id。
  final int? tocItemId;
```

`hashCode` 改為 `Object.hash(locatorJson, progression, locationIndex, locationTotal, visualPageIndex, visualTotalPages, tocItemId)`；`==` 補 `&& other.tocItemId == tocItemId`；`toString` 補 `, tocItemId: $tocItemId`。**不要**改 `positionKey`。

`lib/reader/foliate_bridge_codec.dart`：`parseLocatorChanged` 的 `EpubPositionInfo(...)` 補 `tocItemId: (position['tocItemId'] as num?)?.toInt(),`，並在函式文件註解的鍵清單補上 `tocItemId`（可為 null）。

- [x] **Step 4: 跑測試確認通過**

Run：同 Step 2 指令。Expected：全部通過（含既有案例）。

- [x] **Step 5: Commit**

```bash
flutter analyze
git add lib/reader/toc_entry.dart lib/reader/epub_position_info.dart lib/reader/foliate_bridge_codec.dart \
  test/reader/toc_entry_test.dart test/reader/epub_position_info_test.dart test/reader/foliate_bridge_codec_test.dart
git commit -m "feat(epic-54): Issue 20 TocEntry.tocId 與 EpubPositionInfo.tocItemId 資料契約" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：`findCurrentPath` 的 `currentTocItemId` 優先判定（純函式，TDD）

**Files:**
- Modify: `app/lib/reader/toc_navigator.dart`
- Test: `app/test/reader/toc_navigator_test.dart`（檔尾新增第三個 `group`，**不動**既有兩個 group）

**Interfaces:**
- Consumes：Task 1 的 `TocEntry.tocId`。
- Produces：`static List<TocEntry> findCurrentPath(List<TocEntry> entries, double? currentProgression, {int? currentSpineIndex, int? currentTocItemId})`——Task 3 呼叫端使用。

- [x] **Step 1: 寫失敗測試**

在 `test/reader/toc_navigator_test.dart` 檔尾 `}` 之前新增（`loc(...)` helper 已存在於 `main()` 範圍內；若它定義在前一個 group 內，改為移到 `main()` 頂層共用，**不改其內容**）：

```dart
  group('findCurrentPath（tocItemId 優先，Issue 20）', () {
    // 單一 spine（index 0）內三個錨點：第一章下有第一節／第二節／第三節。
    // progression 刻意設成與「讀者實際位置」不一致，證明結果來自 tocItemId。
    final s1 = TocEntry(title: '第一節', locatorJson: loc(0, 0.10), progression: 0.10, tocId: 1);
    final s2 = TocEntry(title: '第二節', locatorJson: loc(0, 0.40), progression: 0.40, tocId: 2);
    final s3 = TocEntry(title: '第三節', locatorJson: loc(0, 0.70), progression: 0.70, tocId: 3);
    final ch = TocEntry(
      title: '第一章',
      locatorJson: loc(0),
      progression: null,
      tocId: 0,
      children: [s1, s2, s3],
    );
    final next = TocEntry(title: '第二章', locatorJson: loc(1), progression: null, tocId: 4);
    final toc = [ch, next];

    test('開書 progression 偏高（0.55）但 foliate 回報目前是第一節：只選第一節', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.55, currentSpineIndex: 0, currentTocItemId: 1),
        [ch, s1],
        reason: '不得因 0.55 >= 0.40 而誤選第二節',
      );
    });

    test('currentTocItemId 為 0（第一個目錄項）要命中第一個節點，不得退回舊規則', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.55, currentSpineIndex: 0, currentTocItemId: 0),
        [ch],
        reason: '0 是合法 id；若被當成缺席會退回 progression 規則而選到第二節',
      );
    });

    test('回報第三節：回傳第一章→第三節的完整祖先路徑', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.05, currentSpineIndex: 0, currentTocItemId: 3),
        [ch, s3],
      );
    });

    test('目前 spine 沒有目錄項、foliate 回報前一章節點：回傳該節點的祖先路徑', () {
      // 讀者在 spine 2（無目錄項的插頁），tocItem 為前一個項目「第三節」。
      expect(
        TocNavigator.findCurrentPath(toc, 0.9, currentSpineIndex: 2, currentTocItemId: 3),
        [ch, s3],
      );
    });

    test('currentTocItemId 在樹中查無節點：退回 spine index 規則（Issue 19）', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.9, currentSpineIndex: 1, currentTocItemId: 99),
        [next],
      );
    });

    test('currentTocItemId 為 null：行為與 Issue 19 相同', () {
      expect(
        TocNavigator.findCurrentPath(toc, 0.55, currentSpineIndex: 0),
        TocNavigator.findCurrentPath(toc, 0.55, currentSpineIndex: 0, currentTocItemId: null),
      );
    });

    test('節點缺 tocId（舊資料）時 id 不命中，退回舊規則且不拋例外', () {
      final legacy = TocEntry(title: '舊節點', locatorJson: loc(0), progression: null);
      expect(
        TocNavigator.findCurrentPath([legacy], null, currentSpineIndex: 0, currentTocItemId: 0),
        [legacy],
      );
    });

    test('只有 currentTocItemId、其餘皆 null 也能判定（不被「皆 null 回空」誤擋）', () {
      expect(
        TocNavigator.findCurrentPath(toc, null, currentTocItemId: 2),
        [ch, s2],
      );
    });

    test('三者皆 null 回傳空清單（首個 relocate 之前）', () {
      expect(TocNavigator.findCurrentPath(toc, null), isEmpty);
    });
  });
```

- [x] **Step 2: 跑測試確認失敗**

Run：`flutter test test/reader/toc_navigator_test.dart`
Expected：編譯失敗（`No named parameter with the name 'currentTocItemId'`）。

- [x] **Step 3: 實作**

`lib/reader/toc_navigator.dart`：簽章加入 `int? currentTocItemId`；最前面的空檢查改為三者皆 null；其後、`bestPath` 走訪之前插入 id 優先分支。並在文件註解補一段（正體中文）說明 epic-54 Issue 20：

```dart
  static List<TocEntry> findCurrentPath(
    List<TocEntry> entries,
    double? currentProgression, {
    int? currentSpineIndex,
    int? currentTocItemId,
  }) {
    if (currentProgression == null &&
        currentSpineIndex == null &&
        currentTocItemId == null) {
      return const [];
    }
    // epic-54 Issue 20：foliate 以 live DOM 判定的目前目錄項，精確度最高，
    // 有命中就直接採用；查無（id 缺席、目錄尚未載入、節點缺 tocId）則
    // 往下退回 spine index／progression 規則。注意 id 0 是合法值，
    // 一律以 `!= null` 判斷，不可用 truthy。
    if (currentTocItemId != null) {
      final byId = _pathToTocId(entries, currentTocItemId, const []);
      if (byId != null) return byId;
    }
    // …以下維持 Issue 19 既有程式不動（bestPath／walk／return）
```

新增私有 helper：

```dart
  /// DFS 找出 [TocEntry.tocId] 等於 [tocId] 的節點，回傳根到該節點的路徑；
  /// 查無回傳 `null`。
  static List<TocEntry>? _pathToTocId(
    List<TocEntry> nodes,
    int tocId,
    List<TocEntry> path,
  ) {
    for (final node in nodes) {
      if (node.tocId == tocId) return [...path, node];
      final found = _pathToTocId(node.children, tocId, [...path, node]);
      if (found != null) return found;
    }
    return null;
  }
```

- [x] **Step 4: 跑測試確認通過**

Run：`flutter test test/reader/toc_navigator_test.dart`
Expected：全部通過（舊 6＋Issue 19 的 9＋新 9）。

- [x] **Step 5: 突變驗證（證明新測試會咬人）**

(a) 暫時把 `if (currentTocItemId != null)` 改為 `if (currentTocItemId != null && currentTocItemId != 0)`，跑同檔，Expected：「currentTocItemId 為 0」案失敗；還原。
(b) 暫時把 `_pathToTocId` 整段 id 優先分支註解掉，Expected：「開書 progression 偏高…只選第一節」等案失敗；還原後再跑一次確認全過。

- [x] **Step 6: Commit**

```bash
flutter analyze
git add lib/reader/toc_navigator.dart test/reader/toc_navigator_test.dart
git commit -m "feat(epic-54): Issue 20 findCurrentPath 新增 tocItemId 優先判定" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：`main.js` 輸出 id、`ReaderScreen` 傳入 `currentTocItemId`

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`（`buildTocEntry` 約 750-757 行；`onLocatorChanged` 的 `position` 約 1143-1161 行）
- Modify: `app/lib/screens/reader_screen.dart`（`_currentEpubTocPath()` 約 1340 行）
- Test: 既有 `test/screens/reader_screen_test.dart`、`test/screens/toc_bottom_sheet_test.dart`（只確認未回歸）

**Interfaces:**
- Consumes：Task 1 的 wire 欄位名 `tocId`（目錄節點）／`tocItemId`（position）；Task 2 的 `findCurrentPath(…, currentTocItemId:)`。

> **測試現實說明：** `main.js` 依賴 DOM／foliate 全域，專案沒有可在 Node 內載入它的測試慣例（`tts-safe-window.js` 等是另外抽出的零 DOM 純函式）。這兩行 JS 變更**不另抽檔**（過度設計），其正確性由 Task 1 的 codec 測試（wire 格式）＋Task 4 真機 integration（端到端）把關。

- [x] **Step 1: 改 `main.js`**

`buildTocEntry` 回傳物件新增 `tocId`（`item.id` 由 `TOCProgress.init` 就地指派，見上方事實表；用 `?? null` 而非 `||`，`0` 為合法值）：

```javascript
  return {
    title: item.label ?? '',
    locatorJson: cfi
      ? JSON.stringify({ cfi, index, fraction })
      : '',
    progression: fraction,
    // epic-54 Issue 20：foliate TOCProgress.assignIDs 指派的唯一整數 id
    //（DFS 前序、從 0 起；0 為合法值，故用 ?? 不用 ||），供 Dart 端與
    // relocate 回報的 tocItem.id 直接比對。
    tocId: item.id ?? null,
    children,
  }
```

`onLocatorChanged` 的兩個 `position` 分支（FXL／流式）**各自**加一行（兩個物件都要加，漏一個就只有一種格式有效）：

```javascript
            tocItemId: e.detail.tocItem?.id ?? null,
```

放在各自物件的最後一個欄位之後（記得前一行補逗號）；並在 `const position = …` 上方補註解說明：`tocItem` 是 foliate 以 live DOM `Range.comparePoint` 算出的目前目錄項，id 放在第 2 參數 `position`、**不放第 1 參數** `locatorJson`（凍結，會持久化並跨裝置同步）。**不要動** `JSON.stringify({ cfi, index: chapterIndex, fraction: fraction ?? 0 })` 那一行。

- [x] **Step 2: 確認第 1 參數未被改動**

```bash
git diff -U0 android/app/src/main/assets/foliate/main.js | grep -n "chapterIndex, fraction"
```

Expected：**沒有任何輸出**（diff 不含該行）。

- [x] **Step 3: 改 `reader_screen.dart`**

```dart
  List<TocEntry> _currentEpubTocPath() => TocNavigator.findCurrentPath(
        _tocEntries,
        _epubPositionInfo?.progression,
        currentSpineIndex: extractChapterIndex(_epubPositionInfo?.locatorJson),
        currentTocItemId: _epubPositionInfo?.tocItemId,
      );
```

同時更新其上方文件註解：補一句「epic-54 Issue 20 起另傳 foliate 以 live DOM 判定的 `tocItemId`，同 spine 多錨點時優先採用」。

- [x] **Step 4: 靜態檢查與受影響的既有測試**

```bash
flutter analyze
node tool/check_foliate_es_compat.js
flutter test test/screens/reader_screen_test.dart test/screens/toc_bottom_sheet_test.dart test/reader/toc_navigator_test.dart test/reader/foliate_bridge_codec_test.dart
```

Expected：analyze 乾淨；ES 相容守衛 PASS；測試全過。若 `reader_screen_test` 有案例失敗，先判斷是測試過期還是新缺陷，不得直接改斷言，回報使用者決定（全域 CLAUDE.md 第 8 條）。

- [x] **Step 5: Commit**

```bash
git add android/app/src/main/assets/foliate/main.js lib/screens/reader_screen.dart
git commit -m "feat(epic-54): Issue 20 main.js 轉發 foliate tocItem.id 並由 ReaderScreen 傳入目前章節判定" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4：單 spine 多錨點 fixture ＋ 真機 integration 驗證

**Files:**
- Create: `app/test/fixtures/sample_single_spine_multi_anchor.epub`
- Modify: `app/pubspec.yaml`（asset 清單，約 214 行 `sample_multi_chapter.epub` 之後）
- Modify: `app/integration_test/epub_toc_test.dart`（檔尾新增第二個 `testWidgets`，沿用檔內既有 helper）

**Interfaces:**
- Consumes：Task 1～3 全部。

- [x] **Step 1: 產生 fixture**

結構：**一個** spine 項目（`chapter.xhtml`），內含 `<h1>` 與三個 `<h2 id="s1|s2|s3">`；每節約 60 段、每段約 40 字，確保每節遠大於一頁（foliate 在同頁含多錨點時會選最後一個，見 `progress.js:46-54`，節太短會使斷言不穩）。nav 為一個頂層項目「單檔範例」下掛三個子節。在 PowerShell 工具執行（`mimetype` 必須是第一個 entry 且不壓縮）：

```powershell
$work = Join-Path $env:TEMP 'epub20'
Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$work\META-INF","$work\OEBPS" | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
function W($p,$t){ [IO.File]::WriteAllText("$work\$p",$t,$utf8) }

W 'mimetype' 'application/epub+zip'
W 'META-INF\container.xml' @'
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
'@
W 'OEBPS\content.opf' @'
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000020</dc:identifier>
    <dc:title>elinkBook 單檔多錨點目錄範例 EPUB</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="dcterms:modified">2026-10-08T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="chapter"/></spine>
</package>
'@
W 'OEBPS\nav.xhtml' @'
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body>
  <nav epub:type="toc">
    <ol>
      <li><a href="chapter.xhtml">單檔範例</a>
        <ol>
          <li><a href="chapter.xhtml#s1">第一節</a></li>
          <li><a href="chapter.xhtml#s2">第二節</a></li>
          <li><a href="chapter.xhtml#s3">第三節</a></li>
        </ol>
      </li>
    </ol>
  </nav>
</body>
</html>
'@
$body = New-Object System.Text.StringBuilder
[void]$body.Append("<h1>單檔範例</h1>`n")
foreach ($n in 1..3) {
  [void]$body.Append("<h2 id=`"s$n`">第$(('一','二','三')[$n-1])節</h2>`n")
  foreach ($p in 1..60) {
    [void]$body.Append("<p>這是第 $n 節的第 $p 段，用來讓單一檔案內的每個小節都遠超過一個畫面的長度。</p>`n")
  }
}
W 'OEBPS\chapter.xhtml' ("<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<html xmlns=`"http://www.w3.org/1999/xhtml`"><head><title>單檔範例</title></head><body>`n" + $body.ToString() + "</body></html>`n")

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$out = 'C:\Users\fycdc\AI\elinkBook\app\test\fixtures\sample_single_spine_multi_anchor.epub'
Remove-Item $out -ErrorAction SilentlyContinue
$zip = [IO.Compression.ZipFile]::Open($out,'Create')
$files = @(
  @('mimetype','mimetype','NoCompression'),
  @('META-INF/container.xml','META-INF\container.xml','Optimal'),
  @('OEBPS/content.opf','OEBPS\content.opf','Optimal'),
  @('OEBPS/nav.xhtml','OEBPS\nav.xhtml','Optimal'),
  @('OEBPS/chapter.xhtml','OEBPS\chapter.xhtml','Optimal'))
foreach ($f in $files) {
  [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,"$work\$($f[1])",$f[0],[IO.Compression.CompressionLevel]::$($f[2]))
}
$zip.Dispose()
```

驗證：

```bash
unzip -l test/fixtures/sample_single_spine_multi_anchor.epub
```

Expected：5 個 entry，第一個是 `mimetype`（20 bytes）。

在 `pubspec.yaml` 的 asset 清單加入 `    - test/fixtures/sample_single_spine_multi_anchor.epub`。

- [x] **Step 2: 寫整合測試（先紅）**

在 `integration_test/epub_toc_test.dart` 的 `main()` 內、既有 `testWidgets` 之後新增（`_stageAssetAsFile`／`_pumpUntilLoaded`／`_pumpUntilFooterVisible`／`_pumpUntilTocButtonEnabled`／`_pumpUntilProgressChanged` 皆沿用；書籍建構樣板複製自既有測試，`id` 與檔名改為 `b_epub_toc_single_spine`／`epub_toc_single_spine.epub`）：

```dart
  testWidgets('單一 spine 內多個目錄錨點：開書與跳轉後「目前章節」皆由 DOM 判定，精確到小節（epic-54 Issue 20）',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_single_spine_multi_anchor.epub',
        'epub_toc_single_spine.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_epub_toc_single_spine',
      title: 'EPUB 單檔多錨點目錄測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await pumpLocalizedWidget(
      tester,
      ReaderScreen(
        filePath: samplePath,
        bookId: 'b_epub_toc_single_spine',
        dependencies: fakeReaderFeatureDependencies(prefsManager: prefsManager),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilFooterVisible(tester);

    Future<void> openToc() async {
      await _pumpUntilTocButtonEnabled(tester);
      await tester.tap(find.byKey(const Key('reader_chrome_toc_button')));
      await tester.pumpAndSettle();
      expect(find.byType(TocBottomSheet), findsOneWidget);
    }

    bool selected(String title) =>
        tester.widget<ListTile>(find.widgetWithText(ListTile, title)).selected;

    Future<void> closeToc() async {
      await tester.tap(find.byKey(const Key('toc_bottom_sheet_close_button')));
      await tester.pumpAndSettle();
    }

    // 1) 開書位於第一節（頁面含 h1 與 s1 錨點，s2/s3 在後面）：
    //    不得因全書 progression 偏高而選到第二、三節。
    await openToc();
    expect(selected('第一節'), isTrue, reason: '開書位於第一節');
    expect(selected('第二節'), isFalse);
    expect(selected('第三節'), isFalse);
    final progressAtOpen = tester
            .widget<Text>(find.byKey(const Key('reader_footer_progress_text')))
            .data ??
        '';

    // 2) 跳到第三節。
    await tester.tap(find.widgetWithText(ListTile, '第三節'));
    await tester.pumpAndSettle();
    await _pumpUntilProgressChanged(tester, progressAtOpen);
    await openToc();
    expect(selected('第三節'), isTrue, reason: '跳到第三節後應標示第三節');
    expect(selected('第一節'), isFalse);
    expect(selected('第二節'), isFalse);
    final progressAtS3 = tester
            .widget<Text>(find.byKey(const Key('reader_footer_progress_text')))
            .data ??
        '';

    // 3) 回頭跳到第二節（往回跳，驗證不是只會往後）。
    await tester.tap(find.widgetWithText(ListTile, '第二節'));
    await tester.pumpAndSettle();
    await _pumpUntilProgressChanged(tester, progressAtS3);
    await openToc();
    expect(selected('第二節'), isTrue, reason: '往回跳到第二節後應標示第二節');
    expect(selected('第一節'), isFalse);
    expect(selected('第三節'), isFalse);

    await closeToc();
    expect(find.byType(TocBottomSheet), findsNothing);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
```

（`TocBottomSheet` 開書時因目前路徑含「單檔範例」，子節預設展開，三個子節皆可見，無需先點展開鈕——若真機觀察到未展開，改為先點該列展開鈕再斷言，並在 epic.md 記錄。）

- [x] **Step 3: 真機執行（綠）**

向使用者確認可清除 `TCL 14` 的 App 資料後：

```bash
export MSYS_NO_PATHCONV=1
ADB=/c/Users/fycdc/AppData/Local/Android/Sdk/platform-tools/adb.exe
$ADB devices -l
$ADB shell pm clear cc.ugotit.elinkbook
cd /c/Users/fycdc/AI/elinkBook/app
flutter test integration_test/epub_toc_test.dart -d 3CEF42ECD491687
```

Expected：兩個 `testWidgets` 皆通過（`+2`）。失敗時先判斷是 fixture 節長度不足（同頁含多錨點，foliate 取最後一個）還是程式缺陷：前者加長 fixture 段數，後者回 Task 3 查證，不得放寬斷言。

- [x] **Step 4: 突變驗證（證明 integration 有咬力；若無須如實記錄）**

暫時把 `_currentEpubTocPath()` 內 `currentTocItemId: …` 那行註解掉（等同回到 Issue 19 狀態），在 `TCL 14` 跑同一指令。
- 若新 `testWidgets` 失敗（預期於 `expect(selected('第一節'), isTrue …)` 或跳轉後的斷言）→ 還原後再跑確認 `+2`，兩次輸出摘要記入 `epic.md`。
- 若**仍通過** → 代表舊規則在此 fixture 上剛好答對，integration 對 `tocItemId` 沒有咬力；**不得宣稱 integration 驗證了精確度改善**，改在 `epic.md` 如實寫「端到端接線已驗證（id 由 JS 傳到 Dart 且路徑正確），精確度改善由 Task 2 單元測試證明」，並還原。

- [x] **Step 5: 守衛腳本與提交**

```bash
node tool/check_integration_keys.js
node tool/check_l10n_hardcoded_strings.js
flutter analyze
git add test/fixtures/sample_single_spine_multi_anchor.epub pubspec.yaml integration_test/epub_toc_test.dart
git commit -m "test(epic-54): Issue 20 單 spine 多錨點 fixture 與真機目錄章節判定驗證" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：三項皆乾淨／PASS。

---

### Task 5：完整驗證、文件同步與收尾

**Files:**
- Modify：`docs/epics/epic-54-architecture-optimization/epic.md`、`issues.md`（第 20 列狀態，合併後才改）、`docs/epics.md`（備註只寫「Issue 20 已完成」）
- Modify：本計畫檔（勾選 Step、補附錄）

- [x] **Step 1: 完整 `flutter test`（只此一次，背景執行）**

在 `app/` 下以 `run_in_background` 執行 `flutter test`。Expected：全部通過、零失敗（Issue 21／PR #338 已修復 `pdf_reader_view_filters_test`，現行 `main` 為首度全綠的樹）。任何失敗都視為潛在回歸，逐一排查，不得歸為「既存失敗」。

- [x] **Step 2: 補 integration 回歸**

在 `TCL 14` 另跑：

```bash
flutter test integration_test/epub_toc_test.dart -d 3CEF42ECD491687
flutter test integration_test/notes_bookmark_test.dart -d 3CEF42ECD491687
flutter test integration_test/reader_header_footer_toggle_test.dart -d 3CEF42ECD491687
```

Expected：皆通過（`notes_bookmark` 涉及書籤章節名、`header_footer` 涉及頁首章節文字，兩者都走 `_currentEpubTocPath()`）。

- [x] **Step 3: 回寫文件（隨功能分支）**

- `epic.md` 新增「Issue 20 實作完成與真機驗證結果」段：根因、方案 B 機制、使用者原話出處（見附錄 A）、突變驗證結果（含 Task 4 Step 4 是否有咬力的如實記錄）、`locatorJson` 未變動的 diff 驗證。
- 本計畫 checkbox 勾選與附錄。
- **分支與提交方式**（比照 Issue 18／19 先例）：實作紀錄隨功能分支；PR 合併後 `git switch main && git pull`，再把 `issues.md` 第 20 列改 `🟢 已合併（PR #N）`、`docs/epics.md` 備註與 `epic.md` 的「Issue 20 已合併」一行，直接 commit＋push `main`（不開 PR）。功能分支上 `issues.md` 第 20 列維持 `⚪ 待處理`，不提前改 `🟡`。Epic 54 全部 Issue 完成後是否歸檔由使用者指定。

- [x] **Step 4: 發 PR 前確認並請求程式審查**

```bash
git log --oneline main..HEAD
flutter analyze
```

審查者先產出報告（`reviews/review-code-issue-20.md`，gitignore），不得直接改程式；處理審查後才發 PR（由使用者合併）。

---

## 附錄 A：使用者決定紀錄

- 方案選擇（B：轉發 `tocItem`；C：維持現狀）：使用者於 2026-10-08 對話先回答 `C`，隨即更正為原話：`打錯了，要選擇B才對，請修正`。最終為方案 B（出處：`epic.md`「Issue 20 決定推動（方案 B）」）。
- 本計畫無其他待使用者決定的演算法取捨；執行方式（executing-plans／subagent-driven）待計畫審查時由使用者指定。

## Self-Review 結果

- **Spec 涵蓋**：issues.md 第 20 列——轉發 `tocItem` 識別資訊（Task 3）；`buildTocEntry` 同樣帶識別（Task 3）；Dart 直接比對（Task 2）；約束 (1) `locatorJson` 凍結 → Task 3 Step 2 的 diff 守衛＋Task 1 codec 測試；(2) 不改 vendor → 檔案清單只含 `main.js`；(3) 首個 relocate 前語意 → Task 2「三者皆 null 回空」；(4) id 缺失退回 Issue 19 → Task 2 測試；測試素材 → Task 4 fixture。工單「Plan 階段確認 `id` 或 `href` 較穩」的結論：選 `id`——`href` 在同一 spine 多項目時可能重複或帶 fragment 差異，`id` 由 foliate 唯一指派且與 `buildTocEntry` 走訪順序同為 DFS 前序。
- **佔位掃描**：無 TBD、無省略樣板。
- **型別一致**：`TocEntry.tocId`（int?）、`EpubPositionInfo.tocItemId`（int?）、wire 鍵 `tocId`（目錄節點）／`tocItemId`（position）、`findCurrentPath(…, {currentSpineIndex, currentTocItemId})` 在 Task 1～3 一致。
- **Review Focus**：5 項皆對應 Task 1／2／3 的具體測試或 diff 檢查步驟。
