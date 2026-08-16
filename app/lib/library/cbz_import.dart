import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'content_uri_reader.dart';

/// comic-book.js（`readest/foliate-js`，釘定 commit
/// dd71f2be356563c16a23272686189fcfb45d0b82）辨識為漫畫頁面的圖片副檔名
/// 清單，逐字對照該檔案原始碼的 `exts` 常數（epic-11-multi-format-reader
/// Issue 3 查證）——本模組的自然排序與封面判斷須以同一份清單為準，否則
/// Dart 端判定的「第一張圖片」可能與 comic-book.js 實際解析出的頁面順序
/// 不一致。
const _kSupportedImageExtensions = {
  '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg', '.jxl', '.avif',
};

/// CBZ 壓縮檔內完全沒有支援的圖片格式時拋出——沒有可用頁面的漫畫書本質上
/// 無法開啟，呼叫端（book_import_service_impl.dart）應中止匯入、不建立
/// Book 記錄，比照 KF8 DRM 情境（DrmProtectedException）的既有處置慣例，
/// 不可比照一般 metadata 擷取失敗降級為「無封面繼續匯入」——CBZ 不存在
/// 「降級但仍可開啟」的中間狀態。
class NoComicPagesException implements Exception {
  final String message;
  const NoComicPagesException(this.message);
  @override
  String toString() => 'NoComicPagesException: $message';
}

class CbzImportResult {
  /// 依自然排序重新命名、重建索引後的壓縮檔完整位元組內容，供呼叫端落地
  /// 為 `Book.filePath` 指向的衍生檔案。
  final Uint8List rebuiltArchiveBytes;

  /// 自然排序後第一張圖片的原始位元組，供呼叫端落地為封面（spec.md
  /// 「CBZ 支援」：「封面固定取排序後第一張圖片」）。
  final Uint8List coverBytes;

  const CbzImportResult({
    required this.rebuiltArchiveBytes,
    required this.coverBytes,
  });
}

/// 自然排序比較器：先切割成「連續數字」與「連續非數字」交錯的片段，數字
/// 片段以數值比較、其餘片段忽略大小寫比較（審查修正，見
/// reviews/review-issue-3-plan.md Minor #2：漫畫壓縮檔常見由不同掃圖/
/// 壓製來源合併，檔名大小寫可能不一致，例如「Page1.jpg」與「page2.jpg」
/// 混用——若依原始大小寫比較，ASCII 'P'(0x50) < 'p'(0x70) 會讓
/// 「Page2.jpg」排到「page1.jpg」之前，產生違反直覺的錯誤頁序；忽略大小寫
/// 後兩者依數字片段 1 < 2 正確排序）。`comic-book.js` 的 `makeComicBook()`
/// 對圖片檔名僅用純字典序 `.sort()`（見 issues.md Issue 1 Spike 查證：
/// 「1.jpg」「10.jpg」「2.jpg」會被排成「1,10,2,3...」），須在 Dart 端匯入
/// 階段以本比較器排出正確頁序後，重新命名為零填補檔名（見
/// [prepareCbzForImport]），讓 comic-book.js 自己的字典序排序也能得到相同
/// 結果，不依賴其內建排序。
int compareNaturalOrder(String a, String b) {
  final chunksA = _splitIntoChunks(a);
  final chunksB = _splitIntoChunks(b);
  final len = chunksA.length < chunksB.length ? chunksA.length : chunksB.length;
  for (var i = 0; i < len; i++) {
    final numA = int.tryParse(chunksA[i]);
    final numB = int.tryParse(chunksB[i]);
    final cmp = (numA != null && numB != null)
        ? numA.compareTo(numB)
        : chunksA[i].toLowerCase().compareTo(chunksB[i].toLowerCase());
    if (cmp != 0) return cmp;
  }
  return chunksA.length.compareTo(chunksB.length);
}

