/// App 內建的 5 款字型（FR-09）。皆為本地 asset 字型（`app/assets/fonts/`），
/// 非系統字型；自訂字型上傳/管理屬 `epic-14-system-settings`（FR-35），
/// 本 epic 僅從此固定清單中選擇。
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
}
