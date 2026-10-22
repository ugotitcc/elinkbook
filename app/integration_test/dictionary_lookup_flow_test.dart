// epic-63 Issue 8 Task 4：字典查詢流程的真機整合測試。
//
// 用真實的 `DictionaryService`、`DictionaryManager`、`DictionaryDatabase`
// （裝置暫存目錄下的 `dictionary.db`）與真實匯入器，不經檔案選擇器；測試資料
// 在 `setUp` 用 Dart 字串寫進 `getTemporaryDirectory()`，做法比照
// `dictionary_mdx_test.dart`，不新增 fixture（也就不必動 `pubspec.yaml`）。
//
// 涵蓋 spec §9 的驗收 3、5、6、13、33：匯入後面板顯示結果、候選鏈詞形還原、
// CC-CEDICT 繁簡同筆與授權說明、離線仍可查本機、刪除後資料與私有檔案清除。
import 'dart:async';
import 'dart:io';

import 'package:elinkbook/dictionary/dictionary_file_store.dart';
import 'package:elinkbook/dictionary/dictionary_manager.dart';
import 'package:elinkbook/dictionary/dictionary_service.dart';
import 'package:elinkbook/dictionary/dictionary_settings_repository.dart';
import 'package:elinkbook/dictionary/importers/cedict_importer.dart';
import 'package:elinkbook/dictionary/importers/dictionary_importer.dart';
import 'package:elinkbook/dictionary/importers/json_csv_importer.dart';
import 'package:elinkbook/dictionary/importers/mdx_importer.dart';
import 'package:elinkbook/dictionary/mdx_companion_files.dart';
import 'package:elinkbook/dictionary/models/lookup_result.dart';
import 'package:elinkbook/dictionary/providers/moedict_provider.dart';
import 'package:elinkbook/dictionary/storage/dictionary_database.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store_provider.dart';
import 'package:elinkbook/dictionary/storage/mdx_reader_pool.dart';
import 'package:elinkbook/screens/widgets/dictionary_lookup_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../test/support/pump_localized_widget.dart';

const String _jsonDictionary = '''
{
  "name": "測試字典",
  "sourceLang": "zh",
  "targetLang": "zh",
  "entries": [
    {"headword": "天地", "definition": "天與地。", "pronunciation": "tiān dì"}
  ]
}
''';

/// 只存 `run` 的英→中字典，用來驗證 `ran` 的詞形還原候選。
const String _englishJsonDictionary = '''
{
  "name": "英文測試字典",
  "sourceLang": "en",
  "targetLang": "zh",
  "entries": [
    {"headword": "run", "definition": "跑", "pos": "v"}
  ]
}
''';

/// 最小 CC-CEDICT：一行繁簡不同、一行相同；檔頭帶授權。
const String _cedict = '''
# CC-CEDICT 測試資料
#! license=CC BY-SA 4.0

學生 学生 [xue2 sheng5] /student/pupil/
天地 天地 [tian1 di4] /heaven and earth/
''';

/// 同意線上查詞的設定來源；只實作測試需要的部分。
class _ConsentedSettings implements DictionarySettingsRepository {
  @override
  Future<DateTime?> loadOnlineConsentAt() async => DateTime.utc(2026, 10, 22);

  @override
  Future<void> saveOnlineConsentAt(DateTime? at) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Database db;
  late DictionaryStore store;
  late DictionaryStoreProvider provider;
  late DictionaryFileStore files;
  late MdxReaderPool mdxPool;
  late DictionaryManager manager;

  setUp(() async {
    final cache = await getTemporaryDirectory();
    tempRoot = await Directory(
      '${cache.path}/dictionary_lookup_flow_'
      '${DateTime.now().microsecondsSinceEpoch}',
    ).create(recursive: true);
    db = await DictionaryDatabase.open('${tempRoot.path}/dictionary.db');
    store = DictionaryStore(db);
    provider = DictionaryStoreProvider(() async => store);
    files = DictionaryFileStore(Directory('${tempRoot.path}/dictionaries'));
    mdxPool = MdxReaderPool();
    manager = DictionaryManager(
      store: provider,
      files: files,
      importerFactories: [
        (s) => JsonCsvImporter(store: s),
        (s) => CedictImporter(store: s),
        (s) => MdxImporter(store: s, files: files, onEvict: mdxPool.evict),
      ],
      onEvict: mdxPool.evict,
    );
  });

