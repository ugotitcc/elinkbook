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
