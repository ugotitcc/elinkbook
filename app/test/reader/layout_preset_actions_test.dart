import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs.dart';
import 'package:elinkbook/reader/layout_preset.dart';
import 'package:elinkbook/reader/layout_preset_actions.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('layoutPresetTargetsCurrentBookOnly', () {
    test('targetBookIds 恰為 [currentBookId] 時回傳 true', () {
      expect(layoutPresetTargetsCurrentBookOnly(['b1'], 'b1'), isTrue);
    });

    test('targetBookIds 有多本書時回傳 false（即使包含 currentBookId）', () {
      expect(layoutPresetTargetsCurrentBookOnly(['b1', 'b2'], 'b1'), isFalse);
    });

    test('targetBookIds 恰有 1 本但不是 currentBookId 時回傳 false', () {
      expect(layoutPresetTargetsCurrentBookOnly(['b2'], 'b1'), isFalse);
    });

    test('targetBookIds 為空清單時回傳 false', () {
      expect(layoutPresetTargetsCurrentBookOnly([], 'b1'), isFalse);
    });
  });

  group('insertNewLayoutPreset', () {
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

    test('insert 後回傳的清單包含新預設集，且已由資料庫指派 id', () async {
      final updated = await insertNewLayoutPreset(
        repository,
        name: '臥室夜讀直排',
        prefs: const BookReaderPrefs(fontSize: 18),
      );

      expect(updated, hasLength(1));
      expect(updated.single.id, isNotNull);
      expect(updated.single.name, '臥室夜讀直排');
      expect(updated.single.prefs.fontSize, 18);
    });

    test('回傳的清單反映目前完整內容，依插入順序排列', () async {
      await insertNewLayoutPreset(
        repository,
        name: '第一組',
        prefs: BookReaderPrefs.empty,
      );

      final updated = await insertNewLayoutPreset(
        repository,
        name: '第二組',
        prefs: BookReaderPrefs.empty,
      );

      expect(updated.map((p) => p.name).toList(), ['第一組', '第二組']);
    });
  });

  group('overwriteLayoutPreset', () {
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

    test('覆蓋後 id／createdAt 不變，name／prefs 更新為新值', () async {
      final createdAt = DateTime.fromMillisecondsSinceEpoch(1000);
      await repository.insert(LayoutPreset(
        id: null,
        name: '舊名稱',
        createdAt: createdAt,
        updatedAt: createdAt,
        prefs: const BookReaderPrefs(fontSize: 16),
      ));
      final target = (await repository.listAll()).single;

      final updated = await overwriteLayoutPreset(
        repository,
        target: target,
        name: '新名稱',
        prefs: const BookReaderPrefs(fontSize: 20),
      );

      expect(updated, hasLength(1));
      expect(updated.single.id, target.id);
      expect(updated.single.name, '新名稱');
      expect(updated.single.prefs.fontSize, 20);
      expect(updated.single.createdAt, target.createdAt);
    });

    test('target.id 為 null（未持久化的暫存物件）時觸發 assert', () async {
      final target = LayoutPreset(
        id: null,
        name: '暫存',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        prefs: BookReaderPrefs.empty,
      );

      expect(
        () => overwriteLayoutPreset(
          repository,
          target: target,
          name: '新名稱',
          prefs: BookReaderPrefs.empty,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
