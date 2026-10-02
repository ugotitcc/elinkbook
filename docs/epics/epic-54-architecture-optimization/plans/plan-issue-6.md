# Issue 6：ARB 鍵一致性自動守衛 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 新增一組隨 `flutter test` 執行的測試，守住四份 ARB（`app_zh_TW`／`app_zh`／`app_en`／`app_zh_CN`）的一致性：不缺鍵不多鍵、placeholder 名稱一致、`zh` 與 `zh_TW` 逐字相同、`en` 沒有漏翻（刻意相同者列白名單）。

**Architecture：** 偵測邏輯寫成純函式放 `app/test/l10n/arb_consistency_helpers.dart`，回傳「違規訊息清單」；`arb_consistency_helpers_test.dart` 用合成資料證明每條規則「抓得到」違規；`arb_consistency_test.dart` 讀真實四份 ARB 呼叫同一組函式，並持有 `en` 白名單常數。不改任何 App 程式碼與 ARB。

**Tech Stack：** Flutter／Dart、`flutter_test`、`dart:io`、`dart:convert`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立的 `spec.md`，設計依據是 2026-10-02 `/grill-with-docs` 的決策，記錄於 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 6 設計決策」。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **不改 App**：只新增 `app/test/l10n/` 下的測試檔與一行文件；不得修改 `app/lib/` 任何檔案（含四份 ARB 與生成檔）。若測試對真實 ARB 報違規，那是**真實漂移**，停下來回報，不要自行改 ARB。
- **解析規則**：略過 `@@locale` 與所有以 `@` 開頭的鍵；其餘值皆為字串（已驗證 641 個鍵無非字串值）。
- **placeholder 抽取規則**（固定，不得改）：`RegExp(r'\{\s*(\w+)\s*(?:,|\})')` 取第 1 群，結果為名稱集合。已驗證在 641 個鍵上與 template 的 `@key.placeholders` 宣告零差異。已知限制：ICU `select` 或 `plural` 的**單字分支**（如 `=0{None}`、`other{Many}`）會被誤判成 placeholder `None`／`Many`（`plural` 現有 18 個鍵的分支皆為片語或 `{count}`，不受影響）。遇到時把分支寫成含空格的片語（如 `=0{no items}`）即可避開；**尾隨空格（`{None }`）無效**，因為 regex 的 `\s*` 會吃掉空格。這是 `epic.md` 設計決策已接受的限制，本 Issue 不改規則。
- **中文字元判定**：`RegExp(r'[一-鿿]')`。
- **`en` 白名單**：`const Map<String, String>`（鍵 → 理由），放在 `arb_consistency_test.dart`，目前 3 筆：`settingsLanguageZhTW`、`settingsLanguageZhCN`、`settingsLanguageEn`。白名單項目若不再命中「與 zh_TW 相同或含中文字元」（或鍵已不存在）即視為過期並失敗。
- **不檢查**：`zh_CN` 與 zh_TW 相同的字串（現況 78 個多為兩岸寫法一致的詞）；模板每鍵是否有 `@` 描述。
- **失敗訊息**：一次列出所有違規鍵，格式 `[語言] 說明：鍵1, 鍵2`（鍵依字母排序）。
- **讀檔路徑**：`flutter test` 的工作目錄是 `app/`，ARB 以 `lib/l10n/app_xx.arb` 相對路徑讀取（比照 `test/library/book_content_fingerprint_test.dart` 讀 `test/fixtures/sample.epub` 的既有慣例）。
- **指令語法**：bash 語法，用 Bash 工具（Git Bash）執行。
- **Windows 環境**：`python` 在此環境不會實際執行，不可用來編輯檔案；用 Edit 工具或 Node 腳本。多數原始檔是 CRLF 換行（ARB 也是），Edit 的定位字串不要含換行。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 6 分鐘，用 `run_in_background`）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：直接 TDD；程式審查先出報告（存於 `reviews/`，該目錄 gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。

## Review Focus

最可能咬到開發者的情況（依可能性排序），每條都有對應測試：

