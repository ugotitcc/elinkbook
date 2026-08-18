import 'package:flutter/material.dart';

import '../remote/opds_types.dart';

/// 同一書目提供多個下載格式時的選擇彈窗（epic-30-calibre-remote-library
/// Issue 2，spec.md「UI 落地位置」，沿用 `epic-29-cloud-import` 的命名
/// 慣例）。不支援的格式（`format == null`）置灰不可選。
class FormatSelectionDialog extends StatelessWidget {
  final OpdsEntry entry;

  const FormatSelectionDialog({super.key, required this.entry});

  static Future<OpdsAcquisition?> show(BuildContext context, OpdsEntry entry) {
    return showDialog<OpdsAcquisition>(
      context: context,
      builder: (context) => FormatSelectionDialog(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('format_selection_dialog'),
      title: Text('選擇格式：${entry.title}'),
      // 〔審查 review-plan-issue-2.md Finding 2 採納〕格式選項較多或在
      // 橫向/小螢幕裝置上時，固定高度的 AlertDialog 內容可能超出可視
      // 範圍，外層包 SingleChildScrollView 防禦 RenderFlex overflow。
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: entry.acquisitions.map((acquisition) {
            final supported = acquisition.format != null;
            return ListTile(
              key: Key('format_selection_option_${acquisition.href}'),
              enabled: supported,
              title: Text(supported ? acquisition.format!.name.toUpperCase() : '不支援的格式'),
              onTap: supported ? () => Navigator.of(context).pop(acquisition) : null,
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
