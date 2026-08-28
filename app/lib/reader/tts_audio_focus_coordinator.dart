import 'dart:async';

import 'tts_audio_focus_source.dart';
import 'tts_controller.dart';

/// 把 [TtsAudioFocusSource] 送出的系統音訊焦點/耳機事件，轉譯成
/// [TtsController.pause]／[TtsController.play] 呼叫（epic-34-tts-readalong
/// Issue 7，spec.md「Audio Focus 中斷處理」契約）。純 Dart、不依賴
/// Flutter widget 樹，呼叫端（[ReaderScreen]）於 [TtsController] 建構
/// 完成後一併建構本類別，比照 [TtsController] 本身「純 Dart 協調者」的
/// 既有設計慣例（不知道 `ReaderScreen`／WebView 存在）。
///
/// **只有本協調器自己造成的暫停才會在焦點恢復時自動播放**——
/// [_pausedByFocus] 只在「暫時失焦發生時，[controller] 原本正在播放」
/// 這個條件下才被設為 `true`；使用者手動呼叫 [TtsController.pause]、或
/// 永久失焦、或耳機拔出造成的暫停，皆不會設定此旗標，焦點恢復事件對它們
/// 是無操作。
///
/// **焦點恢復時額外核對 `controller.status` 仍為 `paused`**（審查
/// `review-plan-issue-7.md` 4.2 採納）：暫時失焦期間（例如來電中），
/// 使用者可能手動翻頁/跳章，觸發 [TtsController.handleExternalPositionChange]
/// 把狀態重設為 `idle`（見該方法文件：手動導覽一律視為「舊的朗讀段清單
/// 已不適用，完全重設」，不是「暫停中，等待從原位置恢復」）——這個過程
/// 完全不經過本協調器，[_pausedByFocus] 不會被連動清除。若此時只憑
/// [_pausedByFocus] 就呼叫 [TtsController.play]，會在使用者沒有主動按
/// 播放鍵的情況下，從使用者剛剛翻到的新頁面自動開始朗讀——這不是「恢復
/// 被系統打斷的播放」，而是背著使用者開始一次全新的播放，超出「自動恢復」
/// 這句契約的原意。只有 `controller.status` 在焦點恢復當下仍確實是
/// [TtsPlaybackStatus.paused]（代表狀態機從失焦以來沒有被其他事件改
/// 變過）才呼叫 [TtsController.play]。
class TtsAudioFocusCoordinator {
  final TtsAudioFocusSource source;
  final TtsController controller;

  StreamSubscription<TtsAudioFocusEvent>? _sub;
  bool _pausedByFocus = false;

  TtsAudioFocusCoordinator({required this.source, required this.controller}) {
    _sub = source.events.listen(_handleEvent);
  }

  void _handleEvent(TtsAudioFocusEvent event) {
    switch (event) {
      case TtsAudioFocusEvent.transientLoss:
        if (controller.status == TtsPlaybackStatus.playing) {
          _pausedByFocus = true;
          controller.pause();
        }
        break;
      case TtsAudioFocusEvent.permanentLoss:
      case TtsAudioFocusEvent.becomingNoisy:
        _pausedByFocus = false;
        controller.pause();
        break;
      case TtsAudioFocusEvent.focusGained:
        if (_pausedByFocus) {
          _pausedByFocus = false;
          if (controller.status == TtsPlaybackStatus.paused) {
            controller.play();
          }
        }
        break;
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
