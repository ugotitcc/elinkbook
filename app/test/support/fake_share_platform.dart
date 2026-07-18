import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

/// 測試用 [SharePlatform] 替身：攔截 [share] 呼叫並記錄傳入的
/// [ShareParams]，不觸發真實系統分享面板（見 plan-issue-5.md Global
/// Constraints「真實 Android Share Intent 會阻塞等待使用者操作」——真正
/// 呼叫原生分享會讓 `flutter test` 卡住等待人工介入）。
class FakeSharePlatform extends SharePlatform {
  ShareParams? lastParams;

  @override
  Future<ShareResult> share(ShareParams params) async {
    lastParams = params;
    return ShareResult('', ShareResultStatus.success);
  }
}
