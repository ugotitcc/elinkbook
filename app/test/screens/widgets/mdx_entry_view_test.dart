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

  group('decideRequest', () {
    test('所有 http(s) 請求都回 404 空本文，永不回傳 null', () {
      for (final url in [
        'https://dict.local/pic/a.png',
        'https://dict.local/favicon.ico',
        'https://dict.local/style.css',
        'https://example.com/a.png',
        'http://example.com',
        'file:///x',
        'entry://apple',
      ]) {
        final decision = MdxEntryView.decideRequest(url);
        expect(decision.statusCode, 404, reason: url);
        expect(decision.body, isEmpty, reason: url);
      }
    });
  });
}
