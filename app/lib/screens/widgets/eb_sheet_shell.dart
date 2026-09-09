import 'package:flutter/material.dart';

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

  const EBSheetShell({
    super.key,
    required this.title,
    required this.child,
    this.isEinkMode = false,
    this.actions = const [],
  });

  /// `isEinkMode: true` 時用 `AnimationStyle.noAnimation`（`duration`／
  /// `reverseDuration` 皆為 `Duration.zero`）達成「瞬間具現化顯示」
  /// （`DESIGN.md` §10.2）；`showModalBottomSheet` 的 `sheetAnimationStyle`
  /// 參數為 Flutter 3.41+ 原生支援（已查證 `bottom_sheet.dart` SDK 原始
  /// 碼），不需要自建 `AnimationController`（自建需要 `TickerProvider`，
  /// 靜態方法無法取得，且呼叫端須負責 dispose，有記憶體洩漏風險）。
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required WidgetBuilder builder,
    bool isEinkMode = false,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: isEinkMode ? AnimationStyle.noAnimation : null,
      builder: (context) => EBSheetShell(
        title: title,
        isEinkMode: isEinkMode,
        child: Builder(builder: builder),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: ConstrainedBox(
        // `DESIGN.md#L235`：「最大高度」限制為螢幕高度的 50% 至 85%，指的
        // 是抽屜高度的上限箝制，不是任何抽屜都要強制撐滿至少 50% 螢幕高
        // （【review-plan-issue-4.md I-2】內容少時若寫死 minHeight: 0.5
        // 會在平板等大螢幕上產生巨大無意義留白）；超出上限時內部改採
        // ListView 滾動（由呼叫端的 child 自行決定，本元件不強制）。
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.85,
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
                    tooltip: '關閉',
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
  }
}
