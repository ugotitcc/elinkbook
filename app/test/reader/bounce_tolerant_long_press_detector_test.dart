import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/bounce_tolerant_long_press_detector.dart';

void main() {
  Widget wrap({
    required void Function(Offset) onLongPressStart,
    required void Function(Offset) onLongPressMoveUpdate,
    required VoidCallback onLongPressEnd,
    required VoidCallback onLongPressCancel,
    int? longPressDurationMs,
    int mergeGapMs = 350,
    double mergeSlop = 18.0,
  }) {
    return MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BounceTolerantLongPressDetector(
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressEnd: onLongPressEnd,
        onLongPressCancel: onLongPressCancel,
        longPressDurationMs: longPressDurationMs,
        mergeGapMs: mergeGapMs,
        mergeSlop: mergeSlop,
        child: const SizedBox(width: 400, height: 400),
      ),
    );
  }

  testWidgets(
      '重現裝置 2 真實彈跳間隔序列（tmp/epic-25/log-issue5/device-2.txt），'
      '長按仍能正確啟動且完整跑完一次生命週期', (tester) async {
    var startCount = 0;
    Offset? startPos;
    var moveCount = 0;
    Offset? lastMovePos;
    var endCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (p) {
        startCount++;
        startPos = p;
      },
      onLongPressMoveUpdate: (p) {
        moveCount++;
        lastMovePos = p;
      },
      onLongPressEnd: () => endCount++,
      onLongPressCancel: () => cancelCount++,
    ));

    // 真實裝置 2 彈跳序列（device-2.txt 前 21 行，相對第一次 down 的毫秒偏移
    // 與座標，已用腳本逐行核對過，非憑空編造）：
    // down t=0   (297.8,401.4)   up t=49
    // down t=69  (297.8,401.4)   up t=134
    // down t=183 (296.4,403.4)   up t=190
    // down t=196 (296.4,403.4)   up t=251
    // down t=253 (296.8,403.4)   up t=255
    // down t=257 (300.3,406.8)   up t=302
    // down t=313 (301.3,407.3)   up t=322
    // down t=399 (309.6,415.2)   up t=409
    // down t=413 (309.6,415.2)   up t=538   ← duration 500ms 門檻在這段區間內跨過
    // down t=548 (311.0,416.6)   up t=559
    // down t=564 (311.0,417.1)   up t=580
    final downTimes = [0, 69, 183, 196, 253, 257, 313, 399, 413, 548, 564];
    final downPositions = [
      const Offset(297.8, 401.4),
      const Offset(297.8, 401.4),
      const Offset(296.4, 403.4),
      const Offset(296.4, 403.4),
      const Offset(296.8, 403.4),
      const Offset(300.3, 406.8),
      const Offset(301.3, 407.3),
      const Offset(309.6, 415.2),
      const Offset(309.6, 415.2),
      const Offset(311.0, 416.6),
      const Offset(311.0, 417.1),
    ];
    final upTimes = [49, 134, 190, 251, 255, 302, 322, 409, 538, 559, 580];

    var lastEventTime = 0;
    for (var i = 0; i < downTimes.length; i++) {
      await tester.pump(Duration(milliseconds: downTimes[i] - lastEventTime));
      final gesture = await tester.startGesture(downPositions[i]);
      lastEventTime = downTimes[i];
      await tester.pump(Duration(milliseconds: upTimes[i] - lastEventTime));
      await gesture.up();
      lastEventTime = upTimes[i];
    }

    // 最後一次放開後，等待超過 mergeGapMs（350ms）且沒有新的延續事件，
    // 判定為真正結束。
    await tester.pump(const Duration(milliseconds: 400));

    expect(startCount, 1, reason: '整串彈跳應被判定成同一次長按，只啟動一次');
    expect(startPos, const Offset(297.8, 401.4),
        reason: '選取起點須固定為最早那次 down 的位置，不隨雜訊飄移');
    expect(moveCount, greaterThan(0),
        reason: '長按啟動後的延續 down（t=548／t=564）應視為位置更新');
    expect(lastMovePos, const Offset(311.0, 417.1));
    expect(endCount, 1, reason: '最終真正放開後應觸發一次 onLongPressEnd');
    expect(cancelCount, 0, reason: '已成功啟動長按，不應該觸發 onLongPressCancel');
  });

  testWidgets('位移超過 mergeSlop 的新 down 視為全新一次按壓，前一次未結束的按壓須先收到取消回呼',
      (tester) async {
    var startCount = 0;
    Offset? startPos;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (p) {
        startCount++;
        startPos = p;
      },
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () => cancelCount++,
    ));

    final first = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await first.up();

    // 間隔 30ms（< 350ms mergeGapMs），但位置差了 200px（> 18px mergeSlop）。
    await tester.pump(const Duration(milliseconds: 30));
    await tester.startGesture(const Offset(200, 200));

    // 從第二次 down 起算滿 500ms，應以第二次 down 的位置啟動長按。
    await tester.pump(const Duration(milliseconds: 500));

    expect(cancelCount, 1,
        reason: '第一次按壓被判定為與新按壓不相關時，須先收到一次取消回呼，'
            '不能被靜默丟棄（避免下游 _selectionDrag 狀態卡住殘留，'
            'review-plan-issue-5.md Critical #2）');
    expect(startCount, 1);
    expect(startPos, const Offset(200, 200),
        reason: '位移過大應判定為全新按壓，起點是新按壓的位置，不是舊按壓的 (0,0)');
  });

  testWidgets('放開後超過 mergeGapMs 沒有延續事件，判定真正取消；之後的新按壓仍可獨立啟動',
      (tester) async {
    var startCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) => startCount++,
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () => cancelCount++,
    ));

    final first = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await first.up();

    // 超過 mergeGapMs（350ms），沒有任何延續事件。
    await tester.pump(const Duration(milliseconds: 400));
    expect(cancelCount, 1, reason: '未達長按時長就真正放開，應觸發一次取消');
    expect(startCount, 0);

    // 之後一次全新、獨立的長按仍應正常運作。
    await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(startCount, 1, reason: '新的獨立按壓不受先前已取消的按壓影響');
  });

  testWidgets('長按啟動前位移超過 mergeSlop，判定為滑動手勢，直接取消、不會啟動長按',
      (tester) async {
    var startCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) => startCount++,
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () => cancelCount++,
    ));

    final gesture = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(const Offset(30, 0)); // 位移 30px > 18px mergeSlop
    await tester.pump(const Duration(milliseconds: 500));

    expect(cancelCount, 1);
    expect(startCount, 0,
        reason: '長按判定成立前若移動過大，應視為滑動手勢，比照原生 '
            'LongPressGestureRecognizer 行為直接取消');
  });

  testWidgets('長按啟動後拖曳中途發生雜訊，位置更新被吸收、不重新觸發啟動/取消',
      (tester) async {
    var startCount = 0;
    final movePositions = <Offset>[];
    var endCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) => startCount++,
      onLongPressMoveUpdate: (p) => movePositions.add(p),
      onLongPressEnd: () => endCount++,
      onLongPressCancel: () => cancelCount++,
    ));

    final gesture = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(startCount, 1);

    await gesture.moveTo(const Offset(50, 50));
    await tester.pump();
    expect(movePositions.last, const Offset(50, 50));

    // 拖曳中途的雜訊：短暫放開又立刻在幾乎同一位置按下（間隔／位移皆在
    // 門檻內），不應該觸發 End/Cancel，矩形應延續更新到新位置。
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.startGesture(const Offset(52, 51));
    await tester.pump(const Duration(milliseconds: 400));

    expect(cancelCount, 0);
    expect(endCount, 0, reason: '拖曳中途的雜訊應被合併吸收，不應提前結束選取');
    expect(movePositions.last, const Offset(52, 51));
  });

  testWidgets('一般快速點擊（未達長按時長且無雜訊）僅觸發一次取消，不影響翻頁熱區',
      (tester) async {
    var startCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) => startCount++,
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () => cancelCount++,
    ));

    final gesture = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(startCount, 0);
    expect(cancelCount, 1);
  });

  testWidgets(
      '雙指觸控應被拒絕且立即取消，不觸發長按；雙指皆放開後新的單指長按仍可正常獨立啟動',
      (tester) async {
    var startCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) => startCount++,
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () => cancelCount++,
    ));

    final first = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    // 第二指觸碰（例如捏合縮放的第二指），距離遠超 mergeSlop。
    final second = await tester.startGesture(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 500));

    expect(startCount, 0, reason: '雙指同時存在時不能啟動長按，避免與縮放/平移手勢衝突');
    expect(cancelCount, 1, reason: '第一指原本 pending 中的按壓應在偵測到第二指時立即取消');

    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 400));

    // 雙指皆放開後，新的一次單指長按應能正常獨立啟動，不受先前拒絕狀態影響。
    await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(startCount, 1);
  });

  testWidgets(
      '快速點擊（含 150-500ms 短按與快速連續點兩下）不應在背景幽靈觸發長按',
      (tester) async {
    var startCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) => startCount++,
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () {},
      onLongPressCancel: () => cancelCount++,
    ));

    // 情境一：單次持續 300ms 的按壓（介於 mergeGapMs 與 longPressDurationMs
    // 之間，E-Ink 裝置常見），不應在 t=500 被誤判成長按。
    final gesture = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400)); // 超過 mergeGapMs

    expect(startCount, 0, reason: '300ms 的單次按壓不應被誤判成長按');
    expect(cancelCount, 1);

    // 情境二：快速點兩下（Down1@0-Up1@100、Down2@200-Up2@300，皆在
    // mergeGapMs 內合併成同一次按壓），t=500 那一刻手指其實不在螢幕上，
    // 不應該在背景幽靈觸發長按。
    final tap1 = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await tap1.up();
    await tester.pump(const Duration(milliseconds: 100));
    final tap2 = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await tap2.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(startCount, 0, reason: '500ms 那一刻手指不在螢幕上，不應幽靈觸發長按');

    // 再等超過 mergeGapMs，應正確判定為第二次取消。
    await tester.pump(const Duration(milliseconds: 200));
    expect(cancelCount, 2);
  });

  testWidgets('PointerCancelEvent（系統手勢接管）立即取消，不等待彈跳合併寬限期',
      (tester) async {
    var cancelCount = 0;
    var endCount = 0;

    await tester.pumpWidget(wrap(
      onLongPressStart: (_) {},
      onLongPressMoveUpdate: (_) {},
      onLongPressEnd: () => endCount++,
      onLongPressCancel: () => cancelCount++,
    ));

    final gesture = await tester.startGesture(const Offset(0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.cancel();
    await tester.pump();

    expect(cancelCount, 1, reason: '系統取消應立即觸發，不必等 mergeGapMs 寬限期');
    expect(endCount, 0);
  });
}
