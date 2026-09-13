import 'nav_zone_prefs.dart';
import 'reading_defaults.dart';
import 'tts_defaults.dart';

export 'nav_zone_prefs.dart';
export 'reading_defaults.dart';
export 'tts_defaults.dart';

/// 跨書生效的全域預設閱讀偏好聚合根（2026-09-13 由原本的 13 個攤平欄位拆分
/// 為 3 個巢狀值物件＋1 個攤平欄位，見
/// `docs/superpowers/plans/2026-09-13-split-global-reader-prefs.md`）。
///
/// [consoleLogEnabled] 是唯一維持攤平的欄位——`app/lib/screens/
/// settings_scaffold.dart` 是它唯一的讀寫端，語意上跟導覽熱區／TTS／閱讀
/// 預設值三組都無關，沒有可歸類的分組。
class GlobalReaderPrefs {
  /// Console Log 攔截總開關（epic-28-reader-settings-enhancements
  /// Issue 2），預設 `false`（不攔截一般等級訊息）。只影響 `[LOG]`/
  /// `[WARNING]`/`[DEBUG]`/`[TIP]` 等級——`[ERROR]` 等級（含未捕捉例外的
  /// 崩潰診斷用途）永遠強制記錄，不受本開關影響，見
  /// `handleFoliateConsoleMessage()`。
  final bool consoleLogEnabled;

  /// 導航熱區偏好（FR-24），見 [NavZonePrefs]。
  final NavZonePrefs navZone;

  /// 朗讀（TTS）預設值，見 [TtsDefaults]。
  final TtsDefaults tts;

  /// 「閱讀預設值」畫面對應的 7 個欄位，見 [ReadingDefaults]。
  final ReadingDefaults reading;

  const GlobalReaderPrefs({
    this.consoleLogEnabled = false,
    this.navZone = const NavZonePrefs.initial(),
    this.tts = const TtsDefaults.initial(),
    this.reading = const ReadingDefaults.initial(),
  });

  /// 初始值，與現行硬編碼預設一致，不改變任何現有使用者體驗。
  const GlobalReaderPrefs.initial() : this();

  GlobalReaderPrefs copyWith({
    bool? consoleLogEnabled,
    NavZonePrefs? navZone,
    TtsDefaults? tts,
    ReadingDefaults? reading,
  }) {
    return GlobalReaderPrefs(
      consoleLogEnabled: consoleLogEnabled ?? this.consoleLogEnabled,
      navZone: navZone ?? this.navZone,
      tts: tts ?? this.tts,
      reading: reading ?? this.reading,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlobalReaderPrefs &&
      other.consoleLogEnabled == consoleLogEnabled &&
      other.navZone == navZone &&
      other.tts == tts &&
      other.reading == reading;

  @override
  int get hashCode =>
      Object.hash(consoleLogEnabled, navZone, tts, reading);
}
