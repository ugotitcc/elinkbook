import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/library_repository.dart';

Book _book(
  String id, {
  String title = '書名',
  String? author,
  BookFileFormat format = BookFileFormat.epub,
  double progress = 0,
  String groupName = '未分類',
  int createTime = 1000,
  int lastReadTime = 1000,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: format,
    filePath: 'content://example/$id',
    source: BookSource.local,
    progress: progress,
    groupName: groupName,
    createTime: DateTime.fromMillisecondsSinceEpoch(createTime),
    lastReadTime: DateTime.fromMillisecondsSinceEpoch(lastReadTime),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SqliteLibraryRepository repository;

  setUp(() async {
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
  });

  tearDown(() async {
    await repository.close();
  });

  test('insertBook 後可用 listBooks 取回', () async {
    await repository.insertBook(_book('b1', title: '紅樓夢'));

    final books = await repository.listBooks();

    expect(books, hasLength(1));
    expect(books.single.title, '紅樓夢');
  });

  test('updateBook 更新既有書籍的欄位', () async {
    await repository.insertBook(_book('b1', title: '舊書名'));

    await repository.updateBook(_book('b1', title: '新書名'));

    final books = await repository.listBooks();
    expect(books.single.title, '新書名');
  });

  test('deleteBook 移除指定書籍', () async {
    await repository.insertBook(_book('b1'));
    await repository.insertBook(_book('b2'));

    await repository.deleteBook('b1');

    final books = await repository.listBooks();
    expect(books.map((b) => b.id), ['b2']);
  });

  group('listBooks 排序', () {
    setUp(() async {
      await repository.insertBook(_book(
        'b1',
        title: '西遊記',
        author: '吳承恩',
        createTime: 3000,
        lastReadTime: 1000,
      ));
      await repository.insertBook(_book(
        'b2',
        title: '三國演義',
        author: '羅貫中',
        createTime: 1000,
        lastReadTime: 3000,
      ));
      await repository.insertBook(_book(
        'b3',
        title: '水滸傳',
        author: '施耐庵',
        createTime: 2000,
        lastReadTime: 2000,
      ));
    });

    test('lastRead：最近閱讀優先', () async {
      final books = await repository.listBooks(sortBy: LibrarySortBy.lastRead);
      expect(books.map((b) => b.id).toList(), ['b2', 'b3', 'b1']);
    });

    test('createTime：最近建立優先', () async {
      final books =
          await repository.listBooks(sortBy: LibrarySortBy.createTime);
      expect(books.map((b) => b.id).toList(), ['b1', 'b3', 'b2']);
    });

    test('author：依作者排序', () async {
      final books = await repository.listBooks(sortBy: LibrarySortBy.author);
      expect(books.map((b) => b.author).toList(), ['吳承恩', '施耐庵', '羅貫中']);
    });

    test('title：依書名排序', () async {
      final books = await repository.listBooks(sortBy: LibrarySortBy.title);
      expect(books.map((b) => b.title).toList(), ['三國演義', '水滸傳', '西遊記']);
    });
  });

  test('listBooks 依 groupFilter 篩選', () async {
    await repository.insertBook(_book('b1', groupName: '經典名著'));
    await repository.insertBook(_book('b2', groupName: '古典奇幻'));

    final books = await repository.listBooks(groupFilter: '經典名著');

    expect(books.map((b) => b.id).toList(), ['b1']);
  });

  test('listBooks 不指定 groupFilter 時回傳全部', () async {
    await repository.insertBook(_book('b1', groupName: '經典名著'));
    await repository.insertBook(_book('b2', groupName: '古典奇幻'));

    final books = await repository.listBooks();

    expect(books, hasLength(2));
  });

  group('群組管理', () {
    test('upsertGroup 新增群組後出現在 listGroups', () async {
      await repository.upsertGroup('古典奇幻');

      final groups = await repository.listGroups();

      expect(groups.map((g) => g.name), containsAll(['未分類', '古典奇幻']));
    });

    test('upsertGroup 對已存在的名稱不重複新增', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.upsertGroup('古典奇幻');

      final groups = await repository.listGroups();

      expect(groups.where((g) => g.name == '古典奇幻'), hasLength(1));
    });

    test('deleteGroup 後，該群組下書籍改歸「未分類」', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.insertBook(_book('b1', groupName: '古典奇幻'));

      await repository.deleteGroup('古典奇幻');

      final books = await repository.listBooks();
      expect(books.single.groupName, '未分類');
      final groups = await repository.listGroups();
      expect(groups.map((g) => g.name), isNot(contains('古典奇幻')));
    });

    test('deleteGroup 對「未分類」拋出例外', () async {
      expect(
        () => repository.deleteGroup('未分類'),
        throwsA(isA<LibraryRepositoryException>()),
      );
    });

    test('renameGroup 成功後，書籍歸屬同步更新為新名稱', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.insertBook(_book('b1', groupName: '古典奇幻'));

      await repository.renameGroup('古典奇幻', '奇幻小說');

      final books = await repository.listBooks();
      expect(books.single.groupName, '奇幻小說');
      final groups = await repository.listGroups();
      expect(groups.map((g) => g.name), contains('奇幻小說'));
      expect(groups.map((g) => g.name), isNot(contains('古典奇幻')));
    });

    test('renameGroup 對「未分類」拋出例外', () async {
      expect(
        () => repository.renameGroup('未分類', '新名稱'),
        throwsA(isA<LibraryRepositoryException>()),
      );
    });

    test('renameGroup 目標名稱已存在時拋出例外', () async {
      await repository.upsertGroup('古典奇幻');
      await repository.upsertGroup('文言經典');

      expect(
        () => repository.renameGroup('古典奇幻', '文言經典'),
        throwsA(isA<LibraryRepositoryException>()),
      );
    });
  });

  group('book_reader_prefs schema', () {
    test('新安裝資料庫已包含 book_reader_prefs 表，且外鍵約束會在刪除書籍時連動清除',
        () async {
      await repository.insertBook(_book('b1'));
      await repository.database.insert('book_reader_prefs', {
        'book_id': 'b1',
        'font_size': 18.0,
      });

      await repository.deleteBook('b1');

      final rows = await repository.database.query(
        'book_reader_prefs',
        where: 'book_id = ?',
        whereArgs: ['b1'],
      );
      expect(rows, isEmpty);
    });
  });
}
