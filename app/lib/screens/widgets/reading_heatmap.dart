// app/lib/screens/widgets/reading_heatmap.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../stats/heatmap_grid.dart';
import '../../stats/reading_duration_format.dart';
import '../../theme/elink_tokens.dart';

/// 方格邊長／間距／週欄間距（取自 epic.md Issue 1 原型定案值）。
const double kHeatmapCellSize = 16;
const double kHeatmapCellGap = 3;
const double kHeatmapPitch = kHeatmapCellSize + kHeatmapCellGap;

/// 月份標籤列高度，及其與方格區的間距；星期欄頂端以兩者相加的高度對齊。
const double _kMonthRowHeight = 14;
const double _kMonthToGridGap = 3;
const double _kGridTop = _kMonthRowHeight + _kMonthToGridGap;

/// 捲動容器左、右、下留白：選取外框最寬外擴 4px（E-Ink：偏移 1＋線寬 3），
/// 留白避免最右下角的「今天」被裁掉外框。上方不留，才能與左側星期欄垂直對齊。
const double _kScrollPadding = 4;

/// 貢獻圖方格的紋理（E-Ink 下不靠色相，用紋理輔助區分級別）。
enum HeatmapTexture { none, dots, diagonal, cross, solid }

/// 級別 → 紋理：0 留白、1 網點、2 單向斜線、3 交叉斜線、4 實心
/// （epic.md Issue 1 定案）。
HeatmapTexture heatmapTextureForLevel(int level) => switch (level) {
      1 => HeatmapTexture.dots,
      2 => HeatmapTexture.diagonal,
      3 => HeatmapTexture.cross,
      4 => HeatmapTexture.solid,
      _ => HeatmapTexture.none,
    };

/// 繪製單一方格。非 E-Ink：圓角 2px 純色。E-Ink：直角、Token 灰階底、
/// 依級別疊黑色紋理，最外圈畫 1px 黑框（不畫在紋理之下，避免被蓋掉）。
class HeatmapCellPainter extends CustomPainter {
  final int level;
  final Color fillColor;
  final bool isEink;

  /// 紋理與外框顏色（E-Ink 下即黑色）。
  final Color inkColor;

  const HeatmapCellPainter({
    required this.level,
    required this.fillColor,
    required this.isEink,
    required this.inkColor,
  });

  factory HeatmapCellPainter.of(ThemeData theme, int level) {
    final tokens = theme.extension<ElinkTokens>()!;
    return HeatmapCellPainter(
      level: level,
      fillColor: tokens.heatmapLevelColor(level),
      isEink: tokens.isEink,
      inkColor: theme.colorScheme.onSurface,
    );
  }

