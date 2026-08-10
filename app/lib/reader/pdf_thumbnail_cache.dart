/// 泛型、有大小上限的 LRU（最近最少使用）快取，供 [PdfThumbnailPanel]
/// 管理縮圖影像的生命週期（epic-24-pdf-engine-rebuild Issue 7）。刻意設計
/// 為不依賴 `dart:ui`／Flutter 的純 Dart 類別——淘汰時如何釋放資源交由
/// 呼叫端透過 [dispose] 決定，讓核心 LRU 邏輯本身可以用輕量假物件單元測試
/// （不需要真的建構 `ui.Image`），比照既有
/// `_PdfReaderViewState._boldOverlayImages`（Issue 3）的 LRU 快取設計精神
/// 抽成獨立可重用單元。
///
/// 使用 `Map`（Dart 預設實作為插入順序穩定的 `LinkedHashMap`）的插入順序
/// 語意實作 LRU：[get] 命中時會把該項目移到「最近使用」端（透過移除後
/// 重新插入），[put] 在超過 [maxSize] 時淘汰目前最舊（`keys.first`）的
/// 項目並呼叫 [dispose] 釋放。
class PdfThumbnailCache<T> {
  final int maxSize;
  final void Function(T value) dispose;
  final _entries = <int, T>{};

  PdfThumbnailCache({required this.maxSize, required this.dispose});

  /// 讀取鍵 [key] 對應的值；命中時視為「最近使用」，延後被淘汰的順序。
  /// 未命中回傳 `null`。
  T? get(int key) {
    final value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value;
    return value;
  }

  /// 寫入鍵 [key] 對應的值 [value]。若 [key] 已存在，舊值先被 [dispose]
  /// 釋放再覆寫；若寫入後項目數超過 [maxSize]，淘汰目前最舊的項目並呼叫
  /// [dispose] 釋放。
  void put(int key, T value) {
    final existing = _entries.remove(key);
    if (existing != null) dispose(existing);
    _entries[key] = value;
    if (_entries.length > maxSize) {
      final oldestKey = _entries.keys.first;
      dispose(_entries.remove(oldestKey) as T);
    }
  }

  bool contains(int key) => _entries.containsKey(key);

  int get length => _entries.length;

  /// 釋放所有目前快取的項目並清空——供持有者（例如
  /// [PdfThumbnailPanel]）在自身 `dispose()` 時呼叫，避免面板關閉時仍殘留
  /// 未釋放的縮圖影像。
  void clear() {
    for (final value in _entries.values) {
      dispose(value);
    }
    _entries.clear();
  }
}
