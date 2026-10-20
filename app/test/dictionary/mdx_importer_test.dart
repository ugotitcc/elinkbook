// MDX 匯入器測試（epic-63 Issue 6a Task 5）。
import 'dart:io';

import 'package:elinkbook/dictionary/dictionary_file_store.dart';
import 'package:elinkbook/dictionary/dictionary_manager.dart';
import 'package:elinkbook/dictionary/importers/dictionary_importer.dart';
import 'package:elinkbook/dictionary/importers/mdx_importer.dart';
import 'package:elinkbook/dictionary/models/dictionary_source.dart';
import 'package:elinkbook/dictionary/storage/dictionary_database.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _fixtures = 'test/fixtures/mdx';

void main() {
  late Database db;
  late DictionaryStore store;
  late Directory tmp;
  late DictionaryFileStore files;
  late MdxImporter importer;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await DictionaryDatabase.open(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    store = DictionaryStore(db);
    tmp = await Directory.systemTemp.createTemp('mdx_importer_test');
    files = DictionaryFileStore(Directory('${tmp.path}/dicts'));
    importer = MdxImporter(store: store, files: files);
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// 把 fixture 複製到暫存目錄（匯入會搬走來源檔，不能直接用版控內的原檔）。
  Future<String> copyFixture(String name) async {
    final dest = File('${tmp.path}/$name');
    await File('$_fixtures/$name').copy(dest.path);
    return dest.path;
  }

  ImportRequest request(
    String path, {
    String? fileName,
    bool replace = false,
    List<({String path, String name})> companions = const [],
  }) {
    final name = fileName ?? path.split(RegExp(r'[\\/]')).last;
    return ImportRequest(
      filePath: path,
      fileName: name,
      sourceLang: 'zh',
      targetLang: 'zh-Hant',
      replaceExisting: replace,
      companions: companions,
    );
  }

  Stream<ImportProgress> start(
    String path, {
    String? fileName,
    bool replace = false,
    List<({String path, String name})> companions = const [],
    CancelToken? cancel,
  }) => importer.import(
    request(path, fileName: fileName, replace: replace, companions: companions),
    cancel: cancel ?? CancelToken(),
  );

  Future<ImportSummary> run(
    String path, {
    String? fileName,
    bool replace = false,
    List<({String path, String name})> companions = const [],
  }) async {
    final last = await start(
      path,
      fileName: fileName,
      replace: replace,
      companions: companions,
    ).last;
    expect(last.stage, ImportStage.done);
    return last.summary!;
  }

  Future<List<Directory>> subdirs(Directory root) async {
    if (!await root.exists()) return const [];
    return root.list().where((e) => e is Directory).cast<Directory>().toList();
  }

  Matcher importError(String code) =>
      isA<DictionaryImportException>().having((e) => e.code, 'code', code);

  test('canHandle：.mdx 不分大小寫', () {
    expect(importer.canHandle('a.mdx'), isTrue);
    expect(importer.canHandle('A.MDX'), isTrue);
    expect(importer.canHandle('a.mdd'), isFalse);
    expect(importer.canHandle('a.css'), isFalse);
  });

  test('匯入 html.mdx＋.mdd＋.css：來源列、私有目錄與 referenced_css', () async {
    final path = await copyFixture('html.mdx');
    final mdd = await copyFixture('mdd.mdd');
    final css = await copyFixture('ghychyz.css');

    final summary = await run(
      path,
      fileName: 'html.mdx',
      companions: [
        (path: mdd, name: 'mdd.mdd'),
        (path: css, name: 'ghychyz.css'),
      ],
    );

    // 來源檔已被搬進私有目錄。
    expect(File(path).existsSync(), isFalse);

    final source = (await store.getSource(summary.sourceId))!;
    expect(source.format, DictionaryFormat.mdx);
    expect(source.entryCount, 3);
    expect(source.storagePath, startsWith(files.dirFor(summary.sourceId).path));
    expect(File(source.storagePath).existsSync(), isTrue);
    expect(
      await files.listFiles(summary.sourceId),
      containsAll(['html.mdx', 'mdd.mdd', 'ghychyz.css']),
    );
    expect(source.referencedCss, contains('ghychyz.css'));

    final manager = DictionaryManager(
      store: DictionaryStoreProvider(() async => store),
      files: files,
      importerFactories: const [],
    );
    expect((await manager.list()).single.missingCss, isEmpty);

    await File('${files.dirFor(summary.sourceId).path}/ghychyz.css').delete();
    expect((await manager.list()).single.missingCss, ['ghychyz.css']);
  });

  test('假 LZO → unsupportedCompression，無來源列與私有目錄', () async {
    final path = await copyFixture('fake-lzo.mdx');

    await expectLater(
      start(path, fileName: 'fake-lzo.mdx').toList(),
      throwsA(importError('unsupportedCompression')),
    );

    expect(await store.listSources(), isEmpty);
    expect(await subdirs(files.root), isEmpty);
  });

  test('記錄區塊截斷 → corruptFile，無殘留', () async {
    final path = await copyFixture('cut-records.mdx');

    await expectLater(
      start(path, fileName: 'cut-records.mdx').toList(),
      throwsA(importError('corruptFile')),
    );

    expect(await store.listSources(), isEmpty);
    expect(await subdirs(files.root), isEmpty);
  });

  test('記錄區塊加密（假檔）→ encryptedRecords，無殘留', () async {
    final path = await _encryptedVariant(tmp);
    await expectLater(
      start(path, fileName: 'encrypted.mdx').toList(),
      throwsA(importError('encryptedRecords')),
    );
    expect(await store.listSources(), isEmpty);
    expect(await subdirs(files.root), isEmpty);
  });

  test('匯入前已取消 → cancelled，無殘留', () async {
    final path = await copyFixture('html.mdx');
    final cancel = CancelToken()..cancel();

    final progress = await start(
      path,
      fileName: 'html.mdx',
      cancel: cancel,
    ).toList();

    expect(progress.last.stage, ImportStage.cancelled);
    expect(await store.listSources(), isEmpty);
    expect(await subdirs(files.root), isEmpty);
  });

  test('取代匯入在搬檔後失敗：舊列與私有目錄一起清掉，不留壞字典', () async {
    final first = await run(
      await copyFixture('html.mdx'),
      fileName: 'html.mdx',
    );
    final id = first.sourceId;
    expect(await store.getSource(id), isNotNull);

    // 同名同內容 → 判為取代既有來源；附屬檔案指向不存在的路徑，讓搬檔後的
    // 複製步驟失敗（此時私有目錄已經被動過）。
    final againDir = await Directory('${tmp.path}/again').create();
    final again = await File(
      '$_fixtures/html.mdx',
    ).copy('${againDir.path}/html.mdx');

    await expectLater(
      start(
        again.path,
        fileName: 'html.mdx',
        replace: true,
        companions: [(path: '${tmp.path}/no-such.css', name: 'ghychyz.css')],
      ).toList(),
      throwsA(isA<DictionaryImportException>()),
    );

    // 舊列的檔案已被這次匯入覆蓋／刪除，留著只會是查不到的字典。
    expect(await store.getSource(id), isNull);
    expect(await store.listSources(), isEmpty);
    expect(await subdirs(files.root), isEmpty);
  });

  test(
    '重複匯入 → DuplicateDictionaryException；取代後沿用 id／priority／enabled',
    () async {
      final first = await run(
        await copyFixture('html.mdx'),
        fileName: 'html.mdx',
      );
      await store.setPriority(first.sourceId, 7);
      await store.setEnabled(first.sourceId, false);

      final duplicate = await copyFixture('html.mdx');
      await expectLater(
        start(duplicate, fileName: 'html.mdx').toList(),
        throwsA(isA<DuplicateDictionaryException>()),
      );

      final replaced = await run(
        duplicate,
        fileName: 'html.mdx',
        replace: true,
      );
      expect(replaced.sourceId, first.sourceId);

      final source = (await store.getSource(first.sourceId))!;
      expect(source.priority, 7);
      expect(source.enabled, isFalse);
      expect(source.referencedCss, contains('ghychyz.css'));
    },
  );

  test('readHints：名稱用 Description 第一行，語言留空', () async {
    final hints = await importer.readHints(
      '$_fixtures/placeholder-title.mdx',
      'placeholder-title.mdx',
    );

    expect(hints.name, '測試辭典');
    expect(hints.sourceLang, isNull);
    expect(hints.targetLang, isNull);
  });
}

/// 把 zlib.mdx 的檔頭 `Encrypted="0"` 就地改成 `"1"`（等長，位移不變）。
/// dict_reader 在讀完檔頭後就會因為記錄區塊加密而拒絕，不會讀到後面的區塊。
Future<String> _encryptedVariant(Directory tmp) async {
  final bytes = await File('$_fixtures/zlib.mdx').readAsBytes();
  final from = _utf16le('Encrypted="0"');
  final to = _utf16le('Encrypted="1"');
  final at = _indexOf(bytes, from);
  if (at < 0) throw StateError('fixture 沒有 Encrypted 欄位');
  final patched = [...bytes];
  for (var i = 0; i < to.length; i++) {
    patched[at + i] = to[i];
  }
  final file = File('${tmp.path}/encrypted.mdx');
  await file.writeAsBytes(patched);
  return file.path;
}

List<int> _utf16le(String text) => [
  for (final unit in text.codeUnits) ...[unit & 0xff, unit >> 8],
];

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