1. **新增鍵時 `en` 直接複製了中文（或與 zh_TW 同字）。** 這是「四份同步」最常見的偷懶方式：`en` 的值等於 zh_TW，編譯與執行都不報錯，英文介面卻顯示中文。→ Task 1 測「`en` 與 zh_TW 相同被抓」「`en` 含中文字元被抓」。
2. **新增鍵只加進 zh_TW，其他語言漏了（或刪鍵只刪一份）。** → Task 1 測缺鍵與多鍵。
3. **帶參數的訊息某語言漏了 `{count}`（或多了 template 沒有的參數）。** 執行期會顯示缺數字或 `gen-l10n` 行為不明。→ Task 1 測 placeholder 少一個、多一個，以及 ICU `plural` 巢狀的 `{count}` 不會被誤判。已知盲點（不在本 Issue 修）：`plural`／`select` 的單字分支會被誤判，見 Global Constraints 的限制與避開寫法。
4. **只改了 zh_TW 的文案，忘了同步 `app_zh.arb`。** `zh` 是落到 base 的使用者（不帶國別的 `zh`、`zh_HK` 等）看到的文字。→ Task 1 測 `zh` 偏離被抓。
5. **白名單過期而沒人發現。** 語言自稱改了、或鍵被刪了，白名單卻還留著，守衛逐漸變鈍。→ Task 1 測「白名單項目不再命中」與「白名單鍵已不存在」都失敗。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/test/l10n/arb_consistency_helpers.dart` | 新增 | 純函式：`messagesOf`、`loadArbMessages`、`placeholderNames`、`keySetViolations`、`placeholderViolations`、`zhMirrorViolations`、`enUntranslatedViolations` |
| `app/test/l10n/arb_consistency_helpers_test.dart` | 新增 | 以合成資料證明每條規則會失敗、不誤報 |
| `app/test/l10n/arb_consistency_test.dart` | 新增 | 讀真實四份 ARB，呼叫同一組函式；持有 `_enAllowlist` |
| `app/tool/README.md` | 修改 | 「找到問題時怎麼修」補上指向新測試與白名單用法 |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 開發記錄、狀態 |

---

### Task 0：提交計畫、建立 worktree

**Files：**
- Commit：本計畫檔與 `issues.md` 狀態更新（在 `main` 上，純文件）
- 建立 worktree：`.worktrees/epic-54-issue-6-arb-guard`（`.worktrees/` 已 gitignore）

**Interfaces：**
- Consumes：無。
- Produces：後續 Task 都在 worktree 的分支 `epic-54/issue-6-arb-guard` 上進行與提交。

- [ ] **Step 1：在 `main` 提交計畫，並把 Issue 6 標為進行中**

先把 `docs/epics/epic-54-architecture-optimization/issues.md` 的 Issue 6 狀態改為「🟡 進行中（`plans/plan-issue-6.md`）」，並把 `docs/epics.md` Epic 54 那列的「Issue 6 已設計，待寫計畫」改為「Issue 6 進行中」，再提交：

```bash
cd /c/Users/fycdc/AI/elinkBook
git status --short
git add docs/epics/epic-54-architecture-optimization/plans/plan-issue-6.md docs/epics/epic-54-architecture-optimization/issues.md docs/epics.md
git commit -m "docs(epic-54): Issue 6 實作計畫，標為進行中

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`git status --short` 在 add 之前只有這三個檔案。

- [ ] **Step 2：推送 `main`（對外動作，須先取得使用者確認，不得自動推送）**

確認後：

```bash
git push origin main
```

若 push 被拒絕，**不要強制推送**：先 `git pull --no-rebase --no-edit`，再重新 `git push origin main`。

- [ ] **Step 3：建立 worktree 與分支**

```bash
cd /c/Users/fycdc/AI/elinkBook
git worktree add .worktrees/epic-54-issue-6-arb-guard -b epic-54/issue-6-arb-guard main
cd .worktrees/epic-54-issue-6-arb-guard/app
flutter pub get
```

Expected：`Preparing worktree (new branch 'epic-54/issue-6-arb-guard')`。之後所有指令都在這個 worktree 的 `app/` 下執行。

---

### Task 1：偵測函式與合成資料測試

**Files：**
- Create: `app/test/l10n/arb_consistency_helpers.dart`
- Create: `app/test/l10n/arb_consistency_helpers_test.dart`

**Interfaces：**
- Consumes：無（只用 `dart:io`、`dart:convert`）。
- Produces（Task 2 依賴，名稱與簽章必須一致）：

