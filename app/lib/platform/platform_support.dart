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

/// 是否提供只有手機才有意義的閱讀器控制項（epic-66 Issue 10）。
///
/// Windows 為 false，其他平台為 true。涵蓋五項功能：音量鍵翻頁、螢幕方向鎖定、
/// 「全螢幕模式」偏好（Android 沉浸模式，Windows 另有 F11）、PDF 影像濾鏡、
/// E-Ink 高對比模式。目前五項條件相同，所以共用一個旗標。
bool get supportsMobileReaderControls => !isWindowsPlatform;
