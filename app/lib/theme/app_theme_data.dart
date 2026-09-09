import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'elink_tokens.dart';

/// 四套主題（晴空藍天／夜讀水墨／宣紙古風／E-Ink）的 [ThemeData] 工廠。
/// `ColorScheme` 各角色與 `ElinkTokens` 各欄位的色值，一律以 `DESIGN.md`
/// §1.1／§1.2 為唯一事實來源（見 epic-35-design-system-tokens Issue 2）；
/// 早期參考 prototype/index.html CSS 變數的版本已由本工單全面取代。

/// 根據 [theme] 回傳對應的 [ThemeData]，不考慮 E-Ink 高對比模式。
ThemeData buildThemeData(AppTheme theme) {
  switch (theme) {
    case AppTheme.light:
      return _buildLightTheme();
    case AppTheme.dark:
      return _buildDarkTheme();
    case AppTheme.sepia:
      return _buildSepiaTheme();
  }
}

/// 回傳 E-Ink 高對比模式專用的固定黑白 [ThemeData]。
ThemeData buildEinkThemeData() => _buildEinkTheme();

/// 解析最終生效 of [ThemeData]：[isEinkMode] 為 true 時一律套用 E-Ink
/// 高對比主題，不論 [theme] 為何；為 false 時依 [theme] 套用對應主題。
ThemeData resolveThemeData({
  required AppTheme theme,
  required bool isEinkMode,
}) {
  if (isEinkMode) return buildEinkThemeData();
  return buildThemeData(theme);
}

// ──────────────────────────────────────────────────────────
// 私有建構方法
// ──────────────────────────────────────────────────────────

/// 電子紙可辨識度補強（epic-35-design-system-tokens Issue 2）＋視覺還原
/// （Visual Accuracy Mode，對照 `docs/research/uiux/reference/` 截圖／
/// `prototype/elinkbook_theme_prototype.html` 的 `EBSwitchRow` 手刻實作：
/// 開＝軌道 `primary`／圓點 `onPrimary`，關＝軌道近透明／圓點 `onSurface`）：
/// - **OFF 狀態**維持 Issue 2 原有電子紙補強決策不變——M3 預設 OFF 狀態吃
///   outline（thumbColor）／surfaceContainerHighest（trackColor），這兩個
///   角色在 Dark 主題改採 DESIGN.md 色值後跟 surface 的亮度差大幅縮小，
///   電子紙上不可靠（見 spec.md「Dark 主題色值衝突決議」），故 OFF 狀態三
///   插槽全部參照 colorScheme.onSurface，thumb／trackOutline 滿不透明、
///   track 用低透明度（0.15，具體數字為本工單自行詮釋的可調錨點）。
/// - **ON 狀態**改參照 colorScheme.primary／onPrimary（原本同 OFF 態一併
///   用 onSurface，導致非 E-Ink 主題下開關看起來一律是灰黑色，跟原型／
///   Reference 截圖的「開＝主色填滿」視覺不符）。E-Ink 主題下
///   `primary`＝純黑、`onPrimary`＝純白（見 `_buildEinkTheme()`），ON 態因
///   此呈現「黑底白點」，對比度比原本「黑底、黑點疊在半透明黑軌道上」更
///   高，不會削弱電子紙可辨識度，純視覺調整不影響 Issue 2 的補強效果。
SwitchThemeData _buildSwitchTheme(ColorScheme colorScheme) {
  return SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? colorScheme.onPrimary
          : colorScheme.onSurface,
    ),
    trackColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? colorScheme.primary
          : colorScheme.onSurface.withValues(alpha: 0.15),
    ),
    trackOutlineColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? colorScheme.primary
          : colorScheme.onSurface,
    ),
  );
}

/// 視覺還原（Visual Accuracy Mode，`docs/research/uiux/VISUAL_ANALYSIS.md`
/// 全域根因）：`Card`／`AppBar` 先前完全沒有共用主題覆寫，落回 M3 預設的
/// 圓角＋陰影，與 Reference 截圖（`prototype/elinkbook_theme_prototype.html`
/// 渲染結果）「無陰影、統一邊框、方正到中等圓角」的視覺語彙不符。改為
/// 全域一次補齊：無陰影＋`outline` 邊框＋8dp 圓角（沿用 `ReaderOptionTile`
/// 既有的 8dp 圓角慣例，見 `reader_option_tile.dart`，避免同一份設計系統
/// 出現兩種圓角數值）。
CardThemeData _buildCardTheme(ColorScheme colorScheme) {
  return CardThemeData(
    elevation: 0,
    color: colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: colorScheme.outline, width: 1.5),
    ),
  );
}

