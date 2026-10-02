import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一筆第三方授權：顯示名稱（授權頁的套件標題）與授權全文的 asset 路徑。
///
/// 授權全文取自各上游 LICENSE 原檔，不改寫（epic-55 design Q3）。
class ThirdPartyLicense {
  const ThirdPartyLicense({required this.packageName, required this.assetPath});

  /// 授權頁上顯示的套件名稱。
  final String packageName;

  /// 授權全文的 asset 路徑（需已在 pubspec.yaml 宣告）。
  final String assetPath;
}

/// 要登錄的授權清單。
///
/// 這些元件（含 5 款可下載字型）不是 Dart 套件，Flutter 不會自動收集它們的授權，
/// 但各授權都要求散布時保留版權與授權聲明。
const List<ThirdPartyLicense> kThirdPartyLicenses = [
  // foliate-js 與其內附的 zip.js、fflate：位於 android/app/src/main/assets/foliate/
  ThirdPartyLicense(
    packageName: 'foliate-js',
    assetPath: 'assets/licenses/foliate-js.txt',
  ),
  ThirdPartyLicense(
    packageName: 'zip.js',
    assetPath: 'assets/licenses/zip-js.txt',
  ),
  ThirdPartyLicense(
    packageName: 'fflate',
    assetPath: 'assets/licenses/fflate.txt',
  ),
  // OpenCC 簡繁字元對照表：編進 text_conversion_dict.js
  ThirdPartyLicense(
    packageName: 'OpenCC',
    assetPath: 'assets/licenses/opencc.txt',
  ),
  // Readium kotlin-toolkit：readium-shared／readium-streamer 兩個 Android 相依
  ThirdPartyLicense(
    packageName: 'Readium kotlin-toolkit',
    assetPath: 'assets/licenses/readium-kotlin-toolkit.txt',
  ),
  // 5 款可下載字型（SIL OFL 1.1）：字型檔不在 APK 內，由使用者在字型管理下載；
  // 但授權是靜態資訊，與是否已下載無關，永遠顯示（epic-55 design Q5）。
  // 台灣圓體的上游授權檔沒有版權行，原文照顯示、不補寫；asset 末尾另附
  // README 的來源說明（design Q4 修訂版）。
  ThirdPartyLicense(
    packageName: '思源黑體',
    assetPath: 'assets/licenses/font-source-han-sans.txt',
  ),
  ThirdPartyLicense(
    packageName: '思源宋體',
    assetPath: 'assets/licenses/font-source-han-serif.txt',
  ),
  ThirdPartyLicense(
    packageName: '原俠正楷',
    assetPath: 'assets/licenses/font-guan-kiap-tsing-khai.txt',
  ),
  ThirdPartyLicense(
    packageName: '台灣圓體',
    assetPath: 'assets/licenses/font-taiwan-pearl.txt',
  ),
  ThirdPartyLicense(
    packageName: '源流明體',
    assetPath: 'assets/licenses/font-gen-ryu-min.txt',
  ),
];

/// 把 [kThirdPartyLicenses] 登錄到 Flutter 的 [LicenseRegistry]，
/// 授權頁（showLicensePage）會自動列出。
///
/// 只呼叫一次 [LicenseRegistry.addLicense]；每筆授權讀一次 asset。
/// asset 讀不到（任何例外）或內容為空白時略過該筆並繼續，
/// 不讓整個授權頁失敗。[bundle] 預設為 [rootBundle]，測試時可注入。
void registerThirdPartyLicenses({AssetBundle? bundle}) {
  final assetBundle = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    for (final license in kThirdPartyLicenses) {
      final String text;
      try {
        text = await assetBundle.loadString(license.assetPath);
      } catch (_) {
        continue; // 讀不到就略過這一筆
      }
      if (text.trim().isEmpty) continue; // 空檔不登錄
      yield LicenseEntryWithLineBreaks([license.packageName], text);
    }
  });
}
