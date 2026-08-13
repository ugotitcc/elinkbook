import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tap_zone_detector.dart';

void main() {
  Widget wrap({
    required VoidCallback onTap,
    required int Function() nowMs,
    int tapMaxDurationMs = 400,
    double tapSlop = 18.0,
  }) {
    return MaterialApp(
      home: TapZoneDetector(
        onTap: onTap,
        nowMs: nowMs,
        tapMaxDurationMs: tapMaxDurationMs,
        tapSlop: tapSlop,
        child: const SizedBox(width: 100, height: 100),
      ),
    );
  }

  testWidgets('按下與放開耗時在門檻內、位移在容許範圍內時觸發 onTap', (tester) async {
    var tapped = false;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapped = true,
      nowMs: () => fakeNowMs,
    ));

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 100;
    await gesture.up();
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('耗時超過門檻時不觸發 onTap', (tester) async {
    var tapped = false;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapped = true,
      nowMs: () => fakeNowMs,
      tapMaxDurationMs: 400,
    ));

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 500;
    await gesture.up();
    await tester.pump();

    expect(tapped, isFalse);
  });

  testWidgets('位移超過容許範圍時不觸發 onTap（即使耗時在門檻內）', (tester) async {
    var tapped = false;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapped = true,
      nowMs: () => fakeNowMs,
      tapSlop: 18.0,
    ));

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await gesture.moveTo(const Offset(50, 90)); // 位移 40px > 18px
    await gesture.up();
    await tester.pump();

    expect(tapped, isFalse);
  });

  testWidgets(
      'onPointerCancel 不會拋出例外，取消手勢本身不觸發 onTap，後續正常點擊仍正確判定',
      (tester) async {
    var tapped = false;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapped = true,
      nowMs: () => fakeNowMs,
    ));

    final cancelledGesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 100;
    await cancelledGesture.cancel();
    await tester.pump();

    expect(tapped, isFalse);

    final normalGesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 100;
    await normalGesture.up();
    await tester.pump();

    expect(tapped, isTrue);
  });
}
