// Windows 記憶體量測輔助工具（epic-66 Issue 3 Task 2）。
//
// 透過 PowerShell 讀取 App 程序（elinkbook.exe）自身之私有記憶體（Private Bytes）、
// 工作集（Working Set），並展開 Win32_Process 程序樹加總其下的 msedgewebview2.exe
// 私有記憶體與數量。

import 'dart:io';

/// 記憶體取樣數值。
class MemSample {
  /// App 程序自身之私有記憶體（MB，PrivateMemorySize64 / 1MB）。
  final double privateMb;

  /// App 程序自身之工作集（MB，WorkingSet64 / 1MB）。
  final double wsMb;

  /// App 產生的所有 WebView2 子程序私有記憶體加總（MB）。
  final double wv2PrivateMb;

  /// App 產生的 WebView2 子程序數量。
  final int wv2Count;

  const MemSample({
    required this.privateMb,
    required this.wsMb,
    required this.wv2PrivateMb,
    required this.wv2Count,
  });

  @override
  String toString() =>
      'private_mb=${privateMb.toStringAsFixed(2)} ws_mb=${wsMb.toStringAsFixed(2)} wv2_private_mb=${wv2PrivateMb.toStringAsFixed(2)} wv2_count=$wv2Count';
}

/// 解析量測用大檔 EPUB 路徑。
String resolveLargeEpubPath() {
  const candidates = [
    '../tmp/AI世界的底層邏輯與生存法則.epub',
    'tmp/AI世界的底層邏輯與生存法則.epub',
    r'U:\05電子書\IT\AI世界的底層邏輯與生存法則.epub',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) {
      return File(path).absolute.path;
    }
  }
  return candidates.first;
}

/// 量測用大檔 EPUB 路徑。
final String kLargeEpubPath = resolveLargeEpubPath();

/// 正式量測迭代次數（不含第 0 次暖身基線）。
const int kIterations = 4;

/// 每次操作後等待記憶體回落秒數。
const int kSettleSeconds = 6;

/// 取得大檔 EPUB 大小（MB，以 1024 * 1024 二進位計算，與 PowerShell 1MB 單位完全一致）。
double bookSizeMb([String? path]) {
  final targetPath = path ?? kLargeEpubPath;
  final file = File(targetPath);
  if (!file.existsSync()) return 0.0;
  return file.lengthSync() / (1024.0 * 1024.0);
}

/// 透過 PowerShell 讀取 App 與其 WebView2 子程序之即時記憶體。
Future<MemSample> sampleMemory() async {
  final targetPid = pid;
  final script = '''
\$RootId = $targetPid
\$all = Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId
\$ids = New-Object System.Collections.Generic.HashSet[int]
[void]\$ids.Add(\$RootId)
do {
    \$before = \$ids.Count
    foreach (\$p in \$all) {
        if (\$ids.Contains([int]\$p.ParentProcessId)) { [void]\$ids.Add([int]\$p.ProcessId) }
    }
} while (\$ids.Count -ne \$before)

\$idArray = [int[]]\$ids
\$procs = Get-Process -Id \$idArray -ErrorAction SilentlyContinue
\$app = Get-Process -Id \$RootId -ErrorAction SilentlyContinue
\$appPrivate = if (\$app) { [math]::Round(\$app.PrivateMemorySize64 / 1MB, 2) } else { 0.0 }
\$appWs = if (\$app) { [math]::Round(\$app.WorkingSet64 / 1MB, 2) } else { 0.0 }

\$wvPrivate = 0.0
\$wvCount = 0
foreach (\$p in \$procs) {
    if (\$p.ProcessName -eq 'msedgewebview2') {
        \$wvPrivate += \$p.PrivateMemorySize64 / 1MB
        \$wvCount++
    }
}
\$wvPrivate = [math]::Round(\$wvPrivate, 2)
Write-Output ("\$appPrivate \$appWs \$wvPrivate \$wvCount")
''';

  final result = await Process.run('powershell', ['-NoProfile', '-Command', script]);
  if (result.exitCode != 0) {
    throw StateError('PowerShell 記憶體取樣失敗 (${result.exitCode}): ${result.stderr}');
  }
  final stdoutStr = (result.stdout as String).trim();
  final parts = stdoutStr.split(RegExp(r'\s+'));
  if (parts.length < 4) {
    throw StateError('無法解析 PowerShell 記憶體取樣輸出: "$stdoutStr"');
  }
  final privateMb = double.tryParse(parts[0]) ?? 0.0;
  final wsMb = double.tryParse(parts[1]) ?? 0.0;
  final wv2PrivateMb = double.tryParse(parts[2]) ?? 0.0;
  final wv2Count = int.tryParse(parts[3]) ?? 0;

  return MemSample(
    privateMb: privateMb,
    wsMb: wsMb,
    wv2PrivateMb: wv2PrivateMb,
    wv2Count: wv2Count,
  );
}

/// 格式化印出標準 `[leak]` 量測日誌行。
void logLeak(String path, int iter, String phase, MemSample s) {
  // ignore: avoid_print
  print(
    '[leak] path=$path iter=$iter phase=$phase private_mb=${s.privateMb.toStringAsFixed(2)} ws_mb=${s.wsMb.toStringAsFixed(2)} wv2_private_mb=${s.wv2PrivateMb.toStringAsFixed(2)} wv2_count=${s.wv2Count}',
  );
}
