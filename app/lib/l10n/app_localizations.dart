import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh', 'TW'),
    Locale('en'),
    Locale('zh'),
    Locale('zh', 'CN'),
  ];

  /// 系統保留分類「未分類」的表現層顯示名稱（僅用於畫面呈現，不影響底層資料庫欄位值，見 CONTEXT.md「介面語言」詞條）
  ///
  /// In zh_TW, this message translates to:
  /// **'未分類'**
  String get groupUncategorized;

  /// 通用「關閉」按鈕/圖示的無障礙提示文字（tooltip）
  ///
  /// In zh_TW, this message translates to:
  /// **'關閉'**
  String get close;

  /// 設定「外觀」分區的語言選擇入口標題
  ///
  /// In zh_TW, this message translates to:
  /// **'語言'**
  String get settingsLanguageTitle;

  /// 語言選擇器中「跟隨系統」選項標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'跟隨系統'**
  String get settingsLanguageFollowSystem;

  /// 「語言」入口未手動覆寫時的動態副標題，{language} 為依目前系統語言解析出的語言顯示名稱
  ///
  /// In zh_TW, this message translates to:
  /// **'跟隨系統（{language}）'**
  String settingsLanguageFollowSystemSubtitle(String language);

  /// 語言選項：正體中文
  ///
  /// In zh_TW, this message translates to:
  /// **'正體中文'**
  String get settingsLanguageZhTW;

  /// 語言選項：簡體中文
  ///
  /// In zh_TW, this message translates to:
  /// **'簡體中文'**
  String get settingsLanguageZhCN;

  /// 語言選項：英文（語言本身的固有名稱，不翻譯）
  ///
  /// In zh_TW, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// 通用「取消」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'取消'**
  String get cancel;

  /// 通用「確定」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'確定'**
  String get confirm;

  /// 通用操作失敗的 catch-all 錯誤訊息（非例外物件原始文字，見 spec.md §6 執行期例外訊息在地化慣例）
  ///
  /// In zh_TW, this message translates to:
  /// **'操作失敗，請稍後再試'**
  String get errorOperationFailed;

  /// 分類管理對話框標題
  ///
  /// In zh_TW, this message translates to:
  /// **'管理分類'**
  String get libraryGroupManageTitle;

  /// 分類管理對話框新增分類輸入框的 labelText
  ///
  /// In zh_TW, this message translates to:
  /// **'新增分類名稱'**
  String get libraryGroupAddFieldLabel;

  /// 分類管理對話框「新增」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'新增'**
  String get libraryGroupAddButton;

  /// 重新命名分類子對話框標題
  ///
  /// In zh_TW, this message translates to:
  /// **'重新命名分類'**
  String get libraryGroupRenameTitle;

  /// 刪除分類確認子對話框標題
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除分類'**
  String get libraryGroupDeleteTitle;

  /// 刪除分類確認訊息，{name} 為被刪除的分類名稱（使用者自訂，不翻譯），{uncategorized} 為 groupUncategorized 的已轉譯結果
  ///
  /// In zh_TW, this message translates to:
  /// **'確定要刪除分類「{name}」嗎？該分類下的書籍將改列為「{uncategorized}」。'**
  String libraryGroupDeleteConfirmMessage(String name, String uncategorized);

  /// 刪除分類確認子對話框的「刪除」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除'**
  String get libraryGroupDeleteButton;

  /// 新增/重新命名分類時，輸入名稱命中三語言任一保留字時顯示的錯誤訊息，{name} 為使用者實際輸入的名稱
  ///
  /// In zh_TW, this message translates to:
  /// **'「{name}」是系統保留的分類名稱，請使用其他名稱'**
  String libraryGroupReservedNameError(String name);

  /// 「移動到分類」目的地選擇對話框標題
  ///
  /// In zh_TW, this message translates to:
  /// **'移動到分類'**
  String get libraryMoveToGroupTitle;

  /// 一般網路/連線失敗的錯誤訊息（spec.md §6 執行期例外訊息在地化慣例）
  ///
  /// In zh_TW, this message translates to:
  /// **'載入失敗，請檢查網路連線'**
  String get errorNetworkConnection;

  /// 選檔前置重複偵測（Layer 1）命中既有書籍時的確認訊息，{name} 為雲端檔案名稱
  ///
  /// In zh_TW, this message translates to:
  /// **'「{name}」之前匯入過了，仍要建立新的一份嗎？'**
  String cloudBrowserDuplicateConfirmMessage(String name);

  /// 下載加入佇列後的 SnackBar 提示，{count} 為選取的檔案數，需正確處理英文單複數
  ///
  /// In zh_TW, this message translates to:
  /// **'已加入下載佇列（{count, plural, =1{1 個檔案} other{{count} 個檔案}}），可至「來源」畫面查看進度'**
  String cloudBrowserDownloadQueued(int count);

  /// 行動數據流量警示對話框標題
  ///
  /// In zh_TW, this message translates to:
  /// **'行動數據下載提醒'**
  String get cloudBrowserMobileDataDialogTitle;

  /// 行動數據流量警示對話框內容
  ///
  /// In zh_TW, this message translates to:
  /// **'目前使用行動數據連線，勾選的檔案中有超過 20MB 的項目，下載可能產生流量費用，確定要繼續嗎？'**
  String get cloudBrowserMobileDataDialogMessage;

  /// 行動數據流量警示對話框的確認按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'繼續下載'**
  String get cloudBrowserMobileDataDialogConfirm;

  /// AppBar 下載按鈕的無障礙提示文字（tooltip）
  ///
  /// In zh_TW, this message translates to:
  /// **'下載已選取'**
  String get cloudBrowserDownloadSelectedTooltip;

  /// 雲端帳號授權過期時的提示訊息，{provider} 為服務商品牌名（如 Google Drive／OneDrive，不翻譯）或找不到品牌名時的通用「雲端」標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'登入已過期，請至「設定」重新連結 {provider} 帳號'**
  String cloudBrowserReauthMessage(String provider);

  /// cloudBrowserReauthMessage 在 widget.title 為 null 時的通用服務商標籤 fallback
  ///
  /// In zh_TW, this message translates to:
  /// **'雲端'**
  String get cloudBrowserGenericProviderLabel;

  /// 雲端瀏覽畫面「匯入分類」下拉選單前的標籤文字
  ///
  /// In zh_TW, this message translates to:
  /// **'匯入分類：'**
  String get cloudBrowserImportCategoryLabel;

  /// 資料夾檔案數超過清單上限（1000 筆）時的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'這個資料夾檔案較多，僅顯示前 1000 筆'**
  String get cloudBrowserTruncatedNotice;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
