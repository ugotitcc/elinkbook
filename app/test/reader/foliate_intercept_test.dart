// `shouldInterceptRequest` 路徑分類純函式測試（epic-66 Issue 1 Task 7）。
//
// 與 `resolveCustomFontUri`／`handleFoliateConsoleMessage` 同一理由：
// `FakePlatformInAppWebViewWidget` 不會觸發真實 `shouldInterceptRequest`
// 回呼（見 foliate_reader_view.dart:233-245 註解），把路徑判斷抽成
// [classifyFoliateRequestPath] 才能脫離 InAppWebViewController 直接測試。

import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("classifyFoliateRequestPath('/book/current.epub') == book", () {
    expect(
      classifyFoliateRequestPath('/book/current.epub'),
      FoliateRequestKind.book,
    );
  });

  test("classifyFoliateRequestPath('/unknown') == unknown", () {
    expect(classifyFoliateRequestPath('/unknown'), FoliateRequestKind.unknown);
  });

  test("classifyFoliateRequestPath('/assets/custom-fonts/X') == customFont", () {
    expect(
      classifyFoliateRequestPath('/assets/custom-fonts/MyFamily'),
      FoliateRequestKind.customFont,
    );
  });

  test("classifyFoliateRequestPath('/downloaded-fonts/v1/a.ttf') == downloadedFont",
      () {
    expect(
      classifyFoliateRequestPath('${kDownloadedFontsPathPrefix}v1/a.ttf'),
      FoliateRequestKind.downloadedFont,
    );
  });
}
