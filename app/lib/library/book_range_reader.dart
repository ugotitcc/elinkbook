// 書檔長度與區段讀取（含 content:// 與本機路徑）（epic-66 Issue 12 Task 1）。

import 'dart:io';
import 'package:flutter/services.dart';

import 'windows_epub_metadata.dart';

const _defaultChannel = MethodChannel('elinkbook/reader_resources_cache');

/// 解析路徑字串：若為 `file://` URI 則轉為實體檔案路徑，否則回傳原字串。
String _resolveLocalFilePath(String uri) {
  if (uri.startsWith('file://')) {
    try {
      return Uri.parse(uri).toFilePath();
    } catch (_) {
      return uri.substring('file://'.length);
    }
  }
  return uri;
}

/// 取得書檔之總位元組長度。
///
/// - `content://` URI：透過原生通道 `elinkbook/reader_resources_cache` 的 `contentUriLength` 查詢；
/// - 本機檔案或 `file://` URI：使用 `File.length()` 讀取，檔案不存在或無法讀取回傳 null；
/// - 遇到通道拋出 [PlatformException] 時直接向外拋出，供呼叫端處理。
Future<int?> bookLength(
  String uri, {
  MethodChannel? channel,
}) async {
  if (uri.startsWith('content://')) {
    final activeChannel = channel ?? _defaultChannel;
    return await activeChannel.invokeMethod<int>(
      'contentUriLength',
      {'uri': uri},
    );
  }

  final filePath = _resolveLocalFilePath(uri);
  final file = File(filePath);
  try {
    if (!await file.exists()) return null;
    return await file.length();
  } on FileSystemException {
    return null;
  }
}

/// 讀取書檔之 [start, end) 位元組區段（上限 4 MB）。
///
/// - `content://` URI：透過原生通道 `elinkbook/reader_resources_cache` 的 `readContentUriRange` 讀取；
/// - 本機檔案或 `file://` URI：使用 [readFileRange] 讀取；
/// - 遇到通道拋出 [PlatformException] 時直接向外拋出，供呼叫端處理。
Future<Uint8List?> readBookRange(
  String uri,
  int start,
  int end, {
  MethodChannel? channel,
}) async {
  if (uri.startsWith('content://')) {
    final activeChannel = channel ?? _defaultChannel;
    return await activeChannel.invokeMethod<Uint8List>(
      'readContentUriRange',
      {
        'uri': uri,
        'start': start,
        'end': end,
      },
    );
  }

  final filePath = _resolveLocalFilePath(uri);
  return readFileRange(filePath, start, end);
}
