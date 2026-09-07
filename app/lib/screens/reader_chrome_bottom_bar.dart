import 'package:flutter/material.dart';

/// 閱讀器底部 Chrome 列（epic-38-reader-chrome-tts-redesign Issue 1，
/// spec.md §功能①②）：格式無關，三列固定結構——頁碼列（34dp，純顯示書名
/// ＋頁數/百分比）／跳頁列（56dp，內容由呼叫端建好傳入，見 [footer]）／
/// 選單列（64dp，書籤/劃線筆記/版面 3 顆恆常渲染、`onXxxTap` 為 `null`
/// 時顯示停用狀態；朗讀 1 顆 `onTtsTap` 為 `null` 時整格不渲染，因為 PDF
/// 目前結構性沒有 TTS 底層能力）。取代流式 EPUB／FXL 共用的 5 顆與 PDF
/// 獨立的 4 顆 `Positioned` 浮動圓鈕。
///
/// [footer] 由呼叫端已經算好（例如既有 `_buildFoliateEpubFooter()`
/// 回傳的 `ReaderFooter`，或 PDF 對應的等價寫法；尚無位置資訊時傳
/// `const SizedBox.shrink()`）——本 widget 不重新實作頁碼換算與空狀態
/// 判斷，避免與既有邏輯重複（見 `plans/plan-issue-1.md`「計劃範圍澄清」
/// 第 3 點）。
class ReaderChromeBottomBar extends StatelessWidget {
  final String bookTitle;
  final String pageProgressText;
  final Widget footer;
  final bool isBookmarked;
  final VoidCallback? onBookmarkTap;
  final VoidCallback? onAnnotationsTap;
  final VoidCallback? onLayoutTap;
  final VoidCallback? onTtsTap;
  final Color backgroundColor;
  final Color iconColor;
  final bool isEinkMode;

  const ReaderChromeBottomBar({
    super.key,
    required this.bookTitle,
    required this.pageProgressText,
    required this.footer,
    required this.isBookmarked,
    required this.onBookmarkTap,
    required this.onAnnotationsTap,
    required this.onLayoutTap,
    required this.onTtsTap,
    required this.backgroundColor,
    required this.iconColor,
    this.isEinkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final minSize = isEinkMode ? 56.0 : 48.0;
    final buttonStyle =
        IconButton.styleFrom(minimumSize: Size(minSize, minSize));
    return Material(
      color: backgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 34,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    bookTitle,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style:
                        TextStyle(color: iconColor, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  pageProgressText,
                  key: const Key('reader_chrome_page_info_text'),
                  style: TextStyle(color: iconColor),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
          SizedBox(height: 56, child: footer),
          SizedBox(
            height: 64,
            child: Row(
              children: [
                Expanded(
                  child: IconButton(
                    key: const Key('reader_chrome_bookmark_button'),
                    icon: Icon(
                      isBookmarked ? Icons.star : Icons.star_border,
                      color: iconColor,
                    ),
                    tooltip: isBookmarked ? '已加入此頁書籤' : '加入此頁書籤',
                    style: buttonStyle,
                    onPressed: onBookmarkTap,
                  ),
                ),
                Expanded(
                  child: IconButton(
                    key: const Key('reader_chrome_annotations_button'),
                    icon: Icon(Icons.edit_note, color: iconColor),
                    tooltip: '劃線筆記',
                    style: buttonStyle,
                    onPressed: onAnnotationsTap,
                  ),
                ),
                Expanded(
                  child: IconButton(
                    key: const Key('reader_chrome_layout_button'),
                    icon: Icon(Icons.format_size, color: iconColor),
                    tooltip: '版面',
                    style: buttonStyle,
                    onPressed: onLayoutTap,
                  ),
                ),
                if (onTtsTap != null)
                  Expanded(
                    child: IconButton(
                      key: const Key('reader_chrome_tts_button'),
                      icon: Icon(Icons.record_voice_over, color: iconColor),
                      tooltip: '朗讀',
                      style: buttonStyle,
                      onPressed: onTtsTap,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
