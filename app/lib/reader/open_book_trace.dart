import 'package:flutter/foundation.dart';

import 'reader_console_log.dart';

/// 開書階段記錄（epic-54 Issue 29 階段一診斷）。
///
/// 真機回報「同一本書一直開書逾時，關掉 App 才恢復」，但不知道 30 秒卡在哪一關。
/// 本類別把開書每一關（複製書、建立 WebView、頁面載入、渲染、離開）寫進
/// [ReaderConsoleLog]（設定畫面可檢視、截圖）與 debugPrint（logcat），並記住
/// 最後一筆，逾時時多寫一行「最後階段」。只記錄、不影響開書行為。
///
/// 記錄不含書名、完整檔案路徑與網址查詢字串。
class OpenBookTrace {
  OpenBookTrace._();

  /// 取得目前時間的來源；測試可替換成固定時間。
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static _TraceEntry? _last;

  /// 開始新的一次開書：清掉「最後階段」，避免前一本書的記錄（例如它的
  /// 「離開畫面」）污染這一本的逾時摘要。`ReaderScreen.initState` 呼叫。
  static void startSession() {
    _last = null;
  }

  /// 寫一筆 `[OpenBook#<instanceId>] <stage>[ <detail>]` 到 [ReaderConsoleLog]
  /// 與 debugPrint，並記住為「最後階段」。
  static void record(String instanceId, String stage, [String? detail]) {
    final suffix = (detail == null || detail.isEmpty) ? '' : ' $detail';
    final message = '[OpenBook#$instanceId] $stage$suffix';
    ReaderConsoleLog.add(message);
    debugPrint(message);
    _last = _TraceEntry(instanceId, stage, detail, clock());
  }

  /// 格式固定：`最後階段：<stage>[ <detail>]（實例 #<instanceId>，距今 <秒> 秒）`；
  /// 本次開書沒有任何記錄時為 `沒有任何階段記錄`。
  static String timeoutSummary() {
    final last = _last;
    if (last == null) return '沒有任何階段記錄';
    final detail =
        (last.detail == null || last.detail!.isEmpty) ? '' : ' ${last.detail}';
    final seconds = clock().difference(last.at).inSeconds;
    return '最後階段：${last.stage}$detail（實例 #${last.instanceId}，距今 $seconds 秒）';
  }

  /// 先取 [timeoutSummary]，再 `record(instanceId, '開書逾時', summary)`
  /// （順序寫在函式內，不靠引數求值順序）。[instanceId] 預設 `-`。
  static void recordTimeout([String instanceId = '-']) {
    final summary = timeoutSummary();
    record(instanceId, '開書逾時', summary);
  }
}

class _TraceEntry {
  const _TraceEntry(this.instanceId, this.stage, this.detail, this.at);

  final String instanceId;
  final String stage;
  final String? detail;
  final DateTime at;
}
