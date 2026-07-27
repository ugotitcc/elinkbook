import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

/// 測試用 [InAppWebViewPlatform] 替身：`flutter test`（無真實裝置/模擬器）
/// 沒有註冊任何 `flutter_inappwebview` 平台實作，直接 pump 裸的
/// `InAppWebView` widget 會因 [PlatformInAppWebViewWidget] 工廠建構子的
/// assertion（`InAppWebViewPlatform.instance != null`）而失敗。註冊本替身
/// 後，`InAppWebView` 可在純 widget test 環境下正常 pump、建構完整
/// widget 樹（包含疊加在其上的其他 widget），比照本專案既有
/// `test/support/fake_*.dart` 命名慣例。
class FakeInAppWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    return FakePlatformInAppWebViewWidget(params);
  }
}

/// 搭配 [FakeInAppWebViewPlatform] 使用的假 [PlatformInAppWebViewWidget]：
/// 回傳一個具有固定尺寸的 placeholder（而非 `SizedBox.shrink` 的零尺寸），
/// 讓疊加在 `InAppWebView` 之上的其他 widget（例如 9 宮格導覽熱區的
/// `Stack`）可以正確建構子樹並接受 hit test。尺寸需與測試
/// `MediaQuery`/`Surface` 尺寸相容——若測試視窗尺寸設定變動，可能導致
/// hit test 座標落在此固定尺寸之外。
class FakePlatformInAppWebViewWidget extends PlatformInAppWebViewWidget {
  FakePlatformInAppWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 400, height: 800);
  }

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) {
    throw UnimplementedError('controllerFromPlatform not needed in tests');
  }

  @override
  void dispose() {}
}
