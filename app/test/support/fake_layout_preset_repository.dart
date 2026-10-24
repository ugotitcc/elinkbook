import 'package:elinkbook/reader/layout_preset.dart';
import 'package:elinkbook/reader/layout_preset_repository.dart';

/// `LayoutPresetRepository` 原本沒有 Fake，只能用 in-memory sqflite；
/// 工廠需要無 I/O 的預設值，故補上。記憶體 `List<LayoutPreset>`，
/// 行為比照真實類別文件註解：`listAll()` 依 `id ASC` 排序；
/// `insert()` 忽略傳入的 `id`／時間戳，由 fake 指派；
/// `replace()` 保留既有 `createdAt`、`id` 不存在時靜默不做任何事。
class FakeLayoutPresetRepository implements LayoutPresetRepository {
  final List<LayoutPreset> _presets = [];
  int _nextId = 1;

  /// 指定哪些方法要丟例外（`'listAll'`／`'insert'`／`'replace'`／`'delete'`），
  /// 供測試注入失敗情境（epic-54 Issue 26 計畫審查 M-3）。可在測試中途改變。
  final Set<String> failOn = {};

  void _maybeFail(String method) {
    if (failOn.contains(method)) throw StateError('fake $method failed');
  }

  @override
  Future<List<LayoutPreset>> listAll() async {
    _maybeFail('listAll');
    final sorted = _presets.toList()
      ..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
    return sorted;
  }

  @override
  Future<void> insert(LayoutPreset preset) async {
    _maybeFail('insert');
    final now = DateTime.now();
    _presets.add(LayoutPreset(
      id: _nextId++,
      name: preset.name,
      createdAt: now,
      updatedAt: now,
      prefs: preset.prefs,
    ));
  }

  @override
  Future<void> replace(int id, LayoutPreset preset) async {
    _maybeFail('replace');
    final index = _presets.indexWhere((p) => p.id == id);
    if (index == -1) return;
    final existing = _presets[index];
    _presets[index] = LayoutPreset(
      id: id,
      name: preset.name,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
      prefs: preset.prefs,
    );
  }

  @override
  Future<void> delete(int id) async {
    _maybeFail('delete');
    _presets.removeWhere((p) => p.id == id);
  }
}
