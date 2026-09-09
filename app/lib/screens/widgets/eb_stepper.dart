import 'package:flutter/material.dart';

/// E-Ink 模式專用的純步進器（epic-39-layout-settings-redesign Issue 1，
/// spec.md §1）：補實作 `DESIGN.md` §18.3「步進控制」——E-Ink 模式下禁用
/// 所有 Slider 元件，字級/字重/行邊距等控制項一律自動替換為本元件。
///
/// 純展示、無 I/O，顏色一律讀 `Theme.of(context).colorScheme`——E-Ink
/// 主題本身的 `ColorScheme` 已是純黑白（見 `app_theme_data.dart`
/// `_buildEinkTheme()`），元件不自行判斷 `isEinkMode`，呼叫端已經知道
/// 自己在 E-Ink 模式才會建構這個 widget。
///
/// [mainAxisSize]／[mainAxisAlignment] 開放呼叫端覆寫（審查修正 I1，
/// review-plan-issue-1.md）：預設 `MainAxisSize.min` 讓本 widget 在任何
/// 父層（`Column`、`Row` 的非 flex 子項等）中都能安全地依內容自身寬度
/// 渲染，不會因為預設 `MainAxisSize.max` 在無邊界寬度約束下拋出
/// `RenderFlex` 例外；若呼叫端要讓 `-`/`+` 分居兩端撐滿整列寬度（比照
/// 既有 `_buildSliderRow` 用 `Expanded(child: Slider(...))` 撐滿的版面），
/// 可自行傳入 `mainAxisSize: MainAxisSize.max, mainAxisAlignment:
/// MainAxisAlignment.spaceBetween`。
class EBStepper extends StatelessWidget {
  final String keyPrefix;
  final double value;
  final double min;
  final double max;
  final double step;
  final String displayValue;
  final ValueChanged<double> onChanged;
  final MainAxisSize mainAxisSize;
  final MainAxisAlignment mainAxisAlignment;

  const EBStepper({
    super.key,
    required this.keyPrefix,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.displayValue,
    required this.onChanged,
    this.mainAxisSize = MainAxisSize.min,
    this.mainAxisAlignment = MainAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final clampedValue = value.clamp(min, max);
    return Row(
      mainAxisSize: mainAxisSize,
      mainAxisAlignment: mainAxisAlignment,
      children: [
        _StepperButton(
          buttonKey: Key('${keyPrefix}_decrement'),
          icon: Icons.remove,
          onPressed: clampedValue - step < min - 1e-9
              ? null
              : () => onChanged((clampedValue - step).clamp(min, max)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            displayValue,
            key: Key('${keyPrefix}_value'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        _StepperButton(
          buttonKey: Key('${keyPrefix}_increment'),
          icon: Icons.add,
          onPressed: clampedValue + step > max + 1e-9
              ? null
              : () => onChanged((clampedValue + step).clamp(min, max)),
        ),
      ],
    );
  }
}

/// 視覺還原（VISUAL_ANALYSIS.md）：Reference 截圖的 `-`/`+` 是有邊框的方形
/// 按鈕，原本的裸 `IconButton` 完全沒有邊框／圓角。沿用全域 `CardTheme`
/// 已定案的 8dp 圓角＋`outline` 邊框慣例（見 `app_theme_data.dart`），停用
/// 態邊框降低透明度以維持與 `IconButton` 原生 disabled 前景色一致的視覺
/// 語意。
class _StepperButton extends StatelessWidget {
  final Key buttonKey;
  final IconData icon;
  final VoidCallback? onPressed;

  const _StepperButton({
    required this.buttonKey,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: enabled ? 1.0 : 0.35),
          width: 1.5,
        ),
      ),
      child: IconButton(key: buttonKey, icon: Icon(icon), onPressed: onPressed),
    );
  }
}
