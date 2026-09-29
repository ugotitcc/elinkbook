import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/custom_fonts_repository.dart';

Book _book(String id) {
  return Book(
    id: id,
    title: '書名 $id',
    format: BookFileFormat.epub,
    filePath: 'content://example/$id',
    source: BookSource.local,
    progress: 0,
    groupName: '未分類',
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('CustomFont.toMap／fromMap round-trip 保留所有欄位', () {
    const font = CustomFont(
      id: 1,
      displayName: '我的字型',
      familyName: 'MyFamily',
      fontUri: 'content://example/font1',
    );
    final map = font.toMap();
    expect(map['display_name'], '我的字型');
    expect(map['family_name'], 'MyFamily');
    expect(map['font_uri'], 'content://example/font1');
    expect(map.containsKey('id'), isFalse); // 新增用 toMap 刻意不含 id，交由 AUTOINCREMENT 指派

    final restoredMap = {'id': 1, ...map};
    final restored = CustomFont.fromMap(restoredMap);
    expect(restored, font);
  });

  group('CustomFontsRepository', () {
    late SqliteLibraryRepository libraryRepository;
    late CustomFontsRepository repository;

    setUp(() async {
      libraryRepository =
          await SqliteLibraryRepository.open(inMemoryDatabasePath);
      repository = CustomFontsRepository(libraryRepository.database);
    });

    tearDown(() async {
      await libraryRepository.close();
    });

    test('insert 後 listAll 依 displayName 排序回傳', () async {
      await repository.insert(const CustomFont(
        displayName: 'Zeta 字型',
        familyName: 'ZetaFamily',
        fontUri: 'content://example/zeta',
      ));
      await repository.insert(const CustomFont(
        displayName: 'Alpha 字型',
        familyName: 'AlphaFamily',
        fontUri: 'content://example/alpha',
      ));

      final all = await repository.listAll();
      expect(all.map((f) => f.displayName).toList(),
          ['Alpha 字型', 'Zeta 字型']);
      expect(all.every((f) => f.id != null), isTrue);
    });

    test('familyNameExists 正確反映是否已存在', () async {
      expect(await repository.familyNameExists('SomeFamily'), isFalse);
      await repository.insert(const CustomFont(
        displayName: 'X',
        familyName: 'SomeFamily',
        fontUri: 'content://example/x',
      ));
      expect(await repository.familyNameExists('SomeFamily'), isTrue);
    });

    test('相同 family_name 重複 insert 拋出例外（UNIQUE 約束）', () async {
      await repository.insert(const CustomFont(
        displayName: 'A',
        familyName: 'DupFamily',
        fontUri: 'content://example/a',
      ));
      expect(
        () => repository.insert(const CustomFont(
          displayName: 'B',
          familyName: 'DupFamily',
          fontUri: 'content://example/b',
        )),
        throwsA(anything),
      );
    });

    test('rename 只更新 displayName，familyName／fontUri 不變', () async {
      final id = await repository.insert(const CustomFont(
        displayName: '舊名稱',
        familyName: 'RenameFamily',
        fontUri: 'content://example/r',
      ));

      await repository.rename(id, '新名稱');

      final all = await repository.listAll();
      final renamed = all.single;
      expect(renamed.displayName, '新名稱');
      expect(renamed.familyName, 'RenameFamily');
      expect(renamed.fontUri, 'content://example/r');
    });

    test('updateUri 只更新指定字型的 URI，顯示名稱與家族名稱不變，其他字型不受影響', () async {
      final targetId = await repository.insert(const CustomFont(
        displayName: '目標字型',
        familyName: 'TargetFamily',
        fontUri: 'content://old/target',
      ));
      await repository.insert(const CustomFont(
        displayName: '其他字型',
        familyName: 'OtherFamily',
        fontUri: 'content://old/other',
      ));

      await repository.updateUri(targetId, 'content://new/target');

      final all = await repository.listAll();
      final target = all.firstWhere((f) => f.id == targetId);
      expect(target.fontUri, 'content://new/target');
      expect(target.displayName, '目標字型');
      expect(target.familyName, 'TargetFamily');
      final other = all.firstWhere((f) => f.id != targetId);
      expect(other.fontUri, 'content://old/other');
    });

    test('countBooksUsing 正確統計 book_reader_prefs 使用中筆數', () async {
      await libraryRepository.insertBook(_book('b1'));
      await libraryRepository.insertBook(_book('b2'));
      await libraryRepository.insertBook(_book('b3'));
      final db = libraryRepository.database;
      await db.insert('book_reader_prefs',
          {'book_id': 'b1', 'font_family': 'UsedFamily'});
      await db.insert('book_reader_prefs',
          {'book_id': 'b2', 'font_family': 'UsedFamily'});
      await db.insert(
          'book_reader_prefs', {'book_id': 'b3', 'font_family': 'Other'});

      expect(await repository.countBooksUsing('UsedFamily'), 2);
      expect(await repository.countBooksUsing('Other'), 1);
      expect(await repository.countBooksUsing('Unused'), 0);
    });

    test('deleteAndResetUsage 於同一交易內刪除字型並把使用中書籍重置為 NULL',
        () async {
      await libraryRepository.insertBook(_book('b1'));
      await libraryRepository.insertBook(_book('b2'));
      final db = libraryRepository.database;
      await db.insert('book_reader_prefs',
          {'book_id': 'b1', 'font_family': 'ToDeleteFamily'});
      await db.insert('book_reader_prefs',
          {'book_id': 'b2', 'font_family': 'KeepFamily'});
      final id = await repository.insert(const CustomFont(
        displayName: '待刪除字型',
        familyName: 'ToDeleteFamily',
        fontUri: 'content://example/del',
      ));

      await repository.deleteAndResetUsage(id, 'ToDeleteFamily');

      expect(await repository.listAll(), isEmpty);
      final row1 = (await db.query('book_reader_prefs',
              where: 'book_id = ?', whereArgs: ['b1']))
          .single;
      expect(row1['font_family'], isNull);
      final row2 = (await db.query('book_reader_prefs',
              where: 'book_id = ?', whereArgs: ['b2']))
          .single;
      expect(row2['font_family'], 'KeepFamily'); // 不相關的書籍不受影響
    });
  });
}
