// MdxReaderPool：限制同時開啟的 MDX reader 數量（epic-63 Issue 6a Task 6）。
//
// 每本字典只保留一個 reader；超過上限時關掉最久沒用的。以 `Future` 記錄
// 開啟中的項目，避免同一個來源被並發開啟兩次。
//
// 查詢一律走 [MdxReaderPool.use]：`evict`／`closeAll`／LRU 淘汰會等該項目
// 手上沒有進行中的查詢才真的關檔，否則關掉的 reader 還在讀，查詢會被誤判
// 成壞檔（計畫 Task 6）。
import 'dart:async';

import 'mdx_reader.dart';

/// 以來源 id 為鍵的 LRU reader 池。
class MdxReaderPool {
  MdxReaderPool({
    this.maxOpen = 2,
    Future<MdxReader> Function(String path)? opener,
  })  : assert(maxOpen > 0, 'maxOpen 至少要是 1'),
        _opener = opener ?? MdxReader.open;

  /// 同時保持開啟的 reader 上限。
  final int maxOpen;

  final Future<MdxReader> Function(String path) _opener;

  final Map<String, _PoolEntry> _entries = {};

  /// 單調遞增的使用序號；愈大代表愈晚使用。
  int _tick = 0;

  /// 取得 [sourceId] 的 reader；已在池內就直接重用。
  Future<MdxReader> acquire(String sourceId, String path) {
    final existing = _entries[sourceId];
    if (existing != null) {
      existing.lastUsed = ++_tick;
      return existing.reader;
    }
    final entry = _PoolEntry(reader: _opener(path), lastUsed: ++_tick);
    _entries[sourceId] = entry;
    return _resolve(sourceId, entry);
  }

  Future<MdxReader> _resolve(String sourceId, _PoolEntry entry) async {
    try {
      final reader = await entry.reader;
      entry.opening = false;
      if (!identical(_entries[sourceId], entry)) {
        // 開啟期間被 evict／closeAll 移除；不要再把已關閉的 reader 交出去。
        await _close(entry);
        throw const MdxException(MdxErrorKind.notFound, 'reader 已被移出池');
      }
      await _trim(keep: sourceId);
      return reader;
    } catch (error) {
      entry.opening = false;
      if (identical(_entries[sourceId], entry)) _entries.remove(sourceId);
      rethrow;
    }
  }

  /// 取得 reader 並在 [action] 執行期間把它標記為「使用中」。
  ///
  /// 這段期間 `evict`／`closeAll`／LRU 淘汰不會關掉它。查詢請走這個入口，
  /// 不要直接拿 [acquire] 的 reader 去讀。
  Future<T> use<T>(
    String sourceId,
    String path,
    Future<T> Function(MdxReader reader) action,
  ) async {
    final reader = await acquire(sourceId, path);
    final entry = _entries[sourceId];
    if (entry == null) {
      // 在 `acquire` 完成前就被移出池；reader 由移出的一方負責關閉。
      throw const MdxException(MdxErrorKind.notFound, 'reader 已被移出池');
    }
    entry.beginUse();
    try {
      return await action(reader);
    } finally {
      entry.endUse();
    }
  }

  /// 關閉並移除 [sourceId]；不在池內時不做事。
  Future<void> evict(String sourceId) async {
    final entry = _entries.remove(sourceId);
    if (entry != null) await _close(entry);
  }

  /// 關閉全部 reader。之後 [acquire] 會重新開啟。
  Future<void> closeAll() async {
    final entries = _entries.values.toList();
    _entries.clear();
    await Future.wait(entries.map(_close));
  }

  /// 超過 [maxOpen] 時關閉最久未用的項目；開啟中的項目先跳過。
  Future<void> _trim({required String keep}) async {
    while (_entries.length > maxOpen) {
      String? oldestId;
      _PoolEntry? oldest;
      for (final entry in _entries.entries) {
        if (entry.key == keep || entry.value.opening) continue;
        if (oldest == null || entry.value.lastUsed < oldest.lastUsed) {
          oldest = entry.value;
          oldestId = entry.key;
        }
      }
      if (oldest == null || oldestId == null) return;
      _entries.remove(oldestId);
      await _close(oldest);
    }
  }

  /// 關閉單一項目；開啟失敗或關閉失敗都視為已釋放，不影響其他 reader。
  ///
  /// 項目還在被查詢使用時先等它結束，避免關掉正在讀的檔案。
  Future<void> _close(_PoolEntry entry) async {
    try {
      await entry.idle;
      final reader = await entry.reader;
      await reader.close();
    } catch (_) {
      // 清理失敗不該讓 evict／closeAll 失敗。
    }
  }
}

class _PoolEntry {
  _PoolEntry({required this.reader, required this.lastUsed});

  final Future<MdxReader> reader;
  int lastUsed;

  /// 開啟尚未完成；這段期間不要被 LRU 挑中。
  bool opening = true;

  /// 進行中的查詢數；大於 0 時不可以關檔。
  int _inFlight = 0;
  Completer<void>? _idle;

  void beginUse() => _inFlight++;

  void endUse() {
    _inFlight--;
    if (_inFlight > 0) return;
    _idle?.complete();
    _idle = null;
  }

  /// 沒有進行中的查詢時立刻完成；否則等最後一個查詢結束。
  Future<void> get idle {
    if (_inFlight == 0) return Future<void>.value();
    return (_idle ??= Completer<void>()).future;
  }
}
