import 'package:shared_preferences/shared_preferences.dart';

import 'models/library_enums.dart';

/// 圖書庫排序方式與檢視模式選擇的持久化（FR-03/FR-26）。直接使用
/// `shared_preferences` 官方支援的測試方式
/// （`SharedPreferences.setMockInitialValues`）驅動測試，不另外設計抽象介面
/// （見 docs/epics/epic-1-library/spec.md）。
class LibraryPreferences {
  static const _sortByKey = 'library_sort_by';
  static const _viewModeKey = 'library_view_mode';

  Future<LibrarySortBy> loadSortBy() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sortByKey);
    if (raw == null) return LibrarySortBy.lastRead;
    try {
      return LibrarySortBy.values.byName(raw);
    } catch (_) {
      // 儲存的字串無法對應到任何列舉值時（例如未來改了列舉名稱、或裝置上的
      // 資料被污染），byName 會拋出 ArgumentError；安全回退為預設值，避免
      // 呼叫端（LibraryScreen._initialize）未捕捉例外導致畫面卡在載入中。
      return LibrarySortBy.lastRead;
    }
  }

  Future<void> saveSortBy(LibrarySortBy sortBy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortByKey, sortBy.name);
  }

  Future<LibraryViewMode> loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_viewModeKey);
    if (raw == null) return LibraryViewMode.grid;
    try {
      return LibraryViewMode.values.byName(raw);
    } catch (_) {
      return LibraryViewMode.grid;
    }
  }

  Future<void> saveViewMode(LibraryViewMode viewMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewModeKey, viewMode.name);
  }
}
