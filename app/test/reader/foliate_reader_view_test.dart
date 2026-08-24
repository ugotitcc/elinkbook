import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/dual_page_mode.dart';
import 'package:elinkbook/reader/dual_page_direction.dart';
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/reader_console_log.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:elinkbook/reader/custom_font.dart';
import '../support/fake_inappwebview_platform.dart';

void _noop() {}
void _noopError(String message) {}

void main() {
  // 保存原始實作， tearDownAll 時還原
  late Future<String?> Function(String, String) originalCacheBookForServing;

  // Issue 10 審查修正：9 宮格導航熱區 tap／debug overlay 這兩項 widget
  // test 原本因「裸 InAppWebView 無法在 flutter_test 下 pump」被整批移除
  // （見 plan-issue-10.md「驗證紀錄」），比照
  // test/screens/reader_screen_test.dart 已驗證可行的作法，註冊
  // FakeInAppWebViewPlatform 後即可正常 pump，回補於下方
  // 「3×3 導航熱區」group。
  setUpAll(() {
    InAppWebViewPlatform.instance = FakeInAppWebViewPlatform();
    // Issue 8 審查修正：覆寫 cacheBookForServing 頂層函數變數，
    // 繞過 Dart 端檔案系統檢查（File.exists()、resolveSymbolicLinksSync() 等），
    // 確保 FoliateReaderView 的 _cacheBook() 在測試環境中能順利完成。
    originalCacheBookForServing = cacheBookForServing;
    cacheBookForServing = (filePath, instanceId) async {
      return '/fake/cache/dir/current.epub';
    };
  });

  group('colorToCssHex', () {
    test('不透明色轉換為 6 位十六進位色碼（丟棄 alpha）', () {
      expect(colorToCssHex(const Color(0xFF121214)), '#121214');
    });

    test('RGB 帶前導零時仍正確補零（不會被截斷成較短字串）', () {
      expect(colorToCssHex(const Color(0xFF010203)), '#010203');
    });

    test('純白色轉換正確', () {
      expect(colorToCssHex(const Color(0xFFFFFFFF)), '#ffffff');
    });

    test('純黑色轉換正確', () {
      expect(colorToCssHex(const Color(0xFF000000)), '#000000');
    });
  });

  group('buildFoliatePreferencesMap', () {
    test('所有偏好欄位皆為 null 時回傳空 map', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      // isLandscape 為非 nullable 必要參數，預設 false，恆定出現在 map
      expect(buildFoliatePreferencesMap(view), {'isLandscape': false, 'isComicBookHint': false});
    });

    test('columnMode: single 時 map 含 columnMode: single', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        columnMode: ColumnMode.single,
      );
      expect(buildFoliatePreferencesMap(view), {
        'columnMode': 'single',
        'isLandscape': false, 'isComicBookHint': false,
      });
    });

    test('showFooter: false 時 map 含 showFooter: false', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        showFooter: false,
      );
      expect(buildFoliatePreferencesMap(view), {
        'showFooter': false,
        'isLandscape': false, 'isComicBookHint': false,
      });
    });

    test('textColor 非 null 時 map 含轉換後的十六進位色碼字串', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        textColor: Color(0xFFE8E8EC),
      );
      expect(buildFoliatePreferencesMap(view), {
        'textColor': '#e8e8ec',
        'isLandscape': false, 'isComicBookHint': false,
      });
    });

    test('backgroundColor 非 null 時 map 含轉換後的十六進位色碼字串', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        backgroundColor: Color(0xFF121214),
      );
      expect(buildFoliatePreferencesMap(view), {
        'backgroundColor': '#121214',
        'isLandscape': false, 'isComicBookHint': false,
      });
    });

    test('textColor／backgroundColor 未設定（null）時 map 不含這兩個 key', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      expect(buildFoliatePreferencesMap(view).containsKey('textColor'), isFalse);
      expect(
        buildFoliatePreferencesMap(view).containsKey('backgroundColor'),
        isFalse,
      );
    });

    test('所有非 null 建構參數皆正確出現於 map', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.vertical,
        pageTurnMode: PageTurnMode.scroll,
        fontFamily: 'SourceHanSansTC',
        fontSize: 1.125,
        fontWeight: 1.75,
        lineHeight: 1.6,
        paragraphSpacing: 1.2,
        letterSpacing: 0.1,
        marginTop: 72,
        marginBottom: 20,
        marginLeft: 30,
        marginRight: 30,
        textAlign: EpubTextAlign.justify,
        publisherStyles: false,
        columnMode: ColumnMode.single,
        columnSize: 600.0,
        showFooter: false,
        textColor: Color(0xFFE8E8EC),
        backgroundColor: Color(0xFF121214),
      );
      expect(buildFoliatePreferencesMap(view), {
        'writingMode': 'vertical',
        'pageTurnMode': 'scroll',
        'fontFamily': 'SourceHanSansTC',
        'fontSize': 1.125,
        'fontWeight': 1.75,
        'lineHeight': 1.6,
        'paragraphSpacing': 1.2,
        'letterSpacing': 0.1,
        'marginTop': 72.0,
        'marginBottom': 20.0,
        'marginLeft': 30.0,
        'marginRight': 30.0,
        'textAlign': 'justify',
        'publisherStyles': false,
        'columnMode': 'single',
        'columnSize': 600.0,
        'showFooter': false,
        'textColor': '#e8e8ec',
        'backgroundColor': '#121214',
        'isLandscape': false, 'isComicBookHint': false,
      });
    });

    test('writingMode: horizontal 時 map 含 writingMode: horizontal', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.horizontal,
      );
      expect(buildFoliatePreferencesMap(view), {
        'writingMode': 'horizontal',
        'isLandscape': false, 'isComicBookHint': false,
      });
    });

    test('isFixedLayoutHint: true 時 map 含 isFixedLayoutHint: true', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isFixedLayoutHint: true,
      );
      expect(buildFoliatePreferencesMap(view), {
        'isFixedLayoutHint': true,
        'isLandscape': false, 'isComicBookHint': false,
      });
    });

    test('isFixedLayoutHint: false 時 map 含 isFixedLayoutHint: false', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isFixedLayoutHint: false,
      );
      expect(buildFoliatePreferencesMap(view), {
        'isFixedLayoutHint': false,
        'isLandscape': false, 'isComicBookHint': false,
      });
    });

    test('isFixedLayoutHint 未設定（null）時 map 不含該 key', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isFixedLayoutHint: null,
      );
      expect(
        buildFoliatePreferencesMap(view).containsKey('isFixedLayoutHint'),
        isFalse,
      );
    });

    test('letterSpacing 未設定（null）時 map 不含該 key', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      expect(
        buildFoliatePreferencesMap(view).containsKey('letterSpacing'),
        isFalse,
      );
    });

    // Epic 20 Issue 3：dualPageMode／isLandscape 單元測試
    test('dualPageMode: always 時 map 含 dualPageMode: always', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
      );
      expect(buildFoliatePreferencesMap(view), {
        'dualPageMode': 'always',
        'isLandscape': false, 'isComicBookHint': false,
      });
    });

    test('dualPageMode: auto 時 map 含 dualPageMode: auto', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.auto,
      );
      expect(buildFoliatePreferencesMap(view), {
        'dualPageMode': 'auto',
        'isLandscape': false, 'isComicBookHint': false,
      });
    });

    test('dualPageMode: never 時 map 含 dualPageMode: never', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.never,
      );
      expect(buildFoliatePreferencesMap(view), {
        'dualPageMode': 'never',
        'isLandscape': false, 'isComicBookHint': false,
      });
    });

    test('dualPageMode 未設定（null）時 map 不含該 key', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: null,
      );
      expect(
        buildFoliatePreferencesMap(view).containsKey('dualPageMode'),
        isFalse,
      );
    });

    test('isLandscape: true 時 map 含 isLandscape: true', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isLandscape: true,
      );
      expect(buildFoliatePreferencesMap(view), {'isLandscape': true, 'isComicBookHint': false});
    });

    test('isLandscape 預設值（false）時 map 含 isLandscape: false', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      expect(buildFoliatePreferencesMap(view), {'isLandscape': false, 'isComicBookHint': false});
    });

    test('dualPageMode + isLandscape 同時設定時兩者皆出現在 map', () {
      const view = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
        isLandscape: true,
      );
      expect(buildFoliatePreferencesMap(view), {
        'dualPageMode': 'always',
        'isLandscape': true, 'isComicBookHint': false,
      });
    });
  });

  group('foliatePreferencesChanged', () {
    test('完全相同的參數回傳 false', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      expect(foliatePreferencesChanged(oldView, newView), isFalse);
    });

    test('writingMode 變動回傳 true', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.horizontal,
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.vertical,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('letterSpacing 變動回傳 true', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        letterSpacing: 0.1,
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        letterSpacing: 0.2,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('columnMode 變動回傳 true', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        columnMode: ColumnMode.single,
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('showFooter 變動回傳 true', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        showFooter: true,
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        showFooter: false,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('isFixedLayoutHint 變動回傳 true', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isFixedLayoutHint: false,
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isFixedLayoutHint: true,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('非偏好參數（filePath）變動不影響結果', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/old.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/new.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      expect(foliatePreferencesChanged(oldView, newView), isFalse);
    });

    // Epic 20 Issue 3：dualPageMode／isLandscape 變動偵測
    test('dualPageMode 變動回傳 true', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.never,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('dualPageMode 從 null 變為 always 回傳 true', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      const newView = FoliateReaderView(
       filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('isLandscape 變動回傳 true', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isLandscape: false,
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        isLandscape: true,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('dualPageMode + isLandscape 同時變動回傳 true', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.auto,
        isLandscape: false,
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.always,
        isLandscape: true,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('dualPageMode + isLandscape 未變動回傳 false', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.auto,
        isLandscape: true,
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        dualPageMode: DualPageMode.auto,
        isLandscape: true,
      );
      expect(foliatePreferencesChanged(oldView, newView), isFalse);
    });

    test('僅 textColor 不同時回傳 true', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        textColor: Color(0xFF000000),
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        textColor: Color(0xFFE8E8EC),
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('僅 backgroundColor 不同時回傳 true', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        backgroundColor: Color(0xFFFFFFFF),
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        backgroundColor: Color(0xFF121214),
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('textColor／backgroundColor 皆相同（含皆為 null）時回傳 false', () {
      const oldView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      const newView = FoliateReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      expect(foliatePreferencesChanged(oldView, newView), isFalse);
    });

    test('isComicBookHint 恆包含於 map（非 nullable 欄位，比照 isLandscape）', () {
      final view = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
        isComicBookHint: true,
      );
      final map = buildFoliatePreferencesMap(view);
      expect(map['isComicBookHint'], isTrue);
    });

    test('dualPageDirection 為 null 時不出現在 map 中', () {
      final view = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
      );
      final map = buildFoliatePreferencesMap(view);
      expect(map.containsKey('dualPageDirection'), isFalse);
    });

    test('dualPageDirection 非 null 時序列化為 rtl/ltr 字串', () {
      final rtlView = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
        dualPageDirection: DualPageDirection.rtl,
      );
      expect(buildFoliatePreferencesMap(rtlView)['dualPageDirection'], 'rtl');

      final ltrView = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
        dualPageDirection: DualPageDirection.ltr,
      );
      expect(buildFoliatePreferencesMap(ltrView)['dualPageDirection'], 'ltr');
    });

    test('foliatePreferencesChanged 偵測 isComicBookHint/dualPageDirection 變動', () {
      final base = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
        isComicBookHint: true,
        dualPageDirection: DualPageDirection.ltr,
      );
      final changedHint = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
        isComicBookHint: false,
        dualPageDirection: DualPageDirection.ltr,
      );
      final changedDirection = FoliateReaderView(
        filePath: 'test.cbz',
        onPageRendered: () {},
        onError: (_) {},
        isComicBookHint: true,
        dualPageDirection: DualPageDirection.rtl,
      );
      expect(foliatePreferencesChanged(base, changedHint), isTrue);
      expect(foliatePreferencesChanged(base, changedDirection), isTrue);
      expect(foliatePreferencesChanged(base, base), isFalse);
    });
  });

  group('resolveCustomFontUri', () {
    const fonts = [
      CustomFont(
        id: 1,
        displayName: 'A',
        familyName: 'FamilyA',
        fontUri: 'content://example/a',
      ),
      CustomFont(
        id: 2,
        displayName: 'B',
        familyName: 'My Custom B',
        fontUri: 'content://example/b',
      ),
    ];

    test('路徑符合自訂字型前綴且 family name 存在於清單中，回傳對應 fontUri',
        () {
      expect(
        resolveCustomFontUri('/assets/custom-fonts/FamilyA', fonts),
        'content://example/a',
      );
    });

    test('family name 含空白，先經 URL 解碼再比對', () {
      expect(
        resolveCustomFontUri(
            '/assets/custom-fonts/My%20Custom%20B', fonts),
        'content://example/b',
      );
    });

    test('family name 不在清單中，回傳 null', () {
      expect(
        resolveCustomFontUri('/assets/custom-fonts/Unknown', fonts),
        isNull,
      );
    });

    test('路徑不是自訂字型前綴，回傳 null（不影響既有 /assets/fonts/ 等其他路徑）',
        () {
      expect(resolveCustomFontUri('/assets/fonts/foo.ttf', fonts), isNull);
      expect(resolveCustomFontUri('/assets/foliate/main.js', fonts), isNull);
    });

    test('customFonts 為空清單時一律回傳 null', () {
      expect(
        resolveCustomFontUri('/assets/custom-fonts/FamilyA', const []),
        isNull,
      );
    });

    test('畸形百分號跳脫序列（Uri.decodeComponent 會拋 FormatException 或 ArgumentError）時回傳 null，不拋出例外',
        () {
      expect(
        () => resolveCustomFontUri('/assets/custom-fonts/Font%2', fonts),
        returnsNormally,
      );
      expect(resolveCustomFontUri('/assets/custom-fonts/Font%2', fonts), isNull);
    });
  });

  group('3×3 導航熱區（InAppWebView）', () {
    // Issue 10 審查修正：改寫前（AndroidView）版本用
    // SystemChannels.platform_views/MethodChannel mock 驅動底層原生
    // PlatformView 建立流程（見 git 歷史 b2ea4a3 版本的
    // _pumpFoliateReaderView），該機制已隨遷移完全消失；改用
    // setUpAll 註冊的 FakeInAppWebViewPlatform 讓 InAppWebView 可直接
    // pump，不需要任何 mock。pump 後接 runAsync(Future.delayed(Duration.zero))
    // 再 pump 一次，比照 test/screens/reader_screen_test.dart 已驗證可行
    // 的既有寫法。
    testWidgets(
        '3×3 導航熱區：9 個 Key(nav_zone_\$index) 皆存在，點擊觸發對應 onZoneAction',
        (tester) async {
      final capturedActions = <ZoneAction>[];
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
            navZoneActions: const [
              ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
              ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
              ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
            ],
            onZoneAction: capturedActions.add,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      for (var index = 0; index < 9; index++) {
        expect(find.byKey(Key('nav_zone_$index')), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('nav_zone_2')));
      await tester.pump();
      expect(capturedActions, [ZoneAction.nextPage]);

      await tester.tap(find.byKey(const Key('nav_zone_4')));
      await tester.pump();
      expect(capturedActions, [ZoneAction.nextPage, ZoneAction.menu]);

      await tester.tap(find.byKey(const Key('nav_zone_1')));
      await tester.pump();
      expect(
        capturedActions,
        [ZoneAction.nextPage, ZoneAction.menu, ZoneAction.none],
      );
    });

    testWidgets('showNavZoneDebugOverlay=true 時，格子顯示對應動作文字標籤',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
            navZoneActions: const [
              ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
              ZoneAction.none, ZoneAction.none, ZoneAction.none,
              ZoneAction.none, ZoneAction.none, ZoneAction.none,
            ],
            showNavZoneDebugOverlay: true,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(find.text('上一頁'), findsWidgets);
      expect(find.text('選單'), findsWidgets);
      expect(find.text('下一頁'), findsWidgets);
      expect(find.text('無動作'), findsWidgets);
    });

    testWidgets(
        'EPUB nav-zone 熱區：onPointerCancel 不會拋出例外，取消手勢本身不觸發 onZoneAction，後續正常點擊仍正確判定',
        (tester) async {
      ZoneAction? triggered;
      final actions = List<ZoneAction>.filled(9, ZoneAction.menu);

      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: 'test/fixtures/sample.epub',
            onPageRendered: () {},
            onError: (_) {},
            navZoneActions: actions,
            onZoneAction: (action) => triggered = action,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final cancelledGesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('nav_zone_4'))),
      );
      await cancelledGesture.cancel();
      await tester.pump();

      expect(triggered, isNull);

      await tester.tap(find.byKey(const Key('nav_zone_4')));
      await tester.pump();
      expect(triggered, ZoneAction.menu);
    });
  });

  group('ES 相容性 polyfill（診斷修正）', () {
    // 根因：epub.js/epubcfi.js/paginator.js（readest/foliate-js 釘定版本）
    // 在開書必經路徑無條件使用三個較新的 ES 內建方法——Object.groupBy／
    // Map.groupBy（ES2024，需 Chromium 117+）、Array.prototype.at()
    // （ES2022，需 Chromium 92+）、Array.prototype.findLastIndex()
    // （ES2023，需 Chromium 97+）。較舊的 Android System WebView（例如
    // 真機回報的 Mobiscribe WAVE，Chromium 91）三個都不支援：groupBy 那部
    // 分會讓任何 EPUB 直接拋出可觀察的例外；.at()/findLastIndex() 那部分
    // 則是在 loadItem()/loadReplaced()/分頁計算等更深層的呼叫點，這台裝置
    // 的 WebView 建置沒有開啟遠端 DevTools 除錯、無法直接看到例外訊息，
    // 症狀純粹是「畫面永遠停在載入指示器」。已用 @xmldom/xmldom 及未經修
    // 改的實際 epub.js／epubcfi.js 重現並驗證這三個 polyfill 可修復（見
    // 診斷紀錄）。這裡只驗證 InAppWebView 確實在文件載入最早期
    // （AT_DOCUMENT_START）注入了含這三個 polyfill 的腳本；polyfill 本身
    // 的 JS 邏輯正確性已在 Node 環境對照真實 epub.js 驗證過，不在 widget
    // test 範圍內重複驗證。
    testWidgets(
        'InAppWebView 於 AT_DOCUMENT_START 注入 Object.groupBy/Map.groupBy/'
        'Array.prototype.at/Array.prototype.findLastIndex polyfill',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final scripts = webView.platform.params.initialUserScripts;
      expect(scripts, isNotNull);
      expect(scripts, hasLength(4));
      final script = scripts!.first;
      expect(script.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(script.source, contains('Object.groupBy'));
      expect(script.source, contains('Map.groupBy'));
      expect(script.source, contains('Array.prototype.at'));
      expect(script.source, contains('Array.prototype.findLastIndex'));
    });

    testWidgets(
        'ES compat polyfill 本體不含邏輯賦值運算子（??=／||=／&&=），'
        '避免 Chromium 85 之前的 WebView 在解析階段整份腳本失敗'
        '（epic-18-reader-device-qa Issue 38，真機使用回報：iReader Ocean 4 '
        'Plus 系統 WebView 為 Chromium 83，早於 ??= 語法需要的 Chromium 85，'
        'JS 引擎會在執行任何程式碼之前完整解析整份腳本，任何一處語法錯誤都會讓'
        '整份腳本（含 Object.groupBy／Map.groupBy／Array.prototype.at／'
        'Array.prototype.findLastIndex 全部 4 個 polyfill）完全不執行）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final scripts = webView.platform.params.initialUserScripts;
      final polyfillScript = scripts!.first;
      expect(polyfillScript.source, isNot(contains('??=')));
      expect(polyfillScript.source, isNot(contains('||=')));
      expect(polyfillScript.source, isNot(contains('&&=')));
    });

    testWidgets(
        'ES compat polyfill 含 String.prototype.replaceAll／WeakRef 防護'
        '（epic-18-reader-device-qa Issue 41，iReader Ocean 4 Plus 系統 '
        'WebView 為 Chromium 83，早於 replaceAll 需要的 85／WeakRef 需要的 '
        '84，epub.js 的字型反混淆與 view.js 的 media overlay 功能會用到）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final scripts = webView.platform.params.initialUserScripts;
      final polyfillScript = scripts!.first;
      expect(polyfillScript.source, contains('String.prototype.replaceAll'));
      expect(polyfillScript.source, contains('WeakRef'));
    });

    testWidgets(
        'replaceAll polyfill 函式型 replacement 明確拋出例外，不再靜默把'
        '函式原始碼文字字面插入結果字串（程式碼審查修正，'
        'tmp/epic-18/review-issue-38-41.md Important #1）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final scripts = webView.platform.params.initialUserScripts;
      final polyfillScript = scripts!.first;
      expect(
        polyfillScript.source,
        contains("typeof replacement === 'function'"),
      );
      expect(
        polyfillScript.source,
        contains('replaceAll polyfill 尚未實作函式型 replacement'),
      );
      expect(polyfillScript.source, contains(r'\$(\$|&)'),
          reason: '應展開 \$\$／\$& 兩種替換樣式，不再只是純字面插入');
    });

    testWidgets(
        'WeakRef polyfill 內含強參照模擬的權衡取捨說明註解（程式碼審查修正，'
        'tmp/epic-18/review-issue-38-41.md Important #2）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final scripts = webView.platform.params.initialUserScripts;
      final polyfillScript = scripts!.first;
      expect(polyfillScript.source, contains('僅用強參照模擬'));
    });

    // epic-18-reader-device-qa Issue 33：iReader Ocean 4 Plus 開書卡住問題
    // 沒有任何真機診斷資料佐證確切根因（報告 5 個推測皆未經真機驗證），
    // 這裡先建立診斷能力——全局 JS 錯誤捕捉能抓到 main.js 既有
    // try/catch（openBook() 本體）涵蓋範圍之外的失敗，包含 view.js／
    // epub.js／paginator.js 等釘定 vendor 腳本在文件載入極早期（甚至
    // main.js 本身的 try/catch 尚未有機會執行）就拋出的例外——這正是
    // 舊版 WebView 缺少 ES 內建方法時最典型的失敗模式（見上方
    // _esCompatPolyfillJs 的既有診斷紀錄）。透過 AT_DOCUMENT_START
    // 注入、重用既有的 onError JS↔Dart bridge channel（見
    // _onWebViewCreated 的 'onError' handler），不需要新增任何 Dart 端
    // 接線。
    testWidgets(
        'InAppWebView 於 AT_DOCUMENT_START 注入 applyPreferences 佇列 shim，'
        '避免 main.js 尚未載入完成前呼叫 window.applyPreferences 拋出 '
        'TypeError（epic-18-reader-device-qa Issue 39，真機使用回報：'
        'ViWoods Air Reader C，Uncaught TypeError: window.applyPreferences '
        'is not a function）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final scripts = webView.platform.params.initialUserScripts;
      expect(scripts, hasLength(4));
      final shimScript = scripts![1];
      expect(
          shimScript.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(shimScript.source, contains('window.__pendingApplyPreferences'));
      expect(shimScript.source, contains('window.applyPreferences'));
    });

    testWidgets(
        'InAppWebView 於 AT_DOCUMENT_START 注入全局 JS 錯誤捕捉（window.onerror／'
        'window.onunhandledrejection），重用既有 onError bridge channel',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final scripts = webView.platform.params.initialUserScripts;
      expect(scripts, hasLength(4));
      final script = scripts![2];
      expect(script.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(script.source, contains('window.onerror'));
      expect(script.source, contains('window.onunhandledrejection'));
      expect(script.source, contains("callHandler('onError'"),
          reason: '必須重用既有的 onError bridge channel，不新增獨立 handler');
    });

    // epic-18-reader-device-qa Issue 33（程式碼審查建議）：定位「舊版
    // WebView 引擎不支援特定 API」這類相容性缺口時，User Agent 字串
    // （含 Chromium 版本號）是最直接的起點線索。直接用標準 console.log
    // 輸出，沿用既有、已測試過的 onConsoleMessage →
    // handleFoliateConsoleMessage → ReaderConsoleLog 管線。
    testWidgets(
        'InAppWebView 於 AT_DOCUMENT_START 注入 navigator.userAgent 診斷紀錄',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final scripts = webView.platform.params.initialUserScripts;
      expect(scripts, hasLength(4));
      final script = scripts!.last;
      expect(script.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(script.source, contains('navigator.userAgent'));
      expect(script.source, contains('console.log'));
    });

    // epic-18-reader-device-qa Issue 33：iReader Ocean 4 Plus 這類裝置若
    // WebView 建置沒有開啟 setWebContentsDebuggingEnabled，無法用
    // chrome://inspect 遠端除錯，App 內建的 Console Log 檢視畫面是唯一
    // 能取得實際 JS console 輸出的管道。InAppWebView 的 onConsoleMessage
    // 確實有被賦值（結構性驗證，比照 resolveCustomFontUri／
    // _shouldInterceptRequest 的既有先例——FakePlatformInAppWebViewWidget
    // 底下無法真正觸發完整的 callback 型別鏈，故實際的訊息處理邏輯抽成
    // 下方 handleFoliateConsoleMessage 純函式獨立測試）。
    testWidgets('InAppWebView 的 onConsoleMessage 已被賦值', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      expect(webView.platform.params.onConsoleMessage, isNotNull);
    });
  });

  group('handleFoliateConsoleMessage', () {
    setUp(() {
      ReaderConsoleLog.clear();
    });

    test('把 messageLevel 與 message 組成單行文字附加到 ReaderConsoleLog', () {
      handleFoliateConsoleMessage('測試訊息', 'LOG', consoleLogEnabled: true);

      expect(ReaderConsoleLog.entries.value, hasLength(1));
      expect(ReaderConsoleLog.entries.value.single, '[LOG] 測試訊息');
    });

    test('可連續呼叫多次，依序附加不覆蓋既有訊息', () {
      handleFoliateConsoleMessage('第一筆', 'LOG', consoleLogEnabled: true);
      handleFoliateConsoleMessage('第二筆', 'ERROR', consoleLogEnabled: true);

      expect(ReaderConsoleLog.entries.value, ['[LOG] 第一筆', '[ERROR] 第二筆']);
    });

    test('consoleLogEnabled 為 false 時，LOG／WARNING 等非 ERROR 等級不寫入', () {
      handleFoliateConsoleMessage('一般訊息', 'LOG', consoleLogEnabled: false);
      handleFoliateConsoleMessage('警告訊息', 'WARNING', consoleLogEnabled: false);

      expect(ReaderConsoleLog.entries.value, isEmpty);
    });

    test('consoleLogEnabled 為 false 時，ERROR 等級仍強制寫入（崩潰診斷能力不受開關影響）',
        () {
      handleFoliateConsoleMessage('例外訊息', 'ERROR', consoleLogEnabled: false);

      expect(ReaderConsoleLog.entries.value, ['[ERROR] 例外訊息']);
    });

    test('consoleLogEnabled 為 false 時，ERROR 與 LOG 混合呼叫，只有 ERROR 被記錄',
        () {
      handleFoliateConsoleMessage('一般訊息', 'LOG', consoleLogEnabled: false);
      handleFoliateConsoleMessage('例外訊息', 'ERROR', consoleLogEnabled: false);
      handleFoliateConsoleMessage('警告訊息', 'WARNING', consoleLogEnabled: false);

      expect(ReaderConsoleLog.entries.value, ['[ERROR] 例外訊息']);
    });
  });

  // Epic 20 Issue 3 計畫審查 Minor #1：isDualPageEnabled 的 Dart 端 truth
  // table 測試——移植自 EpubReaderView.kt:149-151 既有的 Kotlin 邏輯，
  // 與 main.js 的 JS 版本邏輯完全一致。本測試無法直接驗證 JS 端行為（無
  // JS 測試框架），但作為可執行文件確保四種組合的預期結果被記錄且可回歸
  // 檢查；若未來 Dart 端需要相同邏輯（例如 PDF 路徑），可直接參考此處。
  group('isDualPageEnabled truth table（可執行文件）', () {
    /// 等效於 main.js 的 isDualPageEnabled(dualPageMode, isLandscape)
    /// 與 EpubReaderView.kt:149-151 的邏輯
    bool isDualPageEnabled(String dualPageMode, bool isLandscape) {
      return dualPageMode == 'always' ||
          (dualPageMode == 'auto' && isLandscape);
    }

    test('always + landscape → true', () {
      expect(isDualPageEnabled('always', true), isTrue);
    });

    test('always + portrait → true', () {
      expect(isDualPageEnabled('always', false), isTrue);
    });

    test('auto + landscape → true', () {
      expect(isDualPageEnabled('auto', true), isTrue);
    });

    test('auto + portrait → false', () {
      expect(isDualPageEnabled('auto', false), isFalse);
    });

    test('never + landscape → false', () {
      expect(isDualPageEnabled('never', true), isFalse);
    });

    test('never + portrait → false', () {
      expect(isDualPageEnabled('never', false), isFalse);
    });
  });

  // Epic 27 Issue 9 審查 Minor #1：main.js 的 no-swipe 屬性設定原本完全
  // 沒有自動化回歸防呆。審查建議比照 check_foliate_es_compat.js 寫一支
  // Node 靜態掃描腳本，但該腳本的既有觸發時機是「升級 foliate/ 釘定版本
  // 後才跑」（見 app/tool/README.md）——對「有人在不相關的 openBook()
  // 重構中不小心刪掉/搬動這一行」這個真正的風險情境完全不會被觸發到。
  // 改用 flutter test 直接讀取 main.js 原始碼字串斷言：本專案沒有接
  // CI（見 app/tool/README.md），flutter test 是唯一在每個 Issue 驗收
  // 標準都明文要求執行的既有關卡，比獨立 Node 腳本更可能被實際跑到。
  group('main.js no-swipe 屬性 regression guard（Epic 27 Issue 9）', () {
    late String mainJsSource;

    setUpAll(() {
      mainJsSource = File('android/app/src/main/assets/foliate/main.js')
          .readAsStringSync();
    });

    test('openBook() 內設定 no-swipe 屬性，且位置晚於 await view.open(book)',
        () {
      const openCall = 'await view.open(book)';
      const noSwipeCall = "view.renderer.setAttribute('no-swipe', '')";

      final openIndex = mainJsSource.indexOf(openCall);
      final noSwipeIndex = mainJsSource.indexOf(noSwipeCall);

      expect(openIndex, greaterThanOrEqualTo(0),
          reason: 'main.js 內找不到 "$openCall"——若上游改了寫法，'
              '下面的順序斷言也需要一併更新。');
      expect(noSwipeIndex, greaterThanOrEqualTo(0),
          reason: 'main.js 內找不到 "$noSwipeCall"——這一行負責停用 '
              'paginator.js 內建滑動翻頁（見 '
              'docs/epics/epic-27-reader-device-compat/reviews/'
              'bugfix-repro.md「Issue 9」根因 B），若被刪掉，長按選字/'
              '拖曳劃線手勢會重新容易誤觸翻頁。');
      expect(noSwipeIndex, greaterThan(openIndex),
          reason: '"$noSwipeCall" 必須晚於 "$openCall"——view.renderer 是 '
              'view.open() 內部同步賦值，寫在它之前會存取到 null。');
    });
  });

  // Issue 8 審查 Important #7：mounted 守衛/dispose 競態測試
  // 驗證「快取完成前 dispose」不會導致快取目錄洩漏
  group('mounted guard / dispose race', () {
    testWidgets('dispose during cache does not leak cache directory', (tester) async {
      final completer = Completer<String?>();
      cacheBookForServing = (filePath, instanceId) async {
        return completer.future;
      };

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      ));

      // 移除 widget（觸發 dispose），此時快取尚未完成
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));

      // 讓 Future 完成，不應拋出例外
      completer.complete('/fake/cache/dir/current.epub');
      await tester.pump();
    });

    testWidgets('cache failure calls onError', (tester) async {
      cacheBookForServing = (filePath, instanceId) async {
        return null;
      };

      String? receivedError;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: (msg) => receivedError = msg,
          ),
        ),
      ));

      await tester.pump();
      expect(receivedError, '無法快取書籍檔案');
    });

    testWidgets(
        'cacheBookForServing 拋出例外時（epic-18-reader-device-qa Issue 33），'
        '呼叫 onError 帶入例外訊息，不會讓畫面永遠卡在載入指示器',
        (tester) async {
      cacheBookForServing = (filePath, instanceId) async {
        throw Exception('模擬檔案系統錯誤');
      };

      String? receivedError;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FoliateReaderView(
            filePath: '/tmp/sample.epub',
            onPageRendered: _noop,
            onError: (msg) => receivedError = msg,
          ),
        ),
      ));

      await tester.pump();
      expect(receivedError, contains('快取書籍失敗'));
      expect(receivedError, contains('模擬檔案系統錯誤'));
    });
  });

  tearDownAll(() {
    // 還原 cacheBookForServing 為原始實作，避免污染其他測試檔
    cacheBookForServing = originalCacheBookForServing;
  });
}