  tearDown(() async {
    await mdxPool.closeAll();
    await db.close();
    try {
      if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
    } on FileSystemException {
      // 裝置暫存目錄偶有殘留檔案鎖；測試結果不受影響。
    }
  });

  /// 把文字寫成暫存檔，交給 [DictionaryManager.import] 匯入，回傳摘要。
  Future<ImportSummary> importText(
    String fileName,
    String text, {
    required String sourceLang,
    required String targetLang,
    String? name,
    List<({String path, String name})> companions = const [],
  }) async {
    final path = '${tempRoot.path}/$fileName';
    await File(path).writeAsString(text, flush: true);
    final progress = await manager
        .import(
          PickedFile(path: path, name: fileName, size: text.length),
          ImportRequest(
            filePath: path,
            fileName: fileName,
            sourceLang: sourceLang,
            targetLang: targetLang,
            name: name,
            companions: companions,
          ),
          cancel: CancelToken(),
        )
        .toList();
    return progress.last.summary!;
  }

  /// 把 Flutter asset 複製成裝置上的真實檔案。
  Future<String> stageAsset(String assetPath, String fileName) async {
    final bytes = await rootBundle.load(assetPath);
    final file = File('${tempRoot.path}/$fileName');
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file.path;
  }

  /// 本機查詢完成後的第一個 `found` 分段。
  ProviderOutcome foundOutcome(DictionaryLookupResponse response) {
    expect(response, isA<LookupCompleted>());
    final completed = response as LookupCompleted;
    final found = completed.result.outcomes
        .where((o) => o.status == OutcomeStatus.found)
        .toList();
    expect(found, isNotEmpty, reason: '沒有任何分段查到詞條');
    return found.first;
  }

  /// 輪詢畫面直到出現 [text]（真實資料庫查詢是非同步的）。
  Future<void> waitForText(WidgetTester tester, String text) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      if (find.text(text).evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
    fail('等待逾時：畫面沒有出現「$text」');
  }

