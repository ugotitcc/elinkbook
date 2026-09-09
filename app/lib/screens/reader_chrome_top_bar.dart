import 'package:flutter/material.dart';

/// 閱讀器頂部 Chrome 列（epic-38-reader-chrome-tts-redesign Issue 1，
/// spec.md §功能①）：格式無關，取代流式 EPUB／FXL／PDF 三格式各自獨立的
/// 頂部按鈕（返回／目錄）與已死亡的 `Scaffold.appBar`／`_buildAppBarActions()`。
///
/// **在閱讀畫面內預設永遠渲染，只受 PDF 裁切編輯模式（`!_cropEditModeActive`，
/// 呼叫端閘控，本 widget 不知道這個狀態）影響，不受 `_chromeVisible`
/// 影響**（查證 `prototype/eink_redesign_prototype.html:909-926` 確認頂部
/// 列從未被 `toggleReaderChrome()` 收合過，見 `spec.md`「已解決的規格矛盾
/// （新增）」第 2 項）——這樣使用者收起底部工具列後，仍能透過 ⬓ 按鈕本身
/// 把底部叫回來，不需要精確點中畫面正中央熱區。**例外**：「全螢幕模式」
/// 開啟時，呼叫端（`ReaderScreen`）會放大 `_chromeVisible` 收合的作用
/// 範圍，連本 widget 一併收合（2026-09-08 `/grill-with-docs` 使用者需求，
/// 見 CONTEXT.md「沉浸模式」詞條）——此時使用者只能透過畫面中央的選單
/// 熱區喚回，本 widget 本身消失後自然也拿不到 ⬓ 按鈕。
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
    // 前景色／停用前景色交給 IconButton.styleFrom 統一管理（審查修正
    // review-issue-1.md C-2）：底下每顆 IconButton 的 Icon 一律不再自帶
    // `color:`，讓 Material 依 onPressed 是否為 null 自動套用
    // foregroundColor／disabledForegroundColor——之前 Icon 自帶
    // `color: iconColor` 會覆蓋掉 IconTheme 提供的停用色，導致停用按鈕
    // 外觀與正常按鈕完全無異。
    final buttonStyle = IconButton.styleFrom(
      minimumSize: Size(minSize, minSize),
      foregroundColor: iconColor,
      disabledForegroundColor: iconColor.withValues(alpha: 0.38),
    );
    // 視覺還原（VISUAL_ANALYSIS.md）：Reference 截圖的頂部列下方有一條常駐
    // 分隔線，本元件不吃全域 `AppBarTheme`（不是用 `Scaffold.appBar` 建構），
    // 需自行從 `Theme.of(context)` 補上，維持與其他畫面 AppBar 一致的視覺。
    final borderColor = Theme.of(context).colorScheme.outline;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 2)),
      ),
      child: Material(
        color: backgroundColor,
        child: SizedBox(
          height: _height,
          child: Row(
            children: [
              IconButton(
                key: const Key('reader_chrome_back_button'),
                icon: const Icon(Icons.arrow_back),
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
                  style: TextStyle(
                    color: iconColor,
                    fontWeight: FontWeight.bold,
                  ),
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
                icon: const Icon(Icons.search),
                tooltip: '搜尋內文',
                style: buttonStyle,
                onPressed: onSearchTap,
              ),
              IconButton(
                key: const Key('reader_chrome_immersive_toggle_button'),
                icon: Icon(
                  isBottomChromeVisible ? Icons.dock : Icons.dock_outlined,
                ),
                tooltip: isBottomChromeVisible ? '隱藏工具列' : '顯示工具列',
                style: buttonStyle,
                onPressed: onToggleBottomChrome,
              ),
              IconButton(
                key: const Key('reader_chrome_toc_button'),
                icon: const Icon(Icons.menu_book),
                tooltip: '目錄',
                style: buttonStyle,
                onPressed: onTocTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