```dart
/// 去掉 `@@locale` 與所有 `@key` 中繼資料，回傳「鍵 → 字串」。
Map<String, String> messagesOf(Map<String, dynamic> arb);

/// 讀取 ARB 檔並呼叫 [messagesOf]。
Map<String, String> loadArbMessages(String path);

/// 字串內所有 placeholder 名稱（含 ICU plural／巢狀分支內的）。
Set<String> placeholderNames(String message);

/// 以下四個都回傳「違規訊息」清單；空清單代表沒有違規。
List<String> keySetViolations(String label, Map<String, String> base, Map<String, String> other);
List<String> placeholderViolations(String label, Map<String, String> base, Map<String, String> other);
List<String> zhMirrorViolations(Map<String, String> base, Map<String, String> zh);
List<String> enUntranslatedViolations(Map<String, String> base, Map<String, String> en, Map<String, String> allowlist);
```

違規訊息格式（測試與實作必須逐字一致）：
- `[<label>] 缺鍵：<鍵, 鍵>`、`[<label>] 多鍵：<鍵, 鍵>`
- `[<label>] 鍵 <k> 的 placeholder 不一致：zh_TW={a, b}，<label>={a}`
- `[zh] 與 zh_TW 文字不同的鍵：<鍵, 鍵>`
- `[en] 疑似漏翻（與 zh_TW 相同或含中文字元）：<鍵, 鍵>`
- `[en] 白名單已過期（不再與 zh_TW 相同、也不含中文字元，或鍵已不存在）：<鍵, 鍵>`

- [ ] **Step 1：寫失敗的測試**

建立 `app/test/l10n/arb_consistency_helpers_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'arb_consistency_helpers.dart';

void main() {
  group('messagesOf', () {
    test('略過 @@locale 與所有 @key 中繼資料，只留鍵與字串', () {
      final result = messagesOf({
        '@@locale': 'en',
        'cancel': 'Cancel',
        '@cancel': {'description': '取消按鈕'},
        'close': 'Close',
      });

      expect(result, {'cancel': 'Cancel', 'close': 'Close'});
    });
  });

  group('placeholderNames', () {
    test('單純的 {name} 取出名稱', () {
      expect(placeholderNames('第 {chapter} 章'), {'chapter'});
    });

    test('多個 placeholder 都取出', () {
      expect(placeholderNames('{a} 與 {b}'), {'a', 'b'});
    });

    test('ICU plural 的計數參數與巢狀分支內的 {count} 只算一個名稱，分支文字不誤判', () {
      expect(
        placeholderNames('{count, plural, =1{1 本} other{{count} 本}}'),
        {'count'},
      );
    });

    test('沒有 placeholder 時回傳空集合', () {
      expect(placeholderNames('取消'), isEmpty);
    });
  });

  group('keySetViolations', () {
    test('鍵集合相同：沒有違規', () {
      expect(keySetViolations('en', {'a': '甲', 'b': '乙'}, {'a': 'A', 'b': 'B'}), isEmpty);
    });

    test('other 缺鍵：列出缺的鍵（排序）', () {
      expect(
        keySetViolations('en', {'a': '甲', 'b': '乙', 'c': '丙'}, {'a': 'A'}),
        ['[en] 缺鍵：b, c'],
      );
    });

    test('other 多鍵：列出多的鍵', () {
      expect(
        keySetViolations('zh_CN', {'a': '甲'}, {'a': '甲', 'x': '叉'}),
        ['[zh_CN] 多鍵：x'],
      );
    });

    test('同時缺鍵與多鍵：兩則訊息', () {
      expect(
        keySetViolations('en', {'a': '甲', 'b': '乙'}, {'a': 'A', 'x': 'X'}),
        ['[en] 缺鍵：b', '[en] 多鍵：x'],
      );
    });
  });

  group('placeholderViolations', () {
    test('placeholder 名稱集合相同：沒有違規', () {
      expect(
        placeholderViolations('en', {'k': '{count} 本'}, {'k': '{count} books'}),
        isEmpty,
      );
    });

    test('other 少一個 placeholder：抓出並顯示兩邊集合', () {
      expect(
        placeholderViolations('en', {'k': '{count} 本，共 {total}'}, {'k': 'books'}),
        ['[en] 鍵 k 的 placeholder 不一致：zh_TW={count, total}，en={}'],
      );
    });

    test('other 多一個 template 沒有的 placeholder：抓出', () {
      expect(
        placeholderViolations('zh_CN', {'k': '{count} 本'}, {'k': '{count} 本 {x}'}),
        ['[zh_CN] 鍵 k 的 placeholder 不一致：zh_TW={count}，zh_CN={count, x}'],
      );
    });

    test('只存在於一邊的鍵不在此檢查（交給 keySetViolations）', () {
      expect(placeholderViolations('en', {'a': '{n}'}, {'b': '{m}'}), isEmpty);
    });
  });

  group('zhMirrorViolations', () {
    test('zh 與 zh_TW 逐字相同：沒有違規', () {
      expect(zhMirrorViolations({'a': '取消'}, {'a': '取消'}), isEmpty);
    });

    test('zh 偏離 zh_TW：列出偏離的鍵', () {
      expect(
        zhMirrorViolations({'a': '取消', 'b': '確定'}, {'a': '取消', 'b': '确定'}),
        ['[zh] 與 zh_TW 文字不同的鍵：b'],
      );
    });
  });

  group('enUntranslatedViolations', () {
    test('en 有翻譯：沒有違規', () {
      expect(enUntranslatedViolations({'a': '取消'}, {'a': 'Cancel'}, {}), isEmpty);
    });

    test('en 與 zh_TW 相同：視為漏翻', () {
      expect(
        enUntranslatedViolations({'a': '取消'}, {'a': '取消'}, {}),
        ['[en] 疑似漏翻（與 zh_TW 相同或含中文字元）：a'],
      );
    });

    test('en 與 zh_TW 不同但含中文字元：視為漏翻', () {
      expect(
        enUntranslatedViolations({'a': 'A'}, {'a': '取消 Cancel'}, {}),
        ['[en] 疑似漏翻（與 zh_TW 相同或含中文字元）：a'],
      );
    });

    test('列入白名單的鍵不算漏翻', () {
      expect(
        enUntranslatedViolations(
          {'a': '正體中文'},
          {'a': '正體中文'},
          {'a': '語言自稱，刻意不翻譯'},
        ),
        isEmpty,
      );
    });

    test('白名單項目不再命中（en 已有翻譯）：視為過期', () {
      expect(
        enUntranslatedViolations(
          {'a': '取消'},
          {'a': 'Cancel'},
          {'a': '舊的理由'},
        ),
        ['[en] 白名單已過期（不再與 zh_TW 相同、也不含中文字元，或鍵已不存在）：a'],
      );
    });

    test('白名單的鍵在 en 已不存在：視為過期', () {
      expect(
        enUntranslatedViolations({'a': '取消'}, {'a': 'Cancel'}, {'gone': '已刪除的鍵'}),
        ['[en] 白名單已過期（不再與 zh_TW 相同、也不含中文字元，或鍵已不存在）：gone'],
      );
    });
  });
}
```

