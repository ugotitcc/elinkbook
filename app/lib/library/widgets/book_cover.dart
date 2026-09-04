import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/library_enums.dart';
import '../../theme/elink_tokens.dart';

/// 依書籍格式取得對應佔位圖示。
IconData bookFormatIcon(BookFileFormat format) {
  switch (format) {
    case BookFileFormat.epub:
      return Icons.menu_book;
    case BookFileFormat.pdf:
      return Icons.picture_as_pdf;
    case BookFileFormat.txt:
      return Icons.article;
    case BookFileFormat.azw3:
      return Icons.menu_book;
    case BookFileFormat.cbz:
      return Icons.auto_stories;
    case BookFileFormat.md:
      return Icons.article;
  }
}

/// 書籍封面：有 `coverPath` 且檔案存在時顯示圖片，否則以格式圖示佔位。
/// `existsSync()` 只是一次本機 stat 呼叫，成本低，不需要 FutureBuilder。
class BookCover extends StatelessWidget {
  final Book book;

  const BookCover({
    super.key,
    required this.book,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ElinkTokens>()!;
    final coverPath = book.coverPath;
    final cover = coverPath != null && File(coverPath).existsSync()
        ? Image.file(File(coverPath), fit: BoxFit.cover)
        : CoverPlaceholder(icon: bookFormatIcon(book.format), title: book.title);
    if (book.isDownloaded) return cover;
    return Stack(
      fit: StackFit.expand,
      children: [
        cover,
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            key: const Key('book_cover_cloud_badge'),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: tokens.badgeScrim,
              borderRadius: BorderRadius.circular(12),
            ),
            // 雲朵圖示前景維持寫死白色：badgeScrim 四套主題色值深淺不一，
            // 沒有對應的「badgeScrim 前景色」token（ElinkTokens 欄位已於
            // Issue 1 定案凍結），白色是唯一在四種背景上都可辨識的選擇。
            child: const Icon(Icons.cloud_outlined, size: 16, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// 封面佔位符：依格式圖示（或呼叫端傳入的固定圖示）＋書名文字微型縮略
/// （若有）＋E-Ink 模式下的 1.5dp 純黑實線外框（`DESIGN.md` §8.2）。圖示
/// 與文字大小依容器可用尺寸縮放（`LayoutBuilder`）——這顆元件被共用在
/// 差異極大的尺寸上：書架格狀卡片、48×64 列表列、`library_screen.dart`
/// `_GroupListTile` 內小到 32×48 的縮圖皆共用同一顆元件，固定寫死尺寸會
/// 在最小尺寸下擠爆。[title] 為 `null` 代表「這裡沒有對應的書」（拼貼格／
/// 列表列「不足 4 本」的空格佔位），此時仍渲染一行空字串文字列（而非整段
/// 省略），確保跟「某本書真的沒有封面圖」（[title] 非 null）的情況視覺
/// 佈局高度一致。
class CoverPlaceholder extends StatelessWidget {
  final IconData icon;
  final String? title;

  const CoverPlaceholder({super.key, required this.icon, this.title});

  /// 標題文字列的可用高度／寬度門檻——低於任一值不渲染文字，避免在極小
  /// 尺寸下文字被擠壓到無法閱讀（審查修正 I2：初版只檢查高度，極端窄長
  /// 容器──例如寬 24／高 60──高度門檻會通過但寬度連一個省略號都容不下，
  /// 見 reviews/review-plan-issue-9.md）。具體數值未經真機驗證，見計劃書
  /// Global Constraints。
  static const _titleRowMinHeight = 56.0;
  static const _titleRowMinWidth = 36.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<ElinkTokens>()!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortSide = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final iconSize = (shortSide * 0.4).clamp(16.0, 40.0).toDouble();
        final fontSize = (shortSide * 0.14).clamp(9.0, 12.0).toDouble();
        final showTitle = constraints.maxHeight >= _titleRowMinHeight &&
            constraints.maxWidth >= _titleRowMinWidth;

        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: tokens.coverPlaceholder,
            border: tokens.isEink
                ? Border.all(color: colorScheme.onSurface, width: 1.5)
                : null,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconSize, color: colorScheme.onSurfaceVariant),
                if (showTitle) ...[
                  const SizedBox(height: 4),
                  // 審查修正 I1：E-Ink 模式的 1.5dp 外框跟文字之間需要留一點
                  // 呼吸空間，否則長書名的省略號會直接貼在黑框上，在電子紙
                  // 高對比顯示下辨識度變差（見 reviews/review-plan-issue-9.md）。
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Text(
                      title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: fontSize,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
