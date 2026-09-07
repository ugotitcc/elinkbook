import 'package:flutter/material.dart';

/// 閱讀器頂部 Chrome 列（epic-38-reader-chrome-tts-redesign Issue 1，
/// spec.md §功能①）：格式無關，取代流式 EPUB／FXL／PDF 三格式各自獨立的
/// 頂部按鈕（返回／目錄）與已死亡的 `Scaffold.appBar`／`_buildAppBarActions()`。
///
/// **在閱讀畫面內永遠渲染，只受 PDF 裁切編輯模式（`!_cropEditModeActive`，
/// 呼叫端閘控，本 widget 不知道這個狀態）影響，不受 `_chromeVisible`
/// 影響**（查證 `prototype/eink_redesign_prototype.html:909-926` 確認頂部
/// 列從未被 `toggleReaderChrome()` 收合過，見 `spec.md`「已解決的規格矛盾
/// （新增）」第 2 項）——這樣使用者收起底部工具列後，仍能透過 ⬓ 按鈕本身
/// 把底部叫回來，不需要精確點中畫面正中央熱區。
///
/// [chapterTitle] 由呼叫端算好完整文字（含找不到章節時的「閱讀器」回退
/// 值）；[onTocTap] 為 `null` 時目錄按鈕顯示為停用狀態（呼叫端既有的
/// `_tocLoaded`／`_pdfTocLoaded` 防呆條件）；[showTtsIndicator] 為 `true`
/// 時在標題右側顯示一個小喇叭圖示（本 Issue 固定傳 `false`，真實邏輯留給
/// Issue 2 的 `TtsPanel` 重構）。
class ReaderChromeTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final String chapterTitle;
  final VoidCallback onSearchTap;
  final bool isBottomChromeVisible;
  final VoidCallback onToggleBottomChrome;
  final VoidCallback? onTocTap;
  final bool showTtsIndicator;
  final Color backgroundColor;
  final Color iconColor;
  final bool isEinkMode;

  const ReaderChromeTopBar({
    super.key,
    required this.onBack,
    required this.chapterTitle,
    required this.onSearchTap,
    required this.isBottomChromeVisible,
    required this.onToggleBottomChrome,
    required this.onTocTap,
    required this.showTtsIndicator,
    required this.backgroundColor,
    required this.iconColor,
    this.isEinkMode = false,
  });

  static const double _height = 56;

  @override
  Widget build(BuildContext context) {
    // DESIGN.md §7.2：一般模式最小觸控目標 48dp、E-Ink 模式 56dp。
    final minSize = isEinkMode ? 56.0 : 48.0;
    final buttonStyle =
        IconButton.styleFrom(minimumSize: Size(minSize, minSize));
    return Material(
      color: backgroundColor,
      child: SizedBox(
        height: _height,
        child: Row(
          children: [
            IconButton(
              key: const Key('reader_chrome_back_button'),
              icon: Icon(Icons.arrow_back, color: iconColor),
              tooltip: '返回',
              style: buttonStyle,
              onPressed: onBack,
            ),
            Expanded(
              child: Text(
                key: const Key('reader_chrome_title'),
                chapterTitle,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(color: iconColor, fontWeight: FontWeight.bold),
              ),
            ),
            if (showTtsIndicator)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.volume_up,
                  key: const Key('reader_chrome_tts_indicator_icon'),
                  color: iconColor,
                ),
              ),
            IconButton(
              key: const Key('reader_chrome_search_button'),
              icon: Icon(Icons.search, color: iconColor),
              tooltip: '搜尋內文',
              style: buttonStyle,
              onPressed: onSearchTap,
            ),
            IconButton(
              key: const Key('reader_chrome_immersive_toggle_button'),
              icon: Icon(
                isBottomChromeVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: iconColor,
              ),
              tooltip: isBottomChromeVisible ? '隱藏工具列' : '顯示工具列',
              style: buttonStyle,
              onPressed: onToggleBottomChrome,
            ),
            IconButton(
              key: const Key('reader_chrome_toc_button'),
              icon: Icon(Icons.menu_book, color: iconColor),
              tooltip: '目錄',
              style: buttonStyle,
              onPressed: onTocTap,
            ),
          ],
        ),
      ),
    );
  }
}
