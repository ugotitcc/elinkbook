import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../library/models/book.dart';

/// 單書「⋮」動作選單的動作類型（`spec.md` 功能④）。Sheet 關閉後
/// 透過 `Navigator.pop(BookAction)` 回傳選項，由呼叫端決定實際行為
/// （比照既有 Dialog／Sheet 選項慣例，避免在 Sheet 尚未完全移除時
/// 同幀 push 新 Dialog 導致 Navigator 衝突）。
enum BookAction {
  showDetails,
  move,
  layoutOverride,
  removeCache,
  delete,
}

/// 單書「⋮」動作選單內容（`DESIGN.md` §11.3／`spec.md` 功能④）：純呈現，
/// 點擊選項後透過 `Navigator.pop(BookAction)` 回傳動作類型，由呼叫端
/// （`library_screen.dart`）負責實際邏輯。選項是否渲染由 `showRemoveCache`
/// 與 `showLayoutOverride` 控制。
class BookActionSheet extends StatelessWidget {
  final Book book;

  /// `book.source == BookSource.calibreOpds && book.isDownloaded` 時為
  /// true；`false` 時「移除快取」選項整項不渲染（本機匯入書籍沒有遠端
  /// 來源可重新下載，不該讓使用者以為「這本書其實可以移除快取只是現在
  /// 按不了」）。
  final bool showRemoveCache;

  /// `widget.readerFeatureRepositories.bookReaderPrefsRepository != null`
  /// 時為 true；`false` 時「版面覆寫」選項整項不渲染，比照 [showRemoveCache]
  /// 的不渲染慣例（`plans/plan-issue-4.md`「計劃範圍澄清」第 1 點：
  /// spec.md 原始建構子片段遺漏這個欄位，此為補充）。
  final bool showLayoutOverride;

  const BookActionSheet({
    super.key,
    required this.book,
    required this.showRemoveCache,
    required this.showLayoutOverride,
  });

  void _handle(BuildContext context, BookAction action) {
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 【review-plan-issue-4.md C-1】外層包 SingleChildScrollView：橫向
    // （Landscape）或無障礙大字級下，`EBSheetShell` 的 `Flexible` 給予的
    // 高度可能小於 5 個 ListTile 的總高度（56dp × 5 = 280dp），裸 Column
    // 會拋出 RenderFlex overflow 例外（`DESIGN.md#L235` §10.1 明文要求
    // 「高於此限制時內部採用 ListView 滾動」，由本元件的 child 自行實作）。
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('book_action_details'),
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.bookActionShowDetails),
            onTap: () => _handle(context, BookAction.showDetails),
          ),
          ListTile(
            key: const Key('book_action_move'),
            leading: const Icon(Icons.drive_file_move),
            title: Text(l10n.bookActionMove),
            onTap: () => _handle(context, BookAction.move),
          ),
          if (showLayoutOverride)
            ListTile(
              key: const Key('book_action_layout_override'),
              leading: const Icon(Icons.view_column_outlined),
              title: Text(l10n.bookActionLayoutOverride),
              onTap: () => _handle(context, BookAction.layoutOverride),
            ),
          if (showRemoveCache)
            ListTile(
              key: const Key('book_action_remove_cache'),
              leading: const Icon(Icons.cloud_off_outlined),
              title: Text(l10n.bookActionRemoveCache),
              onTap: () => _handle(context, BookAction.removeCache),
            ),
          ListTile(
            key: const Key('book_action_delete'),
            leading: const Icon(Icons.delete),
            title: Text(l10n.bookActionDelete),
            onTap: () => _handle(context, BookAction.delete),
          ),
        ],
      ),
    );
  }
}
