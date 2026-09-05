import 'package:flutter/material.dart';

/// 書架換頁控制列（`DESIGN.md#L317` §15.1）：純呈現、無狀態，不知道
/// 分頁邏輯本身——`currentPage`/`pageCount` 由呼叫端算好傳入，
/// `onPrevious`/`onNext` 為 `null` 時代表已在邊界頁，按鈕自動停用。
class PagingBar extends StatelessWidget {
  final int currentPage; // 0-based
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool isEinkMode;

  const PagingBar({
    super.key,
    required this.currentPage,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
    this.isEinkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // 觸控目標依 DESIGN.md §7.2：一般模式 48dp、E-Ink 模式 56dp。用
    // SizedBox 給 IconButton 緊約束（tight constraints），確保實際渲染
    // 尺寸精確等於指定值，不受 IconButton 內建最小尺寸影響。
    final buttonSize = isEinkMode ? 56.0 : 48.0;
    // `DESIGN.md#L344` 原文是「高度最小 52dp」，不是寫死 52——E-Ink 模式
    // 按鈕本身就要 56dp，外層若仍固定 52 會把 56dp 的子項在 cross axis
    // 方向夾扁回 52（`SizedBox` 對子項的 tight constraints 會被父層更小
    // 的 maxHeight `enforce()` 蓋掉），E-Ink 觸控目標實際上根本沒有做到
    // 56dp（`review-plan-issue-3.md` C-1）。外層高度改為跟隨按鈕尺寸。
    final barHeight = isEinkMode ? 56.0 : 52.0;
    return SizedBox(
      height: barHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: IconButton(
              key: const Key('paging_bar_previous_button'),
              icon: const Icon(Icons.chevron_left),
              tooltip: '上一頁',
              onPressed: onPrevious,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${currentPage + 1} / $pageCount'),
          ),
          SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: IconButton(
              key: const Key('paging_bar_next_button'),
              icon: const Icon(Icons.chevron_right),
              tooltip: '下一頁',
              onPressed: onNext,
            ),
          ),
        ],
      ),
    );
  }
}
