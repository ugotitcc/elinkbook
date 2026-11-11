// Android 圖書詮釋資料提取分派與序列化調度（epic-66 Issue 12 & Issue 18）。
//
// 依書籍格式分派：
// - 當格式為 epub：透過 runSerialized 包裹，使用 foliate-js 探針解析；
//   若探針解析失敗，統一包裝為 code 為 `extraction_failed` 的 PlatformException；
// - 其他格式（如 pdf）：直接呼叫原生通道 `elinkbook/book_metadata`。

import 'dart:async';

import 'package:flutter/services.dart';

import 'android_epub_metadata.dart';
import 'library_repository.dart' show kBookMetadataChannel;
import 'windows_book_metadata.dart' show runSerialized;

/// 預設原生通道讀取器（供 PDF 等非 EPUB 格式使用）。
Future<Map<String, Object?>?> _defaultNativeReader(
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
/// 支援注入 [foliateReader] 與 [nativeReader] 以便進行單元測試。
Future<Map<String, Object?>?> extractAndroidBookMetadata(
  String uri,
  String format, {
  Future<Map<String, Object?>> Function(String uri)? foliateReader,
  Future<Map<String, Object?>?> Function(String uri, String format)? nativeReader,
}) async {
  final lowerFormat = format.toLowerCase();
  if (lowerFormat == 'epub') {
    return await runSerialized(() async {
      try {
        final reader = foliateReader ?? readEpubMetadataOnAndroid;
        return await reader(uri);
      } catch (e) {
        if (e is PlatformException) rethrow;
        throw PlatformException(
          code: 'extraction_failed',
          message: e.toString(),
        );
      }
    });
  }

  final fallback = nativeReader ?? _defaultNativeReader;
  return await fallback(uri, format);
}

/// Android 既有書籍（`is_fixed_layout == null`）版面回填偵測器（epic-66 Issue 18 Task 1）。
///
/// 經 [runSerialized] 呼叫 foliate-js 探針，回傳是否為固定版面（預設 `false`）；
/// 探針拋出例外時統一包成 `PlatformException(code: 'detection_failed')`。
Future<bool> detectAndroidEpubLayout(
  String uri, {
  Future<Map<String, Object?>> Function(String uri)? foliateReader,
}) async {
  return runSerialized(() async {
    try {
      final reader = foliateReader ?? readEpubMetadataOnAndroid;
      final map = await reader(uri);
      return map['isFixedLayout'] as bool? ?? false;
    } catch (e) {
      if (e is PlatformException) rethrow;
      throw PlatformException(
        code: 'detection_failed',
        message: e.toString(),
      );
    }
  });
}
