import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elinkbook/library/library_preferences.dart';
import 'package:elinkbook/library/models/library_enums.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('尚未儲存過排序方式時，loadSortBy 回傳預設值 lastRead', () async {
    final prefs = LibraryPreferences();
    expect(await prefs.loadSortBy(), LibrarySortBy.lastRead);
  });

  test('saveSortBy 寫入後，loadSortBy 讀回相同的值', () async {
    final prefs = LibraryPreferences();
    await prefs.saveSortBy(LibrarySortBy.title);
    expect(await prefs.loadSortBy(), LibrarySortBy.title);
  });

  test('尚未儲存過檢視模式時，loadViewMode 回傳預設值 grid', () async {
    final prefs = LibraryPreferences();
    expect(await prefs.loadViewMode(), LibraryViewMode.grid);
  });

  test('saveViewMode 寫入後，loadViewMode 讀回相同的值', () async {
    final prefs = LibraryPreferences();
    await prefs.saveViewMode(LibraryViewMode.list);
    expect(await prefs.loadViewMode(), LibraryViewMode.list);
  });

  test('重新建立 LibraryPreferences 實例後（模擬 App 重啟），仍讀回先前儲存的值',
      () async {
    final prefs1 = LibraryPreferences();
    await prefs1.saveViewMode(LibraryViewMode.list);
    await prefs1.saveSortBy(LibrarySortBy.author);

    final prefs2 = LibraryPreferences();
    expect(await prefs2.loadViewMode(), LibraryViewMode.list);
    expect(await prefs2.loadSortBy(), LibrarySortBy.author);
  });

  test('已儲存的排序方式字串無法對應到任何列舉值時，loadSortBy 安全回退為預設值',
      () async {
    SharedPreferences.setMockInitialValues({
      'library_sort_by': 'not_a_real_enum_value',
    });
    final prefs = LibraryPreferences();
    expect(await prefs.loadSortBy(), LibrarySortBy.lastRead);
  });

  test('已儲存的檢視模式字串無法對應到任何列舉值時，loadViewMode 安全回退為預設值',
      () async {
    SharedPreferences.setMockInitialValues({
      'library_view_mode': 'not_a_real_enum_value',
    });
    final prefs = LibraryPreferences();
    expect(await prefs.loadViewMode(), LibraryViewMode.grid);
  });
}
