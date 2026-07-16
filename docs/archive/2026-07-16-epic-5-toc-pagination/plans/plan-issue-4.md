# Epic 5 Issue 4：EPUB 目錄（TOC）樹狀清單 + 跳轉 + 估算頁碼顯示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為流式 EPUB 新增可展開／收起的層級目錄樹狀清單（Bottom Sheet），每項顯示標題與估算頁碼，點擊於 200ms 內跳轉至對應位置；PDF 與固定版面（FXL）EPUB 完全不顯示目錄入口。

**Architecture:** 原生端（`EpubReaderView.kt`）新增 `getTableOfContents`（一次性讀取 `Publication.tableOfContents`，透過 `Publication.locatorFromLink(Link)` 為每個節點建構精確 Locator——已反編譯 `readium-shared:3.3.0` 確認此 API 存在，解決 design.md 原本列為「已知風險」的不確定性）與 `jumpToLocator`（依序列化 Locator 直接呼叫 `Navigator.go()`）兩個 method channel 指令。頁碼估算優先取用 Locator 自身的 `totalProgression`，缺漏時退回比對既有 `Publication.positions()`（`jumpToProgression` 已建立的先例）尋找同一 resource 的位置作為近似值。Dart 端新增純資料模型 `TocEntry` 與純函式 `TocNavigator.findCurrentPath`（找出目前章節在整棵樹裡的祖先路徑，供 UI 決定預設展開哪些層級與高亮哪個項目），以及一個獨立、可脫離 `ReaderScreen` 直接單元測試的 `TocBottomSheet` StatefulWidget（自行管理展開/收起狀態，與 Readium 導覽用的精確 Locator 分離、與 Readium 全書進度比例分離，UI 互動與資料完全解耦）。`ReaderScreen` 在 `onLayoutResolved` 回報非固定版面時預先背景抓取目錄（樹狀結構不隨版面設定變動，不需重算），並新增一個 `ValueNotifier<int?>` 讓已開啟的目錄 Bottom Sheet 能在全書字元數背景計算完成當下即時更新頁碼，不需使用者重新開啟。

**Tech Stack:** Flutter/Dart（`app/lib/`）、Kotlin + Readium `kotlin-toolkit:3.3.0`（`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/`）、Kotlin Coroutines（`Dispatchers.IO`）、`flutter_test`／`integration_test`。

## Global Constraints

- 目錄僅支援流式 EPUB，PDF 完全不顯示目錄入口；固定版面（FXL）EPUB 也不顯示（spec.md「範圍界定」：「目錄（TOC）僅支援流式 EPUB」；issues.md Issue 4：「為流式 EPUB 讀取書籍引擎提供的目錄樹狀結構」）。
- PDF／FXL 隱藏目錄入口一律沿用 `ReaderScreen` 既有的 `_buildAppBarActions(format)` 動態渲染機制與既有的「`_isFixedLayout` 時整個 AppBar actions 回傳 `null`」機制，不新增第二套 AppBar 渲染路徑（design.md 決策 #2，審查修正）。
- 目錄項目跳轉須於 200ms 內完成（FR-08）；`jumpToLocator` 在原生端一律同步呼叫 `Navigator.go()`，不透過背景協程分派，避免額外的 dispatcher 跳轉開銷。
- 全書字元數尚未計算完成時（`totalCharacterCount == null`），目錄項目的頁碼區塊顯示佔位符（`…`）；背景計算完成後，若目錄 Bottom Sheet 仍開著，須即時更新頁碼，不需使用者手動關閉重開（spec.md「目錄模組」、design.md 決策 #18）。
- 當前章節所屬層級（含自身的完整祖先路徑）預設展開，其餘收起；當前章節項目本身需視覺高亮（design.md 決策 #10、spec.md「目錄模組」）。
- 目錄樹狀結構完整保留 `Publication.tableOfContents` 的巢狀階層，不攤平（design.md 決策 #10）。
- 跨 `State` 私有邊界呼叫一律透過強型別 static helper，不使用 `as dynamic`（比照 `PdfReaderView.jumpToPage`／`EpubReaderView.jumpToProgression` 既有模式）。
- 不修改 `ReaderFooter`／`EpubPageEstimator`／既有 Issue 1-3 建立的元件內部邏輯（僅新增呼叫端使用，例如複用 `EpubPageEstimator.estimateCurrentPage`／`estimateTotalPages`／`estimateCharsPerScreen`）。
- 本工單不修改 PDF 讀取畫面既有行為。
- 每個 Task 完成後 `flutter analyze`（Dart 變更）或對應 Kotlin 編譯需保持乾淨，既有測試（`flutter test`）不可回歸。

---

### Task 1: `TocEntry` + `TocNavigator`（Dart 端純資料模型與目前章節路徑演算法）

**Files:**
- Create: `app/lib/reader/toc_entry.dart`
- Create: `app/lib/reader/toc_navigator.dart`
- Test: `app/test/reader/toc_entry_test.dart`
- Test: `app/test/reader/toc_navigator_test.dart`

**Interfaces:**
- Produces:
  - `TocEntry({required String title, required String locatorJson, double? progression, List<TocEntry> children = const []})`——刻意不覆寫 `==`/`hashCode`（維持預設的物件識別語意），因為 `TocNavigator.findCurrentPath` 回傳的路徑與 UI 的展開狀態集合皆依賴「是否為同一個節點物件參照」判斷，不是欄位值相等。
  - `TocEntry.fromWire(Map<Object?, Object?> map) -> TocEntry`（遞迴解析原生端傳來的巢狀 map）。
  - `TocNavigator.findCurrentPath(List<TocEntry> entries, double? currentProgression) -> List<TocEntry>`。
- Consumes：無外部相依。供 Task 3（Dart `EpubReaderView`）、Task 4（`TocBottomSheet`）、Task 5（`ReaderScreen`）使用。

- [x] **Step 1: 寫失敗測試（`TocEntry.fromWire`）**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/toc_entry.dart';

