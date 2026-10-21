import 'dart:async';

import 'package:clock/clock.dart';
import 'package:elinkbook/dictionary/dictionary_manager.dart';
import 'package:elinkbook/dictionary/importers/dictionary_importer.dart';
import 'package:elinkbook/dictionary/mdx_companion_files.dart';
import 'package:elinkbook/dictionary/models/dictionary_source.dart';
import 'package:elinkbook/dictionary/providers/moedict_provider.dart';
import 'package:elinkbook/screens/dictionary_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_dictionary_manager.dart';
import '../support/fake_dictionary_settings_repository.dart';
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
  DictionaryTempFileCleaner? clearTempFiles,
  Locale locale = const Locale('zh', 'TW'),
  FakeDictionarySettingsRepository? settings,
}) async {
  await pumpLocalizedWidget(
    tester,
    DictionarySettingsScreen(
      manager: manager,
      isEinkMode: isEinkMode,
      pickFiles: pickFiles,
      clearTempFiles: clearTempFiles,
      settings: settings ?? FakeDictionarySettingsRepository(),
    ),
    isEinkMode: isEinkMode,
    locale: locale,
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

  for (final eink in [true, false]) {
    testWidgets('拖曳進行中（isEinkMode: $eink）拖曳代理列不丟例外，放開後仍會排序', (
      tester,
    ) async {
      final manager = FakeDictionaryManager(
        items: [
          _item('a', priority: 0),
          _item('b', priority: 1),
          _item('c', priority: 2),
        ],
      );
      await _pump(tester, manager, isEinkMode: eink);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('dictionary_drag_handle_c'))),
      );
      // 分段移動並 pump，讓拖曳代理列真的被建進 Overlay。
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -50));
        await tester.pump(const Duration(milliseconds: 50));
      }
      // 放開前檢查：代理列內的 Switch 需要 Material 祖先。
      expect(tester.takeException(), isNull);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(manager.reorderCalls, [
        ['c', 'a', 'b'],
      ]);
    });
  }

  for (final eink in [true, false]) {
    testWidgets('拖曳把手觸控區寬至少 56dp、涵蓋整列高度（isEinkMode: $eink）', (tester) async {
      final manager = FakeDictionaryManager(
        items: [
          _item('a', priority: 0),
          _item('b', priority: 1),
          _item('c', priority: 2),
        ],
      );
      await _pump(tester, manager, isEinkMode: eink);

      final handle = tester.getRect(
        find.byKey(const Key('dictionary_drag_handle_c')),
      );
      final row = tester.getRect(find.byKey(const Key('dictionary_item_c')));
      expect(handle.width, greaterThanOrEqualTo(56));
      expect(handle.height, greaterThanOrEqualTo(row.height - 20));

      // 起點落在舊圖示（左 8dp 起 40dp 寬、上方 8dp 起 40dp 高）之外、
      // 新觸控區之內：水平偏離圖示中心 24dp、貼近列底部。
      final start = Offset(row.left + 8 + 48, row.bottom - 8);
      final gesture = await tester.startGesture(start);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -50));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(manager.reorderCalls, [
        ['c', 'a', 'b'],
      ]);
    });
  }

  testWidgets('拖曳把手帶有語意標籤', (tester) async {
    final manager = FakeDictionaryManager(items: [_item('a')]);
    final semantics = tester.ensureSemantics();
    await _pump(tester, manager);
    expect(
      find.descendant(
        of: find.byKey(const Key('dictionary_drag_handle_a')),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '拖曳排序',
        ),
      ),
      findsOneWidget,
    );
    semantics.dispose();
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

  testWidgets('英文介面：缺 CSS 提醒用英文逗號分隔', (tester) async {
    final manager = FakeDictionaryManager(
      items: [
        _item(
          'm',
          format: DictionaryFormat.mdx,
          missingCss: ['ghychyz.css', 'b.css'],
        ),
      ],
    );
    await _pump(tester, manager, locale: const Locale('en'));

    expect(
      find.text(
        'Entries refer to these files, which were not imported: '
        'ghychyz.css, b.css',
      ),
      findsOneWidget,
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

  group('匯入流程', () {
    PickedFile pf(String name, {int size = 10}) =>
        PickedFile(path: '/tmp/$name', name: name, size: size);

    ImportProgress writing(int processed, int total) => ImportProgress(
      processed: processed,
      total: total,
      stage: ImportStage.writing,
    );

    ImportProgress done({
      int count = 3,
      int skipped = 0,
      List<ImportSkip> samples = const [],
    }) => ImportProgress(
      processed: count,
      total: count,
      stage: ImportStage.done,
      summary: ImportSummary(
        sourceId: 'new',
        importedCount: count,
        skippedCount: skipped,
        skipSamples: samples,
      ),
    );

    /// 成功匯入的 stream：先回報一次進度，再把新字典加進 [manager.items] 並完成。
    Stream<ImportProgress> Function(PickedFile, ImportRequest, CancelToken)
    okStream(FakeDictionaryManager manager, {ImportProgress? last}) =>
        (file, request, cancel) async* {
          yield writing(1, 3);
          // 多檔匯入時 id 不能重複。
          final id = manager.items.any((i) => i.source.id == 'new') ? 'new2' : 'new';
          manager.items = [...manager.items, _item(id)];
          yield last ?? done();
        };

    Future<void> tapImport(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const Key('dictionary_settings_import_button')),
      );
      await tester.pumpAndSettle();
    }

    /// 在匯入對話框選方向（若指定）並按匯入。
    Future<void> confirmDialog(WidgetTester tester, {String? direction}) async {
      expect(find.byKey(const Key('dictionary_import_dialog')), findsOneWidget);
      if (direction != null) {
        await tester.tap(
          find.byKey(Key('dictionary_import_direction_$direction')),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('dictionary_import_confirm')));
      await tester.pumpAndSettle();
    }

    Future<void> closeMessage(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const Key('dictionary_import_message_close')),
      );
      await tester.pumpAndSettle();
    }

    final progress = find.byKey(const Key('dictionary_import_progress'));

    testWidgets('選一個 JSON：預填 → 確認 → 顯示進度 → 完成摘要 → 清單重新載入', (tester) async {
      final manager = FakeDictionaryManager()
        ..importGate = Completer<void>()
        ..readHintsFn = ((f) => const ImportHints(
          name: '提示名稱',
          sourceLang: 'en',
          targetLang: 'zh',
          licenseNote: 'CC0',
        ));
      manager.importStream = okStream(manager);
      await _pump(tester, manager, pickFiles: (_) async => [pf('a.json')]);

      await tapImport(tester);
      expect(find.text('提示名稱'), findsOneWidget);
      expect(find.text('CC0'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dictionary_import_confirm')));
      await tester.pump();
      await tester.pump();

      // 匯入中：進度遮罩出現，清單還沒有新字典。
      expect(progress, findsOneWidget);
      expect(find.text('字典new'), findsNothing);

      manager.importGate!.complete();
      await tester.pumpAndSettle();

      expect(progress, findsNothing);
      expect(find.text('匯入 3 筆'), findsOneWidget);
      expect(manager.importCalls.single.request.name, '提示名稱');
      expect(manager.importCalls.single.request.sourceLang, 'en');
      expect(manager.importCalls.single.request.targetLang, 'zh-Hant');
      expect(manager.importCalls.single.request.licenseNote, 'CC0');
      expect(manager.importCalls.single.request.replaceExisting, isFalse);
      expect(find.text('字典new'), findsOneWidget);
    });

    testWidgets('提示的 sourceLang／targetLang 對得上就預選方向', (tester) async {
      final manager = FakeDictionaryManager()
        ..readHintsFn = ((f) => const ImportHints(
          name: 'CEDICT',
          sourceLang: 'zh',
          targetLang: 'en',
        ));
      await _pump(tester, manager, pickFiles: (_) async => [pf('c.txt')]);
      await tapImport(tester);

      bool selected(String d) => tester
          .widget<ChoiceChip>(find.byKey(Key('dictionary_import_direction_$d')))
          .selected;
      expect(selected('zhToEn'), isTrue);
      expect(selected('enToZh'), isFalse);
    });

    testWidgets('重複匯入：按略過不再匯入', (tester) async {
      final manager = FakeDictionaryManager();
      manager.importStream = (file, request, cancel) async* {
        throw const DuplicateDictionaryException('old');
      };
      await _pump(tester, manager, pickFiles: (_) async => [pf('a.json')]);
      await tapImport(tester);
      await confirmDialog(tester, direction: 'enToZh');

      expect(find.text('這本字典已匯入'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('dictionary_import_duplicate_skip')),
      );
      await tester.pumpAndSettle();

      expect(manager.importCalls, hasLength(1));
      expect(find.text('這本字典已匯入'), findsNothing);
      expect(find.textContaining('匯入 '), findsNothing);
    });

    testWidgets('重複匯入時進度遮罩已先消失，按取代後只出現一個新的進度遮罩', (tester) async {
      final manager = FakeDictionaryManager();
      final replaceGate = Completer<void>();
      manager.importStream = (file, request, cancel) async* {
        if (!request.replaceExisting) {
          throw const DuplicateDictionaryException('old');
        }
        yield writing(1, 3);
        await replaceGate.future;
        yield done();
      };
      await _pump(tester, manager, pickFiles: (_) async => [pf('a.json')]);
      await tapImport(tester);
      await confirmDialog(tester, direction: 'enToZh');

      // 重複提示出現時，進度遮罩已清掉，畫面上只有一個層。
      expect(find.text('這本字典已匯入'), findsOneWidget);
      expect(progress, findsNothing);

      await tester.tap(
        find.byKey(const Key('dictionary_import_duplicate_replace')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('這本字典已匯入'), findsNothing);
      expect(progress, findsOneWidget);
      expect(manager.importCalls, hasLength(2));
      expect(manager.importCalls.last.request.replaceExisting, isTrue);

      replaceGate.complete();
      await tester.pumpAndSettle();
      expect(progress, findsNothing);
      expect(find.text('匯入 3 筆'), findsOneWidget);
    });

    testWidgets('匯入中按取消：CancelToken 被取消，不出現完成摘要，進度遮罩消失', (tester) async {
      final manager = FakeDictionaryManager();
      CancelToken? token;
      manager.importStream = (file, request, cancel) async* {
        token = cancel;
        yield writing(1, 10);
        while (!cancel.isCancelled) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        yield const ImportProgress(
          processed: 1,
          total: 10,
          stage: ImportStage.cancelled,
        );
      };
      await _pump(tester, manager, pickFiles: (_) async => [pf('a.json')]);
      await tapImport(tester);
      await tester.tap(
        find.byKey(const Key('dictionary_import_direction_enToZh')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('dictionary_import_confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(progress, findsOneWidget);

      await tester.tap(
        find.byKey(const Key('dictionary_import_progress_cancel')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(token!.isCancelled, isTrue);
      expect(progress, findsNothing);
      expect(
        find.byKey(const Key('dictionary_import_message_close')),
        findsNothing,
      );
    });

    testWidgets('匯入失敗後進度遮罩消失，錯誤訊息可關閉', (tester) async {
      final manager = FakeDictionaryManager()
        ..importError = const DictionaryImportException('invalidFormat');
      await _pump(tester, manager, pickFiles: (_) async => [pf('a.json')]);
      await tapImport(tester);
      await confirmDialog(tester, direction: 'enToZh');

      expect(progress, findsNothing);
      expect(find.textContaining('格式不符合字典格式'), findsOneWidget);
      await closeMessage(tester);
      expect(find.textContaining('格式不符合字典格式'), findsNothing);
    });

    testWidgets('未知錯誤碼顯示通用三段式訊息，不顯示原始碼', (tester) async {
      final manager = FakeDictionaryManager()
        ..importError = const DictionaryImportException('weirdCode');
      await _pump(tester, manager, pickFiles: (_) async => [pf('a.json')]);
      await tapImport(tester);
      await confirmDialog(tester, direction: 'enToZh');

      expect(find.textContaining('未預期的錯誤'), findsOneWidget);
      expect(find.textContaining('weirdCode'), findsNothing);
    });

    testWidgets('空檔（noValidEntries）顯示三段式錯誤，清單沒有多一本', (tester) async {
      final manager = FakeDictionaryManager(items: [_item('a')])
        ..importError = const DictionaryImportException('noValidEntries');
      await _pump(tester, manager, pickFiles: (_) async => [pf('empty.json')]);
      await tapImport(tester);
      await confirmDialog(tester, direction: 'enToZh');

      expect(find.textContaining('沒有可用的詞條'), findsOneWidget);
      await closeMessage(tester);
      expect(find.byKey(const Key('dictionary_item_a')), findsOneWidget);
      expect(find.byKey(const Key('dictionary_item_new')), findsNothing);
      expect((await manager.list()).length, 1);
    });

    testWidgets('多選兩個檔案：依序各跳一次對話框', (tester) async {
      final manager = FakeDictionaryManager();
      manager.importStream = okStream(manager);
      await _pump(
        tester,
        manager,
        pickFiles: (_) async => [pf('a.json'), pf('b.csv')],
      );
      await tapImport(tester);
      expect(manager.readHintsCalls.map((f) => f.name), ['a.json']);
      await confirmDialog(tester, direction: 'enToZh');

      expect(manager.readHintsCalls.map((f) => f.name), ['a.json', 'b.csv']);
      expect(find.byKey(const Key('dictionary_import_dialog')), findsOneWidget);
      await confirmDialog(tester, direction: 'zhToEn');

      expect(manager.importCalls.map((c) => c.file.name), ['a.json', 'b.csv']);
    });

    testWidgets('有略過筆數：摘要列出略過數與原因', (tester) async {
      final manager = FakeDictionaryManager();
      manager.importStream = okStream(
        manager,
        last: done(
          count: 5,
          skipped: 2,
          samples: const [
            ImportSkip(index: 3, reason: 'missingHeadword'),
            ImportSkip(index: 7, reason: 'malformedLine'),
          ],
        ),
      );
      await _pump(tester, manager, pickFiles: (_) async => [pf('a.json')]);
      await tapImport(tester);
      await confirmDialog(tester, direction: 'enToZh');

      expect(find.text('匯入 5 筆'), findsOneWidget);
      expect(find.text('略過 2 筆'), findsOneWidget);
      expect(find.text('第 3 筆：缺少詞頭'), findsOneWidget);
      expect(find.text('第 7 筆：該行格式不對'), findsOneWidget);
    });

    testWidgets('a.mdx＋a.mdd＋x.css 顯示尚不能匯入 MDX，同批 b.json 照常匯入', (tester) async {
      final manager = FakeDictionaryManager();
      manager.importStream = okStream(manager);
      await _pump(
        tester,
        manager,
        pickFiles: (_) async => [
          pf('a.mdx'),
          pf('a.mdd'),
          pf('x.css'),
          pf('b.json'),
        ],
      );
      await tapImport(tester);
      await confirmDialog(tester, direction: 'enToZh');

      expect(manager.importCalls.map((c) => c.file.name), ['b.json']);
      expect(find.textContaining('這個版本還不能匯入 MDX'), findsOneWidget);
      expect(find.text('匯入 3 筆'), findsOneWidget);
    });

    testWidgets('選 a.mdx＋a.mdd＋x.css：附屬檔案帶進 ImportRequest，方向未選時匯入鈕停用', (
      tester,
    ) async {
      final manager = FakeDictionaryManager()..canImportFn = (_) => true;
      manager.importStream = okStream(manager);
      await _pump(
        tester,
        manager,
        pickFiles: (_) async => [pf('a.mdx'), pf('a.mdd'), pf('x.css')],
      );
      await tapImport(tester);

      // 檔案標頭沒有語言資訊 → 方向未預選，「匯入」停用。
      expect(find.byKey(const Key('dictionary_import_dialog')), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('dictionary_import_confirm')),
      );
      expect(confirm.onPressed, isNull);

      await confirmDialog(tester, direction: 'enToZh');

      expect(manager.importCalls, hasLength(1));
      expect(manager.importCalls.single.file.name, 'a.mdx');
      expect(
        manager.importCalls.single.request.companions.map((c) => c.name),
        ['a.mdd', 'x.css'],
      );
      expect(
        manager.importCalls.single.request.companions.map((c) => c.path),
        ['/tmp/a.mdd', '/tmp/x.css'],
      );
    });

    testWidgets('選 a.mdx＋x.css（沒有 .mdd）：companions 只含 css，不丟型別錯誤', (tester) async {
      final manager = FakeDictionaryManager()..canImportFn = (_) => true;
      manager.importStream = okStream(manager);
      await _pump(
        tester,
        manager,
        pickFiles: (_) async => [pf('a.mdx'), pf('x.css')],
      );
      await tapImport(tester);
      await confirmDialog(tester, direction: 'enToZh');

      expect(
        manager.importCalls.single.request.companions.map((c) => c.name),
        ['x.css'],
      );
      expect(tester.takeException(), isNull);
    });

    for (final (code, expected) in [
      ('unsupportedCompression', '改用 zlib 版本'),
      ('encryptedRecords', '詞條內容有加密'),
      ('corruptFile', '內容不完整或已損毀'),
    ]) {
      testWidgets('MDX 匯入失敗（$code）：顯示三段式訊息，不顯示原始碼', (tester) async {
        final manager = FakeDictionaryManager()..canImportFn = (_) => true;
        manager.importStream = (file, request, cancel) async* {
          throw DictionaryImportException(code);
        };
        await _pump(tester, manager, pickFiles: (_) async => [pf('a.mdx')]);
        await tapImport(tester);
        await confirmDialog(tester, direction: 'enToZh');

        expect(find.textContaining(expected), findsOneWidget);
        expect(find.textContaining(code), findsNothing);
      });
    }

    testWidgets('匯入成功但缺樣式表：摘要列出缺檔並提示新增附屬檔案', (tester) async {
      final manager = FakeDictionaryManager()..canImportFn = (_) => true;
      manager.importStream = (file, request, cancel) async* {
        manager.items = [
          ...manager.items,
          _item('new', format: DictionaryFormat.mdx, missingCss: ['x.css']),
        ];
        yield done();
      };
      await _pump(tester, manager, pickFiles: (_) async => [pf('a.mdx')]);
      await tapImport(tester);
      await confirmDialog(tester, direction: 'enToZh');

      expect(
        find.text('詞條引用了 x.css，但沒有匯入。請到字典清單按「新增附屬檔案」補上。'),
        findsOneWidget,
      );
      expect(find.textContaining('新增附屬檔案'), findsWidgets);
    });

    testWidgets('同批 a.mdx＋b.json：各跳一次對話框、各匯入一次，MDX 失敗不影響 JSON', (tester) async {
      final manager = FakeDictionaryManager()..canImportFn = (_) => true;
      manager.importStream = (file, request, cancel) async* {
        if (file.name == 'a.mdx') {
          throw const DictionaryImportException('invalidFormat');
        }
        manager.items = [...manager.items, _item('new')];
        yield done();
      };
      await _pump(
        tester,
        manager,
        pickFiles: (_) async => [pf('a.mdx'), pf('b.json')],
      );
      await tapImport(tester);

      // 一般檔案先處理，再處理 MDX 組。
      expect(manager.readHintsCalls.map((f) => f.name), ['b.json']);
      await confirmDialog(tester, direction: 'enToZh');
      expect(manager.readHintsCalls.map((f) => f.name), ['b.json', 'a.mdx']);
      await confirmDialog(tester, direction: 'enToZh');

      expect(manager.importCalls.map((c) => c.file.name), ['b.json', 'a.mdx']);
      expect(find.textContaining('格式不符合字典格式'), findsOneWidget);
      expect(find.text('匯入 3 筆'), findsOneWidget);
    });

    testWidgets('MDX 匯入完成後呼叫清除暫存檔；JSON 匯入不呼叫', (tester) async {
      var cleared = 0;
      final manager = FakeDictionaryManager()..canImportFn = (_) => true;
      manager.importStream = okStream(manager);

      Future<bool?> clear() async {
        cleared += 1;
        return true;
      }

      // 先匯入 JSON：不應清除暫存檔。
      await _pump(
        tester,
        manager,
        pickFiles: (_) async => [pf('a.json')],
        clearTempFiles: clear,
      );
      await tapImport(tester);
      await confirmDialog(tester, direction: 'enToZh');
      expect(cleared, 0);
      await closeMessage(tester);

      // 再匯入 MDX：完成後清除一次。
      await tester.pumpWidget(const SizedBox());
      await _pump(
        tester,
        manager,
        pickFiles: (_) async => [pf('a.mdx')],
        clearTempFiles: clear,
      );
      await tapImport(tester);
      await confirmDialog(tester, direction: 'enToZh');
      // 整批結束（摘要對話框關閉）後才清除。
      await closeMessage(tester);
      expect(cleared, 1);
    });

    testWidgets('同一批兩本 MDX：整批結束後才清除暫存檔，且只清一次（C-1）', (tester) async {
      var cleared = 0;
      final manager = FakeDictionaryManager()..canImportFn = (_) => true;
      manager.importStream = okStream(manager);

      await _pump(
        tester,
        manager,
        pickFiles: (_) async => [pf('a.mdx'), pf('b.mdx')],
        clearTempFiles: () async {
          cleared += 1;
          return true;
        },
      );
      await tapImport(tester);

      // 第一本匯入完成後，第二本的對話框已出現：此時還不能清暫存檔，
      // 否則 b.mdx 與它的附屬檔會在讀取前被刪掉。
      await confirmDialog(tester, direction: 'enToZh');
      expect(manager.importCalls.map((c) => c.file.name), ['a.mdx']);
      expect(cleared, 0);

      await confirmDialog(tester, direction: 'enToZh');
      expect(manager.importCalls.map((c) => c.file.name), ['a.mdx', 'b.mdx']);
      expect(cleared, 0, reason: '摘要對話框還開著，整批尚未結束');
      await closeMessage(tester);
      expect(cleared, 1);
    });

    testWidgets('不支援的副檔名顯示不支援的檔案', (tester) async {
      final manager = FakeDictionaryManager()..canImportFn = (_) => false;
      await _pump(tester, manager, pickFiles: (_) async => [pf('a.json')]);
      await tapImport(tester);

      expect(find.textContaining('這個檔案類型不支援'), findsOneWidget);
      // 這個版本還不能匯入 MDX，訊息不可建議使用者改選 MDX。
      expect(find.textContaining('MDX'), findsNothing);
      expect(manager.importCalls, isEmpty);
    });

    testWidgets('讀取提示失敗：顯示三段式錯誤並跳過該檔', (tester) async {
      final manager = FakeDictionaryManager()
        ..readHintsFn = ((f) =>
            throw const DictionaryImportException('unreadableFile'));
      await _pump(tester, manager, pickFiles: (_) async => [pf('a.json')]);
      await tapImport(tester);

      expect(find.textContaining('檔案無法讀取'), findsOneWidget);
      expect(manager.importCalls, isEmpty);
    });

    testWidgets('兩個檔案其中一個讀取提示失敗：錯誤訊息帶出該檔檔名', (tester) async {
      final manager = FakeDictionaryManager()
        ..readHintsFn = ((f) {
          if (f.name == 'bad.json') {
            throw const DictionaryImportException('unreadableFile');
          }
          return const ImportHints(name: '好字典');
        });
      manager.importStream = okStream(manager);
      await _pump(
        tester,
        manager,
        pickFiles: (_) async => [pf('bad.json'), pf('good.json')],
      );
      await tapImport(tester);
      await confirmDialog(tester, direction: 'enToZh');

      expect(find.text('bad.json'), findsOneWidget);
      expect(find.textContaining('檔案無法讀取'), findsOneWidget);
      expect(find.text('good.json'), findsNothing);
    });

    testWidgets('兩個檔案其中一個匯入失敗：錯誤訊息帶出該檔檔名', (tester) async {
      final manager = FakeDictionaryManager();
      manager.importStream = (file, request, cancel) async* {
        if (file.name == 'bad.json') {
          throw const DictionaryImportException('invalidFormat');
        }
        yield done();
      };
      await _pump(
        tester,
        manager,
        pickFiles: (_) async => [pf('bad.json'), pf('good.json')],
      );
      await tapImport(tester);
      await confirmDialog(tester, direction: 'enToZh');
      await confirmDialog(tester, direction: 'enToZh');

      expect(find.text('bad.json'), findsOneWidget);
      expect(find.textContaining('格式不符合字典格式'), findsOneWidget);
    });

    testWidgets('英文介面：匯入與略過筆數單數用 entry、複數用 entries', (tester) async {
      Future<void> importWith(
        WidgetTester tester,
        int count,
        int skipped,
      ) async {
        final manager = FakeDictionaryManager();
        manager.importStream = okStream(
          manager,
          last: done(count: count, skipped: skipped),
        );
        await _pump(
          tester,
          manager,
          pickFiles: (_) async => [pf('a.json')],
          locale: const Locale('en'),
        );
        await tapImport(tester);
        await confirmDialog(tester, direction: 'enToZh');
      }

      await importWith(tester, 1, 1);
      expect(find.text('Imported 1 entry'), findsOneWidget);
      expect(find.text('Skipped 1 entry'), findsOneWidget);
      await closeMessage(tester);

      // 重新建構畫面，換成複數情境。
      await tester.pumpWidget(const SizedBox());
      await importWith(tester, 2, 3);
      expect(find.text('Imported 2 entries'), findsOneWidget);
      expect(find.text('Skipped 3 entries'), findsOneWidget);
    });

    testWidgets('只選 .css（沒有 .mdx）：顯示沒有可附加的字典提醒', (tester) async {
      final manager = FakeDictionaryManager();
      await _pump(tester, manager, pickFiles: (_) async => [pf('x.css')]);
      await tapImport(tester);

      expect(find.textContaining('沒有可附加的字典'), findsOneWidget);
      expect(manager.importCalls, isEmpty);
    });

    testWidgets('超過 50 MB 的檔案在對話框顯示大檔提示', (tester) async {
      final manager = FakeDictionaryManager();
      await _pump(
        tester,
        manager,
        pickFiles: (_) async => [pf('big.json', size: 60 * 1024 * 1024)],
      );
      await tapImport(tester);
      expect(
        find.byKey(const Key('dictionary_import_large_file_hint')),
        findsOneWidget,
      );
    });

    group('匯入進行中按返回', () {
      /// 把設定畫面 push 在一個首頁上，才有返回鍵與可觀察的離開。
      Future<(FakeDictionaryManager, Completer<void>)> pumpPushed(
        WidgetTester tester,
        void Function(CancelToken) onToken,
      ) async {
        final manager = FakeDictionaryManager();
        final gate = Completer<void>();
        manager.importStream = (file, request, cancel) async* {
          onToken(cancel);
          yield writing(1, 3);
          await gate.future;
          manager.items = [...manager.items, _item('new')];
          yield done();
        };
        await pumpLocalizedWidget(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('home_open'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DictionarySettingsScreen(
                      manager: manager,
                      isEinkMode: false,
                      pickFiles: (_) async => [pf('a.json'), pf('b.json')],
                      settings: FakeDictionarySettingsRepository(),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('home_open')));
        await tester.pumpAndSettle();
        await tapImport(tester);
        await tester.tap(
          find.byKey(const Key('dictionary_import_direction_enToZh')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('dictionary_import_confirm')));
        await tester.pump();
        await tester.pump();
        expect(progress, findsOneWidget);
        return (manager, gate);
      }

      testWidgets('不確認：留在畫面且匯入繼續；點遮罩空白處不會關閉', (tester) async {
        CancelToken? token;
        final (manager, gate) = await pumpPushed(tester, (t) => token = t);

        await tester.tapAt(const Offset(5, 300));
        await tester.pump();
        expect(progress, findsOneWidget);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('離開並取消匯入？'), findsOneWidget);
        expect(find.text('繼續匯入'), findsOneWidget);
        expect(find.text('離開並取消'), findsOneWidget);

        await tester.tap(find.byKey(const Key('dictionary_import_leave_stay')));
        await tester.pumpAndSettle();
        expect(find.byType(DictionarySettingsScreen), findsOneWidget);
        expect(token!.isCancelled, isFalse);
        expect(progress, findsOneWidget);

        // 匯入繼續：放行後，第一個檔案完成並接著處理第二個檔案的對話框。
        gate.complete();
        await tester.pumpAndSettle();
        expect(manager.importCalls.map((c) => c.file.name), ['a.json']);
        expect(find.byKey(const Key('dictionary_import_dialog')), findsOneWidget);
      });

      testWidgets('確認：取消匯入、離開畫面，後面的檔案不再處理', (tester) async {
        CancelToken? token;
        final (manager, gate) = await pumpPushed(tester, (t) => token = t);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('dictionary_import_leave_confirm')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DictionarySettingsScreen), findsNothing);
        expect(token!.isCancelled, isTrue);

        // 放行卡住的 stream，確認離開後不會再處理 b.json，也不丟例外。
        gate.complete();
        await tester.pumpAndSettle();
        expect(manager.readHintsCalls.map((f) => f.name), ['a.json']);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('線上查詞區塊（epic-63 Issue 7）', () {
    SwitchListTile onlineSwitch(WidgetTester tester) =>
        tester.widget<SwitchListTile>(
          find.byKey(const Key('dictionary_online_switch')),
        );

    testWidgets('預設關閉並顯示尚未同意，且載入同意狀態一次', (tester) async {
      final settings = FakeDictionarySettingsRepository();

      await _pump(tester, FakeDictionaryManager(), settings: settings);

      expect(find.byKey(const Key('dictionary_online_section')), findsOneWidget);
      expect(onlineSwitch(tester).value, isFalse);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dictionary_online_status')))
            .data,
        '尚未同意',
      );
      expect(settings.loadCount, 1);
    });

    testWidgets('打開開關先跳同意對話框；取消後仍關閉且不寫入', (tester) async {
      final settings = FakeDictionarySettingsRepository();

      await _pump(tester, FakeDictionaryManager(), settings: settings);
      await tester.tap(find.byKey(const Key('dictionary_online_switch')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('dictionary_online_consent_dialog')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('dictionary_online_consent_cancel')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('dictionary_online_consent_dialog')),
        findsNothing,
      );
      expect(onlineSwitch(tester).value, isFalse);
      expect(settings.saveCount, 0);
      expect(settings.consentAt, isNull);
    });

    testWidgets('同意後開關為開、狀態顯示日期，並寫入同意時刻', (tester) async {
      final settings = FakeDictionarySettingsRepository();
      final now = DateTime.utc(2026, 10, 21, 12);

      await withClock(Clock.fixed(now), () async {
        await _pump(tester, FakeDictionaryManager(), settings: settings);
        await tester.tap(find.byKey(const Key('dictionary_online_switch')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('dictionary_online_consent_agree')),
        );
        await tester.pumpAndSettle();
      });

      expect(settings.saveCount, 1);
      expect(settings.consentAt, now);
      expect(onlineSwitch(tester).value, isTrue);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dictionary_online_status')))
            .data,
        contains('2026-10-21'),
      );
    });

    testWidgets('對話框開啟與儲存期間開關停用，不會重複觸發', (tester) async {
      final settings = _GatedSettingsRepository();

      await _pump(tester, FakeDictionaryManager(), settings: settings);
      await tester.tap(find.byKey(const Key('dictionary_online_switch')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('dictionary_online_consent_dialog')),
        findsOneWidget,
      );
      expect(onlineSwitch(tester).onChanged, isNull);

      await tester.tap(
        find.byKey(const Key('dictionary_online_consent_agree')),
      );
      await tester.pumpAndSettle();

      // 儲存尚未完成：開關維持停用，也沒有再跳一次對話框。
      expect(onlineSwitch(tester).onChanged, isNull);
      expect(settings.saveCount, 1);
      expect(
        find.byKey(const Key('dictionary_online_consent_dialog')),
        findsNothing,
      );

      settings.saveGate.complete();
      await tester.pumpAndSettle();

      expect(onlineSwitch(tester).onChanged, isNotNull);
      expect(onlineSwitch(tester).value, isTrue);
    });

    testWidgets('已同意時關閉開關：清除同意且不跳對話框', (tester) async {
      final settings = FakeDictionarySettingsRepository(
        consentAt: DateTime.utc(2026, 10, 20, 3),
      );

      await _pump(tester, FakeDictionaryManager(), settings: settings);
      expect(onlineSwitch(tester).value, isTrue);

      await tester.tap(find.byKey(const Key('dictionary_online_switch')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('dictionary_online_consent_dialog')),
        findsNothing,
      );
      expect(settings.saveCount, 1);
      expect(settings.consentAt, isNull);
      expect(onlineSwitch(tester).value, isFalse);
    });

    testWidgets('儲存失敗：開關維持關閉、顯示三段式錯誤、不丟例外', (tester) async {
      final settings = FakeDictionarySettingsRepository()..failOnSave = true;

      await _pump(tester, FakeDictionaryManager(), settings: settings);
      await tester.tap(find.byKey(const Key('dictionary_online_switch')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('dictionary_online_consent_agree')),
      );
      await tester.pumpAndSettle();

      expect(onlineSwitch(tester).value, isFalse);
      expect(settings.consentAt, isNull);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dictionary_online_status')))
            .data,
        '尚未同意',
      );
      final error = tester.widget<Text>(
        find.byKey(const Key('dictionary_online_save_error')),
      );
      // 三段式：發生什麼（沒有儲存成功）、為什麼（無法寫入）、怎麼辦（請再切換）。
      expect(error.data, contains('沒有儲存成功'));
      expect(error.data, contains('無法寫入'));
      expect(error.data, contains('請'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('字典清單為空時區塊仍在', (tester) async {
      await _pump(tester, FakeDictionaryManager());

      expect(find.byKey(const Key('dictionary_settings_empty')), findsOneWidget);
      expect(find.byKey(const Key('dictionary_online_section')), findsOneWidget);
    });

    testWidgets('字典清單載入失敗時區塊仍在', (tester) async {
      final manager = FakeDictionaryManager()..listError = StateError('db');

      await _pump(tester, manager);

      expect(
        find.byKey(const Key('dictionary_settings_load_error')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('dictionary_online_section')), findsOneWidget);
    });

    testWidgets('有字典清單時區塊仍在，並顯示萌典來源標示', (tester) async {
      final manager = FakeDictionaryManager(items: [_item('a')]);

      await _pump(tester, manager);

      expect(find.byKey(const Key('dictionary_online_section')), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('dictionary_online_attribution')),
            )
            .data,
        MoedictProvider.attribution,
      );
    });
  });
}

/// `saveOnlineConsentAt` 會停在 [saveGate]，用來驗證「儲存期間」開關停用。
class _GatedSettingsRepository extends FakeDictionarySettingsRepository {
  final Completer<void> saveGate = Completer<void>();

  @override
  Future<void> saveOnlineConsentAt(DateTime? at) async {
    saveCount++;
    await saveGate.future;
    consentAt = at;
  }
}
