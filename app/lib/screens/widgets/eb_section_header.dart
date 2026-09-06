import 'package:flutter/material.dart';

/// 設定畫面分區標題基礎元件（`DESIGN.md` §17，
/// epic-36-adaptive-shelf-navigation Issue 5 首次落地）。最小可用版本，
/// 不含互動；比照 `ReadingDefaultsScreen._buildSectionHeader()` 既有樣式
/// 定調，抽成共用元件供 `SettingsScaffold` 使用。
class EBSectionHeader extends StatelessWidget {
  final String title;

  const EBSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      );
}
