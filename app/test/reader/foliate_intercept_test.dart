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

  // 回歸：Windows 沒有 InternalStoragePathHandler，已下載字型的
  // `/downloaded-fonts/` 請求必須由攔截回呼讀本機檔案，路徑解析要有獨立可測的 seam。
  group('resolveDownloadedFontFile', () {
    test('已知發布路徑 → 存放目錄下的實際檔案路徑', () {
      final file = resolveDownloadedFontFile(
        '${kDownloadedFontsPathPrefix}v1/SweiB2SugarCJKtc-Medium.ttf',
        r'C:\data\downloaded-fonts',
      );
      expect(file, isNotNull);
      expect(file!.replaceAll('\\', '/'),
          'C:/data/downloaded-fonts/v1/SweiB2SugarCJKtc-Medium.ttf');
    });

    test('不在字型目錄清單內的路徑（含路徑穿越）→ null', () {
      expect(
        resolveDownloadedFontFile(
            '$kDownloadedFontsPathPrefix../secret.db', '/d'),
        isNull,
      );
      expect(
        resolveDownloadedFontFile(
            '${kDownloadedFontsPathPrefix}v1/unknown.ttf', '/d'),
        isNull,
      );
    });

    test('前綴不符 → null', () {
      expect(resolveDownloadedFontFile('/book/current.epub', '/d'), isNull);
    });
  });

  test("classifyFoliateRequestPath('/downloaded-fonts/v1/a.ttf') == downloadedFont",
      () {
    expect(
      classifyFoliateRequestPath('${kDownloadedFontsPathPrefix}v1/a.ttf'),
      FoliateRequestKind.downloadedFont,
    );
  });
}