  testWidgets('JSON 字典匯入後，查詢面板顯示結果', (tester) async {
    await importText(
      'test_dictionary.json',
      _jsonDictionary,
      sourceLang: 'zh',
      targetLang: 'zh',
    );
    final service = DictionaryService.fromProvider(provider, mdxPool: mdxPool);

    await pumpLocalizedWidget(tester, const Scaffold(body: SizedBox.expand()));
    unawaited(
      DictionaryLookupSheet.show(
        tester.element(find.byType(Scaffold)),
        selectedText: '天地',
        service: service,
        isEinkMode: false,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    await waitForText(tester, '天與地。');
    expect(find.text('天地'), findsWidgets);
  });

  testWidgets('查詢候選鏈：ran 能查到只存 run 的字典（驗收 13）', (tester) async {
    await importText(
      'english.json',
      _englishJsonDictionary,
      sourceLang: 'en',
      targetLang: 'zh',
    );
    final service = DictionaryService.fromProvider(provider, mdxPool: mdxPool);

    final response = await service.lookup('ran');

    final outcome = foundOutcome(response);
    expect(outcome.entries.single.headword, 'run');
    expect(outcome.entries.single.body, '跑');
  });

  testWidgets('CC-CEDICT：查繁體與簡體得到同一筆，並帶授權說明（驗收 33）',
      (tester) async {
    await importText('cedict_ts.u8', _cedict, sourceLang: 'zh', targetLang: 'en');
    final service = DictionaryService.fromProvider(provider, mdxPool: mdxPool);

    final traditional = foundOutcome(await service.lookup('學生'));
    final simplified = foundOutcome(await service.lookup('学生'));

    expect(traditional.entries.single.body, 'student\npupil');
    expect(simplified.entries.single.body, traditional.entries.single.body);

    // 授權說明存在來源列上，設定畫面會顯示它（`dictionary_settings_screen.dart`
    // 的 `source.licenseNote`）。
    final items = await manager.list();
    expect(items.single.source.licenseNote, 'CC BY-SA 4.0');
  });

  testWidgets('沒有網路也能查本機字典（驗收 5）', (tester) async {
    await importText(
      'offline.json',
      _jsonDictionary,
      sourceLang: 'zh',
      targetLang: 'zh',
    );
    final client = http.Client();
    addTearDown(client.close);
    final moedict = MoedictProvider(client: client);
    final service = DictionaryService.fromProvider(
      provider,
      mdxPool: mdxPool,
      onlineProvider: moedict,
      settings: _ConsentedSettings(),
      // 已同意線上查詞，但裝置沒有連線：本機結果不受影響，線上是 failed/offline。
      isNetworkAvailable: () async => false,
    );

    final response = await service.lookup('天地');

    expect(response, isA<LookupCompleted>());
    final completed = response as LookupCompleted;
    final local = completed.result.outcomes
        .firstWhere((o) => o.providerId != moedict.id);
    expect(local.status, OutcomeStatus.found);
    expect(local.entries.single.body, '天與地。');

    final online = completed.result.outcomes
        .firstWhere((o) => o.providerId == moedict.id);
    expect(online.status, OutcomeStatus.failed);
    expect(online.errorCode, 'offline');
  });

  testWidgets('驗收 23：本機查詢 p95 小於 300 ms（含候選鏈，真機）', (tester) async {
    // 一半查得到（第一個候選就命中）、一半查不到（跑完整條候選鏈），
    // 量測含 SQLite 與候選產生的服務層延遲。
    final entries = List.generate(
      200,
      (i) => '{"headword": "term$i", "definition": "詞條 $i"}',
    ).join(',\n');
    await importText(
      'p95.json',
      '{"name": "p95", "sourceLang": "en", "targetLang": "zh", '
          '"entries": [$entries]}',
      sourceLang: 'en',
      targetLang: 'zh',
    );
    final service = DictionaryService.fromProvider(provider, mdxPool: mdxPool);

    // 暖機：第一次查詢含來源清單載入，不列入分佈。
    await service.lookup('term0');

    final samples = <int>[];
    final stopwatch = Stopwatch();
    for (var i = 0; i < 200; i++) {
      final word = i.isEven ? 'term$i' : 'term${i}ed';
      stopwatch
        ..reset()
        ..start();
      await service.lookup(word);
      stopwatch.stop();
      samples.add(stopwatch.elapsedMicroseconds);
    }
    samples.sort();
    final p50 = samples[99] / 1000;
    final p95 = samples[189] / 1000;
    debugPrint('驗收 23：本機查詢 p50 = ${p50.toStringAsFixed(1)} ms、'
        'p95 = ${p95.toStringAsFixed(1)} ms（200 次）');
    expect(p95, lessThan(300));
  });

  testWidgets('刪除字典後相關資料清除（驗收 6）', (tester) async {
    // MDX 主檔與 `.mdd` 附屬檔都是真實檔案，刪除要連私有目錄一起清掉。
    final mdxPath = await stageAsset('test/fixtures/mdx/images.mdx', 'images.mdx');
    final mddPath = await stageAsset('test/fixtures/mdx/images.mdd', 'images.mdd');
    final fileName = 'images.mdx';
    final progress = await manager
        .import(
          PickedFile(path: mdxPath, name: fileName, size: 0),
          ImportRequest(
            filePath: mdxPath,
            fileName: fileName,
            // 詞頭是拉丁字母（`pic`），來源語言要是 en 才會被拉丁選字挑到。
            sourceLang: 'en',
            targetLang: 'zh',
            companions: [(path: mddPath, name: 'images.mdd')],
          ),
          cancel: CancelToken(),
        )
        .toList();
    final sourceId = progress.last.summary!.sourceId;

    final service = DictionaryService.fromProvider(provider, mdxPool: mdxPool);
    final before = foundOutcome(await service.lookup('pic'));
    expect(before.entries, isNotEmpty);
    expect(await files.listFiles(sourceId), contains('images.mdd'));
    expect(await files.dirFor(sourceId).exists(), isTrue);

    await manager.delete(sourceId);

    expect(await store.getSource(sourceId), isNull);
    expect(await files.listFiles(sourceId), isEmpty);
    expect(await files.dirFor(sourceId).exists(), isFalse);

    final after = await service.lookup('pic');
    expect(after, isA<LookupCompleted>());
    expect((after as LookupCompleted).hasEnabledDictionary, isFalse);
    expect(after.result.outcomes, isEmpty);
  });
}
