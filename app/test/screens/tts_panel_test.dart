import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_controller.dart';
import 'package:elinkbook/screens/tts_panel.dart';

void main() {
  Widget buildPanel({
    TtsPlaybackStatus status = TtsPlaybackStatus.playing,
    double speed = 1.0,
    bool isCbz = false,
    bool isCollapsed = false,
    Duration? sleepTimerRemaining,
    bool isEinkMode = false,
    VoidCallback? onPlayPause,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    VoidCallback? onSpeedTap,
    VoidCallback? onVoiceTap,
    VoidCallback? onSleepTimerTap,
    VoidCallback? onToggleCollapse,
    VoidCallback? onStop,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TtsPanel(
          status: status,
          speed: speed,
          isCbz: isCbz,
          isCollapsed: isCollapsed,
          sleepTimerRemaining: sleepTimerRemaining,
          backgroundColor: Colors.white,
          iconColor: Colors.black,
          disabledIconColor: Colors.grey,
          isEinkMode: isEinkMode,
          onPlayPause: onPlayPause ?? () {},
          onPrevious: onPrevious ?? () {},
          onNext: onNext ?? () {},
          onSpeedTap: onSpeedTap ?? () {},
          onVoiceTap: onVoiceTap ?? () {},
          onSleepTimerTap: onSleepTimerTap ?? () {},
          onToggleCollapse: onToggleCollapse ?? () {},
          onStop: onStop ?? () {},
        ),
      ),
    );
  }

  testWidgets('isCollapsed: false 且 isCbz: false 時，展開列五顆按鈕皆存在', (tester) async {
    await tester.pumpWidget(buildPanel());
    expect(find.byKey(const Key('reader_tts_previous_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_play_pause_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_next_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_speed_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_voice_button')), findsOneWidget);
  });

  testWidgets('底層動作列三顆按鈕恆常渲染', (tester) async {
    await tester.pumpWidget(buildPanel());
    expect(find.byKey(const Key('reader_tts_sleep_timer_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_panel_collapse_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_stop_button')), findsOneWidget);
  });

  testWidgets('isCollapsed: true 時，展開列四顆不存在，底層動作列仍存在', (tester) async {
    await tester.pumpWidget(buildPanel(isCollapsed: true));
    expect(find.byKey(const Key('reader_tts_previous_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_play_pause_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_next_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_speed_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_voice_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_sleep_timer_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_panel_collapse_button')), findsOneWidget);
    expect(find.byKey(const Key('reader_tts_stop_button')), findsOneWidget);
  });

  testWidgets('isCbz: true 時，只有停用狀態播放鍵，不渲染上一句/下一句/語速/語音', (tester) async {
    await tester.pumpWidget(buildPanel(isCbz: true));
    final playFinder = find.byKey(const Key('reader_tts_play_pause_button'));
    expect(playFinder, findsOneWidget);
    expect(tester.widget<IconButton>(playFinder).onPressed, isNull);
    expect(find.byKey(const Key('reader_tts_previous_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_next_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_speed_button')), findsNothing);
    expect(find.byKey(const Key('reader_tts_voice_button')), findsNothing);
  });

  testWidgets('isCbz: true 且 isCollapsed: true 時，展開列（含停用播放鍵）整排不渲染',
      (tester) async {
    await tester.pumpWidget(buildPanel(isCbz: true, isCollapsed: true));
    expect(find.byKey(const Key('reader_tts_play_pause_button')), findsNothing);
  });

  testWidgets('status: playing 時播放鍵顯示暫停圖示，點擊觸發 onPlayPause', (tester) async {
    var called = false;
    await tester.pumpWidget(
      buildPanel(status: TtsPlaybackStatus.playing, onPlayPause: () => called = true),
    );
    final finder = find.byKey(const Key('reader_tts_play_pause_button'));
    final icon = tester.widget<Icon>(
      find.descendant(of: finder, matching: find.byType(Icon)),
    );
    expect(icon.icon, Icons.pause);
    await tester.tap(finder);
    expect(called, isTrue);
  });

  testWidgets('status: paused 時播放鍵顯示播放圖示', (tester) async {
    await tester.pumpWidget(buildPanel(status: TtsPlaybackStatus.paused));
    final finder = find.byKey(const Key('reader_tts_play_pause_button'));
    final icon = tester.widget<Icon>(
      find.descendant(of: finder, matching: find.byType(Icon)),
    );
    expect(icon.icon, Icons.play_arrow);
  });

  testWidgets('點擊上一句/下一句/語速/語音按鈕分別觸發對應 callback', (tester) async {
    var previous = false, next = false, speedTap = false, voiceTap = false;
    await tester.pumpWidget(buildPanel(
      onPrevious: () => previous = true,
      onNext: () => next = true,
      onSpeedTap: () => speedTap = true,
      onVoiceTap: () => voiceTap = true,
    ));
    await tester.tap(find.byKey(const Key('reader_tts_previous_button')));
    await tester.tap(find.byKey(const Key('reader_tts_next_button')));
    await tester.tap(find.byKey(const Key('reader_tts_speed_button')));
    await tester.tap(find.byKey(const Key('reader_tts_voice_button')));
    expect(previous, isTrue);
    expect(next, isTrue);
    expect(speedTap, isTrue);
    expect(voiceTap, isTrue);
  });

  testWidgets('sleepTimerRemaining 為 null 時按鈕文字為「定時」', (tester) async {
    await tester.pumpWidget(buildPanel(sleepTimerRemaining: null));
    expect(find.text('定時'), findsOneWidget);
  });

  testWidgets('sleepTimerRemaining 非 null 時按鈕文字反映剩餘分鐘數', (tester) async {
    await tester.pumpWidget(
      buildPanel(sleepTimerRemaining: const Duration(minutes: 30)),
    );
    expect(find.text('定時 30 分'), findsOneWidget);
  });

  testWidgets('點擊睡眠定時器按鈕觸發 onSleepTimerTap', (tester) async {
    var called = false;
    await tester.pumpWidget(buildPanel(onSleepTimerTap: () => called = true));
    await tester.tap(find.byKey(const Key('reader_tts_sleep_timer_button')));
    expect(called, isTrue);
  });

  testWidgets('isCollapsed: false 時收合按鈕文字為「收合」，點擊觸發 onToggleCollapse',
      (tester) async {
    var called = false;
    await tester.pumpWidget(
      buildPanel(isCollapsed: false, onToggleCollapse: () => called = true),
    );
    expect(find.text('收合'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader_tts_panel_collapse_button')));
    expect(called, isTrue);
  });

  testWidgets('isCollapsed: true 時收合按鈕文字為「展開」', (tester) async {
    await tester.pumpWidget(buildPanel(isCollapsed: true));
    expect(find.text('展開'), findsOneWidget);
  });

  testWidgets('點擊停止按鈕觸發 onStop', (tester) async {
    var called = false;
    await tester.pumpWidget(buildPanel(onStop: () => called = true));
    await tester.tap(find.byKey(const Key('reader_tts_stop_button')));
    expect(called, isTrue);
  });

  testWidgets('isEinkMode: true 時，展開列按鈕觸控目標實際渲染高度為 56dp', (tester) async {
    await tester.pumpWidget(buildPanel(isEinkMode: true));
    final size = tester.getSize(
      find.byKey(const Key('reader_tts_play_pause_button')),
    );
    expect(size.height, greaterThanOrEqualTo(56));
  });

  testWidgets('isEinkMode: false（預設）時，展開列按鈕觸控目標高度為 52dp', (tester) async {
    await tester.pumpWidget(buildPanel(isEinkMode: false));
    final size = tester.getSize(
      find.byKey(const Key('reader_tts_play_pause_button')),
    );
    expect(size.height, greaterThanOrEqualTo(52));
    expect(size.height, lessThan(56));
  });

  // 審查修正（review-plan-issue-2.md I2）：底層動作列（isCollapsed 時
  // 唯一還留在畫面上的一列）漏測，實際上這 3 顆 TextButton 原本沒有設定
  // minimumSize，isEinkMode 下並不會真的達到 56dp——這兩則測試就是抓這個
  // 回歸用的。
  testWidgets('isEinkMode: true 時，底層動作列按鈕觸控目標實際渲染高度為 56dp', (tester) async {
    await tester.pumpWidget(buildPanel(isEinkMode: true, isCollapsed: true));
    final size = tester.getSize(
      find.byKey(const Key('reader_tts_stop_button')),
    );
    expect(size.height, greaterThanOrEqualTo(56));
  });

  testWidgets('isEinkMode: false（預設）時，底層動作列按鈕觸控目標高度為 52dp', (tester) async {
    await tester.pumpWidget(buildPanel(isEinkMode: false, isCollapsed: true));
    final size = tester.getSize(
      find.byKey(const Key('reader_tts_stop_button')),
    );
    expect(size.height, greaterThanOrEqualTo(52));
    expect(size.height, lessThan(56));
  });
}
