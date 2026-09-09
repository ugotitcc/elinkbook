import 'package:flutter/material.dart';

/// 專為閱讀器設定面板設計的高對比選項單選元件（支援 E-Ink 黑白反轉）。
class ReaderOptionTile<T> extends StatelessWidget {
  final Key? itemKey;
  final T value;
  final T groupValue;
  final IconData icon;
  final String? label;
  final String tooltip;
  final ValueChanged<T> onSelected;
  final VisualDensity visualDensity;
  final double iconSize;
  final double labelFontSize;
  final bool forceUnselected;

  const ReaderOptionTile({
    super.key,
    this.itemKey,
    required this.value,
    required this.groupValue,
    required this.icon,
    this.label,
    required this.tooltip,
    required this.onSelected,
    this.visualDensity = VisualDensity.standard,
    this.iconSize = 20,
    this.labelFontSize = 13,
    this.forceUnselected = false,
  });

  @override
  Widget build(BuildContext context) {
    final selected = !forceUnselected && value == groupValue;
    final theme = Theme.of(context);
    final isEink =
        theme.colorScheme.primary == Colors.black &&
        theme.scaffoldBackgroundColor == Colors.white;

    final Color backgroundColor;
    final Color foregroundColor;
    final Border border;

    if (isEink) {
      backgroundColor = selected ? Colors.black : Colors.white;
      foregroundColor = selected ? Colors.white : Colors.black;
      border = Border.all(color: Colors.black, width: 1.5);
    } else {
      // 視覺還原（VISUAL_ANALYSIS.md）：Reference 截圖的選中態是「主色實心
      // 填滿＋onPrimary 白字」（比照原型 `bg-black`→`primary` 的映射），
      // 不是 M3 慣用的淺色 Tonal Container 配色，故改用 primary／onPrimary
      // 而非 primaryContainer／onPrimaryContainer。
      backgroundColor = selected
          ? theme.colorScheme.primary
          : theme.colorScheme.surface;
      foregroundColor = selected
          ? theme.colorScheme.onPrimary
          : theme.colorScheme.onSurfaceVariant;
      border = Border.all(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.outline.withValues(alpha: 0.35),
        width: selected ? 1.5 : 1.0,
      );
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: foregroundColor),
        if (label != null) ...[
          const SizedBox(width: 6),
          Text(
            label!,
            style: TextStyle(
              fontSize: labelFontSize,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: foregroundColor,
            ),
          ),
        ],
      ],
    );

    // 【審查修正 Important】key 掛在帶 BoxDecoration 的 Container 上（而非
    // InkWell）：tester.tap(find.byKey(...)) 對 Container 一樣有效（觸控
    // 事件依 hit-test 順序傳給祖先鏈上的 InkWell），但測試斷言外觀時可以
    // 直接 tester.widget<Container>(find.byKey(...)) 精確取得，不需要
    // find.descendant(...).first 這種依賴「子樹第幾個 Container」的脆弱
    // 寫法（見 reviews/review-plan-issue-5-8.md Issue 6 Important #2）。
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(value),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            key: itemKey,
            padding: EdgeInsets.symmetric(
              horizontal: label != null ? 10 : 8,
              vertical: visualDensity == VisualDensity.compact ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: border,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
