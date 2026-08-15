# Epic 28 Issue 6 — 「選擇書籍」畫面優化（格線化＋統一確認機制＋搜尋） 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `LayoutPresetBookPickerScreen`（版面設定預設集／書籍設定複製共用的選書畫面）從純文字 `ListView` 改為封面格線，單選模式改為「選取＋確定按鈕」（取消目前點擊即觸發、無確認機制的真實誤觸風險），多選模式改為同一套視覺語言呈現，並新增書名/作者即時搜尋。

**Architecture:** 純 UI 層重構，`LayoutPresetBookPickerScreen` 對外建構參數（`books`／`multiSelect`）與回傳值語意（單選/多選皆回傳 `List<String>`，取消回傳 `null`）完全不變，呼叫端（`reader_screen.dart` 的 `_handleRequestBookPicker`）不需要任何修改。畫面內部改用 `GridView.builder` + `SliverGridDelegateWithFixedCrossAxisCount`（直向 3 欄／橫向 4 欄，比照 `LibraryScreen` 既有慣例，`app/lib/screens/library_screen.dart:833-848`），每格是一個新的私有 `_BookGridItem`，視覺上比照 `LibraryScreen._BookGridTile` 既有的「封面＋右上角半透明黑底選取指示圖示（`check_circle`／`radio_button_unchecked`）」語言（`library_screen.dart:1076-1148`）——單選/多選共用同一套圖示，差別只在 `_selected` 集合的成員數上限由呼叫端邏輯控制（單選時每次選取都先清空集合再加入）。**設計決策**：`LibraryScreen._BookCover`／`_BookGridTile` 皆是該檔案的私有 class，Dart 無法跨檔案 import 私有型別，若要真正共用需先把它們改為 public 並抽到新檔案（`issues.md` Solution 第 1 點列為「建議、非強制」）；本計畫選擇**不抽出**，改為在 `layout_preset_book_picker_screen.dart` 內就地實作一份精簡版（只保留封面容錯＋選取圖示，省略 `LibraryScreen` 特有的長按批次選取／進度百分比等本畫面用不到的邏輯），理由：(1) 抽出會連帶碰觸 `library_screen.dart` 與其龐大既有測試檔，超出本 Issue 範圍；(2) 精簡版程式碼量小（約 40 行），複製成本遠低於抽出＋跨檔案接線＋驗證兩處呼叫端零回歸的成本；(3) 本畫面書籍恆為流式 EPUB（呼叫端已用 `LibraryRepository.listReflowableEpubBooks()` 過濾），封面容錯不需要 `LibraryScreen._BookCover` 依 `book.format` 選圖示的完整邏輯，簡化為固定的 `Icons.menu_book` 佔位圖示即可，兩者需求本就不完全相同，共用反而要多繞一層參數化。

**Tech Stack:** Flutter/Dart（`GridView`／`SliverGridDelegateWithFixedCrossAxisCount`／`TextField`，皆為 Flutter SDK 內建，無新增依賴）。

**Spec:** `docs/epics/epic-28-reader-settings-enhancements/issues.md`「Issue 6」、`design.md`「2026-08-15 追加」（決策紀錄）。

## Global Constraints

