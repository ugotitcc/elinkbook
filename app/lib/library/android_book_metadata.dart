// Android 圖書詮釋資料提取分派與序列化調度（epic-66 Issue 12 Task 3）。
//
// 依書籍格式與旗標分派：
// - 當 [foliateFirst] 為 true 且格式為 epub：透過 runSerialized 包裹，使用 foliate-js 探針解析；
//   若探針解析失敗，記錄 debugPrint 並退回 Readium 原生通道；
// - 其他情況（[foliateFirst] 為 false 或格式非 epub 如 pdf）：直接呼叫 Readium 原生通道。

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'android_epub_metadata.dart';
import 'library_repository.dart' show kBookMetadataChannel;
import 'windows_book_metadata.dart' show runSerialized;

/// 是否預設優先使用 foliate-js 解析 Android EPUB 詮釋資料。
///
/// 預設為 false（保持現狀走 Readium）。在對比測試通過並獲得使用者確認後，
/// 於 Task 6 切換為 true。
const bool kAndroidMetadataFoliateFirst = false;

/// 預設 Readium 原生通道讀取器。
Future<Map<String, Object?>?> _defaultReadiumReader(
  String uri,
  String format,
) async {
  return await kBookMetadataChannel.invokeMapMethod<String, Object?>(
    'extractMetadata',
    {'uri': uri, 'format': format},
  );
}

/// Android 平台的圖書詮釋資料提取入口函式。
///
/// 格式相容於 `BookMetadataExtractor` 型別。
/// 支援注入 [foliateReader] 與 [readiumReader] 以便進行單元測試。
Future<Map<String, Object?>?> extractAndroidBookMetadata(
  String uri,
  String format, {
  bool foliateFirst = kAndroidMetadataFoliateFirst,
  Future<Map<String, Object?>> Function(String uri)? foliateReader,
  Future<Map<String, Object?>?> Function(String uri, String format)? readiumReader,
}) async {
  final lowerFormat = format.toLowerCase();
  if (foliateFirst && lowerFormat == 'epub') {
    try {
      return await runSerialized(() async {
        final reader = foliateReader ?? readEpubMetadataOnAndroid;
        return await reader(uri);
      });
    } catch (e, st) {
      debugPrint('foliate-js metadata 提取失敗，退回 Readium：$e\n$st');
      final fallback = readiumReader ?? _defaultReadiumReader;
      return await fallback(uri, format);
    }
  }

  final fallback = readiumReader ?? _defaultReadiumReader;
  return await fallback(uri, format);
}
