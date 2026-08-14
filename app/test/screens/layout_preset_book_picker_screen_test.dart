import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/layout_preset_book_picker_screen.dart';

void main() {
  testWidgets('單選模式：點擊項目立即回傳該書 id 的單一清單', (tester) async {
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
    await tester.pumpAndSettle();

    expect(result, ['b2']);
  });

  testWidgets('複選模式：勾選兩本書後點擊確定，回傳兩個 id 的清單', (tester) async {
    List<String>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<List<String>?>(
              MaterialPageRoute(
                builder: (_) => LayoutPresetBookPickerScreen(
                  books: [_book('b1', '書一'), _book('b2', '書二'), _book('b3', '書三')],
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
    await tester
        .tap(find.byKey(const Key('layout_preset_book_picker_item_b3')));
    await tester.pumpAndSettle();
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

  testWidgets('書籍清單為空時顯示提示文字', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LayoutPresetBookPickerScreen(books: [], multiSelect: false),
    ));

    expect(find.text('沒有可選擇的流式 EPUB 書籍'), findsOneWidget);
  });
}

Book _book(String id, String title) => Book(
      id: id,
      title: title,
      format: BookFileFormat.epub,
      filePath: 'content://example/$id.epub',
      source: BookSource.local,
      createTime: DateTime.fromMillisecondsSinceEpoch(1000),
      lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
    );