/// 視覺還原：AppBar 先前無底部邊框、標題字重落回 M3 預設（約 w400），與
/// Reference 截圖的「AppBar 下方常駐分隔線＋粗黑標題」不符。`shape` 用
/// `Border(bottom:)`——`Border` 是 `BoxBorder`，`BoxBorder` 實作
/// `ShapeBorder`，可直接指定給 `AppBarTheme.shape`，只畫底部一條邊，不會
/// 連左右/頂部也畫出邊框。
AppBarTheme _buildAppBarTheme(ColorScheme colorScheme) {
  return AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: 0,
    backgroundColor: colorScheme.surface,
    foregroundColor: colorScheme.onSurface,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w900,
      color: colorScheme.onSurface,
    ),
    shape: Border(bottom: BorderSide(color: colorScheme.outline, width: 2)),
  );
}

ThemeData _buildLightTheme() {
  const primary = Color(0xFF0284C7);
  const onPrimary = Color(0xFFFFFFFF);
  const primaryContainer = Color(0xFFE0F2FE);
  const onPrimaryContainer = Color(0xFF0284C7);
  const surface = Color(0xFFFFFFFF);
  const onSurface = Color(0xFF0F172A);
  const onSurfaceVariant = Color(0xFF334155);
  const outline = Color(0xFFCBDFE9);
  const scaffoldBackground = Color(0xFFF0F6FC);
  const surfaceContainerHighest = Color(0xFFE6F1FA);
  const error = Color(0xFFEF4444);

  final colorScheme = ColorScheme.light(
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    surfaceContainerHighest: surfaceContainerHighest,
    error: error,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    useMaterial3: true,
    switchTheme: _buildSwitchTheme(colorScheme),
    cardTheme: _buildCardTheme(colorScheme),
    appBarTheme: _buildAppBarTheme(colorScheme),
    extensions: const [
      ElinkTokens(
        highlightYellow: Color(0xFFFEF08A),
        highlightGreen: Color(0xFFBBF7D0),
        highlightBlue: Color(0xFFBFDBFE),
        underlineColor: Color(0xFF0284C7),
        progressTrack: Color(0xFFCBDFE9),
        coverPlaceholder: Color(0xFFE6F1FA),
        badgeScrim: Color(0xFF94A3B8),
        ttsActiveHighlight: Color(0xFFE0F2FE),
        isEink: false,
        reducedMotion: false,
        discretePaging: false,
      ),
    ],
  );
}

ThemeData _buildDarkTheme() {
  const primary = Color(0xFF38BDF8);
  const onPrimary = Color(0xFF141416);
  const primaryContainer = Color(0xFF182836);
  const onPrimaryContainer = Color(0xFF38BDF8);
  const surface = Color(0xFF1D1D22);
  const onSurface = Color(0xFFF2EFE6);
  const onSurfaceVariant = Color(0xFFB5B2A8);
  // 【epic-35-design-system-tokens Issue 2】改採 DESIGN.md §1.1 色表值，
  // 不再維持先前真機電子紙實測調亮值（outline #86868F／
  // surfaceContainerHighest #3C3C44，見 spec.md「Dark 主題色值衝突決議」）
  // ——選擇配色系統一致性優先。這兩個角色跟 surface 的感知亮度差因此大幅
  // 縮小，Switch 等元件不再靠這兩個角色的顏色對比撐可辨識度，改由
  // _buildSwitchTheme() 的 onSurface 邊框補強機制承接（見下方 switchTheme
  // 賦值處，Issue 2 Task 5 加上）。
  const outline = Color(0xFF2C2C34);
  const scaffoldBackground = Color(0xFF141416);
  const surfaceContainerHighest = Color(0xFF19191D);
  const error = Color(0xFFF87171);

  final colorScheme = ColorScheme.dark(
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    surfaceContainerHighest: surfaceContainerHighest,
    error: error,
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    useMaterial3: true,
    switchTheme: _buildSwitchTheme(colorScheme),
    cardTheme: _buildCardTheme(colorScheme),
    appBarTheme: _buildAppBarTheme(colorScheme),
    extensions: const [
      ElinkTokens(
        highlightYellow: Color(0xFF854D0E),
        highlightGreen: Color(0xFF166534),
        highlightBlue: Color(0xFF1E40AF),
        underlineColor: Color(0xFF38BDF8),
        progressTrack: Color(0xFF2C2C34),
        coverPlaceholder: Color(0xFF1D1D22),
        badgeScrim: Color(0xFF7A7872),
        ttsActiveHighlight: Color(0xFF182836),
        isEink: false,
        reducedMotion: false,
        discretePaging: false,
      ),
    ],
  );
}

