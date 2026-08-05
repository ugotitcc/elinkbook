import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/reader_console_log.dart';

void main() {
  setUp(() {
    ReaderConsoleLog.clear();
  });

  test('add() 把訊息附加到 entries', () {
    ReaderConsoleLog.add('第一筆訊息');
    ReaderConsoleLog.add('第二筆訊息');

    expect(ReaderConsoleLog.entries.value, ['第一筆訊息', '第二筆訊息']);
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
    expect(ReaderConsoleLog.entries.value.first, '訊息 10',
        reason: '最舊的 10 筆（訊息 0-9）應被捨棄');
    expect(ReaderConsoleLog.entries.value.last, '訊息 509');
  });
}
