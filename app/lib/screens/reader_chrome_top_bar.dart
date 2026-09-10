import 'package:flutter/material.dart';

/// 閱讀器頂部 Chrome 列（epic-38-reader-chrome-tts-redesign Issue 1；
/// 2026-09-10 修正：拆分頁首／工具列為兩組各自獨立的顯示開關，取代原本
/// 「整條列一起顯示/隱藏、且跟全螢幕模式掛勾」的設計，理由與完整狀態表見
/// `CONTEXT.md`「Chrome Bar」詞條）：格式無關，取代流式 EPUB／FXL／PDF
/// 三格式各自獨立的頂部按鈕（返回／目錄）與已死亡的 `Scaffold.appBar`／
/// `_buildAppBarActions()`。
///
/// 內部分成三組互相獨立的元素：
/// - **頁首**（[chapterTitle] 文字）：由 [isHeaderVisible] 控制（呼叫端依
///   `showHeader` 偏好決定）。跟 [isToolbarVisible]、全螢幕模式完全無關——
///   `showHeader` 關閉時頁首文字永遠不顯示；開啟時不論工具列收合與否都
///   常駐顯示。
/// - **工具列**（返回／搜尋／⬓ 三顆按鈕）：由 [isToolbarVisible] 控制
///   （呼叫端依 `_chromeVisible`，即「沉浸模式」收合狀態決定）。跟全螢幕
///   模式無關——全螢幕模式只負責 Android 系統列（狀態列/導覽列），不影響
///   本列任何元素。**已知取捨**：收合時 ⬓ 按鈕本身也會一併消失，使用者
///   之後只能靠畫面中央的選單熱區把工具列叫回來，不再能直接點 ⬓（此為
///   本次修正的刻意決定，非疏漏）。
/// - **TTS 指示**（[showTtsIndicator]）：獨立於上述兩組，語意不變（呼叫端
///   仍傳 `_isTtsActive && !_chromeVisible`）——工具列收合、朗讀仍在背景
///   進行時顯示，提醒使用者朗讀沒有停止。
///
/// 三組全為 `false` 時本 widget 回傳零高度 `SizedBox.shrink()`，完全不佔
/// 版面。各開關組合下實際顯示哪些項目，完整 N×M 狀態表見 `CONTEXT.md`
/// 「Chrome Bar」詞條。
///
/// **目錄按鈕已移除**（2026-09-10）：改移至 `ReaderChromeBottomBar` 選單列
/// 「書籤」按鈕左側——目錄跟書籤/劃線筆記/版面同屬「內容操作」動作，收在
/// 同一列較符合使用者心智模型。
///
/// [chapterTitle] 由呼叫端算好完整文字（含找不到章節時的回退值）；標題本身
/// 不可點擊。
class ReaderChromeTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final String chapterTitle;
  final VoidCallback onSearchTap;
  final bool isHeaderVisible;
  final bool isToolbarVisible;
  final bool isBottomChromeVisible;
  final VoidCallback onToggleBottomChrome;
  final bool showTtsIndicator;
  final Color backgroundColor;
  final Color iconColor;
  final bool isEinkMode;

  const ReaderChromeTopBar({
    super.key,
    required this.onBack,
    required this.chapterTitle,
    required this.onSearchTap,
    required this.isHeaderVisible,
    required this.isToolbarVisible,
    required this.isBottomChromeVisible,
    required this.onToggleBottomChrome,
    required this.showTtsIndicator,
    required this.backgroundColor,
    required this.iconColor,
    this.isEinkMode = false,
  });

  static const double _height = 56;

  @override
  Widget build(BuildContext context) {
    // 三組皆不需要顯示時整個不佔版面（全沉浸體驗）。
    if (!isHeaderVisible && !isToolbarVisible && !showTtsIndicator) {
      return const SizedBox.shrink();
    }
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
              if (isToolbarVisible)
                IconButton(
                  key: const Key('reader_chrome_back_button'),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '返回',
                  style: buttonStyle,
                  onPressed: onBack,
                ),
              Expanded(
                child: isHeaderVisible
                    ? Text(
                        key: const Key('reader_chrome_title'),
                        chapterTitle,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          color: iconColor,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : const SizedBox.shrink(),
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
              if (isToolbarVisible) ...[
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}
