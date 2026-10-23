import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 底部抽屜外殼基礎元件（`DESIGN.md` §10）：拖曳把手＋標題＋右上角關閉
/// 按鈕＋高度限制，本 Epic 首次落地、只給 `BookActionSheet` 使用（既有
/// `NotesBottomSheet`／閱讀器內既有 Bottom Sheet 不在本次改用範圍，見
/// plans/plan-issue-4.md Global Constraints）。
class EBSheetShell extends StatelessWidget {
  final String title;
  final Widget child;
  final bool isEinkMode;

  /// 標題列右側、關閉按鈕左側的額外動作按鈕（例如「筆記」面板的「導出為
  /// Markdown」）。預設空陣列，不影響既有呼叫端（`BookActionSheet`）的
  /// 標題列版面。
  final List<Widget> actions;

  /// 抽屜高度上限佔螢幕高度的比例，預設 85%。
  final double maxHeightFactor;

  const EBSheetShell({
    super.key,
    required this.title,
    required this.child,
    this.isEinkMode = false,
    this.actions = const [],
    this.maxHeightFactor = 0.85,
  });

  /// `isEinkMode: true` 時用 `AnimationStyle.noAnimation`（`duration`／
  /// `reverseDuration` 皆為 `Duration.zero`）達成「瞬間具現化顯示」
  /// （`DESIGN.md` §10.2）；`showModalBottomSheet` 的 `sheetAnimationStyle`
  /// 參數為 Flutter 3.41+ 原生支援（已查證 `bottom_sheet.dart` SDK 原始
  /// 碼），不需要自建 `AnimationController`（自建需要 `TickerProvider`，
  /// 靜態方法無法取得，且呼叫端須負責 dispose，有記憶體洩漏風險）。
  ///
  /// E-Ink 模式下傳 `elevation: 0` 與 `shape: const RoundedRectangleBorder()`
  /// （直角、無陰影），避免 Material 3 預設陰影與頂部圓角干擾非對稱外框；
  /// 非 E-Ink 模式維持 `null` 沿用主題預設。
  ///
  /// [barrierColor] 原樣傳給 `showModalBottomSheet`；`null` 維持 Flutter
  /// 預設遮罩。閱讀器內的呼叫端比照 `ReaderScreen._showThemedModalBottomSheet`
  /// 的規則，深色主題與 E-Ink 傳 `Colors.transparent`（見
  /// `dictionary_lookup_sheet.dart` 的 `show`）。
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required WidgetBuilder builder,
    bool isEinkMode = false,
    Color? barrierColor,
    double maxHeightFactor = 0.85,
  }) {
    // 深色的外框是直角（見 [build]），面板仍是預設圓角時外框四角會突出，所以
    // 深色也改直角；陰影在深色下本來就看不見，維持預設。
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      barrierColor: barrierColor,
      sheetAnimationStyle: isEinkMode ? AnimationStyle.noAnimation : null,
      elevation: isEinkMode ? 0 : null,
      shape: isEinkMode || isDark ? const RoundedRectangleBorder() : null,
      builder: (context) => EBSheetShell(
        title: title,
        isEinkMode: isEinkMode,
        maxHeightFactor: maxHeightFactor,
        child: Builder(builder: builder),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final content = SafeArea(
      child: ConstrainedBox(
        // `DESIGN.md#L235`：「最大高度」限制為螢幕高度的 50% 至 85%，指的
        // 是抽屜高度的上限箝制，不是任何抽屜都要強制撐滿至少 50% 螢幕高
        // （【review-plan-issue-4.md I-2】內容少時若寫死 minHeight: 0.5
        // 會在平板等大螢幕上產生巨大無意義留白）；超出上限時內部改採
        // ListView 滾動（由呼叫端的 child 自行決定，本元件不強制）。
        constraints: BoxConstraints(
          maxHeight: screenHeight * maxHeightFactor,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              key: const Key('eb_sheet_shell_drag_handle'),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                // `EBRadius` 尚未落地（見 Global Constraints），直接寫
                // 字面值。
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ...actions,
                  IconButton(
                    key: const Key('eb_sheet_shell_close_button'),
                    icon: const Icon(Icons.close),
                    tooltip: AppLocalizations.of(context)?.close ?? '關閉',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );

    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    if (isEinkMode || isDark) {
      // 深色主題的 `outline` 與 `surface` 幾乎同色（約 1.3:1），電子紙上外框
      // 看不見，真機上面板與書頁糊在一起；深色改用高對比的 `onSurfaceVariant`
      // 灰色。E-Ink 維持 `outline`（E-Ink 主題自己的 `outline` 是純黑）。
      final borderColor =
          isEinkMode ? colorScheme.outline : colorScheme.onSurfaceVariant;
      return DecoratedBox(
        key: Key(isEinkMode
            ? 'eb_sheet_shell_eink_border'
            : 'eb_sheet_shell_dark_border'),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: borderColor, width: 2),
            left: BorderSide(color: borderColor, width: 2),
            right: BorderSide(color: borderColor, width: 2),
          ),
        ),
        child: content,
      );
    }

    return content;
  }
}
