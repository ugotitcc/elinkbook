// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get groupUncategorized => '未分類';

  @override
  String get close => '關閉';

  @override
  String get settingsLanguageTitle => '語言';

  @override
  String get settingsLanguageFollowSystem => '跟隨系統';

  @override
  String settingsLanguageFollowSystemSubtitle(String language) {
    return '跟隨系統（$language）';
  }

  @override
  String get settingsLanguageZhTW => '正體中文';

  @override
  String get settingsLanguageZhCN => '簡體中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '確定';

  @override
  String get errorOperationFailed => '操作失敗，請稍後再試';

  @override
  String get libraryGroupManageTitle => '管理分類';

  @override
  String get libraryGroupAddFieldLabel => '新增分類名稱';

  @override
  String get libraryGroupAddButton => '新增';

  @override
  String get libraryGroupRenameTitle => '重新命名分類';

  @override
  String get libraryGroupDeleteTitle => '刪除分類';

  @override
  String libraryGroupDeleteConfirmMessage(String name, String uncategorized) {
    return '確定要刪除分類「$name」嗎？該分類下的書籍將改列為「$uncategorized」。';
  }

  @override
  String get libraryGroupDeleteButton => '刪除';

  @override
  String libraryGroupReservedNameError(String name) {
    return '「$name」是系統保留的分類名稱，請使用其他名稱';
  }

  @override
  String get libraryMoveToGroupTitle => '移動到分類';

  @override
  String get errorNetworkConnection => '載入失敗，請檢查網路連線';

  @override
  String cloudBrowserDuplicateConfirmMessage(String name) {
    return '「$name」之前匯入過了，仍要建立新的一份嗎？';
  }

  @override
  String cloudBrowserDownloadQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個檔案',
      one: '1 個檔案',
    );
    return '已加入下載佇列（$_temp0），可至「來源」畫面查看進度';
  }

  @override
  String get cloudBrowserMobileDataDialogTitle => '行動數據下載提醒';

  @override
  String get cloudBrowserMobileDataDialogMessage =>
      '目前使用行動數據連線，勾選的檔案中有超過 20MB 的項目，下載可能產生流量費用，確定要繼續嗎？';

  @override
  String get cloudBrowserMobileDataDialogConfirm => '繼續下載';

  @override
  String get cloudBrowserDownloadSelectedTooltip => '下載已選取';

  @override
  String cloudBrowserReauthMessage(String provider) {
    return '登入已過期，請至「設定」重新連結 $provider 帳號';
  }

  @override
  String get cloudBrowserGenericProviderLabel => '雲端';

  @override
  String get cloudBrowserImportCategoryLabel => '匯入分類：';

  @override
  String get cloudBrowserTruncatedNotice => '這個資料夾檔案較多，僅顯示前 1000 筆';

  @override
  String get bookActionShowDetails => '詳細資料';

  @override
  String get bookActionMove => '移動';

  @override
  String get bookActionLayoutOverride => '版面覆寫';

  @override
  String get bookActionRemoveCache => '移除快取';

  @override
  String get bookActionDelete => '刪除';

  @override
  String get fullTextSearchEnableDialogTitle => '啟用全文檢索';

  @override
  String get fullTextSearchEnableMessagePdf =>
      '將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量消耗，是否繼續？\n\n部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容，索引後仍查不到屬於正常情況。';

  @override
  String get fullTextSearchEnableMessageOther =>
      '將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量消耗，是否繼續？';

  @override
  String get fullTextSearchEnableConfirmButton => '確認開啟';

  @override
  String get bookSearchHint => '在本書中搜尋...';

  @override
  String get searchClearTooltip => '清除';

  @override
  String get fullTextSearchUnavailableMessage => '本裝置不支援全文檢索';

  @override
  String bookSearchResultsSummary(int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '共 $total 筆結果',
      one: '共 1 筆結果',
    );
    return '$_temp0';
  }

  @override
  String bookSearchResultsSummaryTruncated(int shown, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total 筆結果',
      one: '1 筆結果',
    );
    return '僅顯示前 $shown 筆，共 $_temp0';
  }

  @override
  String get bookSearchSortByPosition => '依書中順序';

  @override
  String get bookSearchSortByRelevance => '依相關度排序';

  @override
  String get fullTextSearchNoContentMatches => '查無符合的書內內容';

  @override
  String bookSearchLocationPage(int page) {
    return '第 $page 頁';
  }

  @override
  String bookSearchLocationChapter(int chapter) {
    return '第 $chapter 章';
  }

  @override
  String get librarySearchSettingsSheetTitle => '全文檢索設定';

  @override
  String get librarySearchScreenTitle => '搜尋書內內容';

  @override
  String get librarySearchSettingsTooltip => '全文檢索設定';

  @override
  String get librarySearchFieldHint => '搜尋書名、作者或書本內容...';

  @override
  String get librarySearchTitleAuthorSectionHeader => '書名/作者匹配';

  @override
  String get librarySearchContentSectionHeader => '內容匹配';

  @override
  String get librarySearchGuidanceNotEnabled =>
      '尚未啟用全文檢索，開啟後才能搜尋書本內容（點擊右上角設定圖示開啟）';

  @override
  String get librarySearchGuidancePdfOnly => '已啟用「PDF」全文檢索，其他格式尚未啟用';

  @override
  String get librarySearchGuidanceOtherOnly => '已啟用「其他格式」全文檢索，PDF 內容尚未啟用';

  @override
  String librarySearchDrillDownButton(int total, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '查看全部 $total 筆結果',
      one: '查看全部 1 筆結果',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '還有 $remaining 筆',
      one: '還有 1 筆',
    );
    return '$_temp0（$_temp1）';
  }

  @override
  String get librarySearchPdfToggleTitle => 'PDF 全文檢索';

  @override
  String get librarySearchPdfToggleSubtitle => '部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容';

  @override
  String get librarySearchRebuildIndexTooltip => '重建索引';

  @override
  String get librarySearchFoliateToggleTitle => '其他格式全文檢索';

  @override
  String get librarySearchFoliateToggleSubtitle => 'EPUB／TXT／KF8 等格式的背景索引建置';
}

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn() : super('zh_CN');

  @override
  String get groupUncategorized => '未分类';

  @override
  String get close => '关闭';

  @override
  String get settingsLanguageTitle => '语言';

  @override
  String get settingsLanguageFollowSystem => '跟随系统';

  @override
  String settingsLanguageFollowSystemSubtitle(String language) {
    return '跟随系统（$language）';
  }

  @override
  String get settingsLanguageZhTW => '正体中文';

  @override
  String get settingsLanguageZhCN => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确定';

  @override
  String get errorOperationFailed => '操作失败，请稍后再试';

  @override
  String get libraryGroupManageTitle => '管理分类';

  @override
  String get libraryGroupAddFieldLabel => '新增分类名称';

  @override
  String get libraryGroupAddButton => '新增';

  @override
  String get libraryGroupRenameTitle => '重新命名分类';

  @override
  String get libraryGroupDeleteTitle => '删除分类';

  @override
  String libraryGroupDeleteConfirmMessage(String name, String uncategorized) {
    return '确定要删除分类「$name」吗？该分类下的书籍将改列为「$uncategorized」。';
  }

  @override
  String get libraryGroupDeleteButton => '删除';

  @override
  String libraryGroupReservedNameError(String name) {
    return '「$name」是系统保留的分类名称，请使用其他名称';
  }

  @override
  String get libraryMoveToGroupTitle => '移动到分类';

  @override
  String get errorNetworkConnection => '加载失败，请检查网络连接';

  @override
  String cloudBrowserDuplicateConfirmMessage(String name) {
    return '「$name」之前已导入过，仍要建立新的一份吗？';
  }

  @override
  String cloudBrowserDownloadQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个文件',
      one: '1 个文件',
    );
    return '已加入下载队列（$_temp0），可至「来源」画面查看进度';
  }

  @override
  String get cloudBrowserMobileDataDialogTitle => '移动数据下载提醒';

  @override
  String get cloudBrowserMobileDataDialogMessage =>
      '目前使用移动数据连接，勾选的文件中有超过 20MB 的项目，下载可能产生流量费用，确定要继续吗？';

  @override
  String get cloudBrowserMobileDataDialogConfirm => '继续下载';

  @override
  String get cloudBrowserDownloadSelectedTooltip => '下载已选取';

  @override
  String cloudBrowserReauthMessage(String provider) {
    return '登录已过期，请至「设置」重新连接 $provider 账户';
  }

  @override
  String get cloudBrowserGenericProviderLabel => '云端';

  @override
  String get cloudBrowserImportCategoryLabel => '导入分类：';

  @override
  String get cloudBrowserTruncatedNotice => '这个文件夹里的文件较多，仅显示前 1000 个';

  @override
  String get bookActionShowDetails => '详细资料';

  @override
  String get bookActionMove => '移动';

  @override
  String get bookActionLayoutOverride => '排版覆盖';

  @override
  String get bookActionRemoveCache => '移除缓存';

  @override
  String get bookActionDelete => '删除';

  @override
  String get fullTextSearchEnableDialogTitle => '启用全文检索';

  @override
  String get fullTextSearchEnableMessagePdf =>
      '将触发后台索引建立（含既有书库旧书回填），过程会增加运算与电量消耗，是否继续？\n\n部分扫描/图片型 PDF 可能没有可搜索的文字内容，索引后仍查不到属于正常情况。';

  @override
  String get fullTextSearchEnableMessageOther =>
      '将触发后台索引建立（含既有书库旧书回填），过程会增加运算与电量消耗，是否继续？';

  @override
  String get fullTextSearchEnableConfirmButton => '确认开启';

  @override
  String get bookSearchHint => '在本书中搜索...';

  @override
  String get searchClearTooltip => '清除';

  @override
  String get fullTextSearchUnavailableMessage => '本设备不支持全文检索';

  @override
  String bookSearchResultsSummary(int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '共 $total 条结果',
      one: '共 1 条结果',
    );
    return '$_temp0';
  }

  @override
  String bookSearchResultsSummaryTruncated(int shown, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total 条结果',
      one: '1 条结果',
    );
    return '仅显示前 $shown 条，共 $_temp0';
  }

  @override
  String get bookSearchSortByPosition => '依书中顺序';

  @override
  String get bookSearchSortByRelevance => '按相关度排序';

  @override
  String get fullTextSearchNoContentMatches => '未找到符合的书内内容';

  @override
  String bookSearchLocationPage(int page) {
    return '第 $page 页';
  }

  @override
  String bookSearchLocationChapter(int chapter) {
    return '第 $chapter 章';
  }

  @override
  String get librarySearchSettingsSheetTitle => '全文检索设置';

  @override
  String get librarySearchScreenTitle => '搜索书内内容';

  @override
  String get librarySearchSettingsTooltip => '全文检索设置';

  @override
  String get librarySearchFieldHint => '搜索书名、作者或书本内容...';

  @override
  String get librarySearchTitleAuthorSectionHeader => '书名/作者匹配';

  @override
  String get librarySearchContentSectionHeader => '内容匹配';

  @override
  String get librarySearchGuidanceNotEnabled =>
      '尚未启用全文检索，开启后才能搜索书本内容（点击右上角设置图标开启）';

  @override
  String get librarySearchGuidancePdfOnly => '已启用「PDF」全文检索，其他格式尚未启用';

  @override
  String get librarySearchGuidanceOtherOnly => '已启用「其他格式」全文检索，PDF 内容尚未启用';

  @override
  String librarySearchDrillDownButton(int total, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '查看全部 $total 条结果',
      one: '查看全部 1 条结果',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '还有 $remaining 条',
      one: '还有 1 条',
    );
    return '$_temp0（$_temp1）';
  }

  @override
  String get librarySearchPdfToggleTitle => 'PDF 全文检索';

  @override
  String get librarySearchPdfToggleSubtitle => '部分扫描/图片型 PDF 可能没有可搜索的文字内容';

  @override
  String get librarySearchRebuildIndexTooltip => '重建索引';

  @override
  String get librarySearchFoliateToggleTitle => '其他格式全文检索';

  @override
  String get librarySearchFoliateToggleSubtitle => 'EPUB／TXT／KF8 等格式的后台索引建立';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get groupUncategorized => '未分類';

  @override
  String get close => '關閉';

  @override
  String get settingsLanguageTitle => '語言';

  @override
  String get settingsLanguageFollowSystem => '跟隨系統';

  @override
  String settingsLanguageFollowSystemSubtitle(String language) {
    return '跟隨系統（$language）';
  }

  @override
  String get settingsLanguageZhTW => '正體中文';

  @override
  String get settingsLanguageZhCN => '簡體中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '確定';

  @override
  String get errorOperationFailed => '操作失敗，請稍後再試';

  @override
  String get libraryGroupManageTitle => '管理分類';

  @override
  String get libraryGroupAddFieldLabel => '新增分類名稱';

  @override
  String get libraryGroupAddButton => '新增';

  @override
  String get libraryGroupRenameTitle => '重新命名分類';

  @override
  String get libraryGroupDeleteTitle => '刪除分類';

  @override
  String libraryGroupDeleteConfirmMessage(String name, String uncategorized) {
    return '確定要刪除分類「$name」嗎？該分類下的書籍將改列為「$uncategorized」。';
  }

  @override
  String get libraryGroupDeleteButton => '刪除';

  @override
  String libraryGroupReservedNameError(String name) {
    return '「$name」是系統保留的分類名稱，請使用其他名稱';
  }

  @override
  String get libraryMoveToGroupTitle => '移動到分類';

  @override
  String get errorNetworkConnection => '載入失敗，請檢查網路連線';

  @override
  String cloudBrowserDuplicateConfirmMessage(String name) {
    return '「$name」之前匯入過了，仍要建立新的一份嗎？';
  }

  @override
  String cloudBrowserDownloadQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個檔案',
      one: '1 個檔案',
    );
    return '已加入下載佇列（$_temp0），可至「來源」畫面查看進度';
  }

  @override
  String get cloudBrowserMobileDataDialogTitle => '行動數據下載提醒';

  @override
  String get cloudBrowserMobileDataDialogMessage =>
      '目前使用行動數據連線，勾選的檔案中有超過 20MB 的項目，下載可能產生流量費用，確定要繼續嗎？';

  @override
  String get cloudBrowserMobileDataDialogConfirm => '繼續下載';

  @override
  String get cloudBrowserDownloadSelectedTooltip => '下載已選取';

  @override
  String cloudBrowserReauthMessage(String provider) {
    return '登入已過期，請至「設定」重新連結 $provider 帳號';
  }

  @override
  String get cloudBrowserGenericProviderLabel => '雲端';

  @override
  String get cloudBrowserImportCategoryLabel => '匯入分類：';

  @override
  String get cloudBrowserTruncatedNotice => '這個資料夾檔案較多，僅顯示前 1000 筆';

  @override
  String get bookActionShowDetails => '詳細資料';

  @override
  String get bookActionMove => '移動';

  @override
  String get bookActionLayoutOverride => '版面覆寫';

  @override
  String get bookActionRemoveCache => '移除快取';

  @override
  String get bookActionDelete => '刪除';

  @override
  String get fullTextSearchEnableDialogTitle => '啟用全文檢索';

  @override
  String get fullTextSearchEnableMessagePdf =>
      '將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量消耗，是否繼續？\n\n部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容，索引後仍查不到屬於正常情況。';

  @override
  String get fullTextSearchEnableMessageOther =>
      '將觸發背景索引建置（含既有書庫舊書回填），過程會增加運算與電量消耗，是否繼續？';

  @override
  String get fullTextSearchEnableConfirmButton => '確認開啟';

  @override
  String get bookSearchHint => '在本書中搜尋...';

  @override
  String get searchClearTooltip => '清除';

  @override
  String get fullTextSearchUnavailableMessage => '本裝置不支援全文檢索';

  @override
  String bookSearchResultsSummary(int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '共 $total 筆結果',
      one: '共 1 筆結果',
    );
    return '$_temp0';
  }

  @override
  String bookSearchResultsSummaryTruncated(int shown, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total 筆結果',
      one: '1 筆結果',
    );
    return '僅顯示前 $shown 筆，共 $_temp0';
  }

  @override
  String get bookSearchSortByPosition => '依書中順序';

  @override
  String get bookSearchSortByRelevance => '依相關度排序';

  @override
  String get fullTextSearchNoContentMatches => '查無符合的書內內容';

  @override
  String bookSearchLocationPage(int page) {
    return '第 $page 頁';
  }

  @override
  String bookSearchLocationChapter(int chapter) {
    return '第 $chapter 章';
  }

  @override
  String get librarySearchSettingsSheetTitle => '全文檢索設定';

  @override
  String get librarySearchScreenTitle => '搜尋書內內容';

  @override
  String get librarySearchSettingsTooltip => '全文檢索設定';

  @override
  String get librarySearchFieldHint => '搜尋書名、作者或書本內容...';

  @override
  String get librarySearchTitleAuthorSectionHeader => '書名/作者匹配';

  @override
  String get librarySearchContentSectionHeader => '內容匹配';

  @override
  String get librarySearchGuidanceNotEnabled =>
      '尚未啟用全文檢索，開啟後才能搜尋書本內容（點擊右上角設定圖示開啟）';

  @override
  String get librarySearchGuidancePdfOnly => '已啟用「PDF」全文檢索，其他格式尚未啟用';

  @override
  String get librarySearchGuidanceOtherOnly => '已啟用「其他格式」全文檢索，PDF 內容尚未啟用';

  @override
  String librarySearchDrillDownButton(int total, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '查看全部 $total 筆結果',
      one: '查看全部 1 筆結果',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '還有 $remaining 筆',
      one: '還有 1 筆',
    );
    return '$_temp0（$_temp1）';
  }

  @override
  String get librarySearchPdfToggleTitle => 'PDF 全文檢索';

  @override
  String get librarySearchPdfToggleSubtitle => '部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容';

  @override
  String get librarySearchRebuildIndexTooltip => '重建索引';

  @override
  String get librarySearchFoliateToggleTitle => '其他格式全文檢索';

  @override
  String get librarySearchFoliateToggleSubtitle => 'EPUB／TXT／KF8 等格式的背景索引建置';
}