- [ ] **Step 2：跑測試確認失敗**

Run: `flutter test test/l10n/arb_consistency_helpers_test.dart`
Expected：編譯失敗，`arb_consistency_helpers.dart` 不存在。

- [ ] **Step 3：實作偵測函式**

建立 `app/test/l10n/arb_consistency_helpers.dart`：

```dart
import 'dart:convert';
import 'dart:io';

/// ARB 一致性守衛的偵測邏輯（`epic-54-architecture-optimization` Issue 6）。
///
/// 每個 `*Violations` 函式都是純函式，回傳「違規訊息」清單，空清單代表沒有
/// 違規；真實 ARB 的檢查見 `arb_consistency_test.dart`，這些函式自身會不會
/// 抓到違規，由 `arb_consistency_helpers_test.dart` 用合成資料證明（真實
/// 資料目前全數通過，光跑真實檔案看不出守衛抓不抓得到）。

/// 從 `{name}`、`{name, plural, ...}` 抽出 placeholder 名稱。已驗證在全部
/// 鍵上與 template 的 `@key.placeholders` 宣告零差異。已知限制：ICU `select`
/// 或 `plural` 的單字分支（如 `=0{None}`、`{He}`）會被誤判成 placeholder，
/// 測試會報錯。遇到時把分支寫成含空格的片語（如 `=0{no items}`）即可避開；
/// 尾隨空格（`{None }`）無效，因為 `\s*` 會吃掉空格。現有 18 個 plural 鍵
/// 不受影響。
final RegExp _placeholderPattern = RegExp(r'\{\s*(\w+)\s*(?:,|\})');

final RegExp _cjkPattern = RegExp(r'[一-鿿]');

/// 去掉 `@@locale` 與所有 `@key` 中繼資料，回傳「鍵 → 字串」。
Map<String, String> messagesOf(Map<String, dynamic> arb) => {
      for (final entry in arb.entries)
        if (!entry.key.startsWith('@') && entry.value is String)
          entry.key: entry.value as String,
    };

/// 讀取 ARB 檔並呼叫 [messagesOf]。涉及檔案 I/O，不在合成資料測試內覆蓋，
/// 由 `arb_consistency_test.dart` 讀真實 ARB 時一併驗證。
Map<String, String> loadArbMessages(String path) {
  final json =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return messagesOf(json);
}

/// 字串內所有 placeholder 名稱（含 ICU plural 巢狀分支內的）。
Set<String> placeholderNames(String message) => {
      for (final match in _placeholderPattern.allMatches(message))
        match.group(1)!,
    };

String _sorted(Iterable<String> items) => (items.toList()..sort()).join(', ');

/// [other] 相對 [base]（zh_TW）缺了哪些鍵、多了哪些鍵。
List<String> keySetViolations(
  String label,
  Map<String, String> base,
  Map<String, String> other,
) {
  final missing = base.keys.where((k) => !other.containsKey(k));
  final extra = other.keys.where((k) => !base.containsKey(k));
  return [
    if (missing.isNotEmpty) '[$label] 缺鍵：${_sorted(missing)}',
    if (extra.isNotEmpty) '[$label] 多鍵：${_sorted(extra)}',
  ];
}

/// 兩邊都有的鍵，placeholder 名稱集合是否一致。只存在於一邊的鍵交給
/// [keySetViolations]，這裡不重複回報。
List<String> placeholderViolations(
  String label,
  Map<String, String> base,
  Map<String, String> other,
) {
  final violations = <String>[];
  for (final key in (base.keys.toList()..sort())) {
    final otherMessage = other[key];
    if (otherMessage == null) continue;
    final baseNames = _sorted(placeholderNames(base[key]!));
    final otherNames = _sorted(placeholderNames(otherMessage));
    if (baseNames != otherNames) {
      violations.add(
        '[$label] 鍵 $key 的 placeholder 不一致：'
        'zh_TW={$baseNames}，$label={$otherNames}',
      );
    }
  }
  return violations;
}

/// `app_zh.arb` 只是 gen-l10n 要求的 base fallback，沒有獨立翻譯，必須與
/// zh_TW 逐字相同。
List<String> zhMirrorViolations(
  Map<String, String> base,
  Map<String, String> zh,
) {
  final differing = base.keys.where(
    (k) => zh.containsKey(k) && zh[k] != base[k],
  );
  return [
    if (differing.isNotEmpty) '[zh] 與 zh_TW 文字不同的鍵：${_sorted(differing)}',
  ];
}

/// `en` 的值與 zh_TW 相同、或含中文字元，視為漏翻；[allowlist]（鍵 → 理由）
/// 內的鍵例外。白名單項目若不再命中（或鍵已不存在）視為過期，同樣回報。
List<String> enUntranslatedViolations(
  Map<String, String> base,
  Map<String, String> en,
  Map<String, String> allowlist,
) {
  bool suspicious(String key) {
    final value = en[key];
    if (value == null) return false;
    return value == base[key] || _cjkPattern.hasMatch(value);
  }

  final untranslated =
      en.keys.where((k) => suspicious(k) && !allowlist.containsKey(k));
  final stale = allowlist.keys.where((k) => !suspicious(k));
  return [
    if (untranslated.isNotEmpty)
      '[en] 疑似漏翻（與 zh_TW 相同或含中文字元）：${_sorted(untranslated)}',
    if (stale.isNotEmpty)
      '[en] 白名單已過期（不再與 zh_TW 相同、也不含中文字元，或鍵已不存在）：${_sorted(stale)}',
  ];
}
```