- 只修改 `app/lib/screens/layout_preset_book_picker_screen.dart` 與 `app/test/screens/layout_preset_book_picker_screen_test.dart`；不修改 `app/lib/screens/library_screen.dart`（見上方 Architecture「設計決策」）、`app/lib/screens/reader_screen.dart`（呼叫端不需要變動）。
- 既有測試 `Key`（`layout_preset_book_picker_item_<id>`／`layout_preset_book_picker_confirm`）逐位元組保留；`layout_preset_book_picker_item_<id>` 現在掛在整個格子的 `InkWell` 上（取代原本的 `ListTile`/`CheckboxListTile`），語意不變（點擊該 Key 觸發選取/取消選取）。
- 新增 `Key`：`layout_preset_book_picker_item_<id>_selected`（選取指示圖示，供測試判斷選取狀態）、`layout_preset_book_picker_search_field`（搜尋框）、`layout_preset_book_picker_grid`（`GridView` 本體）。
- 既有空清單提示文字「沒有可選擇的流式 EPUB 書籍」逐字不變；新增查無搜尋結果提示文字「找不到符合的書籍」，兩者須可區分（不可共用同一段文字）。
- Grid 欄數：直向 3 欄／橫向 4 欄（`MediaQuery.orientationOf(context)` 判斷），`childAspectRatio: 0.62`，逐值比照 `library_screen.dart:835-843`。
- 封面圖無 `coverPath` 或檔案不存在時，一律以 `Icons.menu_book` 圖示佔位（不比照 `LibraryScreen._BookCover` 依 `book.format` 選圖示，見上方 Architecture 決策理由）。
- 「確定」按鈕（`layout_preset_book_picker_confirm`）改為單選/多選模式皆顯示（原本只有多選模式顯示），未選取任何項目時停用，邏輯與既有多選模式完全一致，不需要依 `multiSelect` 分支。
- 單選模式下每次點擊項目一律清空既有選取、只保留剛點擊的這一格（Radio 語意，不是「再點一次可取消選取」）。
- 使用者未點擊「確定」、直接以返回鍵/系統手勢離開畫面時，一律回傳 `null`——這是既有、必須維持的既有契約（`reader_settings_sheet.dart:898/904/910/912` 的 4 個呼叫端皆已有 `if (targets == null || targets.isEmpty) return;` 既有防呆，不可被破壞）。
- 每完成一個 Task 就跑一次 `flutter analyze`，維持乾淨。

---

### Task 1：格線化＋單選/多選統一為「選取＋確定按鈕」

**Files:**
- Modify: `app/lib/screens/layout_preset_book_picker_screen.dart`（全檔重寫）
- Test: `app/test/screens/layout_preset_book_picker_screen_test.dart`（全檔重寫）

**Interfaces:**
- Consumes: 既有 `Book`（`app/lib/library/models/book.dart`，`id`／`title`／`author`／`coverPath` 欄位）。
- Produces: `LayoutPresetBookPickerScreen` 對外建構參數（`books`／`multiSelect`）與回傳值語意不變；新增私有 `_BookGridItem`（`book`／`selected`／`onTap` 3 個參數）與 `_BookCover`（`book` 參數）兩個 `StatelessWidget`，僅供本檔案內部使用，Task 2 會沿用 `_BookGridItem`／`_BookCover` 不需修改。

- [x] **Step 1：寫失敗測試——完整重寫測試檔**

編輯 `app/test/screens/layout_preset_book_picker_screen_test.dart`，整份檔案改為：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/layout_preset_book_picker_screen.dart';

