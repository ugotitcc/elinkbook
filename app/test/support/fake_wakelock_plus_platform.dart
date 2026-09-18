import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// 供 widget test 覆寫 `wakelockPlusPlatformInstance`（見
/// `package:wakelock_plus/wakelock_plus.dart`），避免測試環境下
/// `WakelockPlus.enable()/disable()` 呼叫真實平台通道拋出
/// `PlatformException(channel-error, ...)`（`flutter test` 環境未提供
/// mock handler 時，`wakelock_plus_platform_interface` 的 pigeon 產生碼
/// `_extractReplyValueOrThrow()` 會直接拋出，見
/// `epic-44-wifi-book-transfer` `reviews/review-plan-issue-1.md` C-1）。
/// 任何會掛載 `WifiTransferScreen` 的測試皆須在 `setUp`／`tearDown` 中
/// 覆寫／還原 `wakelockPlusPlatformInstance`。
class FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  bool isEnabled = false;
  final List<bool> toggleCalls = [];

  @override
  Future<void> toggle({required bool enable}) async {
    isEnabled = enable;
    toggleCalls.add(enable);
  }

  @override
  Future<bool> get enabled async => isEnabled;
}