- [ ] **Step 4：跑測試確認通過**

Run: `flutter test test/l10n/arb_consistency_helpers_test.dart`
Expected：全部通過（共 21 個測試）。

- [ ] **Step 5：分析並提交**

```bash
flutter analyze
git add test/l10n/arb_consistency_helpers.dart test/l10n/arb_consistency_helpers_test.dart
git commit -m "test(l10n): ARB 一致性偵測函式與合成資料測試（epic-54 Issue 6）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`No issues found!`

---

### Task 2：對真實四份 ARB 的守衛測試

**Files：**
- Create: `app/test/l10n/arb_consistency_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `loadArbMessages`、`keySetViolations`、`placeholderViolations`、`zhMirrorViolations`、`enUntranslatedViolations`（簽章見 Task 1）。
- Produces：無（終點）。

- [ ] **Step 1：寫測試**

建立 `app/test/l10n/arb_consistency_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'arb_consistency_helpers.dart';

/// `en` 的值刻意與 zh_TW 相同或含中文字元的鍵（鍵 → 理由）。
///
/// 新增項目前先確認真的不該翻譯（專有名詞、語言自稱等），不要為了讓測試
/// 通過就把漏翻的鍵加進來。項目若不再命中（字串已不同、鍵已刪）測試會失敗，
/// 請一併移除。
const Map<String, String> _enAllowlist = {
  'settingsLanguageZhTW': '語言選單中各語言的自稱，刻意不翻譯（zh_TW 與 en 皆為「正體中文」）',
  'settingsLanguageZhCN': '語言選單中各語言的自稱，刻意不翻譯（zh_TW 與 en 皆為「简体中文」）',
  'settingsLanguageEn': '語言選單中各語言的自稱，刻意不翻譯（zh_TW 與 en 皆為「English」）',
};

void main() {
  // `flutter test` 的工作目錄是 app/，與 test/library/book_content_fingerprint_test.dart
  // 讀 test/fixtures/sample.epub 的既有慣例相同。
  final base = loadArbMessages('lib/l10n/app_zh_TW.arb');
  final zh = loadArbMessages('lib/l10n/app_zh.arb');
  final en = loadArbMessages('lib/l10n/app_en.arb');
  final zhCN = loadArbMessages('lib/l10n/app_zh_CN.arb');
  final others = {'zh': zh, 'en': en, 'zh_CN': zhCN};

  void expectNoViolations(List<String> violations) {
    expect(violations, isEmpty, reason: '\n${violations.join('\n')}');
  }

  test('zh／en／zh_CN 與 zh_TW 的鍵集合一致', () {
    expectNoViolations([
      for (final entry in others.entries)
        ...keySetViolations(entry.key, base, entry.value),
    ]);
  });

  test('zh／en／zh_CN 與 zh_TW 的 placeholder 名稱集合一致', () {
    expectNoViolations([
      for (final entry in others.entries)
        ...placeholderViolations(entry.key, base, entry.value),
    ]);
  });

  test('zh 與 zh_TW 逐字相同（zh 只是 gen-l10n 要求的 base fallback）', () {
    expectNoViolations(zhMirrorViolations(base, zh));
  });

  test('en 沒有漏翻（與 zh_TW 相同或含中文字元者須列白名單，且白名單不得過期）', () {
    expectNoViolations(enUntranslatedViolations(base, en, _enAllowlist));
  });
}
```

