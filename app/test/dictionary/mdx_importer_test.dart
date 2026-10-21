// MDX 匯入器測試（epic-63 Issue 6a Task 5）。
import 'dart:io';

import 'package:elinkbook/dictionary/dictionary_file_store.dart';
import 'package:elinkbook/dictionary/dictionary_manager.dart';
import 'package:elinkbook/dictionary/importers/dictionary_importer.dart';
import 'package:elinkbook/dictionary/mdx_companion_files.dart';
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

  /// 先匯入一本 html.mdx（附 .mdd），回傳它的 id 與舊目錄的檔名清單。
  Future<String> importOriginal() async {
    final summary = await run(
      await copyFixture('html.mdx'),
      fileName: 'html.mdx',
      companions: [(path: await copyFixture('mdd.mdd'), name: 'mdd.mdd')],
    );
    return summary.sourceId;
  }

  /// 取代匯入的第二份來源檔（同名同內容 → 判為取代既有來源）。
  Future<String> againFile() async {
    final againDir = await Directory('${tmp.path}/again').create();
    final again = await File(
      '$_fixtures/html.mdx',
    ).copy('${againDir.path}/html.mdx');
    return again.path;
  }

  Future<void> expectOldDictionaryIntact(String id) async {
    final source = await store.getSource(id);
    expect(source, isNotNull, reason: '舊來源列要保留');
    expect(File(source!.storagePath).existsSync(), isTrue);
    expect(
      await files.listFiles(id),
      unorderedEquals(['html.mdx', 'mdd.mdd']),
      reason: '舊檔案要原封不動',
    );
    // 只剩正式目錄，沒有暫存或備份目錄。
    expect((await subdirs(files.root)).map((d) => d.uri.pathSegments[
        d.uri.pathSegments.length - 2]), [id]);
  }

  test('取代匯入在搬檔後失敗：舊列與舊檔案原封不動，只刪暫存目錄（I-3）', () async {
    final id = await importOriginal();
    final before = (await store.getSource(id))!;
    await store.setPriority(id, 5);
    await store.setEnabled(id, false);

    // 附屬檔案指向不存在的路徑，讓暫存目錄內的複製步驟失敗。
    await expectLater(
      start(
        await againFile(),
        fileName: 'html.mdx',
        replace: true,
        companions: [(path: '${tmp.path}/no-such.css', name: 'ghychyz.css')],
      ).toList(),
      throwsA(isA<DictionaryImportException>()),
    );

    await expectOldDictionaryIntact(id);
    final after = (await store.getSource(id))!;
    expect(after.priority, 5);
    expect(after.enabled, isFalse);
    expect(after.storagePath, before.storagePath);
  });

  /// 在「暫存目錄已搬檔、複製附屬檔之後、換目錄與寫來源列之前」這個時間點
  /// 取消或失敗，舊字典必須原封不動（I-3）。
  Future<void> expectReplaceInterruptedAfterStaging({
    required void Function(CancelToken cancel) onStaged,
    required bool expectCancelled,
  }) async {
    final id = await importOriginal();
    await store.setPriority(id, 5);
    await store.setEnabled(id, false);
    final cancel = CancelToken();
    importer = MdxImporter(
      store: store,
      files: _SpyFileStore(files.root, onCopied: () => onStaged(cancel)),
    );

    final events = <ImportProgress>[];
    Object? error;
    try {
      await for (final event in start(
        await againFile(),
        fileName: 'html.mdx',
        replace: true,
        companions: [(path: await copyFixture('ghychyz.css'), name: 'ghychyz.css')],
        cancel: cancel,
      )) {
        events.add(event);
      }
    } catch (e) {
      error = e;
    }

    if (expectCancelled) {
      expect(error, isNull);
      expect(events.last.stage, ImportStage.cancelled);
    } else {
      expect(error, isA<DictionaryImportException>());
    }
    // 暫存目錄確實被建立過、且已搬完檔：不是在搬檔前就中止。
    expect(_SpyFileStore.copiedCount, greaterThan(0));
    await expectOldDictionaryIntact(id);
    final after = (await store.getSource(id))!;
    expect(after.priority, 5);
    expect(after.enabled, isFalse);
  }

  test('取代匯入在暫存檔已搬完、換目錄前被取消：舊列與舊檔案原封不動（I-3）', () async {
    await expectReplaceInterruptedAfterStaging(
      onStaged: (cancel) => cancel.cancel(),
      expectCancelled: true,
    );
  });

  test('取代匯入在暫存檔已搬完、換目錄前失敗：舊列與舊檔案原封不動（I-3）', () async {
    await expectReplaceInterruptedAfterStaging(
      onStaged: (_) => throw const FileSystemException('模擬磁碟已滿'),
      expectCancelled: false,
    );
  });

  test('取代匯入換目錄前會先 evict 該字典的 reader（I-3）', () async {
    final evicted = <String>[];
    importer = MdxImporter(
      store: store,
      files: files,
      onEvict: (id) async => evicted.add(id),
    );
    final id = await importOriginal();
    expect(evicted, isEmpty, reason: '新匯入不需要 evict');

    await run(await againFile(), fileName: 'html.mdx', replace: true);

    expect(evicted, [id]);
  });

  test('取代匯入成功：新檔取代主檔，沿用的附屬檔不丟，無暫存／備份目錄', () async {
    final id = await importOriginal();

    final replaced = await run(
      await againFile(),
      fileName: 'html.mdx',
      replace: true,
      companions: [(path: await copyFixture('ghychyz.css'), name: 'ghychyz.css')],
    );

    expect(replaced.sourceId, id);
    expect(
      await files.listFiles(id),
      unorderedEquals(['html.mdx', 'mdd.mdd', 'ghychyz.css']),
      reason: '這次沒選 mdd，舊目錄的 mdd 沿用',
    );
    final source = (await store.getSource(id))!;
    expect(File(source.storagePath).existsSync(), isTrue);
    expect(source.storagePath, startsWith(files.dirFor(id).path));
    expect(await subdirs(files.root), hasLength(1));
  });

  /// 舊字典目錄：html.mdx、mdd.mdd，加上事後用「新增附屬檔案」補的 ghychyz.css。
  Future<String> importOriginalWithLateCss() async {
    final id = await importOriginal();
    await files.copyInto(
      id,
      PickedFile(
        path: await copyFixture('ghychyz.css'),
        name: 'ghychyz.css',
        size: 0,
      ),
    );
    return id;
  }

  test('取代匯入沒帶任何附屬檔：舊目錄的 .css 與 .mdd 沿用（round 4）', () async {
    final id = await importOriginalWithLateCss();

    await run(await againFile(), fileName: 'html.mdx', replace: true);

    expect(
      await files.listFiles(id),
      unorderedEquals(['html.mdx', 'mdd.mdd', 'ghychyz.css']),
    );
    final source = (await store.getSource(id))!;
    // 重新抽樣看得到沿用過來的檔案：沒有缺 css。
    expect(source.referencedCss, ['ghychyz.css']);
    final manager = DictionaryManager(
      store: DictionaryStoreProvider(() async => store),
      files: files,
      importerFactories: const [],
    );
    expect((await manager.list()).single.missingCss, isEmpty);
    expect(await subdirs(files.root), hasLength(1));
  });

  test('取代匯入帶同名 .css（大小寫不同）：新內容勝出，其他舊附屬檔沿用（round 4）', () async {
    final id = await importOriginalWithLateCss();
    final newCss = File('${tmp.path}/new.css')..writeAsStringSync('NEW-CSS');

    await run(
      await againFile(),
      fileName: 'html.mdx',
      replace: true,
      companions: [(path: newCss.path, name: 'GHYCHYZ.CSS')],
    );

    final names = await files.listFiles(id);
    expect(
      names.map((n) => n.toLowerCase()),
      unorderedEquals(['html.mdx', 'mdd.mdd', 'ghychyz.css']),
      reason: '同名（不分大小寫）只留一份',
    );
    final css = names.firstWhere((n) => n.toLowerCase() == 'ghychyz.css');
    expect(File('${files.dirFor(id).path}/$css').readAsStringSync(), 'NEW-CSS');
  });

  Future<void> expectLateCssDictionaryIntact(String id) async {
    expect(await store.getSource(id), isNotNull);
    expect(
      await files.listFiles(id),
      unorderedEquals(['html.mdx', 'mdd.mdd', 'ghychyz.css']),
    );
    expect(await subdirs(files.root), hasLength(1), reason: '只剩正式目錄');
  }

  test('沿用舊附屬檔時複製失敗：舊目錄與舊列原封不動，無暫存目錄（round 4）', () async {
    final id = await importOriginalWithLateCss();
    final oldDir = files.dirFor(id).path;
    importer = MdxImporter(
      store: store,
      files: _SpyFileStore(
        files.root,
        onCopied: () {},
        onCopiedFile: (file) {
          if (file.path.startsWith(oldDir)) {
            throw const FileSystemException('模擬沿用時磁碟已滿');
          }
        },
      ),
    );

    await expectLater(
      start(await againFile(), fileName: 'html.mdx', replace: true).toList(),
      throwsA(isA<DictionaryImportException>()),
    );
    await expectLateCssDictionaryIntact(id);
  });

  test('沿用舊附屬檔之後被取消：舊目錄與舊列原封不動，無暫存目錄（round 4）', () async {
    final id = await importOriginalWithLateCss();
    final oldDir = files.dirFor(id).path;
    final cancel = CancelToken();
    importer = MdxImporter(
      store: store,
      files: _SpyFileStore(
        files.root,
        onCopied: () {},
        onCopiedFile: (file) {
          if (file.path.startsWith(oldDir)) cancel.cancel();
        },
      ),
    );

    final events = await start(
      await againFile(),
      fileName: 'html.mdx',
      replace: true,
      cancel: cancel,
    ).toList();

    expect(events.last.stage, ImportStage.cancelled);
    await expectLateCssDictionaryIntact(id);
  });

  test(
    '重複匯入 → DuplicateDictionaryException；取代後沿用 id／priority／enabled，並重新抽樣 referenced_css',
    () async {
      final first = await run(
        await copyFixture('html.mdx'),
        fileName: 'html.mdx',
      );
      await store.setPriority(first.sourceId, 7);
      await store.setEnabled(first.sourceId, false);
      // 把舊列的 referenced_css 改成過時的值；取代後必須被重新抽樣的結果蓋掉。
      await store.setReferencedCss(first.sourceId, ['stale-old.css']);
      expect(
        (await store.getSource(first.sourceId))!.referencedCss,
        ['stale-old.css'],
      );

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
      expect(source.referencedCss, ['ghychyz.css']);
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

/// 在每次 `copyInto` 完成後呼叫 [onCopied]，用來在「暫存檔已落地」之後
/// 注入取消或失敗。
class _SpyFileStore extends DictionaryFileStore {
  _SpyFileStore(super.root, {required this.onCopied, this.onCopiedFile}) {
    copiedCount = 0;
  }

  final void Function() onCopied;

  /// 需要知道複製的是哪個檔案時使用（例如區分沿用舊附屬檔的複製）。
  final void Function(PickedFile file)? onCopiedFile;

  static int copiedCount = 0;

  @override
  Future<void> copyInto(String sourceId, PickedFile file) async {
    await super.copyInto(sourceId, file);
    copiedCount++;
    // 此時主檔已搬進暫存目錄，附屬檔也已複製。
    expect(await dirFor(sourceId).exists(), isTrue);
    onCopiedFile?.call(file);
    onCopied();
  }
}
