import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library_repository.dart';

/// 讀取 `content://` URI 指向檔案的完整位元組內容——`dart:io` 無法對
/// `content://` URI 做隨機存取讀取（ADR 0002 既有限制），先透過既有、格式
/// 無關的 `copyContentUriToFile` 原生方法複製到暫存檔，讀取後刪除。
/// [tempFilePrefix]／[tempFileExtension] 供呼叫端區分暫存檔用途與格式
/// （例如 CBZ 用 `cbz_probe`/`.cbz`，TXT 用 `txt_probe`/`.txt`），避免不同
/// 呼叫端的暫存檔互相覆蓋或難以除錯辨識。原本各自在 `kf8_metadata.dart`／
/// `cbz_import.dart` 各自實作一份幾乎相同的邏輯，epic-11-multi-format-reader
/// Issue 4 起抽出為共用版本。
Future<Uint8List> readContentUriBytes(
  String uri, {
  required String tempFilePrefix,
  required String tempFileExtension,
}) async {
  final tempDir = await getTemporaryDirectory();
  final tempPath = p.join(
    tempDir.path,
    '${tempFilePrefix}_${DateTime.now().microsecondsSinceEpoch}$tempFileExtension',
  );
  await kBookMetadataChannel.invokeMethod<void>(
    'copyContentUriToFile',
    {'uri': uri, 'destinationPath': tempPath},
  );
  final tempFile = File(tempPath);
  try {
    return await tempFile.readAsBytes();
  } finally {
    if (tempFile.existsSync()) tempFile.deleteSync();
  }
}