- [ ] **Step 2：跑測試確認通過**

Run: `flutter test test/l10n/arb_consistency_test.dart`
Expected：4 個測試通過。**若有任何一個失敗，代表真實 ARB 已有漂移**：停下來，把失敗訊息原樣回報給使用者，不要修改 ARB 或放寬規則。

- [ ] **Step 3：分析並提交**

```bash
flutter analyze
git add test/l10n/arb_consistency_test.dart
git commit -m "test(l10n): 四份 ARB 一致性守衛（epic-54 Issue 6）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`No issues found!`

---

### Task 3：變異驗證、文件、全套測試

**Files：**
- Modify: `app/tool/README.md`（第 47 行與第 53 行附近）
- Modify: `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md`

**Interfaces：**
- Consumes：Task 1、2 全部完成。
- Produces：可發 PR 的分支。

- [ ] **Step 1：變異驗證（對真實檔案暫時改壞，確認守衛會失敗，再還原）**

每次改壞後跑 `flutter test test/l10n/arb_consistency_test.dart`，預期對應的測試失敗、訊息指出被改的鍵；確認後立刻 `git checkout -- lib/l10n/<檔名>` 還原。四種變異（在 `app/` 下執行）：

```bash
# 1. en 漏鍵：刪掉 cancel
node -e 'const fs=require("fs");const p="lib/l10n/app_en.arb";const j=JSON.parse(fs.readFileSync(p,"utf8"));delete j.cancel;fs.writeFileSync(p,JSON.stringify(j,null,2))'
flutter test test/l10n/arb_consistency_test.dart   # 預期：鍵集合測試失敗，訊息含「[en] 缺鍵：cancel」
git checkout -- lib/l10n/app_en.arb

