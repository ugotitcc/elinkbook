// 診斷用迴圈（epic-66 Issue 2，審查 Important 2 發現的 App 端記憶體累加）。
//
// 在同一個 App 程序內重複解析同一本 224 MB EPUB，每次之後等待、再讀程序自己的
// 常駐記憶體（RSS）。若每次解析都讓 RSS 棘輪式上升約一本書的大小，洩漏就在
// metadata 解析路徑；若不升，洩漏在匯入路徑（見 issue-2-report.md）。
//
// 執行：cd app && flutter test integration_test/windows_metadata/leak_probe_test.dart -d windows
// 輸出格式：[leak] iter=<n> phase=<before|after_parse|after_wait> rss_mb=<數字>

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:elinkbook/library/windows_book_metadata.dart';
import 'package:elinkbook/windows/windows_webview_environment.dart';

const _bookPath = r'U:\05電子書\IT\AI世界的底層邏輯與生存法則.epub';
const _iterations = 4;
const _settleSeconds = 6;

int _rssMb() => (ProcessInfo.currentRss / (1024 * 1024)).round();

// 同時讀私有記憶體（Private Bytes）與工作集：只有工作集升代表共享／映射記憶體，
// 兩者都升代表真的堆積配置沒釋放。用 PowerShell 讀自己的 PID。
String _memDetail() {
  final r = Process.runSync('powershell', [
    '-NoProfile',
    '-Command',
    '\$p = Get-Process -Id $pid; "private_mb=\$([int](\$p.PrivateMemorySize64/1MB)) ws_mb=\$([int](\$p.WorkingSet64/1MB)) virt_mb=\$([int](\$p.VirtualMemorySize64/1MB))"',
  ]);
  return (r.stdout as String).trim();
}

void _log(int iter, String phase) {
  // ignore: avoid_print
  print('[leak] iter=$iter phase=$phase rss_mb=${_rssMb()} ${_memDetail()}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('同一程序內連續解析大檔，觀察 RSS 是否棘輪式上升', (tester) async {
    if (!File(_bookPath).existsSync()) {
      // ignore: avoid_print
      print('[leak] 找不到 $_bookPath，略過');
      return;
    }
    await initAppWebViewEnvironment(
      userDataFolder: (await getApplicationSupportDirectory()).path,
    );

    // 先暖身一次小動作，避免把一次性初始化成本算進第 1 次解析。
    await Future<void>.delayed(const Duration(seconds: 2));
    _log(0, 'before');

    for (var i = 1; i <= _iterations; i++) {
      _log(i, 'before');
      final meta = await extractWindowsBookMetadata(_bookPath, 'epub');
      expect(meta, isNotNull);
      _log(i, 'after_parse');
      await Future<void>.delayed(const Duration(seconds: _settleSeconds));
      _log(i, 'after_wait');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
