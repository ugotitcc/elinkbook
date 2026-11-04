import 'dart:io';

import 'package:path/path.dart' as p;

/// 更新暫存目錄名稱（位於應用程式文件目錄下）。
const String kUpdateStagingFolderName = 'update_staging';

/// 清空 [documentsDirectory]/update_staging 底下所有內容（檔案與子目錄），保留目錄本身或不建立皆可。
/// 目錄不存在視為成功；任何刪除失敗皆吞掉，永不拋例外、不阻擋啟動。
Future<void> sweepUpdateStaging(Directory documentsDirectory) async {
  try {
    final stagingPath = p.join(documentsDirectory.path, kUpdateStagingFolderName);
    final type = await FileSystemEntity.type(stagingPath);
    if (type != FileSystemEntityType.directory) {
      return;
    }

    final stagingDir = Directory(stagingPath);
    final entities = stagingDir.list(recursive: false);
    await for (final entity in entities) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  } catch (_) {}
}
