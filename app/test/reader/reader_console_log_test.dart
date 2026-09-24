import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/reader_console_log.dart';

void main() {
  // 固定時鐘，讓時間戳可預期（每次 add() 之間不推進時間）。
  final fixedNow = DateTime(2026, 9, 24, 14, 39, 51, 123);

  setUp(() {
    ReaderConsoleLog.clear();
    ReaderConsoleLog.clock = () => fixedNow;
  });

  tearDown(() {
    ReaderConsoleLog.clock = DateTime.now;
  });

  test('add() 把訊息附加到 entries，並在開頭加上時間戳', () {
    ReaderConsoleLog.add('第一筆訊息');
    ReaderConsoleLog.add('第二筆訊息');

    expect(ReaderConsoleLog.entries.value, [
      '14:39:51.123 第一筆訊息',
      '14:39:51.123 第二筆訊息',
    ]);
  });

  test('時間戳為 24 小時制 HH:mm:ss.SSS，各欄位補零', () {
    ReaderConsoleLog.clock = () => DateTime(2026, 1, 2, 3, 4, 5, 6);

    ReaderConsoleLog.add('訊息');

    expect(ReaderConsoleLog.entries.value.single, '03:04:05.006 訊息');
  });

  test('時間戳隨時鐘推進，可分辨同一秒內事件的先後', () {
    ReaderConsoleLog.clock = () => DateTime(2026, 9, 24, 14, 39, 51, 100);
    ReaderConsoleLog.add('先發生');
    ReaderConsoleLog.clock = () => DateTime(2026, 9, 24, 14, 39, 51, 850);
    ReaderConsoleLog.add('後發生');

    expect(ReaderConsoleLog.entries.value, [
      '14:39:51.100 先發生',
      '14:39:51.850 後發生',
    ]);
  });

  test('clear() 清空 entries', () {
    ReaderConsoleLog.add('訊息');
    ReaderConsoleLog.clear();

    expect(ReaderConsoleLog.entries.value, isEmpty);
  });

  test('超過上限筆數時，捨棄最舊的訊息、只保留最新的 500 筆', () {
    for (var i = 0; i < 510; i++) {
      ReaderConsoleLog.add('訊息 $i');
    }

    expect(ReaderConsoleLog.entries.value, hasLength(500));
    expect(ReaderConsoleLog.entries.value.first, '14:39:51.123 訊息 10',
        reason: '最舊的 10 筆（訊息 0-9）應被捨棄');
    expect(ReaderConsoleLog.entries.value.last, '14:39:51.123 訊息 509');
  });
}
