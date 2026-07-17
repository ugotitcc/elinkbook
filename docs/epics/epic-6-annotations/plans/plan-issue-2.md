# Epic 6 Issue 2：EPUB 劃線與備註 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為流式 EPUB 新增劃線（螢光筆黃/粉/藍、底線）與備註（可獨立於劃線存在）功能：原生 WebView 選字手勢觸發浮動工具列、Readium Decorator API 疊加視覺樣式、點擊既有標記可編輯/刪除，並讓 Issue 1 建立的 `NotesBottomSheet`「✏️ 劃線與備註」分頁正式生效（依位置排序、同範圍劃線+備註合併顯示、單筆/批次刪除）。

**Architecture:** 新增 `highlights`／`notes` 兩張 SQLite 表（`book_id` 外鍵關聯 `books`；`notes.highlight_id` 可空外鍵 `REFERENCES highlights(id) ON DELETE SET NULL`）與對應的 `HighlightsRepository`／`NotesRepository`；`EpubReaderView.dart`/`.kt` 新增選取事件（`onSelectionChanged`/`onSelectionCleared`）與標記啟用事件（`onAnnotationActivated`）的 method channel 契約，並新增 `setDecorations` 靜態方法把目前應顯示的完整標記清單一次性送給原生端（比照既有 `setPreferences` 整組送出慣例，非增量 diff）；原生端透過 Readium `EpubNavigatorFragment.Configuration.selectionActionModeCallback` 攔截原生選字工具列（改由 Flutter 端浮動工具列 `AnnotationToolbar` 接手)，並透過 `DecorableNavigator.applyDecorations()`/`addDecorationListener()` 疊加視覺樣式與接收點擊事件。`ReaderScreen` 負責整合：載入既有標記、顯示/隱藏浮動工具列、CRUD 呼叫、把真實 Repository 接上 `NotesBottomSheet`。

**Tech Stack:** Flutter/Dart、`sqflite`、`sqflite_common_ffi`（測試）、Readium `kotlin-toolkit:3.3.0`（`readium-navigator` 的 `Decoration`/`DecorableNavigator`/`SelectableNavigator`/`EpubNavigatorFragment.Configuration` API，已透過 `javap` 反編譯 Gradle 快取內的 `readium-navigator-3.3.0-api.jar` 逐一查證下方 Global Constraints 列出的簽章）。

## Global Constraints

- 所有程式註解、文件、commit message 皆使用正體中文（zh-TW）。
- `ReaderScreen` 是本專案唯一的閱讀器 seam（`CLAUDE.md`），本 Issue 不新增第二個閱讀器入口。
- **SQLite schema migration**：目前資料庫 `version` 為 8（Issue 1 已建立 `bookmarks` 表），本 Issue 提升至 9。累加式 `if (oldVersion < N)` 慣例（絕不用 `else if`），`PRAGMA foreign_keys = ON` 已於既有 `onConfigure` 對整個連線設定，`highlights`/`notes` 兩張新表的外鍵約束自動生效，不需額外宣告。Migration 撰寫順序先建 `highlights` 再建 `notes`（spec.md「資料模型關聯」審查修正 1.1 已定案：純屬程式碼可讀性慣例，非技術硬性要求）。
- **PDF 專屬欄位不在本 Issue 範圍**：`highlights`/`notes` 本 Issue 只新增 EPUB 相關欄位（`epub_locator_json`/`progression`）。PDF 的頁碼+矩形座標欄位由 Issue 3 以後續 migration（`ALTER TABLE`）補上，比照 `bookmarks` 表當初只有 `pdf_page_index` 一次到位、`book_reader_prefs` 表則是逐版本 `ALTER TABLE` 增量新增欄位的既有先例——本 Issue 不預先建立用不到的欄位（YAGNI）。
- **Readium Decorator API 簽章**（已用 `javap -p` 反編譯 `readium-navigator-3.3.0-api.jar` 逐一查證，非憑空假設）：
  - `Decoration(id: String, locator: Locator, style: Decoration.Style, extras: Map<String, Any> = emptyMap())`。
  - `Decoration.Style.Highlight(tint: Int, isActive: Boolean)` / `Decoration.Style.Underline(tint: Int, isActive: Boolean)`——皆為 built-in 樣式，`tint` 是完整 ARGB `Int` 色值。
  - `DecorableNavigator.applyDecorations(decorations: List<Decoration>, group: String)`（suspend）／`addDecorationListener(group: String, listener: DecorableNavigator.Listener)`／`DecorableNavigator.Listener.onDecorationActivated(event: OnActivatedEvent): Boolean`，`OnActivatedEvent.decoration.id` 即為點擊到的標記 id。
  - `SelectableNavigator.currentSelection(): Selection?`（suspend，一次性查詢，無 selection-changed 監聽 API）；`Selection(locator: Locator, rect: RectF)`。
  - `EpubNavigatorFragment.Configuration.selectionActionModeCallback: ActionMode.Callback?`——Readium 官方提供的選字工具列客製化掛點，我們用它攔截原生選字選單。**審查修正**：`onCreateActionMode` 必須回傳 `true`（回傳 `false` 會讓 Android 整個跳過 ActionMode 生命週期，`onDestroyActionMode` 永遠不會觸發，是 Android SDK 本身的標準契約，非 Readium 特有行為），改用 `menu?.clear()` 清空選單項目來達成「不顯示原生選單」的視覺效果；同時在 `onCreateActionMode` 當下呼叫 `currentSelection()` 取得選取範圍回報給 Dart。
  - `EpubNavigatorFragment.Configuration.decorationTemplates: HtmlDecorationTemplates?`——設為 `HtmlDecorationTemplates.defaultTemplates()`（Readium 內建預設模板，直接處理 Highlight/Underline 兩種 built-in 樣式的 HTML/CSS 渲染，不自訂 `HtmlDecorationTemplate`）。
- **純備註視覺簡化（本計劃書自行定案，design.md 決策 #2 「淡灰底＋行內小圖示」未展開到此細節；已提交 `/superpowers:requesting-code-review` 審查、審查報告列為「部分實現需求」，經人類確認維持此簡化，不擴大本 Issue 範圍，見 `tmp/epic-6/reviews/plan_issue_2_review.md` Spec (a).1）**：純備註（無劃線）一律套用 `Decoration.Style.Highlight(tint = noteOnlyTint)`（固定淡灰色），沿用 Readium 內建 Highlight 模板即可達成「淡灰底」視覺區隔；「行內小圖示」需要自訂 `HtmlDecorationTemplate`（客製化 HTML 模板），本 Issue 範圍不含此項，以「與螢光筆顏色明顯不同的淡灰色」作為區隔手段（點擊後開啟的編輯 Dialog 本身也會清楚標示「備註」而非「劃線」，不會造成使用者誤判）。若真機測試發現色彩區隔不足以辨識，留待後續 issue 補上自訂圖示模板。
- **色彩決策收斂在 Dart 端**：三種螢光筆固定色票＋純備註灰色皆為 Dart 常數；底線色為目前主題 `primary` 色（design.md 決策 #5），由 Dart 於呼叫 `setDecorations` 當下讀取 `Theme.of(context).colorScheme.primary` 換算。Dart `Color.value`（`0xAARRGGBB`）與 Android `Color` int 版面完全一致，可直接透傳給原生端當 `tint`，原生端不需維護色彩對照表。
- **選取矩形座標協定**：比照 design.md 決策 #15 對 PDF 的既有百分比慣例——原生端把選取矩形換算成相對於 `container`（AndroidView 的量測寬高）的百分比值（`leftPct`/`topPct`/`rightPct`/`bottomPct`，0.0–1.0）送給 Dart，而非絕對像素。Dart 端在 `ReaderScreen._buildBody` 既有的 `Stack` 座標系內（與原生 `container` 1:1 對應，因為流式 EPUB 不像 FXL 有額外縮放/置中變換）用 `LayoutBuilder` 量得的寬高換算回實際座標定位浮動工具列。design.md 決策 #15 提到的「Dart 端以 Overlay 定位」在本計劃書解讀為「視覺上疊加在最上層」，實作上直接沿用 `_buildBody` 既有 `Stack`＋`Positioned` 慣例（FXL 懸浮按鈕已是同樣手法），不引入 Flutter `Overlay`/`OverlayEntry` API，避免新增一套疊加層機制。
- **FXL 排除**（design.md 決策 #7）：`ReaderScreen._handleSelectionChanged` 開頭以 `if (_isFixedLayout) return;` 明確擋下——FXL 頁面本質上多半無可選取文字層，理論上仍可能有極少數例外，此防禦保證不會意外對 FXL 觸發劃線 UI。
- **單筆刪除＝整筆一起刪**（spec.md 決策 #13）：不依賴 FK `ON DELETE SET NULL` 的自動退化（那是給「批次刪除劃線」情境用的）——單筆刪除一個「劃線+備註」合併項目時，程式碼須明確分別呼叫 `notesRepository.delete()` 與 `highlightsRepository.delete()` 兩次。
- **兩層測試架構的既有先例延伸**：`app/test/reader/epub_reader_view_test.dart` 既有測試已示範可用 `TestDefaultBinaryMessengerBinding` 同時驗證「送給原生端的 outgoing method call 參數」與「模擬原生端送來的 incoming method call（例如 `onLocatorChanged`）」，不需要真實裝置、也不是新增 mock 基礎設施（沿用 Flutter test binding 內建機制）。本 Issue 新增的 `onSelectionChanged`/`onSelectionCleared`/`onAnnotationActivated`/`setDecorations` 皆比照此既有先例撰寫 widget test。
- **標記 id 編碼慣例**：`setDecorations` 送給原生端的每筆 `EpubDecoration.id` 一律是 `"highlight:<資料庫 id>"` 或 `"note:<資料庫 id>"` 字串；原生端點擊觸發 `onAnnotationActivated` 時原樣傳回這個字串，Dart 端依前綴反查是哪一張表的哪一筆。
- `flutter analyze` 全程必須保持 `No issues found!`；每個 Task 的最後一步皆須執行並確認。

---

### Task 1：`HighlightStyle` 列舉 + 色票純函式 + `Highlight`／`Note` 模型

**Files:**
- Create: `app/lib/reader/highlight_style.dart`
- Create: `app/lib/reader/highlight.dart`
- Create: `app/lib/reader/note.dart`
- Test: `app/test/reader/highlight_style_test.dart`
- Test: `app/test/reader/highlight_test.dart`
- Test: `app/test/reader/note_test.dart`

**Interfaces:**
- Produces: `HighlightStyle`（列舉，4 個值，各自攜帶 `fixedTint`——審查修正，見 Global Constraints「色彩決策收斂在 Dart 端」，改由列舉本身攜帶資料取代重複 `switch`；純 UI 顯示標籤刻意不放在此檔案，見 Task 7）；`highlighterYellowTint`/`highlighterPinkTint`/`highlighterBlueTint`/`noteOnlyTint`（`Color` 常數）；`highlightStyleTint(HighlightStyle, {required Color primaryColor}) → int`；`Highlight`（`id`/`bookId`/`style`/`epubLocatorJson`/`progression`，`toMap()`/`fromMap()`/`==`/`hashCode`）；`Note`（`id`/`bookId`/`text`/`epubLocatorJson`/`progression`/`highlightId`，`toMap()`/`fromMap()`/`copyWith({text})`/`==`/`hashCode`）。供 Task 2-10 消費。

- [ ] **Step 1: 寫失敗測試（`highlight_style_test.dart`）**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/highlight_style.dart';

