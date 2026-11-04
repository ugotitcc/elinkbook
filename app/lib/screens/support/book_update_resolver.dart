import 'dart:io';

import 'package:flutter/painting.dart';

import '../../library/book_import_service.dart';
import '../../library/book_update_models.dart';
import '../../library/book_update_settle.dart';

export '../../library/book_update_settle.dart'
    show
        BookUpdateChoice,
        ReplaceChoice,
        CoexistChoice,
        SkipChoice,
        BookUpdateSettleOutcome,
        BookUpdateSettleResult,
        settleBookUpdate;

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
    final result = await settleBookUpdate(
      service,
      decision.candidate,
      decision.choice,
    );

    switch (result.outcome) {
      case BookUpdateSettleOutcome.replaced:
        replaced++;
        for (final coverPath in result.changedCoverPaths) {
          try {
            onCoverChanged(coverPath);
          } catch (_) {}
        }
      case BookUpdateSettleOutcome.coexisted:
        coexisted++;
      case BookUpdateSettleOutcome.skipped:
        skipped++;
      case BookUpdateSettleOutcome.failed:
        failed++;
    }
  }

  return BookUpdateApplyResult(
    replaced: replaced,
    coexisted: coexisted,
    skipped: skipped,
    failed: failed,
  );
}