void main() {
  testWidgets('單選模式：點擊項目後選取但不立即關閉，點擊「確定」才回傳該書 id',
      (tester) async {
    List<String>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<List<String>?>(
              MaterialPageRoute(
                builder: (_) => LayoutPresetBookPickerScreen(
                  books: [_book('b1', '書一'), _book('b2', '書二')],
                  multiSelect: false,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_item_b2')));
    await tester.pump();

    expect(result, isNull, reason: '點擊項目只應選取，不應立即關閉畫面');
    expect(find.byType(LayoutPresetBookPickerScreen), findsOneWidget);

    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_confirm')));
    await tester.pumpAndSettle();

    expect(result, ['b2']);
  });

  testWidgets('單選模式（Radio 語意）：選取書一後再選取書二，最終只有書二保持選取狀態',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LayoutPresetBookPickerScreen(
        books: [_book('b1', '書一'), _book('b2', '書二')],
        multiSelect: false,
      ),
    ));

    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_item_b1')));
    await tester.pump();
    expect(
      tester
          .widget<Icon>(find.byKey(
              const Key('layout_preset_book_picker_item_b1_selected')))
          .icon,
      Icons.check_circle,
    );

    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_item_b2')));
    await tester.pump();

    expect(
      tester
          .widget<Icon>(find.byKey(
              const Key('layout_preset_book_picker_item_b1_selected')))
          .icon,
      Icons.radio_button_unchecked,
      reason: '單選模式下選取新項目應取消先前的選取',
    );
    expect(
      tester
          .widget<Icon>(find.byKey(
              const Key('layout_preset_book_picker_item_b2_selected')))
          .icon,
      Icons.check_circle,
    );
  });

  testWidgets('單選模式：未點擊「確定」、直接返回時，回傳 null', (tester) async {
    List<String>? result = const ['sentinel'];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<List<String>?>(
              MaterialPageRoute(
                builder: (_) => LayoutPresetBookPickerScreen(
                  books: [_book('b1', '書一')],
                  multiSelect: false,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('複選模式：點擊兩本書的格子後點擊確定，回傳兩個 id 的清單', (tester) async {
    List<String>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<List<String>?>(
              MaterialPageRoute(
                builder: (_) => LayoutPresetBookPickerScreen(
                  books: [
                    _book('b1', '書一'),
                    _book('b2', '書二'),
                    _book('b3', '書三'),
                  ],
                  multiSelect: true,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_item_b1')));
    await tester.pump();
    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_item_b3')));
    await tester.pump();
    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_confirm')));
    await tester.pumpAndSettle();

    expect(result, unorderedEquals(['b1', 'b3']));
  });

  testWidgets('複選模式：未勾選任何項目時，確定按鈕停用', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LayoutPresetBookPickerScreen(
        books: [_book('b1', '書一')],
        multiSelect: true,
      ),
    ));

    final button = tester.widget<TextButton>(
        find.byKey(const Key('layout_preset_book_picker_confirm')));
    expect(button.onPressed, isNull);
  });

  testWidgets('複選模式：未點擊「確定」、直接返回時，回傳 null（即使已選取項目）',
      (tester) async {
    List<String>? result = const ['sentinel'];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<List<String>?>(
              MaterialPageRoute(
                builder: (_) => LayoutPresetBookPickerScreen(
                  books: [_book('b1', '書一')],
                  multiSelect: true,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_item_b1')));
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('書籍清單為空時顯示提示文字', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LayoutPresetBookPickerScreen(books: [], multiSelect: false),
    ));

    expect(find.text('沒有可選擇的流式 EPUB 書籍'), findsOneWidget);
  });

  testWidgets('格線正確顯示有 coverPath 且檔案存在的書籍封面圖片', (tester) async {
    final tempDir = (await tester.runAsync(() =>
        Directory.systemTemp.createTemp('layout_preset_book_picker_cover_test')))!;
    addTearDown(() => tester.runAsync(() => tempDir.delete(recursive: true)));

    final coverFile = File('${tempDir.path}/cover.png');
    // 最小合法 1x1 PNG（可被 Image.file 成功解碼），比照
    // library_screen_test.dart 既有先例。
    await tester.runAsync(() => coverFile.writeAsBytes(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
          '42YAAAAASUVORK5CYII=',
        )));

    await tester.pumpWidget(MaterialApp(
      home: LayoutPresetBookPickerScreen(
        books: [_book('b1', '有封面的書', coverPath: coverFile.path)],
        multiSelect: false,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.menu_book), findsNothing);
  });

  testWidgets('格線對無 coverPath 的書籍以通用書本圖示佔位', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LayoutPresetBookPickerScreen(
        books: [_book('b1', '無封面的書')],
        multiSelect: false,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.menu_book), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}

Book _book(String id, String title, {String? author, String? coverPath}) =>
    Book(
      id: id,
      title: title,
      author: author,
      format: BookFileFormat.epub,
      filePath: 'content://example/$id.epub',
      source: BookSource.local,
      coverPath: coverPath,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
```

- [x] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/screens/layout_preset_book_picker_screen_test.dart`

預期：多數測試 FAIL——目前程式碼仍是 `ListView`/`ListTile`/`CheckboxListTile`，找不到 `layout_preset_book_picker_item_b1_selected` 等新 Key，單選模式點擊項目仍會立即 `pop`（與「點擊項目後選取但不立即關閉」矛盾）。

- [x] **Step 3：重寫 `layout_preset_book_picker_screen.dart`**

整份檔案改為：

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../library/models/book.dart';

/// 版面設定預設集／書籍設定複製的書籍選擇器（epic-28-reader-settings-
/// enhancements Issue 3「UI 元件責任劃分」`onRequestBookPicker`；格線化＋
/// 統一確認機制見 Issue 6），純展示 widget，不做任何 Repository I/O——
/// [books] 由呼叫端（`ReaderScreen`，已透過
/// `LibraryRepository.listReflowableEpubBooks()` 過濾為僅流式 EPUB）傳入。
/// [multiSelect] 為 `false` 時單選（Radio 語意，同時最多選 1 格）、`true`
/// 時可複選（Checkbox 語意）；兩者皆須點擊 AppBar「確定」按鈕（未選取任何
/// 項目時停用）才會關閉畫面並回傳已選取 id 清單。使用者未點擊「確定」、
/// 直接以返回鍵/系統手勢離開畫面時，一律回傳 `null`——這是既有呼叫端
/// （`reader_settings_sheet.dart` 的 4 處 `onRequestBookPicker` 呼叫）依賴
/// 的既有契約，不可破壞。
class LayoutPresetBookPickerScreen extends StatefulWidget {
  final List<Book> books;
  final bool multiSelect;

  const LayoutPresetBookPickerScreen({
    super.key,
    required this.books,
    required this.multiSelect,
  });

  @override
  State<LayoutPresetBookPickerScreen> createState() =>
      _LayoutPresetBookPickerScreenState();
}

class _LayoutPresetBookPickerScreenState
    extends State<LayoutPresetBookPickerScreen> {
  final Set<String> _selected = {};

  void _handleItemTap(Book book) {
    setState(() {
      if (widget.multiSelect) {
        if (_selected.contains(book.id)) {
          _selected.remove(book.id);
        } else {
          _selected.add(book.id);
        }
      } else {
        // Radio 語意：單選模式下每次點擊一律清空既有選取，只保留剛點擊的
        // 這一格，不支援「再點一次取消選取」。
        _selected
          ..clear()
          ..add(book.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.multiSelect ? '選擇書籍（可複選）' : '選擇書籍'),
        actions: [
          TextButton(
            key: const Key('layout_preset_book_picker_confirm'),
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.toList()),
            child: const Text('確定'),
          ),
        ],
      ),
      body: widget.books.isEmpty
          ? const Center(child: Text('沒有可選擇的流式 EPUB 書籍'))
          : _buildGrid(widget.books),
    );
  }

  Widget _buildGrid(List<Book> books) {
    final orientation = MediaQuery.orientationOf(context);
    final crossAxisCount = orientation == Orientation.landscape ? 4 : 3;
    return GridView.builder(
      key: const Key('layout_preset_book_picker_grid'),
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.62,
        crossAxisSpacing: 8,
        mainAxisSpacing: 12,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return _BookGridItem(
          book: book,
          selected: _selected.contains(book.id),
          onTap: () => _handleItemTap(book),
        );
      },
    );
  }
}

/// 書籍格：封面圖＋書名＋右上角選取指示圖示。單選/複選共用同一套視覺
/// （`check_circle`／`radio_button_unchecked`＋半透明黑底圓圈確保任何封面
/// 底色下都有足夠對比度），比照 `LibraryScreen._BookGridTile` 既有的選取
/// 指示視覺語言（`app/lib/screens/library_screen.dart`）——因跨檔案無法
/// import 私有 class，本畫面就地實作一份精簡版，只保留封面容錯＋選取圖示，
/// 省略 `LibraryScreen` 特有的進度百分比／長按批次選取等本畫面用不到的
/// 邏輯（見 `plan-issue-6.md` Architecture「設計決策」）。
class _BookGridItem extends StatelessWidget {
  final Book book;
  final bool selected;
  final VoidCallback onTap;

  const _BookGridItem({
    required this.book,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('layout_preset_book_picker_item_${book.id}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _BookCover(book: book),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        key: Key(
                            'layout_preset_book_picker_item_${book.id}_selected'),
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 書籍封面：有 `coverPath` 且檔案存在時顯示圖片，否則以通用書本圖示佔位。
/// 本畫面書籍恆為流式 EPUB（呼叫端已用
/// `LibraryRepository.listReflowableEpubBooks()` 過濾），不需要
/// `LibraryScreen._BookCover` 依 `book.format` 選格式專屬圖示的完整邏輯。
class _BookCover extends StatelessWidget {
  final Book book;
  const _BookCover({required this.book});

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    if (coverPath != null && File(coverPath).existsSync()) {
      return Image.file(File(coverPath), fit: BoxFit.cover);
    }
    return const ColoredBox(
      color: Color(0xFFE0E0E0),
      child: Center(child: Icon(Icons.menu_book, size: 32)),
    );
  }
}
```

- [x] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/screens/layout_preset_book_picker_screen_test.dart`

預期：全數 PASS。

- [x] **Step 5：執行完整分析，確認乾淨**

執行：`cd app && flutter analyze`

預期：`"No issues found!"`。

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/layout_preset_book_picker_screen.dart app/test/screens/layout_preset_book_picker_screen_test.dart
git commit -m "feat(epic-28): Issue 6——選擇書籍畫面改為格線＋統一單選/多選為選取＋確定按鈕"
```

---

### Task 2：新增書名/作者即時搜尋＋軟體鍵盤版面適配

**Files:**
- Modify: `app/lib/screens/layout_preset_book_picker_screen.dart`
- Test: `app/test/screens/layout_preset_book_picker_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `_BookGridItem`／`_BookCover`（不修改）、`_buildGrid()`（改為接受篩選後的清單，簽章不變仍是 `Widget _buildGrid(List<Book> books)`）。
- Produces: 新增私有 getter `List<Book> get _filteredBooks`，供 `build()` 使用；不新增對外介面。

- [x] **Step 1：寫失敗測試——新增 6 則測試**

編輯 `app/test/screens/layout_preset_book_picker_screen_test.dart`，在既有最後一則測試「格線對無 coverPath 的書籍以通用書本圖示佔位」之後、`}`（`main()` 收尾）之前，新增：

```dart

  testWidgets('輸入書名子字串，格線即時篩選為符合的書籍', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LayoutPresetBookPickerScreen(
        books: [_book('b1', '射鵰英雄傳'), _book('b2', '神鵰俠侶')],
        multiSelect: false,
      ),
    ));

    await tester.enterText(
        find.byKey(const Key('layout_preset_book_picker_search_field')),
        '射鵰');
    await tester.pump();

    expect(find.byKey(const Key('layout_preset_book_picker_item_b1')),
        findsOneWidget);
    expect(find.byKey(const Key('layout_preset_book_picker_item_b2')),
        findsNothing);
  });

  testWidgets('輸入作者子字串，格線即時篩選為符合的書籍', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LayoutPresetBookPickerScreen(
        books: [
          _book('b1', '書一', author: '金庸'),
          _book('b2', '書二', author: '古龍'),
        ],
        multiSelect: false,
      ),
    ));

    await tester.enterText(
        find.byKey(const Key('layout_preset_book_picker_search_field')),
        '古龍');
    await tester.pump();

    expect(find.byKey(const Key('layout_preset_book_picker_item_b1')),
        findsNothing);
    expect(find.byKey(const Key('layout_preset_book_picker_item_b2')),
        findsOneWidget);
  });

  testWidgets('搜尋查無符合結果時顯示提示文字，與「無可選書籍」提示不同', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LayoutPresetBookPickerScreen(
        books: [_book('b1', '書一')],
        multiSelect: false,
      ),
    ));

    await tester.enterText(
        find.byKey(const Key('layout_preset_book_picker_search_field')),
        '不存在的書名');
    await tester.pump();

    expect(find.text('找不到符合的書籍'), findsOneWidget);
    expect(find.text('沒有可選擇的流式 EPUB 書籍'), findsNothing);
  });

  testWidgets('清空搜尋詞後，格線恢復顯示完整清單', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LayoutPresetBookPickerScreen(
        books: [_book('b1', '書一'), _book('b2', '書二')],
        multiSelect: false,
      ),
    ));

    final searchField =
        find.byKey(const Key('layout_preset_book_picker_search_field'));
    await tester.enterText(searchField, '書一');
    await tester.pump();
    expect(find.byKey(const Key('layout_preset_book_picker_item_b2')),
        findsNothing);

    await tester.enterText(searchField, '');
    await tester.pump();
    expect(find.byKey(const Key('layout_preset_book_picker_item_b1')),
        findsOneWidget);
    expect(find.byKey(const Key('layout_preset_book_picker_item_b2')),
        findsOneWidget);
  });

  testWidgets('多選模式下，篩選隱藏已選取項目後清空搜尋詞，該項目選取狀態仍保留',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LayoutPresetBookPickerScreen(
        books: [_book('b1', '射鵰英雄傳'), _book('b2', '神鵰俠侶')],
        multiSelect: true,
      ),
    ));

    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_item_b1')));
    await tester.pump();
    expect(
      tester
          .widget<Icon>(find.byKey(
              const Key('layout_preset_book_picker_item_b1_selected')))
          .icon,
      Icons.check_circle,
    );

    final searchField =
        find.byKey(const Key('layout_preset_book_picker_search_field'));
    await tester.enterText(searchField, '神鵰');
    await tester.pump();
    expect(find.byKey(const Key('layout_preset_book_picker_item_b1')),
        findsNothing,
        reason: 'b1 被篩選隱藏，暫時不在畫面上');

    await tester.enterText(searchField, '');
    await tester.pump();

    expect(
      tester
          .widget<Icon>(find.byKey(
              const Key('layout_preset_book_picker_item_b1_selected')))
          .icon,
      Icons.check_circle,
      reason: '清空搜尋詞後 b1 重新出現，選取狀態應仍保留',
    );
  });

  testWidgets('GridView 由 Expanded 包裹（避免軟體鍵盤彈出時版面溢位）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LayoutPresetBookPickerScreen(
        books: [_book('b1', '書一')],
        multiSelect: false,
      ),
    ));

    final gridFinder =
        find.byKey(const Key('layout_preset_book_picker_grid'));
    expect(gridFinder, findsOneWidget);
    expect(
      find.ancestor(of: gridFinder, matching: find.byType(Expanded)),
      findsOneWidget,
      reason: 'GridView 需被 Expanded 包裹，Column 內與常駐搜尋欄位共存時才能'
          '正確取得剩餘可用高度，避免軟體鍵盤彈出時 RenderFlex overflowed',
    );
  });
```

- [x] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/screens/layout_preset_book_picker_screen_test.dart --plain-name "搜尋|Expanded"`

預期：6 則新測試皆 FAIL——目前沒有 `layout_preset_book_picker_search_field`，`body:` 直接是 `_buildGrid(widget.books)`，不在 `Expanded` 內。

- [x] **Step 3：新增搜尋欄位與篩選邏輯**

編輯 `app/lib/screens/layout_preset_book_picker_screen.dart`，`_LayoutPresetBookPickerScreenState` 內找到：

```dart
class _LayoutPresetBookPickerScreenState
    extends State<LayoutPresetBookPickerScreen> {
  final Set<String> _selected = {};

  void _handleItemTap(Book book) {
```

改為：

```dart
class _LayoutPresetBookPickerScreenState
    extends State<LayoutPresetBookPickerScreen> {
  final Set<String> _selected = {};
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Book> get _filteredBooks {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.books;
    return widget.books.where((book) {
      if (book.title.toLowerCase().contains(query)) return true;
      final author = book.author;
      return author != null && author.toLowerCase().contains(query);
    }).toList();
  }

  void _handleItemTap(Book book) {
```

找到 `build()` 方法：

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.multiSelect ? '選擇書籍（可複選）' : '選擇書籍'),
        actions: [
          TextButton(
            key: const Key('layout_preset_book_picker_confirm'),
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.toList()),
            child: const Text('確定'),
          ),
        ],
      ),
      body: widget.books.isEmpty
          ? const Center(child: Text('沒有可選擇的流式 EPUB 書籍'))
          : _buildGrid(widget.books),
    );
  }
```

改為：

```dart
  @override
  Widget build(BuildContext context) {
    final filteredBooks = _filteredBooks;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.multiSelect ? '選擇書籍（可複選）' : '選擇書籍'),
        actions: [
          TextButton(
            key: const Key('layout_preset_book_picker_confirm'),
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.toList()),
            child: const Text('確定'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              key: const Key('layout_preset_book_picker_search_field'),
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜尋書名或作者',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: widget.books.isEmpty
                ? const Center(child: Text('沒有可選擇的流式 EPUB 書籍'))
                : filteredBooks.isEmpty
                    ? const Center(child: Text('找不到符合的書籍'))
                    : _buildGrid(filteredBooks),
          ),
        ],
      ),
    );
  }
```

`_buildGrid()`／`_BookGridItem`／`_BookCover` 維持不動——`Scaffold.resizeToAvoidBottomInset` 未被覆寫，維持 Flutter 預設值 `true`，不需要額外程式碼。

- [x] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/screens/layout_preset_book_picker_screen_test.dart`

預期：全數 PASS（Task 1 的既有測試 + Task 2 新增的 6 則）。

- [x] **Step 5：執行完整分析，確認乾淨**

執行：`cd app && flutter analyze`

預期：`"No issues found!"`。

- [x] **Step 6：Commit**

```bash
git add app/lib/screens/layout_preset_book_picker_screen.dart app/test/screens/layout_preset_book_picker_screen_test.dart
git commit -m "feat(epic-28): Issue 6——選擇書籍畫面新增書名/作者即時搜尋"
```

---

### Task 3：修正 `reader_screen_test.dart` 內真正渲染本畫面的既有測試＋全專案回歸

**Files:**
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: 無新增。

已用 `Grep` 核對 `reader_screen_test.dart` 全文對 `layout_preset_book_picker_*` 這幾個 Key 的引用，確認只有 2 處**真正**透過 `Navigator.push` 渲染 `LayoutPresetBookPickerScreen`（其餘測試皆是直接對 `onRequestBookPicker` 傳入 fake 閉包，不經過本畫面，不受影響）：

1. `套用預設集到其他書籍（多本）：跳出「即將覆蓋 N 本書」確認對話框，確認後批次寫入`（約第 6731-6772 行）——多選模式，既有寫法已經是「點擊項目 → 點擊 `layout_preset_book_picker_confirm`」，與 Task 1 的多選模式行為完全一致，**不需要修改**。
2. `複製其他書籍設定到本書：正確以 reflowableEpubFields() 過濾後寫入並即時反映`（約第 6836-6868 行）——單選模式（`_handleCopyFromBookToCurrent`），既有寫法只點擊 `layout_preset_book_picker_item_b_other` 一次就預期畫面關閉並套用，依賴的正是 Task 1 要移除的「單選模式點擊即觸發」行為，**需要修改**。

- [x] **Step 1：修正「複製其他書籍設定到本書」測試，補上點擊確定按鈕**

編輯 `app/test/screens/reader_screen_test.dart`，找到（約第 6859-6863 行）：

```dart
      await tester
          .tap(find.byKey(const Key('layout_preset_book_picker_item_b_other')));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
```

改為：

```dart
      await tester
          .tap(find.byKey(const Key('layout_preset_book_picker_item_b_other')));
      await tester.pump();
      await tester
          .tap(find.byKey(const Key('layout_preset_book_picker_confirm')));
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
```

- [x] **Step 2：執行測試確認通過**

執行：`cd app && flutter test test/screens/reader_screen_test.dart --plain-name "複製其他書籍設定到本書"`

預期：PASS。

- [x] **Step 3：執行全專案測試與分析**

執行：`cd app && flutter analyze && flutter test`

預期：`flutter analyze` "No issues found!"；全專案 `flutter test` 全數 PASS，零回歸。

- [x] **Step 4：Commit**

```bash
git add app/test/screens/reader_screen_test.dart
git commit -m "test(epic-28): Issue 6——reader_screen_test.dart 補上單選模式的確定按鈕點擊"
```

---

## 完成後的驗證（對照 `issues.md` Issue 6 驗收標準）

- [x] 選擇書籍畫面以格線＋封面圖呈現
- [x] 單選與多選皆需經由 Radio/Checkbox 選取＋右上角「確定」按鈕才會關閉畫面，不再有「點擊即觸發」的零確認行為
- [x] 未確認即返回時不觸發任何複製/覆寫（Task 1 測試已涵蓋，含多選模式下已選取項目仍正確回傳 `null`）
- [x] 可透過搜尋列即時依書名/作者篩選書籍，軟體鍵盤彈出時版面不溢位（Task 2 測試已涵蓋）
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸
