import 'package:flutter/foundation.dart';

import '../library/library_preferences.dart';
import '../library/library_repository.dart';
import '../library/models/book.dart';
import '../library/models/book_group.dart';
import '../library/models/library_enums.dart';

/// 收斂 `LibraryScreen` 的書籍清單狀態機（epic-26-architecture-hardening
/// Issue 8，候選 2）：書籍載入／分類清單載入／排序切換與其非同步競態防護
/// （避免較晚回應但較早發出的查詢結果覆蓋畫面），從 `_LibraryScreenState`
/// 抽出成獨立、可脫離 widget 樹直接單元測試的 [ChangeNotifier]。
///
/// `LibraryScreen` 在 `initState()` 建立本控制器並 `addListener()` 觸發
/// `setState()`，在 `dispose()` 時呼叫 [dispose]；本類別不需要
/// `if (!mounted) return;` 這類 guard——改用內部 [_disposed] 旗標達成相同
/// 效果（`notifyListeners()` 在 dispose 後呼叫會拋出例外，見
/// `ChangeNotifier` 官方文件）。
///
/// [groupFilter] 對應 `LibraryScreen.groupFilter`，於建構時決定、之後不再
/// 變動（比照原本 `_groupFilter` 欄位「只在 initState 賦值一次、此後從未
/// 再寫入」的既有行為，改為 `final` 更精確表達這個不變量，見
/// `plans/plan-issue-8.md`「規劃階段查證」第 10 點）。
class LibraryBookListController extends ChangeNotifier {
  LibraryBookListController({
    required this.repository,
    this.groupFilter,
  });

  final LibraryRepository repository;
  final String? groupFilter;
  final _preferences = LibraryPreferences();

  bool _disposed = false;

  List<Book>? books;
  List<BookGroup> groups = const [];
  LibrarySortBy sortBy = LibrarySortBy.lastRead;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 啟動時的初始載入：先讀取持久化的排序偏好，再平行載入分類清單與書籍
  /// 清單。對應原 `_LibraryScreenState._initialize()` 中「讀 `_sortBy`」與
  /// `Future.wait([_loadGroups(), _loadBooks()])` 兩段（`_viewMode` 讀取
  /// 不屬於書籍清單狀態機，留在 `_LibraryScreenState` 自行處理，見
  /// `plans/plan-issue-8.md`「規劃階段查證」第 6、9 點）。
  Future<void> initialLoad() async {
    sortBy = await _preferences.loadSortBy();
    if (_disposed) return;
    notifyListeners();
    await Future.wait([loadGroups(), loadBooks()]);
  }

  Future<void> loadGroups() async {
    try {
      final loaded = await repository.listGroups();
      if (_disposed) return;
      groups = loaded;
      notifyListeners();
    } catch (_) {
      // 暫時性錯誤時保留先前已載入的群組清單，避免因為單次讀取失敗就讓
      // 畫面的分類 tab 列與目前的篩選狀態不一致（見 Issue 7 審查）。若是
      // 第一次載入就失敗，groups 會維持初始的空清單（連「未分類」都不
      // 顯示）——這是「沒有最後已知正確狀態可保留」下的必然結果，安全但
      // 不完美，之後重新整理即可恢復。
    }
  }

  Future<void> loadBooks() async {
    // 擷取呼叫當下的排序條件；若呼叫端在這次非同步查詢完成前又切換了
    // 排序，較晚回應但較早發出的查詢結果會對應到舊條件，此時不應覆蓋
    // 畫面（避免顯示內容與目前選定的條件不一致）。`groupFilter` 為
    // `final`，理論上不會變動，仍保留比對以維持與原本邏輯逐行對應（見
    // `plans/plan-issue-8.md`「規劃階段查證」第 10 點）。
    final requestedSortBy = sortBy;
    final requestedGroupFilter = groupFilter;
    try {
      final loaded = await repository.listBooks(
        sortBy: requestedSortBy,
        groupFilter: requestedGroupFilter,
      );
      if (_disposed) return;
      if (sortBy != requestedSortBy || groupFilter != requestedGroupFilter) {
        return;
      }
      books = loaded;
      notifyListeners();
    } catch (_) {
      // 如果載入失敗，把它當作空列表，顯示既有的空狀態 UI
      if (_disposed) return;
      if (sortBy != requestedSortBy || groupFilter != requestedGroupFilter) {
        return;
      }
      books = [];
      notifyListeners();
    }
  }

  /// 切換排序方式：更新狀態並通知、持久化使用者選擇，再重新載入書籍清單
  /// （對應原 `_LibraryScreenState._changeSortBy()`）。
  Future<void> changeSortBy(LibrarySortBy newSortBy) async {
    sortBy = newSortBy;
    if (_disposed) return;
    notifyListeners();
    await _preferences.saveSortBy(newSortBy);
    await loadBooks();
  }
}
