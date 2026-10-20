// app/lib/dictionary/dictionary_file_store.dart
import 'dart:io';

import 'package:path/path.dart' as p;

import 'mdx_companion_files.dart';

/// 每本字典的 App 私有目錄：`<root>/<sourceId>/`，放 `.mdd`、`.css` 等附屬檔案。
class DictionaryFileStore {
  DictionaryFileStore(this.root);

  final Directory root;

  /// 目錄路徑。[sourceId] 只取 basename，避免 `../` 跳出根目錄。
  Directory dirFor(String sourceId) =>
      Directory('${root.path}/${_safeName(sourceId)}');

  /// 目錄內的檔名；目錄不存在回傳空清單。
  Future<List<String>> listFiles(String sourceId) async {
    final dir = dirFor(sourceId);
    if (!await dir.exists()) return const [];
    final names = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        names.add(entity.uri.pathSegments.last);
      }
    }
    names.sort();
    return names;
  }

  /// 複製到私有目錄，保留原檔名；同名覆蓋。
  Future<void> copyInto(String sourceId, PickedFile file) async {
    final name = _safeName(file.name);
    final dir = dirFor(sourceId);
    await dir.create(recursive: true);
    await File(file.path).copy('${dir.path}/$name');
  }

  /// 把 [path] 搬進私有目錄並改名為 [name]（以 basename 為準）；同名覆蓋。
  ///
  /// 先嘗試 `rename`（同磁碟時不必複製內容）；跨磁碟或 Android 的
  /// `content://` 暫存檔不支援改名時，退回串流複製再刪來源檔。
  ///
  /// 回傳落地後的完整路徑。
  Future<String> moveInto(String sourceId, String path, String name) async {
    final fileName = _safeName(name);
    final dir = dirFor(sourceId);
    await dir.create(recursive: true);
    final destination = '${dir.path}/$fileName';
    try {
      await File(path).rename(destination);
    } on FileSystemException {
      // 目的檔已存在或跨磁碟：複製會覆蓋同名檔。
      await File(path).copy(destination);
      await File(path).delete();
    }
    return destination;
  }

  /// 刪除整個目錄；目錄不存在時不丟例外。
  Future<void> deleteAll(String sourceId) async {
    final dir = dirFor(sourceId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// 只保留 basename，並拒絕空字串與 `.`／`..`。
///
/// 選檔器給的 `name` 可能含路徑（例如 `a/b.css`）或 `../x`；一律取
/// basename，確保檔案只會落在私有目錄內。
String _safeName(String name) {
  final base = p.basename(name);
  if (base.isEmpty || base == '.' || base == '..') {
    throw ArgumentError.value(name, 'name', '檔名不可為空或 .／..');
  }
  return base;
}
