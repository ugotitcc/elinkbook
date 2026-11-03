// 平台判斷輔助（epic-66 Issue 1）。
//
// 全域判斷一律走 [defaultTargetPlatform]，不用 `dart:io` 的 `Platform`：
// 測試可用 `debugDefaultTargetPlatformOverride` 切換平台，`flutter test`
// 預設平台維持 Android，既有測試不受影響。

import 'package:flutter/foundation.dart';

/// 是否為 Windows 桌面平台。
bool get isWindowsPlatform => defaultTargetPlatform == TargetPlatform.windows;

/// 是否為 Android 平台。
bool get isAndroidPlatform => defaultTargetPlatform == TargetPlatform.android;
