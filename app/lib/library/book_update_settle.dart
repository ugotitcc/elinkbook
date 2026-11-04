import 'book_import_service.dart';
import 'book_update_models.dart';

/// 使用者對一筆更新候選的決定。
sealed class BookUpdateChoice {
  const BookUpdateChoice();
}

/// 取代既有書籍（指定 [bookId]）。
final class ReplaceChoice extends BookUpdateChoice {
  final String bookId;
  const ReplaceChoice(this.bookId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplaceChoice &&
          runtimeType == other.runtimeType &&
          bookId == other.bookId;

  @override
  int get hashCode => bookId.hashCode;

  @override
  String toString() => 'ReplaceChoice($bookId)';
}

/// 並存（當成新書匯入）。
final class CoexistChoice extends BookUpdateChoice {
  const CoexistChoice();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoexistChoice && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'CoexistChoice()';
}

/// 跳過此更新候選。
final class SkipChoice extends BookUpdateChoice {
  const SkipChoice();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkipChoice && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'SkipChoice()';
}

/// 單筆更新版結算結果枚舉。
enum BookUpdateSettleOutcome {
  replaced,
  coexisted,
  skipped,
  failed,
}

/// 單筆更新版結算結果。
class BookUpdateSettleResult {
  final BookUpdateSettleOutcome outcome;

  /// 取代成功時，舊書與新書封面路徑（非 null、去重）；供 UI 層 evict 圖片快取。
  final Set<String> changedCoverPaths;

  const BookUpdateSettleResult(
    this.outcome, {
    this.changedCoverPaths = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookUpdateSettleResult &&
          runtimeType == other.runtimeType &&
          outcome == other.outcome &&
          setEquals(changedCoverPaths, other.changedCoverPaths);

  @override
  int get hashCode => Object.hash(outcome, Object.hashAll(changedCoverPaths));

  @override
  String toString() =>
      'BookUpdateSettleResult(outcome: $outcome, changedCoverPaths: $changedCoverPaths)';
}

/// Helper 比較兩個 Set 是否元素相同
bool setEquals<T>(Set<T>? a, Set<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (final T value in a) {
    if (!b.contains(value)) return false;
  }
  return true;
}

/// 對單一更新候選套用決定；永不拋出例外。
///
/// 語意：
/// - [SkipChoice] → `discardUpdateCandidate(candidate)`；回傳 [BookUpdateSettleOutcome.skipped]。
/// - [ReplaceChoice] → 呼叫 `replaceBook`，成功時收集舊書與新書封面路徑回傳；失敗或拋出例外時補丟棄暫存檔並回傳 [BookUpdateSettleOutcome.failed]。
/// - [CoexistChoice] → 呼叫 `importCandidateAsNewBook`（帶入 [folderName] 與 [sourceRefs]），成功回傳 [BookUpdateSettleOutcome.coexisted]；為 null 或拋例外回傳 [BookUpdateSettleOutcome.failed]（服務已自行丟棄暫存檔）。
Future<BookUpdateSettleResult> settleBookUpdate(
  BookImportService service,
  BookUpdateCandidate candidate,
  BookUpdateChoice choice, {
  BookSourceRefs? sourceRefs,
  String? folderName,
}) async {
  switch (choice) {
    case SkipChoice():
      try {
        await service.discardUpdateCandidate(candidate);
      } catch (_) {}
      return const BookUpdateSettleResult(BookUpdateSettleOutcome.skipped);

    case ReplaceChoice(bookId: final targetBookId):
      try {
        final result = await service.replaceBook(
          targetBookId,
          candidate.sourceUri,
          displayName: candidate.displayName,
          candidate: candidate,
          sourceRefs: sourceRefs,
        );

        if (result is BookReplaceSuccess) {
          final oldCover = candidate.candidateBooks
              .where((b) => b.id == targetBookId)
              .firstOrNull
              ?.coverPath;
          final newCover = result.updatedBook.coverPath;

          final coversToEvict = <String>{
            ?oldCover,
            ?newCover,
          };

          return BookUpdateSettleResult(
            BookUpdateSettleOutcome.replaced,
            changedCoverPaths: coversToEvict,
          );
        } else {
          try {
            await service.discardUpdateCandidate(candidate);
          } catch (_) {}
          return const BookUpdateSettleResult(BookUpdateSettleOutcome.failed);
        }
      } catch (_) {
        try {
          await service.discardUpdateCandidate(candidate);
        } catch (_) {}
        return const BookUpdateSettleResult(BookUpdateSettleOutcome.failed);
      }

    case CoexistChoice():
      try {
        final book = await service.importCandidateAsNewBook(
          candidate,
          folderName: folderName,
          sourceRefs: sourceRefs,
        );
        if (book != null) {
          return const BookUpdateSettleResult(BookUpdateSettleOutcome.coexisted);
        } else {
          return const BookUpdateSettleResult(BookUpdateSettleOutcome.failed);
        }
      } catch (_) {
        return const BookUpdateSettleResult(BookUpdateSettleOutcome.failed);
      }
  }
}