List<String> _splitIntoChunks(String value) {
  final chunks = <String>[];
  final buffer = StringBuffer();
  bool? lastWasDigit;
  for (final rune in value.runes) {
    final isDigit = rune >= 0x30 && rune <= 0x39; // '0'-'9'
    if (lastWasDigit != null && isDigit != lastWasDigit) {
      chunks.add(buffer.toString());
      buffer.clear();
    }
    buffer.writeCharCode(rune);
    lastWasDigit = isDigit;
  }
  if (buffer.isNotEmpty) chunks.add(buffer.toString());
  return chunks;
}

/// 讀取 [filePath]（本機路徑或 `content://` URI，比照 kf8_metadata.dart
/// extractKf8Metadata() 的既有的 content:// 處理模式：先透過既有、格式無關
/// 的 copyContentUriToFile 原生方法複製到暫存檔，因為 dart:io 無法對
/// content:// URI 做隨機存取讀取，讀取整個壓縮檔內容需要完整位元組陣列）
/// 指向的 CBZ 壓縮檔，對內部圖片檔名做自然排序，重新命名為零填補檔名
/// （`page_0001.<原副檔名>` 起算）並重建壓縮檔索引，回傳重建後的完整位元組
/// 與封面位元組。非圖片項目（例如 ComicInfo.xml）不保留於重建後的壓縮檔
/// ——comic-book.js 本身也只用圖片項目組成 book.sections/book.toc，本 Epic
/// 範圍未涵蓋 ComicInfo.xml 中繼資料擷取（spec.md「CBZ 支援」未提及，
/// YAGNI）。
Future<CbzImportResult> prepareCbzForImport(String filePath) async {
  final bytes = filePath.contains('://')
      ? await readContentUriBytes(
          filePath,
          tempFilePrefix: 'cbz_probe',
          tempFileExtension: '.cbz',
        )
      : await File(filePath).readAsBytes();
  // 審查修正（見 reviews/review-issue-3-plan.md Important #1）：解壓/排序/
  // 重新壓縮是純 CPU 運算，對包含數百張高解析度圖片的大型 CBZ 可能耗費
  // 明顯時間，外包至 Isolate.run() 背景執行，避免阻塞 UI isolate（比照
  // book_content_fingerprint.dart 對大檔案 SHA-256 計算的既有作法——本檔案
  // 讀取階段〔本機檔案／content:// 複製〕已在上面用 await 完成，傳入
  // Isolate.run() 的只有已讀出的 Uint8List，屬於可跨 isolate 傳遞型別）。
  return Isolate.run(() => _decodeSortAndRebuild(bytes));
}

/// 純 CPU 運算（zip 解壓／自然排序／重建），見 [prepareCbzForImport] 呼叫處
/// 註解——頂層純函式、僅接受可跨 isolate 傳遞的 [Uint8List] 參數，不捕捉
/// 任何 State 或其他不可傳遞物件（比照 CLAUDE.md「不可逆的技術決策」段落對
/// `Isolate.run()` closure 的既有限制：closure 須獨立於呼叫端詞法作用域，
/// 否則 Dart VM 會把整個作用域一併打包，牽連不可跨 isolate 傳遞的物件）。
CbzImportResult _decodeSortAndRebuild(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final imageFiles = archive.files
      .where((file) =>
          file.isFile &&
          _kSupportedImageExtensions.contains(p.extension(file.name).toLowerCase()))
      .toList()
    ..sort((a, b) => compareNaturalOrder(a.name, b.name));
  if (imageFiles.isEmpty) {
    throw const NoComicPagesException('CBZ 壓縮檔內沒有支援的圖片格式');
  }

  final rebuilt = Archive();
  for (var i = 0; i < imageFiles.length; i++) {
    final original = imageFiles[i];
    final newName =
        'page_${(i + 1).toString().padLeft(4, '0')}${p.extension(original.name)}';
    rebuilt.addFile(
      ArchiveFile.bytes(newName, original.readBytes() ?? Uint8List(0)),
    );
  }

  return CbzImportResult(
    rebuiltArchiveBytes: ZipEncoder().encodeBytes(rebuilt),
    coverBytes: imageFiles.first.readBytes() ?? Uint8List(0),
  );
}
