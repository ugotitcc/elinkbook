// Windows 圖書詮釋資料提取分派與序列化調度（epic-66 Issue 2 Task 4）。
//
// 依書籍格式分派：
// - epub: 透過 runSerialized 包裹，使用 HeadlessInAppWebView 背景載入 foliate-js 解析；
// - pdf: 使用 pdfrx 渲染第 0 頁封面，回傳 title/author 為 null；
// - 其他格式: 回傳 null。

import 'dart:async';

import 'package:flutter/services.dart';

import 'windows_epub_metadata.dart';
import 'windows_pdf_cover.dart';

Future<void> _lastSerializedTask = Future<void>.value();

/// 全 App 共用的非同步序列化調度佇列。
///
/// 確保傳入的 [task] 依序執行，即使前一個任務拋出例外也不影響後續任務。
Future<T> runSerialized<T>(Future<T> Function() task) {
  final completer = Completer<T>();
  _lastSerializedTask = _lastSerializedTask.then((_) async {
    try {
      completer.complete(await task());
    } catch (e, st) {
      completer.completeError(e, st);
    }
  }).catchError((_) {});
  return completer.future;
}

/// Windows 平台的圖書詮釋資料提取入口函式。
///
/// 格式相容於 [BookMetadataExtractor] 型別：
/// - 若 [uri] 包含 `://`（非本機純路徑），拋出 [PlatformException]；
/// - 若 [format] 為 `epub`，使用 [runSerialized] 確保同一時間只有一個 headless WebView 運行；
/// - 若 [format] 為 `pdf`，回傳包含 `coverBytes` 且 `title`/`author` 為 null 的 Map；
/// - 若解析失敗，統一包裝為 code 為 `extraction_failed` 的 [PlatformException]。
Future<Map<String, Object?>?> extractWindowsBookMetadata(
  String uri,
  String format, {
  Future<Map<String, Object?>> Function(String)? epubReader,
  Future<Uint8List?> Function(String)? pdfRenderer,
}) async {
  if (uri.contains('://')) {
    throw PlatformException(
      code: 'extraction_failed',
      message: 'Windows 僅支援本機路徑，不支援 URI: $uri',
    );
  }

  final lowerFormat = format.toLowerCase();
  if (lowerFormat == 'epub') {
    return runSerialized(() async {
      try {
        final reader = epubReader ?? readEpubMetadataInWebView;
        return await reader(uri);
      } catch (e) {
        if (e is PlatformException) rethrow;
        throw PlatformException(
          code: 'extraction_failed',
          message: e.toString(),
        );
      }
    });
  } else if (lowerFormat == 'pdf') {
    try {
      final renderer = pdfRenderer ?? renderPdfCover;
      final coverBytes = await renderer(uri);
      if (coverBytes == null) {
        throw PlatformException(
          code: 'extraction_failed',
          message: 'PDF 封面渲染失敗或檔案為空: $uri',
        );
      }
      return <String, Object?>{
        'title': null,
        'author': null,
        'coverBytes': coverBytes,
      };
    } catch (e) {
      if (e is PlatformException) rethrow;
      throw PlatformException(
        code: 'extraction_failed',
        message: e.toString(),
      );
    }
  }

  return null;
}
