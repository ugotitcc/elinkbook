import 'package:flutter/material.dart';

import '../library/models/book.dart';

/// 單書「⋮」動作選單內容（`DESIGN.md` §11.3／`spec.md` 功能④）：純呈現，
/// 不知道各選項實際邏輯，五個 callback 由呼叫端（`library_screen.dart`）
/// 提供。每個選項點擊後先關閉外層 Sheet 再呼叫對應 callback（比照既有
/// Dialog／Sheet 選項慣例，避免 callback 內再彈出的新 Dialog 跟尚未關閉的
/// Sheet 疊在一起）。
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

  final VoidCallback onShowDetails;
  final VoidCallback onMove;
  final VoidCallback onLayoutOverride;
  final VoidCallback? onRemoveCache; // showRemoveCache == false 時不會被觸發
  final VoidCallback onDelete;

  const BookActionSheet({
    super.key,
    required this.book,
    required this.showRemoveCache,
    required this.showLayoutOverride,
    required this.onShowDetails,
    required this.onMove,
    required this.onLayoutOverride,
    required this.onRemoveCache,
    required this.onDelete,
  });

  void _handle(BuildContext context, VoidCallback? callback) {
    Navigator.of(context).pop();
    callback?.call();
  }

  @override
  Widget build(BuildContext context) {
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
            title: const Text('詳細資料'),
            onTap: () => _handle(context, onShowDetails),
          ),
          ListTile(
            key: const Key('book_action_move'),
            leading: const Icon(Icons.drive_file_move),
            title: const Text('移動'),
            onTap: () => _handle(context, onMove),
          ),
          if (showLayoutOverride)
            ListTile(
              key: const Key('book_action_layout_override'),
              leading: const Icon(Icons.view_column_outlined),
              title: const Text('版面覆寫'),
              onTap: () => _handle(context, onLayoutOverride),
            ),
          if (showRemoveCache)
            ListTile(
              key: const Key('book_action_remove_cache'),
              leading: const Icon(Icons.cloud_off_outlined),
              title: const Text('移除快取'),
              onTap: () => _handle(context, onRemoveCache),
            ),
          ListTile(
            key: const Key('book_action_delete'),
            leading: const Icon(Icons.delete),
            title: const Text('刪除'),
            onTap: () => _handle(context, onDelete),
          ),
        ],
      ),
    );
  }
}
