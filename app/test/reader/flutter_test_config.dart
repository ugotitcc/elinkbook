import 'dart:async';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';

/// 自訂測試綁定：擴大 test 環境的邏輯視窗尺寸至 2000×2000。
///
/// **為什麼需要**：`pdf_crop_frame_overlay_test.dart` 的手動裁切框選 UI
/// 使用四角控制點（32×32）放在裁切矩形的精確角落——當 `initialRect` 為
/// 全頁 `(0,0,1,1)` 時，控制點的中心恰好落在 SizedBox 邊界上。Flutter
/// 的 `RenderBox.size.contains()` 使用嚴格小於（`<`），邊界上的點被視為
/// 「不在盒子內」，導致 hit test 失敗。擴大視窗並搭配測試 wrapper 的
/// 更大 SizedBox（見 `pdf_crop_frame_overlay_test.dart` 的 `wrap()`），確
/// 保控制點中心落在容器內部。本檔案不覆寫 `hitTestInView`——邊界問題
/// 透過加大測試容器解決，避免全域 hit test 行為偏離影響其他測試。
///
/// **影響範圍**：`test/reader/` 目錄下所有測試（Flutter 官方慣例：
/// `flutter_test_config.dart` 對其所在目錄與子目錄全域生效）。已確認
/// `pdf_reader_view_test.dart`、`pdf_reader_view_dual_page_test.dart`、
/// `foliate_epub_reader_view_test.dart` 等既有測試不受影響。
class CustomBinding extends AutomatedTestWidgetsFlutterBinding {
  // 不覆寫 hitTestInView——邊界問題透過加大測試容器解決。
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  CustomBinding();
  setUpAll(() {
    final binding = TestWidgetsFlutterBinding.instance;
    // ignore: deprecated_member_use
    binding.window.physicalSizeTestValue = const Size(2000, 2000);
    // ignore: deprecated_member_use
    binding.window.devicePixelRatioTestValue = 1.0;
  });
  tearDownAll(() {
    final binding = TestWidgetsFlutterBinding.instance;
    // ignore: deprecated_member_use
    binding.window.clearPhysicalSizeTestValue();
    // ignore: deprecated_member_use
    binding.window.clearDevicePixelRatioTestValue();
  });
  await testMain();
}