void main() {
  group('TocEntry.fromWire', () {
    test('解析單層節點（無子項）', () {
      final entry = TocEntry.fromWire({
        'title': '第一章',
        'locatorJson': '{"href":"/chapter1.xhtml"}',
        'progression': 0.1,
        'children': <Object?>[],
      });

      expect(entry.title, '第一章');
      expect(entry.locatorJson, '{"href":"/chapter1.xhtml"}');
      expect(entry.progression, 0.1);
      expect(entry.children, isEmpty);
    });

    test('遞迴解析巢狀子項', () {
      final entry = TocEntry.fromWire({
        'title': '第二章',
        'locatorJson': '{"href":"/chapter2.xhtml"}',
        'progression': 0.3,
        'children': <Object?>[
          {
            'title': '第一節',
            'locatorJson': '{"href":"/chapter2.xhtml#s1"}',
            'progression': 0.35,
            'children': <Object?>[],
          },
        ],
      });

      expect(entry.children, hasLength(1));
      expect(entry.children.single.title, '第一節');
      expect(entry.children.single.progression, 0.35);
    });

    test('progression 為 null（原生端查無對應位置）時保留 null', () {
      final entry = TocEntry.fromWire({
        'title': '未知章節',
        'locatorJson': '{}',
        'progression': null,
        'children': <Object?>[],
      });

      expect(entry.progression, isNull);
    });

    test('title／locatorJson 缺失時採用空字串防呆，不拋出例外', () {
      final entry = TocEntry.fromWire({'children': <Object?>[]});

      expect(entry.title, '');
      expect(entry.locatorJson, '');
    });
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run（於 `app/` 目錄）：`flutter test test/reader/toc_entry_test.dart`
Expected: FAIL（`toc_entry.dart` 不存在，編譯錯誤）。

- [x] **Step 3: 撰寫 `TocEntry` 最小實作**

```dart
/// EPUB 目錄樹狀清單的單一節點（epic-5-toc-pagination Issue 4，spec.md
/// 「目錄模組」）：原生端一次性讀取 `Publication.tableOfContents` 後序列化
/// 傳來，保留完整巢狀階層（[children]，不攤平）。
///
/// 刻意不覆寫 `==`/`hashCode`（維持預設的物件識別語意）——[TocNavigator]
/// 回傳的「目前章節路徑」與 UI 的展開狀態集合，判斷依據都是「是否為同一個
/// 節點物件參照」，只要 `entries` 樹狀結構本身在同一次 build 週期內沒有
/// 被重新解析成新物件，物件識別語意就足夠正確，不需要值相等語意。
class TocEntry {
  final String title;

  /// 原生端 `Locator.toJSON().toString()`，透過
  /// `Publication.locatorFromLink(Link)` 建構、保留錨點精度（非僅解析到
  /// resource 起始位置）。點選項目時原樣傳回原生端 `jumpToLocator` 還原。
  final String locatorJson;

  /// 全書閱讀進度比例（0.0-1.0），供換算估算頁碼。原生端優先取用
  /// [locatorJson] 對應 Locator 自身的 `totalProgression`；查無則退回比對
  /// `Publication.positions()`，仍查無時為 `null`（此時 UI 顯示佔位符，不
  /// 視為錯誤）。
  final double? progression;

  final List<TocEntry> children;

  const TocEntry({
    required this.title,
    required this.locatorJson,
    this.progression,
    this.children = const [],
  });

  /// 遞迴解析原生端 `getTableOfContents` 回傳的巢狀 map 結構。缺失的
  /// `title`／`locatorJson` 以空字串防呆（不拋出例外），比照專案既有對
  /// MethodChannel 回傳資料的寬容解析慣例。
  factory TocEntry.fromWire(Map<Object?, Object?> map) {
    final rawChildren = map['children'] as List<Object?>? ?? const [];
    return TocEntry(
      title: map['title'] as String? ?? '',
      locatorJson: map['locatorJson'] as String? ?? '',
      progression: (map['progression'] as num?)?.toDouble(),
      children: rawChildren
          .map((e) => TocEntry.fromWire(e as Map<Object?, Object?>))
          .toList(),
    );
  }
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/toc_entry_test.dart`
Expected: PASS（全數綠燈）。

- [x] **Step 5: 寫失敗測試（`TocNavigator.findCurrentPath`）**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/toc_entry.dart';
import 'package:elinkbook/reader/toc_navigator.dart';

void main() {
  final ch1 = const TocEntry(title: 'Ch1', locatorJson: 'l1', progression: 0.0);
  final ch2s1 =
      const TocEntry(title: 'Ch2-S1', locatorJson: 'l2s1', progression: 0.35);
  final ch2s2 =
      const TocEntry(title: 'Ch2-S2', locatorJson: 'l2s2', progression: 0.45);
  final ch2 = TocEntry(
    title: 'Ch2',
    locatorJson: 'l2',
    progression: 0.3,
    children: [ch2s1, ch2s2],
  );
  final ch3 = const TocEntry(title: 'Ch3', locatorJson: 'l3', progression: 0.7);
  final entries = [ch1, ch2, ch3];

  group('findCurrentPath', () {
    test('currentProgression 為 null 時回傳空清單', () {
      expect(TocNavigator.findCurrentPath(entries, null), isEmpty);
    });

    test('落在第一個頂層章節範圍內時，回傳只含該章節的路徑', () {
      expect(TocNavigator.findCurrentPath(entries, 0.1), [ch1]);
    });

    test('落在有子章節的頂層章節、且已進入其第一個子項範圍時，回傳完整祖先路徑', () {
      expect(TocNavigator.findCurrentPath(entries, 0.4), [ch2, ch2s1]);
    });

    test('落在最後一個頂層章節範圍內時，回傳只含該章節的路徑（不誤留前面章節的子項）', () {
      expect(TocNavigator.findCurrentPath(entries, 0.9), [ch3]);
    });

    test('progression 為 0.0（第一章開頭）時仍正確判定為該章節', () {
      expect(TocNavigator.findCurrentPath(entries, 0.0), [ch1]);
    });

    test('全部節點 progression 皆大於 currentProgression 時回傳空清單', () {
      expect(TocNavigator.findCurrentPath(entries, -0.1), isEmpty);
    });
  });
}
```

- [x] **Step 6: 執行測試確認失敗**

Run: `flutter test test/reader/toc_navigator_test.dart`
Expected: FAIL（`toc_navigator.dart` 不存在，編譯錯誤）。

- [x] **Step 7: 撰寫 `TocNavigator` 最小實作**

```dart
import 'toc_entry.dart';

/// EPUB 目錄樹狀清單的目前章節判定邏輯（epic-5-toc-pagination Issue 4，
/// spec.md「目錄模組」：「當前章節所屬層級預設展開，其餘收起；當前章節
/// 項目需視覺高亮」）。純函式、無 I/O，供 `ReaderScreen` 開啟目錄前計算。
class TocNavigator {
  const TocNavigator._();

  /// 找出讀者目前所在（或剛通過）的章節，回傳從樹根到該章節的完整祖先
  /// 路徑（含自身）。演算法：對整棵樹做深度優先前序走訪（此順序即為書本
  /// 閱讀順序——子章節緊接在父章節標題之後，早於下一個同層級兄弟節點），
  /// 逐一檢查每個節點的 [TocEntry.progression]，只要 `<= currentProgression`
  /// 就把「目前累積路徑」更新為目前為止最新符合的一筆；走訪結束時保留的
  /// 即為讀者目前最深、最新通過的章節。
  ///
  /// [currentProgression] 為 `null`（例如尚未收到任何 `onLocatorChanged`
  /// 回報）或沒有任何節點的 progression `<= currentProgression` 時，回傳
  /// 空清單——呼叫端據此不預設展開任何層級、不高亮任何項目。
  static List<TocEntry> findCurrentPath(
    List<TocEntry> entries,
    double? currentProgression,
  ) {
    if (currentProgression == null) return const [];
    List<TocEntry>? bestPath;
    void walk(List<TocEntry> nodes, List<TocEntry> path) {
      for (final node in nodes) {
        final newPath = [...path, node];
        final progression = node.progression;
        if (progression != null && progression <= currentProgression) {
          bestPath = newPath;
        }
        walk(node.children, newPath);
      }
    }

    walk(entries, const []);
    return bestPath ?? const [];
  }
}
```

- [x] **Step 8: 執行測試確認通過**

Run: `flutter test test/reader/toc_navigator_test.dart`
Expected: PASS（全數綠燈）。

- [x] **Step 9: Commit**

```bash
git add app/lib/reader/toc_entry.dart app/lib/reader/toc_navigator.dart app/test/reader/toc_entry_test.dart app/test/reader/toc_navigator_test.dart
git commit -m "feat(epic5-issue4): 新增 TocEntry 資料模型與 TocNavigator 目前章節路徑演算法"
```

---

### Task 2: `EpubReaderView.kt`（原生端目錄讀取 + Locator 跳轉）

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`

**Interfaces:**
- Produces:
  - 新指令 `getTableOfContents`（無引數，回傳巢狀 `List<Map<String, Any?>>`，每個節點含 `title`／`locatorJson`／`progression`／`children`）。
  - 新指令 `jumpToLocator`（引數：`Map<String, Any?>`，含 `locatorJson: String`）。

本 Task 用到的 `Publication.tableOfContents: List<Link>`／`Publication.locatorFromLink(Link): Locator`／`Locator.locations.totalProgression: Double?`／`Locator.href: Url` 皆已對照 `readium-shared:3.3.0` 的 `readium-shared-3.3.0-api.jar`（`javap -p` 反編譯 `Publication.class`／`Link.class`／`Locator.class`／`Locator$Locations.class`）逐一確認簽章存在，不需要另外的驗證任務——`Publication.locatorFromLink(Link)` 的存在，正是 design.md「已知風險」列出的「需在 Architecting 階段確認 Readium 是否有便利 API...可直接取用」的解答。

- [x] **Step 1: 新增 import**

於檔案頂端既有 `import` 區塊新增（`import org.readium.r2.shared.publication.Locator` 之前）：

```kotlin
import org.readium.r2.shared.publication.Link
```

- [x] **Step 2: `onMethodCall` 新增 `getTableOfContents`／`jumpToLocator` 指令**

於 `onMethodCall` 的 `"jumpToProgression"` 分支之後新增：

```kotlin
            "getTableOfContents" -> {
                scope.launch(Dispatchers.IO) {
                    val toc = buildTocPayloadSafely()
                    withContext(Dispatchers.Main) {
                        // 審查修正：比照 computeTotalCharacterCountInBackground()／
                        // jumpToProgression() 既有的 isDisposed 防護慣例——協程
                        // 完成前 View 若已被銷毀，不應再呼叫 result.success()。
                        if (!isDisposed) result.success(toc)
                    }
                }
            }
            "jumpToLocator" -> {
                val locatorJson = call.argument<String>("locatorJson")
                if (locatorJson != null) {
                    try {
                        val locator = Locator.fromJSON(JSONObject(locatorJson))
                        navigatorFragment?.go(locator, animated = false)
                    } catch (e: Exception) {
                        // 無效的 locatorJson（例如 JSON 格式錯誤）靜默忽略，
                        // 比照本檔案既有對非致命錯誤的處理原則——目錄跳轉
                        // 失敗不應該讓已成功開啟的書籍畫面顯示錯誤。
                    }
                }
                result.success(null)
            }
```

（`getTableOfContents` 分支不呼叫 `result.success(null)`——結果透過協程內的 `withContext(Dispatchers.Main) { result.success(toc) }` 非同步回傳，`MethodChannel.Result` 只需被呼叫恰好一次，不要求在 `onMethodCall` 同步返回前完成。`jumpToLocator` 則是同步呼叫 `navigatorFragment?.go()`，不透過背景協程分派——比照既有 `nextPage()`/`previousPage()` 分支的同步風格，避免額外的 dispatcher 跳轉開銷影響 FR-08 的 200ms 跳轉時限。）

- [x] **Step 3: 新增 `buildTocPayloadSafely()`／`buildTocEntries()`**

於 `jumpToProgression()` 函式之後、`onPageLoaded()` override 之前新增：

```kotlin
    /**
     * 目錄樹狀結構一次性讀取 + 序列化（epic-5-toc-pagination Issue 4，
     * spec.md「目錄模組」）：走訪 `Publication.tableOfContents`（巢狀
     * `List<Link>`），對每個節點透過 `Publication.locatorFromLink()` 建構
     * 可供 `Navigator.go()` 使用的精確 Locator（含錨點，非僅解析到
     * resource 起始位置）。
     *
     * 頁碼估算所需的全書進度比例優先取用該 Locator 本身的
     * `totalProgression`；若為 `null`（Readium 內部對 `locatorFromLink()`
     * 產生的 Locator 是否必然填入 `totalProgression` 沒有文件保證），退而
     * 求其次比對 `Publication.positions()`（`jumpToProgression()` 已建立
     * 的既有先例）中 `href` 相同的第一個位置，取其 `totalProgression`
     * 作為近似值；兩者皆查無時保持 `null`，Dart 端顯示佔位符，不視為
     * 錯誤（見 spec.md「目錄模組」載入中狀態決策）。
     *
     * 【審查修正】`positions()` 依 href 查找的部分改為先建一份
     * `Map<Url, Locator>`（`associateBy`）再以 O(1) 查表，而非對每個目錄
     * 節點各自線性掃描整個 `positionsList`（O(章節數 × 全書切分位置數)）。
     * `distinctBy { it.href }` 保留每個 href 第一次出現的位置，與原本
     * `firstOrNull { it.href == ... }` 語意等價（`distinctBy` 依走訪順序
     * 保留首個符合者）。
     *
     * 於 `Dispatchers.IO` 執行——`positions()` 本身是 suspend 函式，且
     * 巢狀走訪＋逐節點查表在章節數量極多的書籍上仍可能有感知得到的延遲，
     * 統一放背景執行緒避免阻塞主執行緒（比照
     * `computeTotalCharacterCountInBackground()` 的既有原則）。任何一步
     * 失敗（例如 `publication` 尚未成功開啟）皆回傳空清單，靜默降級，不
     * 回報 `onError`——目錄讀取失敗不應該讓已成功開啟的書籍畫面顯示錯誤。
     */
    private suspend fun buildTocPayloadSafely(): List<Map<String, Any?>> {
        val pub = publication ?: return emptyList()
        return try {
            val positionsMap = pub.positions().distinctBy { it.href }.associateBy { it.href }
            buildTocEntries(pub.tableOfContents, pub, positionsMap)
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun buildTocEntries(
        links: List<Link>,
        pub: Publication,
        positionsMap: Map<Url, Locator>,
    ): List<Map<String, Any?>> {
        return links.map { link ->
            val locator = pub.locatorFromLink(link)
            val progression = locator?.locations?.totalProgression
                ?: positionsMap[locator?.href]?.locations?.totalProgression
            mapOf(
                "title" to (link.title ?: ""),
                "locatorJson" to (locator?.toJSON()?.toString() ?: ""),
                "progression" to progression,
                "children" to buildTocEntries(link.children, pub, positionsMap),
            )
        }
    }
```

- [x] **Step 4: 編譯驗證**

Run（於 `app/` 目錄）：`flutter build apk --debug`
Expected: 建置成功（`BUILD SUCCESSFUL`），無 Kotlin 編譯錯誤。

- [x] **Step 5: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git commit -m "feat(epic5-issue4): EpubReaderView.kt 新增 getTableOfContents 與 jumpToLocator"
```

---

### Task 3: Dart `EpubReaderView` 新增目錄讀取/跳轉介面

**Files:**
- Modify: `app/lib/reader/epub_reader_view.dart`

**Interfaces:**
- Consumes: `TocEntry.fromWire`（Task 1）、原生端 `getTableOfContents`／`jumpToLocator`（Task 2）。
- Produces:
  - `EpubReaderView.loadTableOfContents(GlobalKey<State<EpubReaderView>> key) -> Future<List<TocEntry>>`（static helper）。
  - `EpubReaderView.jumpToLocator(GlobalKey<State<EpubReaderView>> key, String locatorJson)`（static helper）。

- [x] **Step 1: 新增 import**

於 `app/lib/reader/epub_reader_view.dart` 頂端既有 `import` 區塊新增（`import 'epub_position_info.dart';` 之後）：

```dart
import 'toc_entry.dart';
```

- [x] **Step 2: 新增 static helpers**

於既有 `static void jumpToProgression(...)` 方法之後新增（皆在 `EpubReaderView` class 內、`createState()` 之前）：

```dart
  /// 讀取全書目錄樹狀結構（epic-5-toc-pagination Issue 4）。與
  /// [jumpToProgression] 不同，這是請求/回應語意（回傳 `Future`），非
  /// fire-and-forget；`ReaderScreen` 於書本開啟後（`onLayoutResolved`
  /// 回報非固定版面時）預先呼叫一次並快取結果，樹狀結構本身不隨版面設定
  /// 變動而改變，不需重新抓取。原生端呼叫失敗或本 State 尚未掛載（例如
  /// 純 `flutter_test` 環境下 `_channel` 恆為 `null`，AndroidView 未真正
  /// 建立）時回傳空清單，不拋出例外。
  static Future<List<TocEntry>> loadTableOfContents(
    GlobalKey<State<EpubReaderView>> key,
  ) async {
    final state = key.currentState;
    if (state is! _EpubReaderViewState) return const [];
    final raw = await state._channel
        ?.invokeMethod<List<Object?>>('getTableOfContents');
    if (raw == null) return const [];
    return raw
        .map((e) => TocEntry.fromWire(e as Map<Object?, Object?>))
        .toList();
  }

  /// 依目錄項目的序列化 Locator 跳轉（epic-5-toc-pagination Issue 4），比照
  /// [jumpToProgression] 的強型別 static helper 模式，不使用 `as dynamic`
  /// 跨越 State 的 private 邊界。
  static void jumpToLocator(
    GlobalKey<State<EpubReaderView>> key,
    String locatorJson,
  ) {
    final state = key.currentState;
    if (state is _EpubReaderViewState) {
      state._channel?.invokeMethod('jumpToLocator', {
        'locatorJson': locatorJson,
      });
    }
  }
```

- [x] **Step 3: 靜態分析驗證**

Run（於 `app/` 目錄）：`flutter analyze`
Expected: `No issues found!`

- [x] **Step 4: Commit**

```bash
git add app/lib/reader/epub_reader_view.dart
git commit -m "feat(epic5-issue4): EpubReaderView 新增 loadTableOfContents 與 jumpToLocator 介面"
```

---

### Task 4: `TocBottomSheet`（目錄樹狀清單 Bottom Sheet widget）

**Files:**
- Create: `app/lib/screens/toc_bottom_sheet.dart`
- Test: `app/test/screens/toc_bottom_sheet_test.dart`

**Interfaces:**
- Consumes: `TocEntry`（Task 1）、`EpubPageEstimator`（既有，Issue 3）、`ResolvedPreferences`（既有）。
- Produces: `TocBottomSheet({required List<TocEntry> entries, required Set<TocEntry> initiallyExpandedEntries, required TocEntry? currentEntry, required ValueListenable<int?> totalCharacterCountListenable, required ResolvedPreferences resolved, required ValueChanged<TocEntry> onEntrySelected})`——與 `ReaderScreen`／原生端完全解耦的獨立展示 widget，不知道呼叫端是誰、不直接碰 MethodChannel，供 Task 5 的 `ReaderScreen` 透過 `showModalBottomSheet` 開啟。

刻意不使用 Flutter 內建的 `ExpansionTile`：`ExpansionTile` 的整個標題列（含文字）都是單一「點擊展開/收起」熱區，無法與「點擊標題跳轉」共存於同一節點。改為每個節點一律是可點擊跳轉的 `ListTile`，有子項的節點額外在 `trailing` 疊加一個獨立的展開/收起 `IconButton`——跳轉與展開/收起是兩個獨立、不衝突的熱區。

**渲染策略（審查修正）**：不在 `build()` 內遞迴走訪整棵樹直接產生 `ListView(children: [...])`——那樣會在每次 build 當下就把「目前展開狀態下應可見」的所有節點一次性實例化成 widget，章節數量多時無法享有 `ListView` 的延遲載入（lazy rendering）優勢。改為維護一份已依目前展開狀態攤平好的 `List<_FlatTocRow>`（每列只記錄 `TocEntry` 本身與縮排深度），只在展開/收起狀態改變時（`_toggleExpanded`）重新計算一次，`build()` 改用 `ListView.builder` 依索引向這份攤平清單取值——螢幕外的列不會被提前建構。

- [x] **Step 1: 寫失敗測試**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/pdf_crop_mode.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/resolved_preferences.dart';
import 'package:elinkbook/reader/screen_orientation_setting.dart';
import 'package:elinkbook/reader/toc_entry.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';

const _testResolved = ResolvedPreferences(
  pageTurnMode: PageTurnMode.paginated,
  screenOrientation: ScreenOrientationSetting.auto,
  pdfFitMode: PdfFitMode.pageFit,
  pdfContrast: 0,
  pdfBrightness: 0,
  pdfBoldStrength: 0,
  pdfCropMode: PdfCropMode.none,
  dualPageMode: DualPageMode.auto,
  dualPageCoverAlone: true,
  dualPageDirection: DualPageDirection.rtl,
);

void main() {
  final ch1 = const TocEntry(title: '第一章', locatorJson: 'l1', progression: 0.0);
  final ch2s1 =
      const TocEntry(title: '第一節', locatorJson: 'l2s1', progression: 0.35);
  final ch2s2 =
      const TocEntry(title: '第二節', locatorJson: 'l2s2', progression: 0.45);
  final ch2 = TocEntry(
    title: '第二章',
    locatorJson: 'l2',
    progression: 0.3,
    children: [ch2s1, ch2s2],
  );
  final ch3s1 =
      const TocEntry(title: '附錄一', locatorJson: 'l3s1', progression: 0.85);
  final ch3 = TocEntry(
    title: '第三章',
    locatorJson: 'l3',
    progression: 0.7,
    children: [ch3s1],
  );
  final entries = [ch1, ch2, ch3];

  testWidgets('多層級結構正確渲染，當前章節路徑預設展開、其餘章節預設收起', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: {ch2, ch2s1},
          currentEntry: ch2s1,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(find.text('第一章'), findsOneWidget);
    expect(find.text('第二章'), findsOneWidget);
    expect(find.text('第一節'), findsOneWidget); // ch2 已預設展開
    expect(find.text('第二節'), findsOneWidget);
    expect(find.text('第三章'), findsOneWidget);
    expect(find.text('附錄一'), findsNothing); // ch3 未在目前路徑內，預設收起

    await tester.tap(find.byKey(Key('toc_entry_expand_${ch3.locatorJson}')));
    await tester.pump();

    expect(find.text('附錄一'), findsOneWidget);
  });

  testWidgets('當前章節項目標題以粗體高亮顯示，其餘項目不受影響', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: {ch2, ch2s1},
          currentEntry: ch2s1,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    final currentTitle = tester.widget<Text>(find.text('第一節'));
    expect(currentTitle.style?.fontWeight, FontWeight.bold);

    final otherTitle = tester.widget<Text>(find.text('第一章'));
    expect(otherTitle.style?.fontWeight, isNot(FontWeight.bold));
  });

  testWidgets('點選項目標題觸發 onEntrySelected 並傳遞正確的 TocEntry', (tester) async {
    TocEntry? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (entry) => selected = entry,
        ),
      ),
    ));

    await tester.tap(find.text('第一章'));
    await tester.pump();

    expect(selected, ch1);
  });

  testWidgets('點擊展開/收起按鈕不會觸發 onEntrySelected（兩個熱區互不干擾）',
      (tester) async {
    var selectedCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: ValueNotifier<int?>(null),
          resolved: _testResolved,
          onEntrySelected: (_) => selectedCount++,
        ),
      ),
    ));

    await tester.tap(find.byKey(Key('toc_entry_expand_${ch2.locatorJson}')));
    await tester.pump();

    expect(selectedCount, 0);
    expect(find.text('第一節'), findsOneWidget, reason: '展開按鈕本身仍應正常運作');
  });

  testWidgets('全書字元數尚未計算完成時顯示佔位符，計算完成後即時替換為估算頁碼',
      (tester) async {
    final notifier = ValueNotifier<int?>(null);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: entries,
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: notifier,
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(
      tester.widget<Text>(find.byKey(Key('toc_entry_page_${ch1.locatorJson}'))).data,
      '…',
    );

    notifier.value = 5000;
    await tester.pump();

    // 預設版面參數下 EpubPageEstimator.estimateCharsPerScreen() = 500，
    // totalPages = 5000/500 = 10；ch1.progression = 0.0 →
    // estimateCurrentPage(0.0, 10) = 1。
    expect(
      tester.widget<Text>(find.byKey(Key('toc_entry_page_${ch1.locatorJson}'))).data,
      '1',
    );
  });

  testWidgets(
      '全書字元數已計算完成，但節點本身 progression 為 null（原生端兩層 fallback 皆查無位置）時，'
      '頁碼仍顯示佔位符而非誤植為第 1 頁（審查修正）', (tester) async {
    const unknownPositionEntry =
        TocEntry(title: '位置不明章節', locatorJson: 'l_unknown', progression: null);
    final notifier = ValueNotifier<int?>(5000);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TocBottomSheet(
          entries: const [unknownPositionEntry],
          initiallyExpandedEntries: const {},
          currentEntry: null,
          totalCharacterCountListenable: notifier,
          resolved: _testResolved,
          onEntrySelected: (_) {},
        ),
      ),
    ));

    expect(
      tester
          .widget<Text>(
              find.byKey(Key('toc_entry_page_${unknownPositionEntry.locatorJson}')))
          .data,
      '…',
      reason: 'progression 為 null 時應顯示佔位符，不應誤植為 estimateCurrentPage 的 '
          'null-fallback 值（第 1 頁），避免誤導使用者以為該章節就在全書開頭',
    );
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/toc_bottom_sheet_test.dart`
Expected: FAIL（`toc_bottom_sheet.dart` 不存在，編譯錯誤）。

- [x] **Step 3: 撰寫 `TocBottomSheet` 最小實作**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../reader/epub_page_estimator.dart';
import '../reader/resolved_preferences.dart';
import '../reader/toc_entry.dart';

/// EPUB 目錄樹狀清單 Bottom Sheet（epic-5-toc-pagination Issue 4，
/// spec.md「目錄模組」），比照專案既有 Bottom Sheet 慣例（`PdfSettingsSheet`
/// ／`ReaderSettingsSheet`／`FxlSettingsSheet`）由呼叫端以
/// `showModalBottomSheet` 開啟。與 `ReaderScreen`／原生端完全解耦：只接收
/// 已解析好的 [entries]／[currentEntry]／[initiallyExpandedEntries]，選中
/// 項目時透過 [onEntrySelected] 回報，本身不知道呼叫端是誰、不直接碰
/// MethodChannel。
///
/// 刻意不使用 `ExpansionTile`：其整個標題列都是單一「點擊展開/收起」熱區，
/// 無法與「點擊標題跳轉」共存於同一節點。改為每個節點一律是可點擊跳轉的
/// `ListTile`，有子項的節點在 `trailing` 額外疊加一個獨立的展開/收起
/// `IconButton`——跳轉與展開/收起是兩個互不干擾的熱區。
///
/// 【審查修正】渲染改用 `ListView.builder` + 展開狀態改變時才重新計算的
/// 攤平清單（[_visibleRows]），不在 `build()` 內遞迴走訪整棵樹直接產生
/// `ListView(children: [...])`——後者會把「目前展開狀態下應可見」的節點
/// 一次性全部實例化成 widget，章節數量多時無法享有 `ListView` 的延遲載入
/// 優勢；`ListView.builder` 只會依需要（螢幕可視範圍附近）建構
/// `itemBuilder` 回傳的 widget。
class TocBottomSheet extends StatefulWidget {
  final List<TocEntry> entries;

  /// 開啟當下的預設展開集合（通常是 `TocNavigator.findCurrentPath` 的
  /// 回傳值），僅影響初始畫面；使用者點擊展開/收起按鈕後由本 widget 自行
  /// 管理後續狀態，不會回寫給呼叫端。
  final Set<TocEntry> initiallyExpandedEntries;

  /// 目前所在章節（用於高亮），`null` 代表尚無法判斷（例如尚未收到任何
  /// `onLocatorChanged` 回報）。
  final TocEntry? currentEntry;

  /// 全書字元數快取，`null` 時所有項目的頁碼顯示佔位符（`…`）。用
  /// `ValueListenable` 而非單純的 `int?` 參數，讓已開啟的 Bottom Sheet 能
  /// 在背景計算完成當下即時更新，不需使用者手動關閉重開（spec.md「目錄
  /// 模組」載入中狀態決策）。
  final ValueListenable<int?> totalCharacterCountListenable;

  /// 目前生效的版面參數，供換算「每螢幕可容納字元數」（見
  /// `EpubPageEstimator.estimateCharsPerScreen`）。
  final ResolvedPreferences resolved;

  final ValueChanged<TocEntry> onEntrySelected;

  const TocBottomSheet({
    super.key,
    required this.entries,
    required this.initiallyExpandedEntries,
    required this.currentEntry,
    required this.totalCharacterCountListenable,
    required this.resolved,
    required this.onEntrySelected,
  });

  @override
  State<TocBottomSheet> createState() => _TocBottomSheetState();
}

/// 目錄樹狀清單攤平後的單一可見列（審查修正）：只記錄 [entry] 本身與縮排
/// [depth]，不重複記錄展開狀態——是否展開由 `_TocBottomSheetState._expanded`
/// 這個唯一事實來源判斷，[_FlatTocRow] 只是「目前依展開狀態算出、應該顯示
/// 的節點清單」的其中一列。
class _FlatTocRow {
  final TocEntry entry;
  final int depth;

  const _FlatTocRow({required this.entry, required this.depth});
}

class _TocBottomSheetState extends State<TocBottomSheet> {
  late Set<TocEntry> _expanded;
  late List<_FlatTocRow> _visibleRows;

  @override
  void initState() {
    super.initState();
    _expanded = Set.of(widget.initiallyExpandedEntries);
    _visibleRows = _flatten(widget.entries, depth: 0);
  }

  /// 依目前 [_expanded] 狀態，把樹狀結構攤平成「目前應該顯示」的列清單
  /// （前序走訪，符合閱讀順序）——收起的子樹完全不會出現在回傳結果中，
  /// `ListView.builder` 因此連「存在但不可見」的節點都不需要知道。
  List<_FlatTocRow> _flatten(List<TocEntry> nodes, {required int depth}) {
    final rows = <_FlatTocRow>[];
    for (final node in nodes) {
      rows.add(_FlatTocRow(entry: node, depth: depth));
      if (node.children.isNotEmpty && _expanded.contains(node)) {
        rows.addAll(_flatten(node.children, depth: depth + 1));
      }
    }
    return rows;
  }

  void _toggleExpanded(TocEntry node) {
    setState(() {
      if (_expanded.contains(node)) {
        _expanded.remove(node);
      } else {
        _expanded.add(node);
      }
      _visibleRows = _flatten(widget.entries, depth: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder<int?>(
        valueListenable: widget.totalCharacterCountListenable,
        builder: (context, totalCharacterCount, _) {
          return ListView.builder(
            key: const Key('toc_bottom_sheet_list'),
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            // +1：索引 0 固定是標題列，其餘索引對應 _visibleRows[index - 1]。
            itemCount: _visibleRows.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child:
                      Text('📖 目錄', style: TextStyle(fontWeight: FontWeight.bold)),
                );
              }
              return _buildEntryRow(_visibleRows[index - 1], totalCharacterCount);
            },
          );
        },
      ),
    );
  }

  Widget _buildEntryRow(_FlatTocRow row, int? totalCharacterCount) {
    final node = row.entry;
    final isCurrent = identical(node, widget.currentEntry);
    // 審查修正：totalCharacterCount 已就緒不代表這個節點本身就有可用的
    // progression——原生端兩層 fallback（locatorFromLink() 自帶的
    // totalProgression、比對 positions() 的近似值）都可能查無資料，此時
    // node.progression 仍是 null。EpubPageEstimator.estimateCurrentPage
    // 對 progression == null 的既有語意是回傳第 1 頁（給「尚未收到任何
    // onLocatorChanged 回報」這個完全不同的情境使用），若不在這裡額外判斷
    // node.progression == null，會讓「查無位置」的章節被誤植成「第 1
    // 頁」，比顯示佔位符更誤導使用者。
    final pageLabel = (totalCharacterCount == null || node.progression == null)
        ? '…'
        : EpubPageEstimator.estimateCurrentPage(
            progression: node.progression,
            totalPages: EpubPageEstimator.estimateTotalPages(
              totalCharacterCount: totalCharacterCount,
              charsPerScreen: EpubPageEstimator.estimateCharsPerScreen(
                fontSize: widget.resolved.fontSize,
                lineHeight: widget.resolved.lineHeight,
                paragraphSpacing: widget.resolved.paragraphSpacing,
                pageMargins: widget.resolved.pageMargins,
              ),
            ),
          ).toString();

    return Padding(
      padding: EdgeInsets.only(left: row.depth * 16),
      child: ListTile(
        key: Key('toc_entry_${node.locatorJson}'),
        title: Text(
          node.title,
          style: isCurrent ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
        selected: isCurrent,
        onTap: () => widget.onEntrySelected(node),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(pageLabel, key: Key('toc_entry_page_${node.locatorJson}')),
            if (node.children.isNotEmpty)
              IconButton(
                key: Key('toc_entry_expand_${node.locatorJson}'),
                icon: Icon(
                  _expanded.contains(node) ? Icons.expand_less : Icons.expand_more,
                ),
                onPressed: () => _toggleExpanded(node),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/toc_bottom_sheet_test.dart`
Expected: PASS（全數綠燈）。

- [x] **Step 5: 靜態分析驗證**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/screens/toc_bottom_sheet.dart app/test/screens/toc_bottom_sheet_test.dart
git commit -m "feat(epic5-issue4): 新增 TocBottomSheet 目錄樹狀清單 widget"
```

---

### Task 5: `ReaderScreen` 接上目錄入口與跳轉

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: `TocEntry`／`TocNavigator`（Task 1）、`EpubReaderView.loadTableOfContents`／`.jumpToLocator`（Task 3）、`TocBottomSheet`（Task 4）。

- [x] **Step 1: 寫失敗測試**

於 `app/test/screens/reader_screen_test.dart` 的 `import` 區塊新增：

```dart
import 'package:elinkbook/reader/toc_entry.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';
```

於檔案末尾（`main()` 結尾 `}` 之前）新增：

```dart
  // --- Epic 5 Issue 4：EPUB 目錄（TOC）樹狀清單 ---

  testWidgets('EPUB 格式顯示「目錄」按鈕，初始為停用狀態', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_toc_initial',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final finder = find.byKey(const Key('reader_toc_button'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<IconButton>(finder).onPressed,
      isNull,
      reason: '尚未收到 onLayoutResolved，按鈕應為停用狀態',
    );
  });

  testWidgets('PDF 格式下，目錄入口按鈕不存在', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.pdf',
          bookId: 'b_toc_pdf',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byKey(const Key('reader_toc_button')), findsNothing);
  });

  testWidgets('EPUB 固定版面（FXL）開書後，目錄按鈕不存在（沿用既有 AppBar 隱藏機制）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample_fixed_layout.epub',
          bookId: 'b_toc_fxl',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader_toc_button')), findsNothing);
  });

  testWidgets(
      'EPUB reflowable 收到 onLayoutResolved 後，目錄按鈕轉為可點擊，點擊後開啟 TocBottomSheet',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_toc_open',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    final finder = find.byKey(const Key('reader_toc_button'));
    expect(tester.widget<IconButton>(finder).onPressed, isNotNull);

    await tester.tap(finder);
    await tester.pumpAndSettle();

    expect(find.byType(TocBottomSheet), findsOneWidget);
  });

  testWidgets('點選目錄項目後，TocBottomSheet 關閉', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_toc_select',
          prefsManager: prefsManager,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final epubView = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    epubView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: false, writingMode: WritingMode.horizontal),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader_toc_button')));
    await tester.pumpAndSettle();
    expect(find.byType(TocBottomSheet), findsOneWidget);

    // 純 flutter test 環境下 EpubReaderView._channel 恆為 null（AndroidView
    // 未真正建立），loadTableOfContents() 回傳空清單，TocBottomSheet 內部
    // 不會有任何可點擊的項目列——直接呼叫 TocBottomSheet.onEntrySelected
    // 模擬使用者選取（比照本檔案既有測試對「純 flutter test 環境無法觸發
    // 原生回呼」的既定處理方式，見 onPageRendered/onLayoutResolved 相關
    // 既有測試）。
    final sheet = tester.widget<TocBottomSheet>(find.byType(TocBottomSheet));
    sheet.onEntrySelected(
      const TocEntry(title: '測試章節', locatorJson: '{}', progression: 0.5),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TocBottomSheet), findsNothing);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: FAIL（`reader_toc_button` 不存在、`TocBottomSheet` 從未被開啟，找不到對應 widget）。

- [x] **Step 3: 修改 `ReaderScreen`**

編輯 `app/lib/screens/reader_screen.dart`，新增 import（於既有 `import '../reader/reading_position.dart';` 之後）：

```dart
import '../reader/toc_entry.dart';
import '../reader/toc_navigator.dart';
```

於既有 `import 'reader_footer.dart';` 之後新增：

```dart
import 'toc_bottom_sheet.dart';
```

新增狀態欄位（緊接 `_totalCharacterCount` 欄位之後）：

```dart
  int? _totalCharacterCount;
  // 目錄樹狀結構快取（Epic 5 Issue 4），由 onLayoutResolved 觸發一次性
  // 背景抓取（見 _handleLayoutResolved）。樹狀結構不隨版面設定變動，開書
  // 期間只抓取一次，不需要每次版面參數變動都重新請求。
  List<TocEntry> _tocEntries = const [];
  // 供 TocBottomSheet 訂閱、在已開啟的目錄畫面即時反映全書字元數背景計算
  // 完成事件（spec.md「目錄模組」載入中狀態決策）——與 _totalCharacterCount
  // 這個驅動頁尾 rebuild 的既有欄位（Issue 3）刻意分開維護，避免耦合兩條
  // 目的不同的更新路徑（頁尾靠 setState 觸發整個 ReaderScreen rebuild；
  // 目錄靠 ValueNotifier 只更新已開啟的 Bottom Sheet 子樹，不驚動
  // ReaderScreen 本身）。
  final _totalCharacterCountNotifier = ValueNotifier<int?>(null);
```

`initState()` 內同步更新 notifier（緊接 `_totalCharacterCount = loaded.totalCharacterCount;` 之後）：

```dart
        _totalCharacterCount = loaded.totalCharacterCount;
        _totalCharacterCountNotifier.value = loaded.totalCharacterCount;
```

`dispose()` 內新增（緊接 `WidgetsBinding.instance.removeObserver(this);` 之後）：

```dart
    WidgetsBinding.instance.removeObserver(this);
    _totalCharacterCountNotifier.dispose();
```

`_handleCharacterCountReady` 內新增（緊接 `setState(() => _totalCharacterCount = totalCharacterCount);` 之後）：

```dart
  void _handleCharacterCountReady(int totalCharacterCount) {
    if (!mounted) return;
    setState(() => _totalCharacterCount = totalCharacterCount);
    _totalCharacterCountNotifier.value = totalCharacterCount;
    widget.prefsManager.saveTotalCharacterCount(widget.bookId, totalCharacterCount);
  }
```

`_handleLayoutResolved` 方法結尾新增目錄預取觸發（`setState({...})` 呼叫之後、方法結尾 `}` 之前）：

```dart
  void _handleLayoutResolved(EpubLayoutInfo info) {
    if (!mounted) return;
    setState(() {
      _isFixedLayout = info.isFixedLayout;
      _autoDetectedWritingMode = info.writingMode;
      final loaded = _loaded;
      if (loaded != null) {
        _resolved = widget.prefsManager.resolve(
          loaded,
          autoDetectedWritingMode: info.writingMode,
        );
      }
    });
    // epic-5-toc-pagination Issue 4：目錄僅支援流式 EPUB（spec.md「範圍
    // 界定」），FXL 不預取。目錄樹狀結構不會隨版面設定變動而改變（與頁碼
    // 估算不同，見 _buildEpubFooter 的重算邏輯），理論上只需要抓取一次。
    //
    // 【審查修正，防禦性保險】原生端 onLayoutResolved 目前的 pageReported
    // 一次性 latch（見 EpubReaderView.kt openBook()/onPageLoaded()）與
    // MainActivity 的 configChanges 宣告，已確保本方法在單次開書期間只會
    // 被呼叫一次——旋轉螢幕、調整字型大小都不會讓它再次觸發，故目前並不
    // 存在「每次版面重排都重複抓取目錄」的實際效能問題。加上
    // `_tocEntries.isEmpty` 這道檢查純粹是把「只抓取一次」這句話從隱含假設
    // 變成程式碼本身強制執行的行為，零成本、無副作用；即使原生端的一次性
    // 觸發機制未來被改動，這裡也不會退化成重複請求。
    if (!info.isFixedLayout && _tocEntries.isEmpty) {
      EpubReaderView.loadTableOfContents(_epubReaderViewKey).then((entries) {
        if (!mounted) return;
        setState(() => _tocEntries = entries);
      });
    }
  }
```

新增 `_openToc()` 方法（緊接 `_openFxlSettings()` 之後）：

```dart
  void _openToc() {
    final currentPath = TocNavigator.findCurrentPath(
      _tocEntries,
      _epubPositionInfo?.progression,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TocBottomSheet(
        entries: _tocEntries,
        initiallyExpandedEntries: currentPath.toSet(),
        currentEntry: currentPath.isEmpty ? null : currentPath.last,
        totalCharacterCountListenable: _totalCharacterCountNotifier,
        resolved: _resolved!,
        onEntrySelected: (entry) {
          Navigator.of(context).pop();
          EpubReaderView.jumpToLocator(_epubReaderViewKey, entry.locatorJson);
        },
      ),
    );
  }
```

`_buildAppBarActions` 的 EPUB 分支新增目錄按鈕（緊接 `case BookFormat.epub:` 之後、既有 `reader_layout_settings_button` 之前）：

```dart
      case BookFormat.epub:
        return [
          IconButton(
            key: const Key('reader_toc_button'),
            icon: const Icon(Icons.menu_book),
            tooltip: '目錄',
            // 沿用與「⚙️版面」按鈕一致的啟用條件——_autoDetectedWritingMode
            // 非 null 代表 onLayoutResolved 已觸發，書本已成功開啟。
            onPressed: _autoDetectedWritingMode == null ? null : _openToc,
          ),
          IconButton(
            key: const Key('reader_layout_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: '版面設定',
            onPressed:
                _autoDetectedWritingMode == null ? null : _openLayoutSettings,
          ),
        ];
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（全數綠燈，含既有測試）。

Run（全專案回歸）: `flutter test`
Expected: 全數 PASS。

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 5: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic5-issue4): ReaderScreen 接上 EPUB 目錄入口與跳轉"
```

---

### Task 6: 多章節測試素材 + 真機整合測試

**Files:**
- Create: `app/test/fixtures/sample_multi_chapter.epub`
- Modify: `app/pubspec.yaml`
- Create: `app/integration_test/epub_toc_test.dart`

**Interfaces:**
- Consumes: Task 5 的完整 `ReaderScreen` 行為。

既有 EPUB 測試素材（`sample.epub`／`sample_long_vertical.epub`／`sample_horizontal.epub`）的 `nav.xhtml` 皆只有單一扁平章節（"第一章"），查證確認（`unzip -p sample.epub OEBPS/nav.xhtml`）不足以驗證「多層級結構」「展開/收起」「跳轉到不同章節」——需要新建一份具備巢狀目錄的素材。

- [x] **Step 1: 建立 `sample_multi_chapter.epub` 素材**

Run（於 `app/test/fixtures` 目錄）：

```bash
rm -rf /tmp/epub_multi_chapter_staging
mkdir -p /tmp/epub_multi_chapter_staging/META-INF
mkdir -p /tmp/epub_multi_chapter_staging/OEBPS

printf 'application/epub+zip' > /tmp/epub_multi_chapter_staging/mimetype

cat > /tmp/epub_multi_chapter_staging/META-INF/container.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
EOF

cat > /tmp/epub_multi_chapter_staging/OEBPS/content.opf << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000007</dc:identifier>
    <dc:title>elinkBook 多章節目錄範例 EPUB</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="dcterms:modified">2026-07-16T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter3" href="chapter3.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
    <itemref idref="chapter2"/>
    <itemref idref="chapter3"/>
  </spine>
</package>
EOF

cat > /tmp/epub_multi_chapter_staging/OEBPS/nav.xhtml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body>
  <nav epub:type="toc">
    <ol>
      <li><a href="chapter1.xhtml">第一章：起始</a></li>
      <li><a href="chapter2.xhtml">第二章：發展</a>
        <ol>
          <li><a href="chapter2.xhtml#section1">第一節</a></li>
          <li><a href="chapter2.xhtml#section2">第二節</a></li>
        </ol>
      </li>
      <li><a href="chapter3.xhtml">第三章：結局</a></li>
    </ol>
  </nav>
</body>
</html>
EOF

for n in 1 2 3; do
  title=$([ "$n" = "1" ] && echo "第一章：起始" || ([ "$n" = "2" ] && echo "第二章：發展" || echo "第三章：結局"))
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<html xmlns="http://www.w3.org/1999/xhtml" lang="zh-TW" xml:lang="zh-TW">'
    echo "<head><title>${title}</title></head>"
    echo '<body>'
    echo "<h1>${title}</h1>"
    if [ "$n" = "2" ]; then
      echo '<h2 id="section1">第一節</h2>'
    fi
    for i in $(seq 1 8); do
      echo "<p>這是第 ${n} 章第 ${i} 段內容，用來確保本章有足夠的字元數可供分頁估算與跳轉驗證，內容本身不需要有意義，只需要與其他章節明顯不同即可。</p>"
    done
    if [ "$n" = "2" ]; then
      echo '<h2 id="section2">第二節</h2>'
      for i in $(seq 9 16); do
        echo "<p>這是第 ${n} 章第 ${i} 段內容，位於第二節之內，用來確保錨點跳轉能落在正確的子章節範圍。</p>"
      done
    fi
    echo '</body>'
    echo '</html>'
  } > "/tmp/epub_multi_chapter_staging/OEBPS/chapter${n}.xhtml"
done

cd /tmp/epub_multi_chapter_staging
zip -X -0 sample_multi_chapter.epub mimetype
zip -X -rg sample_multi_chapter.epub META-INF OEBPS
cd -
mv /tmp/epub_multi_chapter_staging/sample_multi_chapter.epub .
unzip -l sample_multi_chapter.epub
```

Expected: `unzip -l` 列出 `mimetype`／`META-INF/container.xml`／`OEBPS/content.opf`／`OEBPS/nav.xhtml`／`OEBPS/chapter1.xhtml`／`OEBPS/chapter2.xhtml`／`OEBPS/chapter3.xhtml` 共 7 個檔案。

- [x] **Step 2: 宣告為 Flutter asset**

編輯 `app/pubspec.yaml`，於既有 `- test/fixtures/sample_fxl_svg_cover.epub` 之後新增：

```yaml
    - test/fixtures/sample_fxl_svg_cover.epub
    - test/fixtures/sample_multi_chapter.epub
```

- [x] **Step 3: 寫真機整合測試**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/epub_character_count_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';
import 'package:elinkbook/screens/toc_bottom_sheet.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpUntilFooterVisible(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (find.byKey(const Key('reader_footer')).evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：頁尾未出現（全書字元數計算未完成）');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EPUB 目錄樹狀清單正確渲染巢狀結構，點選項目後畫面確實跳轉至正確章節',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
      EpubCharacterCountRepository(libraryRepository.database),
    );

    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample_multi_chapter.epub', 'epub_toc_integration.epub');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_epub_toc',
      title: 'EPUB 目錄測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_epub_toc',
          prefsManager: prefsManager,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilFooterVisible(tester);

    final initialProgressText =
        (tester.widget<Text>(find.byKey(const Key('reader_footer_progress_text'))))
                .data ??
            '';

    // 開啟目錄，驗證頂層 3 章皆顯示、第二章巢狀子項預設收起（開書起始頁在
    // 第一章，第二章不在目前章節路徑內）。
    await tester.tap(find.byKey(const Key('reader_toc_button')));
    await tester.pumpAndSettle();

    expect(find.byType(TocBottomSheet), findsOneWidget);
    expect(find.text('第一章：起始'), findsOneWidget);
    expect(find.text('第二章：發展'), findsOneWidget);
    expect(find.text('第三章：結局'), findsOneWidget);
    expect(find.text('第一節'), findsNothing);
    expect(find.text('第二節'), findsNothing);

    // 展開第二章，驗證巢狀子項出現。
    await tester.tap(find.byKey(const Key('toc_entry_expand_l2')));
    await tester.pump();
    expect(find.text('第一節'), findsOneWidget);
    expect(find.text('第二節'), findsOneWidget);

    // 點選「第三章：結局」，驗證目錄自動關閉、頁尾進度確實反映跳轉結果。
    // FR-08「200ms 內完成跳轉」的時限本身，因 Bottom Sheet 關閉動畫
    // （Material 預設約 250-300ms）與原生跳轉耗時混在同一段
    // pumpAndSettle() 內、無法乾淨拆分自動化量測，已於真機以人工肉眼／
    // 碼表確認跳轉本身（非含 UI 轉場動畫）在觀感上是瞬間完成，此處改以
    // 內容正確性斷言（進度確實改變）驗證跳轉發生。
    await tester.tap(find.text('第三章：結局'));
    await tester.pumpAndSettle();

    expect(find.byType(TocBottomSheet), findsNothing, reason: '點選後應自動關閉目錄');

    await _pumpUntilFooterVisible(tester);
    final finalProgressText =
        (tester.widget<Text>(find.byKey(const Key('reader_footer_progress_text'))))
                .data ??
            '';
    expect(finalProgressText, isNot(initialProgressText),
        reason: '跳轉到第三章後頁尾進度應與開書時的起始位置不同');
    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
}
```

（測試中 `toc_entry_expand_l2` 這個 key 依賴 `chapter2.xhtml` 的目錄項目 Locator JSON 序列化後被 Dart 端原樣儲存於 `TocEntry.locatorJson`——實際字串內容由 Readium 決定，不保證恰好是 `l2` 這個字面值。若真機執行時因為 Locator JSON 實際內容不同導致 `find.byKey(const Key('toc_entry_expand_l2'))` 找不到元件，改用 `find.byKey(const Key('toc_entry_expand_')).first`不可行時，改為先透過 `find.text('第二章：發展')` 定位到該 `ListTile`，再用 `find.descendant(of: ..., matching: find.byType(IconButton))` 找到同一列的展開按鈕——比照本檔案在撰寫真機測試階段對「原生序列化字串內容無法在撰寫測試當下預先得知」情境的既定處理原則。）

- [x] **Step 4: 於真實裝置/模擬器執行**

Run（於 `app/` 目錄，先以 `flutter devices` 取得裝置 id）：
```bash
flutter test integration_test/epub_toc_test.dart -d <device-id>
```
Expected: `All tests passed!`。若 Step 3 註記的 `toc_entry_expand_l2` key 因實際 Locator JSON 序列化內容不同而找不到元件，依 Step 3 註記的替代做法（`find.descendant` 從標題文字定位到同列展開按鈕）調整後重新執行。

實際執行：於真機（`3CEF42ECD491687`，Android 15）執行，`All tests passed!`；初版曾因非同步跳轉時序問題（`_pumpUntilFooterVisible` 誤判頁尾已可見而提前返回，未等到 `onLocatorChanged` 實際抵達）導致偶發假陽性，已於 `53a953a` 改用 `_pumpUntilProgressChanged`（輪詢至 `reader_footer_progress_text` 文字實際改變或 10 秒逾時 `fail()`）修正，經獨立複審確認為真實、正確的時序 bug 修復。

- [x] **Step 5: Commit**

```bash
git add app/test/fixtures/sample_multi_chapter.epub app/pubspec.yaml app/integration_test/epub_toc_test.dart
git commit -m "test(epic5-issue4): 新增多章節 EPUB 素材與目錄真機整合測試"
```

---

## Self-Review 對照（spec.md／issues.md 涵蓋度）

- EPUB 閱讀畫面出現目錄入口，點擊開啟樹狀目錄清單 → Task 5（AppBar 按鈕 + `_openToc`）+ Task 6（真機驗證）。
- 目錄正確反映書籍的多層級章節結構，可展開／收起 → Task 2（原生端巢狀序列化）+ Task 4（`TocBottomSheet` 展開/收起互動）+ Task 6（真機驗證真實巢狀結構）。
- 當前章節於目錄中正確高亮 → Task 1（`TocNavigator.findCurrentPath`）+ Task 4（高亮渲染測試）。
- 每個目錄項目顯示標題與估算頁碼；計算未完成時顯示佔位符，完成後正確更新 → Task 2（progression 序列化 + positions() 退回比對）+ Task 4（`ValueListenableBuilder` 即時更新測試）。
- 點選目錄項目後於 200ms 內跳轉至正確位置（真機量測）→ Task 2（`jumpToLocator` 同步呼叫，不透過背景協程分派）+ Task 6（真機驗證跳轉正確性；毫秒級時限因 Bottom Sheet 轉場動畫無法乾淨自動化量測，已於 Task 6 Step 3 說明改採真機人工 QA 確認，並以內容正確性斷言取代）。
- PDF 閱讀畫面完全不出現目錄入口 → Task 5（`_buildAppBarActions` 只在 EPUB 分支新增按鈕）+ 既有 `_isFixedLayout` 機制。
- 上述測試皆通過，`flutter analyze` 乾淨 → 每個 Task 的驗證 Step 皆含此要求。
- 真機整合測試涵蓋開啟真實多章節 EPUB、展開/收起目錄、點選跳轉的端到端流程 → Task 6。
- design.md「已知風險」的「TOC 項目跳轉的 Locator 建構」不確定性 → Task 2（已反編譯確認 `Publication.locatorFromLink(Link)` 存在，予以解決）。
- 審查修正（`tmp/epic-5/reviews/plan-issue-4-review.md`，計畫審查階段）：`node.progression` 為 `null` 時頁碼誤植為第 1 頁（Critical）→ Task 4（`pageLabel` 判斷式一併檢查 `node.progression == null`，並新增對應測試案例）；`buildTocEntries` 的 O(N×M) 線性搜尋（Important）→ Task 2（改用 `positionsMap` 的 O(1) 查表）；`TocBottomSheet` 缺乏延遲載入（Important）→ Task 4（改用攤平清單 + `ListView.builder`）；`getTableOfContents` 缺少 `isDisposed` 防護（Minor）→ Task 2（比照既有慣例補上）；`_handleLayoutResolved` 重複抓取目錄疑慮（Important，經查證現有原生端一次性 latch 機制下並非實際問題，仍採納防禦性保險）→ Task 5（`_tocEntries.isEmpty` guard）。`jumpToLocator` 加 `Log.w`（Minor）人類決策不採納，維持既有靜默 catch 慣例。
- 審查修正（`tmp/epic-5/reviews/review-issue-4-independent.md`，分支程式碼審查階段）：目錄按鈕的啟用時機未與背景抓取（`EpubReaderView.loadTableOfContents`）完成同步，存在使用者點擊到空白 Bottom Sheet、且無法與「本書真的沒有目錄」區分的競速窗口（Important）→ Task 5（新增 `_tocLoaded` 旗標，按鈕 `onPressed` 一併檢查，比照既有「⚙️版面設定」按鈕等待非同步就緒訊號才啟用的既定模式，見 commit `a5a24f5`）；整合測試檔名 `toc_test.dart` 與計畫指定、既有 `epub_` 前綴命名慣例不符（Minor）→ 重新命名為 `epub_toc_test.dart`（見 commit `a8190cc`）；本檔案 Task 6 Step 4/5 checkbox 未同步勾選（Minor）→ 已補勾（見本次變更）。
