import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_controller.dart';
import 'package:elinkbook/screens/tts_mini_player.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('非 CBZ：完整播放/暫停/上一句/下一句/語速控制', () {
    testWidgets('顯示四顆按鈕：播放/暫停、上一句、下一句、語速', (tester) async {
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
        onClose: () {},
      )));

      expect(find.byKey(const Key('reader_tts_play_pause_button')), findsOneWidget);
      expect(find.byKey(const Key('reader_tts_previous_button')), findsOneWidget);
      expect(find.byKey(const Key('reader_tts_next_button')), findsOneWidget);
      expect(find.byKey(const Key('reader_tts_speed_button')), findsOneWidget);
    });

    testWidgets('status 為 idle 時顯示播放圖示，tooltip 為「開始朗讀」', (tester) async {
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
        onClose: () {},
      )));

      final button = tester.widget<IconButton>(
        find.byKey(const Key('reader_tts_play_pause_button')),
      );
      expect(button.tooltip, '開始朗讀');
      final icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('reader_tts_play_pause_button')),
        matching: find.byType(Icon),
      ));
      expect(icon.icon, Icons.play_arrow);
    });

    testWidgets('status 為 paused 時顯示播放圖示，tooltip 為「開始朗讀」', (tester) async {
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.paused,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
        onClose: () {},
      )));

      final button = tester.widget<IconButton>(
        find.byKey(const Key('reader_tts_play_pause_button')),
      );
      expect(button.tooltip, '開始朗讀');
      final icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('reader_tts_play_pause_button')),
        matching: find.byType(Icon),
      ));
      expect(icon.icon, Icons.play_arrow);
    });

    testWidgets('status 為 playing 時顯示暫停圖示，tooltip 為「暫停朗讀」', (tester) async {
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.playing,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
        onClose: () {},
      )));

      final button = tester.widget<IconButton>(
        find.byKey(const Key('reader_tts_play_pause_button')),
      );
      expect(button.tooltip, '暫停朗讀');
      final icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('reader_tts_play_pause_button')),
        matching: find.byType(Icon),
      ));
      expect(icon.icon, Icons.pause);
    });

    testWidgets('語速按鈕顯示 speed 的兩位小數＋x 後綴，且 tooltip 包含目前語速', (tester) async {
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.25,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
        onClose: () {},
      )));

      final button = tester.widget<IconButton>(
        find.byKey(const Key('reader_tts_speed_button')),
      );
      expect(button.tooltip, '朗讀語速：1.25x（點擊切換）');
      expect(
        find.descendant(
          of: find.byKey(const Key('reader_tts_speed_button')),
          matching: find.text('1.25x'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('點擊播放/暫停觸發 onPlayPause', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () => tapped = true,
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
        onClose: () {},
      )));

      await tester.tap(find.byKey(const Key('reader_tts_play_pause_button')));
      expect(tapped, isTrue);
    });

    testWidgets('點擊上一句觸發 onPrevious', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () => tapped = true,
        onNext: () {},
        onSpeedTap: () {},
        onClose: () {},
      )));

      await tester.tap(find.byKey(const Key('reader_tts_previous_button')));
      expect(tapped, isTrue);
    });

    testWidgets('點擊下一句觸發 onNext', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () => tapped = true,
        onSpeedTap: () {},
        onClose: () {},
      )));

      await tester.tap(find.byKey(const Key('reader_tts_next_button')));
      expect(tapped, isTrue);
    });

    testWidgets('顯示關閉按鈕，點擊觸發 onClose', (tester) async {
      var closed = false;
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
        onClose: () => closed = true,
      )));

      expect(
        find.byKey(const Key('reader_tts_mini_player_close_button')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('reader_tts_mini_player_close_button')),
      );
      expect(closed, isTrue);
    });

    testWidgets('點擊語速按鈕觸發 onSpeedTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: false,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () => tapped = true,
        onClose: () {},
      )));

      await tester.tap(find.byKey(const Key('reader_tts_speed_button')));
      expect(tapped, isTrue);
    });
  });

  group('CBZ：只顯示停用的播放鍵＋關閉鍵', () {
    testWidgets('顯示 reader_tts_play_pause_button 與關閉鍵，其餘三顆按鈕不存在', (tester) async {
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: true,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
        onClose: () {},
      )));

      expect(find.byKey(const Key('reader_tts_play_pause_button')), findsOneWidget);
      expect(
        find.byKey(const Key('reader_tts_mini_player_close_button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reader_tts_previous_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_next_button')), findsNothing);
      expect(find.byKey(const Key('reader_tts_speed_button')), findsNothing);
    });

    testWidgets('點擊關閉鍵觸發 onClose（即使播放鍵本身停用）', (tester) async {
      var closed = false;
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: true,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
        onClose: () => closed = true,
      )));

      await tester.tap(
        find.byKey(const Key('reader_tts_mini_player_close_button')),
      );
      expect(closed, isTrue);
    });

    testWidgets('播放/暫停按鈕為停用狀態（onPressed 為 null），圖示固定為播放箭頭且 tooltip 提示純圖像格式', (tester) async {
      await tester.pumpWidget(wrap(TtsMiniPlayer(
        status: TtsPlaybackStatus.idle,
        speed: 1.0,
        isCbz: true,
        backgroundColor: Colors.black,
        iconColor: Colors.white,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
        onSpeedTap: () {},
        onClose: () {},
      )));

      final button = tester.widget<IconButton>(
        find.byKey(const Key('reader_tts_play_pause_button')),
      );
      expect(button.onPressed, isNull);
      expect(button.tooltip, 'CBZ 為純圖像格式，不支援語音朗讀');
      final icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('reader_tts_play_pause_button')),
        matching: find.byType(Icon),
      ));
      expect(icon.icon, Icons.play_arrow);
    });
  });
}
