import 'dart:ui';

import 'percent_rect.dart';

/// 浮動標註工具列的估計高度（epic-27-reader-device-compat Issue 11 雙列
/// 版面：兩列各 48dp＋外層 Padding 上下各 4dp）。
const double kAnnotationToolbarHeight = 104.0;

/// 工具列與選取範圍之間的間距。
const double kAnnotationToolbarGap = 8.0;

/// 工具列的估計寬度（兩列較寬者 5 顆 48dp 按鈕＝240，加上左右 Padding
/// 各 8dp）。
const double kAnnotationToolbarWidth = 256.0;

/// 浮動標註工具列的垂直位置：優先貼在選取範圍上方，上方空間不足時改貼
/// 下方，並保證不超出畫面。輸入的 [anchorRect] 是相對整個 widget 的百分比
/// 矩形——EPUB 傳 `EpubSelectionInfo.rect`，PDF 傳 `widgetRect`（含
/// letterbox 留白，避免工具列位置隨留白量偏移）。
double annotationToolbarTop({
  required PercentRect anchorRect,
  required Size size,
}) {
  final topAboveSelection =
      anchorRect.top * size.height - kAnnotationToolbarHeight - kAnnotationToolbarGap;
  if (topAboveSelection >= 0) return topAboveSelection;
  final belowSelection = anchorRect.bottom * size.height + kAnnotationToolbarGap;
  return belowSelection.clamp(0.0, size.height - kAnnotationToolbarHeight);
}

/// 浮動標註工具列的水平位置：以選取範圍左緣對齊，clamp 到不超出畫面右緣。
double annotationToolbarLeft({
  required PercentRect anchorRect,
  required Size size,
}) {
  return (anchorRect.left * size.width)
      .clamp(0.0, size.width - kAnnotationToolbarWidth);
}
