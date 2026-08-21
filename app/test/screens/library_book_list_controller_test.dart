import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/book_group.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/screens/library_book_list_controller.dart';

import '../support/fake_library_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'initialLoad() 依序載入持久化排序偏好、分類清單與書籍清單，並依載入結果排序',
      () async {
    SharedPreferences.setMockInitialValues({'library_sort_by': 'title'});
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', title: 'B'),
      _book(id: '2', title: 'A'),
    ]);
    final controller = LibraryBookListController(repository: repository);
    addTearDown(controller.dispose);

    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    await controller.initialLoad();

    expect(controller.sortBy, LibrarySortBy.title);
    expect(controller.books?.map((b) => b.id).toList(), ['2', '1']);
    expect(controller.groups, isNotEmpty);
    expect(notifyCount, greaterThan(0));
  });

  test('loadGroups() 成功時更新 groups', () async {
    final repository = FakeLibraryRepository(
      initialBooks: [_book(id: '1', groupName: '奇幻')],
    );
    final controller = LibraryBookListController(repository: repository);
    addTearDown(controller.dispose);

    await controller.loadGroups();

    expect(controller.groups.map((g) => g.name), contains('奇幻'));
  });

  test('loadGroups() 失敗時保留先前已載入的群組清單，不拋出例外', () async {
    final repository = FakeLibraryRepository(
      initialBooks: [_book(id: '1', groupName: '奇幻')],
    );
    final controller = LibraryBookListController(repository: repository);
    addTearDown(controller.dispose);
    await controller.loadGroups();
    final before = controller.groups;

    final throwingController = LibraryBookListController(
      repository: _ThrowingListGroupsRepository(),
    )..groups = before;
    addTearDown(throwingController.dispose);

    await throwingController.loadGroups();

    expect(throwingController.groups, same(before));
  });

  test('loadBooks() 成功時依目前 sortBy／groupFilter 更新 books', () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', groupName: '奇幻'),
      _book(id: '2', groupName: '未分類'),
    ]);
    final controller = LibraryBookListController(
      repository: repository,
      groupFilter: '奇幻',
    );
    addTearDown(controller.dispose);

    await controller.loadBooks();

    expect(controller.books?.map((b) => b.id).toList(), ['1']);
  });

  test('loadBooks() 失敗時降級為空清單，不拋出例外', () async {
    final repository = FakeLibraryRepository(throwOnListBooks: true);
    final controller = LibraryBookListController(repository: repository);
    addTearDown(controller.dispose);

    await controller.loadBooks();

    expect(controller.books, isEmpty);
  });

  test('changeSortBy() 更新 sortBy、持久化選擇、並重新載入書籍清單', () async {
    final repository = FakeLibraryRepository(initialBooks: [
      _book(id: '1', title: 'B'),
      _book(id: '2', title: 'A'),
    ]);
    final controller = LibraryBookListController(repository: repository);
    addTearDown(controller.dispose);

    await controller.changeSortBy(LibrarySortBy.title);

    expect(controller.sortBy, LibrarySortBy.title);
    expect(controller.books?.map((b) => b.id).toList(), ['2', '1']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('library_sort_by'), 'title');
  });

  test('dispose() 後呼叫 loadBooks()／loadGroups() 不再觸發 notifyListeners()、不拋出例外',
      () async {
    final repository = FakeLibraryRepository();
    final controller = LibraryBookListController(repository: repository);
    controller.dispose();

    await controller.loadBooks();
    await controller.loadGroups();
  });
}

Book _book({
  required String id,
  String title = '測試書',
  String groupName = BookGroup.uncategorized,
}) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: title,
    author: null,
    format: BookFileFormat.epub,
    filePath: 'content://example/$id.epub',
    source: BookSource.local,
    coverPath: null,
    groupName: groupName,
    createTime: now,
    lastReadTime: now,
  );
}

/// 供「loadGroups() 失敗時保留先前清單」測試使用，只覆寫 listGroups() 一個
/// 方法使其拋出例外，其餘行為原樣繼承 FakeLibraryRepository（比照
/// `test/support/fake_remote_server_repository.dart` 系列既有「刻意可變
/// 錯誤模擬旗標」慣例，但此處只有單一測試需要、不下放到共用 fake 檔案，
/// 改用區域子類別)。
class _ThrowingListGroupsRepository extends FakeLibraryRepository {
  @override
  Future<List<BookGroup>> listGroups() async {
    throw Exception('模擬資料庫錯誤');
  }
}
