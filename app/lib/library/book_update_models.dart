import 'models/book.dart';
import 'models/library_enums.dart';

/// 更新版信心等級（見 spec.md「判定規則」）。
enum UpdateConfidence {
  /// 識別碼相同（高信心，僅適用於 EPUB）。
  high,

  /// 書名與作者正規化後相同（疑似更新版，需使用者確認）。
  suspected,
}

/// 一筆更新候選（見 spec.md「更新候選資料契約」）。
class BookUpdateCandidate {
  /// 新檔原始位置（URI 或本機路徑）。
  final String sourceUri;

  /// 顯示名稱（選擇器提供的真實檔名）。
  final String? displayName;

  /// 新檔書籍格式。
  final BookFileFormat format;

  /// 判定信心等級。
  final UpdateConfidence confidence;

  /// 候選書清單（識別碼命中者排最前，至少一本）。
  final List<Book> candidateBooks;

  /// 舊檔讀不到（SAF 授權遺失或檔案已被刪除）的候選書 id 集合。
  final Set<String> unreadableCandidateBookIds;

  /// 新檔已預先處理後的暫存位置；偵測階段為 null。
  final String? stagedPath;

  const BookUpdateCandidate({
    required this.sourceUri,
    this.displayName,
    required this.format,
    required this.confidence,
    required this.candidateBooks,
    this.unreadableCandidateBookIds = const {},
    this.stagedPath,
  });

  BookUpdateCandidate copyWith({
    String? stagedPath,
  }) {
    return BookUpdateCandidate(
      sourceUri: sourceUri,
      displayName: displayName,
      format: format,
      confidence: confidence,
      candidateBooks: candidateBooks,
      unreadableCandidateBookIds: unreadableCandidateBookIds,
      stagedPath: stagedPath ?? this.stagedPath,
    );
  }
}

/// 偵測結果（見 spec.md「模組與介面」）。
sealed class BookDetectionResult {
  const BookDetectionResult();
}

/// 新書（無對應）。
final class DetectedNewBook extends BookDetectionResult {
  const DetectedNewBook();
}

/// 重複（整檔雜湊與既有書相同）。
final class DetectedDuplicate extends BookDetectionResult {
  final Book existingBook;
  const DetectedDuplicate(this.existingBook);
}

/// 更新版（高信心或疑似，附候選清單）。
final class DetectedUpdate extends BookDetectionResult {
  final BookUpdateCandidate candidate;
  const DetectedUpdate(this.candidate);
}

/// 無法處理（格式不支援等）。
final class DetectedUnsupported extends BookDetectionResult {
  const DetectedUnsupported();
}

/// 取代結果（見 spec.md「模組與介面」）。
sealed class BookReplaceResult {
  const BookReplaceResult();
}

/// 取代成功，附更新後的書籍記錄。
final class BookReplaceSuccess extends BookReplaceResult {
  final Book updatedBook;
  const BookReplaceSuccess(this.updatedBook);
}

/// 取代失敗的原因。
enum BookReplaceFailureReason {
  /// 目標書籍不存在。
  bookNotFound,

  /// 新檔格式與原書不符。
  formatMismatch,

  /// 新檔解析失敗（損毀、加密或無內容）。
  newFileParseFailed,

  /// 寫入失敗（複製、換名或資料庫寫入例外）。
  writeFailed,
}

/// 取代失敗，附失敗原因。
final class BookReplaceFailure extends BookReplaceResult {
  final BookReplaceFailureReason reason;
  const BookReplaceFailure(this.reason);
}

/// 取代／並存時補寫的來源欄位（Issue 4 使用；只寫入非 null 者）。
class BookSourceRefs {
  final BookSource? source;
  final String? cloudFileId;
  final String? remoteServerId;
  final String? remoteBookId;
  final String? remoteDownloadUrl;

  const BookSourceRefs({
    this.source,
    this.cloudFileId,
    this.remoteServerId,
    this.remoteBookId,
    this.remoteDownloadUrl,
  });
}

/// 書名／作者比對用的正規化：去首尾空白、轉小寫、全形英數轉半形、
/// 全形空白（U+3000）轉半形空白；空字串或純空白回傳 null（代表「空」，不參與比對）；
/// 中文標點不被改動。
String? normalizeBookKey(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final sb = StringBuffer();
  for (final char in trimmed.runes) {
    if (char == 0x3000) {
      sb.write(' ');
    } else if ((char >= 0xFF10 && char <= 0xFF19) ||
        (char >= 0xFF21 && char <= 0xFF3A) ||
        (char >= 0xFF41 && char <= 0xFF5A)) {
      sb.writeCharCode(char - 0xFEE0);
    } else {
      sb.writeCharCode(char);
    }
  }

  final normalized = sb.toString().trim().toLowerCase();
  return normalized.isEmpty ? null : normalized;
}