void main() {
  test('highlighterYellow/Pink/Blue 回傳各自固定色票，忽略 primaryColor', () {
    const arbitraryPrimary = Color(0xFF000000);
    expect(
      highlightStyleTint(HighlightStyle.highlighterYellow, primaryColor: arbitraryPrimary),
      highlighterYellowTint.value,
    );
    expect(
      highlightStyleTint(HighlightStyle.highlighterPink, primaryColor: arbitraryPrimary),
      highlighterPinkTint.value,
    );
    expect(
      highlightStyleTint(HighlightStyle.highlighterBlue, primaryColor: arbitraryPrimary),
      highlighterBlueTint.value,
    );
  });

  test('underline 回傳呼叫端傳入的 primaryColor（design.md 決策 #5：不提供顏色選擇）', () {
    const primary = Color(0xFF123456);
    expect(
      highlightStyleTint(HighlightStyle.underline, primaryColor: primary),
      primary.value,
    );
  });

  test('HighlightStyle.fixedTint：螢光筆三色為對應色票，underline 為 null（審查修正）', () {
    expect(HighlightStyle.highlighterYellow.fixedTint, highlighterYellowTint);
    expect(HighlightStyle.highlighterPink.fixedTint, highlighterPinkTint);
    expect(HighlightStyle.highlighterBlue.fixedTint, highlighterBlueTint);
    expect(HighlightStyle.underline.fixedTint, isNull);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/highlight_style_test.dart`
Expected: FAIL（`highlight_style.dart` 尚不存在，編譯錯誤）

- [ ] **Step 3: 實作 `highlight_style.dart`**

建立 `app/lib/reader/highlight_style.dart`：

```dart
import 'package:flutter/material.dart';

/// 螢光筆固定色票（design.md 決策 #5），色值換算自
/// `prototype/index.html` 既有 `.highlight-yellow`/`-pink`/`-blue` 的
/// CSS `rgba(..., 0.45)`（45% 透明度 ≈ 0x73/0xFF）。宣告在列舉之前，
/// 供下方列舉建構子直接參照（Dart 頂層宣告不受檔案內文字順序限制）。
const highlighterYellowTint = Color(0x73FDE047);
const highlighterPinkTint = Color(0x73F472B6);
const highlighterBlueTint = Color(0x7360A5FA);

/// 純備註（無劃線）的固定畫面指示色（design.md 決策 #2「淡灰底」，見
/// Global Constraints「純備註視覺簡化」）。
const noteOnlyTint = Color(0x73D1D5DB);

/// 劃線樣式（epic-6-annotations Issue 2，spec.md「劃線與備註模組」）：
/// 螢光筆三色（背景底色填滿）與底線（波浪底線，固定主題 primary 色）為
/// 4 個互斥值，非「樣式＋顏色」兩個獨立維度——避免「底線＋顏色」這種
/// design.md 決策 #5 明確排除的無效狀態組合。持久化時使用 `.name`（比照
/// 既有 `PdfCropMode`/`WritingMode` 等列舉的既有慣例，見
/// book_reader_prefs.dart 的 `Enum.values.byName()` 既有寫法）。
///
/// 【審查修正】[fixedTint] 由列舉本身攜帶固定色票（螢光筆三色），
/// `underline` 為 `null`（其色值是執行期才知道的目前主題 primary
/// 色，非編譯期常數，不可能收斂為列舉欄位）——取代原本 `highlightStyleTint`
/// 對 4 個值各自 `switch` 一次的寫法，把「這個樣式對應哪個固定色票」這件
/// 事收斂成列舉自身的資料，而非外部函式的重複分支邏輯。純 UI 顯示標籤
/// （例如「螢光筆（黃）」）刻意不放在這個檔案——`reader/` 目錄下的其他
/// 列舉（`BookFormat`／`WritingMode`／`PdfCropMode` 等）皆不含 UI 顯示
/// 字串，是純格式無關的領域模型；標籤是唯一消費端 `NotesBottomSheet`
/// 自己的呈現邏輯，收斂在該檔案內的私有函式（見 Task 7），避免領域模型
/// 檔案摻雜 UI 層級的字串常數。
enum HighlightStyle {
  highlighterYellow(highlighterYellowTint),
  highlighterPink(highlighterPinkTint),
  highlighterBlue(highlighterBlueTint),
  underline(null);

  /// 固定色票；`null` 代表色值需由呼叫端於執行期決定（僅 `underline`
  /// 如此，見 [highlightStyleTint]）。
  final Color? fixedTint;

  const HighlightStyle(this.fixedTint);
}

/// 依樣式＋目前主題 primary 色，換算成原生 Decoration API 所需的完整
/// ARGB `int` 色值（Dart `Color.value` 與 Android `Color` int 皆為
/// `0xAARRGGBB` 版面，可直接透傳給原生端，見 Global Constraints「色彩
/// 決策收斂在 Dart 端」）。純函式，不依賴 `BuildContext`——呼叫端自行讀取
/// `Theme.of(context).colorScheme.primary` 後傳入，維持本函式可獨立
/// 單元測試。實作本身不再需要 `switch`——[HighlightStyle.fixedTint] 非
/// null 時直接採用，僅 `underline`（`fixedTint == null`）才退回呼叫端
/// 傳入的 [primaryColor]。
int highlightStyleTint(HighlightStyle style, {required Color primaryColor}) {
  return (style.fixedTint ?? primaryColor).value;
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/highlight_style_test.dart`
Expected: PASS

- [ ] **Step 5: 寫失敗測試（`highlight_test.dart`）**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';

void main() {
  test('toMap／fromMap round-trip 保留所有欄位（不含 id）', () {
    const highlight = Highlight(
      bookId: 'b1',
      style: HighlightStyle.highlighterPink,
      epubLocatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.2,
    );
    final map = highlight.toMap();
    expect(map.containsKey('id'), isFalse);
    expect(map['book_id'], 'b1');
    expect(map['style'], 'highlighterPink');
    expect(map['epub_locator_json'], '{"href":"/c1.xhtml"}');
    expect(map['progression'], 0.2);
  });

  test('fromMap 正確還原 id 與 style（模擬資料庫查詢結果）', () {
    final restored = Highlight.fromMap({
      'id': 5,
      'book_id': 'b1',
      'style': 'underline',
      'epub_locator_json': '{"href":"/c2.xhtml"}',
      'progression': 0.4,
    });
    expect(restored.id, 5);
    expect(restored.style, HighlightStyle.underline);
    expect(restored.progression, 0.4);
  });

  test('兩個欄位值完全相同的 Highlight 視為相等', () {
    const a = Highlight(id: 1, bookId: 'b1', style: HighlightStyle.underline, progression: 0.1);
    const b = Highlight(id: 1, bookId: 'b1', style: HighlightStyle.underline, progression: 0.1);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
```

- [ ] **Step 6: 執行測試確認失敗**

Run: `flutter test test/reader/highlight_test.dart`
Expected: FAIL（`highlight.dart` 尚不存在，編譯錯誤）

- [ ] **Step 7: 實作 `Highlight`**

建立 `app/lib/reader/highlight.dart`：

```dart
import 'highlight_style.dart';

/// 單一劃線（epic-6-annotations Issue 2，spec.md「劃線與備註模組」）：
/// 標記書中「一段選取範圍」，定位精度高於書籤（EPUB：Locator JSON，含
/// 選取範圍本身，非僅單點）。建立後不可改色/改樣式（spec.md 決策），
/// 需要改色時刪除重建。本 Issue 只涵蓋 EPUB 欄位；PDF 專屬欄位由
/// Issue 3 後續 migration 補上（見 Global Constraints）。
class Highlight {
  /// SQLite 自動指派的 rowid，新增前（尚未寫入資料庫）為 null。
  final int? id;
  final String bookId;
  final HighlightStyle style;
  final String? epubLocatorJson;
  final double? progression;

  const Highlight({
    this.id,
    required this.bookId,
    required this.style,
    this.epubLocatorJson,
    this.progression,
  });

  /// 供 [HighlightsRepository.insert] 使用；刻意不含 `id`，比照
  /// `Bookmark.toMap()` 既有慣例（新增一律交由 SQLite `AUTOINCREMENT`
  /// 指派）。
  Map<String, Object?> toMap() {
    return {
      'book_id': bookId,
      'style': style.name,
      'epub_locator_json': epubLocatorJson,
      'progression': progression,
    };
  }

  factory Highlight.fromMap(Map<String, Object?> map) {
    return Highlight(
      id: map['id'] as int?,
      bookId: map['book_id'] as String,
      style: HighlightStyle.values.byName(map['style'] as String),
      epubLocatorJson: map['epub_locator_json'] as String?,
      progression: (map['progression'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Highlight &&
      other.id == id &&
      other.bookId == bookId &&
      other.style == style &&
      other.epubLocatorJson == epubLocatorJson &&
      other.progression == progression;

  @override
  int get hashCode => Object.hash(id, bookId, style, epubLocatorJson, progression);

  @override
  String toString() =>
      'Highlight(id: $id, bookId: $bookId, style: $style, epubLocatorJson: $epubLocatorJson, progression: $progression)';
}
```

- [ ] **Step 8: 執行測試確認通過**

Run: `flutter test test/reader/highlight_test.dart`
Expected: PASS

- [ ] **Step 9: 寫失敗測試（`note_test.dart`）**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/note.dart';

void main() {
  test('toMap／fromMap round-trip 保留所有欄位（不含 id）', () {
    const note = Note(
      bookId: 'b1',
      text: '這段很重要',
      epubLocatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.2,
      highlightId: 7,
    );
    final map = note.toMap();
    expect(map.containsKey('id'), isFalse);
    expect(map['book_id'], 'b1');
    expect(map['text'], '這段很重要');
    expect(map['highlight_id'], 7);
  });

  test('fromMap 正確還原 highlight_id 為 null（純備註）', () {
    final restored = Note.fromMap({
      'id': 3,
      'book_id': 'b1',
      'text': '純備註內容',
      'epub_locator_json': '{"href":"/c2.xhtml"}',
      'progression': 0.5,
      'highlight_id': null,
    });
    expect(restored.highlightId, isNull);
    expect(restored.text, '純備註內容');
  });

  test('copyWith 只更新 text，其餘欄位保留原值', () {
    const original = Note(id: 1, bookId: 'b1', text: '舊文字', highlightId: 2);
    final updated = original.copyWith(text: '新文字');
    expect(updated.id, 1);
    expect(updated.highlightId, 2);
    expect(updated.text, '新文字');
  });

  test('兩個欄位值完全相同的 Note 視為相等', () {
    const a = Note(id: 1, bookId: 'b1', text: 'X', highlightId: null);
    const b = Note(id: 1, bookId: 'b1', text: 'X', highlightId: null);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
```

- [ ] **Step 10: 執行測試確認失敗**

Run: `flutter test test/reader/note_test.dart`
Expected: FAIL（`note.dart` 尚不存在，編譯錯誤）

- [ ] **Step 11: 實作 `Note`**

建立 `app/lib/reader/note.dart`：

```dart
/// 單一備註（epic-6-annotations Issue 2，spec.md「劃線與備註模組」）：
/// 自由文字內容，可獨立於劃線存在。[highlightId] 為 null 代表純備註
/// （無劃線），非 null 代表依附於某一筆 [Highlight]（見 spec.md「資料
/// 模型關聯」——`notes.highlight_id REFERENCES highlights(id) ON DELETE
/// SET NULL`，批次刪除劃線後此欄位由資料庫自動退化為 null）。
class Note {
  final int? id;
  final String bookId;
  final String text;
  final String? epubLocatorJson;
  final double? progression;
  final int? highlightId;

  const Note({
    this.id,
    required this.bookId,
    required this.text,
    this.epubLocatorJson,
    this.progression,
    this.highlightId,
  });

  Map<String, Object?> toMap() {
    return {
      'book_id': bookId,
      'text': text,
      'epub_locator_json': epubLocatorJson,
      'progression': progression,
      'highlight_id': highlightId,
    };
  }

  factory Note.fromMap(Map<String, Object?> map) {
    return Note(
      id: map['id'] as int?,
      bookId: map['book_id'] as String,
      text: map['text'] as String,
      epubLocatorJson: map['epub_locator_json'] as String?,
      progression: (map['progression'] as num?)?.toDouble(),
      highlightId: map['highlight_id'] as int?,
    );
  }

  Note copyWith({String? text}) {
    return Note(
      id: id,
      bookId: bookId,
      text: text ?? this.text,
      epubLocatorJson: epubLocatorJson,
      progression: progression,
      highlightId: highlightId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.bookId == bookId &&
      other.text == text &&
      other.epubLocatorJson == epubLocatorJson &&
      other.progression == progression &&
      other.highlightId == highlightId;

  @override
  int get hashCode =>
      Object.hash(id, bookId, text, epubLocatorJson, progression, highlightId);

  @override
  String toString() =>
      'Note(id: $id, bookId: $bookId, text: $text, epubLocatorJson: $epubLocatorJson, progression: $progression, highlightId: $highlightId)';
}
```

- [ ] **Step 12: 執行測試確認通過**

Run: `flutter test test/reader/note_test.dart`
Expected: PASS

- [ ] **Step 13: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 14: Commit**

```bash
git add app/lib/reader/highlight_style.dart app/lib/reader/highlight.dart app/lib/reader/note.dart app/test/reader/highlight_style_test.dart app/test/reader/highlight_test.dart app/test/reader/note_test.dart
git commit -m "feat(epic-6): 新增 HighlightStyle／Highlight／Note 模型"
```

---

### Task 2：`AnnotationListItem` + `mergeAnnotations` 合併排序純函式

**Files:**
- Create: `app/lib/reader/annotation_list_item.dart`
- Test: `app/test/reader/annotation_list_item_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Highlight`／`Note`。
- Produces: `AnnotationListItem`（`highlight`/`note` 皆 nullable，至少一個非 null；`key` getter）；`mergeAnnotations(List<Highlight>, List<Note>) → List<AnnotationListItem>`，供 Task 7（`NotesBottomSheet`）與 Task 10（`ReaderScreen` 點擊已建立標記時反查）消費。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/reader/annotation_list_item_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/annotation_list_item.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';

void main() {
  test('只有劃線、無備註：每筆各自成一個項目', () {
    final highlights = [
      const Highlight(id: 1, bookId: 'b1', style: HighlightStyle.underline, progression: 0.1),
      const Highlight(id: 2, bookId: 'b1', style: HighlightStyle.highlighterYellow, progression: 0.5),
    ];
    final items = mergeAnnotations(highlights, const []);
    expect(items, hasLength(2));
    expect(items[0].highlight?.id, 1);
    expect(items[0].note, isNull);
  });

  test('只有純備註（highlightId 為 null）：每筆各自成一個項目', () {
    final notes = [
      const Note(id: 9, bookId: 'b1', text: '純備註', progression: 0.3),
    ];
    final items = mergeAnnotations(const [], notes);
    expect(items, hasLength(1));
    expect(items.single.highlight, isNull);
    expect(items.single.note?.id, 9);
  });

  test('劃線＋依附備註（highlightId 指向該劃線）：合併成一個項目', () {
    final highlights = [
      const Highlight(id: 4, bookId: 'b1', style: HighlightStyle.highlighterPink, progression: 0.2),
    ];
    final notes = [
      const Note(id: 10, bookId: 'b1', text: '心得', progression: 0.2, highlightId: 4),
    ];
    final items = mergeAnnotations(highlights, notes);
    expect(items, hasLength(1));
    expect(items.single.highlight?.id, 4);
    expect(items.single.note?.id, 10);
  });

  test('依 progression 由小到大排序，合併項目與純備註/純劃線混合排序', () {
    final highlights = [
      const Highlight(id: 1, bookId: 'b1', style: HighlightStyle.underline, progression: 0.8),
      const Highlight(id: 2, bookId: 'b1', style: HighlightStyle.underline, progression: 0.2),
    ];
    final notes = [
      const Note(id: 5, bookId: 'b1', text: '純備註', progression: 0.5),
    ];
    final items = mergeAnnotations(highlights, notes);
    expect(items.map((i) => i.highlight?.id ?? -i.note!.id!).toList(), [2, -5, 1]);
  });

  test('AnnotationListItem.key 對相同 highlight/note 組合回傳相同值', () {
    const a = AnnotationListItem(
      highlight: Highlight(id: 1, bookId: 'b1', style: HighlightStyle.underline),
    );
    const b = AnnotationListItem(
      highlight: Highlight(id: 1, bookId: 'b1', style: HighlightStyle.underline),
    );
    expect(a.key, b.key);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/annotation_list_item_test.dart`
Expected: FAIL（`annotation_list_item.dart` 尚不存在，編譯錯誤）

- [ ] **Step 3: 實作 `AnnotationListItem` + `mergeAnnotations`**

建立 `app/lib/reader/annotation_list_item.dart`：

```dart
import 'highlight.dart';
import 'note.dart';

/// 「劃線與備註」側邊欄清單的單一顯示項目（epic-6-annotations Issue 2，
/// spec.md「資料模型關聯」：同一選取範圍若同時有 highlight 與指向它的
/// note，清單以一筆呈現）。[highlight]／[note] 至少一個非 null——三種
/// 合法組合：純劃線（note 為 null）、純備註（highlight 為 null）、
/// 劃線+依附備註（兩者皆非 null）。
class AnnotationListItem {
  final Highlight? highlight;
  final Note? note;

  const AnnotationListItem({this.highlight, this.note})
      : assert(highlight != null || note != null,
            'AnnotationListItem 的 highlight／note 至少須有一個非 null');

  /// 供 UI 當作 Widget Key／比對用的穩定識別字串，組合 highlight/note
  /// 各自的資料庫 id（其中一個可能為 null）。
  String get key => 'h${highlight?.id}_n${note?.id}';

  double get _position => highlight?.progression ?? note?.progression ?? 0;
}

/// 合併 [highlights]／[notes] 兩份清單成單一依書中位置排序的顯示清單
/// （spec.md「資料模型關聯」／「側邊欄清單合併顯示」）。演算法：先以
/// `note.highlightId` 建立索引，能對應到 highlight 的 note 與該
/// highlight 合併成一筆；`highlightId == null` 的 note 各自獨立成一筆
/// （純備註，見 `highlight_id IS NULL` 即為純備註的既定判斷依據）；最後
/// 依 [Highlight.progression]／[Note.progression] 由小到大排序。
List<AnnotationListItem> mergeAnnotations(
  List<Highlight> highlights,
  List<Note> notes,
) {
  final noteByHighlightId = <int, Note>{};
  final pureNotes = <Note>[];
  for (final note in notes) {
    final highlightId = note.highlightId;
    if (highlightId != null) {
      noteByHighlightId[highlightId] = note;
    } else {
      pureNotes.add(note);
    }
  }

  final items = <AnnotationListItem>[
    for (final highlight in highlights)
      AnnotationListItem(highlight: highlight, note: noteByHighlightId[highlight.id]),
    for (final note in pureNotes) AnnotationListItem(note: note),
  ];
  items.sort((a, b) => a._position.compareTo(b._position));
  return items;
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/annotation_list_item_test.dart`
Expected: PASS

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/reader/annotation_list_item.dart app/test/reader/annotation_list_item_test.dart
git commit -m "feat(epic-6): 新增劃線／備註合併排序純函式 mergeAnnotations"
```

---

### Task 3：SQLite `highlights`／`notes` 表 + schema migration（v8→v9）

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Test: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Produces: `highlights` 表（`id`/`book_id`/`style`/`epub_locator_json`/`progression`）、`notes` 表（`id`/`book_id`/`text`/`epub_locator_json`/`progression`/`highlight_id` 可空外鍵），供 Task 4 的 `HighlightsRepository`／`NotesRepository` 消費。

- [ ] **Step 1: 寫失敗測試**

於 `app/test/library/sqlite_library_repository_test.dart` 檔案結尾（最後一個 `}` 之前）新增：

```dart
  test('全新安裝的 highlights／notes 表可用（version 9 起 onCreate 已含括）', () async {
    await repository.insertBook(_book('b_highlight'));
    final highlightId = await repository.database.insert('highlights', {
      'book_id': 'b_highlight',
      'style': 'underline',
      'epub_locator_json': '{"href":"/c1.xhtml"}',
      'progression': 0.1,
    });
    expect(highlightId, greaterThan(0));

    final noteId = await repository.database.insert('notes', {
      'book_id': 'b_highlight',
      'text': '心得',
      'epub_locator_json': '{"href":"/c1.xhtml"}',
      'progression': 0.1,
      'highlight_id': highlightId,
    });
    expect(noteId, greaterThan(0));

    final rows = await repository.database
        .query('notes', where: 'book_id = ?', whereArgs: ['b_highlight']);
    expect(rows.single['highlight_id'], highlightId);
  });

  test('既有 version 8 裝置升級到 version 9，highlights／notes 表正確建立', () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v8_to_v9_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 8」的舊資料庫：手動以 version 8 當時的完整
    // schema（books/book_reader_prefs/bookmarks 皆為 version 8 最終樣貌，
    // 不含 highlights/notes）建立，不透過 SqliteLibraryRepository.open()
    // （該方法目前的 onCreate 已經是 version 9 的最終 schema，無法用來
    // 重現「舊裝置」情境，比照 v7→v8 遷移測試既有寫法）。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 8,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE book_reader_prefs (
              book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
              font_family TEXT,
              font_size REAL,
              font_weight REAL,
              line_height REAL,
              paragraph_spacing REAL,
              page_margins REAL,
              text_align TEXT,
              publisher_styles INTEGER,
              writing_mode_override TEXT,
              page_turn_mode_override TEXT,
              screen_orientation_override TEXT,
              pdf_fit_mode TEXT,
              pdf_contrast REAL,
              pdf_brightness REAL,
              pdf_bold_strength REAL,
              pdf_crop_mode TEXT,
              pdf_crop_rect TEXT,
              dual_page_mode TEXT,
              dual_page_cover_alone INTEGER,
              dual_page_direction TEXT,
              show_header INTEGER,
              show_footer INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE bookmarks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              name TEXT NOT NULL,
              epub_locator_json TEXT,
              progression REAL,
              pdf_page_index INTEGER
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'epub',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=8 →
    // newVersion=9），驗證 highlights／notes 表確實建立且可寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final highlightId = await upgraded.database.insert('highlights', {
      'book_id': 'b1',
      'style': 'highlighterYellow',
      'epub_locator_json': null,
      'progression': 0.3,
    });
    expect(highlightId, greaterThan(0));

    final noteId = await upgraded.database.insert('notes', {
      'book_id': 'b1',
      'text': '升級後新增的備註',
      'epub_locator_json': null,
      'progression': 0.3,
      'highlight_id': null,
    });
    expect(noteId, greaterThan(0));

    // 既有書籍資料不受影響。
    final books = await upgraded.listBooks();
    expect(books.single.title, '既有書籍');
  });
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL（`no such table: highlights`，因為 schema 尚未更新且 `version` 仍為 8）

- [ ] **Step 3: 實作 schema migration**

`app/lib/library/sqlite_library_repository.dart` 的 `version: 8,` 改為：

```dart
      version: 9,
```

`onCreate` 內 `await _createBookmarksTable(db);` 之後新增：

```dart
        await _createBookmarksTable(db);
        await _createHighlightsTable(db);
        await _createNotesTable(db);
      },
```

`onUpgrade` 內 `if (oldVersion < 8) { ...; }` 區塊之後，新增第四個獨立區塊：

```dart
        if (oldVersion < 8) {
          await _createBookmarksTable(db);
        }
        if (oldVersion < 9) {
          // epic-6-annotations Issue 2：劃線／備註功能新增的兩張全新
          // 資料表。與 bookmarks 表（oldVersion < 8）比照同一原則——
          // 任何 oldVersion < 9 的裝置都必然還沒有這兩張表，無條件建立
          // 即可，不需要判斷「表是否已存在」。順序先建 highlights 再建
          // notes（notes.highlight_id 參照 highlights，見 spec.md「資料
          // 模型關聯」審查修正 1.1 的程式碼可讀性慣例）。
          await _createHighlightsTable(db);
          await _createNotesTable(db);
        }
      },
    );
    return SqliteLibraryRepository._(db);
  }
```

在 `_createBookmarksTable` 方法之後新增：

```dart
  static Future<void> _createHighlightsTable(Database db) async {
    // 劃線（epic-6-annotations Issue 2，spec.md「劃線與備註模組」），與
    // books 表以 book_id 外鍵關聯（比照 bookmarks 既有關聯模式）。本
    // Issue 只新增 EPUB 相關欄位；PDF 專屬欄位（頁碼＋矩形座標）留待
    // Issue 3 以後續 migration 補上（見 plan-issue-2.md Global
    // Constraints，避免預先建立用不到的欄位）。
    await db.execute('''
      CREATE TABLE highlights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        style TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL
      )
    ''');
  }

  static Future<void> _createNotesTable(Database db) async {
    // 備註（epic-6-annotations Issue 2，spec.md「資料模型關聯」）：
    // highlight_id 為可空外鍵，ON DELETE SET NULL——批次刪除劃線後，
    // 依附的備註自動退化為純備註（highlight_id 變 null），不需應用層
    // 判斷邏輯。建表順序刻意晚於 _createHighlightsTable（程式碼可讀性
    // 慣例，非技術硬性要求，見 spec.md 審查修正 1.1）。
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        text TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL,
        highlight_id INTEGER REFERENCES highlights(id) ON DELETE SET NULL
      )
    ''');
  }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: PASS（全部測試綠燈，含既有 v1→v8 系列遷移測試不受影響）

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-6): 新增 highlights／notes 表與 v8→v9 schema migration"
```

---

### Task 4：`HighlightsRepository` + `NotesRepository`（含 FK 退化行為驗證）

**Files:**
- Create: `app/lib/reader/highlights_repository.dart`
- Create: `app/lib/reader/notes_repository.dart`
- Test: `app/test/reader/highlights_repository_test.dart`
- Test: `app/test/reader/notes_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Highlight`／`Note`；Task 3 的 `highlights`/`notes` 表 schema。
- Produces: `HighlightsRepository(Database)`（`insert`/`listByBook`/`delete`/`deleteAllForBook`）、`NotesRepository(Database)`（`insert`/`listByBook`/`updateText`/`delete`/`deleteAllForBook`），供 Task 7（`NotesBottomSheet`）與 Task 10（`ReaderScreen`）消費。

- [ ] **Step 1: 寫失敗測試（`highlights_repository_test.dart`）**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/highlights_repository.dart';

Book _testBook(String id) {
  return Book(
    id: id,
    title: '測試書',
    format: BookFileFormat.epub,
    filePath: 'content://example/$id',
    source: BookSource.local,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  late SqliteLibraryRepository libraryRepository;
  late HighlightsRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    repository = HighlightsRepository(libraryRepository.database);
    await libraryRepository.insertBook(_testBook('b1'));
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('insert 回傳自動指派的 rowid，listByBook 讀回相同資料', () async {
    final id = await repository.insert(const Highlight(
      bookId: 'b1',
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.1,
    ));
    expect(id, greaterThan(0));

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, id);
    expect(list.single.style, HighlightStyle.highlighterYellow);
  });

  test('listByBook 依 progression 由小到大排序', () async {
    await repository.insert(
        const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.8));
    await repository.insert(
        const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));

    final list = await repository.listByBook('b1');
    expect(list.map((h) => h.progression).toList(), [0.1, 0.8]);
  });

  test('listByBook 只回傳指定 book_id 的劃線', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await repository.insert(
        const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));
    await repository.insert(
        const Highlight(bookId: 'b2', style: HighlightStyle.underline, progression: 0.1));

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
  });

  test('delete 移除指定單筆劃線，其餘不受影響', () async {
    final id1 = await repository.insert(
        const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));
    final id2 = await repository.insert(
        const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.5));
    await repository.delete(id1);

    final list = await repository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, id2);
  });

  test('deleteAllForBook 只清空指定書籍的劃線，其他書籍不受影響', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await repository.insert(
        const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));
    await repository.insert(
        const Highlight(bookId: 'b2', style: HighlightStyle.underline, progression: 0.1));

    await repository.deleteAllForBook('b1');

    expect(await repository.listByBook('b1'), isEmpty);
    expect(await repository.listByBook('b2'), hasLength(1));
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/highlights_repository_test.dart`
Expected: FAIL（`highlights_repository.dart` 尚不存在，編譯錯誤）

- [ ] **Step 3: 實作 `HighlightsRepository`**

建立 `app/lib/reader/highlights_repository.dart`：

```dart
import 'package:sqflite/sqflite.dart';

