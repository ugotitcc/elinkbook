// app/lib/dictionary/content_id.dart
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'importers/dictionary_importer.dart';

const _chunk = 64 * 1024;

/// 重複匯入偵測用的內容指紋（spec §5）。
///
/// 檔案 ≥ 128 KB：前 64 KB 與後 64 KB 各算 SHA-256；較小的檔案只雜湊整個
/// 檔案。最後把「頭雜湊:尾雜湊:大小:檔名」再雜湊一次。大檔案只看頭尾是刻意
/// 的取捨，換取不必讀完整個檔案。用 [RandomAccessFile] 讀區段，不整檔進記憶體。
Future<String> computeContentId({
  required String filePath,
  required String fileName,
}) async {
  RandomAccessFile? file;
  try {
    file = await File(filePath).open();
    final size = await file.length();
    String head;
    String tail = '';
    if (size >= 2 * _chunk) {
      head = await _hashRange(file, 0, _chunk);
      tail = await _hashRange(file, size - _chunk, _chunk);
    } else {
      head = await _hashRange(file, 0, size);
    }
    return sha256.convert(utf8.encode('$head:$tail:$size:$fileName')).toString();
  } on FileSystemException {
    throw const DictionaryImportException('unreadableFile');
  } finally {
    await file?.close();
  }
}

Future<String> _hashRange(RandomAccessFile file, int start, int length) async {
  await file.setPosition(start);
  final bytes = await file.read(length);
  return sha256.convert(bytes).toString();
}