# 2. en 漏翻：把 cancel 設成與 zh_TW 相同
node -e 'const fs=require("fs");const r=n=>JSON.parse(fs.readFileSync("lib/l10n/"+n+".arb","utf8"));const tw=r("app_zh_TW"),en=r("app_en");en.cancel=tw.cancel;fs.writeFileSync("lib/l10n/app_en.arb",JSON.stringify(en,null,2))'
flutter test test/l10n/arb_consistency_test.dart   # 預期：en 漏翻測試失敗，訊息含「疑似漏翻…：cancel」
git checkout -- lib/l10n/app_en.arb

# 3. placeholder 漏參數：把 zh_CN 第一個帶 {…} 的鍵的 placeholder 拿掉
node -e 'const fs=require("fs");const r=n=>JSON.parse(fs.readFileSync("lib/l10n/"+n+".arb","utf8"));const cn=r("app_zh_CN");const k=Object.keys(cn).find(x=>!x.startsWith("@")&&/\{\s*\w+\s*[,}]/.test(cn[x]));console.log("改壞的鍵:",k);cn[k]="（已移除參數）";fs.writeFileSync("lib/l10n/app_zh_CN.arb",JSON.stringify(cn,null,2))'
flutter test test/l10n/arb_consistency_test.dart   # 預期：placeholder 測試失敗，訊息含該鍵
git checkout -- lib/l10n/app_zh_CN.arb

# 4. zh 偏離：改 zh 的 cancel
node -e 'const fs=require("fs");const p="lib/l10n/app_zh.arb";const j=JSON.parse(fs.readFileSync(p,"utf8"));j.cancel=j.cancel+"X";fs.writeFileSync(p,JSON.stringify(j,null,2))'
flutter test test/l10n/arb_consistency_test.dart   # 預期：zh 逐字相同測試失敗，訊息含「[zh] 與 zh_TW 文字不同的鍵：cancel」
git checkout -- lib/l10n/app_zh.arb
```

全部還原後確認：`git status --short` 無輸出，`flutter test test/l10n/arb_consistency_test.dart` 4 個全數通過。把四種變異各自是否如預期失敗記在開發記錄。

- [ ] **Step 2：更新 `tool/README.md`**

用 Edit 工具，兩處單行替換（定位字串不含換行）：

1. 把 `（四份 key 集合必須一致），執行` 改為 `（四份 key 集合必須一致，由 \`test/l10n/arb_consistency_test.dart\` 守衛），執行`。
2. 在 `` `ALLOWED_LITERAL_VALUES` 並註明理由。 `` 這一行之後新增一個步驟：

```markdown
4. ARB 本身的一致性（四份鍵集合與 `{placeholder}` 名稱一致、`app_zh.arb` 與
   `app_zh_TW.arb` 逐字相同、`app_en.arb` 沒有漏翻）由
   `app/test/l10n/arb_consistency_test.dart` 守衛，隨 `flutter test` 執行，不需另外跑腳本。
   若 `en` 的值**刻意**與 zh_TW 相同或含中文（例如語言自稱），把鍵與理由加進該測試的
   `_enAllowlist`；項目不再命中時測試會要求移除。
```

- [ ] **Step 3：分析、l10n 守衛、全套測試**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

Expected：`No issues found!`；腳本兩行 PASS。再跑完整測試（`run_in_background`，約 6 分鐘）：`flutter test`。Expected：全部通過、1 略過。若 `test/downloads/download_queue_controller_test.dart` 出現固定輪數 `pumpEventQueue()` 造成的偶發失敗（Issue 4 已記錄的既有不穩定測試），單獨重跑該檔確認，再重跑全套，並在記錄中註明。

- [ ] **Step 4：更新開發記錄並提交**

在 `epic.md` 開發記錄末尾新增「Issue 6 實作完成」段落，寫明：新增三個測試檔與測試數量（helpers 21 個、守衛 4 個）；變異驗證四種結果；驗證結果（`flutter analyze`、`check_l10n_hardcoded_strings.js`、全套測試數字）；行為變動：無；待真機確認：無。`issues.md` 與 `docs/epics.md` 的 Issue 6 標為「待發 PR」。

```bash
git add tool/README.md ../docs
git commit -m "docs(epic-54): Issue 6 實作記錄與 tool/README 補充，準備程式審查

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

程式審查依 CLAUDE.md 慣例：獨立審查員先出報告到 `reviews/review-code-issue-6.md`，不直接改程式；發 PR 前須取得使用者確認。
