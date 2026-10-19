// app/test/dictionary/dictionary_interfaces_test.dart
import 'package:elinkbook/dictionary/importers/dictionary_importer.dart';
import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/models/lookup_request.dart';
import 'package:elinkbook/dictionary/models/lookup_result.dart';
import 'package:elinkbook/dictionary/providers/dictionary_provider.dart';
import 'package:elinkbook/dictionary/providers/online_dictionary_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProvider implements DictionaryProvider {
  @override
  String get id => 'fake';

  @override
  Future<ProviderOutcome> lookup(LookupRequest request) async => ProviderOutcome(
        providerId: id,
        displayName: '假字典',
        status: OutcomeStatus.found,
        entries: [
          DictionaryEntry(
            sourceId: id,
            headword: request.word,
            body: '釋義',
            bodyKind: EntryBodyKind.plainText,
          ),
        ],
      );
}

class _FakeOnline extends _FakeProvider implements OnlineDictionaryProvider {}

class _FakeImporter implements DictionaryImporter {
  @override
  bool canHandle(String fileName) => fileName.endsWith('.json');

  @override
  Future<ImportHints> readHints(String filePath, String fileName) async =>
      const ImportHints(name: 'x');

  @override
  Stream<ImportProgress> import(
    ImportRequest request, {
    required CancelToken cancel,
  }) =>
      Stream.value(const ImportProgress(processed: 1, total: 1));
}

void main() {
  test('DictionaryProvider 回傳 ProviderOutcome', () async {
    final outcome = await _FakeProvider().lookup(const LookupRequest('run'));
    expect(outcome.status, OutcomeStatus.found);
    expect(outcome.entries.length, 1);
  });

  test('OnlineDictionaryProvider 也是 DictionaryProvider', () {
    expect(_FakeOnline(), isA<DictionaryProvider>());
  });

  test('DictionaryImporter 可依檔名判斷並串流進度', () async {
    final importer = _FakeImporter();
    expect(importer.canHandle('a.json'), isTrue);
    final progress = await importer
        .import(
          const ImportRequest(
            filePath: '/tmp/a.json',
            fileName: 'a.json',
            sourceLang: 'en',
            targetLang: 'zh-Hant',
          ),
          cancel: CancelToken(),
        )
        .toList();
    expect(progress.single.processed, 1);
  });

  test('ImportProgress 預設為寫入階段且沒有摘要', () {
    const progress = ImportProgress(processed: 1, total: 2);
    expect(progress.stage, ImportStage.writing);
    expect(progress.summary, isNull);
  });

  test('CancelToken 取消後 isCancelled 為 true', () {
    final token = CancelToken();
    expect(token.isCancelled, isFalse);
    token.cancel();
    expect(token.isCancelled, isTrue);
  });

  test('headwordNorm 去頭尾空白並轉小寫', () {
    expect(headwordNorm('  IT '), 'it');
    expect(headwordNorm('相濡以沫'), '相濡以沫');
  });
}
