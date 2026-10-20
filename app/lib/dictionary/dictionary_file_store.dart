// app/lib/dictionary/dictionary_file_store.dart
import 'dart:io';

import 'mdx_companion_files.dart';

/// 每本字典的 App 私有目錄：`<root>/<sourceId>/`，放 `.mdd`、`.css` 等附屬檔案。
class DictionaryFileStore {
  DictionaryFileStore(this.root);

  final Directory root;

  Directory dirFor(String sourceId) => Directory('${root.path}/$sourceId');

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
    final dir = dirFor(sourceId);
    await dir.create(recursive: true);
    await File(file.path).copy('${dir.path}/${file.name}');
  }

  /// 刪除整個目錄；目錄不存在時不丟例外。
  Future<void> deleteAll(String sourceId) async {
    final dir = dirFor(sourceId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
