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
  String readerSaveAsPresetFailedMessage(String error) {
    return '另存為新預設集失敗：$error';
  }

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
  String readerApplyPresetFailedMessage(String error) {
    return '套用版面設定失敗：$error';
  }

  @override
  String get readerConfirmDeleteTitle => '確認刪除';

  @override
  String readerDeletePresetConfirmMessage(String name) {
    return '即將刪除預設集「$name」，此動作無法復原。';
  }

  @override
  String readerDeletePresetFailedMessage(String error) {
    return '刪除預設集失敗：$error';
  }

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
  String readerSaveAsPresetFailedMessage(String error) {
    return '另存为新预设集失败：$error';
  }

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
  String readerApplyPresetFailedMessage(String error) {
    return '套用版面设定失败：$error';
  }

  @override
  String get readerConfirmDeleteTitle => '确认删除';

  @override
  String readerDeletePresetConfirmMessage(String name) {
    return '即将删除预设集“$name”，此操作无法复原。';
  }

  @override
  String readerDeletePresetFailedMessage(String error) {
    return '删除预设集失败：$error';
  }

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
  String readerSaveAsPresetFailedMessage(String error) {
    return '另存為新預設集失敗：$error';
  }

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
  String readerApplyPresetFailedMessage(String error) {
    return '套用版面設定失敗：$error';
  }

  @override
  String get readerConfirmDeleteTitle => '確認刪除';

  @override
  String readerDeletePresetConfirmMessage(String name) {
    return '即將刪除預設集「$name」，此動作無法復原。';
  }

  @override
  String readerDeletePresetFailedMessage(String error) {
    return '刪除預設集失敗：$error';
  }

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
}
