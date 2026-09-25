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
  String get settingsLanguageZhCN => '简体中文';

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
  String libraryGroupNameAlreadyExistsError(String name) {
    return '分類「$name」已存在，請使用其他名稱';
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

  @override
  String get libraryBackButtonTooltip => '返回上層';

  @override
  String get libraryShelfTitle => '書架';

  @override
  String get librarySortViewTooltip => '排序與檢視';

  @override
  String get librarySortByLastRead => '最後閱讀';

  @override
  String get librarySortByCreateTime => '建立時間';

  @override
  String get librarySortByAuthor => '作者';

  @override
  String get librarySortByTitle => '書名';

  @override
  String get libraryToggleViewToList => '切換為列表';

  @override
  String get libraryToggleViewToShelf => '切換為書架';

  @override
  String get libraryManageGroupsMenuItem => '管理分類...';

  @override
  String get librarySourceTooltip => '來源';

  @override
  String get librarySettingsTooltip => '設定';

  @override
  String get libraryCancelSelectionTooltip => '取消選取';

  @override
  String librarySelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已選取 $count 本',
      one: '已選取 1 本',
    );
    return '$_temp0';
  }

  @override
  String get libraryMoveToGroupTooltip => '移動到分類';

  @override
  String get libraryForceFxlTooltip => '強制 FXL';

  @override
  String get libraryRestoreAutoLayoutTooltip => '恢復自動判斷';

  @override
  String get libraryDeleteTooltip => '刪除';

  @override
  String get libraryRemoveLocalCacheTooltip => '移除本機快取';

  @override
  String get libraryEmptyStateMessage => '尚未匯入書籍';

  @override
  String get libraryEmptyStateImportButton => '匯入書籍';

  @override
  String get librarySearchHint => '搜尋書名或作者...';

  @override
  String get libraryContentSearchEntryLabel => '搜尋書本內容';

  @override
  String get libraryNoMatchingBooks => '找不到符合的書籍';

  @override
  String get libraryDeleteBooksDialogTitle => '刪除書籍';

  @override
  String libraryDeleteBooksConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '將刪除已選取的 $count 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？',
      one: '將刪除已選取的 1 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？',
    );
    return '$_temp0';
  }

  @override
  String get libraryDeleteBooksConfirmButton => '刪除';

  @override
  String get libraryRedownloadAction => '重新下載';

  @override
  String libraryRedownloadConfirmMessage(String title) {
    return '即將重新下載「$title」，確定要繼續嗎？';
  }

  @override
  String libraryRedownloadConfirmMessageMobileData(String title) {
    return '即將重新下載「$title」，目前使用行動數據連線，可能產生流量費用，確定要繼續嗎？';
  }

  @override
  String get libraryRemoteDisabledMessage => '遠端書庫功能未啟用，無法重新下載';

  @override
  String get libraryRemoteServerNotFoundMessage => '找不到對應的遠端書庫站點';

  @override
  String get libraryRedownloadFailedMessage => '重新下載失敗，請稍後再試';

  @override
  String libraryRemoveCacheConfirmMessage(String title) {
    return '將移除「$title」的本機檔案，書籍紀錄與閱讀進度會保留，之後可重新下載。確定要移除嗎？';
  }

  @override
  String get libraryRemoveCacheConfirmButton => '移除';

  @override
  String get libraryGroupBadgeLabel => '分類';

  @override
  String libraryGroupTileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 本',
      one: '1 本',
    );
    return '$_temp0';
  }

  @override
  String get libraryBookMenuTooltip => '更多';

  @override
  String get libraryContinueReadingLabel => '繼續閱讀';

  @override
  String get libraryBookNotDownloaded => '尚未下載';

  @override
  String get libraryUnknownFileSize => '未知大小';

  @override
  String get libraryLoadingEllipsis => '讀取中...';

  @override
  String libraryDetailAuthorLabel(String author) {
    return '作者：$author';
  }

  @override
  String get libraryUnknownAuthor => '未知';

  @override
  String libraryDetailFormatLabel(String format) {
    return '格式：$format';
  }

  @override
  String libraryDetailFileSizeLabel(String size) {
    return '檔案大小：$size';
  }

  @override
  String libraryDetailProgressLabel(String progress) {
    return '進度：$progress';
  }

  @override
  String libraryDetailLastReadLabel(String date) {
    return '最後閱讀：$date';
  }

  @override
  String get libraryNeverRead => '尚未閱讀';

  @override
  String get libraryLayoutOverrideTitle => '版面覆寫';

  @override
  String get libraryLayoutOverrideWritingModeLabel => '排版方向';

  @override
  String get libraryLayoutOverrideWritingModeDefault => '使用書籍排版';

  @override
  String get libraryLayoutOverrideWritingModeHorizontal => '橫排';

  @override
  String get libraryLayoutOverrideWritingModeVertical => '直排';

  @override
  String get libraryLayoutOverridePageTurnModeLabel => '翻頁模式';

  @override
  String get libraryLayoutOverridePageTurnModeDefault => '使用全域預設';

  @override
  String get libraryLayoutOverridePageTurnModePaginated => '分頁';

  @override
  String get libraryLayoutOverridePageTurnModeScroll => '捲動';

  @override
  String get libraryLayoutOverrideSaveButton => '儲存';

  @override
  String get readerBackTooltip => '返回';

  @override
  String get readerSearchTooltip => '搜尋內文';

  @override
  String get readerHideToolbarTooltip => '隱藏工具列';

  @override
  String get readerShowToolbarTooltip => '顯示工具列';

  @override
  String get readerTocTooltip => '目錄';

  @override
  String get readerBookmarkAddedTooltip => '已加入此頁書籤';

  @override
  String get readerBookmarkAddTooltip => '加入此頁書籤';

  @override
  String get readerAnnotationsTooltip => '劃線筆記';

  @override
  String get readerLayoutTooltip => '版面';

  @override
  String get readerTtsTooltip => '朗讀';

  @override
  String get readerPagingPreviousTooltip => '上一頁';

  @override
  String get readerPagingNextTooltip => '下一頁';

  @override
  String get readerPdfNoPagesAvailable => '無可用頁面';

  @override
  String get readerNoteDialogSaveButton => '儲存';

  @override
  String get readerNoteDialogDefaultTitle => '備註';

  @override
  String get readerAnnotationUnderlineTooltip => '底線';

  @override
  String get readerAnnotationCopyTooltip => '複製';

  @override
  String get readerAnnotationEditNoteTooltip => '編輯備註';

  @override
  String get readerAnnotationAddNoteTooltip => '新增備註';

  @override
  String get readerAnnotationDeleteHighlightAndNote => '刪除畫線與備註';

  @override
  String get readerAnnotationDeleteHighlight => '刪除畫線';

  @override
  String get readerAnnotationDeleteNote => '刪除備註';

  @override
  String get readerPdfSearchHint => '搜尋文字…';

  @override
  String get readerPdfSearchNoMatches => '找不到符合的文字';

  @override
  String get readerPdfSearchPreviousTooltip => '上一個';

  @override
  String get readerPdfSearchNextTooltip => '下一個';

  @override
  String readerPositionConflictTitle(String bookTitle) {
    return '「$bookTitle」的閱讀進度不一致';
  }

  @override
  String readerPositionConflictMessage(String local, String remote) {
    return '偵測到另一台裝置也更新過這本書的閱讀進度，請選擇要保留哪一邊：\n\n本機：$local\n雲端：$remote';
  }

  @override
  String readerPositionConflictPdfLocation(int page, int percent) {
    return '第 $page 頁（進度 $percent%）';
  }

  @override
  String readerPositionConflictEpubLocation(int percent) {
    return '進度 $percent%';
  }

  @override
  String get readerPositionConflictKeepCloud => '保留雲端';

  @override
  String get readerPositionConflictKeepLocal => '保留本機';

  @override
  String get readerTocTitle => '📖 目錄';

  @override
  String get readerTocEmptyMessage => '本書無目錄資料';

  @override
  String get readerTocTabChapters => '章節目錄';

  @override
  String get readerTocTabThumbnails => '縮圖';

  @override
  String get readerTocTabSearch => '搜尋';

  @override
  String get readerFeatureComingSoon => '此功能將於後續版本提供';

  @override
  String get readerTtsCbzUnsupportedTooltip => 'CBZ 為純圖像格式，不支援語音朗讀';

  @override
  String get readerTtsPreviousTooltip => '上一句';

  @override
  String get readerTtsPauseTooltip => '暫停朗讀';

  @override
  String get readerTtsPlayTooltip => '開始朗讀';

  @override
  String get readerTtsNextTooltip => '下一句';

  @override
  String readerTtsSpeedTooltip(String speed) {
    return '朗讀語速：${speed}x（點擊切換）';
  }

  @override
  String get readerTtsVoiceTooltip => '選擇語音';

  @override
  String get readerTtsSleepTimerLabel => '定時';

  @override
  String readerTtsSleepTimerLabelWithMinutes(int minutes) {
    return '定時 $minutes 分';
  }

  @override
  String get readerTtsCollapseLabel => '收合';

  @override
  String get readerTtsExpandLabel => '展開';

  @override
  String get readerTtsStopLabel => '停止';

  @override
  String get readerNotesSheetTitle => '筆記';

  @override
  String get readerNotesSheetExportMarkdownTooltip => '導出為 Markdown';

  @override
  String get readerNotesSheetTabBookmarks => '書籤';

  @override
  String get readerNotesSheetTabAnnotations => '劃線與備註';

  @override
  String get readerNotesSheetDeleteAllBookmarksTooltip => '刪除該書所有書籤';

  @override
  String get readerNotesSheetRenameBookmarkTitle => '重新命名書籤';

  @override
  String get readerDeleteConfirmButton => '刪除';

  @override
  String readerNotesSheetDeleteAllBookmarksConfirm(int count) {
    return '確定要刪除全部書籤嗎？（共 $count 筆）';
  }

  @override
  String get readerNotesSheetRenameTooltip => '重新命名';

  @override
  String get readerNotesSheetDeleteItemTooltip => '刪除';

  @override
  String get readerNotesSheetNoAnnotationsPlaceholder => '尚無劃線或備註';

  @override
  String get readerNotesSheetDeleteAllHighlightsButton => '刪除所有劃線';

  @override
  String get readerNotesSheetDeleteAllNotesButton => '刪除所有備註';

  @override
  String get readerNotesSheetNoteLabel => '備註';

  @override
  String get readerHighlightStyleYellow => '螢光筆（黃）';

  @override
  String get readerHighlightStylePink => '螢光筆（粉）';

  @override
  String get readerHighlightStyleBlue => '螢光筆（藍）';

  @override
  String get readerHighlightStyleUnderline => '底線';

  @override
  String readerNotesSheetDeleteAllHighlightsConfirm(int count) {
    return '確定要刪除全部劃線嗎？（共 $count 筆）';
  }

  @override
  String readerNotesSheetDeleteAllNotesConfirm(int count) {
    return '確定要刪除全部備註嗎？（共 $count 筆）';
  }

  @override
  String get readerFxlSettingsTitle => '⚙️ 漫畫版面設定';

  @override
  String get readerDualPageModeLabel => '雙頁模式';

  @override
  String get readerDualPageAutoTooltip => '自動（橫向雙頁）';

  @override
  String get readerDualPageAutoLabel => '自動';

  @override
  String get readerDualPageAlwaysTooltip => '永遠雙頁';

  @override
  String get readerDualPageAlwaysLabel => '雙頁';

  @override
  String get readerDualPageNeverTooltip => '永遠單頁';

  @override
  String get readerDualPageNeverLabel => '單頁';

  @override
  String get readerPageDirectionLabel => '翻頁方向';

  @override
  String get readerDualPageDirectionLtrTooltip => '左到右（LTR，美漫慣例）';

  @override
  String get readerDualPageDirectionLtrLabel => '左翻';

  @override
  String get readerDualPageDirectionRtlTooltip => '右到左（RTL，日漫慣例）';

  @override
  String get readerDualPageDirectionRtlLabel => '右翻';

  @override
  String get readerTextConversionOverrideLabel => '簡繁轉換覆寫';

  @override
  String get readerGlobalLabel => '全域';

  @override
  String get readerUseGlobalDefaultTooltip => '使用全域預設';

  @override
  String get readerTextConversionOriginalLabel => '原文';

  @override
  String get readerTextConversionTraditionalLabel => '繁體';

  @override
  String get readerTextConversionTraditionalTooltip => '轉換為繁體';

  @override
  String get readerTextConversionSimplifiedLabel => '簡體';

  @override
  String get readerTextConversionSimplifiedTooltip => '轉換為簡體';

  @override
  String get readerFullscreenModeLabel => '全螢幕模式';

  @override
  String get readerShowHeaderLabel => '顯示頁首';

  @override
  String get readerShowFooterLabel => '顯示頁尾';

  @override
  String get readerPdfSettingsTitle => '⚙️ PDF 版面設定';

  @override
  String get readerPdfSettingsTabDisplay => '顯示';

  @override
  String get readerPdfSettingsTabFilters => '濾鏡';

  @override
  String get readerPdfSettingsTabCrop => '裁切';

  @override
  String get readerPdfFitModeLabel => 'Fit 模式';

  @override
  String get readerPdfFitPageTooltip => 'Page-fit（整頁）';

  @override
  String get readerPdfFitPageLabel => '整頁';

  @override
  String get readerPdfFitWidthTooltip => 'Fit Width（頁寬）';

  @override
  String get readerPdfFitWidthLabel => '頁寬';

  @override
  String get readerPdfFitActualTooltip => '真實比例 1:1';

  @override
  String get readerPdfFitActualLabel => '原比';

  @override
  String get readerPdfDualPageCoverAloneLabel => '封面獨立顯示';

  @override
  String get readerPdfPageOrientationLabel => '頁面方向';

  @override
  String get readerPdfDirectionLtrTooltip => '左到右';

  @override
  String get readerPdfDirectionLtrLabel => '左翻';

  @override
  String get readerPdfDirectionRtlTooltip => '右到左（日漫慣例）';

  @override
  String get readerPdfDirectionRtlLabel => '右翻';

  @override
  String get readerPdfPageTurnAnimationLabel => '換頁動畫';

  @override
  String get readerPdfPageTurnAnimationSlide => '滑動';

  @override
  String get readerPdfPageTurnAnimationNone => '無';

  @override
  String get readerPdfContrastLabel => '對比度';

  @override
  String get readerPdfBrightnessLabel => '亮度';

  @override
  String get readerPdfBoldStrengthLabel => '加粗強度';

  @override
  String get readerPdfCropModeLabel => '裁切模式';

  @override
  String get readerPdfCropNoneTooltip => '不裁切';

  @override
  String get readerPdfCropNoneLabel => '不裁';

  @override
  String get readerPdfCropAutoTooltip => '智慧自動';

  @override
  String get readerPdfCropAutoLabel => '智慧';

  @override
  String get readerPdfCropManualLabel => '手動';

  @override
  String get readerPdfCropManualTooltip => '手動選區';

  @override
  String get readerSettingsTitle => '⚙️ 版面設定';

  @override
  String get readerSettingsTabText => '文字';

  @override
  String get readerSettingsTabBoundary => '邊界';

  @override
  String get readerSettingsTabPresentation => '呈現';

  @override
  String get readerSettingsTabPreferences => '預設集';

  @override
  String get readerSettingsFontSizeLabel => '字級';

  @override
  String get readerSettingsFontWeightLabel => '字重';

  @override
  String get readerSettingsLineHeightLabel => '行距';

  @override
  String get readerSettingsParagraphSpacingLabel => '段落間距';

  @override
  String get readerSettingsLetterSpacingLabel => '字距';

  @override
  String get readerSettingsDisableBookCssLabel => '停用書本 CSS';

  @override
  String get readerSettingsMarginTopLabel => '上邊界';

  @override
  String get readerSettingsMarginBottomLabel => '下邊界';

  @override
  String get readerSettingsMarginLeftLabel => '左邊界';

  @override
  String get readerSettingsMarginRightLabel => '右邊界';

  @override
  String get readerSettingsOverriddenBadge => '此書已覆寫';

  @override
  String get readerSettingsResetToBookStyleTooltip => '恢復本書原樣式';

  @override
  String get readerSettingsNotOverriddenTooltip => '跟隨本書原樣式，尚未調整';

  @override
  String get readerSettingsUseBookFontLabel => '使用書本內建字型';

  @override
  String get readerSettingsFontFamilyLabel => '字型';

  @override
  String get readerSettingsColumnCountLabel => '欄數';

  @override
  String get readerSettingsColumnAutoLabel => '自動';

  @override
  String get readerSettingsColumnSingleLabel => '單欄';

  @override
  String get readerSettingsColumnDoubleLabel => '雙欄';

  @override
  String get readerSettingsColumnSizeLabel => '欄位大小';

  @override
  String readerSettingsColumnSizeWithValueLabel(int size) {
    return '欄位大小 ${size}px';
  }

  @override
  String get readerSettingsTextAlignLabel => '文字對齊';

  @override
  String get readerSettingsTextAlignCenterLabel => '置中';

  @override
  String get readerSettingsTextAlignJustifyTooltip => '左右對齊';

  @override
  String get readerSettingsTextAlignJustifyLabel => '齊行';

  @override
  String get readerSettingsTextAlignStartTooltip => '起始邊對齊';

  @override
  String get readerSettingsTextAlignStartLabel => '起始';

  @override
  String get readerSettingsTextAlignEndTooltip => '結尾邊對齊';

  @override
  String get readerSettingsTextAlignEndLabel => '結尾';

  @override
  String get readerSettingsTextAlignLeftLabel => '靠左';

  @override
  String get readerSettingsTextAlignRightLabel => '靠右';

  @override
  String get readerSettingsWritingModeLabel => '排版方向模式';

  @override
  String get readerSettingsWritingModeBookTooltip => '採用書籍排版';

  @override
  String get readerSettingsWritingModeBookLabel => '書籍';

  @override
  String get readerSettingsWritingModeVerticalTooltip => '強制直排';

  @override
  String get readerSettingsWritingModeVerticalLabel => '直排';

  @override
  String get readerSettingsWritingModeHorizontalTooltip => '強制橫排';

  @override
  String get readerSettingsWritingModeHorizontalLabel => '橫排';

  @override
  String get readerSettingsPageTurnModeLabel => '翻頁模式覆寫';

  @override
  String get readerSettingsPageTurnPaginatedTooltip => '點擊翻頁';

  @override
  String get readerSettingsPageTurnPaginatedLabel => '點擊';

  @override
  String get readerSettingsPageTurnScrollTooltip => '滾動翻頁';

  @override
  String get readerSettingsPageTurnScrollLabel => '滾動';

  @override
  String get readerSettingsScreenOrientationLabel => '螢幕方向鎖定覆寫';

  @override
  String get readerSettingsOrientationAutoTooltip => '自動旋轉';

  @override
  String get readerSettingsOrientationAutoLabel => '自動';

  @override
  String get readerSettingsOrientationLock0Tooltip => '鎖定 0°';

  @override
  String get readerSettingsOrientationLock90Tooltip => '鎖定 90°';

  @override
  String get readerSettingsOrientationLock180Tooltip => '鎖定 180°';

  @override
  String get readerSettingsOrientationLock270Tooltip => '鎖定 270°';

  @override
  String get readerSettingsSaveAsPresetButton => '將目前設定存為新預設集';

  @override
  String get readerSettingsSavedPresetsLabel => '已儲存的預設集';

  @override
  String get readerSettingsCopyFromBookLabel => '從其他書籍複製';

  @override
  String get readerSettingsCopyToCurrentBookButton => '複製到本書';

  @override
  String get readerSettingsCopyToOtherBooksButton => '複製到其他書籍';

  @override
  String get readerSettingsResetPresetTitle => '系統預設';

  @override
  String get readerSettingsResetPresetSubtitle =>
      '移除本書所有字級/字重/行距/段落間距/字距覆寫，改用書本原始樣式';

  @override
  String get readerSettingsApplyButton => '套用';

  @override
  String get readerSettingsPresetDefaultValue => '預設';

  @override
  String get readerSettingsPresetSummaryAutoLabel => '自動';

  @override
  String readerSettingsPresetSummaryFormat(
    String fontSize,
    String lineHeight,
    String writingMode,
  ) {
    return '字級$fontSize・行距$lineHeight・$writingMode';
  }

  @override
  String get readerSettingsPresetEmptySlot => '（空）';

  @override
  String get readerSettingsApplyToOtherBooksTooltip => '套用到其他書籍';

  @override
  String get readerSettingsDeletePresetTooltip => '刪除';

  @override
  String get readerUnknownBookTitle => '未知書籍';

  @override
  String get readerSaveAsPresetUnavailableMessage => '暫時無法儲存預設集';

  @override
  String get readerSaveAsPresetFailedMessage => '另存為新預設集失敗';

  @override
  String get readerOverwritePresetPickerTitle => '選擇要覆蓋的預設集';

  @override
  String readerOverwritePresetOptionLabel(String name, String date) {
    return '$name（最後更新：$date）';
  }

  @override
  String get readerConfirmOverwriteTitle => '確認覆蓋';

  @override
  String readerOverwritePresetConfirmMessage(String name) {
    return '即將覆蓋預設集「$name」，此動作無法復原。';
  }

  @override
  String get readerConfirmApplyTitle => '確認套用';

  @override
  String readerApplyToOthersConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '即將覆蓋 $count 本書的版面設定，此動作無法復原。',
      one: '即將覆蓋 1 本書的版面設定，此動作無法復原。',
    );
    return '$_temp0';
  }

  @override
  String get readerApplyPresetFailedMessage => '套用版面設定失敗';

  @override
  String get readerConfirmDeleteTitle => '確認刪除';

  @override
  String readerDeletePresetConfirmMessage(String name) {
    return '即將刪除預設集「$name」，此動作無法復原。';
  }

  @override
  String get readerDeletePresetFailedMessage => '刪除預設集失敗';

  @override
  String get readerSearchUnavailableMessage => '搜尋功能暫時無法使用';

  @override
  String get readerOpenBookTimeoutMessage => '開書逾時，可能是系統 WebView 版本過舊或檔案異常';

  @override
  String get readerCopiedToClipboardMessage => '已複製到剪貼簿';

  @override
  String get readerTtsVoicePickerTitle => '朗讀語音';

  @override
  String get readerUnsupportedFormatMessage => '不支援的檔案格式';

  @override
  String get readerFailedToLoadBookMessage => '無法載入書籍';

  @override
  String readerTtsSleepTimerOptionMinutes(int minutes) {
    return '$minutes 分鐘';
  }

  @override
  String get readerTtsSleepTimerNoLimitLabel => '不限時';

  @override
  String get settingsScaffoldTitle => '設定';

  @override
  String get settingsLibraryTooltip => '書架';

  @override
  String get settingsSourceTooltip => '來源';

  @override
  String get settingsAppearanceSectionTitle => '外觀';

  @override
  String get settingsThemeLabel => '佈景';

  @override
  String get settingsThemeLockedHint => '這裡選的是關閉 E-Ink 後要恢復的主題';

  @override
  String settingsThemeDotSemanticsLabel(String themeName) {
    return '$themeName佈景';
  }

  @override
  String settingsThemeDotLockedSemanticsLabel(
    String themeName,
    String currentThemeName,
  ) {
    return '$themeName佈景，已鎖定，這裡選的是關閉 E-Ink 後要恢復的主題，目前選擇：$currentThemeName';
  }

  @override
  String get settingsThemeLight => '淺色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeSepia => '羊皮紙';

  @override
  String get settingsEinkModeLabel => 'E-Ink 高對比模式';

  @override
  String get settingsEinkModeSubtitle => '停用動畫與漸層，以純黑白高對比顯示，專為電子紙螢幕最佳化';

  @override
  String get settingsFontManagementLabel => '字型管理';

  @override
  String get settingsReadingSectionTitle => '閱讀';

  @override
  String get settingsReadingDefaultsLabel => '閱讀預設值';

  @override
  String get settingsNavZoneLabel => '導航熱區';

  @override
  String get settingsTtsDefaultsLabel => '朗讀語音與語速';

  @override
  String get settingsFullTextSearchUnavailableLabel => '全文檢索';

  @override
  String get settingsFullTextSearchUnavailableSubtitle => '本裝置不支援全文檢索';

  @override
  String get settingsFullTextSearchPdfLabel => 'PDF 全文檢索';

  @override
  String get settingsFullTextSearchPdfSubtitle => '部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容';

  @override
  String get settingsFullTextSearchRebuildIndexTooltip => '重建索引';

  @override
  String get settingsFullTextSearchFoliateLabel => '其他格式全文檢索';

  @override
  String get settingsFullTextSearchFoliateSubtitle => 'EPUB／TXT／KF8 等格式的背景索引建置';

  @override
  String get settingsSyncAccountSectionTitle => '同步與帳號';

  @override
  String get settingsSyncLabel => '同步';

  @override
  String get settingsCloudAccountLabel => '已連結的雲端匯入帳戶';

  @override
  String get settingsAboutSectionTitle => '關於';

  @override
  String get settingsAboutLabel => '關於';

  @override
  String get settingsReaderConsoleLogLabel => '閱讀器 Console Log';

  @override
  String get settingsConsoleLogInterceptLabel => 'Console Log 攔截';

  @override
  String get settingsConsoleLogInterceptSubtitle => '關閉後僅保留錯誤訊息，用於問題回報時的診斷紀錄';

  @override
  String get navZoneSettingsTitle => '導航熱區';

  @override
  String get navZoneSettingsPageTurnModeLabel => '翻頁方式';

  @override
  String get navZoneSettingsSimpleModeLabel => '簡單';

  @override
  String get navZoneSettingsCustomModeLabel => '自訂';

  @override
  String get navZoneSettingsShowDebugOverlayLabel => '顯示熱區輔助線';

  @override
  String get navZoneSettingsSaveCustomButton => '儲存自訂熱區設定';

  @override
  String get navZoneActionPreviousPage => '上一頁';

  @override
  String get navZoneActionNextPage => '下一頁';

  @override
  String get navZoneActionMenu => '選單';

  @override
  String get navZoneActionNone => '無動作';

  @override
  String get navZoneCustomValidationError => '至少需要 1 格設為「選單」，否則將無法退出沉浸模式';

  @override
  String get readingDefaultsTitle => '閱讀預設值';

  @override
  String get readingDefaultsVolumeKeyLabel => '音量鍵翻頁';

  @override
  String get readingDefaultsPageTurnModeSectionTitle => '翻頁模式';

  @override
  String get readingDefaultsPaginatedLabel => '點擊翻頁';

  @override
  String get readingDefaultsScrollLabel => '滾動翻頁';

  @override
  String get readingDefaultsScreenOrientationSectionTitle => '螢幕方向';

  @override
  String get readingDefaultsOrientationAutoLabel => '自動旋轉';

  @override
  String get readingDefaultsOrientationLock0Label => '鎖定 0°';

  @override
  String get readingDefaultsOrientationLock90Label => '鎖定 90°';

  @override
  String get readingDefaultsOrientationLock180Label => '鎖定 180°';

  @override
  String get readingDefaultsOrientationLock270Label => '鎖定 270°';

  @override
  String get readingDefaultsTextConversionSectionTitle => '簡繁轉換顯示';

  @override
  String get readingDefaultsTextConversionOriginalLabel => '原文';

  @override
  String get readingDefaultsTextConversionTraditionalLabel => '轉換為繁體';

  @override
  String get readingDefaultsTextConversionSimplifiedLabel => '轉換為簡體';

  @override
  String get readingDefaultsFullscreenLabel => '全螢幕模式';

  @override
  String get readingDefaultsOpenLastBookLabel => '啟動時開啟最後閱讀的那本書';

  @override
  String get readingDefaultsShowHeaderLabel => '顯示頁首';

  @override
  String get readingDefaultsShowFooterLabel => '顯示頁尾';

  @override
  String get ttsDefaultsTitle => '朗讀語音與語速';

  @override
  String get ttsDefaultsVoiceSectionTitle => '語音';

  @override
  String get ttsDefaultsVoiceUnavailableHint => '目前裝置未安裝或不支援語音選擇';

  @override
  String get ttsDefaultsSpeedSectionTitle => '語速';

  @override
  String get syncSettingsTitle => '同步';

  @override
  String get syncSettingsSyncFailedMessage => '同步失敗，請確認網路連線';

  @override
  String get syncSettingsNeverSynced => '尚未同步過';

  @override
  String syncSettingsLastSyncedAt(String formatted) {
    return '最後同步：$formatted';
  }

  @override
  String get syncSettingsConnectionFailedMessage => '連線失敗，請確認伺服器網址與帳號密碼是否正確';

  @override
  String syncSettingsLoggedInAs(String email) {
    return '已登入：$email';
  }

  @override
  String get syncSettingsManualSyncButton => '立即同步';

  @override
  String get syncSettingsLogoutButton => '登出';

  @override
  String get syncSettingsServerUrlLabel => '伺服器網址';

  @override
  String get syncSettingsPasswordLabel => '密碼';

  @override
  String get syncSettingsShowPasswordTooltip => '顯示密碼';

  @override
  String get syncSettingsHidePasswordTooltip => '隱藏密碼';

  @override
  String get syncSettingsConnectButton => '連線／登入';

  @override
  String get cloudAccountSettingsTitle => '已連結的雲端匯入帳戶';

  @override
  String cloudAccountSettingsLinkedEmail(String email) {
    return '已連結：$email';
  }

  @override
  String get cloudAccountSettingsUnlinkButton => '解除連結';

  @override
  String get cloudAccountSettingsUnlinkedText => '未連結';

  @override
  String get cloudAccountSettingsLinkButton => '連結';

  @override
  String get fontManagementTitle => '字型管理';

  @override
  String get fontNameSourceHanSans => '思源黑體';

  @override
  String get fontNameSourceHanSerif => '思源宋體';

  @override
  String get fontManagementUploadTooltip => '上傳字型';

  @override
  String get fontManagementBuiltInSectionLabel => '內建字型';

  @override
  String get fontManagementCustomSectionLabel => '自訂字型';

  @override
  String get fontManagementNoCustomFontsHint => '尚未上傳任何自訂字型';

  @override
  String get fontManagementRenameTooltip => '重新命名';

  @override
  String get fontManagementDeleteTooltip => '刪除';

  @override
  String get fontManagementRenameDialogTitle => '重新命名';

  @override
  String fontManagementDeleteConfirmTitle(String fontName) {
    return '確定要刪除「$fontName」嗎？';
  }

  @override
  String fontManagementDeleteConfirmMessage(int usageCount) {
    String _temp0 = intl.Intl.pluralLogic(
      usageCount,
      locale: localeName,
      other: '目前有 $usageCount 本書使用此字型，刪除後將自動改用預設字型',
      one: '目前有 1 本書使用此字型，刪除後將自動改用預設字型',
    );
    return '$_temp0';
  }

  @override
  String get fontManagementStatusNotDownloaded => '未下載';

  @override
  String get fontManagementStatusDownloaded => '已下載';

  @override
  String get fontManagementDownloadTooltip => '下載';

  @override
  String get fontManagementCancelDownloadTooltip => '取消下載';

  @override
  String get fontManagementRetryTooltip => '重試';

  @override
  String get fontManagementDownloadableDeleteConfirmMessage =>
      '刪除後可以隨時重新下載。使用這款字型的書會暫時改用書本或系統字型，重新下載後自動恢復。';

  @override
  String get fontDownloadErrorNetwork => '無法連線，請檢查網路後重試';

  @override
  String fontDownloadErrorHttp(int statusCode) {
    return '伺服器錯誤（$statusCode），請稍後重試';
  }

  @override
  String get fontDownloadErrorIntegrity => '檔案不完整或已損毀，請重試';

  @override
  String get fontDownloadErrorStorage => '無法儲存檔案，請確認儲存空間是否足夠';

  @override
  String fontManagementUploadBothMessage(int addedCount, int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      addedCount,
      locale: localeName,
      other: '已新增 $addedCount 款字型',
      one: '已新增 1 款字型',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount 款已存在已跳過',
      one: '1 款已存在已跳過',
    );
    return '$_temp0，$_temp1';
  }

  @override
  String fontManagementUploadAddedOnlyMessage(int addedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      addedCount,
      locale: localeName,
      other: '已新增 $addedCount 款字型',
      one: '已新增 1 款字型',
    );
    return '$_temp0';
  }

  @override
  String fontManagementUploadSkippedOnlyMessage(int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount 款字型已存在，已跳過',
      one: '1 款字型已存在，已跳過',
    );
    return '$_temp0';
  }

  @override
  String get readerConsoleLogTitle => '閱讀器 Console Log';

  @override
  String get readerConsoleLogCopyAllTooltip => '複製全部';

  @override
  String get readerConsoleLogClearTooltip => '清空';

  @override
  String get readerConsoleLogEmptyHint => '目前沒有記錄';

  @override
  String get readerConsoleLogCopiedMessage => '已複製全部記錄到剪貼簿';

  @override
  String get aboutScreenTitle => '關於';

  @override
  String get aboutScreenVersionLabel => '版本';

  @override
  String get aboutScreenBuildTimeLabel => '編譯時間';

  @override
  String get aboutScreenWebViewVersionLabel => '系統 WebView 版本';

  @override
  String get aboutScreenViewLicensesButton => '開源授權清單';

  @override
  String get aboutScreenLoadingText => '讀取中...';

  @override
  String get aboutScreenFailedToLoadVersionMessage => '無法取得版本號';

  @override
  String get aboutScreenUnavailableText => '無法取得';

  @override
  String get remoteServerListTitle => '遠端書庫';

  @override
  String get remoteServerListAddTooltip => '新增站點';

  @override
  String get remoteServerListEmptyState => '尚未新增任何遠端書庫站點';

  @override
  String get remoteServerListEditTooltip => '編輯';

  @override
  String get remoteServerListDeleteTooltip => '刪除';

  @override
  String get remoteServerListDeleteConfirmTitle => '刪除站點';

  @override
  String get remoteServerListDeleteConfirmButton => '刪除';

  @override
  String remoteServerListDeleteConfirmMessage(String name) {
    return '確定要刪除站點「$name」嗎？此動作無法復原。';
  }

  @override
  String get remoteServerListDeleteBlockedTitle => '無法刪除站點';

  @override
  String remoteServerListDeleteBlockedMessage(int count, String titles) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '這個站點還有 $count 本書僅有雲端紀錄、尚未下載：',
      one: '這個站點還有 1 本書僅有雲端紀錄、尚未下載：',
    );
    return '$_temp0\n$titles\n\n請先於書架移除這些書籍，或重新下載後再刪除站點。';
  }

  @override
  String get remoteServerListDeleteBlockedConfirmButton => '了解';

  @override
  String get remoteServerListDeleteFailedMessage => '刪除站點失敗，請稍後再試';

  @override
  String get remoteServerFormTitleAdd => '新增站點';

  @override
  String get remoteServerFormTitleEdit => '編輯站點';

  @override
  String get remoteServerFormNameLabel => '站點名稱';

  @override
  String get remoteServerFormBaseUrlLabel => '伺服器網址';

  @override
  String get remoteServerFormTypeOpds => '標準 OPDS';

  @override
  String get remoteServerFormTypeCalibreServer => '原生 Calibre Content Server';

  @override
  String get remoteServerFormUsernameLabel => '帳號（留空代表匿名連線）';

  @override
  String get remoteServerFormPasswordLabelEditing =>
      '密碼（留空＝沿用既有密碼；清空上方帳號欄位則一併清除密碼）';

  @override
  String get remoteServerFormPasswordLabel => '密碼';

  @override
  String get remoteServerFormPasswordShowTooltip => '顯示密碼';

  @override
  String get remoteServerFormPasswordHideTooltip => '隱藏密碼';

  @override
  String get remoteServerFormAllowInsecureLabel => '允許不安全連線（自簽憑證／純 HTTP）';

  @override
  String get remoteServerFormValidationMissingFields => '請填寫站點名稱與網址';

  @override
  String get remoteServerFormValidationInvalidUrl =>
      '請輸入有效的伺服器網址（需以 http:// 或 https:// 開頭）';

  @override
  String get remoteServerFormSaveFailedMessage => '儲存失敗，請稍後再試';

  @override
  String get remoteServerFormTestSuccess => '連線成功';

  @override
  String get remoteServerFormTestFailed => '連線失敗，請檢查網址/帳密/憑證設定';

  @override
  String get remoteServerFormTestConnectionButton => '測試連線';

  @override
  String get remoteServerFormSaveButton => '儲存';

  @override
  String formatSelectionDialogTitle(String title) {
    return '選擇格式：$title';
  }

  @override
  String get formatSelectionDialogUnsupportedFormat => '不支援的格式';

  @override
  String get cloudDuplicateDialogTitle => '重複的書籍';

  @override
  String get cloudDuplicateDialogConfirmButton => '仍要建立';

  @override
  String get remoteCatalogLoadFailedMessage => '載入失敗，請檢查網路連線或站點設定';

  @override
  String get remoteCatalogDownloadSelectedTooltip => '下載已選取';

  @override
  String remoteCatalogDuplicateConfirmMessage(String title) {
    return '「$title」之前匯入過了，仍要建立新的一份嗎？';
  }

  @override
  String remoteCatalogQueuedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個檔案',
      one: '1 個檔案',
    );
    return '已加入下載佇列（$_temp0），可至「來源」畫面查看進度';
  }

  @override
  String get remoteCatalogEinkPrevPageButton => '上一頁';

  @override
  String get remoteCatalogEinkNextPageButton => '下一頁';

  @override
  String get remoteCatalogLoadMoreButton => '載入更多';

  @override
  String get remoteCatalogDuplicateDialogTitle => '重複的書籍';

  @override
  String get remoteCatalogDuplicateDialogConfirmButton => '仍要建立';

  @override
  String get wifiTransferLeaveConfirmTitle => '目前尚有檔案正在傳輸';

  @override
  String get wifiTransferLeaveConfirmMessage => '離開將中斷連線，是否確定離開？';

  @override
  String get wifiTransferLeaveConfirmButton => '確定離開';

  @override
  String get wifiTransferTitle => 'WiFi 傳書';

  @override
  String get wifiTransferInstructionText => '在同一個 WiFi 下，用瀏覽器打開以下網址：';

  @override
  String wifiTransferActiveCountText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '正在傳輸中（$count 個檔案）…',
      one: '正在傳輸中（1 個檔案）…',
    );
    return '$_temp0';
  }

  @override
  String get wifiTransferUnavailableText => '請連線至 WiFi 或開啟手機熱點';

  @override
  String get wifiTransferManualOverrideButton => '我確定目前是用手機熱點';

  @override
  String get wifiTransferNoInterfacesText => '找不到任何可用網路介面';

  @override
  String get downloadQueueTitle => '下載佇列';

  @override
  String get downloadQueueCancelTooltip => '取消';

  @override
  String get downloadQueueRetryTooltip => '重試';

  @override
  String get downloadQueueDismissTooltip => '從清單移除';

  @override
  String get downloadQueueStatusPending => '待機';

  @override
  String get downloadQueueStatusDownloading => '下載中';

  @override
  String get downloadQueueStatusCheckingDuplicate => '比對中';

  @override
  String get downloadQueueStatusDone => '完成';

  @override
  String get downloadQueueStatusDuplicateSkipped => '重複已略過';

  @override
  String get downloadQueueStatusFailed => '失敗';

  @override
  String get downloadQueueStatusCancelled => '已取消';

  @override
  String downloadQueueDuplicateConfirmMessage(String name) {
    return '偵測到「$name」與本機已有的一本書內容相同，仍要建立新的一份嗎？';
  }

  @override
  String get sourcesHomeTitle => '來源';

  @override
  String get sourcesHomeLibraryTooltip => '書架';

  @override
  String get sourcesHomeSettingsTooltip => '設定';

  @override
  String get sourcesHomeLocalSection => '本機';

  @override
  String get sourcesHomePickFilesTitle => '選擇檔案（可多選）';

  @override
  String get sourcesHomePickFolderTitle => '選擇資料夾';

  @override
  String get sourcesHomeWifiTransferTile => 'WiFi 傳書';

  @override
  String get sourcesHomeConnectedServicesSection => '已連結服務';

  @override
  String get sourcesHomeCloudNotLinkedSubtitle => '尚未連結，請至設定畫面連結帳戶';

  @override
  String get sourcesHomeRemoteLibraryTitle => '遠端書庫（OPDS）';

  @override
  String get sourcesHomeRemoteLibraryNotConfiguredSubtitle => '尚未設定遠端書庫伺服器';

  @override
  String get libraryImportFolderDialogTitle => '匯入資料夾';

  @override
  String get libraryImportFolderAutoGroupLabel => '依資料夾名稱自動建立分類';

  @override
  String get libraryImportFolderConfirmButton => '匯入';

  @override
  String libraryImportResultBothMessage(int importedCount, int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      importedCount,
      locale: localeName,
      other: '已匯入 $importedCount 本',
      one: '已匯入 1 本',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount 本已存在，已跳過',
      one: '1 本已存在，已跳過',
    );
    return '$_temp0，$_temp1';
  }

  @override
  String libraryImportResultImportedOnlyMessage(int importedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      importedCount,
      locale: localeName,
      other: '已匯入 $importedCount 本書',
      one: '已匯入 1 本書',
    );
    return '$_temp0';
  }

  @override
  String libraryImportResultSkippedOnlyMessage(int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount 本已存在，已跳過',
      one: '1 本已存在，已跳過',
    );
    return '$_temp0';
  }

  @override
  String get layoutPresetBookPickerTitleMulti => '選擇書籍（可複選）';

  @override
  String get layoutPresetBookPickerTitleSingle => '選擇書籍';

  @override
  String get layoutPresetBookPickerSearchHint => '搜尋書名或作者';

  @override
  String get layoutPresetBookPickerEmptyBooks => '沒有可選擇的流式 EPUB 書籍';

  @override
  String get layoutPresetBookPickerNoMatch => '找不到符合的書籍';

  @override
  String get layoutPresetNameDialogTitle => '為預設集命名';

  @override
  String get layoutPresetNameDialogEmptyError => '名稱不可為空';

  @override
  String get layoutPresetNameDialogSaveButton => '儲存';

  @override
  String markdownExportTitle(String bookTitle) {
    return '# 閱讀筆記：《$bookTitle》';
  }

  @override
  String markdownExportAuthorLabel(String author) {
    return '*   **作者**：$author';
  }

  @override
  String get markdownExportUnknownAuthor => '未知作者';

  @override
  String markdownExportProgressLabel(int percent) {
    return '*   **閱讀進度**：$percent%';
  }

  @override
  String markdownExportTimeLabel(String time) {
    return '*   **導出時間**：$time';
  }

  @override
  String markdownExportBookmarksSection(int count) {
    return '## 🔖 書籤清單 ($count)';
  }

  @override
  String get markdownExportNoBookmarks => '*(尚未加入書籤)*';

  @override
  String markdownExportAnnotationsSection(int count) {
    return '## ✏️ 劃線與個人備註 ($count)';
  }

  @override
  String get markdownExportNoAnnotations => '*(尚未加入任何劃線或備註)*';

  @override
  String markdownExportAnnotationHeading(String label, String position) {
    return '### 📌 $label（位置：$position）';
  }

  @override
  String bookmarkDefaultNamePdfPage(int page) {
    return '第 $page 頁';
  }

  @override
  String bookmarkDefaultNamePercent(int percent) {
    return '$percent% 處';
  }

  @override
  String get bookmarkDefaultNameFallback => '書籤';

  @override
  String get ttsNotificationChannelName => '朗讀播放中';

  @override
  String get ttsVoiceSystemDefault => '系統預設語音';

  @override
  String get remoteCatalogUnnamedCategory => '未命名分類';

  @override
  String get remoteCatalogUnknownBookTitle => '未知書名';

  @override
  String get wifiPageTitle => 'elinkBook WiFi 傳書';

  @override
  String get wifiPageUploadHeading => '上傳書籍';

  @override
  String get wifiPageDropzoneText => '拖放檔案到此處，或';

  @override
  String get wifiPageChooseFile => '選擇檔案';

  @override
  String get wifiPageDownloadHeading => '下載書籍';

  @override
  String get wifiPageSearchPlaceholder => '搜尋書名…';

  @override
  String get wifiPageSelectPage => '全選目前頁';

  @override
  String get wifiPageClearSelection => '清除勾選';

  @override
  String wifiPageSelectedCount(String count) {
    return '已勾選 $count 本';
  }

  @override
  String get wifiPageLoading => '載入中…';

  @override
  String get wifiPagePrevPage => '上一頁';

  @override
  String get wifiPageNextPage => '下一頁';

  @override
  String wifiPagePageInfo(String page, String total) {
    return '第 $page / $total 頁';
  }

  @override
  String get wifiPageDownloadSelected => '下載已勾選書籍';

  @override
  String get wifiPageNoBooks => '目前沒有可下載的書籍';

  @override
  String get wifiPageNoMatch => '查無符合條件的書籍';

  @override
  String get wifiPageLoadFailed => '無法載入書籍清單';

  @override
  String wifiPageTotalBooks(String count) {
    return '共 $count 本書籍';
  }

  @override
  String wifiPageMatchStats(String matched, String total) {
    return '符合 $matched 本 / 共 $total 本';
  }

  @override
  String get wifiPageSelectAtLeastOne => '請至少勾選一本書';

  @override
  String get wifiPageDownloading => '下載中…';

  @override
  String wifiPageDownloadTriggered(String count) {
    return '已觸發全部下載（共 $count 本）';
  }

  @override
  String get wifiPageOutcomeImported => '已匯入';

  @override
  String get wifiPageOutcomeDuplicateSkipped => '已存在，已略過';

  @override
  String get wifiPageOutcomeUnsupportedFormat => '格式不支援';

  @override
  String get wifiPageOutcomeFailed => '匯入失敗';

  @override
  String wifiPageUploadResultLine(String name, String outcome) {
    return '$name：$outcome';
  }

  @override
  String get wifiPageUnknownFileName => '(未知檔名)';

  @override
  String get wifiPageUploadPreparing => '準備上傳…';

  @override
  String get wifiPageUploading => '正在上傳…';

  @override
  String wifiPageUploadingPercent(String percent) {
    return '正在上傳… ($percent%)';
  }

  @override
  String get wifiPageUploadProcessing => '上傳完成，手機端處理與匯入中，請稍候…';

  @override
  String get wifiPageUnknownSize => '未知';

  @override
  String wifiPageUploadFailedServer(String status) {
    return '上傳失敗：伺服器回應錯誤 ($status)';
  }

  @override
  String get wifiPageUploadFailedParse => '上傳失敗：無法解析伺服器回應';

  @override
  String get wifiPageUploadFailedNetwork => '上傳失敗：網路錯誤';

  @override
  String get wifiPageUploadAborted => '上傳已中斷';

  @override
  String get wifiPageUploadTimeout => '上傳逾時';
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
  String get settingsLanguageZhTW => '正體中文';

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
  String libraryGroupNameAlreadyExistsError(String name) {
    return '分类「$name」已存在，请使用其他名称';
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

  @override
  String get libraryBackButtonTooltip => '返回上层';

  @override
  String get libraryShelfTitle => '书架';

  @override
  String get librarySortViewTooltip => '排序与检视';

  @override
  String get librarySortByLastRead => '最后阅读';

  @override
  String get librarySortByCreateTime => '建立时间';

  @override
  String get librarySortByAuthor => '作者';

  @override
  String get librarySortByTitle => '书名';

  @override
  String get libraryToggleViewToList => '切换为列表';

  @override
  String get libraryToggleViewToShelf => '切换为书架';

  @override
  String get libraryManageGroupsMenuItem => '管理分类...';

  @override
  String get librarySourceTooltip => '来源';

  @override
  String get librarySettingsTooltip => '设置';

  @override
  String get libraryCancelSelectionTooltip => '取消选取';

  @override
  String librarySelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选取 $count 本',
      one: '已选取 1 本',
    );
    return '$_temp0';
  }

  @override
  String get libraryMoveToGroupTooltip => '移动到分类';

  @override
  String get libraryForceFxlTooltip => '强制 FXL';

  @override
  String get libraryRestoreAutoLayoutTooltip => '恢复自动判断';

  @override
  String get libraryDeleteTooltip => '删除';

  @override
  String get libraryRemoveLocalCacheTooltip => '移除本机缓存';

  @override
  String get libraryEmptyStateMessage => '尚未导入书籍';

  @override
  String get libraryEmptyStateImportButton => '导入书籍';

  @override
  String get librarySearchHint => '搜索书名或作者...';

  @override
  String get libraryContentSearchEntryLabel => '搜索书本内容';

  @override
  String get libraryNoMatchingBooks => '找不到符合的书籍';

  @override
  String get libraryDeleteBooksDialogTitle => '删除书籍';

  @override
  String libraryDeleteBooksConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '将删除已选取的 $count 本书籍，并一并删除其书签、划线与备注，此操作无法恢复。确定要删除吗？',
      one: '将删除已选取的 1 本书籍，并一并删除其书签、划线与备注，此操作无法恢复。确定要删除吗？',
    );
    return '$_temp0';
  }

  @override
  String get libraryDeleteBooksConfirmButton => '删除';

  @override
  String get libraryRedownloadAction => '重新下载';

  @override
  String libraryRedownloadConfirmMessage(String title) {
    return '即将重新下载「$title」，确定要继续吗？';
  }

  @override
  String libraryRedownloadConfirmMessageMobileData(String title) {
    return '即将重新下载「$title」，目前使用移动数据连接，可能产生流量费用，确定要继续吗？';
  }

  @override
  String get libraryRemoteDisabledMessage => '远程书库功能未启用，无法重新下载';

  @override
  String get libraryRemoteServerNotFoundMessage => '找不到对应的远程书库站点';

  @override
  String get libraryRedownloadFailedMessage => '重新下载失败，请稍后再试';

  @override
  String libraryRemoveCacheConfirmMessage(String title) {
    return '将移除「$title」的本机文件，书籍记录与阅读进度会保留，之后可重新下载。确定要移除吗？';
  }

  @override
  String get libraryRemoveCacheConfirmButton => '移除';

  @override
  String get libraryGroupBadgeLabel => '分类';

  @override
  String libraryGroupTileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 本',
      one: '1 本',
    );
    return '$_temp0';
  }

  @override
  String get libraryBookMenuTooltip => '更多';

  @override
  String get libraryContinueReadingLabel => '继续阅读';

  @override
  String get libraryBookNotDownloaded => '尚未下载';

  @override
  String get libraryUnknownFileSize => '未知大小';

  @override
  String get libraryLoadingEllipsis => '读取中...';

  @override
  String libraryDetailAuthorLabel(String author) {
    return '作者：$author';
  }

  @override
  String get libraryUnknownAuthor => '未知';

  @override
  String libraryDetailFormatLabel(String format) {
    return '格式：$format';
  }

  @override
  String libraryDetailFileSizeLabel(String size) {
    return '文件大小：$size';
  }

  @override
  String libraryDetailProgressLabel(String progress) {
    return '进度：$progress';
  }

  @override
  String libraryDetailLastReadLabel(String date) {
    return '最后阅读：$date';
  }

  @override
  String get libraryNeverRead => '尚未阅读';

  @override
  String get libraryLayoutOverrideTitle => '排版覆盖';

  @override
  String get libraryLayoutOverrideWritingModeLabel => '排版方向';

  @override
  String get libraryLayoutOverrideWritingModeDefault => '使用书籍排版';

  @override
  String get libraryLayoutOverrideWritingModeHorizontal => '横排';

  @override
  String get libraryLayoutOverrideWritingModeVertical => '竖排';

  @override
  String get libraryLayoutOverridePageTurnModeLabel => '翻页模式';

  @override
  String get libraryLayoutOverridePageTurnModeDefault => '使用全局默认';

  @override
  String get libraryLayoutOverridePageTurnModePaginated => '分页';

  @override
  String get libraryLayoutOverridePageTurnModeScroll => '滚动';

  @override
  String get libraryLayoutOverrideSaveButton => '保存';

  @override
  String get readerBackTooltip => '返回';

  @override
  String get readerSearchTooltip => '搜索内文';

  @override
  String get readerHideToolbarTooltip => '隐藏工具栏';

  @override
  String get readerShowToolbarTooltip => '显示工具栏';

  @override
  String get readerTocTooltip => '目录';

  @override
  String get readerBookmarkAddedTooltip => '已加入此页书签';

  @override
  String get readerBookmarkAddTooltip => '加入此页书签';

  @override
  String get readerAnnotationsTooltip => '划线笔记';

  @override
  String get readerLayoutTooltip => '版面';

  @override
  String get readerTtsTooltip => '朗读';

  @override
  String get readerPagingPreviousTooltip => '上一页';

  @override
  String get readerPagingNextTooltip => '下一页';

  @override
  String get readerPdfNoPagesAvailable => '无可用页面';

  @override
  String get readerNoteDialogSaveButton => '保存';

  @override
  String get readerNoteDialogDefaultTitle => '备注';

  @override
  String get readerAnnotationUnderlineTooltip => '底线';

  @override
  String get readerAnnotationCopyTooltip => '复制';

  @override
  String get readerAnnotationEditNoteTooltip => '编辑备注';

  @override
  String get readerAnnotationAddNoteTooltip => '新增备注';

  @override
  String get readerAnnotationDeleteHighlightAndNote => '删除划线与备注';

  @override
  String get readerAnnotationDeleteHighlight => '删除划线';

  @override
  String get readerAnnotationDeleteNote => '删除备注';

  @override
  String get readerPdfSearchHint => '搜索文字…';

  @override
  String get readerPdfSearchNoMatches => '找不到符合的文字';

  @override
  String get readerPdfSearchPreviousTooltip => '上一个';

  @override
  String get readerPdfSearchNextTooltip => '下一个';

  @override
  String readerPositionConflictTitle(String bookTitle) {
    return '“$bookTitle”的阅读进度不一致';
  }

  @override
  String readerPositionConflictMessage(String local, String remote) {
    return '侦测到另一台装置也更新过这本书的阅读进度，请选择要保留哪一边：\n\n本机：$local\n云端：$remote';
  }

  @override
  String readerPositionConflictPdfLocation(int page, int percent) {
    return '第 $page 页（进度 $percent%）';
  }

  @override
  String readerPositionConflictEpubLocation(int percent) {
    return '进度 $percent%';
  }

  @override
  String get readerPositionConflictKeepCloud => '保留云端';

  @override
  String get readerPositionConflictKeepLocal => '保留本机';

  @override
  String get readerTocTitle => '📖 目录';

  @override
  String get readerTocEmptyMessage => '本书无目录资料';

  @override
  String get readerTocTabChapters => '章节目录';

  @override
  String get readerTocTabThumbnails => '缩图';

  @override
  String get readerTocTabSearch => '搜索';

  @override
  String get readerFeatureComingSoon => '此功能将于后续版本提供';

  @override
  String get readerTtsCbzUnsupportedTooltip => 'CBZ 为纯图像格式，不支持语音朗读';

  @override
  String get readerTtsPreviousTooltip => '上一句';

  @override
  String get readerTtsPauseTooltip => '暂停朗读';

  @override
  String get readerTtsPlayTooltip => '开始朗读';

  @override
  String get readerTtsNextTooltip => '下一句';

  @override
  String readerTtsSpeedTooltip(String speed) {
    return '朗读语速：${speed}x（点击切换）';
  }

  @override
  String get readerTtsVoiceTooltip => '选择语音';

  @override
  String get readerTtsSleepTimerLabel => '定时';

  @override
  String readerTtsSleepTimerLabelWithMinutes(int minutes) {
    return '定时 $minutes 分';
  }

  @override
  String get readerTtsCollapseLabel => '收起';

  @override
  String get readerTtsExpandLabel => '展开';

  @override
  String get readerTtsStopLabel => '停止';

  @override
  String get readerNotesSheetTitle => '笔记';

  @override
  String get readerNotesSheetExportMarkdownTooltip => '导出为 Markdown';

  @override
  String get readerNotesSheetTabBookmarks => '书签';

  @override
  String get readerNotesSheetTabAnnotations => '划线与备注';

  @override
  String get readerNotesSheetDeleteAllBookmarksTooltip => '删除该书所有书签';

  @override
  String get readerNotesSheetRenameBookmarkTitle => '重新命名书签';

  @override
  String get readerDeleteConfirmButton => '删除';

  @override
  String readerNotesSheetDeleteAllBookmarksConfirm(int count) {
    return '确定要删除全部书签吗？（共 $count 笔）';
  }

  @override
  String get readerNotesSheetRenameTooltip => '重新命名';

  @override
  String get readerNotesSheetDeleteItemTooltip => '删除';

  @override
  String get readerNotesSheetNoAnnotationsPlaceholder => '尚无划线或备注';

  @override
  String get readerNotesSheetDeleteAllHighlightsButton => '删除所有划线';

  @override
  String get readerNotesSheetDeleteAllNotesButton => '删除所有备注';

  @override
  String get readerNotesSheetNoteLabel => '备注';

  @override
  String get readerHighlightStyleYellow => '萤光笔（黄）';

  @override
  String get readerHighlightStylePink => '萤光笔（粉）';

  @override
  String get readerHighlightStyleBlue => '萤光笔（蓝）';

  @override
  String get readerHighlightStyleUnderline => '底线';

  @override
  String readerNotesSheetDeleteAllHighlightsConfirm(int count) {
    return '确定要删除全部划线吗？（共 $count 笔）';
  }

  @override
  String readerNotesSheetDeleteAllNotesConfirm(int count) {
    return '确定要删除全部备注吗？（共 $count 笔）';
  }

  @override
  String get readerFxlSettingsTitle => '⚙️ 漫画版面设定';

  @override
  String get readerDualPageModeLabel => '双页模式';

  @override
  String get readerDualPageAutoTooltip => '自动（横向双页）';

  @override
  String get readerDualPageAutoLabel => '自动';

  @override
  String get readerDualPageAlwaysTooltip => '永远双页';

  @override
  String get readerDualPageAlwaysLabel => '双页';

  @override
  String get readerDualPageNeverTooltip => '永远单页';

  @override
  String get readerDualPageNeverLabel => '单页';

  @override
  String get readerPageDirectionLabel => '翻页方向';

  @override
  String get readerDualPageDirectionLtrTooltip => '左到右（LTR，美漫惯例）';

  @override
  String get readerDualPageDirectionLtrLabel => '左翻';

  @override
  String get readerDualPageDirectionRtlTooltip => '右到左（RTL，日漫惯例）';

  @override
  String get readerDualPageDirectionRtlLabel => '右翻';

  @override
  String get readerTextConversionOverrideLabel => '简繁转换覆盖';

  @override
  String get readerGlobalLabel => '全局';

  @override
  String get readerUseGlobalDefaultTooltip => '使用全局预设';

  @override
  String get readerTextConversionOriginalLabel => '原文';

  @override
  String get readerTextConversionTraditionalLabel => '繁体';

  @override
  String get readerTextConversionTraditionalTooltip => '转换为繁体';

  @override
  String get readerTextConversionSimplifiedLabel => '简体';

  @override
  String get readerTextConversionSimplifiedTooltip => '转换为简体';

  @override
  String get readerFullscreenModeLabel => '全屏模式';

  @override
  String get readerShowHeaderLabel => '显示页首';

  @override
  String get readerShowFooterLabel => '显示页尾';

  @override
  String get readerPdfSettingsTitle => '⚙️ PDF 版面设定';

  @override
  String get readerPdfSettingsTabDisplay => '显示';

  @override
  String get readerPdfSettingsTabFilters => '滤镜';

  @override
  String get readerPdfSettingsTabCrop => '裁切';

  @override
  String get readerPdfFitModeLabel => 'Fit 模式';

  @override
  String get readerPdfFitPageTooltip => 'Page-fit（整页）';

  @override
  String get readerPdfFitPageLabel => '整页';

  @override
  String get readerPdfFitWidthTooltip => 'Fit Width（页宽）';

  @override
  String get readerPdfFitWidthLabel => '页宽';

  @override
  String get readerPdfFitActualTooltip => '真实比例 1:1';

  @override
  String get readerPdfFitActualLabel => '原比';

  @override
  String get readerPdfDualPageCoverAloneLabel => '封面独立显示';

  @override
  String get readerPdfPageOrientationLabel => '页面方向';

  @override
  String get readerPdfDirectionLtrTooltip => '左到右';

  @override
  String get readerPdfDirectionLtrLabel => '左翻';

  @override
  String get readerPdfDirectionRtlTooltip => '右到左（日漫惯例）';

  @override
  String get readerPdfDirectionRtlLabel => '右翻';

  @override
  String get readerPdfPageTurnAnimationLabel => '换页动画';

  @override
  String get readerPdfPageTurnAnimationSlide => '滑动';

  @override
  String get readerPdfPageTurnAnimationNone => '无';

  @override
  String get readerPdfContrastLabel => '对比度';

  @override
  String get readerPdfBrightnessLabel => '亮度';

  @override
  String get readerPdfBoldStrengthLabel => '加粗强度';

  @override
  String get readerPdfCropModeLabel => '裁切模式';

  @override
  String get readerPdfCropNoneTooltip => '不裁切';

  @override
  String get readerPdfCropNoneLabel => '不裁';

  @override
  String get readerPdfCropAutoTooltip => '智能自动';

  @override
  String get readerPdfCropAutoLabel => '智能';

  @override
  String get readerPdfCropManualLabel => '手动';

  @override
  String get readerPdfCropManualTooltip => '手动选区';

  @override
  String get readerSettingsTitle => '⚙️ 版面设定';

  @override
  String get readerSettingsTabText => '文字';

  @override
  String get readerSettingsTabBoundary => '边界';

  @override
  String get readerSettingsTabPresentation => '呈现';

  @override
  String get readerSettingsTabPreferences => '预设集';

  @override
  String get readerSettingsFontSizeLabel => '字级';

  @override
  String get readerSettingsFontWeightLabel => '字重';

  @override
  String get readerSettingsLineHeightLabel => '行距';

  @override
  String get readerSettingsParagraphSpacingLabel => '段落间距';

  @override
  String get readerSettingsLetterSpacingLabel => '字距';

  @override
  String get readerSettingsDisableBookCssLabel => '停用书本 CSS';

  @override
  String get readerSettingsMarginTopLabel => '上边界';

  @override
  String get readerSettingsMarginBottomLabel => '下边界';

  @override
  String get readerSettingsMarginLeftLabel => '左边界';

  @override
  String get readerSettingsMarginRightLabel => '右边界';

  @override
  String get readerSettingsOverriddenBadge => '此书已覆盖';

  @override
  String get readerSettingsResetToBookStyleTooltip => '恢复本书原样式';

  @override
  String get readerSettingsNotOverriddenTooltip => '跟随本书原样式，尚未调整';

  @override
  String get readerSettingsUseBookFontLabel => '使用书本内建字体';

  @override
  String get readerSettingsFontFamilyLabel => '字体';

  @override
  String get readerSettingsColumnCountLabel => '栏数';

  @override
  String get readerSettingsColumnAutoLabel => '自动';

  @override
  String get readerSettingsColumnSingleLabel => '单栏';

  @override
  String get readerSettingsColumnDoubleLabel => '双栏';

  @override
  String get readerSettingsColumnSizeLabel => '栏位大小';

  @override
  String readerSettingsColumnSizeWithValueLabel(int size) {
    return '栏位大小 ${size}px';
  }

  @override
  String get readerSettingsTextAlignLabel => '文字对齐';

  @override
  String get readerSettingsTextAlignCenterLabel => '置中';

  @override
  String get readerSettingsTextAlignJustifyTooltip => '左右对齐';

  @override
  String get readerSettingsTextAlignJustifyLabel => '齐行';

  @override
  String get readerSettingsTextAlignStartTooltip => '起始边对齐';

  @override
  String get readerSettingsTextAlignStartLabel => '起始';

  @override
  String get readerSettingsTextAlignEndTooltip => '结尾边对齐';

  @override
  String get readerSettingsTextAlignEndLabel => '结尾';

  @override
  String get readerSettingsTextAlignLeftLabel => '靠左';

  @override
  String get readerSettingsTextAlignRightLabel => '靠右';

  @override
  String get readerSettingsWritingModeLabel => '排版方向模式';

  @override
  String get readerSettingsWritingModeBookTooltip => '采用书籍排版';

  @override
  String get readerSettingsWritingModeBookLabel => '书籍';

  @override
  String get readerSettingsWritingModeVerticalTooltip => '强制直排';

  @override
  String get readerSettingsWritingModeVerticalLabel => '直排';

  @override
  String get readerSettingsWritingModeHorizontalTooltip => '强制横排';

  @override
  String get readerSettingsWritingModeHorizontalLabel => '横排';

  @override
  String get readerSettingsPageTurnModeLabel => '翻页模式覆盖';

  @override
  String get readerSettingsPageTurnPaginatedTooltip => '点击翻页';

  @override
  String get readerSettingsPageTurnPaginatedLabel => '点击';

  @override
  String get readerSettingsPageTurnScrollTooltip => '滚动翻页';

  @override
  String get readerSettingsPageTurnScrollLabel => '滚动';

  @override
  String get readerSettingsScreenOrientationLabel => '屏幕方向锁定覆盖';

  @override
  String get readerSettingsOrientationAutoTooltip => '自动旋转';

  @override
  String get readerSettingsOrientationAutoLabel => '自动';

  @override
  String get readerSettingsOrientationLock0Tooltip => '锁定 0°';

  @override
  String get readerSettingsOrientationLock90Tooltip => '锁定 90°';

  @override
  String get readerSettingsOrientationLock180Tooltip => '锁定 180°';

  @override
  String get readerSettingsOrientationLock270Tooltip => '锁定 270°';

  @override
  String get readerSettingsSaveAsPresetButton => '将目前设定存为新预设集';

  @override
  String get readerSettingsSavedPresetsLabel => '已保存的预设集';

  @override
  String get readerSettingsCopyFromBookLabel => '从其他书籍复制';

  @override
  String get readerSettingsCopyToCurrentBookButton => '复制到本书';

  @override
  String get readerSettingsCopyToOtherBooksButton => '复制到其他书籍';

  @override
  String get readerSettingsResetPresetTitle => '系统预设';

  @override
  String get readerSettingsResetPresetSubtitle =>
      '移除本书所有字级/字重/行距/段落间距/字距覆盖，改用书本原始样式';

  @override
  String get readerSettingsApplyButton => '套用';

  @override
  String get readerSettingsPresetDefaultValue => '预设';

  @override
  String get readerSettingsPresetSummaryAutoLabel => '自动';

  @override
  String readerSettingsPresetSummaryFormat(
    String fontSize,
    String lineHeight,
    String writingMode,
  ) {
    return '字级$fontSize・行距$lineHeight・$writingMode';
  }

  @override
  String get readerSettingsPresetEmptySlot => '（空）';

  @override
  String get readerSettingsApplyToOtherBooksTooltip => '套用到其他书籍';

  @override
  String get readerSettingsDeletePresetTooltip => '删除';

  @override
  String get readerUnknownBookTitle => '未知书籍';

  @override
  String get readerSaveAsPresetUnavailableMessage => '暂时无法保存预设集';

  @override
  String get readerSaveAsPresetFailedMessage => '另存为新预设集失败';

  @override
  String get readerOverwritePresetPickerTitle => '选择要覆盖的预设集';

  @override
  String readerOverwritePresetOptionLabel(String name, String date) {
    return '$name（最后更新：$date）';
  }

  @override
  String get readerConfirmOverwriteTitle => '确认覆盖';

  @override
  String readerOverwritePresetConfirmMessage(String name) {
    return '即将覆盖预设集“$name”，此操作无法复原。';
  }

  @override
  String get readerConfirmApplyTitle => '确认套用';

  @override
  String readerApplyToOthersConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '即将覆盖 $count 本书的版面设定，此操作无法复原。',
      one: '即将覆盖 1 本书的版面设定，此操作无法复原。',
    );
    return '$_temp0';
  }

  @override
  String get readerApplyPresetFailedMessage => '套用版面设定失败';

  @override
  String get readerConfirmDeleteTitle => '确认删除';

  @override
  String readerDeletePresetConfirmMessage(String name) {
    return '即将删除预设集“$name”，此操作无法复原。';
  }

  @override
  String get readerDeletePresetFailedMessage => '删除预设集失败';

  @override
  String get readerSearchUnavailableMessage => '搜索功能暂时无法使用';

  @override
  String get readerOpenBookTimeoutMessage => '开书逾时，可能是系统 WebView 版本过旧或文件异常';

  @override
  String get readerCopiedToClipboardMessage => '已复制到剪贴板';

  @override
  String get readerTtsVoicePickerTitle => '朗读语音';

  @override
  String get readerUnsupportedFormatMessage => '不支持的文件格式';

  @override
  String get readerFailedToLoadBookMessage => '无法载入书籍';

  @override
  String readerTtsSleepTimerOptionMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get readerTtsSleepTimerNoLimitLabel => '不限时';

  @override
  String get settingsScaffoldTitle => '设定';

  @override
  String get settingsLibraryTooltip => '书架';

  @override
  String get settingsSourceTooltip => '来源';

  @override
  String get settingsAppearanceSectionTitle => '外观';

  @override
  String get settingsThemeLabel => '布景';

  @override
  String get settingsThemeLockedHint => '这里选的是关闭 E-Ink 后要恢复的主题';

  @override
  String settingsThemeDotSemanticsLabel(String themeName) {
    return '$themeName布景';
  }

  @override
  String settingsThemeDotLockedSemanticsLabel(
    String themeName,
    String currentThemeName,
  ) {
    return '$themeName布景，已锁定，这里选的是关闭 E-Ink 后要恢复的主题，目前选择：$currentThemeName';
  }

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeSepia => '羊皮纸';

  @override
  String get settingsEinkModeLabel => 'E-Ink 高对比模式';

  @override
  String get settingsEinkModeSubtitle => '停用动画与渐层，以纯黑白高对比显示，专为电子纸屏幕最佳化';

  @override
  String get settingsFontManagementLabel => '字体管理';

  @override
  String get settingsReadingSectionTitle => '阅读';

  @override
  String get settingsReadingDefaultsLabel => '阅读预设值';

  @override
  String get settingsNavZoneLabel => '导航热区';

  @override
  String get settingsTtsDefaultsLabel => '朗读语音与语速';

  @override
  String get settingsFullTextSearchUnavailableLabel => '全文检索';

  @override
  String get settingsFullTextSearchUnavailableSubtitle => '本装置不支持全文检索';

  @override
  String get settingsFullTextSearchPdfLabel => 'PDF 全文检索';

  @override
  String get settingsFullTextSearchPdfSubtitle => '部分扫描/图片型 PDF 可能没有可搜索的文字内容';

  @override
  String get settingsFullTextSearchRebuildIndexTooltip => '重建索引';

  @override
  String get settingsFullTextSearchFoliateLabel => '其他格式全文检索';

  @override
  String get settingsFullTextSearchFoliateSubtitle => 'EPUB／TXT／KF8 等格式的背景索引建置';

  @override
  String get settingsSyncAccountSectionTitle => '同步与账号';

  @override
  String get settingsSyncLabel => '同步';

  @override
  String get settingsCloudAccountLabel => '已链接的云端导入账户';

  @override
  String get settingsAboutSectionTitle => '关于';

  @override
  String get settingsAboutLabel => '关于';

  @override
  String get settingsReaderConsoleLogLabel => '阅读器 Console Log';

  @override
  String get settingsConsoleLogInterceptLabel => 'Console Log 拦截';

  @override
  String get settingsConsoleLogInterceptSubtitle => '关闭后仅保留错误讯息，用于问题回报时的诊断纪录';

  @override
  String get navZoneSettingsTitle => '导航热区';

  @override
  String get navZoneSettingsPageTurnModeLabel => '翻页方式';

  @override
  String get navZoneSettingsSimpleModeLabel => '简单';

  @override
  String get navZoneSettingsCustomModeLabel => '自定义';

  @override
  String get navZoneSettingsShowDebugOverlayLabel => '显示热区辅助线';

  @override
  String get navZoneSettingsSaveCustomButton => '保存自定义热区设定';

  @override
  String get navZoneActionPreviousPage => '上一页';

  @override
  String get navZoneActionNextPage => '下一页';

  @override
  String get navZoneActionMenu => '选单';

  @override
  String get navZoneActionNone => '无动作';

  @override
  String get navZoneCustomValidationError => '至少需要 1 格设为「选单」，否则将无法退出沉浸模式';

  @override
  String get readingDefaultsTitle => '阅读预设值';

  @override
  String get readingDefaultsVolumeKeyLabel => '音量键翻页';

  @override
  String get readingDefaultsPageTurnModeSectionTitle => '翻页模式';

  @override
  String get readingDefaultsPaginatedLabel => '点击翻页';

  @override
  String get readingDefaultsScrollLabel => '滚动翻页';

  @override
  String get readingDefaultsScreenOrientationSectionTitle => '屏幕方向';

  @override
  String get readingDefaultsOrientationAutoLabel => '自动旋转';

  @override
  String get readingDefaultsOrientationLock0Label => '锁定 0°';

  @override
  String get readingDefaultsOrientationLock90Label => '锁定 90°';

  @override
  String get readingDefaultsOrientationLock180Label => '锁定 180°';

  @override
  String get readingDefaultsOrientationLock270Label => '锁定 270°';

  @override
  String get readingDefaultsTextConversionSectionTitle => '简繁转换显示';

  @override
  String get readingDefaultsTextConversionOriginalLabel => '原文';

  @override
  String get readingDefaultsTextConversionTraditionalLabel => '转换为繁体';

  @override
  String get readingDefaultsTextConversionSimplifiedLabel => '转换为简体';

  @override
  String get readingDefaultsFullscreenLabel => '全屏幕模式';

  @override
  String get readingDefaultsOpenLastBookLabel => '启动时打开最后阅读的那本书';

  @override
  String get readingDefaultsShowHeaderLabel => '显示页首';

  @override
  String get readingDefaultsShowFooterLabel => '显示页尾';

  @override
  String get ttsDefaultsTitle => '朗读语音与语速';

  @override
  String get ttsDefaultsVoiceSectionTitle => '语音';

  @override
  String get ttsDefaultsVoiceUnavailableHint => '目前装置未安装或不支持语音选择';

  @override
  String get ttsDefaultsSpeedSectionTitle => '语速';

  @override
  String get syncSettingsTitle => '同步';

  @override
  String get syncSettingsSyncFailedMessage => '同步失败，请确认网络连线';

  @override
  String get syncSettingsNeverSynced => '尚未同步过';

  @override
  String syncSettingsLastSyncedAt(String formatted) {
    return '最后同步：$formatted';
  }

  @override
  String get syncSettingsConnectionFailedMessage => '连线失败，请确认服务器网址与账号密码是否正确';

  @override
  String syncSettingsLoggedInAs(String email) {
    return '已登入：$email';
  }

  @override
  String get syncSettingsManualSyncButton => '立即同步';

  @override
  String get syncSettingsLogoutButton => '登出';

  @override
  String get syncSettingsServerUrlLabel => '服务器网址';

  @override
  String get syncSettingsPasswordLabel => '密码';

  @override
  String get syncSettingsShowPasswordTooltip => '显示密码';

  @override
  String get syncSettingsHidePasswordTooltip => '隐藏密码';

  @override
  String get syncSettingsConnectButton => '连线／登入';

  @override
  String get cloudAccountSettingsTitle => '已链接的云端导入账户';

  @override
  String cloudAccountSettingsLinkedEmail(String email) {
    return '已链接：$email';
  }

  @override
  String get cloudAccountSettingsUnlinkButton => '解除链接';

  @override
  String get cloudAccountSettingsUnlinkedText => '未链接';

  @override
  String get cloudAccountSettingsLinkButton => '链接';

  @override
  String get fontManagementTitle => '字体管理';

  @override
  String get fontNameSourceHanSans => '思源黑体';

  @override
  String get fontNameSourceHanSerif => '思源宋体';

  @override
  String get fontManagementUploadTooltip => '上传字体';

  @override
  String get fontManagementBuiltInSectionLabel => '内建字体';

  @override
  String get fontManagementCustomSectionLabel => '自定义字体';

  @override
  String get fontManagementNoCustomFontsHint => '尚未上传任何自定义字体';

  @override
  String get fontManagementRenameTooltip => '重新命名';

  @override
  String get fontManagementDeleteTooltip => '删除';

  @override
  String get fontManagementRenameDialogTitle => '重新命名';

  @override
  String fontManagementDeleteConfirmTitle(String fontName) {
    return '确定要删除「$fontName」吗？';
  }

  @override
  String fontManagementDeleteConfirmMessage(int usageCount) {
    String _temp0 = intl.Intl.pluralLogic(
      usageCount,
      locale: localeName,
      other: '目前有 $usageCount 本书使用此字体，删除后将自动改用预设字体',
      one: '目前有 1 本书使用此字体，删除后将自动改用预设字体',
    );
    return '$_temp0';
  }

  @override
  String get fontManagementStatusNotDownloaded => '未下载';

  @override
  String get fontManagementStatusDownloaded => '已下载';

  @override
  String get fontManagementDownloadTooltip => '下载';

  @override
  String get fontManagementCancelDownloadTooltip => '取消下载';

  @override
  String get fontManagementRetryTooltip => '重试';

  @override
  String get fontManagementDownloadableDeleteConfirmMessage =>
      '删除后可以随时重新下载。使用这款字体的书会暂时改用书本或系统字体，重新下载后自动恢复。';

  @override
  String get fontDownloadErrorNetwork => '无法连接，请检查网络后重试';

  @override
  String fontDownloadErrorHttp(int statusCode) {
    return '服务器错误（$statusCode），请稍后重试';
  }

  @override
  String get fontDownloadErrorIntegrity => '文件不完整或已损坏，请重试';

  @override
  String get fontDownloadErrorStorage => '无法保存文件，请确认存储空间是否足够';

  @override
  String fontManagementUploadBothMessage(int addedCount, int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      addedCount,
      locale: localeName,
      other: '已新增 $addedCount 款字体',
      one: '已新增 1 款字体',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount 款已存在已跳过',
      one: '1 款已存在已跳过',
    );
    return '$_temp0，$_temp1';
  }

  @override
  String fontManagementUploadAddedOnlyMessage(int addedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      addedCount,
      locale: localeName,
      other: '已新增 $addedCount 款字体',
      one: '已新增 1 款字体',
    );
    return '$_temp0';
  }

  @override
  String fontManagementUploadSkippedOnlyMessage(int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount 款字体已存在，已跳过',
      one: '1 款字体已存在，已跳过',
    );
    return '$_temp0';
  }

  @override
  String get readerConsoleLogTitle => '阅读器 Console Log';

  @override
  String get readerConsoleLogCopyAllTooltip => '复制全部';

  @override
  String get readerConsoleLogClearTooltip => '清空';

  @override
  String get readerConsoleLogEmptyHint => '目前没有记录';

  @override
  String get readerConsoleLogCopiedMessage => '已复制全部记录到剪贴板';

  @override
  String get aboutScreenTitle => '关于';

  @override
  String get aboutScreenVersionLabel => '版本';

  @override
  String get aboutScreenBuildTimeLabel => '编译时间';

  @override
  String get aboutScreenWebViewVersionLabel => '系统 WebView 版本';

  @override
  String get aboutScreenViewLicensesButton => '开源授权清单';

  @override
  String get aboutScreenLoadingText => '读取中...';

  @override
  String get aboutScreenFailedToLoadVersionMessage => '无法取得版本号';

  @override
  String get aboutScreenUnavailableText => '无法取得';

  @override
  String get remoteServerListTitle => '远程书库';

  @override
  String get remoteServerListAddTooltip => '新增站点';

  @override
  String get remoteServerListEmptyState => '尚未新增任何远程书库站点';

  @override
  String get remoteServerListEditTooltip => '编辑';

  @override
  String get remoteServerListDeleteTooltip => '删除';

  @override
  String get remoteServerListDeleteConfirmTitle => '删除站点';

  @override
  String get remoteServerListDeleteConfirmButton => '删除';

  @override
  String remoteServerListDeleteConfirmMessage(String name) {
    return '确定要删除站点「$name」吗？此动作无法复原。';
  }

  @override
  String get remoteServerListDeleteBlockedTitle => '无法删除站点';

  @override
  String remoteServerListDeleteBlockedMessage(int count, String titles) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '这个站点还有 $count 本书仅有云端记录、尚未下载：',
      one: '这个站点还有 1 本书仅有云端记录、尚未下载：',
    );
    return '$_temp0\n$titles\n\n请先于书架移除这些书籍，或重新下载后再删除站点。';
  }

  @override
  String get remoteServerListDeleteBlockedConfirmButton => '了解';

  @override
  String get remoteServerListDeleteFailedMessage => '删除站点失败，请稍后再试';

  @override
  String get remoteServerFormTitleAdd => '新增站点';

  @override
  String get remoteServerFormTitleEdit => '编辑站点';

  @override
  String get remoteServerFormNameLabel => '站点名称';

  @override
  String get remoteServerFormBaseUrlLabel => '服务器网址';

  @override
  String get remoteServerFormTypeOpds => '标准 OPDS';

  @override
  String get remoteServerFormTypeCalibreServer => '原生 Calibre Content Server';

  @override
  String get remoteServerFormUsernameLabel => '账号（留空代表匿名连线）';

  @override
  String get remoteServerFormPasswordLabelEditing =>
      '密码（留空＝沿用既有密码；清空上方账号栏位则一并清除密码）';

  @override
  String get remoteServerFormPasswordLabel => '密码';

  @override
  String get remoteServerFormPasswordShowTooltip => '显示密码';

  @override
  String get remoteServerFormPasswordHideTooltip => '隐藏密码';

  @override
  String get remoteServerFormAllowInsecureLabel => '允许不安全连线（自签凭证／纯 HTTP）';

  @override
  String get remoteServerFormValidationMissingFields => '请填写站点名称与网址';

  @override
  String get remoteServerFormValidationInvalidUrl =>
      '请输入有效的服务器网址（需以 http:// 或 https:// 开头）';

  @override
  String get remoteServerFormSaveFailedMessage => '储存失败，请稍后再试';

  @override
  String get remoteServerFormTestSuccess => '连线成功';

  @override
  String get remoteServerFormTestFailed => '连线失败，请检查网址/账密/凭证设定';

  @override
  String get remoteServerFormTestConnectionButton => '测试连线';

  @override
  String get remoteServerFormSaveButton => '储存';

  @override
  String formatSelectionDialogTitle(String title) {
    return '选择格式：$title';
  }

  @override
  String get formatSelectionDialogUnsupportedFormat => '不支持的格式';

  @override
  String get cloudDuplicateDialogTitle => '重复的书籍';

  @override
  String get cloudDuplicateDialogConfirmButton => '仍要建立';

  @override
  String get remoteCatalogLoadFailedMessage => '载入失败，请检查网络连线或站点设定';

  @override
  String get remoteCatalogDownloadSelectedTooltip => '下载已选取';

  @override
  String remoteCatalogDuplicateConfirmMessage(String title) {
    return '「$title」之前汇入过了，仍要建立新的一份吗？';
  }

  @override
  String remoteCatalogQueuedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个档案',
      one: '1 个档案',
    );
    return '已加入下载队列（$_temp0），可至「来源」画面查看进度';
  }

  @override
  String get remoteCatalogEinkPrevPageButton => '上一页';

  @override
  String get remoteCatalogEinkNextPageButton => '下一页';

  @override
  String get remoteCatalogLoadMoreButton => '载入更多';

  @override
  String get remoteCatalogDuplicateDialogTitle => '重复的书籍';

  @override
  String get remoteCatalogDuplicateDialogConfirmButton => '仍要建立';

  @override
  String get wifiTransferLeaveConfirmTitle => '目前尚有档案正在传输';

  @override
  String get wifiTransferLeaveConfirmMessage => '离开将中断连线，是否确定离开？';

  @override
  String get wifiTransferLeaveConfirmButton => '确定离开';

  @override
  String get wifiTransferTitle => 'WiFi 传书';

  @override
  String get wifiTransferInstructionText => '在同一个 WiFi 下，用浏览器打开以下网址：';

  @override
  String wifiTransferActiveCountText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '正在传输中（$count 个档案）…',
      one: '正在传输中（1 个档案）…',
    );
    return '$_temp0';
  }

  @override
  String get wifiTransferUnavailableText => '请连线至 WiFi 或开启手机热点';

  @override
  String get wifiTransferManualOverrideButton => '我确定目前是用手机热点';

  @override
  String get wifiTransferNoInterfacesText => '找不到任何可用网络介面';

  @override
  String get downloadQueueTitle => '下载队列';

  @override
  String get downloadQueueCancelTooltip => '取消';

  @override
  String get downloadQueueRetryTooltip => '重试';

  @override
  String get downloadQueueDismissTooltip => '从清单移除';

  @override
  String get downloadQueueStatusPending => '待机';

  @override
  String get downloadQueueStatusDownloading => '下载中';

  @override
  String get downloadQueueStatusCheckingDuplicate => '比对中';

  @override
  String get downloadQueueStatusDone => '完成';

  @override
  String get downloadQueueStatusDuplicateSkipped => '重复已略过';

  @override
  String get downloadQueueStatusFailed => '失败';

  @override
  String get downloadQueueStatusCancelled => '已取消';

  @override
  String downloadQueueDuplicateConfirmMessage(String name) {
    return '侦测到「$name」与本机已有的一本书内容相同，仍要建立新的一份吗？';
  }

  @override
  String get sourcesHomeTitle => '来源';

  @override
  String get sourcesHomeLibraryTooltip => '书架';

  @override
  String get sourcesHomeSettingsTooltip => '设定';

  @override
  String get sourcesHomeLocalSection => '本机';

  @override
  String get sourcesHomePickFilesTitle => '选择档案（可多选）';

  @override
  String get sourcesHomePickFolderTitle => '选择资料夹';

  @override
  String get sourcesHomeWifiTransferTile => 'WiFi 传书';

  @override
  String get sourcesHomeConnectedServicesSection => '已连结服务';

  @override
  String get sourcesHomeCloudNotLinkedSubtitle => '尚未连结，请至设定画面连结账户';

  @override
  String get sourcesHomeRemoteLibraryTitle => '远程书库（OPDS）';

  @override
  String get sourcesHomeRemoteLibraryNotConfiguredSubtitle => '尚未设定远程书库服务器';

  @override
  String get libraryImportFolderDialogTitle => '汇入资料夹';

  @override
  String get libraryImportFolderAutoGroupLabel => '依资料夹名称自动建立分类';

  @override
  String get libraryImportFolderConfirmButton => '汇入';

  @override
  String libraryImportResultBothMessage(int importedCount, int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      importedCount,
      locale: localeName,
      other: '已汇入 $importedCount 本',
      one: '已汇入 1 本',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount 本已存在，已跳过',
      one: '1 本已存在，已跳过',
    );
    return '$_temp0，$_temp1';
  }

  @override
  String libraryImportResultImportedOnlyMessage(int importedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      importedCount,
      locale: localeName,
      other: '已汇入 $importedCount 本书',
      one: '已汇入 1 本书',
    );
    return '$_temp0';
  }

  @override
  String libraryImportResultSkippedOnlyMessage(int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount 本已存在，已跳过',
      one: '1 本已存在，已跳过',
    );
    return '$_temp0';
  }

  @override
  String get layoutPresetBookPickerTitleMulti => '选择书籍（可复选）';

  @override
  String get layoutPresetBookPickerTitleSingle => '选择书籍';

  @override
  String get layoutPresetBookPickerSearchHint => '搜索书名或作者';

  @override
  String get layoutPresetBookPickerEmptyBooks => '没有可选择的流式 EPUB 书籍';

  @override
  String get layoutPresetBookPickerNoMatch => '找不到符合的书籍';

  @override
  String get layoutPresetNameDialogTitle => '为预设集命名';

  @override
  String get layoutPresetNameDialogEmptyError => '名称不可为空';

  @override
  String get layoutPresetNameDialogSaveButton => '储存';

  @override
  String markdownExportTitle(String bookTitle) {
    return '# 阅读笔记：《$bookTitle》';
  }

  @override
  String markdownExportAuthorLabel(String author) {
    return '*   **作者**：$author';
  }

  @override
  String get markdownExportUnknownAuthor => '未知作者';

  @override
  String markdownExportProgressLabel(int percent) {
    return '*   **阅读进度**：$percent%';
  }

  @override
  String markdownExportTimeLabel(String time) {
    return '*   **导出时间**：$time';
  }

  @override
  String markdownExportBookmarksSection(int count) {
    return '## 🔖 书签清单 ($count)';
  }

  @override
  String get markdownExportNoBookmarks => '*(尚未加入书签)*';

  @override
  String markdownExportAnnotationsSection(int count) {
    return '## ✏️ 划线与个人备注 ($count)';
  }

  @override
  String get markdownExportNoAnnotations => '*(尚未加入任何划线或备注)*';

  @override
  String markdownExportAnnotationHeading(String label, String position) {
    return '### 📌 $label（位置：$position）';
  }

  @override
  String bookmarkDefaultNamePdfPage(int page) {
    return '第 $page 页';
  }

  @override
  String bookmarkDefaultNamePercent(int percent) {
    return '$percent% 处';
  }

  @override
  String get bookmarkDefaultNameFallback => '书签';

  @override
  String get ttsNotificationChannelName => '朗读播放中';

  @override
  String get ttsVoiceSystemDefault => '系统默认语音';

  @override
  String get remoteCatalogUnnamedCategory => '未命名分类';

  @override
  String get remoteCatalogUnknownBookTitle => '未知书名';

  @override
  String get wifiPageTitle => 'elinkBook WiFi 传书';

  @override
  String get wifiPageUploadHeading => '上传书籍';

  @override
  String get wifiPageDropzoneText => '拖放文件到此处，或';

  @override
  String get wifiPageChooseFile => '选择文件';

  @override
  String get wifiPageDownloadHeading => '下载书籍';

  @override
  String get wifiPageSearchPlaceholder => '搜索书名…';

  @override
  String get wifiPageSelectPage => '全选当前页';

  @override
  String get wifiPageClearSelection => '清除勾选';

  @override
  String wifiPageSelectedCount(String count) {
    return '已勾选 $count 本';
  }

  @override
  String get wifiPageLoading => '加载中…';

  @override
  String get wifiPagePrevPage => '上一页';

  @override
  String get wifiPageNextPage => '下一页';

  @override
  String wifiPagePageInfo(String page, String total) {
    return '第 $page / $total 页';
  }

  @override
  String get wifiPageDownloadSelected => '下载已勾选书籍';

  @override
  String get wifiPageNoBooks => '当前没有可下载的书籍';

  @override
  String get wifiPageNoMatch => '没有符合条件的书籍';

  @override
  String get wifiPageLoadFailed => '无法加载书籍列表';

  @override
  String wifiPageTotalBooks(String count) {
    return '共 $count 本书籍';
  }

  @override
  String wifiPageMatchStats(String matched, String total) {
    return '符合 $matched 本 / 共 $total 本';
  }

  @override
  String get wifiPageSelectAtLeastOne => '请至少勾选一本书';

  @override
  String get wifiPageDownloading => '下载中…';

  @override
  String wifiPageDownloadTriggered(String count) {
    return '已触发全部下载（共 $count 本）';
  }

  @override
  String get wifiPageOutcomeImported => '已导入';

  @override
  String get wifiPageOutcomeDuplicateSkipped => '已存在，已跳过';

  @override
  String get wifiPageOutcomeUnsupportedFormat => '格式不支持';

  @override
  String get wifiPageOutcomeFailed => '导入失败';

  @override
  String wifiPageUploadResultLine(String name, String outcome) {
    return '$name：$outcome';
  }

  @override
  String get wifiPageUnknownFileName => '(未知文件名)';

  @override
  String get wifiPageUploadPreparing => '准备上传…';

  @override
  String get wifiPageUploading => '正在上传…';

  @override
  String wifiPageUploadingPercent(String percent) {
    return '正在上传… ($percent%)';
  }

  @override
  String get wifiPageUploadProcessing => '上传完成，手机端正在处理并导入，请稍候…';

  @override
  String get wifiPageUnknownSize => '未知';

  @override
  String wifiPageUploadFailedServer(String status) {
    return '上传失败：服务器响应错误 ($status)';
  }

  @override
  String get wifiPageUploadFailedParse => '上传失败：无法解析服务器响应';

  @override
  String get wifiPageUploadFailedNetwork => '上传失败：网络错误';

  @override
  String get wifiPageUploadAborted => '上传已中断';

  @override
  String get wifiPageUploadTimeout => '上传超时';
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
  String get settingsLanguageZhCN => '简体中文';

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
  String libraryGroupNameAlreadyExistsError(String name) {
    return '分類「$name」已存在，請使用其他名稱';
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

  @override
  String get libraryBackButtonTooltip => '返回上層';

  @override
  String get libraryShelfTitle => '書架';

  @override
  String get librarySortViewTooltip => '排序與檢視';

  @override
  String get librarySortByLastRead => '最後閱讀';

  @override
  String get librarySortByCreateTime => '建立時間';

  @override
  String get librarySortByAuthor => '作者';

  @override
  String get librarySortByTitle => '書名';

  @override
  String get libraryToggleViewToList => '切換為列表';

  @override
  String get libraryToggleViewToShelf => '切換為書架';

  @override
  String get libraryManageGroupsMenuItem => '管理分類...';

  @override
  String get librarySourceTooltip => '來源';

  @override
  String get librarySettingsTooltip => '設定';

  @override
  String get libraryCancelSelectionTooltip => '取消選取';

  @override
  String librarySelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已選取 $count 本',
      one: '已選取 1 本',
    );
    return '$_temp0';
  }

  @override
  String get libraryMoveToGroupTooltip => '移動到分類';

  @override
  String get libraryForceFxlTooltip => '強制 FXL';

  @override
  String get libraryRestoreAutoLayoutTooltip => '恢復自動判斷';

  @override
  String get libraryDeleteTooltip => '刪除';

  @override
  String get libraryRemoveLocalCacheTooltip => '移除本機快取';

  @override
  String get libraryEmptyStateMessage => '尚未匯入書籍';

  @override
  String get libraryEmptyStateImportButton => '匯入書籍';

  @override
  String get librarySearchHint => '搜尋書名或作者...';

  @override
  String get libraryContentSearchEntryLabel => '搜尋書本內容';

  @override
  String get libraryNoMatchingBooks => '找不到符合的書籍';

  @override
  String get libraryDeleteBooksDialogTitle => '刪除書籍';

  @override
  String libraryDeleteBooksConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '將刪除已選取的 $count 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？',
      one: '將刪除已選取的 1 本書籍，並一併刪除其書籤、劃線與備註，此操作無法復原。確定要刪除嗎？',
    );
    return '$_temp0';
  }

  @override
  String get libraryDeleteBooksConfirmButton => '刪除';

  @override
  String get libraryRedownloadAction => '重新下載';

  @override
  String libraryRedownloadConfirmMessage(String title) {
    return '即將重新下載「$title」，確定要繼續嗎？';
  }

  @override
  String libraryRedownloadConfirmMessageMobileData(String title) {
    return '即將重新下載「$title」，目前使用行動數據連線，可能產生流量費用，確定要繼續嗎？';
  }

  @override
  String get libraryRemoteDisabledMessage => '遠端書庫功能未啟用，無法重新下載';

  @override
  String get libraryRemoteServerNotFoundMessage => '找不到對應的遠端書庫站點';

  @override
  String get libraryRedownloadFailedMessage => '重新下載失敗，請稍後再試';

  @override
  String libraryRemoveCacheConfirmMessage(String title) {
    return '將移除「$title」的本機檔案，書籍紀錄與閱讀進度會保留，之後可重新下載。確定要移除嗎？';
  }

  @override
  String get libraryRemoveCacheConfirmButton => '移除';

  @override
  String get libraryGroupBadgeLabel => '分類';

  @override
  String libraryGroupTileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 本',
      one: '1 本',
    );
    return '$_temp0';
  }

  @override
  String get libraryBookMenuTooltip => '更多';

  @override
  String get libraryContinueReadingLabel => '繼續閱讀';

  @override
  String get libraryBookNotDownloaded => '尚未下載';

  @override
  String get libraryUnknownFileSize => '未知大小';

  @override
  String get libraryLoadingEllipsis => '讀取中...';

  @override
  String libraryDetailAuthorLabel(String author) {
    return '作者：$author';
  }

  @override
  String get libraryUnknownAuthor => '未知';

  @override
  String libraryDetailFormatLabel(String format) {
    return '格式：$format';
  }

  @override
  String libraryDetailFileSizeLabel(String size) {
    return '檔案大小：$size';
  }

  @override
  String libraryDetailProgressLabel(String progress) {
    return '進度：$progress';
  }

  @override
  String libraryDetailLastReadLabel(String date) {
    return '最後閱讀：$date';
  }

  @override
  String get libraryNeverRead => '尚未閱讀';

  @override
  String get libraryLayoutOverrideTitle => '版面覆寫';

  @override
  String get libraryLayoutOverrideWritingModeLabel => '排版方向';

  @override
  String get libraryLayoutOverrideWritingModeDefault => '使用書籍排版';

  @override
  String get libraryLayoutOverrideWritingModeHorizontal => '橫排';

  @override
  String get libraryLayoutOverrideWritingModeVertical => '直排';

  @override
  String get libraryLayoutOverridePageTurnModeLabel => '翻頁模式';

  @override
  String get libraryLayoutOverridePageTurnModeDefault => '使用全域預設';

  @override
  String get libraryLayoutOverridePageTurnModePaginated => '分頁';

  @override
  String get libraryLayoutOverridePageTurnModeScroll => '捲動';

  @override
  String get libraryLayoutOverrideSaveButton => '儲存';

  @override
  String get readerBackTooltip => '返回';

  @override
  String get readerSearchTooltip => '搜尋內文';

  @override
  String get readerHideToolbarTooltip => '隱藏工具列';

  @override
  String get readerShowToolbarTooltip => '顯示工具列';

  @override
  String get readerTocTooltip => '目錄';

  @override
  String get readerBookmarkAddedTooltip => '已加入此頁書籤';

  @override
  String get readerBookmarkAddTooltip => '加入此頁書籤';

  @override
  String get readerAnnotationsTooltip => '劃線筆記';

  @override
  String get readerLayoutTooltip => '版面';

  @override
  String get readerTtsTooltip => '朗讀';

  @override
  String get readerPagingPreviousTooltip => '上一頁';

  @override
  String get readerPagingNextTooltip => '下一頁';

  @override
  String get readerPdfNoPagesAvailable => '無可用頁面';

  @override
  String get readerNoteDialogSaveButton => '儲存';

  @override
  String get readerNoteDialogDefaultTitle => '備註';

  @override
  String get readerAnnotationUnderlineTooltip => '底線';

  @override
  String get readerAnnotationCopyTooltip => '複製';

  @override
  String get readerAnnotationEditNoteTooltip => '編輯備註';

  @override
  String get readerAnnotationAddNoteTooltip => '新增備註';

  @override
  String get readerAnnotationDeleteHighlightAndNote => '刪除畫線與備註';

  @override
  String get readerAnnotationDeleteHighlight => '刪除畫線';

  @override
  String get readerAnnotationDeleteNote => '刪除備註';

  @override
  String get readerPdfSearchHint => '搜尋文字…';

  @override
  String get readerPdfSearchNoMatches => '找不到符合的文字';

  @override
  String get readerPdfSearchPreviousTooltip => '上一個';

  @override
  String get readerPdfSearchNextTooltip => '下一個';

  @override
  String readerPositionConflictTitle(String bookTitle) {
    return '「$bookTitle」的閱讀進度不一致';
  }

  @override
  String readerPositionConflictMessage(String local, String remote) {
    return '偵測到另一台裝置也更新過這本書的閱讀進度，請選擇要保留哪一邊：\n\n本機：$local\n雲端：$remote';
  }

  @override
  String readerPositionConflictPdfLocation(int page, int percent) {
    return '第 $page 頁（進度 $percent%）';
  }

  @override
  String readerPositionConflictEpubLocation(int percent) {
    return '進度 $percent%';
  }

  @override
  String get readerPositionConflictKeepCloud => '保留雲端';

  @override
  String get readerPositionConflictKeepLocal => '保留本機';

  @override
  String get readerTocTitle => '📖 目錄';

  @override
  String get readerTocEmptyMessage => '本書無目錄資料';

  @override
  String get readerTocTabChapters => '章節目錄';

  @override
  String get readerTocTabThumbnails => '縮圖';

  @override
  String get readerTocTabSearch => '搜尋';

  @override
  String get readerFeatureComingSoon => '此功能將於後續版本提供';

  @override
  String get readerTtsCbzUnsupportedTooltip => 'CBZ 為純圖像格式，不支援語音朗讀';

  @override
  String get readerTtsPreviousTooltip => '上一句';

  @override
  String get readerTtsPauseTooltip => '暫停朗讀';

  @override
  String get readerTtsPlayTooltip => '開始朗讀';

  @override
  String get readerTtsNextTooltip => '下一句';

  @override
  String readerTtsSpeedTooltip(String speed) {
    return '朗讀語速：${speed}x（點擊切換）';
  }

  @override
  String get readerTtsVoiceTooltip => '選擇語音';

  @override
  String get readerTtsSleepTimerLabel => '定時';

  @override
  String readerTtsSleepTimerLabelWithMinutes(int minutes) {
    return '定時 $minutes 分';
  }

  @override
  String get readerTtsCollapseLabel => '收合';

  @override
  String get readerTtsExpandLabel => '展開';

  @override
  String get readerTtsStopLabel => '停止';

  @override
  String get readerNotesSheetTitle => '筆記';

  @override
  String get readerNotesSheetExportMarkdownTooltip => '導出為 Markdown';

  @override
  String get readerNotesSheetTabBookmarks => '書籤';

  @override
  String get readerNotesSheetTabAnnotations => '劃線與備註';

  @override
  String get readerNotesSheetDeleteAllBookmarksTooltip => '刪除該書所有書籤';

  @override
  String get readerNotesSheetRenameBookmarkTitle => '重新命名書籤';

  @override
  String get readerDeleteConfirmButton => '刪除';

  @override
  String readerNotesSheetDeleteAllBookmarksConfirm(int count) {
    return '確定要刪除全部書籤嗎？（共 $count 筆）';
  }

  @override
  String get readerNotesSheetRenameTooltip => '重新命名';

  @override
  String get readerNotesSheetDeleteItemTooltip => '刪除';

  @override
  String get readerNotesSheetNoAnnotationsPlaceholder => '尚無劃線或備註';

  @override
  String get readerNotesSheetDeleteAllHighlightsButton => '刪除所有劃線';

  @override
  String get readerNotesSheetDeleteAllNotesButton => '刪除所有備註';

  @override
  String get readerNotesSheetNoteLabel => '備註';

  @override
  String get readerHighlightStyleYellow => '螢光筆（黃）';

  @override
  String get readerHighlightStylePink => '螢光筆（粉）';

  @override
  String get readerHighlightStyleBlue => '螢光筆（藍）';

  @override
  String get readerHighlightStyleUnderline => '底線';

  @override
  String readerNotesSheetDeleteAllHighlightsConfirm(int count) {
    return '確定要刪除全部劃線嗎？（共 $count 筆）';
  }

  @override
  String readerNotesSheetDeleteAllNotesConfirm(int count) {
    return '確定要刪除全部備註嗎？（共 $count 筆）';
  }

  @override
  String get readerFxlSettingsTitle => '⚙️ 漫畫版面設定';

  @override
  String get readerDualPageModeLabel => '雙頁模式';

  @override
  String get readerDualPageAutoTooltip => '自動（橫向雙頁）';

  @override
  String get readerDualPageAutoLabel => '自動';

  @override
  String get readerDualPageAlwaysTooltip => '永遠雙頁';

  @override
  String get readerDualPageAlwaysLabel => '雙頁';

  @override
  String get readerDualPageNeverTooltip => '永遠單頁';

  @override
  String get readerDualPageNeverLabel => '單頁';

  @override
  String get readerPageDirectionLabel => '翻頁方向';

  @override
  String get readerDualPageDirectionLtrTooltip => '左到右（LTR，美漫慣例）';

  @override
  String get readerDualPageDirectionLtrLabel => '左翻';

  @override
  String get readerDualPageDirectionRtlTooltip => '右到左（RTL，日漫慣例）';

  @override
  String get readerDualPageDirectionRtlLabel => '右翻';

  @override
  String get readerTextConversionOverrideLabel => '簡繁轉換覆寫';

  @override
  String get readerGlobalLabel => '全域';

  @override
  String get readerUseGlobalDefaultTooltip => '使用全域預設';

  @override
  String get readerTextConversionOriginalLabel => '原文';

  @override
  String get readerTextConversionTraditionalLabel => '繁體';

  @override
  String get readerTextConversionTraditionalTooltip => '轉換為繁體';

  @override
  String get readerTextConversionSimplifiedLabel => '簡體';

  @override
  String get readerTextConversionSimplifiedTooltip => '轉換為簡體';

  @override
  String get readerFullscreenModeLabel => '全螢幕模式';

  @override
  String get readerShowHeaderLabel => '顯示頁首';

  @override
  String get readerShowFooterLabel => '顯示頁尾';

  @override
  String get readerPdfSettingsTitle => '⚙️ PDF 版面設定';

  @override
  String get readerPdfSettingsTabDisplay => '顯示';

  @override
  String get readerPdfSettingsTabFilters => '濾鏡';

  @override
  String get readerPdfSettingsTabCrop => '裁切';

  @override
  String get readerPdfFitModeLabel => 'Fit 模式';

  @override
  String get readerPdfFitPageTooltip => 'Page-fit（整頁）';

  @override
  String get readerPdfFitPageLabel => '整頁';

  @override
  String get readerPdfFitWidthTooltip => 'Fit Width（頁寬）';

  @override
  String get readerPdfFitWidthLabel => '頁寬';

  @override
  String get readerPdfFitActualTooltip => '真實比例 1:1';

  @override
  String get readerPdfFitActualLabel => '原比';

  @override
  String get readerPdfDualPageCoverAloneLabel => '封面獨立顯示';

  @override
  String get readerPdfPageOrientationLabel => '頁面方向';

  @override
  String get readerPdfDirectionLtrTooltip => '左到右';

  @override
  String get readerPdfDirectionLtrLabel => '左翻';

  @override
  String get readerPdfDirectionRtlTooltip => '右到左（日漫慣例）';

  @override
  String get readerPdfDirectionRtlLabel => '右翻';

  @override
  String get readerPdfPageTurnAnimationLabel => '換頁動畫';

  @override
  String get readerPdfPageTurnAnimationSlide => '滑動';

  @override
  String get readerPdfPageTurnAnimationNone => '無';

  @override
  String get readerPdfContrastLabel => '對比度';

  @override
  String get readerPdfBrightnessLabel => '亮度';

  @override
  String get readerPdfBoldStrengthLabel => '加粗強度';

  @override
  String get readerPdfCropModeLabel => '裁切模式';

  @override
  String get readerPdfCropNoneTooltip => '不裁切';

  @override
  String get readerPdfCropNoneLabel => '不裁';

  @override
  String get readerPdfCropAutoTooltip => '智慧自動';

  @override
  String get readerPdfCropAutoLabel => '智慧';

  @override
  String get readerPdfCropManualLabel => '手動';

  @override
  String get readerPdfCropManualTooltip => '手動選區';

  @override
  String get readerSettingsTitle => '⚙️ 版面設定';

  @override
  String get readerSettingsTabText => '文字';

  @override
  String get readerSettingsTabBoundary => '邊界';

  @override
  String get readerSettingsTabPresentation => '呈現';

  @override
  String get readerSettingsTabPreferences => '預設集';

  @override
  String get readerSettingsFontSizeLabel => '字級';

  @override
  String get readerSettingsFontWeightLabel => '字重';

  @override
  String get readerSettingsLineHeightLabel => '行距';

  @override
  String get readerSettingsParagraphSpacingLabel => '段落間距';

  @override
  String get readerSettingsLetterSpacingLabel => '字距';

  @override
  String get readerSettingsDisableBookCssLabel => '停用書本 CSS';

  @override
  String get readerSettingsMarginTopLabel => '上邊界';

  @override
  String get readerSettingsMarginBottomLabel => '下邊界';

  @override
  String get readerSettingsMarginLeftLabel => '左邊界';

  @override
  String get readerSettingsMarginRightLabel => '右邊界';

  @override
  String get readerSettingsOverriddenBadge => '此書已覆寫';

  @override
  String get readerSettingsResetToBookStyleTooltip => '恢復本書原樣式';

  @override
  String get readerSettingsNotOverriddenTooltip => '跟隨本書原樣式，尚未調整';

  @override
  String get readerSettingsUseBookFontLabel => '使用書本內建字型';

  @override
  String get readerSettingsFontFamilyLabel => '字型';

  @override
  String get readerSettingsColumnCountLabel => '欄數';

  @override
  String get readerSettingsColumnAutoLabel => '自動';

  @override
  String get readerSettingsColumnSingleLabel => '單欄';

  @override
  String get readerSettingsColumnDoubleLabel => '雙欄';

  @override
  String get readerSettingsColumnSizeLabel => '欄位大小';

  @override
  String readerSettingsColumnSizeWithValueLabel(int size) {
    return '欄位大小 ${size}px';
  }

  @override
  String get readerSettingsTextAlignLabel => '文字對齊';

  @override
  String get readerSettingsTextAlignCenterLabel => '置中';

  @override
  String get readerSettingsTextAlignJustifyTooltip => '左右對齊';

  @override
  String get readerSettingsTextAlignJustifyLabel => '齊行';

  @override
  String get readerSettingsTextAlignStartTooltip => '起始邊對齊';

  @override
  String get readerSettingsTextAlignStartLabel => '起始';

  @override
  String get readerSettingsTextAlignEndTooltip => '結尾邊對齊';

  @override
  String get readerSettingsTextAlignEndLabel => '結尾';

  @override
  String get readerSettingsTextAlignLeftLabel => '靠左';

  @override
  String get readerSettingsTextAlignRightLabel => '靠右';

  @override
  String get readerSettingsWritingModeLabel => '排版方向模式';

  @override
  String get readerSettingsWritingModeBookTooltip => '採用書籍排版';

  @override
  String get readerSettingsWritingModeBookLabel => '書籍';

  @override
  String get readerSettingsWritingModeVerticalTooltip => '強制直排';

  @override
  String get readerSettingsWritingModeVerticalLabel => '直排';

  @override
  String get readerSettingsWritingModeHorizontalTooltip => '強制橫排';

  @override
  String get readerSettingsWritingModeHorizontalLabel => '橫排';

  @override
  String get readerSettingsPageTurnModeLabel => '翻頁模式覆寫';

  @override
  String get readerSettingsPageTurnPaginatedTooltip => '點擊翻頁';

  @override
  String get readerSettingsPageTurnPaginatedLabel => '點擊';

  @override
  String get readerSettingsPageTurnScrollTooltip => '滾動翻頁';

  @override
  String get readerSettingsPageTurnScrollLabel => '滾動';

  @override
  String get readerSettingsScreenOrientationLabel => '螢幕方向鎖定覆寫';

  @override
  String get readerSettingsOrientationAutoTooltip => '自動旋轉';

  @override
  String get readerSettingsOrientationAutoLabel => '自動';

  @override
  String get readerSettingsOrientationLock0Tooltip => '鎖定 0°';

  @override
  String get readerSettingsOrientationLock90Tooltip => '鎖定 90°';

  @override
  String get readerSettingsOrientationLock180Tooltip => '鎖定 180°';

  @override
  String get readerSettingsOrientationLock270Tooltip => '鎖定 270°';

  @override
  String get readerSettingsSaveAsPresetButton => '將目前設定存為新預設集';

  @override
  String get readerSettingsSavedPresetsLabel => '已儲存的預設集';

  @override
  String get readerSettingsCopyFromBookLabel => '從其他書籍複製';

  @override
  String get readerSettingsCopyToCurrentBookButton => '複製到本書';

  @override
  String get readerSettingsCopyToOtherBooksButton => '複製到其他書籍';

  @override
  String get readerSettingsResetPresetTitle => '系統預設';

  @override
  String get readerSettingsResetPresetSubtitle =>
      '移除本書所有字級/字重/行距/段落間距/字距覆寫，改用書本原始樣式';

  @override
  String get readerSettingsApplyButton => '套用';

  @override
  String get readerSettingsPresetDefaultValue => '預設';

  @override
  String get readerSettingsPresetSummaryAutoLabel => '自動';

  @override
  String readerSettingsPresetSummaryFormat(
    String fontSize,
    String lineHeight,
    String writingMode,
  ) {
    return '字級$fontSize・行距$lineHeight・$writingMode';
  }

  @override
  String get readerSettingsPresetEmptySlot => '（空）';

  @override
  String get readerSettingsApplyToOtherBooksTooltip => '套用到其他書籍';

  @override
  String get readerSettingsDeletePresetTooltip => '刪除';

  @override
  String get readerUnknownBookTitle => '未知書籍';

  @override
  String get readerSaveAsPresetUnavailableMessage => '暫時無法儲存預設集';

  @override
  String get readerSaveAsPresetFailedMessage => '另存為新預設集失敗';

  @override
  String get readerOverwritePresetPickerTitle => '選擇要覆蓋的預設集';

  @override
  String readerOverwritePresetOptionLabel(String name, String date) {
    return '$name（最後更新：$date）';
  }

  @override
  String get readerConfirmOverwriteTitle => '確認覆蓋';

  @override
  String readerOverwritePresetConfirmMessage(String name) {
    return '即將覆蓋預設集「$name」，此動作無法復原。';
  }

  @override
  String get readerConfirmApplyTitle => '確認套用';

  @override
  String readerApplyToOthersConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '即將覆蓋 $count 本書的版面設定，此動作無法復原。',
      one: '即將覆蓋 1 本書的版面設定，此動作無法復原。',
    );
    return '$_temp0';
  }

  @override
  String get readerApplyPresetFailedMessage => '套用版面設定失敗';

  @override
  String get readerConfirmDeleteTitle => '確認刪除';

  @override
  String readerDeletePresetConfirmMessage(String name) {
    return '即將刪除預設集「$name」，此動作無法復原。';
  }

  @override
  String get readerDeletePresetFailedMessage => '刪除預設集失敗';

  @override
  String get readerSearchUnavailableMessage => '搜尋功能暫時無法使用';

  @override
  String get readerOpenBookTimeoutMessage => '開書逾時，可能是系統 WebView 版本過舊或檔案異常';

  @override
  String get readerCopiedToClipboardMessage => '已複製到剪貼簿';

  @override
  String get readerTtsVoicePickerTitle => '朗讀語音';

  @override
  String get readerUnsupportedFormatMessage => '不支援的檔案格式';

  @override
  String get readerFailedToLoadBookMessage => '無法載入書籍';

  @override
  String readerTtsSleepTimerOptionMinutes(int minutes) {
    return '$minutes 分鐘';
  }

  @override
  String get readerTtsSleepTimerNoLimitLabel => '不限時';

  @override
  String get settingsScaffoldTitle => '設定';

  @override
  String get settingsLibraryTooltip => '書架';

  @override
  String get settingsSourceTooltip => '來源';

  @override
  String get settingsAppearanceSectionTitle => '外觀';

  @override
  String get settingsThemeLabel => '佈景';

  @override
  String get settingsThemeLockedHint => '這裡選的是關閉 E-Ink 後要恢復的主題';

  @override
  String settingsThemeDotSemanticsLabel(String themeName) {
    return '$themeName佈景';
  }

  @override
  String settingsThemeDotLockedSemanticsLabel(
    String themeName,
    String currentThemeName,
  ) {
    return '$themeName佈景，已鎖定，這裡選的是關閉 E-Ink 後要恢復的主題，目前選擇：$currentThemeName';
  }

  @override
  String get settingsThemeLight => '淺色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeSepia => '羊皮紙';

  @override
  String get settingsEinkModeLabel => 'E-Ink 高對比模式';

  @override
  String get settingsEinkModeSubtitle => '停用動畫與漸層，以純黑白高對比顯示，專為電子紙螢幕最佳化';

  @override
  String get settingsFontManagementLabel => '字型管理';

  @override
  String get settingsReadingSectionTitle => '閱讀';

  @override
  String get settingsReadingDefaultsLabel => '閱讀預設值';

  @override
  String get settingsNavZoneLabel => '導航熱區';

  @override
  String get settingsTtsDefaultsLabel => '朗讀語音與語速';

  @override
  String get settingsFullTextSearchUnavailableLabel => '全文檢索';

  @override
  String get settingsFullTextSearchUnavailableSubtitle => '本裝置不支援全文檢索';

  @override
  String get settingsFullTextSearchPdfLabel => 'PDF 全文檢索';

  @override
  String get settingsFullTextSearchPdfSubtitle => '部分掃描/圖片型 PDF 可能沒有可搜尋的文字內容';

  @override
  String get settingsFullTextSearchRebuildIndexTooltip => '重建索引';

  @override
  String get settingsFullTextSearchFoliateLabel => '其他格式全文檢索';

  @override
  String get settingsFullTextSearchFoliateSubtitle => 'EPUB／TXT／KF8 等格式的背景索引建置';

  @override
  String get settingsSyncAccountSectionTitle => '同步與帳號';

  @override
  String get settingsSyncLabel => '同步';

  @override
  String get settingsCloudAccountLabel => '已連結的雲端匯入帳戶';

  @override
  String get settingsAboutSectionTitle => '關於';

  @override
  String get settingsAboutLabel => '關於';

  @override
  String get settingsReaderConsoleLogLabel => '閱讀器 Console Log';

  @override
  String get settingsConsoleLogInterceptLabel => 'Console Log 攔截';

  @override
  String get settingsConsoleLogInterceptSubtitle => '關閉後僅保留錯誤訊息，用於問題回報時的診斷紀錄';

  @override
  String get navZoneSettingsTitle => '導航熱區';

  @override
  String get navZoneSettingsPageTurnModeLabel => '翻頁方式';

  @override
  String get navZoneSettingsSimpleModeLabel => '簡單';

  @override
  String get navZoneSettingsCustomModeLabel => '自訂';

  @override
  String get navZoneSettingsShowDebugOverlayLabel => '顯示熱區輔助線';

  @override
  String get navZoneSettingsSaveCustomButton => '儲存自訂熱區設定';

  @override
  String get navZoneActionPreviousPage => '上一頁';

  @override
  String get navZoneActionNextPage => '下一頁';

  @override
  String get navZoneActionMenu => '選單';

  @override
  String get navZoneActionNone => '無動作';

  @override
  String get navZoneCustomValidationError => '至少需要 1 格設為「選單」，否則將無法退出沉浸模式';

  @override
  String get readingDefaultsTitle => '閱讀預設值';

  @override
  String get readingDefaultsVolumeKeyLabel => '音量鍵翻頁';

  @override
  String get readingDefaultsPageTurnModeSectionTitle => '翻頁模式';

  @override
  String get readingDefaultsPaginatedLabel => '點擊翻頁';

  @override
  String get readingDefaultsScrollLabel => '滾動翻頁';

  @override
  String get readingDefaultsScreenOrientationSectionTitle => '螢幕方向';

  @override
  String get readingDefaultsOrientationAutoLabel => '自動旋轉';

  @override
  String get readingDefaultsOrientationLock0Label => '鎖定 0°';

  @override
  String get readingDefaultsOrientationLock90Label => '鎖定 90°';

  @override
  String get readingDefaultsOrientationLock180Label => '鎖定 180°';

  @override
  String get readingDefaultsOrientationLock270Label => '鎖定 270°';

  @override
  String get readingDefaultsTextConversionSectionTitle => '簡繁轉換顯示';

  @override
  String get readingDefaultsTextConversionOriginalLabel => '原文';

  @override
  String get readingDefaultsTextConversionTraditionalLabel => '轉換為繁體';

  @override
  String get readingDefaultsTextConversionSimplifiedLabel => '轉換為簡體';

  @override
  String get readingDefaultsFullscreenLabel => '全螢幕模式';

  @override
  String get readingDefaultsOpenLastBookLabel => '啟動時開啟最後閱讀的那本書';

  @override
  String get readingDefaultsShowHeaderLabel => '顯示頁首';

  @override
  String get readingDefaultsShowFooterLabel => '顯示頁尾';

  @override
  String get ttsDefaultsTitle => '朗讀語音與語速';

  @override
  String get ttsDefaultsVoiceSectionTitle => '語音';

  @override
  String get ttsDefaultsVoiceUnavailableHint => '目前裝置未安裝或不支援語音選擇';

  @override
  String get ttsDefaultsSpeedSectionTitle => '語速';

  @override
  String get syncSettingsTitle => '同步';

  @override
  String get syncSettingsSyncFailedMessage => '同步失敗，請確認網路連線';

  @override
  String get syncSettingsNeverSynced => '尚未同步過';

  @override
  String syncSettingsLastSyncedAt(String formatted) {
    return '最後同步：$formatted';
  }

  @override
  String get syncSettingsConnectionFailedMessage => '連線失敗，請確認伺服器網址與帳號密碼是否正確';

  @override
  String syncSettingsLoggedInAs(String email) {
    return '已登入：$email';
  }

  @override
  String get syncSettingsManualSyncButton => '立即同步';

  @override
  String get syncSettingsLogoutButton => '登出';

  @override
  String get syncSettingsServerUrlLabel => '伺服器網址';

  @override
  String get syncSettingsPasswordLabel => '密碼';

  @override
  String get syncSettingsShowPasswordTooltip => '顯示密碼';

  @override
  String get syncSettingsHidePasswordTooltip => '隱藏密碼';

  @override
  String get syncSettingsConnectButton => '連線／登入';

  @override
  String get cloudAccountSettingsTitle => '已連結的雲端匯入帳戶';

  @override
  String cloudAccountSettingsLinkedEmail(String email) {
    return '已連結：$email';
  }

  @override
  String get cloudAccountSettingsUnlinkButton => '解除連結';

  @override
  String get cloudAccountSettingsUnlinkedText => '未連結';

  @override
  String get cloudAccountSettingsLinkButton => '連結';

  @override
  String get fontManagementTitle => '字型管理';

  @override
  String get fontNameSourceHanSans => '思源黑體';

  @override
  String get fontNameSourceHanSerif => '思源宋體';

  @override
  String get fontManagementUploadTooltip => '上傳字型';

  @override
  String get fontManagementBuiltInSectionLabel => '內建字型';

  @override
  String get fontManagementCustomSectionLabel => '自訂字型';

  @override
  String get fontManagementNoCustomFontsHint => '尚未上傳任何自訂字型';

  @override
  String get fontManagementRenameTooltip => '重新命名';

  @override
  String get fontManagementDeleteTooltip => '刪除';

  @override
  String get fontManagementRenameDialogTitle => '重新命名';

  @override
  String fontManagementDeleteConfirmTitle(String fontName) {
    return '確定要刪除「$fontName」嗎？';
  }

  @override
  String fontManagementDeleteConfirmMessage(int usageCount) {
    String _temp0 = intl.Intl.pluralLogic(
      usageCount,
      locale: localeName,
      other: '目前有 $usageCount 本書使用此字型，刪除後將自動改用預設字型',
      one: '目前有 1 本書使用此字型，刪除後將自動改用預設字型',
    );
    return '$_temp0';
  }

  @override
  String get fontManagementStatusNotDownloaded => '未下載';

  @override
  String get fontManagementStatusDownloaded => '已下載';

  @override
  String get fontManagementDownloadTooltip => '下載';

  @override
  String get fontManagementCancelDownloadTooltip => '取消下載';

  @override
  String get fontManagementRetryTooltip => '重試';

  @override
  String get fontManagementDownloadableDeleteConfirmMessage =>
      '刪除後可以隨時重新下載。使用這款字型的書會暫時改用書本或系統字型，重新下載後自動恢復。';

  @override
  String get fontDownloadErrorNetwork => '無法連線，請檢查網路後重試';

  @override
  String fontDownloadErrorHttp(int statusCode) {
    return '伺服器錯誤（$statusCode），請稍後重試';
  }

  @override
  String get fontDownloadErrorIntegrity => '檔案不完整或已損毀，請重試';

  @override
  String get fontDownloadErrorStorage => '無法儲存檔案，請確認儲存空間是否足夠';

  @override
  String fontManagementUploadBothMessage(int addedCount, int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      addedCount,
      locale: localeName,
      other: '已新增 $addedCount 款字型',
      one: '已新增 1 款字型',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount 款已存在已跳過',
      one: '1 款已存在已跳過',
    );
    return '$_temp0，$_temp1';
  }

  @override
  String fontManagementUploadAddedOnlyMessage(int addedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      addedCount,
      locale: localeName,
      other: '已新增 $addedCount 款字型',
      one: '已新增 1 款字型',
    );
    return '$_temp0';
  }

  @override
  String fontManagementUploadSkippedOnlyMessage(int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount 款字型已存在，已跳過',
      one: '1 款字型已存在，已跳過',
    );
    return '$_temp0';
  }

  @override
  String get readerConsoleLogTitle => '閱讀器 Console Log';

  @override
  String get readerConsoleLogCopyAllTooltip => '複製全部';

  @override
  String get readerConsoleLogClearTooltip => '清空';

  @override
  String get readerConsoleLogEmptyHint => '目前沒有記錄';

  @override
  String get readerConsoleLogCopiedMessage => '已複製全部記錄到剪貼簿';

  @override
  String get aboutScreenTitle => '關於';

  @override
  String get aboutScreenVersionLabel => '版本';

  @override
  String get aboutScreenBuildTimeLabel => '編譯時間';

  @override
  String get aboutScreenWebViewVersionLabel => '系統 WebView 版本';

  @override
  String get aboutScreenViewLicensesButton => '開源授權清單';

  @override
  String get aboutScreenLoadingText => '讀取中...';

  @override
  String get aboutScreenFailedToLoadVersionMessage => '無法取得版本號';

  @override
  String get aboutScreenUnavailableText => '無法取得';

  @override
  String get remoteServerListTitle => '遠端書庫';

  @override
  String get remoteServerListAddTooltip => '新增站點';

  @override
  String get remoteServerListEmptyState => '尚未新增任何遠端書庫站點';

  @override
  String get remoteServerListEditTooltip => '編輯';

  @override
  String get remoteServerListDeleteTooltip => '刪除';

  @override
  String get remoteServerListDeleteConfirmTitle => '刪除站點';

  @override
  String get remoteServerListDeleteConfirmButton => '刪除';

  @override
  String remoteServerListDeleteConfirmMessage(String name) {
    return '確定要刪除站點「$name」嗎？此動作無法復原。';
  }

  @override
  String get remoteServerListDeleteBlockedTitle => '無法刪除站點';

  @override
  String remoteServerListDeleteBlockedMessage(int count, String titles) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '這個站點還有 $count 本書僅有雲端紀錄、尚未下載：',
      one: '這個站點還有 1 本書僅有雲端紀錄、尚未下載：',
    );
    return '$_temp0\n$titles\n\n請先於書架移除這些書籍，或重新下載後再刪除站點。';
  }

  @override
  String get remoteServerListDeleteBlockedConfirmButton => '了解';

  @override
  String get remoteServerListDeleteFailedMessage => '刪除站點失敗，請稍後再試';

  @override
  String get remoteServerFormTitleAdd => '新增站點';

  @override
  String get remoteServerFormTitleEdit => '編輯站點';

  @override
  String get remoteServerFormNameLabel => '站點名稱';

  @override
  String get remoteServerFormBaseUrlLabel => '伺服器網址';

  @override
  String get remoteServerFormTypeOpds => '標準 OPDS';

  @override
  String get remoteServerFormTypeCalibreServer => '原生 Calibre Content Server';

  @override
  String get remoteServerFormUsernameLabel => '帳號（留空代表匿名連線）';

  @override
  String get remoteServerFormPasswordLabelEditing =>
      '密碼（留空＝沿用既有密碼；清空上方帳號欄位則一併清除密碼）';

  @override
  String get remoteServerFormPasswordLabel => '密碼';

  @override
  String get remoteServerFormPasswordShowTooltip => '顯示密碼';

  @override
  String get remoteServerFormPasswordHideTooltip => '隱藏密碼';

  @override
  String get remoteServerFormAllowInsecureLabel => '允許不安全連線（自簽憑證／純 HTTP）';

  @override
  String get remoteServerFormValidationMissingFields => '請填寫站點名稱與網址';

  @override
  String get remoteServerFormValidationInvalidUrl =>
      '請輸入有效的伺服器網址（需以 http:// 或 https:// 開頭）';

  @override
  String get remoteServerFormSaveFailedMessage => '儲存失敗，請稍後再試';

  @override
  String get remoteServerFormTestSuccess => '連線成功';

  @override
  String get remoteServerFormTestFailed => '連線失敗，請檢查網址/帳密/憑證設定';

  @override
  String get remoteServerFormTestConnectionButton => '測試連線';

  @override
  String get remoteServerFormSaveButton => '儲存';

  @override
  String formatSelectionDialogTitle(String title) {
    return '選擇格式：$title';
  }

  @override
  String get formatSelectionDialogUnsupportedFormat => '不支援的格式';

  @override
  String get cloudDuplicateDialogTitle => '重複的書籍';

  @override
  String get cloudDuplicateDialogConfirmButton => '仍要建立';

  @override
  String get remoteCatalogLoadFailedMessage => '載入失敗，請檢查網路連線或站點設定';

  @override
  String get remoteCatalogDownloadSelectedTooltip => '下載已選取';

  @override
  String remoteCatalogDuplicateConfirmMessage(String title) {
    return '「$title」之前匯入過了，仍要建立新的一份嗎？';
  }

  @override
  String remoteCatalogQueuedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個檔案',
      one: '1 個檔案',
    );
    return '已加入下載佇列（$_temp0），可至「來源」畫面查看進度';
  }

  @override
  String get remoteCatalogEinkPrevPageButton => '上一頁';

  @override
  String get remoteCatalogEinkNextPageButton => '下一頁';

  @override
  String get remoteCatalogLoadMoreButton => '載入更多';

  @override
  String get remoteCatalogDuplicateDialogTitle => '重複的書籍';

  @override
  String get remoteCatalogDuplicateDialogConfirmButton => '仍要建立';

  @override
  String get wifiTransferLeaveConfirmTitle => '目前尚有檔案正在傳輸';

  @override
  String get wifiTransferLeaveConfirmMessage => '離開將中斷連線，是否確定離開？';

  @override
  String get wifiTransferLeaveConfirmButton => '確定離開';

  @override
  String get wifiTransferTitle => 'WiFi 傳書';

  @override
  String get wifiTransferInstructionText => '在同一個 WiFi 下，用瀏覽器打開以下網址：';

  @override
  String wifiTransferActiveCountText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '正在傳輸中（$count 個檔案）…',
      one: '正在傳輸中（1 個檔案）…',
    );
    return '$_temp0';
  }

  @override
  String get wifiTransferUnavailableText => '請連線至 WiFi 或開啟手機熱點';

  @override
  String get wifiTransferManualOverrideButton => '我確定目前是用手機熱點';

  @override
  String get wifiTransferNoInterfacesText => '找不到任何可用網路介面';

  @override
  String get downloadQueueTitle => '下載佇列';

  @override
  String get downloadQueueCancelTooltip => '取消';

  @override
  String get downloadQueueRetryTooltip => '重試';

  @override
  String get downloadQueueDismissTooltip => '從清單移除';

  @override
  String get downloadQueueStatusPending => '待機';

  @override
  String get downloadQueueStatusDownloading => '下載中';

  @override
  String get downloadQueueStatusCheckingDuplicate => '比對中';

  @override
  String get downloadQueueStatusDone => '完成';

  @override
  String get downloadQueueStatusDuplicateSkipped => '重複已略過';

  @override
  String get downloadQueueStatusFailed => '失敗';

  @override
  String get downloadQueueStatusCancelled => '已取消';

  @override
  String downloadQueueDuplicateConfirmMessage(String name) {
    return '偵測到「$name」與本機已有的一本書內容相同，仍要建立新的一份嗎？';
  }

  @override
  String get sourcesHomeTitle => '來源';

  @override
  String get sourcesHomeLibraryTooltip => '書架';

  @override
  String get sourcesHomeSettingsTooltip => '設定';

  @override
  String get sourcesHomeLocalSection => '本機';

  @override
  String get sourcesHomePickFilesTitle => '選擇檔案（可多選）';

  @override
  String get sourcesHomePickFolderTitle => '選擇資料夾';

  @override
  String get sourcesHomeWifiTransferTile => 'WiFi 傳書';

  @override
  String get sourcesHomeConnectedServicesSection => '已連結服務';

  @override
  String get sourcesHomeCloudNotLinkedSubtitle => '尚未連結，請至設定畫面連結帳戶';

  @override
  String get sourcesHomeRemoteLibraryTitle => '遠端書庫（OPDS）';

  @override
  String get sourcesHomeRemoteLibraryNotConfiguredSubtitle => '尚未設定遠端書庫伺服器';

  @override
  String get libraryImportFolderDialogTitle => '匯入資料夾';

  @override
  String get libraryImportFolderAutoGroupLabel => '依資料夾名稱自動建立分類';

  @override
  String get libraryImportFolderConfirmButton => '匯入';

  @override
  String libraryImportResultBothMessage(int importedCount, int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      importedCount,
      locale: localeName,
      other: '已匯入 $importedCount 本',
      one: '已匯入 1 本',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount 本已存在，已跳過',
      one: '1 本已存在，已跳過',
    );
    return '$_temp0，$_temp1';
  }

  @override
  String libraryImportResultImportedOnlyMessage(int importedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      importedCount,
      locale: localeName,
      other: '已匯入 $importedCount 本書',
      one: '已匯入 1 本書',
    );
    return '$_temp0';
  }

  @override
  String libraryImportResultSkippedOnlyMessage(int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount 本已存在，已跳過',
      one: '1 本已存在，已跳過',
    );
    return '$_temp0';
  }

  @override
  String get layoutPresetBookPickerTitleMulti => '選擇書籍（可複選）';

  @override
  String get layoutPresetBookPickerTitleSingle => '選擇書籍';

  @override
  String get layoutPresetBookPickerSearchHint => '搜尋書名或作者';

  @override
  String get layoutPresetBookPickerEmptyBooks => '沒有可選擇的流式 EPUB 書籍';

  @override
  String get layoutPresetBookPickerNoMatch => '找不到符合的書籍';

  @override
  String get layoutPresetNameDialogTitle => '為預設集命名';

  @override
  String get layoutPresetNameDialogEmptyError => '名稱不可為空';

  @override
  String get layoutPresetNameDialogSaveButton => '儲存';

  @override
  String markdownExportTitle(String bookTitle) {
    return '# 閱讀筆記：《$bookTitle》';
  }

  @override
  String markdownExportAuthorLabel(String author) {
    return '*   **作者**：$author';
  }

  @override
  String get markdownExportUnknownAuthor => '未知作者';

  @override
  String markdownExportProgressLabel(int percent) {
    return '*   **閱讀進度**：$percent%';
  }

  @override
  String markdownExportTimeLabel(String time) {
    return '*   **導出時間**：$time';
  }

  @override
  String markdownExportBookmarksSection(int count) {
    return '## 🔖 書籤清單 ($count)';
  }

  @override
  String get markdownExportNoBookmarks => '*(尚未加入書籤)*';

  @override
  String markdownExportAnnotationsSection(int count) {
    return '## ✏️ 劃線與個人備註 ($count)';
  }

  @override
  String get markdownExportNoAnnotations => '*(尚未加入任何劃線或備註)*';

  @override
  String markdownExportAnnotationHeading(String label, String position) {
    return '### 📌 $label（位置：$position）';
  }

  @override
  String bookmarkDefaultNamePdfPage(int page) {
    return '第 $page 頁';
  }

  @override
  String bookmarkDefaultNamePercent(int percent) {
    return '$percent% 處';
  }

  @override
  String get bookmarkDefaultNameFallback => '書籤';

  @override
  String get ttsNotificationChannelName => '朗讀播放中';

  @override
  String get ttsVoiceSystemDefault => '系統預設語音';

  @override
  String get remoteCatalogUnnamedCategory => '未命名分類';

  @override
  String get remoteCatalogUnknownBookTitle => '未知書名';

  @override
  String get wifiPageTitle => 'elinkBook WiFi 傳書';

  @override
  String get wifiPageUploadHeading => '上傳書籍';

  @override
  String get wifiPageDropzoneText => '拖放檔案到此處，或';

  @override
  String get wifiPageChooseFile => '選擇檔案';

  @override
  String get wifiPageDownloadHeading => '下載書籍';

  @override
  String get wifiPageSearchPlaceholder => '搜尋書名…';

  @override
  String get wifiPageSelectPage => '全選目前頁';

  @override
  String get wifiPageClearSelection => '清除勾選';

  @override
  String wifiPageSelectedCount(String count) {
    return '已勾選 $count 本';
  }

  @override
  String get wifiPageLoading => '載入中…';

  @override
  String get wifiPagePrevPage => '上一頁';

  @override
  String get wifiPageNextPage => '下一頁';

  @override
  String wifiPagePageInfo(String page, String total) {
    return '第 $page / $total 頁';
  }

  @override
  String get wifiPageDownloadSelected => '下載已勾選書籍';

  @override
  String get wifiPageNoBooks => '目前沒有可下載的書籍';

  @override
  String get wifiPageNoMatch => '查無符合條件的書籍';

  @override
  String get wifiPageLoadFailed => '無法載入書籍清單';

  @override
  String wifiPageTotalBooks(String count) {
    return '共 $count 本書籍';
  }

  @override
  String wifiPageMatchStats(String matched, String total) {
    return '符合 $matched 本 / 共 $total 本';
  }

  @override
  String get wifiPageSelectAtLeastOne => '請至少勾選一本書';

  @override
  String get wifiPageDownloading => '下載中…';

  @override
  String wifiPageDownloadTriggered(String count) {
    return '已觸發全部下載（共 $count 本）';
  }

  @override
  String get wifiPageOutcomeImported => '已匯入';

  @override
  String get wifiPageOutcomeDuplicateSkipped => '已存在，已略過';

  @override
  String get wifiPageOutcomeUnsupportedFormat => '格式不支援';

  @override
  String get wifiPageOutcomeFailed => '匯入失敗';

  @override
  String wifiPageUploadResultLine(String name, String outcome) {
    return '$name：$outcome';
  }

  @override
  String get wifiPageUnknownFileName => '(未知檔名)';

  @override
  String get wifiPageUploadPreparing => '準備上傳…';

  @override
  String get wifiPageUploading => '正在上傳…';

  @override
  String wifiPageUploadingPercent(String percent) {
    return '正在上傳… ($percent%)';
  }

  @override
  String get wifiPageUploadProcessing => '上傳完成，手機端處理與匯入中，請稍候…';

  @override
  String get wifiPageUnknownSize => '未知';

  @override
  String wifiPageUploadFailedServer(String status) {
    return '上傳失敗：伺服器回應錯誤 ($status)';
  }

  @override
  String get wifiPageUploadFailedParse => '上傳失敗：無法解析伺服器回應';

  @override
  String get wifiPageUploadFailedNetwork => '上傳失敗：網路錯誤';

  @override
  String get wifiPageUploadAborted => '上傳已中斷';

  @override
  String get wifiPageUploadTimeout => '上傳逾時';
}