import 'highlight.dart';

/// `highlights` 表的存取層（epic-6-annotations Issue 2，spec.md「劃線
/// 與備註模組」）。比照既有 `BookmarksRepository` 模式。
class HighlightsRepository {
  final Database _db;

  const HighlightsRepository(this._db);

  Future<int> insert(Highlight highlight) {
    return _db.insert('highlights', highlight.toMap());
  }

  /// 依書中位置順序排序（本 Issue 只有 EPUB，故直接用 progression；PDF
  /// 欄位由 Issue 3 補上時，這裡的 ORDER BY 需要改回 bookmarks 既有的
  /// `COALESCE(...)` 寫法，屬 Issue 3 範圍）。
  Future<List<Highlight>> listByBook(String bookId) async {
    final rows = await _db.query(
      'highlights',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'progression ASC',
    );
    return rows.map(Highlight.fromMap).toList();
  }

  Future<void> delete(int id) {
    return _db.delete('highlights', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllForBook(String bookId) {
    return _db.delete('highlights', where: 'book_id = ?', whereArgs: [bookId]);
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/highlights_repository_test.dart`
Expected: PASS

- [ ] **Step 5: 寫失敗測試（`notes_repository_test.dart`，含 FK 退化行為）**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/notes_repository.dart';

Book _testBook(String id) {
  return Book(
    id: id,
    title: '測試書',
    format: BookFileFormat.epub,
    filePath: 'content://example/$id',
    source: BookSource.local,
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  late SqliteLibraryRepository libraryRepository;
  late HighlightsRepository highlightsRepository;
  late NotesRepository notesRepository;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    highlightsRepository = HighlightsRepository(libraryRepository.database);
    notesRepository = NotesRepository(libraryRepository.database);
    await libraryRepository.insertBook(_testBook('b1'));
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('insert 回傳自動指派的 rowid，listByBook 讀回相同資料', () async {
    final id = await notesRepository.insert(const Note(bookId: 'b1', text: 'A', progression: 0.1));
    expect(id, greaterThan(0));

    final list = await notesRepository.listByBook('b1');
    expect(list.single.text, 'A');
  });

  test('listByBook 依 progression 由小到大排序', () async {
    await notesRepository.insert(const Note(bookId: 'b1', text: 'B', progression: 0.8));
    await notesRepository.insert(const Note(bookId: 'b1', text: 'A', progression: 0.1));

    final list = await notesRepository.listByBook('b1');
    expect(list.map((n) => n.text).toList(), ['A', 'B']);
  });

  test('updateText 更新指定備註的文字，其餘欄位不受影響', () async {
    final id = await notesRepository
        .insert(const Note(bookId: 'b1', text: '舊文字', progression: 0.2, highlightId: null));
    await notesRepository.updateText(id, '新文字');

    final list = await notesRepository.listByBook('b1');
    expect(list.single.text, '新文字');
    expect(list.single.progression, 0.2);
  });

  test('delete 移除指定單筆備註，其餘不受影響', () async {
    final id1 = await notesRepository.insert(const Note(bookId: 'b1', text: 'A', progression: 0.1));
    final id2 = await notesRepository.insert(const Note(bookId: 'b1', text: 'B', progression: 0.5));
    await notesRepository.delete(id1);

    final list = await notesRepository.listByBook('b1');
    expect(list, hasLength(1));
    expect(list.single.id, id2);
  });

  test('deleteAllForBook 只清空指定書籍的備註，其他書籍不受影響', () async {
    await libraryRepository.insertBook(_testBook('b2'));
    await notesRepository.insert(const Note(bookId: 'b1', text: 'A', progression: 0.1));
    await notesRepository.insert(const Note(bookId: 'b2', text: 'B', progression: 0.1));

    await notesRepository.deleteAllForBook('b1');

    expect(await notesRepository.listByBook('b1'), isEmpty);
    expect(await notesRepository.listByBook('b2'), hasLength(1));
  });

  test(
      'FK 退化行為（spec.md 決策 #13／資料模型關聯）：刪除劃線後，依附的'
      '備註 highlight_id 自動變 null，備註內容本身不受影響', () async {
    final highlightId = await highlightsRepository.insert(
      const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.3),
    );
    final noteId = await notesRepository.insert(
      Note(bookId: 'b1', text: '依附備註', progression: 0.3, highlightId: highlightId),
    );

    await highlightsRepository.delete(highlightId);

    final notes = await notesRepository.listByBook('b1');
    final degraded = notes.singleWhere((n) => n.id == noteId);
    expect(degraded.highlightId, isNull);
    expect(degraded.text, '依附備註');
  });

  test(
      'FK 退化行為（批次版本）：deleteAllForBook 清空劃線後，所有依附備註'
      '皆退化為純備註，備註本身不被刪除', () async {
    final h1 = await highlightsRepository
        .insert(const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.1));
    final h2 = await highlightsRepository
        .insert(const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.2));
    await notesRepository.insert(Note(bookId: 'b1', text: 'N1', progression: 0.1, highlightId: h1));
    await notesRepository.insert(Note(bookId: 'b1', text: 'N2', progression: 0.2, highlightId: h2));

    await highlightsRepository.deleteAllForBook('b1');

    final notes = await notesRepository.listByBook('b1');
    expect(notes, hasLength(2));
    expect(notes.every((n) => n.highlightId == null), isTrue);
  });
}
```

- [ ] **Step 6: 執行測試確認失敗**

Run: `flutter test test/reader/notes_repository_test.dart`
Expected: FAIL（`notes_repository.dart` 尚不存在，編譯錯誤）

- [ ] **Step 7: 實作 `NotesRepository`**

建立 `app/lib/reader/notes_repository.dart`：

```dart
import 'package:sqflite/sqflite.dart';

import 'note.dart';

/// `notes` 表的存取層（epic-6-annotations Issue 2，spec.md「劃線與備註
/// 模組」）。FK `ON DELETE SET NULL` 的退化行為由資料庫本身保證（見
/// sqlite_library_repository.dart `_createNotesTable`），本類別不需要
/// 額外實作任何退化邏輯，`listByBook` 讀到的 `highlight_id` 已經是
/// 資料庫層級處理過的最終結果。
class NotesRepository {
  final Database _db;

  const NotesRepository(this._db);

  Future<int> insert(Note note) {
    return _db.insert('notes', note.toMap());
  }

  Future<List<Note>> listByBook(String bookId) async {
    final rows = await _db.query(
      'notes',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'progression ASC',
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<void> updateText(int id, String text) {
    return _db.update('notes', {'text': text}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(int id) {
    return _db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllForBook(String bookId) {
    return _db.delete('notes', where: 'book_id = ?', whereArgs: [bookId]);
  }
}
```

- [ ] **Step 8: 執行測試確認通過**

Run: `flutter test test/reader/notes_repository_test.dart`
Expected: PASS（含 FK 退化行為測試）

- [ ] **Step 9: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add app/lib/reader/highlights_repository.dart app/lib/reader/notes_repository.dart app/test/reader/highlights_repository_test.dart app/test/reader/notes_repository_test.dart
git commit -m "feat(epic-6): 新增 HighlightsRepository／NotesRepository"
```

---

### Task 5：備註文字輸入/編輯共用 Dialog

**Files:**
- Create: `app/lib/screens/note_edit_dialog.dart`
- Test: `app/test/screens/note_edit_dialog_test.dart`

**Interfaces:**
- Produces: `showNoteTextDialog(BuildContext, {String initialText, String title}) → Future<String?>`，供 Task 7（`NotesBottomSheet` 編輯既有備註）與 Task 10（`ReaderScreen` 新增備註）共用消費。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/screens/note_edit_dialog_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/note_edit_dialog.dart';

void main() {
  testWidgets('輸入文字後按儲存，回傳已 trim 的文字', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showNoteTextDialog(context, title: '新增備註');
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('新增備註'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('note_edit_dialog_field')), '  這段很重要  ');
    await tester.tap(find.byKey(const Key('note_edit_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(result, '這段很重要');
  });

  testWidgets('文字為空白時按儲存，回傳 null（視同取消）', (tester) async {
    String? result = 'not-set-yet';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showNoteTextDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note_edit_dialog_field')), '   ');
    await tester.tap(find.byKey(const Key('note_edit_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('帶入 initialText 時，輸入框預先顯示該文字', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showNoteTextDialog(context, initialText: '既有備註'),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byKey(const Key('note_edit_dialog_field')));
    expect(field.controller?.text, '既有備註');
  });

  testWidgets('按取消，回傳 null 且不拋出例外（含退場動畫期間）', (tester) async {
    String? result = 'not-set-yet';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showNoteTextDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    // 刻意用逐格 pump（而非 pumpAndSettle）跨過退場轉場動畫的中間幾個
    // frame，驗證此時 TextField 底下的 controller 尚未被過早 dispose
    // 而拋出「used after being disposed」例外（見 Global Constraints
    // 之前 NotesBottomSheet._renameController 已修過的同類問題）。
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/note_edit_dialog_test.dart`
Expected: FAIL（`note_edit_dialog.dart` 尚不存在，編譯錯誤）

- [ ] **Step 3: 實作 `note_edit_dialog.dart`**

建立 `app/lib/screens/note_edit_dialog.dart`：

```dart
import 'package:flutter/material.dart';

/// 備註文字輸入/編輯共用 Dialog（epic-6-annotations Issue 2，design.md
/// 使用者流程步驟 2／3）：`ReaderScreen` 新增備註與 `NotesBottomSheet`
/// 編輯既有備註文字共用同一個函式。回傳使用者輸入且已 trim 的文字；
/// 取消或空白輸入回傳 `null`。
///
/// 【TextEditingController 生命週期】刻意把輸入框包成獨立的
/// `_NoteTextDialog` StatefulWidget，讓 controller 綁定在這個 Dialog
/// 自己的 State——Flutter 只會在這個 Dialog 的 Element 真正從 widget
/// tree 移除（退場轉場動畫跑完）時才呼叫其 `dispose()`，時機天生正確，
/// 不會重蹈 `NotesBottomSheet._renameController` 當初「showDialog 的
/// Future 提早於退場動畫完成前解析、若在此時同步 dispose 控制器會讓底下
/// TextField 在後續幾個 frame 重新 build 時拋出例外」的覆轍（那個問題
/// 之所以發生，是因為 controller 綁定在呼叫端 State、而非 Dialog 自己
/// 的 State）。
Future<String?> showNoteTextDialog(
  BuildContext context, {
  String initialText = '',
  String title = '備註',
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _NoteTextDialog(initialText: initialText, title: title),
  );
}

class _NoteTextDialog extends StatefulWidget {
  final String initialText;
  final String title;

  const _NoteTextDialog({required this.initialText, required this.title});

  @override
  State<_NoteTextDialog> createState() => _NoteTextDialogState();
}

class _NoteTextDialogState extends State<_NoteTextDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('note_edit_dialog_field'),
        controller: _controller,
        autofocus: true,
        maxLines: 4,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('note_edit_dialog_confirm'),
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.of(context).pop(text.isEmpty ? null : text);
          },
          child: const Text('儲存'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/note_edit_dialog_test.dart`
Expected: PASS

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/note_edit_dialog.dart app/test/screens/note_edit_dialog_test.dart
git commit -m "feat(epic-6): 新增備註文字輸入/編輯共用 Dialog"
```

---

### Task 6：`AnnotationToolbar` 浮動工具列 Widget

**Files:**
- Create: `app/lib/screens/annotation_toolbar.dart`
- Test: `app/test/screens/annotation_toolbar_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `HighlightStyle`／色票常數。
- Produces: `AnnotationToolbar({onStyleSelected, onNotePressed})`，供 Task 10（`ReaderScreen`）消費；design.md 明訂 EPUB／PDF 共用同一組 Widget（Issue 3 會直接複用，本 Issue 不含 PDF 專屬邏輯）。

- [ ] **Step 1: 寫失敗測試**

建立 `app/test/screens/annotation_toolbar_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/screens/annotation_toolbar.dart';

void main() {
  testWidgets('顯示螢光筆三色、底線、備註共 5 個按鈕', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(onStyleSelected: (_) {}, onNotePressed: () {}),
      ),
    ));

    expect(find.byKey(const Key('annotation_toolbar_highlighter_yellow')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_highlighter_pink')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_highlighter_blue')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_underline')), findsOneWidget);
    expect(find.byKey(const Key('annotation_toolbar_note')), findsOneWidget);
  });

  testWidgets('點擊黃色螢光筆按鈕觸發 onStyleSelected(highlighterYellow)', (tester) async {
    HighlightStyle? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (style) => selected = style,
          onNotePressed: () {},
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('annotation_toolbar_highlighter_yellow')));
    expect(selected, HighlightStyle.highlighterYellow);
  });

  testWidgets('點擊底線按鈕觸發 onStyleSelected(underline)', (tester) async {
    HighlightStyle? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(
          onStyleSelected: (style) => selected = style,
          onNotePressed: () {},
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('annotation_toolbar_underline')));
    expect(selected, HighlightStyle.underline);
  });

  testWidgets('點擊備註按鈕觸發 onNotePressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnnotationToolbar(onStyleSelected: (_) {}, onNotePressed: () => pressed = true),
      ),
    ));

    await tester.tap(find.byKey(const Key('annotation_toolbar_note')));
    expect(pressed, isTrue);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/annotation_toolbar_test.dart`
Expected: FAIL（`annotation_toolbar.dart` 尚不存在，編譯錯誤）

- [ ] **Step 3: 實作 `AnnotationToolbar`**

建立 `app/lib/screens/annotation_toolbar.dart`：

```dart
import 'package:flutter/material.dart';

import '../reader/highlight_style.dart';

/// 選字/框選後浮現的浮動工具列（design.md「使用者流程」步驟 1-2；
/// EPUB（本 Issue）與 PDF（issues.md Issue 3）共用同一組 Widget）：
/// 螢光筆三色、底線、備註共 5 個按鈕。點擊螢光筆/底線立即觸發
/// [onStyleSelected]（呼叫端負責建立劃線，並保持選取狀態存在讓使用者
/// 能接著點備註，見 design.md 使用者流程「若同時已選色/底線，備註與
/// 劃線共存於同一筆記錄」）；點擊備註觸發 [onNotePressed]（呼叫端負責
/// 另外呼叫 `showNoteTextDialog` 開啟輸入 Dialog，本 Widget 不含 Dialog
/// 邏輯，維持單一職責）。
class AnnotationToolbar extends StatelessWidget {
  final ValueChanged<HighlightStyle> onStyleSelected;
  final VoidCallback onNotePressed;

  const AnnotationToolbar({
    super.key,
    required this.onStyleSelected,
    required this.onNotePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _colorButton(
              key: const Key('annotation_toolbar_highlighter_yellow'),
              color: highlighterYellowTint,
              onTap: () => onStyleSelected(HighlightStyle.highlighterYellow),
            ),
            _colorButton(
              key: const Key('annotation_toolbar_highlighter_pink'),
              color: highlighterPinkTint,
              onTap: () => onStyleSelected(HighlightStyle.highlighterPink),
            ),
            _colorButton(
              key: const Key('annotation_toolbar_highlighter_blue'),
              color: highlighterBlueTint,
              onTap: () => onStyleSelected(HighlightStyle.highlighterBlue),
            ),
            IconButton(
              key: const Key('annotation_toolbar_underline'),
              icon: const Icon(Icons.format_underline),
              tooltip: '底線',
              onPressed: () => onStyleSelected(HighlightStyle.underline),
            ),
            IconButton(
              key: const Key('annotation_toolbar_note'),
              icon: const Icon(Icons.edit_note),
              tooltip: '備註',
              onPressed: onNotePressed,
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorButton({
    required Key key,
    required Color color,
    required VoidCallback onTap,
  }) {
    return IconButton(
      key: key,
      icon: Icon(Icons.circle, color: color),
      onPressed: onTap,
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/screens/annotation_toolbar_test.dart`
Expected: PASS

- [ ] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/annotation_toolbar.dart app/test/screens/annotation_toolbar_test.dart
git commit -m "feat(epic-6): 新增 AnnotationToolbar 浮動工具列 Widget"
```

---

### Task 7：`NotesBottomSheet`「✏️ 劃線與備註」分頁正式生效

**Files:**
- Modify: `app/lib/screens/notes_bottom_sheet.dart`
- Create: `app/test/support/fake_highlights_repository.dart`
- Create: `app/test/support/fake_notes_repository.dart`
- Test: `app/test/screens/notes_bottom_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Highlight`／`Note`／色票／`HighlightStyle.fixedTint`；Task 2 的 `AnnotationListItem`／`mergeAnnotations`；Task 4 的 `HighlightsRepository`／`NotesRepository`；Task 5 的 `showNoteTextDialog`。UI 顯示標籤（例如「螢光筆（黃）」）不從 `reader/highlight_style.dart` 消費——`reader/` 目錄下的列舉刻意不含 UI 字串（審查修正，見 Task 1），本 Task 在 `notes_bottom_sheet.dart` 內自建私有的 `_highlightStyleLabel` 函式（唯一消費端）。
- Produces: `NotesBottomSheet` 新增可選具名參數 `highlightsRepository`／`notesRepository`／`onAnnotationSelected`／`onAnnotationsChanged`（皆 nullable，未提供時「✏️」分頁維持 Issue 1 既有的空狀態佔位符，供 FXL／尚未有 Issue 3 的 PDF 呼叫端零回歸沿用），供 Task 10（`ReaderScreen`）消費。

- [ ] **Step 1: 建立測試用 Fake**

建立 `app/test/support/fake_highlights_repository.dart`：

```dart
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlights_repository.dart';

/// 測試用 Fake，比照 [FakeBookmarksRepository] 模式。
class FakeHighlightsRepository implements HighlightsRepository {
  final List<Highlight> _storage = [];
  int _nextId = 1;

  @override
  Future<int> insert(Highlight highlight) async {
    final id = _nextId++;
    _storage.add(Highlight(
      id: id,
      bookId: highlight.bookId,
      style: highlight.style,
      epubLocatorJson: highlight.epubLocatorJson,
      progression: highlight.progression,
    ));
    return id;
  }

  @override
  Future<List<Highlight>> listByBook(String bookId) async {
    final list = _storage.where((h) => h.bookId == bookId).toList();
    list.sort((a, b) => (a.progression ?? 0).compareTo(b.progression ?? 0));
    return list;
  }

  @override
  Future<void> delete(int id) async {
    _storage.removeWhere((h) => h.id == id);
  }

  @override
  Future<void> deleteAllForBook(String bookId) async {
    _storage.removeWhere((h) => h.bookId == bookId);
  }
}
```

建立 `app/test/support/fake_notes_repository.dart`：

```dart
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/notes_repository.dart';

/// 測試用 Fake。刻意不模擬 FK `ON DELETE SET NULL` 的資料庫層退化行為
/// （那已由 Task 4 的真實 SQLite repository 測試涵蓋）——本 Fake 供
/// widget test 使用，widget test 只需要驗證「假設資料已經是退化後的
/// 狀態」時 UI 是否正確呈現，不需要重新模擬 FK 機制本身。
class FakeNotesRepository implements NotesRepository {
  final List<Note> _storage = [];
  int _nextId = 1;

  @override
  Future<int> insert(Note note) async {
    final id = _nextId++;
    _storage.add(Note(
      id: id,
      bookId: note.bookId,
      text: note.text,
      epubLocatorJson: note.epubLocatorJson,
      progression: note.progression,
      highlightId: note.highlightId,
    ));
    return id;
  }

  @override
  Future<List<Note>> listByBook(String bookId) async {
    final list = _storage.where((n) => n.bookId == bookId).toList();
    list.sort((a, b) => (a.progression ?? 0).compareTo(b.progression ?? 0));
    return list;
  }

  @override
  Future<void> updateText(int id, String text) async {
    final index = _storage.indexWhere((n) => n.id == id);
    if (index == -1) return;
    _storage[index] = _storage[index].copyWith(text: text);
  }

  @override
  Future<void> delete(int id) async {
    _storage.removeWhere((n) => n.id == id);
  }

  @override
  Future<void> deleteAllForBook(String bookId) async {
    _storage.removeWhere((n) => n.bookId == bookId);
  }
}
```

- [ ] **Step 2: 寫失敗測試**

於 `app/test/screens/notes_bottom_sheet_test.dart` 頂部新增 import：

```dart
import 'package:elinkbook/reader/annotation_list_item.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';
```

`_pumpSheet` 輔助函式擴充可選的 `highlightsRepository`／`notesRepository`／`onAnnotationSelected`／`onAnnotationsChanged` 參數並透傳給 `NotesBottomSheet`：

```dart
Future<void> _pumpSheet(
  WidgetTester tester, {
  required FakeBookmarksRepository repository,
  String bookId = 'b1',
  BookmarkPositionContext currentPosition = const BookmarkPositionContext(),
  ValueChanged<Bookmark>? onBookmarkSelected,
  FakeHighlightsRepository? highlightsRepository,
  FakeNotesRepository? notesRepository,
  ValueChanged<AnnotationListItem>? onAnnotationSelected,
  VoidCallback? onAnnotationsChanged,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: NotesBottomSheet(
        bookId: bookId,
        bookmarksRepository: repository,
        currentPosition: currentPosition,
        onBookmarkSelected: onBookmarkSelected ?? (_) {},
        highlightsRepository: highlightsRepository,
        notesRepository: notesRepository,
        onAnnotationSelected: onAnnotationSelected,
        onAnnotationsChanged: onAnnotationsChanged,
      ),
    ),
  ));
  await tester.pump();
}
```

於檔案結尾（最後一個 `}` 之前）新增：

```dart
  testWidgets('未提供 highlightsRepository／notesRepository 時，維持 Issue 1 既有空狀態佔位符',
      (tester) async {
    final repository = FakeBookmarksRepository();
    await _pumpSheet(tester, repository: repository);

    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_sheet_annotations_placeholder')), findsOneWidget);
  });

