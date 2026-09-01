import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tap_zone_detector.dart';

void main() {
  Widget wrap({
    required VoidCallback onTap,
    required int Function() nowMs,
    int tapMaxDurationMs = 400,
    double tapSlop = 18.0,
    int tapDebounceMs = 350,
    void Function(String message)? onDebugEvent,
  }) {
    return MaterialApp(
      home: TapZoneDetector(
        onTap: onTap,
        nowMs: nowMs,
        tapMaxDurationMs: tapMaxDurationMs,
        tapSlop: tapSlop,
        tapDebounceMs: tapDebounceMs,
        onDebugEvent: onDebugEvent,
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

  testWidgets(
      '拖曳中途超過容許位移範圍後，即使放開時位置回到容許範圍內，仍不觸發 onTap（epic-27-reader-device-compat Issue 9：模擬選字/劃線手勢中途小幅拖曳後手指移回原點附近才放開）',
      (tester) async {
    var tapped = false;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapped = true,
      nowMs: () => fakeNowMs,
      tapSlop: 18.0,
    ));

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await gesture.moveTo(const Offset(50, 90)); // 位移 40px > 18px，途中已超過容許範圍
    fakeNowMs += 50;
    await gesture.moveTo(const Offset(50, 52)); // 放開前移回幾乎原點，此刻與按下點僅距 2px < 18px
    await gesture.up();
    await tester.pump();

    expect(tapped, isFalse,
        reason: '目前實作只在 onPointerUp 那一瞬間比較距離，中途曾超過 tapSlop '
            '這件事沒有被記住，放開時位置又落回容許範圍內會被誤判為一次快速點擊'
            '——這正是使用者真機回報「劃線時容易誤觸翻頁」的其中一種真實手勢形狀，'
            '本測試在加入 onPointerMove 熔斷前應為 FAIL（tapped 會是 true）');
  });

  testWidgets('短時間內同一格熱區收到第二次觸發時，只有第一次觸發 onTap（防彈跳機制）', (tester) async {
    var tapCount = 0;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapCount++,
      nowMs: () => fakeNowMs,
      tapDebounceMs: 350,
    ));

    // 第一次點擊：耗時 50ms 放開
    final gesture1 = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await gesture1.up();
    await tester.pump();
    expect(tapCount, 1);

    // 第二次點擊（間隔 100ms < 350ms）：耗時 50ms 放開，應被防彈跳機制過濾
    fakeNowMs += 100;
    final gesture2 = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await gesture2.up();
    await tester.pump();
    expect(tapCount, 1);
  });

  testWidgets(
      '重現真機 adb getevent 側錄到的實際硬體彈跳間隔序列，連續 7 次快速觸發只會觸發 1 次 onTap',
      (tester) async {
    var tapCount = 0;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapCount++,
      nowMs: () => fakeNowMs,
      tapDebounceMs: 350,
    ));

    // 真機 adb getevent 側錄到的 6 段「按下→按下」（DOWN to DOWN）事件
    // 間隔（毫秒）：[86, 152, 261, 326, 87, 207]。
    final bounceIntervalsMs = [86, 152, 261, 326, 87, 207];

    // 第 1 次觸發
    final firstGesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 20;
    await firstGesture.up();
    await tester.pump();
    expect(tapCount, 1);

    // 後續 6 次硬體彈跳觸發（間隔皆小於 350ms）。迴圈內先扣掉本次模擬
    // 按壓耗時（20ms）再推進，確保兩次 startGesture() 之間量到的
    // DOWN-to-DOWN 間隔精確等於 interval 本身（而非 interval + 20）——
    // 審查修正（review-issue-12.md Important）：先前版本漏了這一步，
    // 導致重播出來的最大間隔是 346ms 而非真機實際側錄到的 326ms。
    for (final interval in bounceIntervalsMs) {
      fakeNowMs += interval - 20;
      final bounceGesture = await tester.startGesture(const Offset(50, 50));
      fakeNowMs += 20;
      await bounceGesture.up();
      await tester.pump();
    }

    expect(tapCount, 1,
        reason: '連續的硬體彈跳訊號在 350ms 窗口內應全數被吸收，只保留第 1 次 onTap');
  });

  testWidgets('間隔超過防彈跳門檻（400ms > 350ms）後再次點擊，仍正常觸發第二次 onTap',
      (tester) async {
    var tapCount = 0;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapCount++,
      nowMs: () => fakeNowMs,
      tapDebounceMs: 350,
    ));

    // 第一次點擊
    final gesture1 = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await gesture1.up();
    await tester.pump();
    expect(tapCount, 1);

    // 間隔 400ms（超過 350ms 門檻）
    fakeNowMs += 400;

    // 第二次點擊
    final gesture2 = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await gesture2.up();
    await tester.pump();
    expect(tapCount, 2);
  });

  test('kTapZoneSlop 為 EPUB／PDF 共用的位移容許值 18.0', () {
    expect(kTapZoneSlop, 18.0);
  });

  test('kTapZoneDebounceMs 為 EPUB／PDF 共用的防彈跳門檻 350ms', () {
    expect(kTapZoneDebounceMs, 350);
  });

  testWidgets(
      '未明確傳入 tapSlop 時，建構子預設值等同 kTapZoneSlop——位移剛好超過 '
      'kTapZoneSlop 仍會被判定為超出容許範圍，不觸發 onTap',
      (tester) async {
    var tapped = false;
    var fakeNowMs = 1000;
    await tester.pumpWidget(
      MaterialApp(
        home: TapZoneDetector(
          onTap: () => tapped = true,
          nowMs: () => fakeNowMs,
          tapMaxDurationMs: 400,
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await gesture.moveTo(Offset(50, 50 + kTapZoneSlop + 1));
    await gesture.up();
    await tester.pump();

    expect(tapped, isFalse,
        reason: '若建構子預設值不是 kTapZoneSlop（例如意外退回舊的某個字面值），'
            '這個剛好超過 kTapZoneSlop 的位移可能不會被正確判定為超出範圍');
  });

  testWidgets(
      'onDebugEvent（Epic 26 Issue 3 暫時性真機診斷插樁）在合格點擊時回報 up qualified=true fired=true',
      (tester) async {
    final messages = <String>[];
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () {},
      nowMs: () => fakeNowMs,
      onDebugEvent: messages.add,
    ));

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 100;
    await gesture.up();
    await tester.pump();

    expect(
      messages,
      contains(
          '[DEBUG-e26i3] up qualified=true fired=true elapsed=100 distance=0.0 t=1100'),
    );
  });

  testWidgets(
      'onDebugEvent（Epic 26 Issue 3 暫時性真機診斷插樁）在超過時長門檻時回報 qualified=false reason=duration',
      (tester) async {
    final messages = <String>[];
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () {},
      nowMs: () => fakeNowMs,
      tapMaxDurationMs: 400,
      onDebugEvent: messages.add,
    ));

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 500;
    await gesture.up();
    await tester.pump();

    expect(
      messages,
      contains(
          '[DEBUG-e26i3] up qualified=false reason=duration elapsed=500 distance=0.0 t=1500'),
    );
  });
}

