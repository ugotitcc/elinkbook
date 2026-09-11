// app/lib/screens/full_text_search_confirm_dialog.dart
import 'package:flutter/material.dart';

import '../search/full_text_search_settings_repository.dart';

/// 「啟用全文檢索」確認對話框（epic-10-search Issue 3，見 spec.md §4）：
/// 兩個分類（PDF／其他格式）共用同一個對話框，依 [category] 帶入不同
/// 文案；套用 `DESIGN.md` §9.1 一般排版慣例（平板上限寬度 400dp、主動作
/// 靠右、E-Ink 模式下 Scrim 即時切換不淡入淡出），但**不套用** §9.2「破壞
/// 性操作」的 error 色按鈕慣例——啟用全文檢索不會刪除/遺失任何資料。
/// `content` 用 `ConstrainedBox(maxWidth: 400)` 而非固定寬度的 `SizedBox`
/// （review-plan-issue-3.md I-3：`AlertDialog` 預設 `insetPadding` 左右各
/// 40dp，共 80dp，`SizedBox` 施加的緊約束若沒扣掉這個值，在 360～400dp
/// 手機上會溢位；`ConstrainedBox` 只設上限，實際寬度仍依父層可用空間
/// 收縮，不會超出）。`EBDialogShell` 目前尚未落地為共用元件，手動以
/// `AlertDialog` 符合上述排版規則。
///
/// 純 UI 確認元件，本身不呼叫 [FullTextSearchSettingsRepository]——呼叫端
/// （`SettingsScaffold`）在使用者按下「確認開啟」（本函式回傳 `true`）之後
/// 才呼叫 `setEnabled(category, true)`，比照既有
/// `showCloudDuplicateConfirmDialog()` 純回傳 bool 的既有慣例。
Future<bool> showFullTextSearchEnableConfirmDialog(
  BuildContext context, {
  required ContentIndexCategory category,
  bool isEinkMode = false,
}) async {
  final message = category == ContentIndexCategory.pdf
      ? '將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量'
          '消耗，是否繼續？\n\n部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容，'
          '索引後仍查不到屬於正常情況。'
      : '將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量'
          '消耗，是否繼續？';
  final result = await showDialog<bool>(
    context: context,
    animationStyle: isEinkMode ? AnimationStyle.noAnimation : null,
    builder: (context) => AlertDialog(
      key: const Key('full_text_search_enable_confirm_dialog'),
      title: const Text('啟用全文檢索'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Text(message),
      ),
      actions: [
        TextButton(
          key: const Key('full_text_search_enable_confirm_dialog_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('full_text_search_enable_confirm_dialog_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('確認開啟'),
        ),
      ],
    ),
  );
  return result ?? false;
}