  testWidgets('提供兩個 repository 後，「劃線與備註」分頁依位置排序顯示合併清單',
      (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    final highlightId = await highlightsRepository.insert(const Highlight(
      bookId: 'b1',
      style: HighlightStyle.highlighterPink,
      progression: 0.2,
    ));
    await notesRepository.insert(
      Note(bookId: 'b1', text: '依附備註', progression: 0.2, highlightId: highlightId),
    );
    await notesRepository.insert(const Note(bookId: 'b1', text: '純備註', progression: 0.5));

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_sheet_annotation_list')), findsOneWidget);
    expect(find.text('螢光筆（粉）'), findsOneWidget);
    expect(find.text('依附備註'), findsOneWidget);
    expect(find.text('純備註'), findsOneWidget);
  });

  testWidgets('點選合併項目觸發 onAnnotationSelected', (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(
      const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.1),
    );
    AnnotationListItem? selected;

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
      onAnnotationSelected: (item) => selected = item,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('底線'));

    expect(selected?.highlight?.style, HighlightStyle.underline);
  });

  testWidgets('編輯備註文字後清單即時反映，且觸發 onAnnotationsChanged', (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    final noteId =
        await notesRepository.insert(const Note(bookId: 'b1', text: '舊文字', progression: 0.1));
    var changedCount = 0;

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
      onAnnotationsChanged: () => changedCount++,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('notes_sheet_annotation_edit_$noteId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note_edit_dialog_field')), '新文字');
    await tester.tap(find.byKey(const Key('note_edit_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('新文字'), findsOneWidget);
    expect(changedCount, greaterThan(0));
  });

  testWidgets('單筆刪除合併項目時，劃線與備註一併刪除', (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    final highlightId = await highlightsRepository.insert(
      const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.1),
    );
    await notesRepository.insert(
      Note(bookId: 'b1', text: '依附備註', progression: 0.1, highlightId: highlightId),
    );

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    final itemKey = 'h${highlightId}_n1';
    await tester.tap(find.byKey(Key('notes_sheet_annotation_delete_$itemKey')));
    await tester.pumpAndSettle();

    expect(await highlightsRepository.listByBook('b1'), isEmpty);
    expect(await notesRepository.listByBook('b1'), isEmpty);
    expect(find.byKey(const Key('notes_sheet_annotations_placeholder')), findsOneWidget);
  });

  testWidgets('批次刪除所有劃線：確認對話框顯示正確筆數，確認後劃線清單清空',
      (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(
      const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.1),
    );
    await highlightsRepository.insert(
      const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.2),
    );

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notes_sheet_delete_all_highlights')));
    await tester.pumpAndSettle();
    expect(find.textContaining('2'), findsWidgets);

    await tester.tap(find.byKey(const Key('notes_sheet_delete_all_highlights_confirm')));
    await tester.pumpAndSettle();

    expect(await highlightsRepository.listByBook('b1'), isEmpty);
    expect(find.byKey(const Key('notes_sheet_annotations_placeholder')), findsOneWidget);
  });

  testWidgets(
      '已退化的純備註（highlightId 已為 null，模擬真實資料庫 FK ON DELETE SET NULL '
      'cascade 之後的狀態——真正的 cascade 行為本身由 Task 4 對真實 SQLite 的 '
      'notes_repository_test.dart 驗證，本測試不重複模擬那段邏輯，Fake 之間也刻意'
      '不互相協調）：批次刪除所有劃線後，這筆早已獨立存在的純備註不受影響，仍正確'
      '顯示在清單中', (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(
      const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.1),
    );
    // 直接建構「已退化」狀態（highlightId: null），而非先建立一筆連結中的
    // 備註再期待 Fake 自動模擬 cascade——兩個 Fake 刻意保持互不協調（見
    // Global Constraints／FakeNotesRepository 既有 KDoc），避免在測試替身
    // 裡重新實作一份可能與真實資料庫語意逐漸失準的 FK cascade 邏輯。
    await notesRepository.insert(
      const Note(bookId: 'b1', text: '已退化的純備註', progression: 0.3, highlightId: null),
    );

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notes_sheet_delete_all_highlights')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_delete_all_highlights_confirm')));
    await tester.pumpAndSettle();

    expect(await highlightsRepository.listByBook('b1'), isEmpty);
    expect(find.text('已退化的純備註'), findsOneWidget);
    expect(find.byKey(const Key('notes_sheet_annotations_placeholder')), findsNothing);
  });

  testWidgets('批次刪除所有備註：取消不刪除，確認後備註消失、劃線不受影響', (tester) async {
    final repository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();
    await highlightsRepository.insert(
      const Highlight(bookId: 'b1', style: HighlightStyle.underline, progression: 0.1),
    );
    await notesRepository.insert(const Note(bookId: 'b1', text: '純備註', progression: 0.5));

    await _pumpSheet(
      tester,
      repository: repository,
      highlightsRepository: highlightsRepository,
      notesRepository: notesRepository,
    );
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notes_sheet_delete_all_notes')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await notesRepository.listByBook('b1'), hasLength(1));

    await tester.tap(find.byKey(const Key('notes_sheet_delete_all_notes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_delete_all_notes_confirm')));
    await tester.pumpAndSettle();

    expect(await notesRepository.listByBook('b1'), isEmpty);
    expect(await highlightsRepository.listByBook('b1'), hasLength(1));
  });
