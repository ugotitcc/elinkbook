import 'package:flutter/scheduler.dart';

/// 原生平台檢視（`InAppWebView`）關閉後，補送幾個畫面（epic-64）。
///
/// 為什麼需要：有平台檢視時，Flutter 引擎會把 raster 執行緒併進主執行緒，要「送出
/// 若干個畫面」後才會拆開。電子紙 App 閒置時幾乎不出畫面，所以閱讀器或字典 WebView
/// 關閉後，併合狀態會一直留著。這時使用者離開 App 再回來（選檔案、Home、切換 App、
/// 螢幕關閉再開），畫面表面在主執行緒重建，EGL context 就被設成主執行緒 current，
/// raster 執行緒之後 `eglMakeCurrent` 得到 `EGL_BAD_ACCESS`，畫面全黑或 Impeller
/// abort。WAVE（Allwinner／PowerVR Rogue GE8300）真機重現：
/// 開閱讀器 → 關閉 → 按 Home 再回來 → 紅燈；中間補約 16 個畫面 → 綠燈（各 2 次）。
///
/// 做法：在 [frames] 個連續的 frame 內，每個 frame 結束後再排下一個，補完就停止，
/// 不會一直重繪（電子紙要避免多餘的刷新）。
void flushFramesAfterPlatformViewRemoved({int frames = 12}) {
  var remaining = frames;
  if (remaining <= 0) return;

  void next(Duration _) {
    remaining--;
    if (remaining <= 0) return;
    SchedulerBinding.instance
      ..addPostFrameCallback(next)
      ..scheduleFrame();
  }

  SchedulerBinding.instance
    ..addPostFrameCallback(next)
    ..scheduleFrame();
}
