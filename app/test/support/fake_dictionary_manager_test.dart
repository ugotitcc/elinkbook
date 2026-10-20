import 'package:elinkbook/dictionary/dictionary_manager.dart';
import 'package:elinkbook/dictionary/models/dictionary_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_dictionary_manager.dart';

DictionaryListItem _item(String id, int priority) => DictionaryListItem(
  source: DictionarySource(
    id: id,
    name: id,
    format: DictionaryFormat.jsonCsv,
    sourceLang: 'en',
    targetLang: 'zh-Hant',
    priority: priority,
    enabled: true,
    storagePath: '',
    entryCount: 1,
    licenseNote: '',
    importedAt: DateTime(2026),
  ),
  missingCss: const [],
);

void main() {
  test('reorder：不存在的 id 不佔序號，未列出的來源保留原優先序', () async {
    final fake = FakeDictionaryManager(
      items: [_item('a', 0), _item('b', 1), _item('c', 2)],
    );

    await fake.reorder(['c', 'zzz', 'a']);

    final list = await fake.list();
    expect(list.map((e) => (e.source.id, e.source.priority)), [
      ('c', 0),
      ('a', 1),
      ('b', 1),
    ]);
  });

  test('delete：deleteError 時丟例外且來源列保留', () async {
    final fake = FakeDictionaryManager(items: [_item('a', 0)])
      ..deleteError = StateError('x');

    await expectLater(fake.delete('a'), throwsStateError);

    expect(fake.deleteCalls, ['a']);
    expect((await fake.list()).length, 1);
  });
}
