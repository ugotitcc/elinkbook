import 'dart:async';

import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/custom_fonts_repository.dart';

/// 測試用 Fake，比照 [FakeBookmarksRepository] 模式。不共用真實
/// `book_reader_prefs` 表資料，[countBooksUsing] 改由 [usageCounts] 手動
/// 設定回傳值（widget test 不需要真的建一個資料庫連線）。
class FakeCustomFontsRepository implements CustomFontsRepository {
  final List<CustomFont> _storage = [];
  int _nextId = 1;

  /// 測試預先設定「這個 family name 目前有幾本書使用中」，供
  /// [countBooksUsing] 回傳；未設定的 family name 預設回傳 0。
  final Map<String, int> usageCounts = {};

  /// 測試用：若非 null，[listAll] 會先等待這個 Completer 完成才回傳，
  /// 供測試精確控制非同步載入完成的時機（epic-14-system-settings Issue 3，
  /// 驗證 ReaderScreen 在自訂字型清單載入完成前延後建構 FoliateEpubReaderView）。
  Completer<void>? loadGate;

  @override
  Future<List<CustomFont>> listAll() async {
    if (loadGate != null) await loadGate!.future;
    final list = List<CustomFont>.from(_storage);
    list.sort((a, b) => a.displayName.compareTo(b.displayName));
    return list;
  }

  @override
  Future<bool> familyNameExists(String familyName) async {
    return _storage.any((f) => f.familyName == familyName);
  }

  @override
  Future<int> insert(CustomFont font) async {
    final id = _nextId++;
    _storage.add(CustomFont(
      id: id,
      displayName: font.displayName,
      familyName: font.familyName,
      fontUri: font.fontUri,
    ));
    return id;
  }

  @override
  Future<void> rename(int id, String newDisplayName) async {
    final index = _storage.indexWhere((f) => f.id == id);
    if (index == -1) return;
    _storage[index] = _storage[index].copyWith(displayName: newDisplayName);
  }

  @override
  Future<int> countBooksUsing(String familyName) async {
    return usageCounts[familyName] ?? 0;
  }

  @override
  Future<void> deleteAndResetUsage(int id, String familyName) async {
    _storage.removeWhere((f) => f.id == id);
  }
}
