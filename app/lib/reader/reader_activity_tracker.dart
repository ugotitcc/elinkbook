// app/lib/reader/reader_activity_tracker.dart
import 'package:flutter/foundation.dart';

/// 追蹤「目前是否有任何閱讀畫面（[ReaderScreen]）開啟」（epic-10-search
/// Issue 1，見 spec.md §3.3）。`ContentIndexingScheduler` 監聽本類別，只在
/// [isReaderOpen] 為 false 且 App 前台時才處理背景索引佇列——使用者一旦
/// 開啟任何一本書，排程器須立即暫停，避免背景索引與使用者正在閱讀互相
/// 搶資源。
///
/// 全域單例（由 `main.dart` 建構一次，經既有依賴注入模式往下傳遞），
/// 由每個 [ReaderScreen] 實例的 `initState()`/`dispose()` 呼叫
/// [markReaderOpened]/[markReaderClosed]。
class ReaderActivityTracker extends ChangeNotifier {
  bool _isReaderOpen = false;

  bool get isReaderOpen => _isReaderOpen;

  void markReaderOpened() {
    if (_isReaderOpen) return;
    _isReaderOpen = true;
    notifyListeners();
  }

  void markReaderClosed() {
    if (!_isReaderOpen) return;
    _isReaderOpen = false;
    notifyListeners();
  }
}
