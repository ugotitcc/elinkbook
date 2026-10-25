import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'reader_colors.dart';

/// 全域閱讀器自訂背景色與文字色的持久化（epic-65 Issue 2）。
///
/// 依各佈景（`AppTheme.light`、`AppTheme.dark`、`AppTheme.sepia`）分別儲存 `#RRGGBB` 色碼。
/// 欄位為 `null` 時代表退回佈景原色，並從 `SharedPreferences` 移除該 key。
class ReaderColorPreferences {
  const ReaderColorPreferences();

  static String _bgKey(AppTheme theme) => 'reader_color_${theme.name}_background';
  static String _textKey(AppTheme theme) => 'reader_color_${theme.name}_text';

  /// 讀取指定佈景的自訂顏色設定。若未設定或色碼格式毀損，欄位安全回退為 `null`。
  Future<ReaderColors> load(AppTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    final rawBg = prefs.getString(_bgKey(theme));
    final rawText = prefs.getString(_textKey(theme));

    final bg = rawBg != null ? parseHexColor(rawBg) : null;
    final text = rawText != null ? parseHexColor(rawText) : null;

    return ReaderColors(background: bg, text: text);
  }

  /// 儲存指定佈景的自訂顏色設定。欄位若為 `null`，則移除對應 key。
  Future<void> save(AppTheme theme, ReaderColors colors) async {
    final prefs = await SharedPreferences.getInstance();
    final bgKey = _bgKey(theme);
    final textKey = _textKey(theme);

    if (colors.background != null) {
      await prefs.setString(bgKey, formatHexColor(colors.background!));
    } else {
      await prefs.remove(bgKey);
    }

    if (colors.text != null) {
      await prefs.setString(textKey, formatHexColor(colors.text!));
    } else {
      await prefs.remove(textKey);
    }
  }
}
