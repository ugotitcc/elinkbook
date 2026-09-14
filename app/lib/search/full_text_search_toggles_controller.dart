// app/lib/search/full_text_search_toggles_controller.dart
import 'full_text_search_settings_repository.dart';

/// 收斂「啟用全文檢索」兩個分類（PDF／其他格式）開關的讀取與切換邏輯
/// （epic-41-search-architecture-hardening Issue 5）：`library_search_screen.dart`
/// 的 `_FullTextSearchQuickSettingsPanel` 與 `settings_scaffold.dart` 的
/// `SettingsScaffold` 原本逐行重複實作同一套「呼叫 isEnabled() 兩次填兩個
/// 布林值」＋「切換前彈確認 Dialog、確認後呼叫 setEnabled 再更新畫面」邏輯，
/// 收斂成這個純資料物件。
///
/// 刻意**不繼承** `ChangeNotifier`——確認 Dialog 的彈出/取消判斷需要
/// `BuildContext`，維持在各自 Widget 層呼叫 [toggle] 前處理；兩個呼叫端在
/// `await controller.toggle(...)` 後自行 `setState(() {})` 刷新畫面，比引入
/// `ChangeNotifier`／`AnimatedBuilder` 更貼合既有兩個 `StatefulWidget` 的
/// 既有寫法（`reviews/review-epic-and-issues.md` M-2 已定案）。
class FullTextSearchTogglesController {
  FullTextSearchTogglesController(this._repository);

  final FullTextSearchSettingsRepository? _repository;

  bool _pdfEnabled = false;
  bool _foliateEnabled = false;

  /// 唯讀——只能透過 [toggle] 變更，避免呼叫端略過 `repository.setEnabled()`
  /// 直接賦值，導致記憶體狀態與持久化儲存不同步。
  bool get pdfEnabled => _pdfEnabled;
  bool get foliateEnabled => _foliateEnabled;

  /// 從 repository 讀回兩個分類目前的啟用狀態。[_repository] 為 `null`
  /// （呼叫端尚未組裝完成，或測試替身刻意留空）時直接 no-op，
  /// [pdfEnabled]／[foliateEnabled] 維持預設值 `false`，不拋例外。
  Future<void> load() async {
    final repository = _repository;
    if (repository == null) return;
    _pdfEnabled = await repository.isEnabled(ContentIndexCategory.pdf);
    _foliateEnabled =
        await repository.isEnabled(ContentIndexCategory.foliate);
  }

  /// 切換 [category] 的啟用狀態為 [newValue]：呼叫 `repository.setEnabled()`
  /// 並更新對應的內部布林值。**不**負責彈出確認對話框——呼叫端須自行在
  /// 「從關閉切成開啟」時先詢問使用者確認，確認後才呼叫本方法。
  /// [_repository] 為 `null` 時直接 no-op，不拋例外。
  Future<void> toggle(ContentIndexCategory category, bool newValue) async {
    final repository = _repository;
    if (repository == null) return;
    await repository.setEnabled(category, newValue);
    if (category == ContentIndexCategory.pdf) {
      _pdfEnabled = newValue;
    } else {
      _foliateEnabled = newValue;
    }
  }
}
