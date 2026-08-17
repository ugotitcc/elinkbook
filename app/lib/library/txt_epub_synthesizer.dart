// app/lib/library/txt_epub_synthesizer.dart
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'content_uri_reader.dart';
import 'epub_container_builder.dart';
import 'txt_chapter_splitter.dart';
import 'txt_charset_detection.dart';

/// TXT 檔案解碼後找不到任何非空白內容時拋出——沒有內容的書本質上無法
/// 開啟，呼叫端（book_import_service_impl.dart）應中止匯入、不建立 Book
/// 記錄，比照 CBZ 的 `NoComicPagesException`（epic-11 Issue 3）既有處置
/// 慣例。
class EmptyTxtException implements Exception {
  final String message;
  const EmptyTxtException(this.message);
  @override
  String toString() => 'EmptyTxtException: $message';
}

class TxtSynthesisResult {
  /// 合成後的 EPUB 壓縮檔完整位元組內容，供呼叫端落地為 `Book.filePath`
  /// 指向的衍生檔案（**檔名副檔名須維持 `.txt`**，見 Global Constraints
  /// 已查證事實 #1，本函式不負責落地檔案，只回傳位元組）。
  final Uint8List epubBytes;

  /// 本次解碼實際採用的編碼，供匯入流程記錄／除錯使用。
  final TxtEncoding detectedEncoding;

  const TxtSynthesisResult({required this.epubBytes, required this.detectedEncoding});
}

/// 每行（去除純空白行）成為一個 `<p>` 元素——常見網路小說 TXT 排版慣例
/// （每行即一段，非以空白行分隔），比照本專案既有排版管線不主動猜測換行
/// 語意的既定精神（見 spec.md「TXT／Markdown 合成書籍結構」）。
String _buildXhtmlBody(String content) {
  final buffer = StringBuffer();
  for (final line in content.split(RegExp(r'\r\n|\r|\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    buffer.writeln('<p>${escapeXml(trimmed)}</p>');
  }
  return buffer.toString();
}

String _chapterXhtml(String content) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>內容</title></head>
<body>
${_buildXhtmlBody(content)}</body>
</html>
''';

/// 純 CPU 運算（解碼＋章節切分＋EPUB 結構產生），外包至 `Isolate.run()`
/// 背景執行（見呼叫處 [synthesizeTxtBook] 註解）。頂層純函式、僅接受可
/// 跨 isolate 傳遞的 [Uint8List]／[String] 參數，不捕捉任何 State 或其他
/// 不可傳遞物件（比照 CLAUDE.md「不可逆的技術決策」段落對 `Isolate.run()`
/// closure 的既有限制）。**不呼叫 `generateTxtCover()`**（`dart:ui` 在
/// spawn 的 isolate 內不可用，見本檔案／Task 6 開頭「背景」說明），封面
/// 產生由呼叫端（`book_import_service_impl.dart`）在主 isolate 另行處理。
TxtSynthesisResult _decodeAndSynthesize(Uint8List bytes, String bookId, String title) {
  final decoded = detectAndDecodeTxt(bytes);
  final chapters = splitIntoChapters(decoded.text);
  final hasContent = chapters.any((c) => c.content.trim().isNotEmpty);
  if (!hasContent) {
    throw const EmptyTxtException('TXT 檔案內容為空');
  }

  final archive = Archive();
  archive.addFile(
    ArchiveFile.bytes('mimetype', utf8.encode('application/epub+zip'))
      ..compression = CompressionType.none,
  );
  archive.addFile(ArchiveFile.bytes('META-INF/container.xml', utf8.encode(kEpubContainerXml)));

  final manifestItems = StringBuffer();
  final spineItems = StringBuffer();
  final navItems = StringBuffer();
  var chapterIndex = 0;

  for (final chapter in chapters) {
    if (chapter.content.trim().isEmpty) continue;
    final subChunks = chunkByByteSize(chapter.content);
    String? firstHref;
    for (var i = 0; i < subChunks.length; i++) {
      chapterIndex++;
      final id = 'chap${chapterIndex.toString().padLeft(4, '0')}';
      final href = 'text/$id.xhtml';
      firstHref ??= href;
      archive.addFile(
        ArchiveFile.bytes('OEBPS/$href', utf8.encode(_chapterXhtml(subChunks[i]))),
      );
      manifestItems.writeln('<item id="$id" href="$href" media-type="application/xhtml+xml"/>');
      spineItems.writeln('<itemref idref="$id"/>');
    }
    // 只有真正偵測到章節標題的段落才產生目錄項——分塊本身是位元組上限
    // 防護（chunkByByteSize），不是語意章節邊界，不應冒充為目錄項目
    // （見 Task 6 設計討論；比照 Issue 3 CBZ 虛擬目錄「有明確語意才產生
    // 項目」的相同原則，此處反過來是「沒有語意就不產生」）。
    if (chapter.title != null && firstHref != null) {
      navItems.writeln('<li><a href="$firstHref">${escapeXml(chapter.title!)}</a></li>');
    }
  }

  archive.addFile(ArchiveFile.bytes('OEBPS/nav.xhtml', utf8.encode(buildEpubNavXhtml(navItems.toString()))));
  archive.addFile(ArchiveFile.bytes(
    'OEBPS/content.opf',
    utf8.encode(buildEpubContentOpf(
      identifier: 'elinkbook-txt-$bookId',
      title: title,
      manifestItems: manifestItems.toString(),
      spineItems: spineItems.toString(),
    )),
  ));

  return TxtSynthesisResult(
    epubBytes: ZipEncoder().encodeBytes(archive),
    detectedEncoding: decoded.encoding,
  );
}

/// 讀取 [filePath]（本機路徑或 `content://` URI）指向的 TXT 檔案，偵測
/// 編碼、依章節標題與位元組大小分塊，合成一份最小合法 EPUB3 壓縮檔（見
/// Global Constraints 已查證事實 #2 的結構要求）。[bookId] 用於 OPF
/// `dc:identifier`，[title] 用於 `dc:title`（呼叫端傳入書名，通常是依
/// 檔名推導的既有慣例，見 `book_import_service_impl.dart`
/// `titleFromFileName()`）。CPU 密集的解碼／分塊／XML 組裝外包至
/// `Isolate.run()`（spec.md 明文要求，比照 `book_content_fingerprint.dart`
/// 既有作法）。
Future<TxtSynthesisResult> synthesizeTxtBook(
  String filePath,
  String bookId,
  String title,
) async {
  final bytes = filePath.contains('://')
      ? await readContentUriBytes(filePath, tempFilePrefix: 'txt_probe', tempFileExtension: '.txt')
      : await File(filePath).readAsBytes();
  return Isolate.run(() => _decodeAndSynthesize(bytes, bookId, title));
}