```

- [ ] **Step 3: 執行測試確認失敗**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: FAIL（`NotesBottomSheet` 建構子尚無 `highlightsRepository` 等新參數，編譯錯誤）

- [ ] **Step 4: 擴充 `NotesBottomSheet`**

`app/lib/screens/notes_bottom_sheet.dart` 頂部新增 import：

```dart
import '../reader/annotation_list_item.dart';
import '../reader/highlight.dart';
import '../reader/highlight_style.dart';
import '../reader/highlights_repository.dart';
import '../reader/note.dart';
import '../reader/notes_repository.dart';
import 'note_edit_dialog.dart';
```

建構子新增可選具名參數（緊接在既有 `onBookmarkSelected` 之後）：

```dart
  /// 劃線／備註資料存取層（epic-6-annotations Issue 2）。兩者皆為
  /// 可選具名參數，且必須「同時提供」才會顯示真實內容——未提供（或只提供
  /// 其中一個）時「✏️」分頁維持 Issue 1 既有的空狀態佔位符，讓 FXL
  /// （不支援劃線/備註，見 issues.md Issue 4）與尚未做完 Issue 3 的 PDF
  /// 呼叫端零回歸沿用。
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;

  /// 使用者點選某筆合併項目時觸發，呼叫端負責實際跳轉並關閉本 Bottom
  /// Sheet（比照 [onBookmarkSelected] 既有模式）。
  final ValueChanged<AnnotationListItem>? onAnnotationSelected;

  /// 本 Bottom Sheet 內任何劃線/備註 CRUD 動作完成後觸發，供呼叫端
  /// （ReaderScreen）重新查詢並把最新標記清單送給原生端重繪 Decorator
  /// （見 Task 10）。
  final VoidCallback? onAnnotationsChanged;

  const NotesBottomSheet({
    super.key,
    required this.bookId,
    required this.bookmarksRepository,
    required this.currentPosition,
    required this.onBookmarkSelected,
    this.highlightsRepository,
    this.notesRepository,
    this.onAnnotationSelected,
    this.onAnnotationsChanged,
  });
```

`_NotesBottomSheetState` 新增欄位與初始載入：

```dart
  List<Highlight> _highlights = [];
  List<Note> _notes = [];
```

`initState` 內 `_loadBookmarks();` 之後新增 `_loadAnnotations();`：

```dart
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBookmarks();
    _loadAnnotations();
  }
```

`_loadBookmarks` 方法之後新增：

```dart
  Future<void> _loadAnnotations() async {
    final highlightsRepository = widget.highlightsRepository;
    final notesRepository = widget.notesRepository;
    if (highlightsRepository == null || notesRepository == null) return;
    final highlights = await highlightsRepository.listByBook(widget.bookId);
    final notes = await notesRepository.listByBook(widget.bookId);
    if (!mounted) return;
    setState(() {
      _highlights = highlights;
      _notes = notes;
    });
  }
```

`build()` 內 `TabBarView` 的第二個 child（原本的靜態佔位符）改為呼叫新方法：

```dart
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBookmarksTab(),
                  _buildAnnotationsTab(),
                ],
              ),
            ),
