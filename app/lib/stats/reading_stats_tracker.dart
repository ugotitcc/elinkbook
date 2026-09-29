import 'dart:async';
import 'dart:developer' as developer;

import 'package:clock/clock.dart';

/// 把「已確認」的閱讀秒數寫入儲存層的回呼。
/// 回呼拋出例外時，該批秒數會保留在緩衝，下次再試。
typedef ReadingStatsFlush = Future<void> Function(
  String date,
  String bookId,
  String bookTitle,
  int seconds,
);

/// 閒置門檻：距最後一次活動超過這段時間，視為沒在讀。
const Duration kReadingIdleThreshold = Duration(minutes: 2);

/// 計時中的寫入週期，同時是閒置看門狗的檢查週期。
const Duration kReadingFlushInterval = Duration(seconds: 30);

enum _TrackerState {
  /// 剛開書、尚無活動。
  unverified,

  /// 閱讀中。
  active,

  /// 已閒置、凍結（不計時、沒有計時器）。
  idle,
}

/// 閱讀計時器：每本書一個的會話級實例，純 Dart。
///
/// 核心概念：
/// - 「錨點」是最後一次活動（或上次確認）的時間；錨點之後的時間只是暫態，
///   **不進緩衝、不寫入**。
/// - 只有後續活動（且距錨點不超過門檻）、合法退出、TTS 播放中，
///   才把「錨點 → 現在」確認進緩衝。
/// - 超過門檻的空檔整段丟棄。
class ReadingStatsTracker {
  ReadingStatsTracker({
    required this.bookId,
    required this.bookTitle,
    required ReadingStatsFlush onFlush,
    Stream<void>? onCleared,
    Clock? clock,
  })  : _onFlush = onFlush,
        _clock = clock {
    _setAnchor(_now());
    _clearedSubscription = onCleared?.listen((_) => _handleCleared());
  }

  final String bookId;
  final String bookTitle;
  final ReadingStatsFlush _onFlush;
  final Clock? _clock;

  _TrackerState _state = _TrackerState.unverified;

  /// 最後一次活動（或上次確認）的時間；開書時為開書時間。
  late DateTime _anchor;

  /// 目前已見過的最晚日期。早於它的日期一律不寫入（倒撥跨日防護）。
  String? _floorDate;

  /// 已確認、尚未成功寫入的時間，依本地日期分組；以 [Duration] 保留子秒精度。
  final Map<String, Duration> _confirmed = {};

  Timer? _timer;
  StreamSubscription<void>? _clearedSubscription;

  /// 寫入的串接：上一批完成後才處理下一批，避免重複送出。
  Future<void> _flushChain = Future<void>.value();

  /// 每次清除加一；寫入在途期間若發生清除，完成後不再扣減緩衝。
  int _clearEpoch = 0;

  bool _closed = false;

  /// TTS 是否正在播放（由 ReaderScreen 轉譯後回報）。
  bool _ttsPlaying = false;

  /// App 是否在背景（由 ReaderScreen 轉譯 paused／resumed 後回報）。
  bool _inBackground = false;

  /// 翻頁、捲動、長按劃線等閱讀活動。
  void recordActivity() {
    if (_closed) return;
    final now = _now();
    if (_state != _TrackerState.idle) {
      final gap = now.difference(_anchor);
      // 倒撥（gap 為負）或空檔超過門檻：這一段不計，直接從現在重新起算。
      if (!gap.isNegative && gap <= kReadingIdleThreshold) {
        _confirmSpan(_anchor, now);
      }
    }
    _state = _TrackerState.active;
    _setAnchor(now);
    _ensureTimer();
  }

  /// App 進入背景（paused）。TTS 未播放：立即結算並寫入，結束這一段；
  /// TTS 播放中：不結束，進入背景計時，直到 TTS 停止。
  void onEnteredBackground() {
    if (_closed) return;
    _inBackground = true;
    if (_ttsPlaying) return;
    _settleTail(_now());
    _goIdle();
    unawaited(_flush());
  }

  /// App 回到前景（resumed）。TTS 仍在播放時無縫延續，不需要任何結算。
  void onReturnedToForeground() {
    if (_closed) return;
    _inBackground = false;
  }

  /// TTS 播放狀態變化。開始播放本身算一次活動；停止時先把播放期間確認完；
  /// 若此時 App 在背景，結束這一段並寫入。重複回報相同狀態不做任何事。
  void onTtsPlayingChanged(bool isPlaying) {
    if (_closed || isPlaying == _ttsPlaying) return;
    if (isPlaying) {
      recordActivity();
      _ttsPlaying = true;
      return;
    }
    if (_state == _TrackerState.active) _confirmThrough(_now());
    _ttsPlaying = false;
    if (_inBackground) {
      _goIdle();
      unawaited(_flush());
    }
  }

  /// 退出閱讀器：結算尾段、寫入已確認的秒數並釋放資源。
  /// 重複呼叫，或在 [dispose] 之後呼叫，都不會再寫入。
  Future<void> flushAndClose() async {
    if (_closed) {
      await _flushChain;
      return;
    }
    _settleTail(_now());
    _shutdown();
    await _flush();
  }

