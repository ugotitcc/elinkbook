import 'dart:async';

import 'package:elinkbook/dictionary/dictionary_manager.dart';
import 'package:elinkbook/dictionary/mdx_companion_files.dart';
import 'package:elinkbook/dictionary/models/dictionary_source.dart';
import 'package:elinkbook/screens/dictionary_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_dictionary_manager.dart';
import '../support/pump_localized_widget.dart';

DictionaryListItem _item(
  String id, {
  int priority = 0,
  String sourceLang = 'en',
  String targetLang = 'zh-Hant',
  DictionaryFormat format = DictionaryFormat.jsonCsv,
  int entryCount = 3,
  bool enabled = true,
  String licenseNote = '',
  List<String> missingCss = const [],
}) => DictionaryListItem(
  source: DictionarySource(
    id: id,
    name: '字典$id',
    format: format,
    sourceLang: sourceLang,
    targetLang: targetLang,
    priority: priority,
    enabled: enabled,
    storagePath: '',
    entryCount: entryCount,
    licenseNote: licenseNote,
    importedAt: DateTime.utc(2026, 10, 19),
  ),
  missingCss: missingCss,
);

Future<void> _pump(
  WidgetTester tester,
  FakeDictionaryManager manager, {
  bool isEinkMode = false,
  DictionaryFilePicker? pickFiles,
}) async {
  await pumpLocalizedWidget(
    tester,
    DictionarySettingsScreen(
      manager: manager,
      isEinkMode: isEinkMode,
      pickFiles: pickFiles,
    ),
    isEinkMode: isEinkMode,
  );
  await tester.pumpAndSettle();
}

/// 清單由上到下的字典 id 順序（依各列在畫面上的垂直位置）。
List<String> _visibleOrder(WidgetTester tester, List<String> ids) {
  final sorted = List<String>.of(ids)
    ..sort(
      (a, b) => tester
          .getTopLeft(find.byKey(Key('dictionary_item_$a')))
          .dy
          .compareTo(
            tester.getTopLeft(find.byKey(Key('dictionary_item_$b'))).dy,
          ),
    );
  return sorted;
}