ThemeData _buildSepiaTheme() {
  const primary = Color(0xFFB8362D);
  const onPrimary = Color(0xFFFFFFFF);
  const primaryContainer = Color(0xFFFAECEA);
  const onPrimaryContainer = Color(0xFFB8362D);
  const surface = Color(0xFFFAF3E3);
  const onSurface = Color(0xFF1F2022);
  const onSurfaceVariant = Color(0xFF535457);
  const outline = Color(0xFFE6DFCB);
  const scaffoldBackground = Color(0xFFFCFAF2);
  const surfaceContainerHighest = Color(0xFFF0EBD9);
  const error = Color(0xFFDC2626);

  final colorScheme = ColorScheme.light(
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    surfaceContainerHighest: surfaceContainerHighest,
    error: error,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    useMaterial3: true,
    switchTheme: _buildSwitchTheme(colorScheme),
    cardTheme: _buildCardTheme(colorScheme),
    appBarTheme: _buildAppBarTheme(colorScheme),
    extensions: const [
      ElinkTokens(
        highlightYellow: Color(0xFFFEF3C7),
        highlightGreen: Color(0xFFEDF5F0),
        highlightBlue: Color(0xFFEDF2F7),
        underlineColor: Color(0xFFB8362D),
        progressTrack: Color(0xFFE6DFCB),
        coverPlaceholder: Color(0xFFF0EBD9),
        badgeScrim: Color(0xFF848588),
        ttsActiveHighlight: Color(0xFFFAECEA),
        isEink: false,
        reducedMotion: false,
        discretePaging: false,
      ),
    ],
  );
}

ThemeData _buildEinkTheme() {
  const primary = Color(0xFF000000);
  const primaryContainer = Color(0xFFFFFFFF);
  const onPrimaryContainer = Color(0xFF000000);
  const surface = Color(0xFFFFFFFF);
  const onSurface = Color(0xFF000000);
  const onSurfaceVariant = Color(0xFF000000);
  const outline = Color(0xFF000000);
  const surfaceContainerHighest = Color(0xFFFFFFFF);
  const error = Color(0xFF000000);

  final colorScheme = ColorScheme.light(
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    surfaceContainerHighest: surfaceContainerHighest,
    error: error,
    onError: Colors.white,
    // epic-39-layout-settings-redesign Issue 4：ReaderSettingsSheet 預設集
    // 「目前套用中」反白列是全專案第一個實際讀取這兩個角色的功能，
    // ColorScheme.light() 若不明確覆寫會落回 M3 預設的灰紫色/近白色，
    // 與 E-Ink「全角色純黑白」的既定設計語言矛盾。
    inverseSurface: primary,
    onInverseSurface: Colors.white,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.white,
    useMaterial3: true,
    switchTheme: _buildSwitchTheme(colorScheme),
    cardTheme: _buildCardTheme(colorScheme),
    appBarTheme: _buildAppBarTheme(colorScheme),
    // 停用點擊水波紋效果與高亮，以避免電子紙裝置上產生嚴重殘影與刷新閃爍
    splashFactory: NoSplash.splashFactory,
    hoverColor: Colors.transparent,
    highlightColor: Colors.transparent,
    extensions: const [
      ElinkTokens(
        // highlightYellow／highlightGreen／highlightBlue／ttsActiveHighlight：
        // DESIGN.md §1.2 標註「無背景（改用下劃線／外框／點虛線）」、未給
        // 明確 hex 值——E-Ink 純黑白色盤下取黑色（描邊/底線用色），實際
        // 「不畫底色改畫線條」的渲染邏輯屬其他 Issue 範圍，這裡只決定色票值。
        highlightYellow: Color(0xFF000000),
        highlightGreen: Color(0xFF000000),
        highlightBlue: Color(0xFF000000),
        underlineColor: Color(0xFF000000),
        progressTrack: Color(0xFF000000),
        coverPlaceholder: Color(0xFFFFFFFF),
        badgeScrim: Color(0xFF000000),
        ttsActiveHighlight: Color(0xFF000000),
        isEink: true,
        reducedMotion: true,
        discretePaging: true,
      ),
    ],
  );
}