```

在 `_buildBookmarkRow` 方法之後新增：

```dart
  Widget _buildAnnotationsTab() {
    final highlightsRepository = widget.highlightsRepository;
    final notesRepository = widget.notesRepository;
    if (highlightsRepository == null || notesRepository == null) {
      return const Center(
        child: Text('尚無劃線或備註', key: Key('notes_sheet_annotations_placeholder')),
      );
    }
    final items = mergeAnnotations(_highlights, _notes);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('notes_sheet_delete_all_highlights'),
                  onPressed: _highlights.isEmpty ? null : _confirmDeleteAllHighlights,
                  child: const Text('刪除所有劃線'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const Key('notes_sheet_delete_all_notes'),
                  onPressed: _notes.isEmpty ? null : _confirmDeleteAllNotes,
                  child: const Text('刪除所有備註'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text('尚無劃線或備註', key: Key('notes_sheet_annotations_placeholder')),
                )
              : ListView.builder(
                  key: const Key('notes_sheet_annotation_list'),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _buildAnnotationRow(items[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildAnnotationRow(AnnotationListItem item) {
    final highlight = item.highlight;
    final note = item.note;
    return ListTile(
      key: Key('notes_sheet_annotation_${item.key}'),
      leading: Icon(
        Icons.circle,
        color: highlight != null
            ? Color(highlightStyleTint(highlight.style,
                primaryColor: Theme.of(context).colorScheme.primary))
            : noteOnlyTint,
      ),
      title: Text(highlight != null ? _highlightStyleLabel(highlight.style) : '📌 備註'),
      subtitle: note != null
          ? Text(note.text, maxLines: 2, overflow: TextOverflow.ellipsis)
          : null,
      onTap: () => widget.onAnnotationSelected?.call(item),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (note != null)
            IconButton(
              key: Key('notes_sheet_annotation_edit_${note.id}'),
              icon: const Icon(Icons.edit),
              tooltip: '編輯備註',
              onPressed: () => _editNoteText(note),
            ),
          IconButton(
            key: Key('notes_sheet_annotation_delete_${item.key}'),
            icon: const Icon(Icons.delete),
            tooltip: '刪除',
            onPressed: () => _deleteAnnotationItem(item),
          ),
        ],
      ),
    );
  }

  /// 供劃線清單項目顯示用的中文標籤。【審查修正】刻意不放在
  /// `reader/highlight_style.dart`（領域模型層）——`reader/` 目錄下的其他
  /// 列舉（`BookFormat`／`WritingMode`／`PdfCropMode` 等）皆不含 UI 顯示
  /// 字串，是純格式無關的領域模型；本函式是唯一消費端，收斂在這裡避免
  /// 領域模型檔案摻雜 UI 層級的字串常數。
  String _highlightStyleLabel(HighlightStyle style) {
    switch (style) {
      case HighlightStyle.highlighterYellow:
        return '螢光筆（黃）';
      case HighlightStyle.highlighterPink:
        return '螢光筆（粉）';
      case HighlightStyle.highlighterBlue:
        return '螢光筆（藍）';
      case HighlightStyle.underline:
        return '底線';
    }
  }

  Future<void> _editNoteText(Note note) async {
    final newText = await showNoteTextDialog(context, initialText: note.text, title: '編輯備註');
    if (newText == null) return;
    await widget.notesRepository!.updateText(note.id!, newText);
    await _loadAnnotations();
    widget.onAnnotationsChanged?.call();
  }

  /// 單筆刪除＝整筆一起刪（spec.md 決策 #13）：不依賴 FK `ON DELETE SET
  /// NULL` 的自動退化（那是給批次刪除劃線情境用的），明確分別刪除兩張表
  /// 各自的列。
  Future<void> _deleteAnnotationItem(AnnotationListItem item) async {
    if (item.note != null) await widget.notesRepository!.delete(item.note!.id!);
    if (item.highlight != null) await widget.highlightsRepository!.delete(item.highlight!.id!);
    await _loadAnnotations();
    widget.onAnnotationsChanged?.call();
  }

  Future<void> _confirmDeleteAllHighlights() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('確定要刪除全部劃線嗎？（共 ${_highlights.length} 筆）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('notes_sheet_delete_all_highlights_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.highlightsRepository!.deleteAllForBook(widget.bookId);
    await _loadAnnotations();
    widget.onAnnotationsChanged?.call();
  }

  Future<void> _confirmDeleteAllNotes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('確定要刪除全部備註嗎？（共 ${_notes.length} 筆）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('notes_sheet_delete_all_notes_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.notesRepository!.deleteAllForBook(widget.bookId);
    await _loadAnnotations();
    widget.onAnnotationsChanged?.call();
  }
```

- [ ] **Step 5: 執行測試確認通過**

Run: `flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: PASS（全部測試綠燈，含 Issue 1 既有測試不受影響）

- [ ] **Step 6: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/notes_bottom_sheet.dart app/test/support/fake_highlights_repository.dart app/test/support/fake_notes_repository.dart app/test/screens/notes_bottom_sheet_test.dart
git commit -m "feat(epic-6): NotesBottomSheet「劃線與備註」分頁正式生效"
```

---

### Task 8：`EpubReaderView.dart`——選取事件／標記啟用事件／`setDecorations` 契約擴充

**Files:**
- Create: `app/lib/reader/percent_rect.dart`
- Create: `app/lib/reader/epub_selection_info.dart`
- Create: `app/lib/reader/epub_decoration.dart`
- Modify: `app/lib/reader/epub_reader_view.dart`
- Test: `app/test/reader/percent_rect_test.dart`
- Test: `app/test/reader/epub_selection_info_test.dart`
- Test: `app/test/reader/epub_decoration_test.dart`
- Test: `app/test/reader/epub_reader_view_test.dart`

**Interfaces:**
- Produces: `PercentRect`（`left`/`top`/`right`/`bottom`，`==`/`hashCode`，審查修正——見下方 Step 1-2）；`EpubSelectionInfo`（`locatorJson`/`progression`/`rect: PercentRect`）；`EpubDecoration`（`id`/`locatorJson`/`tint`/`isUnderline`，`toWire()`，`EpubDecoration.forHighlight(...)`/`EpubDecoration.forNote(...)` 具名建構子）；`AnnotationKind`／`decodeAnnotationId(String) → ({AnnotationKind kind, int id})?`（審查修正，見下方 Step 5-6）；`EpubReaderView` 新增 `onSelectionChanged`/`onSelectionCleared`/`onAnnotationActivated` 建構參數與 `EpubReaderView.setDecorations(key, List<EpubDecoration>)` 靜態方法，供 Task 10（`ReaderScreen`）消費；`EpubReaderView.kt`（Task 9）為其原生對應端。

- [ ] **Step 1: 寫失敗測試（`percent_rect_test.dart`，審查修正：抽出獨立值物件取代 `EpubSelectionInfo` 內 4 個高度相關的百分比欄位）**

建立 `app/test/reader/percent_rect_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  test('四個欄位值完全相同的 PercentRect 視為相等', () {
    const a = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
    const b = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('任一欄位不同時視為不相等', () {
    const a = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
    const b = PercentRect(left: 0.15, top: 0.2, right: 0.3, bottom: 0.4);
    expect(a, isNot(b));
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/percent_rect_test.dart`
Expected: FAIL（`percent_rect.dart` 尚不存在，編譯錯誤）

- [ ] **Step 3: 實作 `PercentRect`**

建立 `app/lib/reader/percent_rect.dart`：

```dart
/// 相對容器寬高的百分比矩形（0.0-1.0），比照 design.md 決策 #15 對 PDF
/// 框選座標的既有百分比慣例。目前供 [EpubSelectionInfo] 使用；Issue 3
/// （PDF 長按框選，見 issues.md）預期會有結構相同的座標傳遞需求，屆時可
/// 直接複用本類別，不需再各自宣告一組同義欄位（審查修正：原本
/// `leftPct`/`topPct`/`rightPct`/`bottomPct` 四個高度相關欄位直接散落
/// 宣告在 `EpubSelectionInfo` 內，屬於「總是同時出現、應封裝為單一物件」
/// 的資料泥團，收斂為獨立值物件）。
class PercentRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const PercentRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  @override
  bool operator ==(Object other) =>
      other is PercentRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'PercentRect(left: $left, top: $top, right: $right, bottom: $bottom)';
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/percent_rect_test.dart`
Expected: PASS

- [ ] **Step 5: 寫失敗測試（`epub_selection_info_test.dart`）**

建立 `app/test/reader/epub_selection_info_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  test('兩個欄位值完全相同的 EpubSelectionInfo 視為相等', () {
    const a = EpubSelectionInfo(
      locatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.2,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
    );
    const b = EpubSelectionInfo(
      locatorJson: '{"href":"/c1.xhtml"}',
      progression: 0.2,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
```

- [ ] **Step 6: 執行測試確認失敗**

Run: `flutter test test/reader/epub_selection_info_test.dart`
Expected: FAIL（`epub_selection_info.dart` 尚不存在，編譯錯誤）

- [ ] **Step 7: 實作 `EpubSelectionInfo`**

建立 `app/lib/reader/epub_selection_info.dart`：

```dart
import 'percent_rect.dart';

/// [EpubReaderView] 使用者原生選字手勢建立/變動選取範圍時回報的資訊
/// （epic-6-annotations Issue 2）。[rect] 為選取矩形相對於 AndroidView
/// 容器寬高的百分比值（見 [PercentRect]），供 Dart 端在
/// `ReaderScreen._buildBody` 既有的 Stack 座標系內定位浮動工具列。
class EpubSelectionInfo {
  final String locatorJson;
  final double? progression;
  final PercentRect rect;

  const EpubSelectionInfo({
    required this.locatorJson,
    this.progression,
    required this.rect,
  });

  @override
  bool operator ==(Object other) =>
      other is EpubSelectionInfo &&
      other.locatorJson == locatorJson &&
      other.progression == progression &&
      other.rect == rect;

  @override
  int get hashCode => Object.hash(locatorJson, progression, rect);

  @override
  String toString() =>
      'EpubSelectionInfo(locatorJson: $locatorJson, progression: $progression, rect: $rect)';
}
```

- [ ] **Step 8: 執行測試確認通過**

Run: `flutter test test/reader/epub_selection_info_test.dart`
Expected: PASS

- [ ] **Step 9: 寫失敗測試（`epub_decoration_test.dart`）**

建立 `app/test/reader/epub_decoration_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/epub_decoration.dart';

void main() {
  test('EpubDecoration.forHighlight／forNote 產生正確的 id 編碼與 wire 格式', () {
    final highlight = EpubDecoration.forHighlight(
      highlightId: 12,
      locatorJson: '{"href":"/c1.xhtml"}',
      tint: 0x73FDE047,
      isUnderline: false,
    );
    expect(highlight.id, 'highlight:12');
    expect(highlight.toWire()['isUnderline'], isFalse);

    final note = EpubDecoration.forNote(
      noteId: 7,
      locatorJson: '{"href":"/c2.xhtml"}',
      tint: 0x73D1D5DB,
    );
    expect(note.id, 'note:7');
  });

  test('decodeAnnotationId 正確解析 "highlight:<id>"／"note:<id>"', () {
    expect(decodeAnnotationId('highlight:12'), (kind: AnnotationKind.highlight, id: 12));
    expect(decodeAnnotationId('note:7'), (kind: AnnotationKind.note, id: 7));
  });

  test('decodeAnnotationId 對格式不符的字串回傳 null（不拋出例外）', () {
    expect(decodeAnnotationId('malformed'), isNull);
    expect(decodeAnnotationId('highlight:not-a-number'), isNull);
    expect(decodeAnnotationId('unknown-kind:1'), isNull);
  });
}
```

- [ ] **Step 10: 執行測試確認失敗**

Run: `flutter test test/reader/epub_decoration_test.dart`
Expected: FAIL（`epub_decoration.dart` 尚不存在，編譯錯誤）

- [ ] **Step 11: 實作 `EpubDecoration`**

建立 `app/lib/reader/epub_decoration.dart`：

```dart
/// 單筆「劃線/純備註」的原生疊加樣式資訊（epic-6-annotations Issue 2），
/// 供 [EpubReaderView.setDecorations] 一次性送出目前應顯示的完整標記
/// 清單（非增量 diff，比照既有 `setPreferences`「整組送出目前狀態」
/// 慣例）。[id] 一律由 [forHighlight]／[forNote] 這兩個具名建構子產生
/// （審查修正：原本由呼叫端〔ReaderScreen〕直接手動字串拼接
/// `'highlight:${h.id}'`，散落各處且缺乏型別安全，收斂為本類別自己的
/// 具名建構子，搭配 [decodeAnnotationId] 做反向解析，兩者對稱維護在
/// 同一個檔案）。[tint] 為完整 ARGB 色值（見 highlight_style.dart「色彩
/// 決策收斂在 Dart 端」），原生端不需維護色彩對照表。[isUnderline] 為
/// true 時原生端套用 `Decoration.Style.Underline`，否則套用
/// `Style.Highlight`（螢光筆三色與純備註灰底皆屬此類）。
class EpubDecoration {
  final String id;
  final String locatorJson;
  final int tint;
  final bool isUnderline;

  const EpubDecoration({
    required this.id,
    required this.locatorJson,
    required this.tint,
    this.isUnderline = false,
  });

  factory EpubDecoration.forHighlight({
    required int highlightId,
    required String locatorJson,
    required int tint,
    required bool isUnderline,
  }) {
    return EpubDecoration(
      id: 'highlight:$highlightId',
      locatorJson: locatorJson,
      tint: tint,
      isUnderline: isUnderline,
    );
  }

  factory EpubDecoration.forNote({
    required int noteId,
    required String locatorJson,
    required int tint,
  }) {
    return EpubDecoration(id: 'note:$noteId', locatorJson: locatorJson, tint: tint);
  }

  Map<String, Object?> toWire() => {
        'id': id,
        'locatorJson': locatorJson,
        'tint': tint,
        'isUnderline': isUnderline,
      };
}

/// 標記種類，對應 [EpubDecoration.id] 的字串前綴（`"highlight"`／
/// `"note"`）。
enum AnnotationKind { highlight, note }

/// 解析原生端 `onAnnotationActivated` 回傳的標記 id 字串（見
/// [EpubDecoration.forHighlight]/[EpubDecoration.forNote] 的編碼慣例），
/// 供 `ReaderScreen` 反查是哪一張表的哪一筆資料庫記錄（審查修正：原本
/// `decorationId.split(':')` 與 `parts[1]` 這種型別不安全的字串操作直接
/// 寫在 `ReaderScreen` 內，收斂為單一、集中管理的解析函式）。格式不符
/// （前綴非 `highlight`/`note`、或 id 部分不是合法整數）時回傳 `null`，
/// 不拋出例外——理論上不會發生（id 皆由本檔案的具名建構子產生），但呼叫
/// 端仍須以「查無對應記錄」的靜默忽略原則處理，見 spec.md 既有慣例。
DecodedAnnotationId? decodeAnnotationId(String encoded) {
  final parts = encoded.split(':');
  if (parts.length != 2) return null;
  final id = int.tryParse(parts[1]);
  if (id == null) return null;
  final AnnotationKind? kind = switch (parts[0]) {
    'highlight' => AnnotationKind.highlight,
    'note' => AnnotationKind.note,
    _ => null,
  };
  if (kind == null) return null;
  return (kind: kind, id: id);
}

/// [decodeAnnotationId] 的回傳型別（Dart 3 record），比宣告一個只有兩個
/// 唯讀欄位的小型 class 更精簡。
typedef DecodedAnnotationId = ({AnnotationKind kind, int id});
```

- [ ] **Step 12: 執行測試確認通過**

Run: `flutter test test/reader/epub_decoration_test.dart`
Expected: PASS

- [ ] **Step 13: 執行 `flutter analyze` 確認乾淨（本 Task 中途檢查點）**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 14: 寫失敗測試（擴充 `epub_reader_view_test.dart`）**

於 `app/test/reader/epub_reader_view_test.dart` 頂部新增 import：

```dart
import 'package:elinkbook/reader/epub_decoration.dart';
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';
```

於檔案結尾（最後一個 `}` 之前）新增：

```dart
  testWidgets('收到原生端 onSelectionChanged 事件時正確解析 EpubSelectionInfo',
      (tester) async {
    EpubSelectionInfo? received;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onSelectionChanged: (info) => received = info,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onSelectionChanged', {
      'locatorJson': '{"href":"/c1.xhtml"}',
      'progression': 0.2,
      'leftPct': 0.1,
      'topPct': 0.2,
      'rightPct': 0.3,
      'bottomPct': 0.4,
    }));
    await binaryMessenger.handlePlatformMessage(
        instanceChannel!.name, data, (_) {});

    expect(
      received,
      const EpubSelectionInfo(
        locatorJson: '{"href":"/c1.xhtml"}',
        progression: 0.2,
        rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
      ),
    );
  });

  testWidgets('收到原生端 onSelectionCleared 事件時觸發 callback', (tester) async {
    var cleared = false;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onSelectionCleared: () => cleared = true,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onSelectionCleared', null));
    await binaryMessenger.handlePlatformMessage(instanceChannel!.name, data, (_) {});

    expect(cleared, isTrue);
  });

  testWidgets('收到原生端 onAnnotationActivated 事件時傳回標記 id 字串',
      (tester) async {
    String? activatedId;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: EpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        onAnnotationActivated: (id) => activatedId = id,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data =
        codec.encodeMethodCall(const MethodCall('onAnnotationActivated', 'highlight:12'));
    await binaryMessenger.handlePlatformMessage(instanceChannel!.name, data, (_) {});

    expect(activatedId, 'highlight:12');
  });

  testWidgets('setDecorations 呼叫原生端時正確序列化 EpubDecoration 清單',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/epub_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(instanceChannel!, (call) async {
          instanceCalls.add(call);
          return null;
        });
        return 0;
      }
      return null;
    });

    final key = GlobalKey<State<EpubReaderView>>();
    await tester.pumpWidget(MaterialApp(
      home: EpubReaderView(
        key: key,
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();

    EpubReaderView.setDecorations(key, [
      EpubDecoration.forHighlight(
        highlightId: 1,
        locatorJson: '{"href":"/c1.xhtml"}',
        tint: 0x73FDE047,
        isUnderline: false,
      ),
      EpubDecoration.forHighlight(
        highlightId: 2,
        locatorJson: '{"href":"/c2.xhtml"}',
        tint: 0xFF6750A4,
        isUnderline: true,
      ),
    ]);

    final call = instanceCalls.singleWhere((c) => c.method == 'setDecorations');
    final decorations =
        (call.arguments as Map<Object?, Object?>)['decorations'] as List<Object?>;
    expect(decorations, hasLength(2));
    expect((decorations[0] as Map<Object?, Object?>)['id'], 'highlight:1');
    expect((decorations[1] as Map<Object?, Object?>)['isUnderline'], isTrue);
  });
```

- [ ] **Step 15: 執行測試確認失敗**

Run: `flutter test test/reader/epub_reader_view_test.dart`
Expected: FAIL（`EpubReaderView` 尚無 `onSelectionChanged`/`onSelectionCleared`/`onAnnotationActivated` 建構參數與 `setDecorations` 靜態方法，編譯錯誤）

- [ ] **Step 16: 擴充 `EpubReaderView.dart`**

`app/lib/reader/epub_reader_view.dart` 頂部新增 import：

```dart
import 'epub_decoration.dart';
import 'epub_selection_info.dart';
import 'percent_rect.dart';
```

`EpubReaderView` class 內，`onCharacterCountReady` 欄位之後新增：

```dart
  /// 使用者原生選字手勢建立/變動選取範圍時觸發（epic-6-annotations
  /// Issue 2），供呼叫端顯示浮動工具列。
  final ValueChanged<EpubSelectionInfo>? onSelectionChanged;

  /// 選取範圍被清除時觸發（原生端 ActionMode 銷毀，例如使用者點擊選取
  /// 範圍以外的地方），供呼叫端收起浮動工具列。
  final VoidCallback? onSelectionCleared;

  /// 使用者點擊既有劃線/備註標記時觸發，傳回該筆標記的 id 字串（見
  /// `EpubDecoration` 的 id 編碼慣例 `"highlight:<id>"`／`"note:<id>"`），
  /// 供呼叫端開啟編輯/刪除 Dialog。
  final ValueChanged<String>? onAnnotationActivated;
```

建構子參數列新增對應項目：

```dart
    this.onSelectionChanged,
    this.onSelectionCleared,
    this.onAnnotationActivated,
  });
```

`jumpToLocator` 靜態方法之後新增：

```dart
  /// 把目前應顯示的完整標記清單一次性送給原生端（比照既有
  /// `setPreferences` 整組送出慣例，非增量 diff），供 Readium
  /// `applyDecorations` 疊加視覺樣式。
  static void setDecorations(
    GlobalKey<State<EpubReaderView>> key,
    List<EpubDecoration> decorations,
  ) {
    final state = key.currentState;
    if (state is _EpubReaderViewState) {
      state._channel?.invokeMethod('setDecorations', {
        'decorations': decorations.map((d) => d.toWire()).toList(),
      });
    }
  }
```

`_handleMethodCall` 的 `switch` 內，`onCharacterCountReady` 分支之後新增：

```dart
      case 'onSelectionChanged':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onSelectionChanged?.call(EpubSelectionInfo(
          locatorJson: args['locatorJson'] as String,
          progression: (args['progression'] as num?)?.toDouble(),
          rect: PercentRect(
            left: (args['leftPct'] as num).toDouble(),
            top: (args['topPct'] as num).toDouble(),
            right: (args['rightPct'] as num).toDouble(),
            bottom: (args['bottomPct'] as num).toDouble(),
          ),
        ));
        break;
      case 'onSelectionCleared':
        widget.onSelectionCleared?.call();
        break;
      case 'onAnnotationActivated':
        widget.onAnnotationActivated?.call(call.arguments as String);
        break;
```

- [ ] **Step 17: 執行測試確認通過**

Run: `flutter test test/reader/epub_reader_view_test.dart`
Expected: PASS（全部測試綠燈，含既有測試不受影響）

- [ ] **Step 18: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 19: Commit**

```bash
git add app/lib/reader/percent_rect.dart app/lib/reader/epub_selection_info.dart app/lib/reader/epub_decoration.dart app/lib/reader/epub_reader_view.dart app/test/reader/percent_rect_test.dart app/test/reader/epub_selection_info_test.dart app/test/reader/epub_decoration_test.dart app/test/reader/epub_reader_view_test.dart
git commit -m "feat(epic-6): EpubReaderView.dart 新增選取事件／標記啟用事件／setDecorations 契約"
```

---

### Task 9：`EpubReaderView.kt`——原生端選字攔截、Decorator 疊加、標記點擊

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`

**Interfaces:**
- Consumes: Task 8 的 Dart 端 method channel 契約（`setDecorations` 呼叫、`onSelectionChanged`/`onSelectionCleared`/`onAnnotationActivated` 回呼）。
- Produces: 原生端對稱實作，無新增 Dart 型別。本 Task 無 `app/test/` 單元測試（純 Kotlin 原生邏輯，比照專案既有兩層測試架構——`app/test/` 不 mock 原生 method channel，真機互動驗證留給 Task 11 的 `integration_test`）；只以 `flutter analyze`（確認 Dart 端未受影響）與 Kotlin 編譯通過作為本 Task 驗證手段。

- [ ] **Step 1: 新增 import**

`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` 頂部新增：

```kotlin
import android.view.ActionMode
import android.view.Menu
import org.readium.r2.navigator.DecorableNavigator
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.Selection
import org.readium.r2.navigator.html.HtmlDecorationTemplates
import org.readium.r2.navigator.util.BaseActionModeCallback
```

- [ ] **Step 2: 新增群組常數與內部欄位**

於 `companion object` 內（`isDualPageEnabled` 之後）新增：

```kotlin
        /** applyDecorations／addDecorationListener 使用的群組鍵，任取一個
         * 在整個 App 內唯一的字串即可，不需要與其他任何既有機制對應。*/
        internal const val ANNOTATIONS_DECORATION_GROUP = "elinkbook_annotations"
```

於 `dualPageMode`/`isLandscape` 欄位之後（`init` 之前）新增：

```kotlin
    /** 標記點擊監聽器，dispose() 時需要用同一個實例呼叫
     * removeDecorationListener，故保留參照（見 Decoration.kt
     * addDecorationListener／removeDecorationListener 簽章）。*/
    private var decorationListener: DecorableNavigator.Listener? = null
```

- [ ] **Step 3: 新增 `SelectionActionModeCallback` 內部類別**

在 `applyFxlFitScale`/`removeFxlLayoutListener` 方法之後新增：

```kotlin
    /**
     * 攔截 Readium 原生選字工具列（epic-6-annotations Issue 2，design.md
     * 決策：改由 Flutter 端 `AnnotationToolbar` 接手顯示浮動工具列）。
     *
     * 【審查修正，重要】`onCreateActionMode` 必須回傳 `true`，**不能**回傳
     * `false`——這是 Android `ActionMode.Callback` 官方文件明訂的契約：
     * 回傳 `false` 代表整個 ActionMode 生命週期直接不建立，其後
     * `onDestroyActionMode` 也「不會」被呼叫（非 Readium 特有行為，是
     * Android SDK 本身的標準行為）。若回傳 `false`，`onSelectionCleared`
     * 事件永遠不會送出，Flutter 端浮動工具列會卡在畫面上收不起來。改為
     * 回傳 `true`（讓 ActionMode 正常建立、生命週期正常運作），並在
     * `menu?.clear()` 清空選單項目，讓原生 Cut/Copy/Share 等按鈕不會
     * 顯示——視覺效果與原本「不顯示原生選單」的意圖相同，但透過清空選單
     * 內容達成，而非跳過整個生命週期。
     *
     * 同時在 `onCreateActionMode` 當下呼叫 `currentSelection()`
     * （suspend）取得選取範圍的 Locator／矩形，回報給 Dart 端。
     *
     * `onDestroyActionMode` 現在能正常在使用者點擊選取範圍以外的地方
     * （原生選取被清除）時觸發，通知 Dart 端收起浮動工具列。先呼叫
     * `super.onDestroyActionMode()`——`BaseActionModeCallback` 本身可能有
     * Readium 內部需要的清理邏輯，本類別只是附加通知，不取代它。
     */
    private inner class SelectionActionModeCallback : BaseActionModeCallback() {
        override fun onCreateActionMode(mode: ActionMode?, menu: Menu?): Boolean {
            menu?.clear()
            scope.launch {
                val selection = navigatorFragment?.currentSelection() ?: return@launch
                if (!isDisposed) reportSelectionChanged(selection)
            }
            return true
        }

        override fun onDestroyActionMode(mode: ActionMode) {
            super.onDestroyActionMode(mode)
            if (!isDisposed) channel.invokeMethod("onSelectionCleared", null)
        }
    }

    /**
     * 把 [selection] 換算成相對於 [container] 寬高的百分比矩形送給 Dart
     * 端（見 Global Constraints「選取矩形座標協定」）。流式 EPUB
     * （本 Issue 範圍，FXL 排除）不像 `applyFxlFitScale()` 那樣對 WebView
     * 做額外縮放/位移變換，故 `Selection.rect` 可視為已經是相對
     * [container] 座標系的量測結果，不需要額外的座標轉換——此假設留待
     * Task 11 真機測試驗證（見 issues.md 驗收標準）。
     */
    private fun reportSelectionChanged(selection: Selection) {
        val width = container.width.toFloat()
        val height = container.height.toFloat()
        if (width <= 0 || height <= 0) return
        val rect = selection.rect
        channel.invokeMethod(
            "onSelectionChanged",
            mapOf(
                "locatorJson" to selection.locator.toJSON().toString(),
                "progression" to selection.locator.locations.totalProgression,
                "leftPct" to (rect.left / width).toDouble(),
                "topPct" to (rect.top / height).toDouble(),
                "rightPct" to (rect.right / width).toDouble(),
                "bottomPct" to (rect.bottom / height).toDouble(),
            ),
        )
    }
```

- [ ] **Step 4: 於 `onMethodCall` 新增 `setDecorations` 分支**

`jumpToLocator` 分支之後新增：

```kotlin
            "setDecorations" -> {
                @Suppress("UNCHECKED_CAST")
                val list = call.argument<List<Map<String, Any?>>>("decorations") ?: emptyList()
                scope.launch {
                    applyDecorationsFromWire(list)
                    if (!isDisposed) result.success(null)
                }
            }
```

- [ ] **Step 5: 新增 `applyDecorationsFromWire`**

在 `reportSelectionChanged` 方法之後新增：

```kotlin
    /**
     * 把 Dart 端送來的完整標記清單（見
     * app/lib/reader/epub_decoration.dart `EpubDecoration.toWire()`）
     * 轉換為 Readium `Decoration` 清單並整組套用（`applyDecorations`
     * 本身是「取代目前該群組全部標記」語意，非增量新增，比照
     * `EpubPreferences` 整組送出的既有慣例）。單筆解析失敗（例如
     * locatorJson 格式錯誤）時該筆略過，不影響其餘標記，比照本檔案既有
     * 對非致命錯誤的處理原則（見 `jumpToLocator` 分支）。
     */
    private suspend fun applyDecorationsFromWire(list: List<Map<String, Any?>>) {
        val nav = navigatorFragment ?: return
        val decorations = list.mapNotNull { entry ->
            val id = entry["id"] as? String ?: return@mapNotNull null
            val locatorJson = entry["locatorJson"] as? String ?: return@mapNotNull null
            val tint = (entry["tint"] as? Number)?.toInt() ?: return@mapNotNull null
            val isUnderline = entry["isUnderline"] as? Boolean ?: false
            val locator = try {
                Locator.fromJSON(JSONObject(locatorJson))
            } catch (e: Exception) {
                null
            } ?: return@mapNotNull null
            val style: Decoration.Style = if (isUnderline) {
                Decoration.Style.Underline(tint = tint, isActive = false)
            } else {
                Decoration.Style.Highlight(tint = tint, isActive = false)
            }
            Decoration(id = id, locator = locator, style = style)
        }
        if (isDisposed) return
        nav.applyDecorations(decorations, ANNOTATIONS_DECORATION_GROUP)
    }
```

- [ ] **Step 6: 在 `attachNavigator()` 內註冊標記點擊監聽器**

於 `attachNavigator()` 內，`navigatorFragment?.currentLocator?.onEach { ... }?.launchIn(scope)` 陳述式之後新增：

```kotlin
            // epic-6-annotations Issue 2：標記點擊事件（design.md 使用者
            // 流程步驟 3：「點擊既有劃線/備註 → 開啟編輯 Dialog」）。
            val listener = object : DecorableNavigator.Listener {
                override fun onDecorationActivated(
                    event: DecorableNavigator.OnActivatedEvent,
                ): Boolean {
                    channel.invokeMethod("onAnnotationActivated", event.decoration.id)
                    return true
                }
            }
            decorationListener = listener
            navigatorFragment?.addDecorationListener(ANNOTATIONS_DECORATION_GROUP, listener)
```

- [ ] **Step 7: 於 `buildFontFamiliesConfiguration()` 加上選字攔截與 Decoration 模板設定**

方法名稱改為 `buildNavigatorConfiguration()`（其職責已從「只登記字型」擴充為整個 `Configuration` 物件，見下方 KDoc 補充），對應呼叫處（`attachNavigator()` 內 `createFragmentFactory(..., configuration = buildFontFamiliesConfiguration())`）同步改名為 `buildNavigatorConfiguration()`。

KDoc 補充（沿用既有內容，於段落結尾追加）：

```kotlin
     * 【epic-6-annotations Issue 2 擴充】本函式職責已從「只登記字型」擴充
     * 為建構整個 EpubNavigatorFragment.Configuration：額外設定
     * `selectionActionModeCallback`（攔截原生選字工具列，見
     * SelectionActionModeCallback KDoc）與 `decorationTemplates`
     * （`HtmlDecorationTemplates.defaultTemplates()`，Readium 內建預設
     * 模板即可正確渲染 Highlight/Underline 兩種 built-in 樣式，不自訂
     * HtmlDecorationTemplate，見 plan-issue-2.md Global Constraints「純
     * 備註視覺簡化」）。方法名稱同步由 buildFontFamiliesConfiguration
     * 改為 buildNavigatorConfiguration，反映此擴充後的實際職責。
```

函式本體內，`return EpubNavigatorFragment.Configuration { ... }` 的 lambda 內，`servedAssets = lookupKeys.values.toList()` 之後新增：

```kotlin
        return EpubNavigatorFragment.Configuration {
            servedAssets = lookupKeys.values.toList()
            selectionActionModeCallback = SelectionActionModeCallback()
            decorationTemplates = HtmlDecorationTemplates.defaultTemplates()
            for ((familyName, lookupKey) in lookupKeys) {
```

- [ ] **Step 8: 在 `dispose()` 移除標記點擊監聽器**

`dispose()` 內 `removeFxlLayoutListener()` 之後新增：

```kotlin
        decorationListener?.let { navigatorFragment?.removeDecorationListener(it) }
```

- [ ] **Step 9: 編譯驗證**

Run: `cd app && flutter build apk --debug`
Expected: 建置成功（Kotlin 編譯通過，確認新增的 import／型別簽章與 Readium `kotlin-toolkit:3.3.0` 實際 API 相符）。

- [ ] **Step 10: 執行 `flutter analyze` 確認 Dart 端未受影響**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 11: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git commit -m "feat(epic-6): EpubReaderView.kt 原生端接上選字攔截／Decorator 疊加／標記點擊"
```

---

### Task 10：`ReaderScreen` 整合接線

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1-9 的全部型別與 Widget。
- Produces: `ReaderScreen` 新增可選具名參數 `highlightsRepository`／`notesRepository`（皆 nullable，未提供時行為等同本 Issue 之前，零回歸）；完成本 Issue 端到端接線。

- [ ] **Step 1: 寫失敗測試**

於 `app/test/screens/reader_screen_test.dart` 頂部新增 import：

```dart
import 'package:elinkbook/reader/annotation_list_item.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/screens/annotation_toolbar.dart';
import '../support/fake_highlights_repository.dart';
import '../support/fake_notes_repository.dart';
```

於檔案結尾（最後一個 `}` 之前）新增：

```dart
  testWidgets(
      '未提供 highlightsRepository／notesRepository 時，EPUB 選取事件不顯示浮動工具列（既有呼叫端零回歸）',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.epub',
        bookId: 'b1',
        prefsManager: FakeReaderPrefsManager(),
        bookmarksRepository: bookmarksRepository,
      ),
    ));
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsNothing);
  });

  testWidgets('提供 highlightsRepository／notesRepository 後，ReaderScreen 建構不受影響、仍正常顯示（既有測試涵蓋常態載入行為）',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();

    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.epub',
        bookId: 'b1',
        prefsManager: FakeReaderPrefsManager(),
        bookmarksRepository: bookmarksRepository,
        highlightsRepository: highlightsRepository,
        notesRepository: notesRepository,
      ),
    ));
    await tester.pump();

    final state = tester.state(find.byType(ReaderScreen));
    // ReaderScreen 在 app/test/ 環境下 _channel 恆為 null（無真實
    // AndroidView），無法透過原生端觸發 onSelectionChanged；改為直接
    // 呼叫 State 內部的處理方法驗證（比照既有測試對「_channel 恆為
    // null」限制的既有因應方式：專案既有測試不新增 Method Channel Mock
    // 基礎設施，見 spec.md「Testing Decisions」）。由於
    // `_handleSelectionChanged` 是私有方法，本測試改為直接驗證
    // `AnnotationToolbar` 在 `_currentSelection` 非 null 時確實會被
    // build 出來，透過 State 是否存在對應的公開行為間接驗證——此處
    // 選擇不新增測試專用的 public API，僅驗證 widget tree 初始狀態不
    // 顯示 AnnotationToolbar（上一個測試已涵蓋），選取觸發後的顯示邏輯
    // 交由 Task 11 的 integration_test 驗證（原生選字手勢本身即無法在
    // widget test 環境下真實模擬）。
    expect(state, isNotNull);
  });