void main() {
  testWidgets('空清單顯示尚未匯入字典', (tester) async {
    await _pump(tester, FakeDictionaryManager());
    expect(find.byKey(const Key('dictionary_settings_empty')), findsOneWidget);
    expect(find.text('尚未匯入字典'), findsOneWidget);
  });

  testWidgets('清單依序顯示名稱、方向標籤、筆數', (tester) async {
    final manager = FakeDictionaryManager(
      items: [
        _item('a', priority: 0, entryCount: 12),
        _item(
          'b',
          priority: 1,
          sourceLang: 'zh',
          targetLang: 'en',
          entryCount: 1,
        ),
        _item('c', priority: 2, sourceLang: 'zh', targetLang: 'zh-Hant'),
      ],
    );
    await _pump(tester, manager);

    expect(find.text('字典a'), findsOneWidget);
    expect(find.text('英→繁中 · 12 筆'), findsOneWidget);
    expect(find.text('中→英 · 1 筆'), findsOneWidget);
    expect(find.text('中→中 · 3 筆'), findsOneWidget);
    expect(_visibleOrder(tester, ['a', 'b', 'c']), ['a', 'b', 'c']);
  });

  testWidgets('授權說明有填時顯示', (tester) async {
    final manager = FakeDictionaryManager(
      items: [_item('a', licenseNote: 'CC BY-SA 3.0')],
    );
    await _pump(tester, manager);
    expect(find.text('CC BY-SA 3.0'), findsOneWidget);
  });

  testWidgets('切換啟用開關呼叫 setEnabled 並更新畫面', (tester) async {
    final manager = FakeDictionaryManager(items: [_item('a')]);
    await _pump(tester, manager);

    await tester.tap(find.byKey(const Key('dictionary_enabled_a')));
    await tester.pumpAndSettle();

    expect(manager.setEnabledCalls, [(id: 'a', enabled: false)]);
    final switchWidget = tester.widget<Switch>(
      find.byKey(const Key('dictionary_enabled_a')),
    );
    expect(switchWidget.value, isFalse);
  });

  testWidgets('拖曳排序後呼叫 reorder，傳入新的 id 順序', (tester) async {
    final manager = FakeDictionaryManager(
      items: [
        _item('a', priority: 0),
        _item('b', priority: 1),
        _item('c', priority: 2),
      ],
    );
    await _pump(tester, manager);

    await tester.drag(
      find.byKey(const Key('dictionary_drag_handle_c')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(manager.reorderCalls, [
      ['c', 'a', 'b'],
    ]);
    expect(_visibleOrder(tester, ['a', 'b', 'c']), ['c', 'a', 'b']);
  });

  testWidgets('拖曳排序：reorder 尚未完成時畫面已是新順序，不彈回原位', (tester) async {
    final manager = FakeDictionaryManager(
      items: [
        _item('a', priority: 0),
        _item('b', priority: 1),
        _item('c', priority: 2),
      ],
    )..reorderGate = Completer<void>();
    await _pump(tester, manager);

    await tester.drag(
      find.byKey(const Key('dictionary_drag_handle_c')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    // 寫入還卡住，畫面就已經是新順序。
    expect(_visibleOrder(tester, ['a', 'b', 'c']), ['c', 'a', 'b']);

    manager.reorderGate!.complete();
    await tester.pumpAndSettle();
    expect(_visibleOrder(tester, ['a', 'b', 'c']), ['c', 'a', 'b']);
  });

  testWidgets('reorder 丟例外：顯示三段式錯誤並還原成舊順序', (tester) async {
    final manager = FakeDictionaryManager(
      items: [
        _item('a', priority: 0),
        _item('b', priority: 1),
        _item('c', priority: 2),
      ],
    )..reorderError = StateError('disk full');
    await _pump(tester, manager);

    await tester.drag(
      find.byKey(const Key('dictionary_drag_handle_c')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(find.text('無法儲存字典順序。寫入資料時發生錯誤，已還原成原本的順序。請再拖曳一次。'), findsOneWidget);
    expect(_visibleOrder(tester, ['a', 'b', 'c']), ['a', 'b', 'c']);
  });

  testWidgets('刪除：先出確認對話框；取消不刪；確認後呼叫 delete 並從清單消失', (tester) async {
    final manager = FakeDictionaryManager(items: [_item('a'), _item('b')]);
    await _pump(tester, manager);

    await tester.tap(find.byKey(const Key('dictionary_delete_a')));
    await tester.pumpAndSettle();
    expect(find.text('刪除字典'), findsOneWidget);
    expect(find.textContaining('字典a'), findsWidgets);
    expect(find.textContaining('詞條與附屬檔案會一併刪除，無法復原'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dictionary_delete_cancel')));
    await tester.pumpAndSettle();
    expect(manager.deleteCalls, isEmpty);
    expect(find.byKey(const Key('dictionary_item_a')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dictionary_delete_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dictionary_delete_confirm')));
    await tester.pumpAndSettle();

    expect(manager.deleteCalls, ['a']);
    expect(find.byKey(const Key('dictionary_item_a')), findsNothing);
    expect(find.byKey(const Key('dictionary_item_b')), findsOneWidget);
  });

  testWidgets('刪除失敗：顯示三段式錯誤，清單重新載入後仍在，可再按刪除重試', (tester) async {
    final manager = FakeDictionaryManager(items: [_item('a')])
      ..deleteError = StateError('locked');
    await _pump(tester, manager);

    await tester.tap(find.byKey(const Key('dictionary_delete_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dictionary_delete_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('無法刪除這本字典。字典的檔案可能正被其他程式占用。請稍後再按一次刪除。'), findsOneWidget);
    expect(find.byKey(const Key('dictionary_item_a')), findsOneWidget);

    // 重試：排除錯誤後再刪一次，成功且錯誤訊息消失。
    manager.deleteError = null;
    await tester.tap(find.byKey(const Key('dictionary_delete_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dictionary_delete_confirm')));
    await tester.pumpAndSettle();

    expect(manager.deleteCalls, ['a', 'a']);
    expect(find.byKey(const Key('dictionary_item_a')), findsNothing);
    expect(
      find.byKey(const Key('dictionary_settings_action_error')),
      findsNothing,
    );
  });

  testWidgets('MDX 來源缺 CSS 時顯示提醒；非 MDX 來源不顯示提醒與新增附屬檔案', (tester) async {
    final manager = FakeDictionaryManager(
      items: [
        _item(
          'm',
          format: DictionaryFormat.mdx,
          missingCss: ['ghychyz.css', 'b.css'],
        ),
        _item('j', priority: 1),
      ],
    );
    await _pump(tester, manager);

    expect(find.text('詞條引用了 ghychyz.css、b.css，但沒有匯入'), findsOneWidget);
    expect(find.byKey(const Key('dictionary_missing_css_m')), findsOneWidget);
    expect(find.byKey(const Key('dictionary_add_companion_m')), findsOneWidget);
    expect(find.byKey(const Key('dictionary_missing_css_j')), findsNothing);
    expect(find.byKey(const Key('dictionary_add_companion_j')), findsNothing);
  });

  testWidgets('點新增附屬檔案：選檔後呼叫 addCompanions，提醒消失', (tester) async {
    final manager = FakeDictionaryManager(
      items: [
        _item('m', format: DictionaryFormat.mdx, missingCss: ['ghychyz.css']),
      ],
    );
    manager.onAddCompanions = (sourceId, files) {
      manager.items = [_item('m', format: DictionaryFormat.mdx)];
    };
    List<String>? requestedExtensions;
    await _pump(
      tester,
      manager,
      pickFiles: (extensions) async {
        requestedExtensions = extensions;
        return const [
          PickedFile(path: '/tmp/ghychyz.css', name: 'ghychyz.css', size: 10),
        ];
      },
    );

    await tester.tap(find.byKey(const Key('dictionary_add_companion_m')));
    await tester.pumpAndSettle();

    expect(requestedExtensions, containsAll(['css', 'mdd']));
    expect(manager.addCompanionsCalls.single.sourceId, 'm');
    expect(manager.addCompanionsCalls.single.files.single.name, 'ghychyz.css');
    expect(find.byKey(const Key('dictionary_missing_css_m')), findsNothing);
  });

  const addFailedMessage =
      '無法新增附屬檔案。檔案無法讀取，或儲存空間不足。請確認檔案存在、空間足夠後再試一次。';

  testWidgets('addCompanions 丟例外：顯示三段式錯誤，缺檔提醒仍在', (tester) async {
    final manager = FakeDictionaryManager(items: [
      _item('m', format: DictionaryFormat.mdx, missingCss: ['ghychyz.css']),
    ]);
    manager.onAddCompanions = (sourceId, files) => throw StateError('disk full');
    await _pump(
      tester,
      manager,
      pickFiles: (_) async => const [
        PickedFile(path: '/tmp/ghychyz.css', name: 'ghychyz.css', size: 10),
      ],
    );

    await tester.tap(find.byKey(const Key('dictionary_add_companion_m')));
    await tester.pumpAndSettle();

    expect(find.text(addFailedMessage), findsOneWidget);
    expect(find.byKey(const Key('dictionary_missing_css_m')), findsOneWidget);
  });

  testWidgets('選檔器丟例外：顯示同樣的錯誤，不產生未處理例外', (tester) async {
    final manager = FakeDictionaryManager(items: [
      _item('m', format: DictionaryFormat.mdx, missingCss: ['ghychyz.css']),
    ]);
    await _pump(
      tester,
      manager,
      pickFiles: (_) async => throw StateError('picker'),
    );

    await tester.tap(find.byKey(const Key('dictionary_add_companion_m')));
    await tester.pumpAndSettle();

    expect(find.text(addFailedMessage), findsOneWidget);
    expect(manager.addCompanionsCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('list() 丟例外時顯示失敗訊息，不是空白畫面', (tester) async {
    final manager = FakeDictionaryManager()..listError = StateError('db');
    await _pump(tester, manager);

    expect(
      find.byKey(const Key('dictionary_settings_load_error')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('dictionary_settings_empty')), findsNothing);
  });

  testWidgets('E-Ink 模式找不到 AnimatedSwitcher、AnimatedContainer', (tester) async {
    final manager = FakeDictionaryManager(items: [_item('a'), _item('b')]);
    await _pump(tester, manager, isEinkMode: true);

    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.byType(AnimatedContainer), findsNothing);
  });
}
