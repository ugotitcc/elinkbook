# Epic 41 Issue 4：抽出 splitHighlightSegments 純函式 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `BookSearchScreen._buildHighlightedText()`（`book_search_screen.dart:347-394`）內「找出命中位置、切成片段」這段純演算法抽成公開頂層函式 `splitHighlightSegments()`，讓它脫離 `BuildContext`／E-Ink 模式，可被獨立單元測試覆蓋；`_buildHighlightedText()` 改為只負責把切分結果轉成有樣式的 `TextSpan`。

**Architecture:** 新增 `app/lib/search/highlight_segments.dart`，內含一個值相等（`operator ==`/`hashCode`）的 `HighlightSegment` 類別與純函式 `splitHighlightSegments(String text, String query)`。`BookSearchScreen` 改為呼叫這個純函式取得片段清單，再依 `widget.isEinkMode` 決定每個命中片段的樣式（粗體+底線 vs 粗體+背景色），組成 `TextSpan` 清單。純函式邏輯與 widget 樣式邏輯完全分離，前者可用普通 `flutter_test`（不需 `testWidgets`）驗證，後者維持既有 widget test 驗證零回歸。

**Tech Stack:** Flutter/Dart，`flutter_test`（純 Dart 單元測試驗證 `splitHighlightSegments()` 本身；既有 `testWidgets` 驗證 `BookSearchScreen` 呼叫端零回歸，含最近的字級回歸測試）。

**Spec:** `docs/epics/epic-41-search-architecture-hardening/issues.md`（Issue 4 段落，已依 `reviews/review-epic-and-issues.md` M-1 修訂——`HighlightSegment` 須為公開頂層型別、補齊 `operator ==`/`hashCode`）。

## Global Constraints

- 所有新增/修改的程式碼註解與本計畫文件一律使用正體中文（zh-TW），不得使用簡體中文（使用者全域 CLAUDE.md 規則）。
- `splitHighlightSegments()` 必須是**公開頂層函式**（不可設為 `book_search_screen.dart` 內的私有函式）——放在新檔案 `app/lib/search/highlight_segments.dart`，讓 `test/search/highlight_segments_test.dart` 可以直接 import 使用，不需要透過 widget tree 間接驗證。
- `HighlightSegment` 必須補齊 `operator ==`／`hashCode`（`@immutable` 標註），否則單元測試裡 `expect(segments, [HighlightSegment(...), ...])` 這種清單比對會因為預設參照相等而永遠失敗。
- `splitHighlightSegments()` **不依賴** `BuildContext`／`Theme`／E-Ink 模式——純粹輸入 `text`／`query` 兩個字串，回傳「這段文字要不要標記為命中」的序列；樣式決定完全留在 `_buildHighlightedText()`。
- **不改動** `app/lib/screens/library_search_screen.dart`——`spec.md` §9.2 刻意決定 `LibrarySearchScreen` 的內容匹配片段不做高亮（`_buildContentGroupCard` 維持純 `Text(snippet)`），本 Issue 範圍邊界已由 `/grilling` Q6 確認，不擴大範圍。
- `_buildHighlightedText()` 重構後**必須保留既有的字級 bug 修復語意**（commit `b6cd0b7f`）：完全沒有命中（含 `query` 為空、或 `query` 在 `text` 中找不到）時回傳純 `Text(text)`，不得用 `Text.rich(TextSpan(text: text))`；有命中時才用 `Text.rich(TextSpan(children: spans))`，且非命中片段的 `TextSpan` 一律不手動指定 `style`（維持 `null`，讓 `Text.rich` 走它自己掛載時的 `DefaultTextStyle` 繼承）。
- 每個 Task 只跑「這次異動實際觸及」的測試檔；只在**最後一個 Task**（Task 2）跑一次完整 `flutter analyze`／`flutter test` 作最終確認（專案 `CLAUDE.md`「測試執行範圍」既有慣例）。
- Git commit 訊息結尾需附加下列兩行（本次 session 的固定 attribution，見系統提示）：
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
  ```

---

### Task 1: 新增 `splitHighlightSegments()` 純函式

**Files:**
- Create: `app/lib/search/highlight_segments.dart`
- Test: `app/test/search/highlight_segments_test.dart`（新檔案）

**Interfaces:**
- Consumes：無（純 Dart 字串運算，不依賴專案內任何既有型別）。
- Produces（供 Task 2 呼叫）：
  ```dart
  @immutable
  class HighlightSegment {
    final String text;
    final bool isMatch;
    const HighlightSegment(this.text, this.isMatch);
    // operator == / hashCode 依 text/isMatch 值比對
  }

  List<HighlightSegment> splitHighlightSegments(String text, String query);
  ```

- [x] **Step 1: 寫失敗測試**

建立 `app/test/search/highlight_segments_test.dart`：

```dart
// app/test/search/highlight_segments_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/search/highlight_segments.dart';

