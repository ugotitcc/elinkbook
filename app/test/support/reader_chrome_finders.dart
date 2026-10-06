import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 讀取閱讀器底部工具列的頁碼文字（`reader_chrome_page_info_text`），格式
/// `'$current / $total · $percent%'`，例如 `1 / 6 · 17%`（epic-38 Issue 1，
/// `ReaderScreen._pageProgressText`）。
///
/// 這個 widget 只在工具列可見時存在（`_chromeVisible` 預設為 true；觸發
/// `ZoneAction.menu` 或 FXL 換頁後會收合），找不到時請先確認工具列沒被收合。
String pageInfoText(WidgetTester tester) {
  final finder = find.byKey(const Key('reader_chrome_page_info_text'));
  if (finder.evaluate().isEmpty) {
    fail('找不到 reader_chrome_page_info_text：工具列可能已收合，或位置資訊尚未載入');
  }
  return tester.widget<Text>(finder).data ?? '';
}
