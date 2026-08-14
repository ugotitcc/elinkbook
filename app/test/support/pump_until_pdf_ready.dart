import 'package:flutter_test/flutter_test.dart';

/// 等待 pdfrx（或其他真實非同步渲染流程）在 widget test 環境下完成初次
/// 渲染的共用測試 adapter（epic-26-architecture-hardening Issue 4，收斂
/// 原本散落在 9 個測試檔案、104 個編輯點的重複輪詢迴圈）。
///
/// [condition] 為 `null`（省略）時無條件跑滿 [maxIterations] 輪；提供時，
/// 每輪 pump 之後檢查一次，回傳 `true` 即提前停止等待。[maxIterations] 與
/// [delayBetweenPumps] 皆可覆寫，涵蓋既有程式碼中出現過的 10／30／40 輪與
/// 10ms／50ms 間隔等變形。
///
/// 兩種時間職責不同、不可混淆：`tester.pump(Duration(milliseconds: 100))`
/// 是固定的 fake-clock 虛擬推進量（framework 動畫/計時器邏輯用），寫死不
/// 開放調整；[delayBetweenPumps] 則是 `runAsync` 跳出 fake zone 之後、
/// 真實 `Future.delayed`，用來讓底層真正的非同步 I/O／Isolate 運算（例如
/// pdfrx 解碼、影像濾鏡背景運算）有機會推進，兩者分屬不同時鐘、不可互相
/// 替代。
Future<void> pumpUntilPdfReady(
  WidgetTester tester, {
  bool Function()? condition,
  int maxIterations = 30,
  Duration delayBetweenPumps = const Duration(milliseconds: 10),
}) {
  return tester.runAsync(() async {
    for (var i = 0;
        i < maxIterations && (condition == null || !condition());
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(delayBetweenPumps);
    }
  });
}
