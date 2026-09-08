import 'package:flutter/material.dart';

import 'reader_option_tile.dart';

/// 單選晶片群組的其中一個選項（epic-39-layout-settings-redesign Issue 1，
/// spec.md §2）。[onTap] 非 null 時代表這是「動作型」項目（例如 PDF 裁切
/// 分頁的「手動選區」：點擊只觸發外部動作、不代表選中一個可選值）——
/// 點擊時只呼叫 [onTap]，不呼叫 [EBOptionChipGroup.onSelected]，且該
/// chip 恆為未選中樣式（透過 [ReaderOptionTile.forceUnselected]，不參與
/// groupValue 比對）。
class EBOptionChipItem<T> {
  final Key? itemKey;
  final T value;
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  const EBOptionChipItem({
    this.itemKey,
    required this.value,
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onTap,
  });
}

/// 取代分散在三個版面設定 Bottom Sheet 共 13 處「`Wrap` 包一組
/// `ReaderOptionTile`」的重複寫法（spec.md §2）：依可用寬度連續縮放圖示/
/// 文字大小，寬度極窄時只顯示圖示。**寬度縮放依容器絕對寬度**（不除以
/// `items.length`）——除以項目數會與 `Wrap` 本身的折行特性衝突：6 選項
/// 群組在常規手機寬度下會被誤判為「永遠過窄」，但 `Wrap` 實際上會自動
/// 折成兩行，每行 3 顆的可用寬度其實綽綽有餘（見 spec.md 審查回應 I2）。
class EBOptionChipGroup<T> extends StatelessWidget {
  static const double _maxWidthForMinSize = 240;
  static const double _minWidthForMaxSize = 360;
  static const double _hideLabelWidth = 200;
  static const double _minIconSize = 16;
  static const double _maxIconSize = 20;
  static const double _minLabelFontSize = 11;
  static const double _maxLabelFontSize = 13;

  final List<EBOptionChipItem<T>> items;
  final T groupValue;
  final ValueChanged<T> onSelected;
  final VisualDensity visualDensity;

  const EBOptionChipGroup({
    super.key,
    required this.items,
    required this.groupValue,
    required this.onSelected,
    this.visualDensity = VisualDensity.standard,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final clampedWidth =
            maxWidth.clamp(_maxWidthForMinSize, _minWidthForMaxSize);
        final t = (clampedWidth - _maxWidthForMinSize) /
            (_minWidthForMaxSize - _maxWidthForMinSize);
        final iconSize = _minIconSize + (_maxIconSize - _minIconSize) * t;
        final labelFontSize =
            _minLabelFontSize + (_maxLabelFontSize - _minLabelFontSize) * t;
        final showLabel = maxWidth >= _hideLabelWidth;

        return Wrap(
          spacing: 4,
          // 審查修正 M1（review-plan-issue-1.md）：Wrap 的 runSpacing 預設
          // 為 0，6 選項群組折成兩行時，第二行晶片會與第一行緊貼、垂直
          // 無間距，補上與 spacing 一致的 4，讓水平/垂直留白一致。
          runSpacing: 4,
          children: items.map((item) {
            final isAction = item.onTap != null;
            return ReaderOptionTile<T>(
              itemKey: item.itemKey,
              value: item.value,
              groupValue: groupValue,
              icon: item.icon,
              label: showLabel ? item.label : null,
              tooltip: item.tooltip,
              iconSize: iconSize,
              labelFontSize: labelFontSize,
              visualDensity: visualDensity,
              forceUnselected: isAction,
              onSelected: (v) {
                if (isAction) {
                  item.onTap!();
                } else {
                  onSelected(v);
                }
              },
            );
          }).toList(),
        );
      },
    );
  }
}