  /// 目前實際會畫出的紋理（非 E-Ink 恆為 [HeatmapTexture.none]）。
  HeatmapTexture get texture =>
      isEink ? heatmapTextureForLevel(level) : HeatmapTexture.none;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fill = Paint()..color = fillColor;
    if (!isEink) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        fill,
      );
      return;
    }

    canvas.drawRect(rect, fill);
    canvas.save();
    canvas.clipRect(rect.deflate(1));
    switch (texture) {
      case HeatmapTexture.dots:
        // 4px 週期的 1px 圓點
        final dot = Paint()..color = inkColor;
        for (var x = 2.0; x < size.width; x += 4) {
          for (var y = 2.0; y < size.height; y += 4) {
            canvas.drawCircle(Offset(x, y), 0.75, dot);
          }
        }
      case HeatmapTexture.diagonal:
        _drawDiagonals(canvas, size, rising: true, strokeWidth: 1);
      case HeatmapTexture.cross:
        _drawDiagonals(canvas, size, rising: true, strokeWidth: 1.5);
        _drawDiagonals(canvas, size, rising: false, strokeWidth: 1.5);
      case HeatmapTexture.none:
      case HeatmapTexture.solid:
        break;
    }
    canvas.restore();

    canvas.drawRect(
      rect.deflate(0.5),
      Paint()
        ..color = inkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// 45° 斜線，4px 週期；[rising] 為 true 畫「／」，否則畫「＼」。
  void _drawDiagonals(
    Canvas canvas,
    Size size, {
    required bool rising,
    required double strokeWidth,
  }) {
    final paint = Paint()
      ..color = inkColor
      ..strokeWidth = strokeWidth;
    for (var k = -size.height; k < size.width; k += 4) {
      if (rising) {
        canvas.drawLine(
            Offset(k, size.height), Offset(k + size.height, 0), paint);
      } else {
        canvas.drawLine(
            Offset(k, 0), Offset(k + size.height, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant HeatmapCellPainter old) =>
      old.level != level ||
      old.fillColor != fillColor ||
      old.isEink != isEink ||
      old.inkColor != inkColor;
}

/// 被選中方格的高對比外框：偏移 1px、線寬 [strokeWidth]（E-Ink 3、其餘 2）。
/// 畫在整張網格之上的獨立疊加層，不會被後畫的鄰格蓋住。
class HeatmapSelectionOutlinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const HeatmapSelectionOutlinePainter({
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).inflate(1 + strokeWidth / 2);
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant HeatmapSelectionOutlinePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

/// 貢獻圖：左側固定星期標籤欄＋右側水平捲動的方格區（月份標籤在方格上方、
/// 隨方格一起捲動）。捲動位置由呼叫端的 [scrollController] 控制（畫面載入
/// 後把它捲到最右側）。
class ReadingHeatmap extends StatelessWidget {
  final HeatmapGrid grid;

  /// `YYYY-MM-DD` → 當日全部書籍總秒數；沒有紀錄的日期不出現。
  final Map<String, int> dailyTotals;

  /// 目前選取的日期；`null` 表示不畫外框。
  final String? selectedDate;
  final ValueChanged<String> onSelectDate;
  final ScrollController scrollController;

  const ReadingHeatmap({
    super.key,
    required this.grid,
    required this.dailyTotals,
    required this.selectedDate,
    required this.onSelectDate,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isEink = theme.extension<ElinkTokens>()!.isEink;
    final ink = theme.colorScheme.onSurface;
    final selected = selectedDate == null ? null : grid.locate(selectedDate!);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WeekdayColumn(l10n: l10n, color: ink),
        Expanded(
          child: SingleChildScrollView(
            key: const Key('reading_stats_heatmap'),
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
                _kScrollPadding, 0, _kScrollPadding, _kScrollPadding),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MonthLabelRow(grid: grid, l10n: l10n, color: ink),
                    const SizedBox(height: _kMonthToGridGap),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _gapped(
                        [
                          // 以座標為佔位 Key（末週 5 個佔位同屬一個 Column，
                          // 全域單一 Key 會觸發 Flutter duplicate-keys 斷言）。
                          for (final weekEntry in grid.weeks.asMap().entries)
                            Column(
                              children: _gapped(
                                [
                                  for (final cellEntry in weekEntry.value
                                      .asMap()
                                      .entries)
                                    cellEntry.value == null
                                        ? SizedBox.square(
                                            key: Key(
                                                'heatmap_placeholder_${weekEntry.key}_${cellEntry.key}'),
                                            dimension: kHeatmapCellSize,
                                          )
                                        : _HeatmapCell(
                                            date: cellEntry.value!,
                                            seconds: dailyTotals[
                                                    cellEntry.value!] ??
                                                0,
                                            painter: HeatmapCellPainter.of(
                                              theme,
                                              heatmapLevelForSeconds(
                                                  dailyTotals[
                                                          cellEntry.value!] ??
                                                      0),
                                            ),
                                            selected: cellEntry.value ==
                                                selectedDate,
                                            onTap: onSelectDate,
                                          ),
                                ],
                                const SizedBox(height: kHeatmapCellGap),
                              ),
                            ),
                        ],
                        const SizedBox(width: kHeatmapCellGap),
                      ),
                    ),
                  ],
                ),
                if (selected != null)
                  Positioned(
                    left: selected.week * kHeatmapPitch,
                    top: _kGridTop + selected.row * kHeatmapPitch,
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const Key('heatmap_selection_outline'),
                        size: const Size.square(kHeatmapCellSize),
                        painter: HeatmapSelectionOutlinePainter(
                          color: ink,
                          strokeWidth: isEink ? 3 : 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

List<Widget> _gapped(List<Widget> items, Widget gap) => [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) gap,
        items[i],
      ],
    ];

class _HeatmapCell extends StatelessWidget {
  final String date;
  final HeatmapCellPainter painter;
  final bool selected;
  final ValueChanged<String> onTap;

  /// 當日閱讀秒數，只用於無障礙標籤（讓螢幕閱讀器直接唸出時數）。
  final int seconds;

  const _HeatmapCell({
    required this.date,
    required this.seconds,
    required this.painter,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('heatmap_cell_$date'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(date),
      child: Semantics(
        label:
            '$date ${formatReadingDuration(AppLocalizations.of(context)!, seconds)}',
        button: true,
        selected: selected,
        child: CustomPaint(
          size: const Size.square(kHeatmapCellSize),
          painter: painter,
        ),
      ),
    );
  }
}

/// 左側固定星期標籤欄：只標「週一、三、五」（第 0、2、4 列）。標籤單行、不縮放，
/// 欄寬由文字撐開（最少 14px，加 4px 右內距），英文「Mon」也不會折行。
class _WeekdayColumn extends StatelessWidget {
  final AppLocalizations l10n;
  final Color color;

  const _WeekdayColumn({required this.l10n, required this.color});

  @override
  Widget build(BuildContext context) {
    final labels = <int, (Key, String)>{
      0: (const Key('heatmap_weekday_label_mon'), l10n.statsWeekdayMon),
      2: (const Key('heatmap_weekday_label_wed'), l10n.statsWeekdayWed),
      4: (const Key('heatmap_weekday_label_fri'), l10n.statsWeekdayFri),
    };
    return IntrinsicWidth(
      key: const Key('heatmap_weekday_column'),
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: _kGridTop),
              for (var row = 0; row < 7; row++) ...[
                if (row > 0) const SizedBox(height: kHeatmapCellGap),
                SizedBox(
                  key: labels[row]?.$1,
                  height: kHeatmapCellSize,
                  child: labels[row] == null
                      ? null
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            labels[row]!.$2,
                            maxLines: 1,
                            softWrap: false,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                                fontSize: 10, height: 1, color: color),
                          ),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 方格上方的月份標籤列：標籤貼在對應週欄的左緣，隨方格一起水平捲動。
class _MonthLabelRow extends StatelessWidget {
  final HeatmapGrid grid;
  final AppLocalizations l10n;
  final Color color;

  const _MonthLabelRow({
    required this.grid,
    required this.l10n,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final format = DateFormat.MMM(l10n.localeName);
    return SizedBox(
      height: _kMonthRowHeight,
      width: grid.weekCount * kHeatmapPitch,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final m in grid.monthLabels)
            Positioned(
              left: m.weekIndex * kHeatmapPitch,
              top: 0,
              child: Text(
                format.format(DateTime(2000, m.month)),
                maxLines: 1,
                softWrap: false,
                textScaler: TextScaler.noScaling,
                style: TextStyle(fontSize: 10, height: 1.4, color: color),
              ),
            ),
        ],
      ),
    );
  }
}

/// 圖例：「較少 ▢▢▢▢▢ 較多」，方格與貢獻圖使用同一個繪製器（E-Ink 下含紋理）。
class ReadingHeatmapLegend extends StatelessWidget {
  const ReadingHeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final style = TextStyle(fontSize: 10, color: theme.colorScheme.onSurface);
    return Row(
      key: const Key('reading_stats_legend'),
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(l10n.statsLegendLess, style: style),
        const SizedBox(width: 4),
        for (var level = 0; level < 5; level++) ...[
          if (level > 0) const SizedBox(width: 3),
          CustomPaint(
            size: const Size.square(kHeatmapCellSize),
            painter: HeatmapCellPainter.of(theme, level),
          ),
        ],
        const SizedBox(width: 4),
        Text(l10n.statsLegendMore, style: style),
      ],
    );
  }
}
