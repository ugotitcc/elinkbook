// app/test/dictionary/cedict_importer_test.dart
import 'dart:io';

import 'package:elinkbook/dictionary/importers/cedict_importer.dart';
import 'package:elinkbook/dictionary/importers/dictionary_importer.dart';
import 'package:elinkbook/dictionary/models/dictionary_entry.dart';
import 'package:elinkbook/dictionary/models/dictionary_source.dart';
import 'package:elinkbook/dictionary/storage/dictionary_database.dart';
import 'package:elinkbook/dictionary/storage/dictionary_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late DictionaryStore store;
  late CedictImporter importer;
  late Directory dir;

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
    importer = CedictImporter(store: store);
    dir = Directory.systemTemp.createTempSync('cedict_importer_test');
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  String writeText(String name, String text) {
    final f = File('${dir.path}/$name')..writeAsStringSync(text);
    return f.path;
  }

  Stream<ImportProgress> start(
    String path, {
    String sourceLang = 'zh',
    String targetLang = 'en',
  }) =>
      importer.import(
        ImportRequest(
          filePath: path,
          fileName: path.split(RegExp(r'[\\/]')).last,
          sourceLang: sourceLang,
          targetLang: targetLang,
        ),
        cancel: CancelToken(),
      );

  Future<ImportProgress> runImport(String path) async =>
      (await start(path).toList()).last;

  test('註解行與空行略過，檔頭 license 存進 licenseNote', () async {
    final path = writeText('c.u8', '''
# CC-CEDICT
#! version=1
#! license=Creative Commons Attribution-ShareAlike 4.0 International License
#! entries=1

學生 学生 [xue2 sheng5] /student/pupil/
''');

    final last = await runImport(path);

    // 筆數算「行數」，不是詞頭數：繁簡不同的一行算 1 筆。
    expect(last.summary!.importedCount, 1);
    expect(last.summary!.skippedCount, 0);
    final source = (await store.getSource(last.summary!.sourceId))!;
    expect(
      source.licenseNote,
      'Creative Commons Attribution-ShareAlike 4.0 International License',
    );
    expect(source.name, 'c');
    expect(source.entryCount, 1);
    // 兩個詞頭都寫進去了。
    expect((await store.lookup(source.id, '學生')).length, 1);
    expect((await store.lookup(source.id, '学生')).length, 1);
  });

  test('繁簡不同：各產生一個詞頭，共用內容', () async {
    final path = writeText('c.u8', '學生 学生 [xue2 sheng5] /student/pupil/\n');

    final id = (await runImport(path)).summary!.sourceId;

    final trad = (await store.lookup(id, '學生')).single;
    final simp = (await store.lookup(id, '学生')).single;
    expect(trad.body, 'student\npupil');
    expect(simp.body, trad.body);
    expect(trad.pronunciation, 'xue2 sheng5');
    expect(simp.pronunciation, 'xue2 sheng5');
    expect(trad.bodyKind, EntryBodyKind.plainText);
  });

  test('繁簡相同：只產生一個詞頭', () async {
    final path = writeText('c.u8', '的 的 [de5] /possessive particle/\n');
    expect((await runImport(path)).summary!.importedCount, 1);
  });

  test('釋義頭尾沒有空行', () async {
    final path = writeText('c.u8', '學生 学生 [xue2 sheng5] /student/pupil/\n');
    final id = (await runImport(path)).summary!.sourceId;
    final body = (await store.lookup(id, '學生')).single.body;
    expect(body, 'student\npupil');
    expect(body.startsWith('\n') || body.endsWith('\n'), isFalse);
  });

  test('拼音以原文存放，不轉聲調符號', () async {
    final path = writeText('c.u8', '拼音 拼音 [pin1 yin1] /pinyin/\n');
    final id = (await runImport(path)).summary!.sourceId;
    expect((await store.lookup(id, '拼音')).single.pronunciation, 'pin1 yin1');
  });

  test('交叉參照原文保留', () async {
    final path = writeText('c.u8', '同學 同学 [tong2 xue2] /see 學生|学生[xue2 sheng5]/\n');
    final id = (await runImport(path)).summary!.sourceId;
    expect(
      (await store.lookup(id, '同學')).single.body,
      'see 學生|学生[xue2 sheng5]',
    );
  });

  test('釋義內含斜線之外的特殊字元原樣保留', () async {
    final path = writeText('c.u8', '個 个 [ge4] /CL:個|个[ge4]/\n');
    final id = (await runImport(path)).summary!.sourceId;
    expect((await store.lookup(id, '個')).single.body, 'CL:個|个[ge4]');
  });

  test('壞行略過並計數', () async {
    final path = writeText('c.u8', '''
好 好 [hao3] /good/
缺方括號 缺方括號 hao3 /good/
缺結尾 缺結尾 [hao3] /good
只有一個詞
''');

    final last = await runImport(path);

    expect(last.summary!.importedCount, 1);
    expect(last.summary!.skippedCount, 3);
    expect(last.summary!.skipSamples.map((s) => s.index), [2, 3, 4]);
    expect(
      last.summary!.skipSamples.every((s) => s.reason == 'malformedLine'),
      isTrue,
    );
  });

  test('語言方向由 request 決定；readHints 預設 zh→en', () async {
    final path = writeText('c.u8', '#! license=CC\n好 好 [hao3] /good/\n');

    final last = await (start(path, sourceLang: 'zh-Hant', targetLang: 'en-US')
            .toList())
        .then((e) => e.last);
    final source = (await store.getSource(last.summary!.sourceId))!;
    expect(source.sourceLang, 'zh-Hant');
    expect(source.targetLang, 'en-US');
    expect(source.format, DictionaryFormat.cedict);

    final hints = await importer.readHints(path, 'c.u8');
    expect(hints.name, 'c');
    expect(hints.sourceLang, 'zh');
    expect(hints.targetLang, 'en');
    expect(hints.licenseNote, 'CC');
  });

  test('canHandle 吃 .u8 與 .txt', () {
    expect(importer.canHandle('cedict_ts.u8'), isTrue);
    expect(importer.canHandle('CEDICT.TXT'), isTrue);
    expect(importer.canHandle('a.json'), isFalse);
  });

  test('全部是註解的檔案丟 noValidEntries', () async {
    final path = writeText('c.u8', '# only\n#! license=CC\n');
    await expectLater(
      start(path).toList(),
      throwsA(
        isA<DictionaryImportException>()
            .having((e) => e.code, 'code', 'noValidEntries'),
      ),
    );
    expect(await store.listSources(), isEmpty);
  });

  test('重複匯入同一檔案丟 DuplicateDictionaryException', () async {
    final path = writeText('c.u8', '好 好 [hao3] /good/\n');
    await runImport(path);
    await expectLater(
      start(path).toList(),
      throwsA(isA<DuplicateDictionaryException>()),
    );
  });

  test('取消走同一條流程：解析前取消則資料庫無殘留', () async {
    final path = writeText('c.u8', '好 好 [hao3] /good/\n');
    final token = CancelToken()..cancel();

    final events = await importer
        .import(
          ImportRequest(
            filePath: path,
            fileName: 'c.u8',
            sourceLang: 'zh',
            targetLang: 'en',
          ),
          cancel: token,
        )
        .toList();

    expect(events.last.stage, ImportStage.cancelled);
    expect(await store.listSources(), isEmpty);
  });
}
