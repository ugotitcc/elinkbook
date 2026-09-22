import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../reader/reader_console_log.dart';

/// 閱讀器 WebView 診斷用 Console Log 檢視畫面（epic-18-reader-device-qa
/// Issue 33）：真機無法連 `chrome://inspect` 遠端除錯時，供使用者從「設定」
/// 進入查看／截圖回報 [ReaderConsoleLog] 累積的訊息。
class ReaderConsoleLogScreen extends StatelessWidget {
  const ReaderConsoleLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.readerConsoleLogTitle),
        actions: [
          IconButton(
            key: const Key('reader_console_log_copy_all_button'),
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: l10n.readerConsoleLogCopyAllTooltip,
            onPressed: () => _copyAllToClipboard(context),
          ),
          IconButton(
            key: const Key('reader_console_log_clear_button'),
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.readerConsoleLogClearTooltip,
            onPressed: ReaderConsoleLog.clear,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: ReaderConsoleLog.entries,
        builder: (context, entries, _) {
          if (entries.isEmpty) {
            return Center(
              key: const Key('reader_console_log_empty'),
              child: Text(l10n.readerConsoleLogEmptyHint),
            );
          }
          return ListView.builder(
            key: const Key('reader_console_log_list'),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: SelectableText(
                  entries[index],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _copyAllToClipboard(BuildContext context) async {
    final entries = ReaderConsoleLog.entries.value;
    await Clipboard.setData(ClipboardData(text: entries.join('\n')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.readerConsoleLogCopiedMessage)),
    );
  }
}
