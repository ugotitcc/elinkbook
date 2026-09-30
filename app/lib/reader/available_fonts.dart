import 'app_font.dart';
import 'custom_font.dart';

/// 可用字型（epic-54-architecture-optimization Issue 1，見 CONTEXT.md「可用字型」）：
/// 這台裝置、這次開書能實際渲染的字型集合——已下載且系統 WebView 載得動的內建
/// 字型，加上自訂字型。
///
/// 純值物件、不做 I/O：載入由呼叫端負責（[installedBuiltIn] 來自
/// `DownloadableFontStore.installedFonts()`，該方法已依 `supportedFonts` 過濾
/// WebView 載不動的字型；[customFonts] 來自 `CustomFontsRepository.listAll()`）。
///
/// 「偏好字型現在能不能用」這條規則只在 [effectiveFamily]：閱讀器渲染端與設定面板
/// 下拉選單的目前值共用同一個方法，兩邊不可能再分歧。
class AvailableFonts {
  /// 已下載且 WebView 載得動的內建字型。
  final Set<AppFont> installedBuiltIn;

  /// 使用者上傳的自訂字型（ADR 0021）。
  final List<CustomFont> customFonts;

  const AvailableFonts({
    this.installedBuiltIn = const {},
    this.customFonts = const [],
  });

  /// 什麼都沒有：兩個來源都沒提供（測試與舊呼叫端），或載入失敗的退路。
  static const AvailableFonts empty = AvailableFonts();

  /// 下拉選單可列出的內建字型，依 [AppFont.values] 的順序，不受集合迭代順序影響。
  List<AppFont> get builtInFonts => [
        for (final font in AppFont.values)
          if (installedBuiltIn.contains(font)) font,
      ];

  /// 偏好字型 [preferred]（`BookReaderPrefs.fontFamily`）實際該用的家族名稱。
  ///
  /// 偏好是「使用書本字型」（null），或指向不可用的字型（尚未下載、已刪除、
  /// WebView 載不動、名稱不認得、空字串）時回傳 null，讓書本字型生效；否則照
  /// 原值回傳。只影響渲染與顯示，**絕不改寫偏好**——字型之後變成可用（例如下載
  /// 完成）就自然恢復（ADR 0035）。
  String? effectiveFamily(String? preferred) {
    if (preferred == null) return null;
    if (installedBuiltIn.any((font) => font.familyName == preferred)) return preferred;
    if (customFonts.any((font) => font.familyName == preferred)) return preferred;
    return null;
  }
}
