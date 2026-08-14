import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/layout_preset.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';
import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/writing_mode.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository libraryRepository;
  late LayoutPresetRepository repository;

  setUp(() async {
    libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    repository = LayoutPresetRepository(libraryRepository.database);
  });

  tearDown(() async {
    await libraryRepository.close();
  });

  test('尚未儲存過任何預設集時，listAll 回傳空清單', () async {
    expect(await repository.listAll(), isEmpty);
  });

  test('insert 後 listAll 可讀回，id 由資料庫自動指派', () async {
    await repository.insert(LayoutPreset(
      id: null,
      name: '臥室夜讀直排',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: const BookReaderPrefs(
        fontSize: 18,
        writingModeOverride: WritingMode.vertical,
      ),
    ));

    final all = await repository.listAll();
    expect(all, hasLength(1));
    expect(all.single.id, isNotNull);
    expect(all.single.name, '臥室夜讀直排');
    expect(all.single.prefs.fontSize, 18);
    expect(all.single.prefs.writingModeOverride, WritingMode.vertical);
  });

  test('insert 三組後，listAll 依 id ASC（插入順序）排序', () async {
    for (final name in ['第一組', '第二組', '第三組']) {
      await repository.insert(LayoutPreset(
        id: null,
        name: name,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        prefs: BookReaderPrefs.empty,
      ));
    }

    final all = await repository.listAll();
    expect(all.map((p) => p.name).toList(), ['第一組', '第二組', '第三組']);
  });

  test('replace 後，id／createdAt 不變，updatedAt 更新，name／prefs 覆蓋為新值', () async {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(1000);
    await repository.insert(LayoutPreset(
      id: null,
      name: '舊名稱',
      createdAt: createdAt,
      updatedAt: createdAt,
      prefs: const BookReaderPrefs(fontSize: 16),
    ));
    final original = (await repository.listAll()).single;

    await repository.replace(
      original.id!,
      LayoutPreset(
        id: original.id,
        name: '新名稱',
        createdAt: createdAt,
        updatedAt: createdAt, // 呼叫端傳入的 updatedAt 應被忽略，repository 一律用當下時間。
        prefs: const BookReaderPrefs(fontSize: 20),
      ),
    );

    final updated = (await repository.listAll()).single;
    expect(updated.id, original.id);
    expect(updated.name, '新名稱');
    expect(updated.prefs.fontSize, 20);
    expect(updated.createdAt, original.createdAt);
    expect(updated.updatedAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(original.updatedAt.millisecondsSinceEpoch));
  });

  test('delete 後該筆從 listAll 消失，其餘不受影響', () async {
    await repository.insert(LayoutPreset(
      id: null,
      name: '保留組',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    ));
    await repository.insert(LayoutPreset(
      id: null,
      name: '刪除組',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: BookReaderPrefs.empty,
    ));
    final toDelete =
        (await repository.listAll()).firstWhere((p) => p.name == '刪除組');

    await repository.delete(toDelete.id!);

    final remaining = await repository.listAll();
    expect(remaining, hasLength(1));
    expect(remaining.single.name, '保留組');
  });

  test('prefs_json 的 JSON 序列化往返正確保留欄位值（含 enum／double／bool）', () async {
    const prefs = BookReaderPrefs(
      fontFamily: 'TaiwanPearl',
      fontSize: 18.5,
      letterSpacing: 0.1,
      writingModeOverride: WritingMode.vertical,
      publisherStyles: false,
    );
    await repository.insert(LayoutPreset(
      id: null,
      name: '完整欄位測試',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: prefs,
    ));

    final restored = (await repository.listAll()).single.prefs;
    expect(restored, prefs);
  });

  test('即使 prefs 含未過濾的 PDF/雙頁欄位，JSON 往返仍不遺失資料（過濾責任在寫入端 reflowableEpubFields()，repository 本身不做過濾）',
      () async {
    const prefs = BookReaderPrefs(
      pdfFitMode: PdfFitMode.fitWidth,
      pdfContrast: 15,
      dualPageMode: DualPageMode.always,
    );
    await repository.insert(LayoutPreset(
      id: null,
      name: 'PDF 測試',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      prefs: prefs,
    ));

    final restored = (await repository.listAll()).single.prefs;
    expect(restored.pdfFitMode, PdfFitMode.fitWidth);
    expect(restored.pdfContrast, 15);
    expect(restored.dualPageMode, DualPageMode.always);
  });
}
