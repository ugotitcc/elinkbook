import 'package:elinkbook/dictionary/importers/dictionary_importer.dart';
import 'package:elinkbook/screens/widgets/dictionary_import_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_localized_widget.dart';

/// 開一個按鈕，按下後顯示匯入對話框，結果存進 [result]。
class _Host extends StatelessWidget {
  const _Host({
    required this.hints,
    required this.initialDirection,
    required this.isLargeFile,
    required this.onResult,
  });

  final ImportHints hints;
  final DictionaryDirection? initialDirection;
  final bool isLargeFile;
  final void Function(ImportChoices?) onResult;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: const Key('open'),
        onPressed: () async {
          final r = await showDictionaryImportDialog(
            context,
            hints: hints,
            initialDirection: initialDirection,
            isLargeFile: isLargeFile,
            isEinkMode: false,
          );
          onResult(r);
        },
        child: const Text('open'),
      ),
    ),
  );
}

Future<void> _open(
  WidgetTester tester, {
  ImportHints hints = const ImportHints(name: '預填名稱', licenseNote: 'CC0'),
  DictionaryDirection? initialDirection,
  bool isLargeFile = false,
  required void Function(ImportChoices?) onResult,
}) async {
  await pumpLocalizedWidget(
    tester,
    _Host(
      hints: hints,
      initialDirection: initialDirection,
      isLargeFile: isLargeFile,
      onResult: onResult,
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

void main() {
  group('DictionaryDirection.fromLangs', () {
    test('固定語言碼', () {
      expect(
        DictionaryDirection.fromLangs('en', 'zh-Hant'),
        DictionaryDirection.enToZh,
      );
      expect(
        DictionaryDirection.fromLangs('zh', 'en'),
        DictionaryDirection.zhToEn,
      );
      expect(
        DictionaryDirection.fromLangs('zh', 'zh-Hant'),
        DictionaryDirection.zhToZh,
      );
    });

    test('寬容比對：大小寫、底線、只看第一段', () {
      expect(
        DictionaryDirection.fromLangs('EN', 'zh-TW'),
        DictionaryDirection.enToZh,
      );
      expect(
        DictionaryDirection.fromLangs('zh', 'zh_CN'),
        DictionaryDirection.zhToZh,
      );
      expect(
        DictionaryDirection.fromLangs('en', 'zh'),
        DictionaryDirection.enToZh,
      );
    });

    test('對不上或缺值回傳 null', () {
      expect(DictionaryDirection.fromLangs('fr', 'en'), isNull);
      expect(DictionaryDirection.fromLangs('en', 'en'), isNull);
      expect(DictionaryDirection.fromLangs(null, null), isNull);
      expect(DictionaryDirection.fromLangs('en', null), isNull);
    });

    test('固定語言碼屬性', () {
      expect(DictionaryDirection.enToZh.sourceLang, 'en');
      expect(DictionaryDirection.enToZh.targetLang, 'zh-Hant');
      expect(DictionaryDirection.zhToEn.sourceLang, 'zh');
      expect(DictionaryDirection.zhToEn.targetLang, 'en');
      expect(DictionaryDirection.zhToZh.sourceLang, 'zh');
      expect(DictionaryDirection.zhToZh.targetLang, 'zh-Hant');
    });
  });

  testWidgets('initialDirection 為 null 時匯入按鈕停用，選了方向後啟用', (tester) async {
    await _open(tester, onResult: (_) {});
    FilledButton confirm() => tester.widget<FilledButton>(
      find.byKey(const Key('dictionary_import_confirm')),
    );
    expect(confirm().onPressed, isNull);

    await tester.tap(
      find.byKey(const Key('dictionary_import_direction_zhToEn')),
    );
    await tester.pumpAndSettle();
    expect(confirm().onPressed, isNotNull);
  });

  testWidgets('還沒選方向時，選項下方顯示「請先選擇查詢方向」，選了就消失', (tester) async {
    await _open(tester, onResult: (_) {});
    final hint = find.byKey(const Key('dictionary_import_direction_hint'));
    expect(hint, findsOneWidget);
    expect(find.text('請先選擇查詢方向'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('dictionary_import_direction_zhToZh')),
    );
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
  });

  testWidgets('已有預選方向時不顯示方向提示', (tester) async {
    await _open(
      tester,
      initialDirection: DictionaryDirection.enToZh,
      onResult: (_) {},
    );
    expect(
      find.byKey(const Key('dictionary_import_direction_hint')),
      findsNothing,
    );
  });

  testWidgets('名稱與授權預填 hints，可修改，確認時回傳修改後的值', (tester) async {
    ImportChoices? result;
    await _open(
      tester,
      initialDirection: DictionaryDirection.enToZh,
      onResult: (r) => result = r,
    );
    expect(find.text('預填名稱'), findsOneWidget);
    expect(find.text('CC0'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('dictionary_import_name')),
      '改過的名稱',
    );
    await tester.enterText(
      find.byKey(const Key('dictionary_import_license')),
      'CC BY-SA',
    );
    await tester.tap(find.byKey(const Key('dictionary_import_confirm')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.name, '改過的名稱');
    expect(result!.licenseNote, 'CC BY-SA');
    expect(result!.direction, DictionaryDirection.enToZh);
  });

  testWidgets('isLargeFile 為真時顯示大檔提示，為假時不顯示', (tester) async {
    await _open(tester, isLargeFile: true, onResult: (_) {});
    expect(
      find.byKey(const Key('dictionary_import_large_file_hint')),
      findsOneWidget,
    );
  });

  testWidgets('非大檔不顯示大檔提示', (tester) async {
    await _open(tester, onResult: (_) {});
    expect(
      find.byKey(const Key('dictionary_import_large_file_hint')),
      findsNothing,
    );
  });

  testWidgets('取消回傳 null', (tester) async {
    var called = false;
    ImportChoices? result = (
      name: 'x',
      direction: DictionaryDirection.enToZh,
      licenseNote: '',
    );
    await _open(
      tester,
      initialDirection: DictionaryDirection.enToZh,
      onResult: (r) {
        called = true;
        result = r;
      },
    );
    await tester.tap(find.byKey(const Key('dictionary_import_cancel')));
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(result, isNull);
  });
}
