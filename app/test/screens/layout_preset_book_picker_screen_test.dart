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