void main() {
  group('splitHighlightSegments', () {
    test('query 為空字串時，回傳單一非命中片段，內容為整段原文', () {
      final segments = splitHighlightSegments('第1章含有搜尋關鍵字的文本片段', '');

      expect(segments, [
        const HighlightSegment('第1章含有搜尋關鍵字的文本片段', false),
      ]);
    });

    test('text 為空字串時，回傳單一非命中片段，內容為空字串', () {
      final segments = splitHighlightSegments('', '關鍵字');

      expect(segments, [const HighlightSegment('', false)]);
    });

    test('找不到任何命中時，回傳單一非命中片段，內容為整段原文', () {
      final segments = splitHighlightSegments('這段文字完全沒有目標', '關鍵字');

      expect(segments, [const HighlightSegment('這段文字完全沒有目標', false)]);
    });

    test('大小寫不敏感比對：query 為大寫，text 為小寫仍應命中', () {
      final segments = splitHighlightSegments('hello world', 'WORLD');

      expect(segments, [
        const HighlightSegment('hello ', false),
        const HighlightSegment('world', true),
      ]);
    });

    test('命中位置在字串開頭：不產生開頭的空白非命中片段', () {
      final segments = splitHighlightSegments('關鍵字出現在最前面', '關鍵字');

      expect(segments, [
        const HighlightSegment('關鍵字', true),
        const HighlightSegment('出現在最前面', false),
      ]);
    });

    test('命中位置在字串結尾：不產生結尾的空白非命中片段', () {
      final segments = splitHighlightSegments('最後面出現關鍵字', '關鍵字');

      expect(segments, [
        const HighlightSegment('最後面出現', false),
        const HighlightSegment('關鍵字', true),
      ]);
    });

    test('整段文字剛好等於 query 時，回傳單一命中片段', () {
      final segments = splitHighlightSegments('關鍵字', '關鍵字');

      expect(segments, [const HighlightSegment('關鍵字', true)]);
    });

    test('多個命中：命中之間夾雜非命中片段', () {
      final segments = splitHighlightSegments('關鍵字A普通文字關鍵字B', '關鍵字');

      expect(segments, [
        const HighlightSegment('關鍵字', true),
        const HighlightSegment('A普通文字', false),
        const HighlightSegment('關鍵字', true),
        const HighlightSegment('B', false),
      ]);
    });

    test('命中緊鄰邊界：連續兩次命中之間沒有非命中片段', () {
      final segments = splitHighlightSegments('aaaa', 'aa');

      expect(segments, [
        const HighlightSegment('aa', true),
        const HighlightSegment('aa', true),
      ]);
    });

    test('大小寫混合比對：text 為大寫，query 為小寫時仍應命中並保留原文大小寫', () {
      final segments = splitHighlightSegments('EPUB 規範說明', 'epub');

      expect(segments, [
        const HighlightSegment('EPUB', true),
        const HighlightSegment(' 規範說明', false),
      ]);
    });
  });

  group('HighlightSegment', () {
    test('支援值相等性與 hashCode（防止實作漏比欄位或漏寫 hashCode）', () {
      const seg1 = HighlightSegment('文字', true);
      const seg2 = HighlightSegment('文字', true);
      const segDiffMatch = HighlightSegment('文字', false);
      const segDiffText = HighlightSegment('其他', true);

      expect(seg1, equals(seg2));
      expect(seg1.hashCode, equals(seg2.hashCode));
      expect(seg1, isNot(equals(segDiffMatch)));
      expect(seg1, isNot(equals(segDiffText)));
      expect({seg1, seg2}.length, 1);
    });
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `cd app && flutter test test/search/highlight_segments_test.dart`
Expected: FAIL（編譯錯誤，找不到 `package:elinkbook/search/highlight_segments.dart`）

- [x] **Step 3: 寫最小實作**

建立 `app/lib/search/highlight_segments.dart`：

```dart
// app/lib/search/highlight_segments.dart
import 'package:flutter/foundation.dart';

/// 高亮切分後的其中一段文字（epic-41-search-architecture-hardening
/// Issue 4）：[isMatch] 為 `true` 代表這段文字是命中 query 的部分，
/// 呼叫端依此決定是否套用高亮樣式。純資料物件，不含任何樣式資訊。
@immutable
class HighlightSegment {
  final String text;
  final bool isMatch;

  const HighlightSegment(this.text, this.isMatch);

  @override
  bool operator ==(Object other) =>
      other is HighlightSegment &&
      other.text == text &&
      other.isMatch == isMatch;

  @override
  int get hashCode => Object.hash(text, isMatch);

  @override
  String toString() => 'HighlightSegment($text, isMatch: $isMatch)';
}

/// 在 [text] 中找出 [query] 出現的所有位置（case-insensitive），依命中與否
/// 切成一連串片段。純函式，不依賴 `BuildContext`／樣式——原本混在
/// `BookSearchScreen._buildHighlightedText()` 裡的字串演算法（見
/// epic-41-search-architecture-hardening Issue 4），抽出後可獨立單元測試。
///
/// [query] 為空字串，或在 [text] 中找不到任何命中時，回傳單一非命中片段
/// （內容為整段 [text]，可能是空字串）——呼叫端可用這個特徵判斷「完全沒有
/// 需要高亮的內容」。
List<HighlightSegment> splitHighlightSegments(String text, String query) {
  if (query.isEmpty || text.isEmpty) return [HighlightSegment(text, false)];

  final lowerText = text.toLowerCase();
  final lowerQuery = query.toLowerCase();
  final segments = <HighlightSegment>[];
  var start = 0;

  while (start < text.length) {
    final matchIndex = lowerText.indexOf(lowerQuery, start);
    if (matchIndex < 0) {
      segments.add(HighlightSegment(text.substring(start), false));
      break;
    }
    if (matchIndex > start) {
      segments.add(HighlightSegment(text.substring(start, matchIndex), false));
    }
    // matchIndex 是在 lowerText 中對 lowerQuery 搜尋得到的結果，這裡改用
    // query.length（而非 lowerQuery.length）取出原始大小寫的命中片段；
    // toLowerCase() 對兩者的長度轉換同源、恆等，故長度可互換使用。
    final matchEnd = matchIndex + query.length;
    segments.add(HighlightSegment(text.substring(matchIndex, matchEnd), true));
    start = matchEnd;
  }

  if (segments.isEmpty) return [HighlightSegment(text, false)];
  return segments;
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/search/highlight_segments_test.dart`
Expected: PASS（11 個測試案例全數通過）

- [x] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/search/highlight_segments.dart test/search/highlight_segments_test.dart`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/search/highlight_segments.dart app/test/search/highlight_segments_test.dart
git commit -m "$(cat <<'EOF'
feat(search): 新增 splitHighlightSegments 純函式抽出高亮切分演算法（epic-41 Issue 4 Task 1）

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

---

### Task 2: `BookSearchScreen` 改用 `splitHighlightSegments()`，並跑全套驗證收尾

**Files:**
- Modify: `app/lib/screens/book_search_screen.dart:1-15`（新增 import）、`:347-394`（`_buildHighlightedText()` 方法本體，含 doc comment 與結尾大括號）
- Test: `app/test/screens/book_search_screen_test.dart`（既有測試，不新增案例）

**Interfaces:**
- Consumes：Task 1 產出的 `HighlightSegment`／`splitHighlightSegments()`。

- [x] **Step 1: 新增 import**

在 `app/lib/screens/book_search_screen.dart` 開頭 import 區塊，原本：

```dart
import '../reader/reader_jump_target.dart';
import '../reader/reader_prefs_manager.dart';
import '../search/search_repository.dart';
```

改為：

```dart
import '../reader/reader_jump_target.dart';
import '../reader/reader_prefs_manager.dart';
import '../search/highlight_segments.dart';
import '../search/search_repository.dart';
```

- [x] **Step 2: 改寫 `_buildHighlightedText()`**

在 `app/lib/screens/book_search_screen.dart:347-394`，原本：

```dart
  /// 關鍵字高亮：在 [text] 中找到 [query] 出現的所有位置（case-insensitive），
  /// 命中段加粗；非 E-Ink 模式搭配淡色背景，E-Ink 模式搭配底線（高對比、
  /// 避免電子紙殘影）。spec.md §9.3。使用 Text.rich 支援系統文字縮放。
  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) return Text(text);

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;

    while (start < text.length) {
      final matchIndex = lowerText.indexOf(lowerQuery, start);
      if (matchIndex < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (matchIndex > start) {
        final safeStart = start.clamp(0, text.length);
        final safeMatch = matchIndex.clamp(0, text.length);
        spans.add(TextSpan(text: text.substring(safeStart, safeMatch)));
      }
      final matchEnd = (matchIndex + query.length).clamp(0, text.length);
      final safeMatchIndex = matchIndex.clamp(0, text.length);
      spans.add(TextSpan(
        text: text.substring(safeMatchIndex, matchEnd),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          backgroundColor:
              widget.isEinkMode ? null : Theme.of(context).colorScheme.primaryContainer,
          decoration: widget.isEinkMode ? TextDecoration.underline : null,
        ),
      ));
      start = matchEnd;
    }

    if (spans.isEmpty) return Text(text);
    // 【/diagnose：全書搜尋結果符合文字部分變得特別大】不可在此手動指定
    // style: DefaultTextStyle.of(context).style——這裡的 context 是
    // _BookSearchScreenState 自己的 build context，位於本畫面 Scaffold/
    // Material 之上、尚未進入 ListTile 標題實際掛載位置，解析出來的並非
    // ListTile 的正常字級，而是 MaterialApp 特意設計、用來提醒開發者
    // 「文字未包在 Material 內」的 48px 紅色錯誤警示字級（見
    // flutter/material/app.dart `_errorTextStyle`）。留空讓 Text.rich
    // 用它自己實際掛載時的 context 走正常 DefaultTextStyle 繼承，字級才會
    // 與同一份清單裡的一般 Text（無高亮）一致。
    return Text.rich(TextSpan(children: spans));
  }
```

改為：

```dart
  /// 關鍵字高亮：在 [text] 中找到 [query] 出現的所有位置（case-insensitive），
  /// 命中段加粗；非 E-Ink 模式搭配淡色背景，E-Ink 模式搭配底線（高對比、
  /// 避免電子紙殘影）。spec.md §9.3。使用 Text.rich 支援系統文字縮放。
  /// 命中位置切分邏輯已抽至 [splitHighlightSegments]（epic-41 Issue 4），
  /// 本方法只負責把切分結果轉成有樣式的 TextSpan。
  Widget _buildHighlightedText(String text, String query) {
    final segments = splitHighlightSegments(text, query);
    final hasMatch = segments.any((segment) => segment.isMatch);
    if (!hasMatch) {
      // 完全沒有命中（含 query 為空字串）：直接回傳純 Text，不得改用
      // Text.rich(TextSpan(text: text))——【/diagnose：全書搜尋結果符合
      // 文字部分變得特別大】的字級 bug 修復只保護「有命中片段」這條路徑
      // （見下方 spans 分支的說明），這條無高亮路徑本來就沒有手動指定過
      // style，維持現狀即可。用 any(isMatch) 判斷而非假設 segments 長度，
      // 不耦合 splitHighlightSegments 內部「無命中時剛好回傳單一片段」的
      // 實作細節。
      return Text(text);
    }

    final spans = [
      for (final segment in segments)
        TextSpan(
          text: segment.text,
          style: segment.isMatch
              ? TextStyle(
                  fontWeight: FontWeight.bold,
                  backgroundColor: widget.isEinkMode
                      ? null
                      : Theme.of(context).colorScheme.primaryContainer,
                  decoration: widget.isEinkMode ? TextDecoration.underline : null,
                )
              : null,
        ),
    ];

    // 【/diagnose：全書搜尋結果符合文字部分變得特別大】不可在此手動指定
    // style: DefaultTextStyle.of(context).style——這裡的 context 是
    // _BookSearchScreenState 自己的 build context，位於本畫面 Scaffold/
    // Material 之上、尚未進入 ListTile 標題實際掛載位置，解析出來的並非
    // ListTile 的正常字級，而是 MaterialApp 特意設計、用來提醒開發者
    // 「文字未包在 Material 內」的 48px 紅色錯誤警示字級（見
    // flutter/material/app.dart `_errorTextStyle`）。留空讓 Text.rich
    // 用它自己實際掛載時的 context 走正常 DefaultTextStyle 繼承，字級才會
    // 與同一份清單裡的一般 Text（無高亮）一致。
    return Text.rich(TextSpan(children: spans));
  }
```

- [x] **Step 3: 執行既有回歸測試**

Run: `cd app && flutter test test/screens/book_search_screen_test.dart`
Expected: PASS（全數通過，含 `test/screens/book_search_screen_test.dart:402-443` 字級回歸測試——這個測試實際 pump 真實 `BookSearchScreen` 並量測 `find.byKey(const Key('book_search_snippet_0'))` 的實際渲染高度，是本次重構「高亮渲染行為完全不變」的關鍵證據）

- [x] **Step 4: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/book_search_screen.dart`
Expected: `No issues found!`

- [x] **Step 5: 跑完整 `flutter analyze`／`flutter test` 作最終確認**

本 Issue 兩個 Task 皆完成，依專案慣例在最後一個 Task 跑一次全套驗證：

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數通過（新增 11 個 `highlight_segments_test.dart` 測試案例後，全庫測試總數為 Issue 3 合併後的既有基準淨增 +11；失敗數維持 2 且必須是同樣兩個 `adaptive_shell_scaffold_test.dart` 既有案例，不可出現新的失敗）。

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/book_search_screen.dart
git commit -m "$(cat <<'EOF'
refactor(search): BookSearchScreen 高亮邏輯改用 splitHighlightSegments()（epic-41 Issue 4 Task 2）

_buildHighlightedText() 的命中位置切分演算法已收斂為呼叫獨立的純函式
splitHighlightSegments()，本方法只保留「切分結果轉樣式」這層 widget 邏輯。
LibrarySearchScreen 未變動（spec.md §9.2 既有決定）。
flutter analyze/flutter test 全數通過，零回歸。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01X2e4fg8iDx8VoshjLi95gk
EOF
)"
```

- [x] **Step 7: 更新工單狀態**

在 `docs/epics/epic-41-search-architecture-hardening/issues.md` 的 Issue 4 段落，依專案既有看板慣例，把 `**Status:** ready-for-agent` 改為：

```
**Status:** completed（`plans/plan-issue-4.md` 2 個 Task 全數完成，新增 `splitHighlightSegments()` 純函式，`BookSearchScreen` 已改用，`LibrarySearchScreen` 未變動，`flutter analyze`/`flutter test` 全數通過零回歸）
```

同步在 `epic.md` 的開發記錄追加一句「Issue 4 已完成」。
