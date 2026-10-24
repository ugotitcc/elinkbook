import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/open_book_trace.dart';
import 'package:elinkbook/reader/reader_console_log.dart';

void main() {
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 10, 24, 12, 0, 0);
    OpenBookTrace.clock = () => now;
    ReaderConsoleLog.clock = () => now;
    ReaderConsoleLog.clear();
    OpenBookTrace.startSession();
  });

  tearDown(() {
    OpenBookTrace.clock = DateTime.now;
    ReaderConsoleLog.clock = DateTime.now;
    ReaderConsoleLog.clear();
    OpenBookTrace.startSession();
  });

  group('record', () {
    test('寫入 ReaderConsoleLog，格式為 [OpenBook#<編號>] <階段> <細節>', () {
      OpenBookTrace.record('101', '開書開始', 'epub');

      expect(ReaderConsoleLog.entries.value, hasLength(1));
      expect(ReaderConsoleLog.entries.value.single,
          endsWith('[OpenBook#101] 開書開始 epub'));
    });

    test('沒有細節時，尾端沒有空白', () {
      OpenBookTrace.record('101', 'WebView 建立');

      expect(ReaderConsoleLog.entries.value.single,
          endsWith('[OpenBook#101] WebView 建立'));
    });

    test('細節是空字串時，視同沒有細節', () {
      OpenBookTrace.record('101', 'WebView 建立', '');

      expect(ReaderConsoleLog.entries.value.single,
          endsWith('[OpenBook#101] WebView 建立'));
    });
  });

  group('timeoutSummary', () {
    test('本次開書沒有任何記錄：回「沒有任何階段記錄」', () {
      expect(OpenBookTrace.timeoutSummary(), '沒有任何階段記錄');
    });

    test('反映最後一筆，含細節、實例編號與距今秒數', () {
      OpenBookTrace.record('101', '開書開始', 'epub');
      OpenBookTrace.record('101', '書複製失敗', '回傳 null（耗時 12 ms）');
      now = now.add(const Duration(seconds: 31));

      expect(
        OpenBookTrace.timeoutSummary(),
        '最後階段：書複製失敗 回傳 null（耗時 12 ms）（實例 #101，距今 31 秒）',
      );
    });

    test('最後一筆沒有細節時，不多出空白', () {
      OpenBookTrace.record('7', 'WebView 建立');

      expect(
        OpenBookTrace.timeoutSummary(),
        '最後階段：WebView 建立（實例 #7，距今 0 秒）',
      );
    });
  });

  group('startSession', () {
    test('清掉前一本書的最後階段（例如「離開畫面」）', () {
      OpenBookTrace.record('101', '離開畫面', '已刪快取目錄=是');

      OpenBookTrace.startSession();

      expect(OpenBookTrace.timeoutSummary(), '沒有任何階段記錄');
    });

    test('不清 ReaderConsoleLog（使用者還要看歷史）', () {
      OpenBookTrace.record('101', '離開畫面');

      OpenBookTrace.startSession();

      expect(ReaderConsoleLog.entries.value, hasLength(1));
    });
  });

  group('recordTimeout', () {
    test('寫一行「開書逾時」，內含逾時前的最後階段，而不是它自己', () {
      OpenBookTrace.record('101', '頁面載入開始', '/assets/foliate/index.html');
      now = now.add(const Duration(seconds: 30));

      OpenBookTrace.recordTimeout();

      final last = ReaderConsoleLog.entries.value.last;
      expect(last, contains('[OpenBook#-] 開書逾時'));
      expect(
        last,
        contains(
          '最後階段：頁面載入開始 /assets/foliate/index.html（實例 #101，距今 30 秒）',
        ),
      );
    });

    test('沒有任何階段記錄時，仍寫一行逾時', () {
      OpenBookTrace.recordTimeout();

      expect(ReaderConsoleLog.entries.value.single,
          endsWith('[OpenBook#-] 開書逾時 沒有任何階段記錄'));
    });
  });
}