  /// 同步釋放：取消訂閱與計時器。不寫入任何資料（要寫入請用 [flushAndClose]）。
  void dispose() => _shutdown();

  DateTime _now() => (_clock ?? clock).now().toLocal();

  static String _dateOf(DateTime t) {
    final month = t.month.toString().padLeft(2, '0');
    final day = t.day.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}-$month-$day';
  }

  void _setAnchor(DateTime t) {
    _anchor = t;
    final date = _dateOf(t);
    final floor = _floorDate;
    if (floor == null || date.compareTo(floor) > 0) _floorDate = date;
  }

  /// 把 [from, to] 確認進緩衝；跨越本地午夜時切成前後兩天。
  /// 呼叫端保證 to - from 不超過閒置門檻，因此最多跨越一個午夜。
  void _confirmSpan(DateTime from, DateTime to) {
    if (!to.isAfter(from)) return;
    final fromDate = _dateOf(from);
    final toDate = _dateOf(to);
    if (fromDate == toDate) {
      _credit(toDate, to.difference(from));
      return;
    }
    final midnight = DateTime(to.year, to.month, to.day);
    _credit(fromDate, midnight.difference(from));
    _credit(toDate, to.difference(midnight));
  }

  void _credit(String date, Duration amount) {
    if (amount <= Duration.zero) return;
    final floor = _floorDate;
    if (floor != null && date.compareTo(floor) < 0) return;
    _confirmed[date] = (_confirmed[date] ?? Duration.zero) + amount;
  }

  /// 結算尾段：TTS 播放中，朗讀本身就是連續活動，直接確認到現在；
  /// 否則只有距錨點未超過門檻時才確認。
  /// 剛開書尚無活動（unverified）或已閒置（idle）時直接返回，計 0 秒。
  void _settleTail(DateTime now) {
    if (_state != _TrackerState.active) return;
    if (_ttsPlaying) {
      _confirmThrough(now);
      return;
    }
    final gap = now.difference(_anchor);
    if (!gap.isNegative && gap <= kReadingIdleThreshold) {
      _confirmSpan(_anchor, now);
    }
  }

  /// TTS 播放中：把「錨點 → 現在」確認進緩衝並前移錨點。
  /// 單次計量不超過閒置門檻（擋時鐘快轉）；倒撥則不計並重新起算。
  void _confirmThrough(DateTime now) {
    final gap = now.difference(_anchor);
    if (gap.isNegative) {
      _setAnchor(now);
      return;
    }
    final counted = gap > kReadingIdleThreshold ? kReadingIdleThreshold : gap;
    _confirmSpan(now.subtract(counted), now);
    _setAnchor(now);
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(kReadingFlushInterval, (_) => _onTick());
  }

  void _goIdle() {
    _state = _TrackerState.idle;
    _timer?.cancel();
    _timer = null;
  }

  /// 30 秒觸發：閒置看門狗＋寫入。
  void _onTick() {
    final now = _now();
    if (_state == _TrackerState.active) {
      if (_ttsPlaying) {
        _confirmThrough(now); // TTS 播放中沒有活動事件：由定時器持續確認
      } else {
        final gap = now.difference(_anchor);
        if (gap.isNegative) {
          _setAnchor(now); // 倒撥：重新起算
        } else if (gap >= kReadingIdleThreshold) {
          _goIdle(); // 已閒置：丟棄暫態、取消計時器
        }
      }
    }
    unawaited(_flush());
  }

  void _handleCleared() {
    _confirmed.clear();
    _clearEpoch++;
    // 暫態時間也丟棄：從清除當下重新起算。
    if (_state != _TrackerState.idle) _setAnchor(_now());
  }

  void _shutdown() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _clearedSubscription?.cancel();
    _clearedSubscription = null;
  }

  Future<void> _flush() {
    _flushChain = _flushChain.then((_) => _drain());
    return _flushChain;
  }

  /// 把緩衝內的整數秒逐日寫出；失敗的日期保留，成功的扣掉已寫出的整數秒。
  Future<void> _drain() async {
    final epoch = _clearEpoch;
    final dates = _confirmed.keys.toList()..sort();
    for (final date in dates) {
      final whole = (_confirmed[date] ?? Duration.zero).inSeconds;
      if (whole <= 0) continue;
      try {
        await _onFlush(date, bookId, bookTitle, whole);
      } catch (error, stackTrace) {
        developer.log(
          '閱讀統計寫入失敗（$date，$whole 秒），秒數保留待下次重試',
          name: 'ReadingStatsTracker',
          error: error,
          stackTrace: stackTrace,
        );
        continue;
      }
      // 寫入期間發生清除：緩衝已被清空，不能再扣。
      if (epoch != _clearEpoch) return;
      final remain = (_confirmed[date] ?? Duration.zero) - Duration(seconds: whole);
      if (remain <= Duration.zero) {
        _confirmed.remove(date);
      } else {
        _confirmed[date] = remain;
      }
    }
  }
}