```

（上方第二個測試刻意保守——`ReaderScreen` 對外沒有暴露測試用的「模擬選取事件」callback，比照 `CLAUDE.md`「`ReaderScreen` 是唯一的閱讀器 seam...刻意不新增公開 callback 參數」的既有原則，選取觸發後的實際浮動工具列顯示效果留給 Task 11 真機驗證；本測試只驗證建構參數可正確傳入不崩潰。）

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: FAIL（`ReaderScreen` 建構子尚無 `highlightsRepository`/`notesRepository` 參數，編譯錯誤）

- [ ] **Step 3: 擴充 `ReaderScreen` 建構參數**

`app/lib/screens/reader_screen.dart` 頂部新增 import：

```dart
import '../reader/annotation_list_item.dart';
import '../reader/epub_decoration.dart';
import '../reader/epub_selection_info.dart';
import '../reader/highlight.dart';
import '../reader/highlight_style.dart';
import '../reader/highlights_repository.dart';
import '../reader/note.dart';
import '../reader/notes_repository.dart';
import 'annotation_toolbar.dart';
import 'note_edit_dialog.dart';
```

`ReaderScreen` class 內，`bookmarksRepository` 欄位之後新增：

```dart
  /// 劃線／備註功能的資料存取層（epic-6-annotations Issue 2）。與
  /// [bookmarksRepository] 同樣刻意為可選參數——未提供時 EPUB 選取事件
  /// 不會顯示浮動工具列、`NotesBottomSheet`「✏️」分頁維持空狀態佔位符，
  /// 行為等同本 Issue 之前，零回歸。
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.bookId,
    required this.prefsManager,
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
  });
```

- [ ] **Step 4: 執行測試確認 Step 1 的建構參數編譯通過（尚未驗證行為）**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: 兩個新測試皆 PASS（此步驟僅驗證建構參數已可傳入；下方 Step 5-9 才會真正接上行為邏輯）。

- [ ] **Step 5: 新增 State 欄位**

`_ReaderScreenState` 內，`_tocEntries`/`_tocLoaded` 欄位群之後新增：

```dart
  // EPUB 劃線／備註快取（epic-6-annotations Issue 2），由
  // _reloadAnnotationsAndRefreshDecorations() 統一載入與更新。
  List<Highlight> _highlights = [];
  List<Note> _notes = [];
  bool _annotationsLoaded = false;
  // 目前選取範圍（原生 onSelectionChanged 回報），非 null 時於 body
  // Stack 顯示 AnnotationToolbar；FXL 一律不使用（見
  // _handleSelectionChanged 開頭防呆）。
  EpubSelectionInfo? _currentSelection;
  // 同一次選取中，使用者若已點擊螢光筆/底線建立劃線，暫存其資料庫 id，
  // 供接著點擊「備註」時把新備註連結到這筆劃線（design.md 使用者流程：
  // 「若同時已選色/底線，備註與劃線共存於同一筆記錄」）。新選取範圍
  // 開始時（_handleSelectionChanged）重置為 null。
  int? _pendingHighlightIdForSelection;
