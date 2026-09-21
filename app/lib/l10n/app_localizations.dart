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
