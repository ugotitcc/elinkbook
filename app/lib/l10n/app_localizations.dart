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

  /// layoutPresetRepository 未提供時，點擊「另存為新預設集」顯示的 SnackBar 訊息
  ///
  /// In zh_TW, this message translates to:
  /// **'暫時無法儲存預設集'**
  String get readerSaveAsPresetUnavailableMessage;

  /// 另存為新預設集過程發生例外時顯示的 SnackBar 訊息，{error} 為例外物件的字串表示
  ///
  /// In zh_TW, this message translates to:
  /// **'另存為新預設集失敗：{error}'**
  String readerSaveAsPresetFailedMessage(String error);

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

  /// 套用版面設定（來自預設集或來自其他書籍）過程發生例外時顯示的 SnackBar 訊息，{error} 為例外物件的字串表示，兩處呼叫端共用
  ///
  /// In zh_TW, this message translates to:
  /// **'套用版面設定失敗：{error}'**
  String readerApplyPresetFailedMessage(String error);

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

  /// 刪除預設集過程發生例外時顯示的 SnackBar 訊息，{error} 為例外物件的字串表示
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除預設集失敗：{error}'**
  String readerDeletePresetFailedMessage(String error);

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

  /// 開書失敗且 _errorMessage 為 null 時的回退錯誤文字
  ///
  /// In zh_TW, this message translates to:
  /// **'無法載入書籍'**
  String get readerFailedToLoadBookMessage;

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