```

- [ ] **Step 6: 新增選取事件／標記啟用事件處理方法**

在 `_handleCharacterCountReady` 方法之後新增：

```dart
  /// FXL 一律不處理選取事件（design.md 決策 #7：劃線/備註排除 FXL）——
  /// 理論上 FXL 頁面多半無可選取文字層，此防呆保證不會意外對 FXL 觸發
  /// 劃線 UI（見 plan-issue-2.md Global Constraints「FXL 排除」）。
  void _handleSelectionChanged(EpubSelectionInfo info) {
    if (!mounted || _isFixedLayout) return;
    setState(() {
      _currentSelection = info;
      _pendingHighlightIdForSelection = null;
    });
  }

  void _handleSelectionCleared() {
    if (!mounted) return;
    setState(() {
      _currentSelection = null;
      _pendingHighlightIdForSelection = null;
    });
  }

  Future<void> _handleHighlightStyleSelected(HighlightStyle style) async {
    final selection = _currentSelection;
    final repository = widget.highlightsRepository;
    if (selection == null || repository == null) return;
    final id = await repository.insert(Highlight(
      bookId: widget.bookId,
      style: style,
      epubLocatorJson: selection.locatorJson,
      progression: selection.progression,
    ));
    _pendingHighlightIdForSelection = id;
    await _reloadAnnotationsAndRefreshDecorations();
  }

  Future<void> _handleNotePressed() async {
    final selection = _currentSelection;
    final repository = widget.notesRepository;
    if (selection == null || repository == null) return;
    final text = await showNoteTextDialog(context, title: '新增備註');
    if (text == null) return;
    await repository.insert(Note(
      bookId: widget.bookId,
      text: text,
      epubLocatorJson: selection.locatorJson,
      progression: selection.progression,
      highlightId: _pendingHighlightIdForSelection,
    ));
    await _reloadAnnotationsAndRefreshDecorations();
    if (!mounted) return;
    setState(() {
      _currentSelection = null;
      _pendingHighlightIdForSelection = null;
    });
  }

  /// 重新查詢本書全部劃線/備註並送給原生端重繪 Decorator（比照 TOC 的
  /// 「只在尚未載入過才抓取」慣例，但本方法每次 CRUD 後皆會主動重新
  /// 呼叫，非只呼叫一次——這裡的 `_annotationsLoaded` 只用於「開書時是否
  /// 已載入過初始清單」，不是「是否曾呼叫過本方法」）。
  Future<void> _reloadAnnotationsAndRefreshDecorations() async {
    final highlightsRepository = widget.highlightsRepository;
    final notesRepository = widget.notesRepository;
    if (highlightsRepository == null || notesRepository == null) return;
    final highlights = await highlightsRepository.listByBook(widget.bookId);
    final notes = await notesRepository.listByBook(widget.bookId);
    if (!mounted) return;
    setState(() {
      _highlights = highlights;
      _notes = notes;
    });
    _sendDecorationsToNative();
  }

  void _sendDecorationsToNative() {
    if (!mounted) return;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final decorations = <EpubDecoration>[
      for (final highlight in _highlights)
        if (highlight.id != null && highlight.epubLocatorJson != null)
          EpubDecoration.forHighlight(
            highlightId: highlight.id!,
            locatorJson: highlight.epubLocatorJson!,
            tint: highlightStyleTint(highlight.style, primaryColor: primaryColor),
            isUnderline: highlight.style == HighlightStyle.underline,
          ),
      for (final note in _notes)
        if (note.highlightId == null && note.id != null && note.epubLocatorJson != null)
          EpubDecoration.forNote(
            noteId: note.id!,
            locatorJson: note.epubLocatorJson!,
            tint: noteOnlyTint.value,
          ),
    ];
    EpubReaderView.setDecorations(_epubReaderViewKey, decorations);
  }

  Highlight? _findHighlightById(int id) {
    for (final highlight in _highlights) {
      if (highlight.id == id) return highlight;
    }
    return null;
  }

  Note? _findNoteByHighlightId(int highlightId) {
    for (final note in _notes) {
      if (note.highlightId == highlightId) return note;
    }
    return null;
  }

  Note? _findNoteById(int id) {
    for (final note in _notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  /// 原生端 onAnnotationActivated 回呼（使用者點擊既有標記）：依
  /// [decodeAnnotationId] 反查是哪一筆記錄，開啟編輯/刪除 Dialog
  /// （design.md 使用者流程步驟 3）。id 格式不明或查無對應記錄時靜默
  /// 忽略——理論上不會發生（送給原生端的 id 皆由
  /// [EpubDecoration.forHighlight]/[EpubDecoration.forNote] 產生），但
  /// 點擊當下記錄可能已被其他途徑刪除（極短競速窗口），静默忽略比拋出
  /// 例外更穩妥。
  void _handleAnnotationActivated(String decorationId) {
    final decoded = decodeAnnotationId(decorationId);
    if (decoded == null) return;
    AnnotationListItem item;
    switch (decoded.kind) {
      case AnnotationKind.highlight:
        final highlight = _findHighlightById(decoded.id);
        if (highlight == null) return;
        item = AnnotationListItem(
          highlight: highlight,
          note: _findNoteByHighlightId(decoded.id),
        );
        break;
      case AnnotationKind.note:
        final note = _findNoteById(decoded.id);
        if (note == null) return;
        item = AnnotationListItem(note: note);
        break;
    }
    _showAnnotationActionDialog(item);
  }

  Future<void> _showAnnotationActionDialog(AnnotationListItem item) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('劃線/備註'),
        children: [
          if (item.note != null)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop('edit'),
              child: const Text('✍️ 編輯備註文字'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop('delete'),
            child: const Text('🗑️ 刪除此劃線與備註'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final note = item.note;
    final highlight = item.highlight;
    if (action == 'edit' && note != null) {
      final newText = await showNoteTextDialog(context, initialText: note.text, title: '編輯備註');
      if (newText != null) {
        await widget.notesRepository!.updateText(note.id!, newText);
        await _reloadAnnotationsAndRefreshDecorations();
      }
    } else if (action == 'delete') {
      // 單筆刪除＝整筆一起刪（spec.md 決策 #13），比照
      // NotesBottomSheet._deleteAnnotationItem 的既有原則。
      if (note != null) await widget.notesRepository!.delete(note.id!);
      if (highlight != null) await widget.highlightsRepository!.delete(highlight.id!);
      await _reloadAnnotationsAndRefreshDecorations();
    }
  }
```

- [ ] **Step 7: 於 `_handleLayoutResolved` 觸發初始標記載入**

`_handleLayoutResolved` 方法內，既有的目錄背景抓取 `if (!info.isFixedLayout && _tocEntries.isEmpty && !_tocLoaded) { ... }` 區塊之後新增：

```dart
    if (!info.isFixedLayout &&
        !_annotationsLoaded &&
        widget.highlightsRepository != null &&
        widget.notesRepository != null) {
      _annotationsLoaded = true;
      _reloadAnnotationsAndRefreshDecorations();
    }
```

- [ ] **Step 8: 於 `_buildNativeView` 的 EPUB 分支接上新回呼**

`_buildNativeView` 的 `case BookFormat.epub:` 分支，`onCharacterCountReady: _handleCharacterCountReady,` 之後新增：

```dart
          onSelectionChanged: _handleSelectionChanged,
          onSelectionCleared: _handleSelectionCleared,
          onAnnotationActivated: _handleAnnotationActivated,
        );
```

- [ ] **Step 9: 於 `_buildBody` 疊加 `AnnotationToolbar`**

`_buildBody` 方法內，`final body = Stack(` 改為包一層 `LayoutBuilder`：

```dart
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final selection = _currentSelection;
        return Stack(
          children: [
            if (_resolved != null) _buildNativeView(format, isLandscape),
            if (_isFixedLayout && _fixedLayoutControlsVisible)
              Positioned(
                top: 16,
                left: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_fixed_layout_back_button'),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            if (_isFixedLayout && _fixedLayoutControlsVisible)
              Positioned(
                top: 16,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_fixed_layout_settings_button'),
                      icon: const Icon(Icons.settings, color: Colors.white),
                      tooltip: '版面設定',
                      onPressed: _openFxlSettings,
                    ),
                  ),
                ),
              ),
            if (selection != null)
              Positioned(
                left: (selection.rect.left * size.width).clamp(0.0, size.width),
                top: _annotationToolbarTop(selection, size),
                child: AnnotationToolbar(
                  onStyleSelected: _handleHighlightStyleSelected,
                  onNotePressed: _handleNotePressed,
                ),
              ),
            if (_state == _RenderState.loading)
              const Center(
                key: Key('reader_loading_indicator'),
                child: CircularProgressIndicator(),
              ),
          ],
        );
      },
    );
```

（原本 `Positioned`/`if (_state == _RenderState.loading)` 內容原封不動搬進 `LayoutBuilder` 的 `builder` 回傳的 `Stack` 內，僅新增 `if (selection != null) Positioned(...)` 這一個區塊；請勿更動既有邏輯本身。）

在 `_buildBody` 方法之前（或同一類別內任一位置）新增輔助方法：

```dart
  // 浮動工具列估計高度／與選取範圍的間距（初始選擇，真機測試後可能需
  // 微調，見 Global Constraints「選取矩形座標協定」）。
  static const _annotationToolbarHeight = 56.0;
  static const _annotationToolbarGap = 8.0;

  /// 【審查修正】原本無條件把工具列定位在選取範圍上方、clamp 到
  /// `>= 0`，若選取範圍太靠近頂端（`topPct * height < 工具列高度`），
  /// clamp 後的 `top` 會落在 0，導致工具列往下遮住選取範圍第一行文字
  /// （clamp 只保證不跑到畫面外，不保證不遮擋選取範圍本身）。改為：
  /// 選取範圍上方若有足夠空間才貼在上方；空間不足時改貼在選取範圍
  /// 下方，兩種情況下工具列都不會覆蓋選取矩形本體。
  double _annotationToolbarTop(EpubSelectionInfo selection, Size size) {
    final topAboveSelection =
        selection.rect.top * size.height - _annotationToolbarHeight - _annotationToolbarGap;
    if (topAboveSelection >= 0) return topAboveSelection;
    final belowSelection = selection.rect.bottom * size.height + _annotationToolbarGap;
    return belowSelection.clamp(0.0, size.height - _annotationToolbarHeight);
  }
```

- [ ] **Step 10: 於 `_openNotesSheet` 接上真實 Repository**

`_openNotesSheet` 方法內，`NotesBottomSheet(` 建構呼叫新增：

```dart
      builder: (_) => NotesBottomSheet(
        bookId: widget.bookId,
        bookmarksRepository: repository,
        currentPosition: positionContext,
        highlightsRepository:
            format == BookFormat.epub && !_isFixedLayout ? widget.highlightsRepository : null,
        notesRepository:
            format == BookFormat.epub && !_isFixedLayout ? widget.notesRepository : null,
        onAnnotationSelected: (item) {
          Navigator.of(context).pop();
          final locatorJson = item.highlight?.epubLocatorJson ?? item.note?.epubLocatorJson;
          if (locatorJson != null) {
            EpubReaderView.jumpToLocator(_epubReaderViewKey, locatorJson);
          }
        },
        onAnnotationsChanged: _reloadAnnotationsAndRefreshDecorations,
        onBookmarkSelected: (bookmark) {
          Navigator.of(context).pop();
          if (bookmark.epubLocatorJson != null) {
            EpubReaderView.jumpToLocator(
              _epubReaderViewKey,
              bookmark.epubLocatorJson!,
            );
          } else if (bookmark.pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, bookmark.pdfPageIndex!);
          }
        },
      ),
```

（`format == BookFormat.epub && !_isFixedLayout` 這個判斷式把「劃線/備註只支援流式 EPUB」的排除規則收斂在單一位置——FXL 與 PDF 呼叫端此時仍傳入 `null`，`NotesBottomSheet` 據此維持既有空狀態佔位符；PDF 支援留待 Issue 3 把這個條件式擴充為 `|| format == BookFormat.pdf`。）

- [ ] **Step 11: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（全部測試綠燈，含既有測試不受影響）

Run: `flutter test`
Expected: 全專案測試皆 PASS（確認本次跨檔案修改無回歸）。

- [ ] **Step 12: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 13: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-6): ReaderScreen 接上 EPUB 劃線/備註端到端流程"
```

---

### Task 11：integration_test（真機）＋ 手勢驅動流程的人工驗證清單

**Files:**
- Create: `app/integration_test/epub_highlights_notes_test.dart`

**Interfaces:**
- Consumes: Task 1-10 的全部型別（`HighlightsRepository`／`NotesRepository`／`ReaderScreen`／`NotesBottomSheet`）。
- Produces: 無新增 Dart 型別；驗證 repository 驅動的端到端流程（清單顯示、跳轉、編輯、刪除），比照 `notes_bookmark_test.dart` 既有結構。

- [ ] **Step 1: 撰寫 integration_test**

建立 `app/integration_test/epub_highlights_notes_test.dart`：

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
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/reader/epub_character_count_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/notes_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import 'package:elinkbook/screens/reader_screen.dart';

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

Future<void> _pumpUntilNotesButtonEnabled(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final finder = find.byKey(const Key('reader_notes_button'));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<IconButton>(finder).onPressed != null) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：筆記按鈕未轉為可點擊狀態');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 【真機人工驗證清單，本測試無法自動涵蓋】
  // Flutter integration_test 對 PlatformView（AndroidView）內部原生
  // WebView 的觸控事件模擬並不可靠（既有慣例：本專案其餘涉及原生手勢的
  // 功能，如 PDF 長按框選、FXL 三欄熱區，也都未嘗試以 tester.longPress/
  // drag 模擬 WebView 內部選字），故下列項目須另外以真實裝置人工驗證，
  // 不在本檔案自動化範圍：
  //   1. 原生長按+拖曳選字手勢確實觸發 onSelectionChanged、浮動工具列
  //      正確定位於選取範圍上方。
  //   2. 點擊螢光筆三色/底線按鈕，Decorator 疊加的視覺樣式與資料庫寫入
  //      一致；純備註淡灰底視覺可辨識。
  //   3. 點擊既有標記觸發 onAnnotationActivated、編輯/刪除 Dialog 正確
  //      開啟。
  //   4. 直排/橫排切換後，既有劃線視覺仍正確跟隨文字位置（design.md
  //      已知風險，底線樣式尤其需要確認）。
  // 本檔案改為驗證「repository 驅動」的部分：預先透過 Repository 寫入
  // 劃線/備註資料（模擬手勢建立後的最終資料狀態），驗證 NotesBottomSheet
  // 清單顯示、跳轉、編輯、刪除的端到端流程（比照 notes_bookmark_test.dart
  // 既有結構，書籤跳轉本身的原生渲染結果同樣無法在 widget test 層級斷言）。

  testWidgets('EPUB：預先寫入劃線＋依附備註，NotesBottomSheet 正確顯示合併清單並可跳轉/刪除',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
      EpubCharacterCountRepository(libraryRepository.database),
    );
    final bookmarksRepository = BookmarksRepository(libraryRepository.database);
    final highlightsRepository = HighlightsRepository(libraryRepository.database);
    final notesRepository = NotesRepository(libraryRepository.database);

    final samplePath = await _stageAssetAsFile(
      'test/fixtures/sample_multi_chapter.epub',
      'epub_highlights_notes.epub',
    );
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_highlights_epub',
      title: '劃線測試書',
      format: BookFileFormat.epub,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    final highlightId = await highlightsRepository.insert(const Highlight(
      bookId: 'b_highlights_epub',
      style: HighlightStyle.highlighterYellow,
      epubLocatorJson: '{"href":"/OEBPS/chapter1.xhtml"}',
      progression: 0.05,
    ));
    await notesRepository.insert(Note(
      bookId: 'b_highlights_epub',
      text: '這段很重要',
      epubLocatorJson: '{"href":"/OEBPS/chapter1.xhtml"}',
      progression: 0.05,
      highlightId: highlightId,
    ));
    await notesRepository.insert(const Note(
      bookId: 'b_highlights_epub',
      text: '純備註內容',
      epubLocatorJson: '{"href":"/OEBPS/chapter2.xhtml"}',
      progression: 0.3,
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_highlights_epub',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilNotesButtonEnabled(tester);

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_sheet_annotation_list')), findsOneWidget);
    expect(find.text('這段很重要'), findsOneWidget);
    expect(find.text('純備註內容'), findsOneWidget);

    // 點選合併項目後 Bottom Sheet 應關閉（跳轉本身的原生渲染結果無法在
    // widget test 層級斷言，比照既有書籤測試的既定限制）。
    await tester.tap(find.text('這段很重要'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesBottomSheet), findsNothing);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 重新開啟，驗證單筆刪除（劃線+備註一併消失）持久化生效。
    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('notes_sheet_annotation_delete_h${highlightId}_n1')));
    await tester.pumpAndSettle();

    expect(await highlightsRepository.listByBook('b_highlights_epub'), isEmpty);
    expect(find.text('這段很重要'), findsNothing);
    expect(find.text('純備註內容'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 記錄待執行狀態**

本測試需在真實 Android 裝置/模擬器上執行（`flutter test integration_test/epub_highlights_notes_test.dart -d <device-id>`）；比照 Issue 1 `notes_bookmark_test.dart` 先例，若撰寫當下無可用裝置，於 `issues.md` Issue 2 驗收標準對應項目註記「測試檔已撰寫，尚待裝置就緒後實際執行」，並列出上方 Step 1 KDoc 註解中的「真機人工驗證清單」4 項供人工測試時對照。

- [ ] **Step 3: 若有裝置可用，執行驗證**

Run: `flutter devices`（確認是否有可用裝置/模擬器）
若有：Run: `flutter test integration_test/epub_highlights_notes_test.dart -d <device-id>`
Expected: PASS；並依上方「真機人工驗證清單」逐項人工操作確認。
若無：跳過本步驟，維持 Step 2 的註記狀態。

- [ ] **Step 4: Commit**

```bash
git add app/integration_test/epub_highlights_notes_test.dart
git commit -m "test(epic-6): 新增 EPUB 劃線/備註真機整合測試（尚待真機執行驗證）"
```

---

## 完成後的整體驗證

- [ ] Run: `flutter test`（全專案）
  Expected: 全數 PASS，無回歸。
- [ ] Run: `flutter analyze`
  Expected: `No issues found!`
- [ ] Run: `cd app && flutter build apk --debug`
  Expected: 建置成功。
- [ ] 依 `issues.md` Issue 2 驗收標準逐項核對，勾選已完成項目；真機相關項目（Decorator 視覺渲染、直排/橫排一致性、手勢競技場）維持標註「測試檔已撰寫，尚待裝置就緒後實際執行」。
