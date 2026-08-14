import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'pump_until_pdf_ready.dart';

void main() {
  testWidgets('condition 省略時（null），確實跑滿 maxIterations 輪（以真實耗時下限驗證，'
      '而非只驗證「不拋例外」——避免 null 分支被誤判為提前終止卻測不出來）',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    final stopwatch = Stopwatch()..start();
    await pumpUntilPdfReady(
      tester,
      maxIterations: 3,
      delayBetweenPumps: const Duration(milliseconds: 20),
    );
    stopwatch.stop();

    // delayBetweenPumps 是跳出 fake zone（runAsync）後的真實
    // Future.delayed，3 輪至少累積 3*20=60ms 真實耗時；用「至少」而非
    // 精確比對，避免測試環境時序 jitter 造成 flaky。若 condition==null
    // 分支被誤寫成提前跳出（例如迴圈只跑 1 輪就停），耗時會遠低於
    // 60ms，這則測試就會抓到。
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(60),
        reason: 'condition 為 null 時應無條件跑滿 3 輪，每輪至少 20ms 真實延遲，'
            '總耗時應 >= 60ms；耗時遠低於此代表迴圈未跑滿或 null 分支邏輯有誤');
  });

  testWidgets('condition 提前滿足時，提前跳出、不跑滿 maxIterations', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    var callCount = 0;

    await pumpUntilPdfReady(
      tester,
      condition: () {
        callCount++;
        return callCount >= 2; // 第 2 次呼叫就回傳 true，應提前跳出
      },
      maxIterations: 100,
      delayBetweenPumps: Duration.zero,
    );

    expect(callCount, 2, reason: 'condition 在第 2 次呼叫回傳 true，迴圈應立即停止，'
        '不應繼續呼叫到第 3 次（若繼續呼叫代表提前跳出邏輯有誤）');
  });

  testWidgets('maxIterations 上限確實生效（condition 永遠不滿足時）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    var callCount = 0;

    await pumpUntilPdfReady(
      tester,
      condition: () {
        callCount++;
        return false; // 永遠不滿足
      },
      maxIterations: 3,
      delayBetweenPumps: Duration.zero,
    );

    expect(callCount, 3, reason: 'condition 永遠回傳 false 時，迴圈應恰好跑滿 '
        'maxIterations=3 輪後停止，不多不少');
  });
}
