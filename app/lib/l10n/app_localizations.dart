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

  /// 語言選項：正體中文（語言本身的固有名稱，各語系一律相同，不翻譯）
  ///
  /// In zh_TW, this message translates to:
  /// **'正體中文'**
  String get settingsLanguageZhTW;

  /// 語言選項：簡體中文（語言本身的固有名稱，各語系一律寫成「简体中文」，不翻譯）
  ///
  /// In zh_TW, this message translates to:
  /// **'简体中文'**
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

  /// 重新命名分類時，新名稱與既有分類撞名時顯示的錯誤訊息，{name} 為使用者嘗試使用的新名稱
  ///
  /// In zh_TW, this message translates to:
  /// **'分類「{name}」已存在，請使用其他名稱'**
  String libraryGroupNameAlreadyExistsError(String name);

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

  /// 單書「⋮」動作選單「詳細資料」選項文字
  ///
  /// In zh_TW, this message translates to:
  /// **'詳細資料'**
  String get bookActionShowDetails;

  /// 單書「⋮」動作選單「移動」選項文字（移動到分類）
  ///
  /// In zh_TW, this message translates to:
  /// **'移動'**
  String get bookActionMove;

  /// 單書「⋮」動作選單「版面覆寫」選項文字
  ///
  /// In zh_TW, this message translates to:
  /// **'版面覆寫'**
  String get bookActionLayoutOverride;

  /// 單書「⋮」動作選單「移除快取」選項文字（僅 Calibre 來源已下載書籍顯示）
  ///
  /// In zh_TW, this message translates to:
  /// **'移除快取'**
  String get bookActionRemoveCache;

  /// 單書「⋮」動作選單「刪除」選項文字
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除'**
  String get bookActionDelete;

  /// 「啟用全文檢索」確認對話框標題（PDF／其他格式共用同一對話框）
  ///
  /// In zh_TW, this message translates to:
  /// **'啟用全文檢索'**
  String get fullTextSearchEnableDialogTitle;

  /// 啟用 PDF 全文檢索時的確認訊息（額外附加掃描件提示）
  ///
  /// In zh_TW, this message translates to:
  /// **'將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量消耗，是否繼續？\n\n部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容，索引後仍查不到屬於正常情況。'**
  String get fullTextSearchEnableMessagePdf;

  /// 啟用其他格式（EPUB/TXT/KF8）全文檢索時的確認訊息
  ///
  /// In zh_TW, this message translates to:
  /// **'將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量消耗，是否繼續？'**
  String get fullTextSearchEnableMessageOther;

  /// 「啟用全文檢索」確認對話框的確認按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'確認開啟'**
  String get fullTextSearchEnableConfirmButton;

  /// 單書內容搜尋畫面輸入框的 hintText
  ///
  /// In zh_TW, this message translates to:
  /// **'在本書中搜尋...'**
  String get bookSearchHint;

  /// 搜尋輸入框「清除」按鈕的無障礙提示文字，book_search_screen.dart／library_search_screen.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'清除'**
  String get searchClearTooltip;

  /// 裝置不支援全文檢索時的提示訊息，book_search_screen.dart／library_search_screen.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'本裝置不支援全文檢索'**
  String get fullTextSearchUnavailableMessage;

  /// 單書內容搜尋結果數量摘要（未截斷情境），{total} 為結果總數
  ///
  /// In zh_TW, this message translates to:
  /// **'{total, plural, =1{共 1 筆結果} other{共 {total} 筆結果}}'**
  String bookSearchResultsSummary(int total);

  /// 單書內容搜尋結果數量摘要（截斷情境），{shown} 為目前清單實際渲染的筆數（呼叫端傳入 result.matches.length），{total} 為該書全部命中筆數（result.totalMatches）
  ///
  /// In zh_TW, this message translates to:
  /// **'僅顯示前 {shown} 筆，共 {total, plural, =1{1 筆結果} other{{total} 筆結果}}'**
  String bookSearchResultsSummaryTruncated(int shown, int total);

  /// 單書內容搜尋結果排序切換按鈕：依書中出現順序
  ///
  /// In zh_TW, this message translates to:
  /// **'依書中順序'**
  String get bookSearchSortByPosition;

  /// 單書內容搜尋結果排序切換按鈕：依相關度
  ///
  /// In zh_TW, this message translates to:
  /// **'依相關度排序'**
  String get bookSearchSortByRelevance;

  /// 全文檢索已啟用但查無結果時的提示，book_search_screen.dart／library_search_screen.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'查無符合的書內內容'**
  String get fullTextSearchNoContentMatches;

  /// PDF 搜尋結果片段的位置標籤，{page} 為頁碼（1-based）
  ///
  /// In zh_TW, this message translates to:
  /// **'第 {page} 頁'**
  String bookSearchLocationPage(int page);

  /// 非 PDF 格式搜尋結果片段的位置標籤，{chapter} 為章節序號（1-based）
  ///
  /// In zh_TW, this message translates to:
  /// **'第 {chapter} 章'**
  String bookSearchLocationChapter(int chapter);

  /// 書內搜尋畫面 AppBar「全文檢索設定」入口彈出的 EBSheetShell 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'全文檢索設定'**
  String get librarySearchSettingsSheetTitle;

  /// 全庫內容搜尋畫面的 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'搜尋書內內容'**
  String get librarySearchScreenTitle;

  /// 全庫內容搜尋畫面 AppBar 設定圖示的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'全文檢索設定'**
  String get librarySearchSettingsTooltip;

  /// 全庫內容搜尋畫面輸入框的 hintText
  ///
  /// In zh_TW, this message translates to:
  /// **'搜尋書名、作者或書本內容...'**
  String get librarySearchFieldHint;

  /// 全庫內容搜尋結果「書名/作者匹配」分區標題
  ///
  /// In zh_TW, this message translates to:
  /// **'書名/作者匹配'**
  String get librarySearchTitleAuthorSectionHeader;

  /// 全庫內容搜尋結果「內容匹配」分區標題
  ///
  /// In zh_TW, this message translates to:
  /// **'內容匹配'**
  String get librarySearchContentSectionHeader;

  /// PDF／其他格式全文檢索皆未啟用時的引導卡片文字
  ///
  /// In zh_TW, this message translates to:
  /// **'尚未啟用全文檢索，開啟後才能搜尋書本內容（點擊右上角設定圖示開啟）'**
  String get librarySearchGuidanceNotEnabled;

  /// 僅 PDF 全文檢索已啟用時的引導卡片文字
  ///
  /// In zh_TW, this message translates to:
  /// **'已啟用「PDF」全文檢索，其他格式尚未啟用'**
  String get librarySearchGuidancePdfOnly;

  /// 僅其他格式全文檢索已啟用時的引導卡片文字
  ///
  /// In zh_TW, this message translates to:
  /// **'已啟用「其他格式」全文檢索，PDF 內容尚未啟用'**
  String get librarySearchGuidanceOtherOnly;

  /// 內容匹配卡片「查看全部」下鑽按鈕文字，{total} 為該書總命中數，{remaining} 為清單未顯示的剩餘筆數
  ///
  /// In zh_TW, this message translates to:
  /// **'{total, plural, =1{查看全部 1 筆結果} other{查看全部 {total} 筆結果}}（{remaining, plural, =1{還有 1 筆} other{還有 {remaining} 筆}}）'**
  String librarySearchDrillDownButton(int total, int remaining);

  /// 全文檢索設定面板 PDF 開關項目標題
  ///
  /// In zh_TW, this message translates to:
  /// **'PDF 全文檢索'**
  String get librarySearchPdfToggleTitle;

  /// 全文檢索設定面板 PDF 開關項目副標題
  ///
  /// In zh_TW, this message translates to:
  /// **'部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容'**
  String get librarySearchPdfToggleSubtitle;

  /// 全文檢索設定面板「重建索引」按鈕的無障礙提示文字，PDF／其他格式兩個開關項目共用
  ///
  /// In zh_TW, this message translates to:
  /// **'重建索引'**
  String get librarySearchRebuildIndexTooltip;

  /// 全文檢索設定面板「其他格式」開關項目標題
  ///
  /// In zh_TW, this message translates to:
  /// **'其他格式全文檢索'**
  String get librarySearchFoliateToggleTitle;

  /// 全文檢索設定面板「其他格式」開關項目副標題
  ///
  /// In zh_TW, this message translates to:
  /// **'EPUB／TXT／KF8 等格式的背景索引建置'**
  String get librarySearchFoliateToggleSubtitle;

  /// 下鑽分類檢視時 AppBar 返回按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'返回上層'**
  String get libraryBackButtonTooltip;

  /// 書架頂層（未下鑽任何分類）AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'書架'**
  String get libraryShelfTitle;

  /// AppBar 排序/檢視選單按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'排序與檢視'**
  String get librarySortViewTooltip;

  /// 排序選單選項：依最後閱讀時間
  ///
  /// In zh_TW, this message translates to:
  /// **'最後閱讀'**
  String get librarySortByLastRead;

  /// 排序選單選項：依建立時間
  ///
  /// In zh_TW, this message translates to:
  /// **'建立時間'**
  String get librarySortByCreateTime;

  /// 排序選單選項：依作者
  ///
  /// In zh_TW, this message translates to:
  /// **'作者'**
  String get librarySortByAuthor;

  /// 排序選單選項：依書名
  ///
  /// In zh_TW, this message translates to:
  /// **'書名'**
  String get librarySortByTitle;

  /// 排序選單「切換檢視模式」項目文字（目前為格狀時顯示，點擊後切換為列表）
  ///
  /// In zh_TW, this message translates to:
  /// **'切換為列表'**
  String get libraryToggleViewToList;

  /// 排序選單「切換檢視模式」項目文字（目前為列表時顯示，點擊後切換為格狀）
  ///
  /// In zh_TW, this message translates to:
  /// **'切換為書架'**
  String get libraryToggleViewToShelf;

  /// 排序選單「管理分類」項目文字（僅頂層書架顯示，下鑽分類時不顯示）
  ///
  /// In zh_TW, this message translates to:
  /// **'管理分類...'**
  String get libraryManageGroupsMenuItem;

  /// AppBar「來源」圖示按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'來源'**
  String get librarySourceTooltip;

  /// AppBar「設定」圖示按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'設定'**
  String get librarySettingsTooltip;

  /// 選取模式 AppBar「✕」取消按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'取消選取'**
  String get libraryCancelSelectionTooltip;

  /// 選取模式 AppBar 標題，{count} 為目前已選取的書籍數
  ///
  /// In zh_TW, this message translates to:
  /// **'{count, plural, =1{已選取 1 本} other{已選取 {count} 本}}'**
  String librarySelectedCount(int count);

  /// 選取模式 AppBar「移動到分類」圖示按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'移動到分類'**
  String get libraryMoveToGroupTooltip;

  /// 選取模式 AppBar「強制 FXL」圖示按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'強制 FXL'**
  String get libraryForceFxlTooltip;

  /// 選取模式 AppBar「恢復自動判斷」圖示按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'恢復自動判斷'**
  String get libraryRestoreAutoLayoutTooltip;

  /// 選取模式 AppBar「刪除」圖示按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除'**
  String get libraryDeleteTooltip;

  /// 選取模式 AppBar「移除本機快取」圖示按鈕的無障礙提示文字，同時作為單書移除快取確認對話框標題（文字完全相同）
  ///
  /// In zh_TW, this message translates to:
  /// **'移除本機快取'**
  String get libraryRemoveLocalCacheTooltip;

  /// 書架無任何書籍時的空狀態提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'尚未匯入書籍'**
  String get libraryEmptyStateMessage;

  /// 空狀態「匯入書籍」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'匯入書籍'**
  String get libraryEmptyStateImportButton;

  /// 書架常駐搜尋列輸入框的 hintText
  ///
  /// In zh_TW, this message translates to:
  /// **'搜尋書名或作者...'**
  String get librarySearchHint;

  /// 書架搜尋列下方「搜尋書本內容」導覽橫幅文字
  ///
  /// In zh_TW, this message translates to:
  /// **'搜尋書本內容'**
  String get libraryContentSearchEntryLabel;

  /// 書架快速搜尋（書名/作者）查無結果時的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'找不到符合的書籍'**
  String get libraryNoMatchingBooks;

  /// 刪除書籍確認對話框標題（單書／批次共用）
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除書籍'**
  String get libraryDeleteBooksDialogTitle;

  /// 刪除書籍確認對話框內容，{count} 為將被刪除的書籍數（單書刪除時為 1）
  ///
  /// In zh_TW, this message translates to:
  /// **'{count, plural, =1{將刪除已選取的 1 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？} other{將刪除已選取的 {count} 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？}}'**
  String libraryDeleteBooksConfirmMessage(int count);

  /// 刪除書籍確認對話框的「刪除」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除'**
  String get libraryDeleteBooksConfirmButton;

  /// 重新下載確認對話框的標題與確認按鈕（兩處文字完全相同，共用一個 key）
  ///
  /// In zh_TW, this message translates to:
  /// **'重新下載'**
  String get libraryRedownloadAction;

  /// 重新下載確認訊息（非行動數據連線情境），{title} 為書名
  ///
  /// In zh_TW, this message translates to:
  /// **'即將重新下載「{title}」，確定要繼續嗎？'**
  String libraryRedownloadConfirmMessage(String title);

  /// 重新下載確認訊息（行動數據連線情境），{title} 為書名
  ///
  /// In zh_TW, this message translates to:
  /// **'即將重新下載「{title}」，目前使用行動數據連線，可能產生流量費用，確定要繼續嗎？'**
  String libraryRedownloadConfirmMessageMobileData(String title);

  /// 遠端書庫依賴未提供時，點擊重新下載顯示的 SnackBar 訊息
  ///
  /// In zh_TW, this message translates to:
  /// **'遠端書庫功能未啟用，無法重新下載'**
  String get libraryRemoteDisabledMessage;

  /// 重新下載時找不到書籍對應的遠端站點設定，顯示的 SnackBar 訊息
  ///
  /// In zh_TW, this message translates to:
  /// **'找不到對應的遠端書庫站點'**
  String get libraryRemoteServerNotFoundMessage;

  /// 重新下載過程發生例外時顯示的 SnackBar 訊息
  ///
  /// In zh_TW, this message translates to:
  /// **'重新下載失敗，請稍後再試'**
  String get libraryRedownloadFailedMessage;

  /// 移除本機快取確認對話框內容，{title} 為書名
  ///
  /// In zh_TW, this message translates to:
  /// **'將移除「{title}」的本機檔案，書籍紀錄與閱讀進度會保留，之後可重新下載。確定要移除嗎？'**
  String libraryRemoveCacheConfirmMessage(String title);

  /// 移除本機快取確認對話框的「移除」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'移除'**
  String get libraryRemoveCacheConfirmButton;

  /// 分類拼貼格（格狀檢視）左上角角標文字
  ///
  /// In zh_TW, this message translates to:
  /// **'分類'**
  String get libraryGroupBadgeLabel;

  /// 分類拼貼格顯示的書籍數量，{count} 為該分類書籍總數
  ///
  /// In zh_TW, this message translates to:
  /// **'{count, plural, =1{1 本} other{{count} 本}}'**
  String libraryGroupTileCount(int count);

  /// 書籍格/列項目「⋮」動作選單按鈕的無障礙提示文字（格狀／列表檢視共用）
  ///
  /// In zh_TW, this message translates to:
  /// **'更多'**
  String get libraryBookMenuTooltip;

  /// 書架頂部常駐「繼續閱讀列」的小標籤文字
  ///
  /// In zh_TW, this message translates to:
  /// **'繼續閱讀'**
  String get libraryContinueReadingLabel;

  /// 書籍詳細資料對話框「檔案大小」欄位在書籍尚未下載時顯示
  ///
  /// In zh_TW, this message translates to:
  /// **'尚未下載'**
  String get libraryBookNotDownloaded;

  /// 書籍詳細資料對話框「檔案大小」欄位在檔案不存在/讀取失敗/發生例外時的回退顯示
  ///
  /// In zh_TW, this message translates to:
  /// **'未知大小'**
  String get libraryUnknownFileSize;

  /// 書籍詳細資料對話框「檔案大小」欄位在 FutureBuilder 尚未回傳結果時顯示
  ///
  /// In zh_TW, this message translates to:
  /// **'讀取中...'**
  String get libraryLoadingEllipsis;

  /// 書籍詳細資料對話框「作者」欄位，{author} 為已解析的作者顯示文字（含 libraryUnknownAuthor 回退與簡繁轉換結果）
  ///
  /// In zh_TW, this message translates to:
  /// **'作者：{author}'**
  String libraryDetailAuthorLabel(String author);

  /// 書籍作者欄位為 null 時的回退文字，供組進 libraryDetailAuthorLabel 的 {author} placeholder
  ///
  /// In zh_TW, this message translates to:
  /// **'未知'**
  String get libraryUnknownAuthor;

  /// 書籍詳細資料對話框「格式」欄位，{format} 為格式名稱（epub/pdf 等，不翻譯）
  ///
  /// In zh_TW, this message translates to:
  /// **'格式：{format}'**
  String libraryDetailFormatLabel(String format);

  /// 書籍詳細資料對話框「檔案大小」欄位，{size} 為已格式化的大小文字或上述三種回退文字之一
  ///
  /// In zh_TW, this message translates to:
  /// **'檔案大小：{size}'**
  String libraryDetailFileSizeLabel(String size);

  /// 書籍詳細資料對話框「進度」欄位，{progress} 為百分比字串（如 50%，不需翻譯）
  ///
  /// In zh_TW, this message translates to:
  /// **'進度：{progress}'**
  String libraryDetailProgressLabel(String progress);

  /// 書籍詳細資料對話框「最後閱讀」欄位，{date} 為已依 DateFormat 格式化的日期字串或 libraryNeverRead
  ///
  /// In zh_TW, this message translates to:
  /// **'最後閱讀：{date}'**
  String libraryDetailLastReadLabel(String date);

  /// 書籍從未被閱讀過（lastReadTime epoch 0）時的回退文字
  ///
  /// In zh_TW, this message translates to:
  /// **'尚未閱讀'**
  String get libraryNeverRead;

  /// 版面覆寫對話框標題（loading／已載入兩種狀態皆使用同一文字）
  ///
  /// In zh_TW, this message translates to:
  /// **'版面覆寫'**
  String get libraryLayoutOverrideTitle;

  /// 版面覆寫對話框「排版方向」區塊小標題
  ///
  /// In zh_TW, this message translates to:
  /// **'排版方向'**
  String get libraryLayoutOverrideWritingModeLabel;

  /// 版面覆寫對話框排版方向選項：使用書籍原生排版（不覆寫）
  ///
  /// In zh_TW, this message translates to:
  /// **'使用書籍排版'**
  String get libraryLayoutOverrideWritingModeDefault;

  /// 版面覆寫對話框排版方向選項：強制橫排
  ///
  /// In zh_TW, this message translates to:
  /// **'橫排'**
  String get libraryLayoutOverrideWritingModeHorizontal;

  /// 版面覆寫對話框排版方向選項：強制直排
  ///
  /// In zh_TW, this message translates to:
  /// **'直排'**
  String get libraryLayoutOverrideWritingModeVertical;

  /// 版面覆寫對話框「翻頁模式」區塊小標題
  ///
  /// In zh_TW, this message translates to:
  /// **'翻頁模式'**
  String get libraryLayoutOverridePageTurnModeLabel;

  /// 版面覆寫對話框翻頁模式選項：使用全域預設（不覆寫）
  ///
  /// In zh_TW, this message translates to:
  /// **'使用全域預設'**
  String get libraryLayoutOverridePageTurnModeDefault;

  /// 版面覆寫對話框翻頁模式選項：強制分頁
  ///
  /// In zh_TW, this message translates to:
  /// **'分頁'**
  String get libraryLayoutOverridePageTurnModePaginated;

  /// 版面覆寫對話框翻頁模式選項：強制捲動
  ///
  /// In zh_TW, this message translates to:
  /// **'捲動'**
  String get libraryLayoutOverridePageTurnModeScroll;

  /// 版面覆寫對話框「儲存」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存'**
  String get libraryLayoutOverrideSaveButton;

  /// 閱讀器頂部 Chrome 列返回按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'返回'**
  String get readerBackTooltip;

  /// 閱讀器頂部 Chrome 列搜尋按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'搜尋內文'**
  String get readerSearchTooltip;

  /// 閱讀器頂部 Chrome 列收合底部工具列按鈕的提示文字（底部工具列目前顯示中）
  ///
  /// In zh_TW, this message translates to:
  /// **'隱藏工具列'**
  String get readerHideToolbarTooltip;

  /// 閱讀器頂部 Chrome 列展開底部工具列按鈕的提示文字（底部工具列目前收合中）
  ///
  /// In zh_TW, this message translates to:
  /// **'顯示工具列'**
  String get readerShowToolbarTooltip;

  /// 閱讀器底部選單列「目錄」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'目錄'**
  String get readerTocTooltip;

  /// 閱讀器底部選單列書籤按鈕提示文字：目前頁已加入書籤
  ///
  /// In zh_TW, this message translates to:
  /// **'已加入此頁書籤'**
  String get readerBookmarkAddedTooltip;

  /// 閱讀器底部選單列書籤按鈕提示文字：目前頁尚未加入書籤
  ///
  /// In zh_TW, this message translates to:
  /// **'加入此頁書籤'**
  String get readerBookmarkAddTooltip;

  /// 閱讀器底部選單列「劃線筆記」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'劃線筆記'**
  String get readerAnnotationsTooltip;

  /// 閱讀器底部選單列「版面」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'版面'**
  String get readerLayoutTooltip;

  /// 閱讀器底部選單列「朗讀」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'朗讀'**
  String get readerTtsTooltip;

  /// PagingBar「上一頁」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'上一頁'**
  String get readerPagingPreviousTooltip;

  /// PagingBar「下一頁」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'下一頁'**
  String get readerPagingNextTooltip;

  /// PDF 縮圖面板在 totalPages <= 0 時顯示的空狀態文字
  ///
  /// In zh_TW, this message translates to:
  /// **'無可用頁面'**
  String get readerPdfNoPagesAvailable;

  /// 備註編輯對話框「儲存」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存'**
  String get readerNoteDialogSaveButton;

  /// showNoteTextDialog() 呼叫端未明確指定 title 時的預設對話框標題（目前所有呼叫端皆明確指定，此為防禦性預設值）
  ///
  /// In zh_TW, this message translates to:
  /// **'備註'**
  String get readerNoteDialogDefaultTitle;

  /// 選字浮動工具列「底線」樣式按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'底線'**
  String get readerAnnotationUnderlineTooltip;

  /// 選字浮動工具列「複製」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'複製'**
  String get readerAnnotationCopyTooltip;

  /// 選字浮動工具列備註按鈕提示文字：這次選取已有備註
  ///
  /// In zh_TW, this message translates to:
  /// **'編輯備註'**
  String get readerAnnotationEditNoteTooltip;

  /// 選字浮動工具列備註按鈕提示文字：這次選取尚無備註
  ///
  /// In zh_TW, this message translates to:
  /// **'新增備註'**
  String get readerAnnotationAddNoteTooltip;

  /// 選字浮動工具列刪除按鈕提示文字：這次選取同時命中劃線與備註
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除畫線與備註'**
  String get readerAnnotationDeleteHighlightAndNote;

  /// 選字浮動工具列刪除按鈕提示文字：這次選取只命中劃線
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除畫線'**
  String get readerAnnotationDeleteHighlight;

  /// 選字浮動工具列刪除按鈕提示文字：這次選取只命中備註
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除備註'**
  String get readerAnnotationDeleteNote;

  /// PDF 內文搜尋面板輸入框的 hintText
  ///
  /// In zh_TW, this message translates to:
  /// **'搜尋文字…'**
  String get readerPdfSearchHint;

  /// PDF 內文搜尋查無結果時的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'找不到符合的文字'**
  String get readerPdfSearchNoMatches;

  /// PDF 內文搜尋「上一個」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'上一個'**
  String get readerPdfSearchPreviousTooltip;

  /// PDF 內文搜尋「下一個」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'下一個'**
  String get readerPdfSearchNextTooltip;

  /// 閱讀位置衝突對話框標題，{bookTitle} 為書名（使用者資料，不翻譯）
  ///
  /// In zh_TW, this message translates to:
  /// **'「{bookTitle}」的閱讀進度不一致'**
  String readerPositionConflictTitle(String bookTitle);

  /// 閱讀位置衝突對話框內容，{local}／{remote} 為已格式化的位置描述文字（readerPositionConflictPdfLocation 或 readerPositionConflictEpubLocation 的結果）
  ///
  /// In zh_TW, this message translates to:
  /// **'偵測到另一台裝置也更新過這本書的閱讀進度，請選擇要保留哪一邊：\n\n本機：{local}\n雲端：{remote}'**
  String readerPositionConflictMessage(String local, String remote);

  /// PDF 格式的位置描述，{page} 為頁碼（1-based），{percent} 為進度百分比整數
  ///
  /// In zh_TW, this message translates to:
  /// **'第 {page} 頁（進度 {percent}%）'**
  String readerPositionConflictPdfLocation(int page, int percent);

  /// 非 PDF 格式（CFI 定位無法簡單轉人類可讀文字）的位置描述，{percent} 為進度百分比整數
  ///
  /// In zh_TW, this message translates to:
  /// **'進度 {percent}%'**
  String readerPositionConflictEpubLocation(int percent);

  /// 閱讀位置衝突對話框「保留雲端」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'保留雲端'**
  String get readerPositionConflictKeepCloud;

  /// 閱讀位置衝突對話框「保留本機」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'保留本機'**
  String get readerPositionConflictKeepLocal;

  /// 目錄 Bottom Sheet 標題列文字（含書本 Emoji，比照既有設計慣例保留）
  ///
  /// In zh_TW, this message translates to:
  /// **'📖 目錄'**
  String get readerTocTitle;

  /// 本書解析不出任何目錄項目時的空狀態提示
  ///
  /// In zh_TW, this message translates to:
  /// **'本書無目錄資料'**
  String get readerTocEmptyMessage;

  /// PDF 目錄 Bottom Sheet 第一個分頁籤：章節目錄
  ///
  /// In zh_TW, this message translates to:
  /// **'章節目錄'**
  String get readerTocTabChapters;

  /// PDF 目錄 Bottom Sheet 第二個分頁籤：頁碼縮圖
  ///
  /// In zh_TW, this message translates to:
  /// **'縮圖'**
  String get readerTocTabThumbnails;

  /// PDF 目錄 Bottom Sheet 第三個分頁籤：內文搜尋
  ///
  /// In zh_TW, this message translates to:
  /// **'搜尋'**
  String get readerTocTabSearch;

  /// 縮圖/搜尋分頁內容為 null 時的佔位文字（目前兩個分頁皆已實作，此為向後相容的防禦性回退）
  ///
  /// In zh_TW, this message translates to:
  /// **'此功能將於後續版本提供'**
  String get readerFeatureComingSoon;

  /// TTS 面板播放鍵在 CBZ（純圖像格式）停用狀態下的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'CBZ 為純圖像格式，不支援語音朗讀'**
  String get readerTtsCbzUnsupportedTooltip;

  /// TTS 面板「上一句」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'上一句'**
  String get readerTtsPreviousTooltip;

  /// TTS 面板播放/暫停鍵提示文字：目前朗讀中，點擊暫停
  ///
  /// In zh_TW, this message translates to:
  /// **'暫停朗讀'**
  String get readerTtsPauseTooltip;

  /// TTS 面板播放/暫停鍵提示文字：目前暫停中，點擊開始
  ///
  /// In zh_TW, this message translates to:
  /// **'開始朗讀'**
  String get readerTtsPlayTooltip;

  /// TTS 面板「下一句」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'下一句'**
  String get readerTtsNextTooltip;

  /// TTS 面板語速按鈕的無障礙提示文字，{speed} 為目前語速（已格式化為小數點後兩位的字串）
  ///
  /// In zh_TW, this message translates to:
  /// **'朗讀語速：{speed}x（點擊切換）'**
  String readerTtsSpeedTooltip(String speed);

  /// TTS 面板「選擇語音」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇語音'**
  String get readerTtsVoiceTooltip;

  /// TTS 面板睡眠定時器按鈕文字：尚未設定定時器
  ///
  /// In zh_TW, this message translates to:
  /// **'定時'**
  String get readerTtsSleepTimerLabel;

  /// TTS 面板睡眠定時器按鈕文字：已設定定時器，{minutes} 為剩餘分鐘數
  ///
  /// In zh_TW, this message translates to:
  /// **'定時 {minutes} 分'**
  String readerTtsSleepTimerLabelWithMinutes(int minutes);

  /// TTS 面板收合/展開按鈕文字：目前展開中，點擊收合
  ///
  /// In zh_TW, this message translates to:
  /// **'收合'**
  String get readerTtsCollapseLabel;

  /// TTS 面板收合/展開按鈕文字：目前收合中，點擊展開
  ///
  /// In zh_TW, this message translates to:
  /// **'展開'**
  String get readerTtsExpandLabel;

  /// TTS 面板「停止朗讀」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'停止'**
  String get readerTtsStopLabel;

  /// 筆記 Bottom Sheet（書籤／劃線與備註）的標題
  ///
  /// In zh_TW, this message translates to:
  /// **'筆記'**
  String get readerNotesSheetTitle;

  /// 筆記 Bottom Sheet 標題列「導出為 Markdown」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'導出為 Markdown'**
  String get readerNotesSheetExportMarkdownTooltip;

  /// 筆記 Bottom Sheet 第一個分頁籤：書籤
  ///
  /// In zh_TW, this message translates to:
  /// **'書籤'**
  String get readerNotesSheetTabBookmarks;

  /// 筆記 Bottom Sheet 第二個分頁籤：劃線與備註
  ///
  /// In zh_TW, this message translates to:
  /// **'劃線與備註'**
  String get readerNotesSheetTabAnnotations;

  /// 書籤分頁「刪除該書所有書籤」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除該書所有書籤'**
  String get readerNotesSheetDeleteAllBookmarksTooltip;

  /// 重新命名書籤對話框標題
  ///
  /// In zh_TW, this message translates to:
  /// **'重新命名書籤'**
  String get readerNotesSheetRenameBookmarkTitle;

  /// 筆記 Bottom Sheet 內各種刪除確認對話框的「刪除」按鈕文字（書籤/劃線/備註批次刪除共用）
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除'**
  String get readerDeleteConfirmButton;

  /// 刪除全部書籤確認對話框標題，{count} 為目前書籤總數
  ///
  /// In zh_TW, this message translates to:
  /// **'確定要刪除全部書籤嗎？（共 {count} 筆）'**
  String readerNotesSheetDeleteAllBookmarksConfirm(int count);

  /// 書籤列項目「重新命名」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'重新命名'**
  String get readerNotesSheetRenameTooltip;

  /// 書籤/劃線/備註單筆項目「刪除」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除'**
  String get readerNotesSheetDeleteItemTooltip;

  /// 劃線與備註分頁的空狀態提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'尚無劃線或備註'**
  String get readerNotesSheetNoAnnotationsPlaceholder;

  /// 劃線與備註分頁「刪除所有劃線」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除所有劃線'**
  String get readerNotesSheetDeleteAllHighlightsButton;

  /// 劃線與備註分頁「刪除所有備註」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除所有備註'**
  String get readerNotesSheetDeleteAllNotesButton;

  /// 劃線與備註合併清單中，純備註項目（無對應劃線）的項目標題
  ///
  /// In zh_TW, this message translates to:
  /// **'備註'**
  String get readerNotesSheetNoteLabel;

  /// 劃線清單項目標題：黃色螢光筆樣式
  ///
  /// In zh_TW, this message translates to:
  /// **'螢光筆（黃）'**
  String get readerHighlightStyleYellow;

  /// 劃線清單項目標題：粉色螢光筆樣式
  ///
  /// In zh_TW, this message translates to:
  /// **'螢光筆（粉）'**
  String get readerHighlightStylePink;

  /// 劃線清單項目標題：藍色螢光筆樣式
  ///
  /// In zh_TW, this message translates to:
  /// **'螢光筆（藍）'**
  String get readerHighlightStyleBlue;

  /// 劃線清單項目標題：底線樣式
  ///
  /// In zh_TW, this message translates to:
  /// **'底線'**
  String get readerHighlightStyleUnderline;

  /// 刪除全部劃線確認對話框標題，{count} 為目前劃線總數
  ///
  /// In zh_TW, this message translates to:
  /// **'確定要刪除全部劃線嗎？（共 {count} 筆）'**
  String readerNotesSheetDeleteAllHighlightsConfirm(int count);

  /// 刪除全部備註確認對話框標題，{count} 為目前備註總數
  ///
  /// In zh_TW, this message translates to:
  /// **'確定要刪除全部備註嗎？（共 {count} 筆）'**
  String readerNotesSheetDeleteAllNotesConfirm(int count);

  /// FXL（固定版面）版面設定 Bottom Sheet 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'⚙️ 漫畫版面設定'**
  String get readerFxlSettingsTitle;

  /// 雙頁模式選項群組的小標題，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'雙頁模式'**
  String get readerDualPageModeLabel;

  /// 雙頁模式「自動」選項 tooltip，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'自動（橫向雙頁）'**
  String get readerDualPageAutoTooltip;

  /// 雙頁模式「自動」選項短標籤，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'自動'**
  String get readerDualPageAutoLabel;

  /// 雙頁模式「永遠雙頁」選項 tooltip，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'永遠雙頁'**
  String get readerDualPageAlwaysTooltip;

  /// 雙頁模式「永遠雙頁」選項短標籤，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'雙頁'**
  String get readerDualPageAlwaysLabel;

  /// 雙頁模式「永遠單頁」選項 tooltip，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'永遠單頁'**
  String get readerDualPageNeverTooltip;

  /// 雙頁模式「永遠單頁」選項短標籤，fxl_settings_sheet.dart／pdf_settings_sheet.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'單頁'**
  String get readerDualPageNeverLabel;

  /// fxl_settings_sheet.dart 翻頁方向選項群組的小標題
  ///
  /// In zh_TW, this message translates to:
  /// **'翻頁方向'**
  String get readerPageDirectionLabel;

  /// fxl_settings_sheet.dart 翻頁方向「左到右」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'左到右（LTR，美漫慣例）'**
  String get readerDualPageDirectionLtrTooltip;

  /// fxl_settings_sheet.dart 翻頁方向「左到右」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'左翻'**
  String get readerDualPageDirectionLtrLabel;

  /// fxl_settings_sheet.dart 翻頁方向「右到左」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'右到左（RTL，日漫慣例）'**
  String get readerDualPageDirectionRtlTooltip;

  /// fxl_settings_sheet.dart 翻頁方向「右到左」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'右翻'**
  String get readerDualPageDirectionRtlLabel;

  /// 簡繁轉換覆寫選項群組的小標題，fxl_settings_sheet.dart／reader_settings_sheet.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'簡繁轉換覆寫'**
  String get readerTextConversionOverrideLabel;

  /// 「使用全域預設」選項的短標籤，簡繁轉換覆寫／翻頁模式覆寫／螢幕方向覆寫共用
  ///
  /// In zh_TW, this message translates to:
  /// **'全域'**
  String get readerGlobalLabel;

  /// 「使用全域預設」選項的 tooltip，簡繁轉換覆寫／翻頁模式覆寫／螢幕方向覆寫共用
  ///
  /// In zh_TW, this message translates to:
  /// **'使用全域預設'**
  String get readerUseGlobalDefaultTooltip;

  /// 簡繁轉換覆寫「原文」選項的標籤與 tooltip（兩者文字相同，共用一個 key）
  ///
  /// In zh_TW, this message translates to:
  /// **'原文'**
  String get readerTextConversionOriginalLabel;

  /// 簡繁轉換覆寫「繁體」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'繁體'**
  String get readerTextConversionTraditionalLabel;

  /// 簡繁轉換覆寫「繁體」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'轉換為繁體'**
  String get readerTextConversionTraditionalTooltip;

  /// 簡繁轉換覆寫「簡體」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'簡體'**
  String get readerTextConversionSimplifiedLabel;

  /// 簡繁轉換覆寫「簡體」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'轉換為簡體'**
  String get readerTextConversionSimplifiedTooltip;

  /// 全螢幕模式開關標題，fxl_settings_sheet.dart／pdf_settings_sheet.dart／reader_settings_sheet.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'全螢幕模式'**
  String get readerFullscreenModeLabel;

  /// 顯示頁首開關標題，fxl_settings_sheet.dart／reader_settings_sheet.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'顯示頁首'**
  String get readerShowHeaderLabel;

  /// 顯示頁尾開關標題，fxl_settings_sheet.dart／pdf_settings_sheet.dart／reader_settings_sheet.dart 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'顯示頁尾'**
  String get readerShowFooterLabel;

  /// PDF 版面設定 Bottom Sheet 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'⚙️ PDF 版面設定'**
  String get readerPdfSettingsTitle;

  /// PDF 版面設定第一個分頁籤：顯示
  ///
  /// In zh_TW, this message translates to:
  /// **'顯示'**
  String get readerPdfSettingsTabDisplay;

  /// PDF 版面設定第二個分頁籤：濾鏡
  ///
  /// In zh_TW, this message translates to:
  /// **'濾鏡'**
  String get readerPdfSettingsTabFilters;

  /// PDF 版面設定第三個分頁籤：裁切
  ///
  /// In zh_TW, this message translates to:
  /// **'裁切'**
  String get readerPdfSettingsTabCrop;

  /// PDF 顯示分頁「Fit 模式」選項群組小標題
  ///
  /// In zh_TW, this message translates to:
  /// **'Fit 模式'**
  String get readerPdfFitModeLabel;

  /// PDF Fit 模式「整頁」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'Page-fit（整頁）'**
  String get readerPdfFitPageTooltip;

  /// PDF Fit 模式「整頁」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'整頁'**
  String get readerPdfFitPageLabel;

  /// PDF Fit 模式「頁寬」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'Fit Width（頁寬）'**
  String get readerPdfFitWidthTooltip;

  /// PDF Fit 模式「頁寬」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'頁寬'**
  String get readerPdfFitWidthLabel;

  /// PDF Fit 模式「原比」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'真實比例 1:1'**
  String get readerPdfFitActualTooltip;

  /// PDF Fit 模式「原比」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'原比'**
  String get readerPdfFitActualLabel;

  /// PDF 雙頁模式「封面獨立顯示」開關標題
  ///
  /// In zh_TW, this message translates to:
  /// **'封面獨立顯示'**
  String get readerPdfDualPageCoverAloneLabel;

  /// PDF 顯示分頁「頁面方向」選項群組小標題
  ///
  /// In zh_TW, this message translates to:
  /// **'頁面方向'**
  String get readerPdfPageOrientationLabel;

  /// PDF 頁面方向「左到右」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'左到右'**
  String get readerPdfDirectionLtrTooltip;

  /// PDF 頁面方向「左到右」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'左翻'**
  String get readerPdfDirectionLtrLabel;

  /// PDF 頁面方向「右到左」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'右到左（日漫慣例）'**
  String get readerPdfDirectionRtlTooltip;

  /// PDF 頁面方向「右到左」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'右翻'**
  String get readerPdfDirectionRtlLabel;

  /// PDF 顯示分頁「翻頁模式」（逐頁／連續捲動）選項群組小標題
  ///
  /// In zh_TW, this message translates to:
  /// **'翻頁模式'**
  String get readerPdfPageTurnModeLabel;

  /// PDF 翻頁模式「逐頁」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'逐頁：一次只顯示一頁，換頁瞬間切換'**
  String get readerPdfPageTurnModePaginatedTooltip;

  /// PDF 翻頁模式「逐頁」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'逐頁'**
  String get readerPdfPageTurnModePaginatedLabel;

  /// PDF 翻頁模式「連續捲動」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'連續捲動：頁面上下相連，可自由捲動'**
  String get readerPdfPageTurnModeScrollTooltip;

  /// PDF 翻頁模式「連續捲動」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'連續捲動'**
  String get readerPdfPageTurnModeScrollLabel;

  /// PDF 顯示分頁「換頁動畫」選項群組小標題
  ///
  /// In zh_TW, this message translates to:
  /// **'換頁動畫'**
  String get readerPdfPageTurnAnimationLabel;

  /// 換頁動畫「滑動」選項標籤與 tooltip（文字相同）
  ///
  /// In zh_TW, this message translates to:
  /// **'滑動'**
  String get readerPdfPageTurnAnimationSlide;

  /// 換頁動畫「無」選項標籤與 tooltip（文字相同）
  ///
  /// In zh_TW, this message translates to:
  /// **'無'**
  String get readerPdfPageTurnAnimationNone;

  /// PDF 濾鏡分頁「對比度」滑桿標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'對比度'**
  String get readerPdfContrastLabel;

  /// PDF 濾鏡分頁「亮度」滑桿標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'亮度'**
  String get readerPdfBrightnessLabel;

  /// PDF 濾鏡分頁「加粗強度」滑桿標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'加粗強度'**
  String get readerPdfBoldStrengthLabel;

  /// PDF 裁切分頁「裁切模式」選項群組小標題
  ///
  /// In zh_TW, this message translates to:
  /// **'裁切模式'**
  String get readerPdfCropModeLabel;

  /// 裁切模式「不裁切」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'不裁切'**
  String get readerPdfCropNoneTooltip;

  /// 裁切模式「不裁切」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'不裁'**
  String get readerPdfCropNoneLabel;

  /// 裁切模式「智慧自動」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'智慧自動'**
  String get readerPdfCropAutoTooltip;

  /// 裁切模式「智慧自動」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'智慧'**
  String get readerPdfCropAutoLabel;

  /// 裁切模式「手動」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'手動'**
  String get readerPdfCropManualLabel;

  /// 裁切模式「手動」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'手動選區'**
  String get readerPdfCropManualTooltip;

  /// 手動裁切編輯模式尚未畫框時的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'拖拉選取要保留的範圍'**
  String get readerPdfCropDragHint;

  /// EPUB 版面設定 Bottom Sheet 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'⚙️ 版面設定'**
  String get readerSettingsTitle;

  /// 版面設定第一個分頁籤：文字
  ///
  /// In zh_TW, this message translates to:
  /// **'文字'**
  String get readerSettingsTabText;

  /// 版面設定第二個分頁籤：邊界
  ///
  /// In zh_TW, this message translates to:
  /// **'邊界'**
  String get readerSettingsTabBoundary;

  /// 版面設定第三個分頁籤：呈現
  ///
  /// In zh_TW, this message translates to:
  /// **'呈現'**
  String get readerSettingsTabPresentation;

  /// 版面設定第四個分頁籤：預設集
  ///
  /// In zh_TW, this message translates to:
  /// **'預設集'**
  String get readerSettingsTabPreferences;

  /// 文字分頁「字級」滑桿標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'字級'**
  String get readerSettingsFontSizeLabel;

  /// 文字分頁「字重」滑桿標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'字重'**
  String get readerSettingsFontWeightLabel;

  /// 文字分頁「行距」滑桿標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'行距'**
  String get readerSettingsLineHeightLabel;

  /// 文字分頁「段落間距」滑桿標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'段落間距'**
  String get readerSettingsParagraphSpacingLabel;

  /// 文字分頁「字距」滑桿標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'字距'**
  String get readerSettingsLetterSpacingLabel;

  /// 文字分頁「停用書本 CSS」開關標題
  ///
  /// In zh_TW, this message translates to:
  /// **'停用書本 CSS'**
  String get readerSettingsDisableBookCssLabel;

  /// 邊界分頁「上邊界」滑桿標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'上邊界'**
  String get readerSettingsMarginTopLabel;

  /// 邊界分頁「下邊界」滑桿標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'下邊界'**
  String get readerSettingsMarginBottomLabel;

  /// 邊界分頁「左邊界」滑桿標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'左邊界'**
  String get readerSettingsMarginLeftLabel;

  /// 邊界分頁「右邊界」滑桿標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'右邊界'**
  String get readerSettingsMarginRightLabel;

  /// 數值型設定已對本書覆寫時顯示的徽章文字
  ///
  /// In zh_TW, this message translates to:
  /// **'此書已覆寫'**
  String get readerSettingsOverriddenBadge;

  /// 已覆寫欄位旁「恢復本書原樣式」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'恢復本書原樣式'**
  String get readerSettingsResetToBookStyleTooltip;

  /// 未覆寫欄位「使用全域預設」徽章的 Tooltip 說明文字
  ///
  /// In zh_TW, this message translates to:
  /// **'跟隨本書原樣式，尚未調整'**
  String get readerSettingsNotOverriddenTooltip;

  /// 字型下拉選單「使用書本內建字型」選項（不指定自訂字型）
  ///
  /// In zh_TW, this message translates to:
  /// **'使用書本內建字型'**
  String get readerSettingsUseBookFontLabel;

  /// 版面設定「文字」分頁中字型下拉選單左側的標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'字型'**
  String get readerSettingsFontFamilyLabel;

  /// 閱讀設定字型下拉選單下方的提示：一款內建字型都還沒下載時顯示（epic-49）
  ///
  /// In zh_TW, this message translates to:
  /// **'到「字型管理」下載更多字型'**
  String get readerSettingsDownloadMoreFontsHint;

  /// 呈現分頁「欄數」選項群組小標題
  ///
  /// In zh_TW, this message translates to:
  /// **'欄數'**
  String get readerSettingsColumnCountLabel;

  /// 欄數「自動」選項標籤與 tooltip（文字相同）
  ///
  /// In zh_TW, this message translates to:
  /// **'自動'**
  String get readerSettingsColumnAutoLabel;

  /// 欄數「單欄」選項標籤與 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'單欄'**
  String get readerSettingsColumnSingleLabel;

  /// 欄數「雙欄」選項標籤與 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'雙欄'**
  String get readerSettingsColumnDoubleLabel;

  /// E-Ink 模式下欄位大小標題（不含數值，避免與 EBStepper 內顯示的數值重複）
  ///
  /// In zh_TW, this message translates to:
  /// **'欄位大小'**
  String get readerSettingsColumnSizeLabel;

  /// 一般主題下欄位大小標題（含目前數值），{size} 為像素數
  ///
  /// In zh_TW, this message translates to:
  /// **'欄位大小 {size}px'**
  String readerSettingsColumnSizeWithValueLabel(int size);

  /// 呈現分頁「文字對齊」選項群組小標題
  ///
  /// In zh_TW, this message translates to:
  /// **'文字對齊'**
  String get readerSettingsTextAlignLabel;

  /// 文字對齊「置中」選項標籤與 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'置中'**
  String get readerSettingsTextAlignCenterLabel;

  /// 文字對齊「齊行」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'左右對齊'**
  String get readerSettingsTextAlignJustifyTooltip;

  /// 文字對齊「齊行」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'齊行'**
  String get readerSettingsTextAlignJustifyLabel;

  /// 文字對齊「起始」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'起始邊對齊'**
  String get readerSettingsTextAlignStartTooltip;

  /// 文字對齊「起始」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'起始'**
  String get readerSettingsTextAlignStartLabel;

  /// 文字對齊「結尾」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'結尾邊對齊'**
  String get readerSettingsTextAlignEndTooltip;

  /// 文字對齊「結尾」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'結尾'**
  String get readerSettingsTextAlignEndLabel;

  /// 文字對齊「靠左」選項標籤與 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'靠左'**
  String get readerSettingsTextAlignLeftLabel;

  /// 文字對齊「靠右」選項標籤與 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'靠右'**
  String get readerSettingsTextAlignRightLabel;

  /// 呈現分頁「排版方向模式」選項群組小標題
  ///
  /// In zh_TW, this message translates to:
  /// **'排版方向模式'**
  String get readerSettingsWritingModeLabel;

  /// 排版方向「採用書籍排版」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'採用書籍排版'**
  String get readerSettingsWritingModeBookTooltip;

  /// 排版方向「採用書籍排版」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'書籍'**
  String get readerSettingsWritingModeBookLabel;

  /// 排版方向「強制直排」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'強制直排'**
  String get readerSettingsWritingModeVerticalTooltip;

  /// 排版方向「強制直排」選項短標籤，亦供預設集摘要文字重用
  ///
  /// In zh_TW, this message translates to:
  /// **'直排'**
  String get readerSettingsWritingModeVerticalLabel;

  /// 排版方向「強制橫排」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'強制橫排'**
  String get readerSettingsWritingModeHorizontalTooltip;

  /// 排版方向「強制橫排」選項短標籤，亦供預設集摘要文字重用
  ///
  /// In zh_TW, this message translates to:
  /// **'橫排'**
  String get readerSettingsWritingModeHorizontalLabel;

  /// 呈現分頁「翻頁模式覆寫」選項群組小標題
  ///
  /// In zh_TW, this message translates to:
  /// **'翻頁模式覆寫'**
  String get readerSettingsPageTurnModeLabel;

  /// 翻頁模式「點擊翻頁」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'點擊翻頁'**
  String get readerSettingsPageTurnPaginatedTooltip;

  /// 翻頁模式「點擊翻頁」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'點擊'**
  String get readerSettingsPageTurnPaginatedLabel;

  /// 翻頁模式「滾動翻頁」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'滾動翻頁'**
  String get readerSettingsPageTurnScrollTooltip;

  /// 翻頁模式「滾動翻頁」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'滾動'**
  String get readerSettingsPageTurnScrollLabel;

  /// 呈現分頁「螢幕方向鎖定覆寫」選項群組小標題
  ///
  /// In zh_TW, this message translates to:
  /// **'螢幕方向鎖定覆寫'**
  String get readerSettingsScreenOrientationLabel;

  /// 螢幕方向「自動旋轉」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'自動旋轉'**
  String get readerSettingsOrientationAutoTooltip;

  /// 螢幕方向「自動旋轉」選項短標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'自動'**
  String get readerSettingsOrientationAutoLabel;

  /// 螢幕方向「鎖定 0°」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'鎖定 0°'**
  String get readerSettingsOrientationLock0Tooltip;

  /// 螢幕方向「鎖定 90°」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'鎖定 90°'**
  String get readerSettingsOrientationLock90Tooltip;

  /// 螢幕方向「鎖定 180°」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'鎖定 180°'**
  String get readerSettingsOrientationLock180Tooltip;

  /// 螢幕方向「鎖定 270°」選項 tooltip
  ///
  /// In zh_TW, this message translates to:
  /// **'鎖定 270°'**
  String get readerSettingsOrientationLock270Tooltip;

  /// 預設集分頁「另存為新預設集」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'將目前設定存為新預設集'**
  String get readerSettingsSaveAsPresetButton;

  /// 預設集分頁「已儲存的預設集」區塊標題
  ///
  /// In zh_TW, this message translates to:
  /// **'已儲存的預設集'**
  String get readerSettingsSavedPresetsLabel;

  /// 預設集分頁「從其他書籍複製」區塊標題
  ///
  /// In zh_TW, this message translates to:
  /// **'從其他書籍複製'**
  String get readerSettingsCopyFromBookLabel;

  /// 「複製到本書」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'複製到本書'**
  String get readerSettingsCopyToCurrentBookButton;

  /// 「複製到其他書籍」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'複製到其他書籍'**
  String get readerSettingsCopyToOtherBooksButton;

  /// 固定列（重設為本書原樣式）的標題
  ///
  /// In zh_TW, this message translates to:
  /// **'系統預設'**
  String get readerSettingsResetPresetTitle;

  /// 固定列（重設為本書原樣式）的副標題說明
  ///
  /// In zh_TW, this message translates to:
  /// **'移除本書所有字級/字重/行距/段落間距/字距覆寫，改用書本原始樣式'**
  String get readerSettingsResetPresetSubtitle;

  /// 預設集卡片列「套用」按鈕文字，固定列與各 preset slot 共用
  ///
  /// In zh_TW, this message translates to:
  /// **'套用'**
  String get readerSettingsApplyButton;

  /// 預設集摘要文字中，欄位未收錄時的回退顯示（例如字級/行距缺席）
  ///
  /// In zh_TW, this message translates to:
  /// **'預設'**
  String get readerSettingsPresetDefaultValue;

  /// 預設集摘要文字中，排版方向欄位為 null（自動偵測）時的顯示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'自動'**
  String get readerSettingsPresetSummaryAutoLabel;

  /// 預設集卡片副標題摘要格式，三個 placeholder 皆為已格式化完成的字串（含 readerSettingsPresetDefaultValue／readerSettingsPresetSummaryAutoLabel 等回退值）
  ///
  /// In zh_TW, this message translates to:
  /// **'字級{fontSize}・行距{lineHeight}・{writingMode}'**
  String readerSettingsPresetSummaryFormat(
    String fontSize,
    String lineHeight,
    String writingMode,
  );

  /// 預設集尚未使用的空 slot 顯示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'（空）'**
  String get readerSettingsPresetEmptySlot;

  /// 預設集卡片列「套用到其他書籍」圖示按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'套用到其他書籍'**
  String get readerSettingsApplyToOtherBooksTooltip;

  /// 預設集卡片列「刪除」圖示按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除'**
  String get readerSettingsDeletePresetTooltip;

  /// ReaderScreen.bookTitle 未提供（僅測試直接建構時可能發生，正式生產路徑必定提供書名）時的回退顯示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'未知書籍'**
  String get readerUnknownBookTitle;

  /// 另存為新預設集過程發生例外時顯示的固定 SnackBar 訊息（不含例外原始文字，技術細節已由呼叫端 debugPrint() 記錄，見 epic-45-interface-i18n Issue 7）
  ///
  /// In zh_TW, this message translates to:
  /// **'另存為新預設集失敗'**
  String get readerSaveAsPresetFailedMessage;

  /// 已存滿 3 組預設集時，選擇要覆蓋哪一組的對話框標題
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇要覆蓋的預設集'**
  String get readerOverwritePresetPickerTitle;

  /// 覆蓋預設集選單的單一選項文字，{name} 為預設集名稱，{date} 為已依 DateFormat.yMd() 格式化的最後更新日期字串
  ///
  /// In zh_TW, this message translates to:
  /// **'{name}（最後更新：{date}）'**
  String readerOverwritePresetOptionLabel(String name, String date);

  /// 覆蓋預設集二次確認對話框標題與確認按鈕（兩處文字相同，共用一個 key）
  ///
  /// In zh_TW, this message translates to:
  /// **'確認覆蓋'**
  String get readerConfirmOverwriteTitle;

  /// 覆蓋預設集二次確認訊息，{name} 為預設集名稱
  ///
  /// In zh_TW, this message translates to:
  /// **'即將覆蓋預設集「{name}」，此動作無法復原。'**
  String readerOverwritePresetConfirmMessage(String name);

  /// 套用版面設定到其他書籍的確認對話框標題與確認按鈕（兩處文字相同，共用一個 key）
  ///
  /// In zh_TW, this message translates to:
  /// **'確認套用'**
  String get readerConfirmApplyTitle;

  /// 套用版面設定到其他書籍的確認訊息，{count} 為目標書籍數
  ///
  /// In zh_TW, this message translates to:
  /// **'{count, plural, =1{即將覆蓋 1 本書的版面設定，此動作無法復原。} other{即將覆蓋 {count} 本書的版面設定，此動作無法復原。}}'**
  String readerApplyToOthersConfirmMessage(int count);

  /// 套用版面設定（來自預設集或來自其他書籍）過程發生例外時顯示的固定 SnackBar 訊息（不含例外原始文字，技術細節已由呼叫端 debugPrint() 記錄，見 epic-45-interface-i18n Issue 7），兩處呼叫端共用
  ///
  /// In zh_TW, this message translates to:
  /// **'套用版面設定失敗'**
  String get readerApplyPresetFailedMessage;

  /// 刪除預設集確認對話框標題與確認按鈕（兩處文字相同，共用一個 key）
  ///
  /// In zh_TW, this message translates to:
  /// **'確認刪除'**
  String get readerConfirmDeleteTitle;

  /// 刪除預設集確認訊息，{name} 為預設集名稱
  ///
  /// In zh_TW, this message translates to:
  /// **'即將刪除預設集「{name}」，此動作無法復原。'**
  String readerDeletePresetConfirmMessage(String name);

  /// 刪除預設集過程發生例外時顯示的固定 SnackBar 訊息（不含例外原始文字，技術細節已由呼叫端 debugPrint() 記錄，見 epic-45-interface-i18n Issue 7）
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除預設集失敗'**
  String get readerDeletePresetFailedMessage;

  /// searchRepository／libraryRepository 未提供或書籍格式無法辨識時，點擊搜尋顯示的 SnackBar 訊息
  ///
  /// In zh_TW, this message translates to:
  /// **'搜尋功能暫時無法使用'**
  String get readerSearchUnavailableMessage;

  /// 開書逾時錯誤畫面顯示的訊息
  ///
  /// In zh_TW, this message translates to:
  /// **'開書逾時，可能是系統 WebView 版本過舊或檔案異常'**
  String get readerOpenBookTimeoutMessage;

  /// 選字工具列「複製」按鈕點擊後的 SnackBar 提示
  ///
  /// In zh_TW, this message translates to:
  /// **'已複製到剪貼簿'**
  String get readerCopiedToClipboardMessage;

  /// TTS 選擇語音選單的標題列文字
  ///
  /// In zh_TW, this message translates to:
  /// **'朗讀語音'**
  String get readerTtsVoicePickerTitle;

  /// 書籍格式無法辨識（BookFormat.unknown）時的畫面中央提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'不支援的檔案格式'**
  String get readerUnsupportedFormatMessage;

  /// 開書失敗且視圖沒有回報錯誤訊息（OpenBookFailed.viewMessage 為 null）時的回退錯誤文字
  ///
  /// In zh_TW, this message translates to:
  /// **'無法載入書籍'**
  String get readerFailedToLoadBookMessage;

  /// epic-15 Issue 1：開書失敗且存取探測結果為權限已撤銷（SecurityException）時的錯誤說明
  ///
  /// In zh_TW, this message translates to:
  /// **'App 對這個檔案的存取權限已失效，請重新選取檔案。'**
  String get readerStoragePermissionRevokedMessage;

  /// epic-15 Issue 1：開書失敗且存取探測結果為檔案不存在（FileNotFoundException）時的錯誤說明
  ///
  /// In zh_TW, this message translates to:
  /// **'找不到原始檔案，可能已被移動、改名或刪除。請先確認檔案仍在裝置中，再重新選取。'**
  String get readerStorageFileNotFoundMessage;

  /// epic-15 Issue 2：存取權限失效或找不到檔案時，錯誤畫面上重新選取書籍檔案的按鈕
  ///
  /// In zh_TW, this message translates to:
  /// **'重新選取檔案'**
  String get readerStorageRelinkButton;

  /// epic-15 Issue 2：重新選取的檔案格式與原書不同（例如原書 EPUB 卻選了 PDF）時的 SnackBar
  ///
  /// In zh_TW, this message translates to:
  /// **'選取的檔案格式與原書不同'**
  String get readerStorageRelinkFormatMismatch;

  /// epic-15 Issue 2：重新選取的檔案內容指紋與原書不同（選到另一本書）時的 SnackBar
  ///
  /// In zh_TW, this message translates to:
  /// **'選取的檔案與原書內容不同，請選取同一本書'**
  String get readerStorageRelinkContentMismatch;

  /// epic-15 Issue 2：重新選取的檔案已是書庫中另一本書的來源時的 SnackBar
  ///
  /// In zh_TW, this message translates to:
  /// **'這個檔案已經是書庫中的另一本書'**
  String get readerStorageRelinkAlreadyInLibrary;

  /// epic-15 Issue 2：重新連結因讀取或寫入失敗等其他原因失敗時的 SnackBar
  ///
  /// In zh_TW, this message translates to:
  /// **'重新連結失敗，請再試一次'**
  String get readerStorageRelinkFailed;

  /// TTS 睡眠定時器選單的分鐘數選項文字，{minutes} 為分鐘數（固定選項 15/30/45/60，恆大於 1，不需要 ICU plural）
  ///
  /// In zh_TW, this message translates to:
  /// **'{minutes} 分鐘'**
  String readerTtsSleepTimerOptionMinutes(int minutes);

  /// TTS 睡眠定時器選單「不限時」選項文字
  ///
  /// In zh_TW, this message translates to:
  /// **'不限時'**
  String get readerTtsSleepTimerNoLimitLabel;

  /// 設定畫面 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'設定'**
  String get settingsScaffoldTitle;

  /// 設定畫面 AppBar 右上角「書架」導覽按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'書架'**
  String get settingsLibraryTooltip;

  /// 設定畫面 AppBar 右上角「來源」導覽按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'來源'**
  String get settingsSourceTooltip;

  /// 設定畫面「外觀」分區標題
  ///
  /// In zh_TW, this message translates to:
  /// **'外觀'**
  String get settingsAppearanceSectionTitle;

  /// 設定畫面「佈景」項目標題（主題色點選取器入口）
  ///
  /// In zh_TW, this message translates to:
  /// **'佈景'**
  String get settingsThemeLabel;

  /// E-Ink 模式開啟時，「佈景」項目下方顯示的提示文字，說明目前選的是解除 E-Ink 後要恢復的主題
  ///
  /// In zh_TW, this message translates to:
  /// **'這裡選的是關閉 E-Ink 後要恢復的主題'**
  String get settingsThemeLockedHint;

  /// 主題色點的無障礙 Semantics 標籤（一般狀態），{themeName} 為 settingsThemeLight/Dark/Sepia 的已轉譯結果
  ///
  /// In zh_TW, this message translates to:
  /// **'{themeName}佈景'**
  String settingsThemeDotSemanticsLabel(String themeName);

  /// 主題色點的無障礙 Semantics 標籤（E-Ink 鎖定狀態），{themeName} 為該色點對應主題名稱，{currentThemeName} 為目前實際選擇（鎖定後要恢復）的主題名稱
  ///
  /// In zh_TW, this message translates to:
  /// **'{themeName}佈景，已鎖定，這裡選的是關閉 E-Ink 後要恢復的主題，目前選擇：{currentThemeName}'**
  String settingsThemeDotLockedSemanticsLabel(
    String themeName,
    String currentThemeName,
  );

  /// 淺色主題的顯示名稱
  ///
  /// In zh_TW, this message translates to:
  /// **'淺色'**
  String get settingsThemeLight;

  /// 深色主題的顯示名稱
  ///
  /// In zh_TW, this message translates to:
  /// **'深色'**
  String get settingsThemeDark;

  /// 羊皮紙主題的顯示名稱
  ///
  /// In zh_TW, this message translates to:
  /// **'羊皮紙'**
  String get settingsThemeSepia;

  /// 設定畫面「E-Ink 高對比模式」開關標題
  ///
  /// In zh_TW, this message translates to:
  /// **'E-Ink 高對比模式'**
  String get settingsEinkModeLabel;

  /// 設定畫面「E-Ink 高對比模式」開關的說明文字
  ///
  /// In zh_TW, this message translates to:
  /// **'停用動畫與漸層，以純黑白高對比顯示，專為電子紙螢幕最佳化'**
  String get settingsEinkModeSubtitle;

  /// 設定畫面「字型管理」項目標題，同時是 FontManagementScreen 的 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'字型管理'**
  String get settingsFontManagementLabel;

  /// 設定畫面「閱讀」分區標題
  ///
  /// In zh_TW, this message translates to:
  /// **'閱讀'**
  String get settingsReadingSectionTitle;

  /// 設定畫面「閱讀預設值」項目標題，同時是 ReadingDefaultsScreen 的 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'閱讀預設值'**
  String get settingsReadingDefaultsLabel;

  /// 設定畫面「導航熱區」項目標題，同時是 NavZoneSettingsScreen 的 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'導航熱區'**
  String get settingsNavZoneLabel;

  /// 設定畫面「朗讀語音與語速」項目標題，同時是 TtsDefaultsScreen 的 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'朗讀語音與語速'**
  String get settingsTtsDefaultsLabel;

  /// 裝置不支援全文檢索時顯示的卡片標題
  ///
  /// In zh_TW, this message translates to:
  /// **'全文檢索'**
  String get settingsFullTextSearchUnavailableLabel;

  /// 裝置不支援全文檢索時顯示的卡片說明文字
  ///
  /// In zh_TW, this message translates to:
  /// **'本裝置不支援全文檢索'**
  String get settingsFullTextSearchUnavailableSubtitle;

  /// PDF 全文檢索開關卡片標題
  ///
  /// In zh_TW, this message translates to:
  /// **'PDF 全文檢索'**
  String get settingsFullTextSearchPdfLabel;

  /// PDF 全文檢索開關卡片說明文字
  ///
  /// In zh_TW, this message translates to:
  /// **'部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容'**
  String get settingsFullTextSearchPdfSubtitle;

  /// PDF／其他格式全文檢索卡片「重建索引」按鈕的無障礙提示文字（兩處共用同一 key）
  ///
  /// In zh_TW, this message translates to:
  /// **'重建索引'**
  String get settingsFullTextSearchRebuildIndexTooltip;

  /// EPUB／TXT／KF8 等格式全文檢索開關卡片標題
  ///
  /// In zh_TW, this message translates to:
  /// **'其他格式全文檢索'**
  String get settingsFullTextSearchFoliateLabel;

  /// EPUB／TXT／KF8 等格式全文檢索開關卡片說明文字
  ///
  /// In zh_TW, this message translates to:
  /// **'EPUB／TXT／KF8 等格式的背景索引建置'**
  String get settingsFullTextSearchFoliateSubtitle;

  /// 設定畫面「同步與帳號」分區標題
  ///
  /// In zh_TW, this message translates to:
  /// **'同步與帳號'**
  String get settingsSyncAccountSectionTitle;

  /// 設定畫面「同步」項目標題
  ///
  /// In zh_TW, this message translates to:
  /// **'同步'**
  String get settingsSyncLabel;

  /// 設定畫面「已連結的雲端匯入帳戶」項目標題，同時是 CloudAccountSettingsScreen 的 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'已連結的雲端匯入帳戶'**
  String get settingsCloudAccountLabel;

  /// 設定畫面「關於」分區標題
  ///
  /// In zh_TW, this message translates to:
  /// **'關於'**
  String get settingsAboutSectionTitle;

  /// 設定畫面「關於」項目標題（與分區標題文字相同，共用一個 key）
  ///
  /// In zh_TW, this message translates to:
  /// **'關於'**
  String get settingsAboutLabel;

  /// 設定畫面「閱讀器 Console Log」項目標題，同時是 ReaderConsoleLogScreen 的 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'閱讀器 Console Log'**
  String get settingsReaderConsoleLogLabel;

  /// 設定畫面「Console Log 攔截」開關標題
  ///
  /// In zh_TW, this message translates to:
  /// **'Console Log 攔截'**
  String get settingsConsoleLogInterceptLabel;

  /// 設定畫面「Console Log 攔截」開關的說明文字
  ///
  /// In zh_TW, this message translates to:
  /// **'關閉後僅保留錯誤訊息，用於問題回報時的診斷紀錄'**
  String get settingsConsoleLogInterceptSubtitle;

  /// 導航熱區設定畫面 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'導航熱區'**
  String get navZoneSettingsTitle;

  /// 導航熱區設定畫面「翻頁方式」（簡單/自訂模板切換）區塊標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'翻頁方式'**
  String get navZoneSettingsPageTurnModeLabel;

  /// 翻頁方式切換鈕「簡單」選項文字（三選一固定模板）
  ///
  /// In zh_TW, this message translates to:
  /// **'簡單'**
  String get navZoneSettingsSimpleModeLabel;

  /// 翻頁方式切換鈕「自訂」選項文字（9 格自由編輯器）
  ///
  /// In zh_TW, this message translates to:
  /// **'自訂'**
  String get navZoneSettingsCustomModeLabel;

  /// 「顯示熱區輔助線」開關標題
  ///
  /// In zh_TW, this message translates to:
  /// **'顯示熱區輔助線'**
  String get navZoneSettingsShowDebugOverlayLabel;

  /// 自訂熱區編輯器「儲存自訂熱區設定」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存自訂熱區設定'**
  String get navZoneSettingsSaveCustomButton;

  /// 自訂熱區九宮格「上一頁」動作的格內文字
  ///
  /// In zh_TW, this message translates to:
  /// **'上一頁'**
  String get navZoneActionPreviousPage;

  /// 自訂熱區九宮格「下一頁」動作的格內文字
  ///
  /// In zh_TW, this message translates to:
  /// **'下一頁'**
  String get navZoneActionNextPage;

  /// 自訂熱區九宮格「選單」動作的格內文字
  ///
  /// In zh_TW, this message translates to:
  /// **'選單'**
  String get navZoneActionMenu;

  /// 自訂熱區九宮格「無動作」動作的格內文字
  ///
  /// In zh_TW, this message translates to:
  /// **'無動作'**
  String get navZoneActionNone;

  /// 自訂熱區儲存時驗證失敗（沒有任何格子設為選單）的錯誤提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'至少需要 1 格設為「選單」，否則將無法退出沉浸模式'**
  String get navZoneCustomValidationError;

  /// 閱讀預設值畫面 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'閱讀預設值'**
  String get readingDefaultsTitle;

  /// 「音量鍵翻頁」開關標題
  ///
  /// In zh_TW, this message translates to:
  /// **'音量鍵翻頁'**
  String get readingDefaultsVolumeKeyLabel;

  /// 「翻頁模式」（點擊/滾動）區塊標題
  ///
  /// In zh_TW, this message translates to:
  /// **'翻頁模式'**
  String get readingDefaultsPageTurnModeSectionTitle;

  /// 翻頁模式選項：點擊翻頁
  ///
  /// In zh_TW, this message translates to:
  /// **'點擊翻頁'**
  String get readingDefaultsPaginatedLabel;

  /// 翻頁模式選項：滾動翻頁
  ///
  /// In zh_TW, this message translates to:
  /// **'滾動翻頁'**
  String get readingDefaultsScrollLabel;

  /// 「螢幕方向」區塊標題
  ///
  /// In zh_TW, this message translates to:
  /// **'螢幕方向'**
  String get readingDefaultsScreenOrientationSectionTitle;

  /// 螢幕方向選項：自動旋轉
  ///
  /// In zh_TW, this message translates to:
  /// **'自動旋轉'**
  String get readingDefaultsOrientationAutoLabel;

  /// 螢幕方向選項：鎖定 0 度
  ///
  /// In zh_TW, this message translates to:
  /// **'鎖定 0°'**
  String get readingDefaultsOrientationLock0Label;

  /// 螢幕方向選項：鎖定 90 度
  ///
  /// In zh_TW, this message translates to:
  /// **'鎖定 90°'**
  String get readingDefaultsOrientationLock90Label;

  /// 螢幕方向選項：鎖定 180 度
  ///
  /// In zh_TW, this message translates to:
  /// **'鎖定 180°'**
  String get readingDefaultsOrientationLock180Label;

  /// 螢幕方向選項：鎖定 270 度
  ///
  /// In zh_TW, this message translates to:
  /// **'鎖定 270°'**
  String get readingDefaultsOrientationLock270Label;

  /// 「簡繁轉換顯示」區塊標題
  ///
  /// In zh_TW, this message translates to:
  /// **'簡繁轉換顯示'**
  String get readingDefaultsTextConversionSectionTitle;

  /// 簡繁轉換選項：原文（不轉換）
  ///
  /// In zh_TW, this message translates to:
  /// **'原文'**
  String get readingDefaultsTextConversionOriginalLabel;

  /// 簡繁轉換選項：轉換為繁體
  ///
  /// In zh_TW, this message translates to:
  /// **'轉換為繁體'**
  String get readingDefaultsTextConversionTraditionalLabel;

  /// 簡繁轉換選項：轉換為簡體
  ///
  /// In zh_TW, this message translates to:
  /// **'轉換為簡體'**
  String get readingDefaultsTextConversionSimplifiedLabel;

  /// 「全螢幕模式」開關標題
  ///
  /// In zh_TW, this message translates to:
  /// **'全螢幕模式'**
  String get readingDefaultsFullscreenLabel;

  /// 「啟動時開啟最後閱讀的那本書」開關標題
  ///
  /// In zh_TW, this message translates to:
  /// **'啟動時開啟最後閱讀的那本書'**
  String get readingDefaultsOpenLastBookLabel;

  /// 「顯示頁首」開關標題
  ///
  /// In zh_TW, this message translates to:
  /// **'顯示頁首'**
  String get readingDefaultsShowHeaderLabel;

  /// 「顯示頁尾」開關標題
  ///
  /// In zh_TW, this message translates to:
  /// **'顯示頁尾'**
  String get readingDefaultsShowFooterLabel;

  /// 朗讀預設值畫面 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'朗讀語音與語速'**
  String get ttsDefaultsTitle;

  /// 「語音」選擇區塊標題
  ///
  /// In zh_TW, this message translates to:
  /// **'語音'**
  String get ttsDefaultsVoiceSectionTitle;

  /// 裝置沒有可用 TTS 引擎或語音清單為空時顯示的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'目前裝置未安裝或不支援語音選擇'**
  String get ttsDefaultsVoiceUnavailableHint;

  /// 「語速」調整區塊標題
  ///
  /// In zh_TW, this message translates to:
  /// **'語速'**
  String get ttsDefaultsSpeedSectionTitle;

  /// 同步設定畫面 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'同步'**
  String get syncSettingsTitle;

  /// 手動觸發「立即同步」失敗時的 SnackBar 訊息
  ///
  /// In zh_TW, this message translates to:
  /// **'同步失敗，請確認網路連線'**
  String get syncSettingsSyncFailedMessage;

  /// 尚未有任何一次成功同步紀錄時顯示的文字
  ///
  /// In zh_TW, this message translates to:
  /// **'尚未同步過'**
  String get syncSettingsNeverSynced;

  /// 最後同步時間顯示，{formatted} 為已依目前介面語言格式化的日期時間字串（DateFormat.yMd(locale).add_Hm() 的結果）
  ///
  /// In zh_TW, this message translates to:
  /// **'最後同步：{formatted}'**
  String syncSettingsLastSyncedAt(String formatted);

  /// 登入/連線測試失敗時顯示的錯誤文字
  ///
  /// In zh_TW, this message translates to:
  /// **'連線失敗，請確認伺服器網址與帳號密碼是否正確'**
  String get syncSettingsConnectionFailedMessage;

  /// 同步 token 已過期、被自動登出時，登入表單上方顯示的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'登入已過期，請重新輸入密碼登入'**
  String get syncSettingsSessionExpiredMessage;

  /// 自動同步時發現登入已過期，在目前畫面顯示一次的 Toast 提示
  ///
  /// In zh_TW, this message translates to:
  /// **'同步登入已過期，請至「設定 → 同步」重新登入'**
  String get syncSessionExpiredToast;

  /// 已登入狀態顯示目前登入帳號的 email，{email} 為使用者資料不翻譯
  ///
  /// In zh_TW, this message translates to:
  /// **'已登入：{email}'**
  String syncSettingsLoggedInAs(String email);

  /// 「立即同步」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'立即同步'**
  String get syncSettingsManualSyncButton;

  /// 「登出」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'登出'**
  String get syncSettingsLogoutButton;

  /// 伺服器網址輸入欄位標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'伺服器網址'**
  String get syncSettingsServerUrlLabel;

  /// 密碼輸入欄位標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'密碼'**
  String get syncSettingsPasswordLabel;

  /// 密碼欄位「顯示密碼」眼睛圖示按鈕提示文字（目前為隱藏狀態）
  ///
  /// In zh_TW, this message translates to:
  /// **'顯示密碼'**
  String get syncSettingsShowPasswordTooltip;

  /// 密碼欄位「隱藏密碼」眼睛圖示按鈕提示文字（目前為顯示狀態）
  ///
  /// In zh_TW, this message translates to:
  /// **'隱藏密碼'**
  String get syncSettingsHidePasswordTooltip;

  /// 未登入表單「連線／登入」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'連線／登入'**
  String get syncSettingsConnectButton;

  /// 已連結的雲端匯入帳戶畫面 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'已連結的雲端匯入帳戶'**
  String get cloudAccountSettingsTitle;

  /// 雲端服務已連結狀態顯示的帳號 email，{email} 為使用者資料不翻譯
  ///
  /// In zh_TW, this message translates to:
  /// **'已連結：{email}'**
  String cloudAccountSettingsLinkedEmail(String email);

  /// 「解除連結」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'解除連結'**
  String get cloudAccountSettingsUnlinkButton;

  /// 雲端服務尚未連結狀態顯示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'未連結'**
  String get cloudAccountSettingsUnlinkedText;

  /// 「連結」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'連結'**
  String get cloudAccountSettingsLinkButton;

  /// 字型管理畫面 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'字型管理'**
  String get fontManagementTitle;

  /// 內建字型名稱：思源黑體（字型管理清單與閱讀設定的字型下拉選單）
  ///
  /// In zh_TW, this message translates to:
  /// **'思源黑體'**
  String get fontNameSourceHanSans;

  /// 內建字型名稱：思源宋體（字型管理清單與閱讀設定的字型下拉選單）
  ///
  /// In zh_TW, this message translates to:
  /// **'思源宋體'**
  String get fontNameSourceHanSerif;

  /// 內建字型名稱：原俠正楷（字型管理清單與閱讀設定的字型下拉選單，epic-49 Issue 8）
  ///
  /// In zh_TW, this message translates to:
  /// **'原俠正楷'**
  String get fontNameGuanKiapTsingKhai;

  /// 內建字型名稱：台灣圓體（字型管理清單與閱讀設定的字型下拉選單，epic-49 Issue 8）
  ///
  /// In zh_TW, this message translates to:
  /// **'台灣圓體'**
  String get fontNameTaiwanPearl;

  /// 內建字型名稱：源流明體（字型管理清單與閱讀設定的字型下拉選單，epic-49 Issue 8）
  ///
  /// In zh_TW, this message translates to:
  /// **'源流明體'**
  String get fontNameGenRyuMinTW;

  /// 內建字型名稱：白鷺楷（字型管理清單與閱讀設定的字型下拉選單，epic-55 Issue 3）
  ///
  /// In zh_TW, this message translates to:
  /// **'白鷺楷'**
  String get fontNameBailuKai;

  /// 內建字型名稱：獅尾B2加糖宋體（字型管理清單與閱讀設定的字型下拉選單，epic-55 Issue 3）
  ///
  /// In zh_TW, this message translates to:
  /// **'獅尾B2加糖宋體'**
  String get fontNameSweiB2Sugar;

  /// AppBar「上傳字型」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'上傳字型'**
  String get fontManagementUploadTooltip;

  /// 「內建字型」區塊標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'內建字型'**
  String get fontManagementBuiltInSectionLabel;

  /// 「自訂字型」區塊標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'自訂字型'**
  String get fontManagementCustomSectionLabel;

  /// 使用者尚未上傳任何自訂字型時的空狀態提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'尚未上傳任何自訂字型'**
  String get fontManagementNoCustomFontsHint;

  /// 自訂字型項目「重新命名」按鈕的無障礙提示文字，同時是重新命名對話框標題（共用同一 key）
  ///
  /// In zh_TW, this message translates to:
  /// **'重新命名'**
  String get fontManagementRenameTooltip;

  /// 自訂字型項目「刪除」按鈕的無障礙提示文字，同時是刪除確認對話框確認按鈕文字（共用同一 key）
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除'**
  String get fontManagementDeleteTooltip;

  /// 重新命名對話框標題（與 fontManagementRenameTooltip 文字相同，但語意角色不同，各自獨立宣告以便未來調整不互相牽動）
  ///
  /// In zh_TW, this message translates to:
  /// **'重新命名'**
  String get fontManagementRenameDialogTitle;

  /// 刪除自訂字型確認對話框標題，{fontName} 為使用者自訂的字型顯示名稱（不翻譯）
  ///
  /// In zh_TW, this message translates to:
  /// **'確定要刪除「{fontName}」嗎？'**
  String fontManagementDeleteConfirmTitle(String fontName);

  /// 刪除自訂字型時，若有書籍正在使用該字型顯示的警告文字，{usageCount} 為使用中的書籍數
  ///
  /// In zh_TW, this message translates to:
  /// **'{usageCount, plural, =1{目前有 1 本書使用此字型，刪除後將自動改用預設字型} other{目前有 {usageCount} 本書使用此字型，刪除後將自動改用預設字型}}'**
  String fontManagementDeleteConfirmMessage(int usageCount);

  /// 字型管理：內建字型尚未下載的狀態文字，接在檔案大小後面（epic-49）
  ///
  /// In zh_TW, this message translates to:
  /// **'未下載'**
  String get fontManagementStatusNotDownloaded;

  /// 字型管理：內建字型已下載的狀態文字，接在檔案大小後面（epic-49）
  ///
  /// In zh_TW, this message translates to:
  /// **'已下載'**
  String get fontManagementStatusDownloaded;

  /// 字型管理：下載內建字型按鈕的提示文字（epic-49）
  ///
  /// In zh_TW, this message translates to:
  /// **'下載'**
  String get fontManagementDownloadTooltip;

  /// 字型管理：取消進行中下載按鈕的提示文字（epic-49）
  ///
  /// In zh_TW, this message translates to:
  /// **'取消下載'**
  String get fontManagementCancelDownloadTooltip;

  /// 字型管理：下載失敗後重試按鈕的提示文字（epic-49）
  ///
  /// In zh_TW, this message translates to:
  /// **'重試'**
  String get fontManagementRetryTooltip;

  /// 刪除已下載內建字型的確認內文。刻意不沿用自訂字型的 fontManagementDeleteConfirmMessage：可下載字型刪除時不清除書籍偏好（ADR 0035）（epic-49）
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除後可以隨時重新下載。使用這款字型的書會暫時改用書本或系統字型，重新下載後自動恢復。'**
  String get fontManagementDownloadableDeleteConfirmMessage;

  /// 字型管理：系統 WebView 太舊（Chromium 106 以前拒絕超過 30MB 的網頁字型），有內建字型被隱藏時顯示在「內建字型」標題下（epic-49 Issue 7）
  ///
  /// In zh_TW, this message translates to:
  /// **'這台裝置的系統 WebView 版本太舊，部分內建字型無法使用，已從清單隱藏。更新「Android System WebView」並重新開啟 App 後即可下載。'**
  String get fontManagementBuiltInUnsupportedHint;

  /// 字型下載失敗：網路連線失敗或中途斷線（epic-49）
  ///
  /// In zh_TW, this message translates to:
  /// **'無法連線，請檢查網路後重試'**
  String get fontDownloadErrorNetwork;

  /// 字型下載失敗：伺服器回傳非 200 狀態碼，{statusCode} 為 HTTP 狀態碼（epic-49）
  ///
  /// In zh_TW, this message translates to:
  /// **'伺服器錯誤（{statusCode}），請稍後重試'**
  String fontDownloadErrorHttp(int statusCode);

  /// 字型下載失敗：下載內容的 SHA-256 與預期不符（epic-49）
  ///
  /// In zh_TW, this message translates to:
  /// **'檔案不完整或已損毀，請重試'**
  String get fontDownloadErrorIntegrity;

  /// 字型下載失敗：寫入檔案失敗，例如儲存空間不足（epic-49）
  ///
  /// In zh_TW, this message translates to:
  /// **'無法儲存檔案，請確認儲存空間是否足夠'**
  String get fontDownloadErrorStorage;

  /// 批次上傳字型結果訊息：同時有新增與跳過的情境，{addedCount}／{skippedCount} 各自獨立處理單複數
  ///
  /// In zh_TW, this message translates to:
  /// **'{addedCount, plural, =1{已新增 1 款字型} other{已新增 {addedCount} 款字型}}，{skippedCount, plural, =1{1 款已存在已跳過} other{{skippedCount} 款已存在已跳過}}'**
  String fontManagementUploadBothMessage(int addedCount, int skippedCount);

  /// 批次上傳字型結果訊息：全部成功新增、沒有跳過的情境
  ///
  /// In zh_TW, this message translates to:
  /// **'{addedCount, plural, =1{已新增 1 款字型} other{已新增 {addedCount} 款字型}}'**
  String fontManagementUploadAddedOnlyMessage(int addedCount);

  /// 批次上傳字型結果訊息：全部跳過、沒有新增成功的情境
  ///
  /// In zh_TW, this message translates to:
  /// **'{skippedCount, plural, =1{1 款字型已存在，已跳過} other{{skippedCount} 款字型已存在，已跳過}}'**
  String fontManagementUploadSkippedOnlyMessage(int skippedCount);

  /// epic-15 Issue 3：字型管理中，自訂字型檔案讀不到時，列上顯示的文字標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'檔案無法讀取'**
  String get fontManagementFileInaccessibleBadge;

  /// epic-15 Issue 3：字型管理中，檔案讀不到的自訂字型列上的重新連結按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'重新連結字型檔案'**
  String get fontManagementRelinkAction;

  /// epic-15 Issue 3：重新連結時，選取的字型家族名稱與原字型不同而被拒絕的 SnackBar
  ///
  /// In zh_TW, this message translates to:
  /// **'選取的字型與原字型的家族名稱不同'**
  String get fontManagementFamilyMismatchMessage;

  /// 閱讀器 Console Log 畫面 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'閱讀器 Console Log'**
  String get readerConsoleLogTitle;

  /// 「複製全部」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'複製全部'**
  String get readerConsoleLogCopyAllTooltip;

  /// 「清空」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'清空'**
  String get readerConsoleLogClearTooltip;

  /// 沒有任何 Console Log 記錄時的空狀態提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'目前沒有記錄'**
  String get readerConsoleLogEmptyHint;

  /// 點擊「複製全部」後的 SnackBar 提示
  ///
  /// In zh_TW, this message translates to:
  /// **'已複製全部記錄到剪貼簿'**
  String get readerConsoleLogCopiedMessage;

  /// 關於畫面 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'關於'**
  String get aboutScreenTitle;

  /// 「版本」項目標題
  ///
  /// In zh_TW, this message translates to:
  /// **'版本'**
  String get aboutScreenVersionLabel;

  /// 「編譯時間」項目標題
  ///
  /// In zh_TW, this message translates to:
  /// **'編譯時間'**
  String get aboutScreenBuildTimeLabel;

  /// 「系統 WebView 版本」項目標題
  ///
  /// In zh_TW, this message translates to:
  /// **'系統 WebView 版本'**
  String get aboutScreenWebViewVersionLabel;

  /// 「開源授權清單」項目標題（點擊開啟 Flutter 內建授權清單頁）
  ///
  /// In zh_TW, this message translates to:
  /// **'開源授權清單'**
  String get aboutScreenViewLicensesButton;

  /// 授權頁頁首的說明文字（說明下列清單是 App 使用的開源元件）
  ///
  /// In zh_TW, this message translates to:
  /// **'本 App 使用下列開源元件，各元件的版權與授權條款如下。'**
  String get aboutScreenLicensesLegalese;

  /// 版本號/編譯時間/WebView 版本非同步載入完成前的暫時顯示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'讀取中...'**
  String get aboutScreenLoadingText;

  /// PackageInfo.fromPlatform() 呼叫失敗時，版本號欄位顯示的錯誤文字
  ///
  /// In zh_TW, this message translates to:
  /// **'無法取得版本號'**
  String get aboutScreenFailedToLoadVersionMessage;

  /// 編譯時間/WebView 版本呼叫失敗或回傳空值時顯示的通用錯誤文字
  ///
  /// In zh_TW, this message translates to:
  /// **'無法取得'**
  String get aboutScreenUnavailableText;

  /// 遠端書庫站點清單畫面 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'遠端書庫'**
  String get remoteServerListTitle;

  /// AppBar「新增站點」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'新增站點'**
  String get remoteServerListAddTooltip;

  /// 尚未新增任何站點時的空狀態文字
  ///
  /// In zh_TW, this message translates to:
  /// **'尚未新增任何遠端書庫站點'**
  String get remoteServerListEmptyState;

  /// 站點列項目「編輯」圖示按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'編輯'**
  String get remoteServerListEditTooltip;

  /// 站點列項目「刪除」圖示按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除'**
  String get remoteServerListDeleteTooltip;

  /// 刪除站點確認對話框標題
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除站點'**
  String get remoteServerListDeleteConfirmTitle;

  /// 刪除站點確認對話框的動作按鈕文字（審查意見 review-issue-6.md M-1：原與圖示按鈕的無障礙提示 remoteServerListDeleteTooltip 共用同一個 key，拆為獨立 key 避免兩處字義各自演進時互相牽制）
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除'**
  String get remoteServerListDeleteConfirmButton;

  /// 刪除站點確認訊息，{name} 為使用者自訂的站點名稱（不翻譯）
  ///
  /// In zh_TW, this message translates to:
  /// **'確定要刪除站點「{name}」嗎？此動作無法復原。'**
  String remoteServerListDeleteConfirmMessage(String name);

  /// 站點仍有僅雲端紀錄書籍、刪除被擋下時的示警對話框標題
  ///
  /// In zh_TW, this message translates to:
  /// **'無法刪除站點'**
  String get remoteServerListDeleteBlockedTitle;

  /// 刪除被擋下時的示警訊息，{count} 為僅雲端紀錄書籍本數，{titles} 為呼叫端已組好的書名清單文字（每行一本，前綴「．」，不含末尾換行）
  ///
  /// In zh_TW, this message translates to:
  /// **'{count, plural, =1{這個站點還有 1 本書僅有雲端紀錄、尚未下載：} other{這個站點還有 {count} 本書僅有雲端紀錄、尚未下載：}}\n{titles}\n\n請先於書架移除這些書籍，或重新下載後再刪除站點。'**
  String remoteServerListDeleteBlockedMessage(int count, String titles);

  /// 示警對話框的確認按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'了解'**
  String get remoteServerListDeleteBlockedConfirmButton;

  /// 刪除防護例外以外的其餘刪除失敗時顯示的 SnackBar 訊息
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除站點失敗，請稍後再試'**
  String get remoteServerListDeleteFailedMessage;

  /// 新增模式的 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'新增站點'**
  String get remoteServerFormTitleAdd;

  /// 編輯模式的 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'編輯站點'**
  String get remoteServerFormTitleEdit;

  /// 站點名稱輸入框的 labelText
  ///
  /// In zh_TW, this message translates to:
  /// **'站點名稱'**
  String get remoteServerFormNameLabel;

  /// 伺服器網址輸入框的 labelText
  ///
  /// In zh_TW, this message translates to:
  /// **'伺服器網址'**
  String get remoteServerFormBaseUrlLabel;

  /// 伺服器類型下拉選單選項：標準 OPDS
  ///
  /// In zh_TW, this message translates to:
  /// **'標準 OPDS'**
  String get remoteServerFormTypeOpds;

  /// 伺服器類型下拉選單選項：原生 Calibre Content Server
  ///
  /// In zh_TW, this message translates to:
  /// **'原生 Calibre Content Server'**
  String get remoteServerFormTypeCalibreServer;

  /// 帳號輸入框的 labelText
  ///
  /// In zh_TW, this message translates to:
  /// **'帳號（留空代表匿名連線）'**
  String get remoteServerFormUsernameLabel;

  /// 編輯模式下密碼輸入框的 labelText
  ///
  /// In zh_TW, this message translates to:
  /// **'密碼（留空＝沿用既有密碼；清空上方帳號欄位則一併清除密碼）'**
  String get remoteServerFormPasswordLabelEditing;

  /// 新增模式下密碼輸入框的 labelText
  ///
  /// In zh_TW, this message translates to:
  /// **'密碼'**
  String get remoteServerFormPasswordLabel;

  /// 密碼顯示/隱藏切換圖示，目前為隱藏狀態時的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'顯示密碼'**
  String get remoteServerFormPasswordShowTooltip;

  /// 密碼顯示/隱藏切換圖示，目前為顯示狀態時的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'隱藏密碼'**
  String get remoteServerFormPasswordHideTooltip;

  /// 允許不安全連線開關的標題文字
  ///
  /// In zh_TW, this message translates to:
  /// **'允許不安全連線（自簽憑證／純 HTTP）'**
  String get remoteServerFormAllowInsecureLabel;

  /// 站點名稱或網址為空時的驗證錯誤文字
  ///
  /// In zh_TW, this message translates to:
  /// **'請填寫站點名稱與網址'**
  String get remoteServerFormValidationMissingFields;

  /// 網址格式不合法時的驗證錯誤文字
  ///
  /// In zh_TW, this message translates to:
  /// **'請輸入有效的伺服器網址（需以 http:// 或 https:// 開頭）'**
  String get remoteServerFormValidationInvalidUrl;

  /// SQLite／secure storage 寫入失敗時的錯誤文字
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存失敗，請稍後再試'**
  String get remoteServerFormSaveFailedMessage;

  /// 測試連線成功時顯示的文字
  ///
  /// In zh_TW, this message translates to:
  /// **'連線成功'**
  String get remoteServerFormTestSuccess;

  /// 測試連線失敗時顯示的文字
  ///
  /// In zh_TW, this message translates to:
  /// **'連線失敗，請檢查網址/帳密/憑證設定'**
  String get remoteServerFormTestFailed;

  /// 「測試連線」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'測試連線'**
  String get remoteServerFormTestConnectionButton;

  /// 「儲存」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存'**
  String get remoteServerFormSaveButton;

  /// 格式選擇對話框標題，{title} 為書目標題（使用者資料，不翻譯）
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇格式：{title}'**
  String formatSelectionDialogTitle(String title);

  /// 格式選項本身不受支援（format 為 null）時顯示的文字
  ///
  /// In zh_TW, this message translates to:
  /// **'不支援的格式'**
  String get formatSelectionDialogUnsupportedFormat;

  /// 雲端匯入重複匯入確認彈窗標題
  ///
  /// In zh_TW, this message translates to:
  /// **'重複的書籍'**
  String get cloudDuplicateDialogTitle;

  /// 重複匯入確認彈窗的確認按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'仍要建立'**
  String get cloudDuplicateDialogConfirmButton;

  /// 載入 Feed 失敗時的錯誤文字
  ///
  /// In zh_TW, this message translates to:
  /// **'載入失敗，請檢查網路連線或站點設定'**
  String get remoteCatalogLoadFailedMessage;

  /// AppBar「下載已選取」按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'下載已選取'**
  String get remoteCatalogDownloadSelectedTooltip;

  /// 偵測到重複匯入時的確認訊息，{title} 為書目標題（使用者資料，不翻譯）
  ///
  /// In zh_TW, this message translates to:
  /// **'「{title}」之前匯入過了，仍要建立新的一份嗎？'**
  String remoteCatalogDuplicateConfirmMessage(String title);

  /// 開始下載後的 SnackBar 訊息，{count} 為加入佇列的檔案數
  ///
  /// In zh_TW, this message translates to:
  /// **'已加入下載佇列（{count, plural, =1{1 個檔案} other{{count} 個檔案}}），可至「來源」畫面查看進度'**
  String remoteCatalogQueuedMessage(int count);

  /// E-Ink 離散換頁模式的「上一頁」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'上一頁'**
  String get remoteCatalogEinkPrevPageButton;

  /// E-Ink 離散換頁模式的「下一頁」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'下一頁'**
  String get remoteCatalogEinkNextPageButton;

  /// 非 E-Ink 模式連續捲動載入的「載入更多」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'載入更多'**
  String get remoteCatalogLoadMoreButton;

  /// 重複匯入確認彈窗標題
  ///
  /// In zh_TW, this message translates to:
  /// **'重複的書籍'**
  String get remoteCatalogDuplicateDialogTitle;

  /// 重複匯入確認彈窗的確認按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'仍要建立'**
  String get remoteCatalogDuplicateDialogConfirmButton;

  /// 離開畫面前的傳輸中示警對話框標題
  ///
  /// In zh_TW, this message translates to:
  /// **'目前尚有檔案正在傳輸'**
  String get wifiTransferLeaveConfirmTitle;

  /// 離開畫面前的傳輸中示警對話框訊息
  ///
  /// In zh_TW, this message translates to:
  /// **'離開將中斷連線，是否確定離開？'**
  String get wifiTransferLeaveConfirmMessage;

  /// 示警對話框的「確定離開」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'確定離開'**
  String get wifiTransferLeaveConfirmButton;

  /// WiFi 傳書畫面 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'WiFi 傳書'**
  String get wifiTransferTitle;

  /// 顯示網址/QR Code 前的操作說明文字
  ///
  /// In zh_TW, this message translates to:
  /// **'在同一個 WiFi 下，用瀏覽器打開以下網址：'**
  String get wifiTransferInstructionText;

  /// 傳輸中橫幅文字，{count} 為目前進行中的傳輸檔案數
  ///
  /// In zh_TW, this message translates to:
  /// **'{count, plural, =1{正在傳輸中（1 個檔案）…} other{正在傳輸中（{count} 個檔案）…}}'**
  String wifiTransferActiveCountText(int count);

  /// 偵測不到可用網路時的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'請連線至 WiFi 或開啟手機熱點'**
  String get wifiTransferUnavailableText;

  /// 手動覆寫偵測結果的按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'我確定目前是用手機熱點'**
  String get wifiTransferManualOverrideButton;

  /// 手動覆寫候選清單為空時的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'找不到任何可用網路介面'**
  String get wifiTransferNoInterfacesText;

  /// 「來源」畫面常駐下載佇列區塊的分區標題
  ///
  /// In zh_TW, this message translates to:
  /// **'下載佇列'**
  String get downloadQueueTitle;

  /// 下載中項目的「取消」圖示按鈕無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'取消'**
  String get downloadQueueCancelTooltip;

  /// 失敗/已取消項目的「重試」圖示按鈕無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'重試'**
  String get downloadQueueRetryTooltip;

  /// 已結束項目（完成/重複已略過）的「從清單移除」圖示按鈕無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'從清單移除'**
  String get downloadQueueDismissTooltip;

  /// 項目狀態標籤：排隊中尚未開始下載
  ///
  /// In zh_TW, this message translates to:
  /// **'待機'**
  String get downloadQueueStatusPending;

  /// 項目狀態標籤：正在下載且尚無位元組進度回報時顯示（有進度時改顯示百分比數字，數字本身不需翻譯）
  ///
  /// In zh_TW, this message translates to:
  /// **'下載中'**
  String get downloadQueueStatusDownloading;

  /// 項目狀態標籤：下載完成後正在比對是否與既有書籍重複
  ///
  /// In zh_TW, this message translates to:
  /// **'比對中'**
  String get downloadQueueStatusCheckingDuplicate;

  /// 項目狀態標籤：下載並匯入成功
  ///
  /// In zh_TW, this message translates to:
  /// **'完成'**
  String get downloadQueueStatusDone;

  /// 項目狀態標籤：偵測到重複且使用者選擇不建立新副本
  ///
  /// In zh_TW, this message translates to:
  /// **'重複已略過'**
  String get downloadQueueStatusDuplicateSkipped;

  /// 項目狀態標籤：下載或匯入過程發生非取消性錯誤
  ///
  /// In zh_TW, this message translates to:
  /// **'失敗'**
  String get downloadQueueStatusFailed;

  /// 項目狀態標籤：下載失敗的原因是雲端匯入來源帳號授權失效（見 CONTEXT.md「雲端授權失效」），使用者需到設定重新連結帳號後按重試
  ///
  /// In zh_TW, this message translates to:
  /// **'需重新連結帳號'**
  String get downloadQueueStatusNeedsReauth;

  /// 項目狀態標籤：使用者主動取消下載
  ///
  /// In zh_TW, this message translates to:
  /// **'已取消'**
  String get downloadQueueStatusCancelled;

  /// 下載佇列指紋比對命中重複時的確認訊息（審查意見 review-issue-6.md I-1：原為 download_queue_controller.dart 內硬編碼中文，改由 main.dart 呼叫端在地化組裝）
  ///
  /// In zh_TW, this message translates to:
  /// **'偵測到「{name}」與本機已有的一本書內容相同，仍要建立新的一份嗎？'**
  String downloadQueueDuplicateConfirmMessage(String name);

  /// 「來源」聚合頁 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'來源'**
  String get sourcesHomeTitle;

  /// AppBar「書架」導覽按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'書架'**
  String get sourcesHomeLibraryTooltip;

  /// AppBar「設定」導覽按鈕的無障礙提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'設定'**
  String get sourcesHomeSettingsTooltip;

  /// 「本機」分區標題
  ///
  /// In zh_TW, this message translates to:
  /// **'本機'**
  String get sourcesHomeLocalSection;

  /// 「選擇檔案」入口列標題
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇檔案（可多選）'**
  String get sourcesHomePickFilesTitle;

  /// 「選擇資料夾」入口列標題
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇資料夾'**
  String get sourcesHomePickFolderTitle;

  /// 「WiFi 傳書」入口列標題
  ///
  /// In zh_TW, this message translates to:
  /// **'WiFi 傳書'**
  String get sourcesHomeWifiTransferTile;

  /// 「已連結服務」分區標題
  ///
  /// In zh_TW, this message translates to:
  /// **'已連結服務'**
  String get sourcesHomeConnectedServicesSection;

  /// 「遠端書庫」入口列標題，OPDS 為技術協定縮寫不翻譯
  ///
  /// In zh_TW, this message translates to:
  /// **'遠端書庫（OPDS）'**
  String get sourcesHomeRemoteLibraryTitle;

  /// 「是否依資料夾名稱自動建立分類」確認對話框標題
  ///
  /// In zh_TW, this message translates to:
  /// **'匯入資料夾'**
  String get libraryImportFolderDialogTitle;

  /// 自動建立分類勾選項的標題文字
  ///
  /// In zh_TW, this message translates to:
  /// **'依資料夾名稱自動建立分類'**
  String get libraryImportFolderAutoGroupLabel;

  /// 匯入資料夾確認對話框的確認按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'匯入'**
  String get libraryImportFolderConfirmButton;

  /// 匯入完成時，成功匯入與跳過重複兩者皆大於 0 的合併提示，{importedCount}／{skippedCount} 各自獨立處理單複數
  ///
  /// In zh_TW, this message translates to:
  /// **'{importedCount, plural, =1{已匯入 1 本} other{已匯入 {importedCount} 本}}，{skippedCount, plural, =1{1 本已存在，已跳過} other{{skippedCount} 本已存在，已跳過}}'**
  String libraryImportResultBothMessage(int importedCount, int skippedCount);

  /// 匯入完成時，僅有成功匯入（無跳過重複）的提示
  ///
  /// In zh_TW, this message translates to:
  /// **'{importedCount, plural, =1{已匯入 1 本書} other{已匯入 {importedCount} 本書}}'**
  String libraryImportResultImportedOnlyMessage(int importedCount);

  /// 匯入完成時，僅有跳過重複（無成功匯入）的提示
  ///
  /// In zh_TW, this message translates to:
  /// **'{skippedCount, plural, =1{1 本已存在，已跳過} other{{skippedCount} 本已存在，已跳過}}'**
  String libraryImportResultSkippedOnlyMessage(int skippedCount);

  /// 資料夾匯入整體失敗（無法取得持久化授權，或列舉資料夾內容失敗）時的 SnackBar；兩種失敗使用者能做的事相同（重新選資料夾／重新授權），共用一則
  ///
  /// In zh_TW, this message translates to:
  /// **'無法讀取這個資料夾，請確認已授權存取後再試一次'**
  String get libraryImportFolderFailedMessage;

  /// 複選模式的 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇書籍（可複選）'**
  String get layoutPresetBookPickerTitleMulti;

  /// 單選模式的 AppBar 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇書籍'**
  String get layoutPresetBookPickerTitleSingle;

  /// 搜尋輸入框的 hintText
  ///
  /// In zh_TW, this message translates to:
  /// **'搜尋書名或作者'**
  String get layoutPresetBookPickerSearchHint;

  /// 傳入的 books 清單為空時的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'沒有可選擇的流式 EPUB 書籍'**
  String get layoutPresetBookPickerEmptyBooks;

  /// 搜尋結果為空時的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'找不到符合的書籍'**
  String get layoutPresetBookPickerNoMatch;

  /// 版面設定預設集命名輸入 Dialog 標題
  ///
  /// In zh_TW, this message translates to:
  /// **'為預設集命名'**
  String get layoutPresetNameDialogTitle;

  /// trim 後名稱為空字串時的驗證錯誤文字
  ///
  /// In zh_TW, this message translates to:
  /// **'名稱不可為空'**
  String get layoutPresetNameDialogEmptyError;

  /// 命名對話框的「儲存」按鈕文字
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存'**
  String get layoutPresetNameDialogSaveButton;

  /// Markdown 匯出檔案標題行，{bookTitle} 為使用者書名資料，不翻譯
  ///
  /// In zh_TW, this message translates to:
  /// **'# 閱讀筆記：《{bookTitle}》'**
  String markdownExportTitle(String bookTitle);

  /// Markdown 匯出的作者標籤行，{author} 為已解析好的作者字串（可能是使用者資料，也可能是 markdownExportUnknownAuthor 的在地化回退值）
  ///
  /// In zh_TW, this message translates to:
  /// **'*   **作者**：{author}'**
  String markdownExportAuthorLabel(String author);

  /// Markdown 匯出時，書籍作者欄位為 null 的回退顯示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'未知作者'**
  String get markdownExportUnknownAuthor;

  /// Markdown 匯出的閱讀進度標籤行，{percent} 為 0-100 整數
  ///
  /// In zh_TW, this message translates to:
  /// **'*   **閱讀進度**：{percent}%'**
  String markdownExportProgressLabel(int percent);

  /// Markdown 匯出的導出時間標籤行，{time} 為依目前介面語言格式化後的日期字串（DateFormat.yMd）
  ///
  /// In zh_TW, this message translates to:
  /// **'*   **導出時間**：{time}'**
  String markdownExportTimeLabel(String time);

  /// Markdown 匯出的書籤清單區塊標題，{count} 為書籤本數
  ///
  /// In zh_TW, this message translates to:
  /// **'## 🔖 書籤清單 ({count})'**
  String markdownExportBookmarksSection(int count);

  /// Markdown 匯出時，書籤清單為空的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'*(尚未加入書籤)*'**
  String get markdownExportNoBookmarks;

  /// Markdown 匯出的劃線與個人備註區塊標題，{count} 為劃線/備註合併總筆數
  ///
  /// In zh_TW, this message translates to:
  /// **'## ✏️ 劃線與個人備註 ({count})'**
  String markdownExportAnnotationsSection(int count);

  /// Markdown 匯出時，劃線與備註清單為空的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'*(尚未加入任何劃線或備註)*'**
  String get markdownExportNoAnnotations;

  /// Markdown 匯出的單筆劃線/備註標題行，{label} 為樣式標籤（螢光筆/底線/備註），{position} 為 Bookmark.defaultName() 產出的位置文字（該函式本身不在本 Issue 翻譯範圍，見 spec.md §7）
  ///
  /// In zh_TW, this message translates to:
  /// **'### 📌 {label}（位置：{position}）'**
  String markdownExportAnnotationHeading(String label, String position);

  /// 新增書籤時的預設名稱（PDF），{page} 為頁碼（1-based）
  ///
  /// In zh_TW, this message translates to:
  /// **'第 {page} 頁'**
  String bookmarkDefaultNamePdfPage(int page);

  /// 新增書籤時的預設名稱（無章節名稱時），{percent} 為全書進度百分比（0–100）；同時用於 Markdown 匯出的位置標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'{percent}% 處'**
  String bookmarkDefaultNamePercent(int percent);

  /// 新增書籤時，章節名稱與進度皆無法取得時的通用預設名稱
  ///
  /// In zh_TW, this message translates to:
  /// **'書籤'**
  String get bookmarkDefaultNameFallback;

  /// 朗讀（TTS）音訊服務啟動初始化失敗而降級後，進入閱讀器時顯示一次的 SnackBar 文字（每次啟動 App 只顯示一次，見 TtsDegradedNotice）。朗讀本身仍可用，少的是系統媒體通知、鎖定畫面控制與背景朗讀的前景服務保護
  ///
  /// In zh_TW, this message translates to:
  /// **'本次沒有媒體通知與鎖定畫面控制，朗讀仍可使用'**
  String get ttsDegradedNotice;

  /// Android 朗讀（TTS）前景服務的通知頻道名稱，顯示於系統的通知設定。頻道於啟動時建立，語言以啟動當下為準（無 BuildContext，見 startup_localizations.dart）
  ///
  /// In zh_TW, this message translates to:
  /// **'朗讀播放中'**
  String get ttsNotificationChannelName;

  /// 朗讀語音清單中內建的「系統預設語音」選項顯示名稱（TtsVoice.systemDefault，依語音 id 判斷後轉譯）
  ///
  /// In zh_TW, this message translates to:
  /// **'系統預設語音'**
  String get ttsVoiceSystemDefault;

  /// 遠端 OPDS 目錄的分類導覽連結缺少標題時的預設名稱（由畫面層傳給解析器）
  ///
  /// In zh_TW, this message translates to:
  /// **'未命名分類'**
  String get remoteCatalogUnnamedCategory;

  /// 遠端 OPDS 目錄的書目缺少標題時的預設書名（由畫面層傳給解析器）
  ///
  /// In zh_TW, this message translates to:
  /// **'未知書名'**
  String get remoteCatalogUnknownBookTitle;

  /// WiFi 傳書網頁（電腦瀏覽器開啟）的頁面標題與 h1
  ///
  /// In zh_TW, this message translates to:
  /// **'elinkBook WiFi 傳書'**
  String get wifiPageTitle;

  /// WiFi 傳書網頁「上傳書籍」區塊標題
  ///
  /// In zh_TW, this message translates to:
  /// **'上傳書籍'**
  String get wifiPageUploadHeading;

  /// WiFi 傳書網頁拖放區文字，後面接「選擇檔案」連結
  ///
  /// In zh_TW, this message translates to:
  /// **'拖放檔案到此處，或'**
  String get wifiPageDropzoneText;

  /// WiFi 傳書網頁拖放區內開啟檔案選擇器的連結文字
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇檔案'**
  String get wifiPageChooseFile;

  /// WiFi 傳書網頁「下載書籍」區塊標題
  ///
  /// In zh_TW, this message translates to:
  /// **'下載書籍'**
  String get wifiPageDownloadHeading;

  /// WiFi 傳書網頁書名搜尋框的提示文字
  ///
  /// In zh_TW, this message translates to:
  /// **'搜尋書名…'**
  String get wifiPageSearchPlaceholder;

  /// WiFi 傳書網頁按鈕：勾選目前頁的全部書籍
  ///
  /// In zh_TW, this message translates to:
  /// **'全選目前頁'**
  String get wifiPageSelectPage;

  /// WiFi 傳書網頁按鈕：清除所有勾選
  ///
  /// In zh_TW, this message translates to:
  /// **'清除勾選'**
  String get wifiPageClearSelection;

  /// WiFi 傳書網頁已勾選數量；{count} 為數量（以字串傳入，由網頁端代入）
  ///
  /// In zh_TW, this message translates to:
  /// **'已勾選 {count} 本'**
  String wifiPageSelectedCount(String count);

  /// WiFi 傳書網頁書籍清單載入中的提示
  ///
  /// In zh_TW, this message translates to:
  /// **'載入中…'**
  String get wifiPageLoading;

  /// WiFi 傳書網頁分頁按鈕：上一頁
  ///
  /// In zh_TW, this message translates to:
  /// **'上一頁'**
  String get wifiPagePrevPage;

  /// WiFi 傳書網頁分頁按鈕：下一頁
  ///
  /// In zh_TW, this message translates to:
  /// **'下一頁'**
  String get wifiPageNextPage;

  /// WiFi 傳書網頁目前頁碼；{page}、{total} 以字串傳入，由網頁端代入
  ///
  /// In zh_TW, this message translates to:
  /// **'第 {page} / {total} 頁'**
  String wifiPagePageInfo(String page, String total);

  /// WiFi 傳書網頁按鈕：下載已勾選的書籍
  ///
  /// In zh_TW, this message translates to:
  /// **'下載已勾選書籍'**
  String get wifiPageDownloadSelected;

  /// WiFi 傳書網頁：手機端沒有任何可下載書籍時的提示
  ///
  /// In zh_TW, this message translates to:
  /// **'目前沒有可下載的書籍'**
  String get wifiPageNoBooks;

  /// WiFi 傳書網頁：搜尋後沒有符合的書籍時的提示
  ///
  /// In zh_TW, this message translates to:
  /// **'查無符合條件的書籍'**
  String get wifiPageNoMatch;

  /// WiFi 傳書網頁：書籍清單載入失敗的提示
  ///
  /// In zh_TW, this message translates to:
  /// **'無法載入書籍清單'**
  String get wifiPageLoadFailed;

  /// WiFi 傳書網頁書籍總數；{count} 以字串傳入，由網頁端代入
  ///
  /// In zh_TW, this message translates to:
  /// **'共 {count} 本書籍'**
  String wifiPageTotalBooks(String count);

  /// WiFi 傳書網頁搜尋結果統計；{matched} 為符合數、{total} 為總數，皆以字串傳入
  ///
  /// In zh_TW, this message translates to:
  /// **'符合 {matched} 本 / 共 {total} 本'**
  String wifiPageMatchStats(String matched, String total);

  /// WiFi 傳書網頁：未勾選任何書籍就按下載時的提示
  ///
  /// In zh_TW, this message translates to:
  /// **'請至少勾選一本書'**
  String get wifiPageSelectAtLeastOne;

  /// WiFi 傳書網頁：批次下載進行中的狀態文字
  ///
  /// In zh_TW, this message translates to:
  /// **'下載中…'**
  String get wifiPageDownloading;

  /// WiFi 傳書網頁：已觸發全部下載；{count} 為本數，以字串傳入
  ///
  /// In zh_TW, this message translates to:
  /// **'已觸發全部下載（共 {count} 本）'**
  String wifiPageDownloadTriggered(String count);

  /// WiFi 傳書網頁上傳結果：已匯入
  ///
  /// In zh_TW, this message translates to:
  /// **'已匯入'**
  String get wifiPageOutcomeImported;

  /// WiFi 傳書網頁上傳結果：書籍已存在而略過
  ///
  /// In zh_TW, this message translates to:
  /// **'已存在，已略過'**
  String get wifiPageOutcomeDuplicateSkipped;

  /// WiFi 傳書網頁上傳結果：檔案格式不支援
  ///
  /// In zh_TW, this message translates to:
  /// **'格式不支援'**
  String get wifiPageOutcomeUnsupportedFormat;

  /// WiFi 傳書網頁上傳結果：匯入失敗
  ///
  /// In zh_TW, this message translates to:
  /// **'匯入失敗'**
  String get wifiPageOutcomeFailed;

  /// WiFi 傳書網頁上傳結果列；{name} 為檔名、{outcome} 為結果文字，皆以字串傳入
  ///
  /// In zh_TW, this message translates to:
  /// **'{name}：{outcome}'**
  String wifiPageUploadResultLine(String name, String outcome);

  /// WiFi 傳書網頁：上傳的檔案缺少檔名時顯示的名稱
  ///
  /// In zh_TW, this message translates to:
  /// **'(未知檔名)'**
  String get wifiPageUnknownFileName;

  /// WiFi 傳書網頁：開始上傳前的準備狀態
  ///
  /// In zh_TW, this message translates to:
  /// **'準備上傳…'**
  String get wifiPageUploadPreparing;

  /// WiFi 傳書網頁：上傳進行中（無法得知進度百分比時）
  ///
  /// In zh_TW, this message translates to:
  /// **'正在上傳…'**
  String get wifiPageUploading;

  /// WiFi 傳書網頁：上傳進行中並附進度；{percent} 為百分比數字，以字串傳入
  ///
  /// In zh_TW, this message translates to:
  /// **'正在上傳… ({percent}%)'**
  String wifiPageUploadingPercent(String percent);

  /// WiFi 傳書網頁：位元組已傳完，手機端處理與匯入中
  ///
  /// In zh_TW, this message translates to:
  /// **'上傳完成，手機端處理與匯入中，請稍候…'**
  String get wifiPageUploadProcessing;

  /// WiFi 傳書網頁：無法得知檔案總大小時的容量顯示
  ///
  /// In zh_TW, this message translates to:
  /// **'未知'**
  String get wifiPageUnknownSize;

  /// WiFi 傳書網頁：伺服器回應錯誤狀態碼；{status} 為 HTTP 狀態碼，以字串傳入
  ///
  /// In zh_TW, this message translates to:
  /// **'上傳失敗：伺服器回應錯誤 ({status})'**
  String wifiPageUploadFailedServer(String status);

  /// WiFi 傳書網頁：伺服器回應無法解析
  ///
  /// In zh_TW, this message translates to:
  /// **'上傳失敗：無法解析伺服器回應'**
  String get wifiPageUploadFailedParse;

  /// WiFi 傳書網頁：網路錯誤導致上傳失敗
  ///
  /// In zh_TW, this message translates to:
  /// **'上傳失敗：網路錯誤'**
  String get wifiPageUploadFailedNetwork;

  /// WiFi 傳書網頁：上傳被中斷
  ///
  /// In zh_TW, this message translates to:
  /// **'上傳已中斷'**
  String get wifiPageUploadAborted;

  /// WiFi 傳書網頁：上傳逾時
  ///
  /// In zh_TW, this message translates to:
  /// **'上傳逾時'**
  String get wifiPageUploadTimeout;

  /// 閱讀統計畫面標題，同時作為設定頁「閱讀統計」入口的標籤
  ///
  /// In zh_TW, this message translates to:
  /// **'閱讀統計'**
  String get statsScreenTitle;

  /// 閱讀統計畫面「累計總時數」卡片的標題
  ///
  /// In zh_TW, this message translates to:
  /// **'累計閱讀時數'**
  String get statsTotalDuration;

  /// 時數顯示（滿 1 小時）：{hours} 為小時數、{minutes} 為剩餘分鐘數（0–59）
  ///
  /// In zh_TW, this message translates to:
  /// **'{hours} 小時 {minutes} 分鐘'**
  String statsHoursMinutesFormat(int hours, int minutes);

  /// 時數顯示（未滿 1 小時）：{minutes} 為分鐘數
  ///
  /// In zh_TW, this message translates to:
  /// **'{minutes} 分鐘'**
  String statsMinutesFormat(int minutes);

  /// 當日詳情卡片標題，{date} 為已依目前介面語言格式化的日期字串（DateFormat.yMd(locale) 的結果）
  ///
  /// In zh_TW, this message translates to:
  /// **'{date} 閱讀明細'**
  String statsDailyDetailsTitle(String date);

  /// 當日詳情卡片在該日沒有任何閱讀紀錄時顯示的說明文字
  ///
  /// In zh_TW, this message translates to:
  /// **'當日無閱讀紀錄'**
  String get statsNoDataOnDate;

  /// 閱讀統計畫面讀取資料失敗時顯示的固定錯誤文字（取代載入中圖示，避免永遠停在 spinner）
  ///
  /// In zh_TW, this message translates to:
  /// **'無法載入閱讀統計'**
  String get statsLoadFailed;

  /// 貢獻圖圖例左端文字（色階較淺＝閱讀較少）
  ///
  /// In zh_TW, this message translates to:
  /// **'較少'**
  String get statsLegendLess;

  /// 貢獻圖圖例右端文字（色階較深＝閱讀較多）
  ///
  /// In zh_TW, this message translates to:
  /// **'較多'**
  String get statsLegendMore;

  /// 「清除全部統計」按鈕文字，同時是確認對話框的標題與確認鈕文字（DESIGN.md §9.2：確認鈕需標明具體後果）
  ///
  /// In zh_TW, this message translates to:
  /// **'清除全部統計'**
  String get statsClearAllTitle;

  /// 清除全部統計確認對話框的內文
  ///
  /// In zh_TW, this message translates to:
  /// **'確定要清除所有閱讀統計嗎？此動作無法復原。'**
  String get statsClearAllConfirmMessage;

  /// 清除全部統計成功後的提示訊息（SnackBar）
  ///
  /// In zh_TW, this message translates to:
  /// **'已清除全部閱讀統計'**
  String get statsClearAllSuccess;

  /// 貢獻圖左側星期標籤欄：星期一（週一列）
  ///
  /// In zh_TW, this message translates to:
  /// **'一'**
  String get statsWeekdayMon;

  /// 貢獻圖左側星期標籤欄：星期三（週三列）
  ///
  /// In zh_TW, this message translates to:
  /// **'三'**
  String get statsWeekdayWed;

  /// 貢獻圖左側星期標籤欄：星期五（週五列）
  ///
  /// In zh_TW, this message translates to:
  /// **'五'**
  String get statsWeekdayFri;
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
