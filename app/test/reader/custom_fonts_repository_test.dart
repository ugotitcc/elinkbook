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

    test('countBooksUsing 只有標題字型使用該字型的書也會計入（epic-68 Issue 4）',
        () async {
      await libraryRepository.insertBook(_book('b1'));
      await libraryRepository.insertBook(_book('b2'));
      final db = libraryRepository.database;
      await db.insert('book_reader_prefs', {
        'book_id': 'b1',
        'font_family': 'OtherFamily',
        'heading_font_family': 'TargetFamily',
      });
      await db.insert('book_reader_prefs', {
        'book_id': 'b2',
        'font_family': null,
        'heading_font_family': 'TargetFamily',
      });

      expect(await repository.countBooksUsing('TargetFamily'), 2);
      // 主字型端仍可正確計數
      expect(await repository.countBooksUsing('OtherFamily'), 1);
    });

    test('countBooksUsing 同一本書主字型與標題字型都用該字型只算一次（epic-68 Issue 4）',
        () async {
      for (final id in ['b1', 'b2', 'b3', 'b4', 'b5']) {
        await libraryRepository.insertBook(_book(id));
      }
      final db = libraryRepository.database;
      // b1：兩欄皆用；b2：只主字型；b3：只標題字型（共 3 本）
      await db.insert('book_reader_prefs', {
        'book_id': 'b1',
        'font_family': 'TargetFamily',
        'heading_font_family': 'TargetFamily',
      });
      await db.insert('book_reader_prefs',
          {'book_id': 'b2', 'font_family': 'TargetFamily'});
      await db.insert('book_reader_prefs',
          {'book_id': 'b3', 'heading_font_family': 'TargetFamily'});
      // b4、b5：無關
      await db.insert('book_reader_prefs', {
        'book_id': 'b4',
        'font_family': 'OtherFamily',
        'heading_font_family': 'OtherFamily',
      });
      await db.insert('book_reader_prefs', {'book_id': 'b5'});

      // 以列為單位計數：是 3 而不是 4
      expect(await repository.countBooksUsing('TargetFamily'), 3);
    });

    test('countBooksUsing 沒有任何書使用時回傳 0，且標題字型為 NULL 的列不被誤算（epic-68 Issue 4）',
        () async {
      await libraryRepository.insertBook(_book('b1'));
      final db = libraryRepository.database;
      await db.insert('book_reader_prefs', {
        'book_id': 'b1',
        'font_family': null,
        'heading_font_family': null,
      });

      expect(await repository.countBooksUsing('TargetFamily'), 0);
    });

    // 取得單一書籍的偏好列（epic-68 Issue 4 刪除連動測試共用）
    Future<Map<String, Object?>> prefsRow(String bookId) async {
      return (await libraryRepository.database.query('book_reader_prefs',
              where: 'book_id = ?', whereArgs: [bookId]))
          .single;
    }

    Future<int> insertTargetFont() {
      return repository.insert(const CustomFont(
        displayName: '目標字型',
        familyName: 'TargetFamily',
        fontUri: 'content://example/target',
      ));
    }

    test('刪除字型時，標題字型用該字型而主字型用另一字型 → 只清標題字型，主字型保留（epic-68 Issue 4）',
        () async {
      await libraryRepository.insertBook(_book('b1'));
      await libraryRepository.database.insert('book_reader_prefs', {
        'book_id': 'b1',
        'font_family': 'OtherFamily',
        'heading_font_family': 'TargetFamily',
      });
      final id = await insertTargetFont();

      await repository.deleteAndResetUsage(id, 'TargetFamily');

      final row = await prefsRow('b1');
      expect(row['font_family'], 'OtherFamily');
      expect(row['heading_font_family'], isNull);
    });

    test('刪除字型時，主字型用該字型而標題字型用另一字型 → 只清主字型，標題字型保留（epic-68 Issue 4）',
        () async {
      await libraryRepository.insertBook(_book('b1'));
      await libraryRepository.database.insert('book_reader_prefs', {
        'book_id': 'b1',
        'font_family': 'TargetFamily',
        'heading_font_family': 'OtherFamily',
      });
      final id = await insertTargetFont();

      await repository.deleteAndResetUsage(id, 'TargetFamily');

      final row = await prefsRow('b1');
      expect(row['font_family'], isNull);
      expect(row['heading_font_family'], 'OtherFamily');
    });

    test('刪除字型時，主字型與標題字型都用該字型 → 兩欄同時清為 NULL（epic-68 Issue 4）',
        () async {
      await libraryRepository.insertBook(_book('b1'));
      await libraryRepository.database.insert('book_reader_prefs', {
        'book_id': 'b1',
        'font_family': 'TargetFamily',
        'heading_font_family': 'TargetFamily',
      });
      final id = await insertTargetFont();

      await repository.deleteAndResetUsage(id, 'TargetFamily');

      final row = await prefsRow('b1');
      expect(row['font_family'], isNull);
      expect(row['heading_font_family'], isNull);
    });

    test('刪除字型連動：多本書混合情境，無關書與其他欄位不受影響（epic-68 Issue 4）',
        () async {
      for (final id in ['b1', 'b2', 'b3', 'b4']) {
        await libraryRepository.insertBook(_book(id));
      }
      final db = libraryRepository.database;
      await db.insert('book_reader_prefs',
          {'book_id': 'b1', 'heading_font_family': 'TargetFamily'});
      await db.insert('book_reader_prefs',
          {'book_id': 'b2', 'font_family': 'TargetFamily'});
      await db.insert('book_reader_prefs', {
        'book_id': 'b3',
        'font_family': 'KeepFamily',
        'heading_font_family': 'KeepFamily',
      });
      await db.insert('book_reader_prefs', {
        'book_id': 'b4',
        'font_family': 'OtherFamily',
        'heading_font_family': 'TargetFamily',
        'font_size': 1.25,
      });
      final id = await insertTargetFont();

      await repository.deleteAndResetUsage(id, 'TargetFamily');

      expect((await prefsRow('b1'))['heading_font_family'], isNull);
      expect((await prefsRow('b2'))['font_family'], isNull);
      final b3 = await prefsRow('b3');
      expect(b3['font_family'], 'KeepFamily');
      expect(b3['heading_font_family'], 'KeepFamily');
      final b4 = await prefsRow('b4');
      expect(b4['heading_font_family'], isNull);
      expect(b4['font_family'], 'OtherFamily');
      expect(b4['font_size'], 1.25); // 其他欄位不變
      expect(await repository.listAll(), isEmpty); // 字型已刪
    });

    test('刪除字型後 countBooksUsing 回傳 0（計數與重置口徑一致，epic-68 Issue 4）',
        () async {
      for (final id in ['b1', 'b2', 'b3']) {
        await libraryRepository.insertBook(_book(id));
      }
      final db = libraryRepository.database;
      await db.insert('book_reader_prefs',
          {'book_id': 'b1', 'heading_font_family': 'TargetFamily'});
      await db.insert('book_reader_prefs',
          {'book_id': 'b2', 'font_family': 'TargetFamily'});
      await db.insert('book_reader_prefs', {
        'book_id': 'b3',
        'font_family': 'TargetFamily',
        'heading_font_family': 'TargetFamily',
      });
      final id = await insertTargetFont();
      expect(await repository.countBooksUsing('TargetFamily'), 3);

      await repository.deleteAndResetUsage(id, 'TargetFamily');

      expect(await repository.countBooksUsing('TargetFamily'), 0);
    });
  });
}
