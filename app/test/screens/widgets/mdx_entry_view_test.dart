import 'package:elinkbook/screens/widgets/mdx_entry_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// Epic 63 Issue 6a Task 7：`MdxEntryView` 的兩個決策函式是純函式，這裡只測
/// 判斷結果，不建 `InAppWebView`（真機行為由整合測試涵蓋）。
void main() {
  group('decideNavigation', () {
    test('entry://apple 取消導航並帶出詞條文字', () {
      final decision = MdxEntryView.decideNavigation('entry://apple');

      expect(decision.allow, isFalse);
      expect(decision.entryWord, 'apple');
    });

    test('entry:// 的 percent-encoding 與結尾斜線都會還原', () {
      final decision = MdxEntryView.decideNavigation(
        'entry://%E5%A4%A9%E5%9C%B0/',
      );

      expect(decision.allow, isFalse);
      expect(decision.entryWord, '天地');
    });

    test('bword:// 與 entry:// 同樣視為詞條連結', () {
      final decision = MdxEntryView.decideNavigation('bword://apple');

      expect(decision.allow, isFalse);
      expect(decision.entryWord, 'apple');
    });

    test('entry://#錨點 是頁內錨點，交給 WebView 放行', () {
      final decision = MdxEntryView.decideNavigation('entry://#x');

      expect(decision.allow, isTrue);
      expect(decision.entryWord, isNull);
    });

    test('#x 放行', () {
      final decision = MdxEntryView.decideNavigation('#x');

      expect(decision.allow, isTrue);
      expect(decision.entryWord, isNull);
    });

    test('外部、檔案與音訊連結一律取消且不帶詞條', () {
      for (final url in [
        'https://example.com',
        'http://example.com/a',
        'file:///x',
        'sound://a',
        'javascript:alert(1)',
        'data:text/html,hi',
        '',
      ]) {
        final decision = MdxEntryView.decideNavigation(url);
        expect(decision.allow, isFalse, reason: url);
        expect(decision.entryWord, isNull, reason: url);
      }
    });
  });

  group('decideNavigation：自動觸發的導覽（I-7）', () {
    test('子框架（iframe）的 entry:// 取消且不帶詞條', () {
      final decision = MdxEntryView.decideNavigation(
        'entry://apple',
        isForMainFrame: false,
        hasGesture: true,
      );

      expect(decision.allow, isFalse);
      expect(decision.entryWord, isNull);
    });

    test('子框架的錨點也不放行', () {
      final decision = MdxEntryView.decideNavigation(
        '#x',
        isForMainFrame: false,
      );

      expect(decision.allow, isFalse);
    });

    test('主框架但沒有使用者手勢（hasGesture == false）的 entry:// 不帶詞條', () {
      final decision = MdxEntryView.decideNavigation(
        'entry://apple',
        isForMainFrame: true,
        hasGesture: false,
      );

      expect(decision.allow, isFalse);
      expect(decision.entryWord, isNull);
    });

    test('主框架且有手勢：照常帶出詞條', () {
      final decision = MdxEntryView.decideNavigation(
        'entry://apple',
        isForMainFrame: true,
        hasGesture: true,
      );

      expect(decision.entryWord, 'apple');
    });

    test('平台沒有提供 hasGesture（null）時，只看是否為主框架', () {
      final decision = MdxEntryView.decideNavigation(
        'entry://apple',
        isForMainFrame: true,
        hasGesture: null,
      );

      expect(decision.entryWord, 'apple');
    });

    test('主框架錨點不受 hasGesture 影響', () {
      expect(
        MdxEntryView.decideNavigation('#x', hasGesture: false).allow,
        isTrue,
      );
    });
  });

  group('decideRequest', () {
    test('data: 初始文件交還 WebView，其餘請求一律 404 空本文', () {
      expect(
        MdxEntryView.decideRequest(
          'data:text/html;charset=utf-8;base64,PGh0bWw+',
        ),
        isNull,
      );
      for (final url in [
        'https://dict.local/pic/a.png',
        'https://dict.local/favicon.ico',
        'https://dict.local/style.css',
        'https://example.com/a.png',
        'http://example.com',
        'file:///x',
        'entry://apple',
      ]) {
        final decision = MdxEntryView.decideRequest(url)!;
        expect(decision.statusCode, 404, reason: url);
        expect(decision.body, isEmpty, reason: url);
      }
    });
  });
}
