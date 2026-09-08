import 'package:flutter/material.dart';

import '../reader/tts_controller.dart';

/// TTS 朗讀常駐面板（epic-38-reader-chrome-tts-redesign Issue 2，spec.md
/// §功能③）：取代 [TtsMiniPlayer]（`tts_mini_player.dart`，本 Issue 一併
/// 刪除），與呼叫端（[ReaderScreen]）的 `ReaderChromeBottomBar` 依
/// `TtsController.status` 衍生完全互斥（不設手動旗標，見
/// `reader_screen.dart` `_buildBottomChrome` 文件註解）。純
/// [StatelessWidget]，不直接持有 [TtsController]，只吃基本型別與
/// callback（比照既有 [TtsMiniPlayer] 慣例，spec.md「單一事實來源」
/// 要求）。
///
/// 兩排固定結構：
/// - **展開控制列**（[isCollapsed] 為 `true` 時整排不渲染）：上一句／
///   播放暫停／下一句／語速／語音，[isCbz] 為 `true` 時只渲染一顆停用
///   狀態的播放鍵（CBZ 為純圖像格式，無文字可朗讀，沿用既有
///   [TtsMiniPlayer] 降級語意）。
/// - **底層動作列**（睡眠定時器／收合展開／停止，恆常渲染，不受
///   [isCollapsed] 或 [isCbz] 影響——即使是 CBZ 的純裝飾面板，使用者仍
///   可能想直接跳出朗讀模式）。
///
/// 觸控目標依 `DESIGN.md` §7.2：一般模式 52dp（spec.md 對本元件「大按鈕」
/// 的既定基準，比 `ReaderChromeTopBar`／`ReaderChromeBottomBar` 的 48dp
/// 略大）、`isEinkMode` 時 56dp。
class TtsPanel extends StatelessWidget {
  final TtsPlaybackStatus status;
  final double speed;
  final bool isCbz;
  final bool isCollapsed;
  final Duration? sleepTimerRemaining;
  final Color backgroundColor;
  final Color iconColor;
  final Color disabledIconColor;
  final bool isEinkMode;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSpeedTap;
  final VoidCallback onVoiceTap;
  final VoidCallback onSleepTimerTap;
  final VoidCallback onToggleCollapse;
  final VoidCallback onStop;

  const TtsPanel({
    super.key,
    required this.status,
    required this.speed,
    required this.isCbz,
    required this.isCollapsed,
    required this.sleepTimerRemaining,
    required this.backgroundColor,
    required this.iconColor,
    required this.disabledIconColor,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSpeedTap,
    required this.onVoiceTap,
    required this.onSleepTimerTap,
    required this.onToggleCollapse,
    required this.onStop,
    this.isEinkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final playing = status == TtsPlaybackStatus.playing;
    final minSize = isEinkMode ? 56.0 : 52.0;
    // 前景色／停用前景色交給 IconButton.styleFrom 統一管理（沿用
    // review-issue-1.md C-2 修法：Icon 不自帶 color，避免覆蓋掉 Material
    // 的停用色，讓 CBZ 停用播放鍵的視覺回饋不會與正常按鈕無異）。
    final buttonStyle = IconButton.styleFrom(
      minimumSize: Size(minSize, minSize),
      foregroundColor: iconColor,
      disabledForegroundColor: disabledIconColor,
    );
    return Material(
      color: backgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isCollapsed)
            SizedBox(
              height: minSize,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: isCbz
                    ? [
                        IconButton(
                          key: const Key('reader_tts_play_pause_button'),
                          icon: const Icon(Icons.play_arrow),
                          tooltip: 'CBZ 為純圖像格式，不支援語音朗讀',
                          style: buttonStyle,
                          onPressed: null,
                        ),
                      ]
                    : [
                        IconButton(
                          key: const Key('reader_tts_previous_button'),
                          icon: const Icon(Icons.skip_previous),
                          tooltip: '上一句',
                          style: buttonStyle,
                          onPressed: onPrevious,
                        ),
                        IconButton(
                          key: const Key('reader_tts_play_pause_button'),
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          tooltip: playing ? '暫停朗讀' : '開始朗讀',
                          style: buttonStyle,
                          onPressed: onPlayPause,
                        ),
                        IconButton(
                          key: const Key('reader_tts_next_button'),
                          icon: const Icon(Icons.skip_next),
                          tooltip: '下一句',
                          style: buttonStyle,
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
                          style: buttonStyle,
                          onPressed: onSpeedTap,
                        ),
                        IconButton(
                          key: const Key('reader_tts_voice_button'),
                          icon: const Icon(Icons.record_voice_over),
                          tooltip: '選擇語音',
                          style: buttonStyle,
                          onPressed: onVoiceTap,
                        ),
                      ],
              ),
            ),
          SizedBox(
            height: minSize,
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    key: const Key('reader_tts_sleep_timer_button'),
                    onPressed: onSleepTimerTap,
                    // 審查修正（review-plan-issue-2.md I2）：Row 的
                    // crossAxisAlignment 預設 center，外層 SizedBox 的
                    // height: minSize 只約束 Row 本身、不會讓子項自動
                    // 撐滿——TextButton 預設高度 48dp，isEinkMode: true
                    // 時若不明講 minimumSize，實際渲染高度仍是 48dp，
                    // 收合成細列時畫面上只剩這 3 顆按鈕，觸控目標達不到
                    // E-Ink 56dp 規範（`DESIGN.md` §7.2）。
                    style: TextButton.styleFrom(
                      foregroundColor: iconColor,
                      minimumSize: Size.fromHeight(minSize),
                    ),
                    icon: const Icon(Icons.bedtime_outlined),
                    label: Text(
                      sleepTimerRemaining == null
                          ? '睡眠定時器'
                          : '睡眠 ${sleepTimerRemaining!.inMinutes} 分',
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    key: const Key('reader_tts_panel_collapse_button'),
                    onPressed: onToggleCollapse,
                    style: TextButton.styleFrom(
                      foregroundColor: iconColor,
                      minimumSize: Size.fromHeight(minSize),
                    ),
                    icon: Icon(
                      isCollapsed ? Icons.expand_less : Icons.expand_more,
                    ),
                    label: Text(isCollapsed ? '展開控制列' : '收合成細列'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    key: const Key('reader_tts_stop_button'),
                    onPressed: onStop,
                    style: TextButton.styleFrom(
                      foregroundColor: backgroundColor,
                      backgroundColor: iconColor,
                      minimumSize: Size.fromHeight(minSize),
                    ),
                    icon: const Icon(Icons.stop),
                    label: const Text('停止'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
