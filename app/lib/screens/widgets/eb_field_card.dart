import 'package:flutter/material.dart';

/// 視覺還原共用元件（Visual Accuracy Mode，
/// `docs/research/uiux/VISUAL_ANALYSIS.md`）：把任意內容包進一張套用全域
/// `CardTheme`（見 `app_theme_data.dart`：無陰影＋`outline` 邊框＋8dp 圓角）
/// 的卡片，對齊 Reference 截圖「每個設定項目/欄位都是獨立卡片」的視覺
/// 語彙。取代原本散落在設定畫面／版面設定三個 Bottom Sheet 各自「裸
/// `ListTile`／裸 `Column`」沒有邊框的寫法，避免同一種卡片包裝邏輯重複
/// 造好幾份。
///
/// [padding] 預設 `EdgeInsets.all(12)`（對應 `DESIGN.md` §3 `EBSpace.md`）；
/// 若 [child] 本身已管理好自己的內距（例如 `ListTile`／`SwitchListTile`），
/// 改傳 `EdgeInsets.zero` 避免雙重內距。[margin] 預設只留垂直間距、不留
/// 水平——多數呼叫端所在的外層 `ListView`／`Column` 通常已經有自己的水平
/// padding，卡片本身再疊加水平 margin 會造成雙重內縮；若外層沒有水平
/// padding（例如 `SettingsScaffold` 的 `ListView`），呼叫端需自行傳入含
/// 水平值的 margin。
class EBFieldCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const EBFieldCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.margin = const EdgeInsets.symmetric(vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: margin,
      child: Padding(padding: padding, child: child),
    );
  }
}
