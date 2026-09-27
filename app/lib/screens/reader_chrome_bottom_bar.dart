import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

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
///
/// [onTocTap]（2026-09-10 新增）：選單列最左側「目錄」按鈕，原本收在
/// `ReaderChromeTopBar` 最右邊，因為跟書籤/劃線筆記/版面同屬「內容操作」
/// 動作，改移到本列、書籤按鈕左側，理由與完整狀態表見 `CONTEXT.md`
/// 「Chrome Bar」詞條。`null` 時顯示為停用狀態，比照既有 `onXxxTap` 慣例。
class ReaderChromeBottomBar extends StatelessWidget {
  final String bookTitle;
  final String pageProgressText;
  final Widget footer;
  final VoidCallback? onTocTap;
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
    required this.onTocTap,
    required this.isBookmarked,
    required this.onBookmarkTap,
    required this.onAnnotationsTap,
    required this.onLayoutTap,
    required this.onTtsTap,
    required this.backgroundColor,
    required this.iconColor,
    this.isEinkMode = false,
  });

  /// E-Ink 模式下本列是「反白」配色（黑底白字：`backgroundColor` 是
  /// `onSurface`、`iconColor` 是 `surface`，見 `reader_screen.dart`
  /// `_themedFabBackgroundColor`）。呼叫端傳進來的 [footer]（跳頁列的
  /// 頁碼文字／輸入框／Slider）卻沿用全域主題的黑色前景，黑畫在黑上幾乎
  /// 看不到（2026-09-28 Mobiscribe 真機回報）。這裡把 footer 子樹的前景色
  /// 統一改成 [iconColor]。Slider 未讀部分用不透明的 [Colors.grey]，
  /// 不用 alpha 半透明——電子紙灰階抖動下半透明色會糊掉（理由同
  /// `reader_screen.dart` `_themedTtsDisabledIconColor`）。
  Widget _einkForeground(BuildContext context, Widget child) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        // TextField 的文字色取自 textTheme（建主題時就已寫死顏色），
        // 底線／游標則取自 colorScheme，兩邊都要換。
        textTheme: theme.textTheme.apply(
          bodyColor: iconColor,
          displayColor: iconColor,
        ),
        colorScheme: theme.colorScheme.copyWith(
          primary: iconColor,
          onSurface: iconColor,
          onSurfaceVariant: iconColor,
        ),
        sliderTheme: theme.sliderTheme.copyWith(
          activeTrackColor: iconColor,
          thumbColor: iconColor,
          inactiveTrackColor: Colors.grey,
          activeTickMarkColor: iconColor,
          inactiveTickMarkColor: Colors.grey,
          valueIndicatorColor: iconColor,
          valueIndicatorTextStyle: TextStyle(color: backgroundColor),
        ),
      ),
      // 一般 Text 吃的是 DefaultTextStyle，不會跟著上面 colorScheme 變。
      child: DefaultTextStyle.merge(
        style: TextStyle(color: iconColor),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final minSize = isEinkMode ? 56.0 : 48.0;
    // 前景色／停用前景色交給 IconButton.styleFrom 統一管理（審查修正
    // review-issue-1.md C-2）：底下每顆 IconButton 的 Icon 一律不再自帶
    // `color:`，讓 Material 依 onXxxTap 是否為 null 自動套用
    // foregroundColor／disabledForegroundColor——之前 Icon 自帶
    // `color: iconColor` 會覆蓋掉 IconTheme 提供的停用色，導致停用按鈕
    // 外觀與正常按鈕完全無異。
    final buttonStyle = IconButton.styleFrom(
      minimumSize: Size(minSize, minSize),
      foregroundColor: iconColor,
      disabledForegroundColor: iconColor.withValues(alpha: 0.38),
    );
    // 視覺還原（VISUAL_ANALYSIS.md）：Reference 截圖三列（頁碼列／跳頁列／
    // 選單列）之間、以及選單列 4 顆按鈕之間都有分隔線，本元件先前完全沒有
    // 邊框；本身不吃全域 AppBarTheme（不是用 Scaffold.appBar 建構），
    // 需自行從 Theme.of(context) 補上。
    final borderColor = Theme.of(context).colorScheme.outline;
    Widget verticalDivider(Widget child) => DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: borderColor, width: 1)),
      ),
      child: child,
    );
    return Material(
      color: backgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor, width: 2)),
            ),
            child: SizedBox(
              height: 34,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      bookTitle,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: iconColor,
                        fontWeight: FontWeight.bold,
                      ),
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
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor, width: 1)),
            ),
            child: SizedBox(
              height: 56,
              child: isEinkMode ? _einkForeground(context, footer) : footer,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor, width: 2)),
            ),
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  Expanded(
                    child: IconButton(
                      key: const Key('reader_chrome_toc_button'),
                      icon: const Icon(Icons.menu_book),
                      tooltip: l10n.readerTocTooltip,
                      style: buttonStyle,
                      onPressed: onTocTap,
                    ),
                  ),
                  Expanded(
                    child: verticalDivider(
                      IconButton(
                        key: const Key('reader_chrome_bookmark_button'),
                        icon: Icon(isBookmarked ? Icons.star : Icons.star_border),
                        tooltip: isBookmarked ? l10n.readerBookmarkAddedTooltip : l10n.readerBookmarkAddTooltip,
                        style: buttonStyle,
                        onPressed: onBookmarkTap,
                      ),
                    ),
                  ),
                  Expanded(
                    child: verticalDivider(
                      IconButton(
                        key: const Key('reader_chrome_annotations_button'),
                        icon: const Icon(Icons.edit_note),
                        tooltip: l10n.readerAnnotationsTooltip,
                        style: buttonStyle,
                        onPressed: onAnnotationsTap,
                      ),
                    ),
                  ),
                  Expanded(
                    child: verticalDivider(
                      IconButton(
                        key: const Key('reader_chrome_layout_button'),
                        icon: const Icon(Icons.format_size),
                        tooltip: l10n.readerLayoutTooltip,
                        style: buttonStyle,
                        onPressed: onLayoutTap,
                      ),
                    ),
                  ),
                  if (onTtsTap != null)
                    Expanded(
                      child: verticalDivider(
                        IconButton(
                          key: const Key('reader_chrome_tts_button'),
                          icon: const Icon(Icons.record_voice_over),
                          tooltip: l10n.readerTtsTooltip,
                          style: buttonStyle,
                          onPressed: onTtsTap,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
