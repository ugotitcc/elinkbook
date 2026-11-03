// 平台判斷輔助的單元測試（epic-66 Issue 1 Task 2）。

import 'package:elinkbook/platform/platform_support.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('預設測試平台是 Android', () {
    expect(isAndroidPlatform, isTrue);
    expect(isWindowsPlatform, isFalse);
  });

  test('覆寫為 Windows 後', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(isWindowsPlatform, isTrue);
    expect(isAndroidPlatform, isFalse);
  });
}
