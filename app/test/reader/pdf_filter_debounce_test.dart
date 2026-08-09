import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_filter_debounce.dart';

void main() {
  test('單次 schedule 延遲後執行一次', () {
    fakeAsync((async) {
      final debouncer = PdfFilterDebouncer(delay: const Duration(milliseconds: 300));
      var callCount = 0;
      debouncer.schedule(() => callCount++);
      async.elapse(const Duration(milliseconds: 299));
      expect(callCount, 0, reason: '延遲時間未到不應執行');
      async.elapse(const Duration(milliseconds: 1));
      expect(callCount, 1);
      debouncer.dispose();
    });
  });

  test('延遲時間內多次 schedule 只執行最後一次的 action', () {
    fakeAsync((async) {
      final debouncer = PdfFilterDebouncer(delay: const Duration(milliseconds: 300));
      final calls = <int>[];
      debouncer.schedule(() => calls.add(1));
      async.elapse(const Duration(milliseconds: 100));
      debouncer.schedule(() => calls.add(2));
      async.elapse(const Duration(milliseconds: 100));
      debouncer.schedule(() => calls.add(3));
      async.elapse(const Duration(milliseconds: 300));
      expect(calls, [3]);
      debouncer.dispose();
    });
  });

  test('dispose 後不再執行任何已排程的 action', () {
    fakeAsync((async) {
      final debouncer = PdfFilterDebouncer(delay: const Duration(milliseconds: 300));
      var callCount = 0;
      debouncer.schedule(() => callCount++);
      debouncer.dispose();
      async.elapse(const Duration(milliseconds: 300));
      expect(callCount, 0);
    });
  });
}
