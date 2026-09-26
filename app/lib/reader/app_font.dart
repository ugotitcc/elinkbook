import '../l10n/app_localizations.dart';

/// App 內建字型（FR-09）。自訂字型上傳/管理屬 `epic-14-system-settings`
/// （FR-35），本 enum 僅定義固定的內建清單。
///
/// epic-48 起字型檔一律不打包進 APK（見 `pubspec.yaml`），改由 epic-49
/// 「可下載字型」提供；下載功能完成前，WebView 找不到字型檔時會由系統字型補位。
///
/// epic-48 曾停用原俠正楷、台灣圓體、源流明體，epic-49 Issue 8 恢復為可下載字型。
enum AppFont {
  sourceHanSans, // 思源黑體 SourceHanSansTC-VF.ttf
  sourceHanSerif, // 思源宋體 SourceHanSerifTC-VF.ttf
  guanKiapTsingKhai, // 原俠正楷 GuanKiapTsingKhai.ttf
  taiwanPearl, // 台灣圓體 TaiwanPearl-Regular.ttf
  genRyuMinTW, // 源流明體 GenRyuMinTW-Regular.ttf
}

/// [AppFont] 對應的實際字型家族名稱字串。此值透過 method channel 的
/// `fontFamily` key 送給原生端，原生端 `EpubReaderView.kt` 的
/// `addFontFamilyDeclaration` 登記字型時使用**完全相同**的字串（見
/// docs/epics/epic-3-fonts-layout/spec.md「自訂字型如何讓原生 WebView
/// 實際載入」）——兩處字串若不一致，`fontFamily` 偏好設定會被靜默忽略
/// （Readium 找不到對應的已登記字型，落回 WebView 預設字型）。
extension AppFontFamilyName on AppFont {
  String get familyName {
    switch (this) {
      case AppFont.sourceHanSans:
        return 'SourceHanSansTC';
      case AppFont.sourceHanSerif:
        return 'SourceHanSerifTC';
      case AppFont.guanKiapTsingKhai:
        return 'GuanKiapTsingKhai';
      case AppFont.taiwanPearl:
        return 'TaiwanPearl';
      case AppFont.genRyuMinTW:
        return 'GenRyuMinTW';
    }
  }

  /// 依目前介面語系顯示的字型名稱（epic-48：原本字型管理畫面與閱讀設定
  /// 下拉選單各自硬寫中文名稱，英文介面下仍顯示中文，收斂到這裡共用）。
  String displayName(AppLocalizations l10n) {
    switch (this) {
      case AppFont.sourceHanSans:
        return l10n.fontNameSourceHanSans;
      case AppFont.sourceHanSerif:
        return l10n.fontNameSourceHanSerif;
      case AppFont.guanKiapTsingKhai:
        return l10n.fontNameGuanKiapTsingKhai;
      case AppFont.taiwanPearl:
        return l10n.fontNameTaiwanPearl;
      case AppFont.genRyuMinTW:
        return l10n.fontNameGenRyuMinTW;
    }
  }
}
