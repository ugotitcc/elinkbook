import 'package:flutter/material.dart';

import '../reader/reader_console_log.dart';

/// 閱讀器 WebView 診斷用 Console Log 檢視畫面（epic-18-reader-device-qa
/// Issue 33）：真機無法連 `chrome://inspect` 遠端除錯時，供使用者從「設定」
/// 進入查看／截圖回報 [ReaderConsoleLog] 累積的訊息。
class ReaderConsoleLogScreen extends StatelessWidget {
  const ReaderConsoleLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('閱讀器 Console Log'),
        actions: [
          IconButton(
            key: const Key('reader_console_log_clear_button'),
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空',
            onPressed: ReaderConsoleLog.clear,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: ReaderConsoleLog.entries,
        builder: (context, entries, _) {
          if (entries.isEmpty) {
            return const Center(
              key: Key('reader_console_log_empty'),
              child: Text('目前沒有記錄'),
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
}
