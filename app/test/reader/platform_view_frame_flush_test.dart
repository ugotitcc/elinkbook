import 'package:elinkbook/reader/platform_view_frame_flush.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  testWidgets('補送指定數量的畫面，補完就停止，不會一直排程', (tester) async {
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.hasScheduledFrame, isFalse);

    flushFramesAfterPlatformViewRemoved(frames: 12);
    expect(tester.binding.hasScheduledFrame, isTrue, reason: '呼叫後要排好第一個畫面');

    // 送出一半（5 個）畫面後，還有後續畫面排著。
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.binding.hasScheduledFrame, isTrue, reason: '還沒補完');

    // 補完後不再排程（電子紙不能一直重繪）。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.binding.hasScheduledFrame, isFalse, reason: '補完就停止');
  });

  testWidgets('frames 為 0 或負數時不排任何畫面', (tester) async {
    await tester.pumpWidget(const SizedBox());
    flushFramesAfterPlatformViewRemoved(frames: 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
