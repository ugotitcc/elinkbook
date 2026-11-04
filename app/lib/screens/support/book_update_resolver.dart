import 'dart:io';

import 'package:flutter/painting.dart';

import '../../library/book_import_service.dart';
import '../../library/book_update_models.dart';

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

/// 一筆候選與其對應的使用者決定。
class BookUpdateDecision {
  final BookUpdateCandidate candidate;
  final BookUpdateChoice choice;

  const BookUpdateDecision(this.candidate, this.choice);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookUpdateDecision &&
          runtimeType == other.runtimeType &&
          candidate == other.candidate &&
          choice == other.choice;

  @override
  int get hashCode => Object.hash(candidate, choice);

  @override
  String toString() => 'BookUpdateDecision($candidate, $choice)';
}

/// 套用結果：各操作計數，使用者可見文字由呼叫端在地化呈現。
class BookUpdateApplyResult {
  final int replaced;
  final int coexisted;
  final int skipped;
  final int failed;

  const BookUpdateApplyResult({
    this.replaced = 0,
    this.coexisted = 0,
    this.skipped = 0,
    this.failed = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookUpdateApplyResult &&
          runtimeType == other.runtimeType &&
          replaced == other.replaced &&
          coexisted == other.coexisted &&
          skipped == other.skipped &&
          failed == other.failed;

  @override
  int get hashCode => Object.hash(replaced, coexisted, skipped, failed);

  @override
  String toString() =>
      'BookUpdateApplyResult(replaced: $replaced, coexisted: $coexisted, skipped: $skipped, failed: $failed)';
}

/// 預設的封面快取失效函式：使 Flutter 記憶體中的 [ImageCache] 移除對應路徑的圖片。
void evictCoverImageCache(String coverPath) {
  try {
    PaintingBinding.instance.imageCache.evict(FileImage(File(coverPath)));
  } catch (_) {}
}

/// 逐筆循序套用使用者對更新候選的決定。
///
/// 任何單筆處理失敗均被隔離計入 [BookUpdateApplyResult.failed] 並丟棄其暫存檔，
/// 永不拋出例外，確保批次作業平順完成。
Future<BookUpdateApplyResult> applyBookUpdateChoices(
  BookImportService service,
  List<BookUpdateDecision> decisions, {
  void Function(String coverPath) onCoverChanged = evictCoverImageCache,
}) async {
  var replaced = 0;
  var coexisted = 0;
  var skipped = 0;
  var failed = 0;

  for (final decision in decisions) {
    final candidate = decision.candidate;
    final choice = decision.choice;

    switch (choice) {
      case SkipChoice():
        try {
          await service.discardUpdateCandidate(candidate);
        } catch (_) {}
        skipped++;

      case ReplaceChoice(bookId: final targetBookId):
        try {
          final result = await service.replaceBook(
            targetBookId,
            candidate.sourceUri,
            displayName: candidate.displayName,
            candidate: candidate,
          );

          if (result is BookReplaceSuccess) {
            replaced++;

            // 收集舊書與新書封面，非空且去重後觸發快取失效通知
            final oldCover = candidate.candidateBooks
                .where((b) => b.id == targetBookId)
                .firstOrNull
                ?.coverPath;
            final newCover = result.updatedBook.coverPath;

            final coversToEvict = <String>{
              ?oldCover,
              ?newCover,
            };

            for (final coverPath in coversToEvict) {
              try {
                onCoverChanged(coverPath);
              } catch (_) {}
            }
          } else {
            failed++;
            try {
              await service.discardUpdateCandidate(candidate);
            } catch (_) {}
          }
        } catch (_) {
          failed++;
          try {
            await service.discardUpdateCandidate(candidate);
          } catch (_) {}
        }

      case CoexistChoice():
        try {
          final book = await service.importCandidateAsNewBook(candidate);
          if (book != null) {
            coexisted++;
          } else {
            failed++;
          }
        } catch (_) {
          failed++;
        }
    }
  }

  return BookUpdateApplyResult(
    replaced: replaced,
    coexisted: coexisted,
    skipped: skipped,
    failed: failed,
  );
}
