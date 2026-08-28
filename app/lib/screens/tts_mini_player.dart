import 'package:flutter/material.dart';

import '../reader/tts_controller.dart';

/// TTS 朗讀正式 Mini Player 控制列（epic-34-tts-readalong Issue 6）。
/// 比照本專案既有 [AnnotationToolbar]（`annotation_toolbar.dart`）的既定
/// 慣例：純 [StatelessWidget]，不直接持有 [TtsController]，只吃基本型別
/// 與 callback 參數——呼叫端（[ReaderScreen]）以
/// `AnimatedBuilder(animation: TtsController, builder: ...)` 包住本
/// widget，每次 [TtsController.notifyListeners] 觸發時傳入最新的
/// [status]／[speed]，本 widget 完全不維護任何私有狀態（`spec.md`
/// 「單一事實來源」要求，審查 `review-issues.md` Minor #1）。
///
/// [isCbz] 為 `true` 時，只顯示一顆停用狀態的播放鍵（CBZ 為純圖像格式，
/// 無文字可朗讀，見 Issue 2 既有設計），不建構上一句/下一句/語速三顆
/// 按鈕——沿用 Issue 5 既有的 CBZ 排除範圍，本 Issue 不新增播放邏輯。
class TtsMiniPlayer extends StatelessWidget {
  final TtsPlaybackStatus status;
  final double speed;
  final bool isCbz;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSpeedTap;

  const TtsMiniPlayer({
    super.key,
    required this.status,
    required this.speed,
    required this.isCbz,
    required this.backgroundColor,
    required this.iconColor,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSpeedTap,
  });

  @override
  Widget build(BuildContext context) {
    final playing = status == TtsPlaybackStatus.playing;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: isCbz
            ? IconButton(
                key: const Key('reader_tts_play_pause_button'),
                icon: Icon(Icons.play_arrow, color: iconColor),
                tooltip: 'CBZ 為純圖像格式，不支援語音朗讀',
                onPressed: null,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('reader_tts_previous_button'),
                    icon: Icon(Icons.skip_previous, color: iconColor),
                    tooltip: '上一句',
                    onPressed: onPrevious,
                  ),
                  IconButton(
                    key: const Key('reader_tts_play_pause_button'),
                    icon: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      color: iconColor,
                    ),
                    tooltip: playing ? '暫停朗讀' : '開始朗讀',
                    onPressed: onPlayPause,
                  ),
                  IconButton(
                    key: const Key('reader_tts_next_button'),
                    icon: Icon(Icons.skip_next, color: iconColor),
                    tooltip: '下一句',
                    onPressed: onNext,
                  ),
                  IconButton(
                    key: const Key('reader_tts_speed_button'),
                    icon: Text(
                      '${speed.toStringAsFixed(2)}x',
                      style: TextStyle(
                        color: iconColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    tooltip: '朗讀語速：${speed.toStringAsFixed(2)}x（點擊切換）',
                    onPressed: onSpeedTap,
                  ),
                ],
              ),
      ),
    );
  }
}
