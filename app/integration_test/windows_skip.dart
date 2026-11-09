import 'dart:io';

/// 在 Windows 平台上略過不支援的整合測試。
///
/// Flutter 的 `testWidgets` 其 `skip` 參數型別為 `bool?`，無法像一般 `test` 一樣傳入字串原因。
/// 本函式強制呼叫端傳入非空的 [reason]，並在 Windows 上回傳 `true`，以供
/// `testWidgets(..., skip: skipOnWindows('原因'))` 使用。
bool skipOnWindows(String reason) {
  assert(reason.trim().isNotEmpty, '略過原因不得為空');
  return Platform.isWindows;
}
