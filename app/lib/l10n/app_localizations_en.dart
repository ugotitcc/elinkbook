// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get groupUncategorized => 'Uncategorized';

  @override
  String get close => 'Close';

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get settingsLanguageFollowSystem => 'Follow System';

  @override
  String settingsLanguageFollowSystemSubtitle(String language) {
    return 'Follow System ($language)';
  }

  @override
  String get settingsLanguageZhTW => '正體中文';

  @override
  String get settingsLanguageZhCN => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'OK';

  @override
  String get errorOperationFailed =>
      'Operation failed. Please try again later.';

  @override
  String get libraryGroupManageTitle => 'Manage Categories';

  @override
  String get libraryGroupAddFieldLabel => 'New category name';

  @override
  String get libraryGroupAddButton => 'Add';

  @override
  String get libraryGroupRenameTitle => 'Rename Category';

  @override
  String get libraryGroupDeleteTitle => 'Delete Category';

  @override
  String libraryGroupDeleteConfirmMessage(String name, String uncategorized) {
    return 'Delete category \"$name\"? Books in this category will be moved to \"$uncategorized\".';
  }

  @override
  String get libraryGroupDeleteButton => 'Delete';

  @override
  String libraryGroupReservedNameError(String name) {
    return '\"$name\" is a reserved category name. Please use a different name.';
  }

  @override
  String libraryGroupNameAlreadyExistsError(String name) {
    return '\"$name\" already exists. Please use a different name.';
  }

  @override
  String get libraryMoveToGroupTitle => 'Move to Category';

  @override
  String get errorNetworkConnection =>
      'Failed to load. Please check your network connection.';

  @override
  String cloudBrowserDuplicateConfirmMessage(String name) {
    return '\"$name\" was already imported before. Create a new copy anyway?';
  }

  @override
  String cloudBrowserDownloadQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return 'Added to download queue ($_temp0), check progress in the Sources screen';
  }

  @override
  String get cloudBrowserMobileDataDialogTitle => 'Mobile Data Download Notice';

  @override
  String get cloudBrowserMobileDataDialogMessage =>
      'You\'re currently on a mobile data connection, and some selected files are over 20MB. Downloading may incur data charges. Continue anyway?';

  @override
  String get cloudBrowserMobileDataDialogConfirm => 'Continue Download';

  @override
  String get cloudBrowserDownloadSelectedTooltip => 'Download Selected';

  @override
  String cloudBrowserReauthMessage(String provider) {
    return 'Login expired. Please reconnect your $provider account in Settings.';
  }

  @override
  String get cloudBrowserGenericProviderLabel => 'cloud';

  @override
  String get cloudBrowserImportCategoryLabel => 'Import to category:';

  @override
  String get cloudBrowserTruncatedNotice =>
      'This folder has many files; only the first 1000 are shown.';

  @override
  String get bookActionShowDetails => 'Details';

  @override
  String get bookActionMove => 'Move';

  @override
  String get bookActionLayoutOverride => 'Layout Override';

  @override
  String get bookActionRemoveCache => 'Remove Cache';

  @override
  String get bookActionDelete => 'Delete';

  @override
  String get fullTextSearchEnableDialogTitle => 'Enable Full-Text Search';

  @override
  String get fullTextSearchEnableMessagePdf =>
      'This will start background indexing (including existing books in your library), which increases CPU and battery usage. Continue?\n\nSome scanned/image-based PDFs may not contain searchable text — it\'s normal if they still can\'t be found after indexing.';

  @override
  String get fullTextSearchEnableMessageOther =>
      'This will start background indexing (including existing books in your library), which increases CPU and battery usage. Continue?';

  @override
  String get fullTextSearchEnableConfirmButton => 'Enable';

  @override
  String get bookSearchHint => 'Search in this book...';

  @override
  String get searchClearTooltip => 'Clear';

  @override
  String get fullTextSearchUnavailableMessage =>
      'Full-text search is not supported on this device';

  @override
  String bookSearchResultsSummary(int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total results',
      one: '1 result',
    );
    return '$_temp0';
  }

  @override
  String bookSearchResultsSummaryTruncated(int shown, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total results',
      one: '1 result',
    );
    return 'Showing first $shown of $_temp0';
  }

  @override
  String get bookSearchSortByPosition => 'By book order';

  @override
  String get bookSearchSortByRelevance => 'By relevance';

  @override
  String get fullTextSearchNoContentMatches => 'No matching content found';

  @override
  String bookSearchLocationPage(int page) {
    return 'Page $page';
  }

  @override
  String bookSearchLocationChapter(int chapter) {
    return 'Chapter $chapter';
  }

  @override
  String get librarySearchSettingsSheetTitle => 'Full-Text Search Settings';

  @override
  String get librarySearchScreenTitle => 'Search Book Content';

  @override
  String get librarySearchSettingsTooltip => 'Full-Text Search Settings';

  @override
  String get librarySearchFieldHint => 'Search by title, author, or content...';

  @override
  String get librarySearchTitleAuthorSectionHeader => 'Title/Author Matches';

  @override
  String get librarySearchContentSectionHeader => 'Content Matches';

  @override
  String get librarySearchGuidanceNotEnabled =>
      'Full-text search is not enabled yet. Enable it to search book content (tap the settings icon in the top right).';

  @override
  String get librarySearchGuidancePdfOnly =>
      '\"PDF\" full-text search is enabled; other formats are not yet enabled';

  @override
  String get librarySearchGuidanceOtherOnly =>
      '\"Other formats\" full-text search is enabled; PDF content is not yet enabled';

  @override
  String librarySearchDrillDownButton(int total, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'View all $total results',
      one: 'View all 1 result',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining more',
      one: '1 more',
    );
    return '$_temp0 ($_temp1)';
  }

  @override
  String get librarySearchPdfToggleTitle => 'PDF Full-Text Search';

  @override
  String get librarySearchPdfToggleSubtitle =>
      'Some scanned/image-based PDFs may not have searchable text';

  @override
  String get librarySearchRebuildIndexTooltip => 'Rebuild Index';

  @override
  String get librarySearchFoliateToggleTitle =>
      'Other Formats Full-Text Search';

  @override
  String get librarySearchFoliateToggleSubtitle =>
      'Background indexing for EPUB, TXT, KF8, and other formats';

  @override
  String get libraryBackButtonTooltip => 'Back';

  @override
  String get libraryShelfTitle => 'Library';

  @override
  String get librarySortViewTooltip => 'Sort & View';

  @override
  String get librarySortByLastRead => 'Last Read';

  @override
  String get librarySortByCreateTime => 'Date Added';

  @override
  String get librarySortByAuthor => 'Author';

  @override
  String get librarySortByTitle => 'Title';

  @override
  String get libraryToggleViewToList => 'Switch to List';

  @override
  String get libraryToggleViewToShelf => 'Switch to Grid';

  @override
  String get libraryManageGroupsMenuItem => 'Manage Categories...';

  @override
  String get librarySourceTooltip => 'Sources';

  @override
  String get librarySettingsTooltip => 'Settings';

  @override
  String get libraryCancelSelectionTooltip => 'Cancel Selection';

  @override
  String librarySelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String get libraryMoveToGroupTooltip => 'Move to Category';

  @override
  String get libraryForceFxlTooltip => 'Force Fixed Layout';

  @override
  String get libraryRestoreAutoLayoutTooltip => 'Restore Auto-Detect';

  @override
  String get libraryDeleteTooltip => 'Delete';

  @override
  String get libraryRemoveLocalCacheTooltip => 'Remove Local Cache';

  @override
  String get libraryEmptyStateMessage => 'No books imported yet';

  @override
  String get libraryEmptyStateImportButton => 'Import Books';

  @override
  String get librarySearchHint => 'Search by title or author...';

  @override
  String get libraryContentSearchEntryLabel => 'Search Book Content';

  @override
  String get libraryNoMatchingBooks => 'No matching books found';

  @override
  String get libraryDeleteBooksDialogTitle => 'Delete Books';

  @override
  String libraryDeleteBooksConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This will delete the $count selected books, including their bookmarks, highlights, and notes. This cannot be undone. Delete anyway?',
      one:
          'This will delete the 1 selected book, including its bookmarks, highlights, and notes. This cannot be undone. Delete anyway?',
    );
    return '$_temp0';
  }

  @override
  String get libraryDeleteBooksConfirmButton => 'Delete';

  @override
  String get libraryRedownloadAction => 'Redownload';

  @override
  String libraryRedownloadConfirmMessage(String title) {
    return 'About to redownload \"$title\". Continue?';
  }

  @override
  String libraryRedownloadConfirmMessageMobileData(String title) {
    return 'About to redownload \"$title\" on a mobile data connection, which may incur data charges. Continue?';
  }

  @override
  String get libraryRemoteDisabledMessage =>
      'Remote library feature is not enabled; cannot redownload';

  @override
  String get libraryRemoteServerNotFoundMessage =>
      'Could not find the matching remote library server';

  @override
  String get libraryRedownloadFailedMessage =>
      'Redownload failed. Please try again later.';

  @override
  String libraryRemoveCacheConfirmMessage(String title) {
    return 'This will remove the local file for \"$title\". The book record and reading progress will be kept, and you can redownload it later. Remove anyway?';
  }

  @override
  String get libraryRemoveCacheConfirmButton => 'Remove';

  @override
  String get libraryGroupBadgeLabel => 'Category';

  @override
  String libraryGroupTileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books',
      one: '1 book',
    );
    return '$_temp0';
  }

  @override
  String get libraryBookMenuTooltip => 'More';

  @override
  String get libraryContinueReadingLabel => 'Continue Reading';

  @override
  String get libraryBookNotDownloaded => 'Not downloaded';

  @override
  String get libraryUnknownFileSize => 'Unknown size';

  @override
  String get libraryLoadingEllipsis => 'Loading...';

  @override
  String libraryDetailAuthorLabel(String author) {
    return 'Author: $author';
  }

  @override
  String get libraryUnknownAuthor => 'Unknown';

  @override
  String libraryDetailFormatLabel(String format) {
    return 'Format: $format';
  }

  @override
  String libraryDetailFileSizeLabel(String size) {
    return 'File size: $size';
  }

  @override
  String libraryDetailProgressLabel(String progress) {
    return 'Progress: $progress';
  }

  @override
  String libraryDetailLastReadLabel(String date) {
    return 'Last read: $date';
  }

  @override
  String get libraryNeverRead => 'Never read';

  @override
  String get libraryLayoutOverrideTitle => 'Layout Override';

  @override
  String get libraryLayoutOverrideWritingModeLabel => 'Writing Mode';

  @override
  String get libraryLayoutOverrideWritingModeDefault => 'Use Book\'s Layout';

  @override
  String get libraryLayoutOverrideWritingModeHorizontal => 'Horizontal';

  @override
  String get libraryLayoutOverrideWritingModeVertical => 'Vertical';

  @override
  String get libraryLayoutOverridePageTurnModeLabel => 'Page Turn Mode';

  @override
  String get libraryLayoutOverridePageTurnModeDefault => 'Use Global Default';

  @override
  String get libraryLayoutOverridePageTurnModePaginated => 'Paginated';

  @override
  String get libraryLayoutOverridePageTurnModeScroll => 'Scroll';

  @override
  String get libraryLayoutOverrideSaveButton => 'Save';

  @override
  String get readerBackTooltip => 'Back';

  @override
  String get readerSearchTooltip => 'Search in book';

  @override
  String get readerHideToolbarTooltip => 'Hide toolbar';

  @override
  String get readerShowToolbarTooltip => 'Show toolbar';

  @override
  String get readerTocTooltip => 'Table of contents';

  @override
  String get readerBookmarkAddedTooltip => 'Bookmarked';

  @override
  String get readerBookmarkAddTooltip => 'Add bookmark';

  @override
  String get readerAnnotationsTooltip => 'Highlights & notes';

  @override
  String get readerLayoutTooltip => 'Layout';

  @override
  String get readerTtsTooltip => 'Read aloud';

  @override
  String get readerPagingPreviousTooltip => 'Previous page';

  @override
  String get readerPagingNextTooltip => 'Next page';

  @override
  String get readerPdfNoPagesAvailable => 'No pages available';

  @override
  String get readerNoteDialogSaveButton => 'Save';

  @override
  String get readerNoteDialogDefaultTitle => 'Note';

  @override
  String get readerAnnotationUnderlineTooltip => 'Underline';

  @override
  String get readerAnnotationCopyTooltip => 'Copy';

  @override
  String get readerAnnotationEditNoteTooltip => 'Edit note';

  @override
  String get readerAnnotationAddNoteTooltip => 'Add note';

  @override
  String get readerAnnotationDeleteHighlightAndNote =>
      'Delete highlight & note';

  @override
  String get readerAnnotationDeleteHighlight => 'Delete highlight';

  @override
  String get readerAnnotationDeleteNote => 'Delete note';

  @override
  String get readerPdfSearchHint => 'Search text…';

  @override
  String get readerPdfSearchNoMatches => 'No matching text found';

  @override
  String get readerPdfSearchPreviousTooltip => 'Previous';

  @override
  String get readerPdfSearchNextTooltip => 'Next';

  @override
  String readerPositionConflictTitle(String bookTitle) {
    return 'Reading position for “$bookTitle” doesn\'t match';
  }

  @override
  String readerPositionConflictMessage(String local, String remote) {
    return 'Another device also updated the reading position for this book. Choose which one to keep:\n\nThis device: $local\nCloud: $remote';
  }

  @override
  String readerPositionConflictPdfLocation(int page, int percent) {
    return 'Page $page ($percent% progress)';
  }

  @override
  String readerPositionConflictEpubLocation(int percent) {
    return '$percent% progress';
  }

  @override
  String get readerPositionConflictKeepCloud => 'Keep cloud';

  @override
  String get readerPositionConflictKeepLocal => 'Keep this device';

  @override
  String get readerTocTitle => '📖 Table of Contents';

  @override
  String get readerTocEmptyMessage => 'This book has no table of contents';

  @override
  String get readerTocTabChapters => 'Chapters';

  @override
  String get readerTocTabThumbnails => 'Thumbnails';

  @override
  String get readerTocTabSearch => 'Search';

  @override
  String get readerFeatureComingSoon =>
      'This feature is coming in a future version';

  @override
  String get readerTtsCbzUnsupportedTooltip =>
      'CBZ is image-only and doesn\'t support read-aloud';

  @override
  String get readerTtsPreviousTooltip => 'Previous sentence';

  @override
  String get readerTtsPauseTooltip => 'Pause';

  @override
  String get readerTtsPlayTooltip => 'Play';

  @override
  String get readerTtsNextTooltip => 'Next sentence';

  @override
  String readerTtsSpeedTooltip(String speed) {
    return 'Speed: ${speed}x (tap to change)';
  }

  @override
  String get readerTtsVoiceTooltip => 'Choose voice';

  @override
  String get readerTtsSleepTimerLabel => 'Timer';

  @override
  String readerTtsSleepTimerLabelWithMinutes(int minutes) {
    return 'Timer $minutes min';
  }

  @override
  String get readerTtsCollapseLabel => 'Collapse';

  @override
  String get readerTtsExpandLabel => 'Expand';

  @override
  String get readerTtsStopLabel => 'Stop';

  @override
  String get readerNotesSheetTitle => 'Notes';

  @override
  String get readerNotesSheetExportMarkdownTooltip => 'Export as Markdown';

  @override
  String get readerNotesSheetTabBookmarks => 'Bookmarks';

  @override
  String get readerNotesSheetTabAnnotations => 'Highlights & Notes';

  @override
  String get readerNotesSheetDeleteAllBookmarksTooltip =>
      'Delete all bookmarks for this book';

  @override
  String get readerNotesSheetRenameBookmarkTitle => 'Rename bookmark';

  @override
  String get readerDeleteConfirmButton => 'Delete';

  @override
  String readerNotesSheetDeleteAllBookmarksConfirm(int count) {
    return 'Delete all $count bookmark(s)?';
  }

  @override
  String get readerNotesSheetRenameTooltip => 'Rename';

  @override
  String get readerNotesSheetDeleteItemTooltip => 'Delete';

  @override
  String get readerNotesSheetNoAnnotationsPlaceholder =>
      'No highlights or notes yet';

  @override
  String get readerNotesSheetDeleteAllHighlightsButton =>
      'Delete all highlights';

  @override
  String get readerNotesSheetDeleteAllNotesButton => 'Delete all notes';

  @override
  String get readerNotesSheetNoteLabel => 'Note';

  @override
  String get readerHighlightStyleYellow => 'Highlighter (Yellow)';

  @override
  String get readerHighlightStylePink => 'Highlighter (Pink)';

  @override
  String get readerHighlightStyleBlue => 'Highlighter (Blue)';

  @override
  String get readerHighlightStyleUnderline => 'Underline';

  @override
  String readerNotesSheetDeleteAllHighlightsConfirm(int count) {
    return 'Delete all $count highlight(s)?';
  }

  @override
  String readerNotesSheetDeleteAllNotesConfirm(int count) {
    return 'Delete all $count note(s)?';
  }

  @override
  String get readerFxlSettingsTitle => '⚙️ Comic Layout Settings';

  @override
  String get readerDualPageModeLabel => 'Dual-page mode';

  @override
  String get readerDualPageAutoTooltip => 'Auto (dual-page in landscape)';

  @override
  String get readerDualPageAutoLabel => 'Auto';

  @override
  String get readerDualPageAlwaysTooltip => 'Always dual-page';

  @override
  String get readerDualPageAlwaysLabel => 'Dual';

  @override
  String get readerDualPageNeverTooltip => 'Always single-page';

  @override
  String get readerDualPageNeverLabel => 'Single';

  @override
  String get readerPageDirectionLabel => 'Page direction';

  @override
  String get readerDualPageDirectionLtrTooltip =>
      'Left to right (LTR, Western comic convention)';

  @override
  String get readerDualPageDirectionLtrLabel => 'LTR';

  @override
  String get readerDualPageDirectionRtlTooltip =>
      'Right to left (RTL, manga convention)';

  @override
  String get readerDualPageDirectionRtlLabel => 'RTL';

  @override
  String get readerTextConversionOverrideLabel => 'Script conversion override';

  @override
  String get readerGlobalLabel => 'Global';

  @override
  String get readerUseGlobalDefaultTooltip => 'Use global default';

  @override
  String get readerTextConversionOriginalLabel => 'Original';

  @override
  String get readerTextConversionTraditionalLabel => 'Traditional';

  @override
  String get readerTextConversionTraditionalTooltip => 'Convert to Traditional';

  @override
  String get readerTextConversionSimplifiedLabel => 'Simplified';

  @override
  String get readerTextConversionSimplifiedTooltip => 'Convert to Simplified';

  @override
  String get readerFullscreenModeLabel => 'Fullscreen mode';

  @override
  String get readerShowHeaderLabel => 'Show header';

  @override
  String get readerShowFooterLabel => 'Show footer';

  @override
  String get readerPdfSettingsTitle => '⚙️ PDF Layout Settings';

  @override
  String get readerPdfSettingsTabDisplay => 'Display';

  @override
  String get readerPdfSettingsTabFilters => 'Filters';

  @override
  String get readerPdfSettingsTabCrop => 'Crop';

  @override
  String get readerPdfFitModeLabel => 'Fit mode';

  @override
  String get readerPdfFitPageTooltip => 'Page-fit';

  @override
  String get readerPdfFitPageLabel => 'Page';

  @override
  String get readerPdfFitWidthTooltip => 'Fit Width';

  @override
  String get readerPdfFitWidthLabel => 'Width';

  @override
  String get readerPdfFitActualTooltip => 'Actual size 1:1';

  @override
  String get readerPdfFitActualLabel => 'Actual';

  @override
  String get readerPdfDualPageCoverAloneLabel => 'Show cover alone';

  @override
  String get readerPdfPageOrientationLabel => 'Page direction';

  @override
  String get readerPdfDirectionLtrTooltip => 'Left to right';

  @override
  String get readerPdfDirectionLtrLabel => 'LTR';

  @override
  String get readerPdfDirectionRtlTooltip => 'Right to left (manga convention)';

  @override
  String get readerPdfDirectionRtlLabel => 'RTL';

  @override
  String get readerPdfPageTurnAnimationLabel => 'Page-turn animation';

  @override
  String get readerPdfPageTurnAnimationSlide => 'Slide';

  @override
  String get readerPdfPageTurnAnimationNone => 'None';

  @override
  String get readerPdfContrastLabel => 'Contrast';

  @override
  String get readerPdfBrightnessLabel => 'Brightness';

  @override
  String get readerPdfBoldStrengthLabel => 'Bold strength';

  @override
  String get readerPdfCropModeLabel => 'Crop mode';

  @override
  String get readerPdfCropNoneTooltip => 'No crop';

  @override
  String get readerPdfCropNoneLabel => 'None';

  @override
  String get readerPdfCropAutoTooltip => 'Smart auto-crop';

  @override
  String get readerPdfCropAutoLabel => 'Smart';

  @override
  String get readerPdfCropManualLabel => 'Manual';

  @override
  String get readerPdfCropManualTooltip => 'Manual selection';

  @override
  String get readerSettingsTitle => '⚙️ Layout Settings';

  @override
  String get readerSettingsTabText => 'Text';

  @override
  String get readerSettingsTabBoundary => 'Margins';

  @override
  String get readerSettingsTabPresentation => 'Display';

  @override
  String get readerSettingsTabPreferences => 'Presets';

  @override
  String get readerSettingsFontSizeLabel => 'Font size';

  @override
  String get readerSettingsFontWeightLabel => 'Font weight';

  @override
  String get readerSettingsLineHeightLabel => 'Line height';

  @override
  String get readerSettingsParagraphSpacingLabel => 'Paragraph spacing';

  @override
  String get readerSettingsLetterSpacingLabel => 'Letter spacing';

  @override
  String get readerSettingsDisableBookCssLabel => 'Disable book CSS';

  @override
  String get readerSettingsMarginTopLabel => 'Top margin';

  @override
  String get readerSettingsMarginBottomLabel => 'Bottom margin';

  @override
  String get readerSettingsMarginLeftLabel => 'Left margin';

  @override
  String get readerSettingsMarginRightLabel => 'Right margin';

  @override
  String get readerSettingsOverriddenBadge => 'Overridden for this book';

  @override
  String get readerSettingsResetToBookStyleTooltip =>
      'Reset to book\'s original style';

  @override
  String get readerSettingsNotOverriddenTooltip =>
      'Following book\'s original style, not yet adjusted';

  @override
  String get readerSettingsUseBookFontLabel => 'Use book\'s built-in font';

  @override
  String get readerSettingsFontFamilyLabel => 'Font';

  @override
  String get readerSettingsColumnCountLabel => 'Columns';

  @override
  String get readerSettingsColumnAutoLabel => 'Auto';

  @override
  String get readerSettingsColumnSingleLabel => 'Single';

  @override
  String get readerSettingsColumnDoubleLabel => 'Double';

  @override
  String get readerSettingsColumnSizeLabel => 'Column size';

  @override
  String readerSettingsColumnSizeWithValueLabel(int size) {
    return 'Column size ${size}px';
  }

  @override
  String get readerSettingsTextAlignLabel => 'Text align';

  @override
  String get readerSettingsTextAlignCenterLabel => 'Center';

  @override
  String get readerSettingsTextAlignJustifyTooltip => 'Justify';

  @override
  String get readerSettingsTextAlignJustifyLabel => 'Justify';

  @override
  String get readerSettingsTextAlignStartTooltip => 'Align to start edge';

  @override
  String get readerSettingsTextAlignStartLabel => 'Start';

  @override
  String get readerSettingsTextAlignEndTooltip => 'Align to end edge';

  @override
  String get readerSettingsTextAlignEndLabel => 'End';

  @override
  String get readerSettingsTextAlignLeftLabel => 'Left';

  @override
  String get readerSettingsTextAlignRightLabel => 'Right';

  @override
  String get readerSettingsWritingModeLabel => 'Writing mode override';

  @override
  String get readerSettingsWritingModeBookTooltip => 'Use book\'s writing mode';

  @override
  String get readerSettingsWritingModeBookLabel => 'Book';

  @override
  String get readerSettingsWritingModeVerticalTooltip => 'Force vertical';

  @override
  String get readerSettingsWritingModeVerticalLabel => 'Vertical';

  @override
  String get readerSettingsWritingModeHorizontalTooltip => 'Force horizontal';

  @override
  String get readerSettingsWritingModeHorizontalLabel => 'Horizontal';

  @override
  String get readerSettingsPageTurnModeLabel => 'Page-turn mode override';

  @override
  String get readerSettingsPageTurnPaginatedTooltip => 'Tap to turn page';

  @override
  String get readerSettingsPageTurnPaginatedLabel => 'Tap';

  @override
  String get readerSettingsPageTurnScrollTooltip => 'Scroll to read';

  @override
  String get readerSettingsPageTurnScrollLabel => 'Scroll';

  @override
  String get readerSettingsScreenOrientationLabel =>
      'Screen orientation lock override';

  @override
  String get readerSettingsOrientationAutoTooltip => 'Auto-rotate';

  @override
  String get readerSettingsOrientationAutoLabel => 'Auto';

  @override
  String get readerSettingsOrientationLock0Tooltip => 'Lock 0°';

  @override
  String get readerSettingsOrientationLock90Tooltip => 'Lock 90°';

  @override
  String get readerSettingsOrientationLock180Tooltip => 'Lock 180°';

  @override
  String get readerSettingsOrientationLock270Tooltip => 'Lock 270°';

  @override
  String get readerSettingsSaveAsPresetButton =>
      'Save current settings as new preset';

  @override
  String get readerSettingsSavedPresetsLabel => 'Saved presets';

  @override
  String get readerSettingsCopyFromBookLabel => 'Copy from another book';

  @override
  String get readerSettingsCopyToCurrentBookButton => 'Copy to this book';

  @override
  String get readerSettingsCopyToOtherBooksButton => 'Copy to other books';

  @override
  String get readerSettingsResetPresetTitle => 'System default';

  @override
  String get readerSettingsResetPresetSubtitle =>
      'Remove this book\'s font size/weight/line height/paragraph spacing/letter spacing overrides and use the book\'s original style';

  @override
  String get readerSettingsApplyButton => 'Apply';

  @override
  String get readerSettingsPresetDefaultValue => 'Default';

  @override
  String get readerSettingsPresetSummaryAutoLabel => 'Auto';

  @override
  String readerSettingsPresetSummaryFormat(
    String fontSize,
    String lineHeight,
    String writingMode,
  ) {
    return 'Size $fontSize · Line height $lineHeight · $writingMode';
  }

  @override
  String get readerSettingsPresetEmptySlot => '(Empty)';

  @override
  String get readerSettingsApplyToOtherBooksTooltip => 'Apply to other books';

  @override
  String get readerSettingsDeletePresetTooltip => 'Delete';

  @override
  String get readerUnknownBookTitle => 'Unknown Book';

  @override
  String get readerSaveAsPresetUnavailableMessage =>
      'Can\'t save preset right now';

  @override
  String get readerSaveAsPresetFailedMessage => 'Failed to save new preset';

  @override
  String get readerOverwritePresetPickerTitle => 'Choose a preset to overwrite';

  @override
  String readerOverwritePresetOptionLabel(String name, String date) {
    return '$name (updated $date)';
  }

  @override
  String get readerConfirmOverwriteTitle => 'Confirm Overwrite';

  @override
  String readerOverwritePresetConfirmMessage(String name) {
    return 'This will overwrite preset “$name”. This can\'t be undone.';
  }

  @override
  String get readerConfirmApplyTitle => 'Confirm Apply';

  @override
  String readerApplyToOthersConfirmMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This will overwrite the layout settings of $count books. This can\'t be undone.',
      one:
          'This will overwrite the layout settings of 1 book. This can\'t be undone.',
    );
    return '$_temp0';
  }

  @override
  String get readerApplyPresetFailedMessage =>
      'Failed to apply layout settings';

  @override
  String get readerConfirmDeleteTitle => 'Confirm Delete';

  @override
  String readerDeletePresetConfirmMessage(String name) {
    return 'This will delete preset “$name”. This can\'t be undone.';
  }

  @override
  String get readerDeletePresetFailedMessage => 'Failed to delete preset';

  @override
  String get readerSearchUnavailableMessage =>
      'Search is temporarily unavailable';

  @override
  String get readerOpenBookTimeoutMessage =>
      'Timed out opening the book. The system WebView may be outdated, or the file may be corrupted.';

  @override
  String get readerCopiedToClipboardMessage => 'Copied to clipboard';

  @override
  String get readerTtsVoicePickerTitle => 'Voice';

  @override
  String get readerUnsupportedFormatMessage => 'Unsupported file format';

  @override
  String get readerFailedToLoadBookMessage => 'Failed to load book';

  @override
  String readerTtsSleepTimerOptionMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get readerTtsSleepTimerNoLimitLabel => 'No limit';

  @override
  String get settingsScaffoldTitle => 'Settings';

  @override
  String get settingsLibraryTooltip => 'Library';

  @override
  String get settingsSourceTooltip => 'Sources';

  @override
  String get settingsAppearanceSectionTitle => 'Appearance';

  @override
  String get settingsThemeLabel => 'Theme';

  @override
  String get settingsThemeLockedHint =>
      'This selects the theme to restore when E-Ink mode is turned off';

  @override
  String settingsThemeDotSemanticsLabel(String themeName) {
    return '$themeName theme';
  }

  @override
  String settingsThemeDotLockedSemanticsLabel(
    String themeName,
    String currentThemeName,
  ) {
    return '$themeName theme, locked. This selects the theme to restore when E-Ink mode is off. Currently selected: $currentThemeName';
  }

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeSepia => 'Sepia';

  @override
  String get settingsEinkModeLabel => 'E-Ink high contrast mode';

  @override
  String get settingsEinkModeSubtitle =>
      'Disables animations and gradients, showing pure black-and-white high contrast optimized for e-paper screens';

  @override
  String get settingsFontManagementLabel => 'Font Management';

  @override
  String get settingsReadingSectionTitle => 'Reading';

  @override
  String get settingsReadingDefaultsLabel => 'Reading Defaults';

  @override
  String get settingsNavZoneLabel => 'Navigation Zones';

  @override
  String get settingsTtsDefaultsLabel => 'Read-Aloud Voice & Speed';

  @override
  String get settingsFullTextSearchUnavailableLabel => 'Full-Text Search';

  @override
  String get settingsFullTextSearchUnavailableSubtitle =>
      'Full-text search isn\'t supported on this device';

  @override
  String get settingsFullTextSearchPdfLabel => 'PDF Full-Text Search';

  @override
  String get settingsFullTextSearchPdfSubtitle =>
      'Some scanned or image-based PDFs may not have searchable text';

  @override
  String get settingsFullTextSearchRebuildIndexTooltip => 'Rebuild index';

  @override
  String get settingsFullTextSearchFoliateLabel =>
      'Other Formats Full-Text Search';

  @override
  String get settingsFullTextSearchFoliateSubtitle =>
      'Background index building for EPUB／TXT／KF8 and similar formats';

  @override
  String get settingsSyncAccountSectionTitle => 'Sync & Accounts';

  @override
  String get settingsSyncLabel => 'Sync';

  @override
  String get settingsCloudAccountLabel => 'Linked Cloud Import Accounts';

  @override
  String get settingsAboutSectionTitle => 'About';

  @override
  String get settingsAboutLabel => 'About';

  @override
  String get settingsReaderConsoleLogLabel => 'Reader Console Log';

  @override
  String get settingsConsoleLogInterceptLabel => 'Console Log Interception';

  @override
  String get settingsConsoleLogInterceptSubtitle =>
      'When off, only error messages are kept for diagnostic reports';

  @override
  String get navZoneSettingsTitle => 'Navigation Zones';

  @override
  String get navZoneSettingsPageTurnModeLabel => 'Page Turn Method';

  @override
  String get navZoneSettingsSimpleModeLabel => 'Simple';

  @override
  String get navZoneSettingsCustomModeLabel => 'Custom';

  @override
  String get navZoneSettingsShowDebugOverlayLabel => 'Show zone guide overlay';

  @override
  String get navZoneSettingsSaveCustomButton => 'Save Custom Zone Settings';

  @override
  String get navZoneActionPreviousPage => 'Previous Page';

  @override
  String get navZoneActionNextPage => 'Next Page';

  @override
  String get navZoneActionMenu => 'Menu';

  @override
  String get navZoneActionNone => 'No Action';

  @override
  String get navZoneCustomValidationError =>
      'At least 1 cell must be set to \"Menu\", otherwise there will be no way to exit immersive mode';

  @override
  String get readingDefaultsTitle => 'Reading Defaults';

  @override
  String get readingDefaultsVolumeKeyLabel => 'Volume key page turn';

  @override
  String get readingDefaultsPageTurnModeSectionTitle => 'Page Turn Method';

  @override
  String get readingDefaultsPaginatedLabel => 'Tap to turn';

  @override
  String get readingDefaultsScrollLabel => 'Scroll to turn';

  @override
  String get readingDefaultsScreenOrientationSectionTitle =>
      'Screen Orientation';

  @override
  String get readingDefaultsOrientationAutoLabel => 'Auto-rotate';

  @override
  String get readingDefaultsOrientationLock0Label => 'Lock 0°';

  @override
  String get readingDefaultsOrientationLock90Label => 'Lock 90°';

  @override
  String get readingDefaultsOrientationLock180Label => 'Lock 180°';

  @override
  String get readingDefaultsOrientationLock270Label => 'Lock 270°';

  @override
  String get readingDefaultsTextConversionSectionTitle =>
      'Text Conversion Display';

  @override
  String get readingDefaultsTextConversionOriginalLabel => 'Original';

  @override
  String get readingDefaultsTextConversionTraditionalLabel =>
      'Convert to Traditional';

  @override
  String get readingDefaultsTextConversionSimplifiedLabel =>
      'Convert to Simplified';

  @override
  String get readingDefaultsFullscreenLabel => 'Fullscreen mode';

  @override
  String get readingDefaultsOpenLastBookLabel =>
      'Open the last read book on launch';

  @override
  String get readingDefaultsShowHeaderLabel => 'Show header';

  @override
  String get readingDefaultsShowFooterLabel => 'Show footer';

  @override
  String get ttsDefaultsTitle => 'Read-Aloud Voice & Speed';

  @override
  String get ttsDefaultsVoiceSectionTitle => 'Voice';

  @override
  String get ttsDefaultsVoiceUnavailableHint =>
      'No voice is installed or supported on this device';

  @override
  String get ttsDefaultsSpeedSectionTitle => 'Speed';

  @override
  String get syncSettingsTitle => 'Sync';

  @override
  String get syncSettingsSyncFailedMessage =>
      'Sync failed. Please check your network connection.';

  @override
  String get syncSettingsNeverSynced => 'Never synced';

  @override
  String syncSettingsLastSyncedAt(String formatted) {
    return 'Last synced: $formatted';
  }

  @override
  String get syncSettingsConnectionFailedMessage =>
      'Connection failed. Please check the server URL and your credentials.';

  @override
  String syncSettingsLoggedInAs(String email) {
    return 'Signed in as: $email';
  }

  @override
  String get syncSettingsManualSyncButton => 'Sync Now';

  @override
  String get syncSettingsLogoutButton => 'Sign Out';

  @override
  String get syncSettingsServerUrlLabel => 'Server URL';

  @override
  String get syncSettingsPasswordLabel => 'Password';

  @override
  String get syncSettingsShowPasswordTooltip => 'Show password';

  @override
  String get syncSettingsHidePasswordTooltip => 'Hide password';

  @override
  String get syncSettingsConnectButton => 'Connect / Sign In';

  @override
  String get cloudAccountSettingsTitle => 'Linked Cloud Import Accounts';

  @override
  String cloudAccountSettingsLinkedEmail(String email) {
    return 'Linked: $email';
  }

  @override
  String get cloudAccountSettingsUnlinkButton => 'Unlink';

  @override
  String get cloudAccountSettingsUnlinkedText => 'Not linked';

  @override
  String get cloudAccountSettingsLinkButton => 'Link';

  @override
  String get fontManagementTitle => 'Font Management';

  @override
  String get fontNameSourceHanSans => 'Source Han Sans';

  @override
  String get fontNameSourceHanSerif => 'Source Han Serif';

  @override
  String get fontManagementUploadTooltip => 'Upload font';

  @override
  String get fontManagementBuiltInSectionLabel => 'Built-in Fonts';

  @override
  String get fontManagementCustomSectionLabel => 'Custom Fonts';

  @override
  String get fontManagementNoCustomFontsHint => 'No custom fonts uploaded yet';

  @override
  String get fontManagementRenameTooltip => 'Rename';

  @override
  String get fontManagementDeleteTooltip => 'Delete';

  @override
  String get fontManagementRenameDialogTitle => 'Rename';

  @override
  String fontManagementDeleteConfirmTitle(String fontName) {
    return 'Delete \"$fontName\"?';
  }

  @override
  String fontManagementDeleteConfirmMessage(int usageCount) {
    String _temp0 = intl.Intl.pluralLogic(
      usageCount,
      locale: localeName,
      other:
          '$usageCount books currently use this font. They will fall back to the default font after deletion.',
      one:
          '1 book currently uses this font. It will fall back to the default font after deletion.',
    );
    return '$_temp0';
  }

  @override
  String get fontManagementStatusNotDownloaded => 'Not downloaded';

  @override
  String get fontManagementStatusDownloaded => 'Downloaded';

  @override
  String get fontManagementDownloadTooltip => 'Download';

  @override
  String get fontManagementCancelDownloadTooltip => 'Cancel download';

  @override
  String get fontManagementRetryTooltip => 'Retry';

  @override
  String get fontManagementDownloadableDeleteConfirmMessage =>
      'You can download it again at any time. Books that use this font will use the book\'s font or the system font until it\'s downloaded again.';

  @override
  String get fontDownloadErrorNetwork =>
      'Can\'t connect. Check your network and try again.';

  @override
  String fontDownloadErrorHttp(int statusCode) {
    return 'Server error ($statusCode). Try again later.';
  }

  @override
  String get fontDownloadErrorIntegrity =>
      'The file is incomplete or corrupted. Try again.';

  @override
  String get fontDownloadErrorStorage =>
      'Couldn\'t save the file. Check that there\'s enough storage space.';

  @override
  String fontManagementUploadBothMessage(int addedCount, int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      addedCount,
      locale: localeName,
      other: 'Added $addedCount fonts',
      one: 'Added 1 font',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount already exist and were skipped',
      one: '1 already exists and was skipped',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String fontManagementUploadAddedOnlyMessage(int addedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      addedCount,
      locale: localeName,
      other: 'Added $addedCount fonts',
      one: 'Added 1 font',
    );
    return '$_temp0';
  }

  @override
  String fontManagementUploadSkippedOnlyMessage(int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount fonts already exist and were skipped',
      one: '1 font already exists and was skipped',
    );
    return '$_temp0';
  }

  @override
  String get readerConsoleLogTitle => 'Reader Console Log';

  @override
  String get readerConsoleLogCopyAllTooltip => 'Copy all';

  @override
  String get readerConsoleLogClearTooltip => 'Clear';

  @override
  String get readerConsoleLogEmptyHint => 'No records yet';

  @override
  String get readerConsoleLogCopiedMessage => 'Copied all records to clipboard';

  @override
  String get aboutScreenTitle => 'About';

  @override
  String get aboutScreenVersionLabel => 'Version';

  @override
  String get aboutScreenBuildTimeLabel => 'Build Time';

  @override
  String get aboutScreenWebViewVersionLabel => 'System WebView Version';

  @override
  String get aboutScreenViewLicensesButton => 'Open Source Licenses';

  @override
  String get aboutScreenLoadingText => 'Loading...';

  @override
  String get aboutScreenFailedToLoadVersionMessage => 'Failed to get version';

  @override
  String get aboutScreenUnavailableText => 'Unavailable';

  @override
  String get remoteServerListTitle => 'Remote Library';

  @override
  String get remoteServerListAddTooltip => 'Add Server';

  @override
  String get remoteServerListEmptyState =>
      'No remote library servers added yet';

  @override
  String get remoteServerListEditTooltip => 'Edit';

  @override
  String get remoteServerListDeleteTooltip => 'Delete';

  @override
  String get remoteServerListDeleteConfirmTitle => 'Delete Server';

  @override
  String get remoteServerListDeleteConfirmButton => 'Delete';

  @override
  String remoteServerListDeleteConfirmMessage(String name) {
    return 'Delete server \"$name\"? This cannot be undone.';
  }

  @override
  String get remoteServerListDeleteBlockedTitle => 'Cannot Delete Server';

  @override
  String remoteServerListDeleteBlockedMessage(int count, String titles) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This server still has $count books that only have a cloud record and have not been downloaded:',
      one:
          'This server still has 1 book that only has a cloud record and has not been downloaded:',
    );
    return '$_temp0\n$titles\n\nPlease remove these books from your library, or download them again before deleting the server.';
  }

  @override
  String get remoteServerListDeleteBlockedConfirmButton => 'Got It';

  @override
  String get remoteServerListDeleteFailedMessage =>
      'Failed to delete server. Please try again later.';

  @override
  String get remoteServerFormTitleAdd => 'Add Server';

  @override
  String get remoteServerFormTitleEdit => 'Edit Server';

  @override
  String get remoteServerFormNameLabel => 'Server Name';

  @override
  String get remoteServerFormBaseUrlLabel => 'Server URL';

  @override
  String get remoteServerFormTypeOpds => 'Standard OPDS';

  @override
  String get remoteServerFormTypeCalibreServer =>
      'Native Calibre Content Server';

  @override
  String get remoteServerFormUsernameLabel =>
      'Username (leave blank for anonymous connection)';

  @override
  String get remoteServerFormPasswordLabelEditing =>
      'Password (leave blank to keep the existing password; clearing the username above also clears the password)';

  @override
  String get remoteServerFormPasswordLabel => 'Password';

  @override
  String get remoteServerFormPasswordShowTooltip => 'Show Password';

  @override
  String get remoteServerFormPasswordHideTooltip => 'Hide Password';

  @override
  String get remoteServerFormAllowInsecureLabel =>
      'Allow insecure connection (self-signed certificate / plain HTTP)';

  @override
  String get remoteServerFormValidationMissingFields =>
      'Please fill in the server name and URL';

  @override
  String get remoteServerFormValidationInvalidUrl =>
      'Please enter a valid server URL (must start with http:// or https://)';

  @override
  String get remoteServerFormSaveFailedMessage =>
      'Failed to save. Please try again later.';

  @override
  String get remoteServerFormTestSuccess => 'Connection successful';

  @override
  String get remoteServerFormTestFailed =>
      'Connection failed. Please check the URL/credentials/certificate settings.';

  @override
  String get remoteServerFormTestConnectionButton => 'Test Connection';

  @override
  String get remoteServerFormSaveButton => 'Save';

  @override
  String formatSelectionDialogTitle(String title) {
    return 'Select Format: $title';
  }

  @override
  String get formatSelectionDialogUnsupportedFormat => 'Unsupported format';

  @override
  String get cloudDuplicateDialogTitle => 'Duplicate Book';

  @override
  String get cloudDuplicateDialogConfirmButton => 'Create Anyway';

  @override
  String get remoteCatalogLoadFailedMessage =>
      'Failed to load. Please check your network connection or server settings.';

  @override
  String get remoteCatalogDownloadSelectedTooltip => 'Download Selected';

  @override
  String remoteCatalogDuplicateConfirmMessage(String title) {
    return '\"$title\" has already been imported before. Create a new copy anyway?';
  }

  @override
  String remoteCatalogQueuedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return 'Added $_temp0 to the download queue. Check progress on the \"Sources\" screen.';
  }

  @override
  String get remoteCatalogEinkPrevPageButton => 'Previous Page';

  @override
  String get remoteCatalogEinkNextPageButton => 'Next Page';

  @override
  String get remoteCatalogLoadMoreButton => 'Load More';

  @override
  String get remoteCatalogDuplicateDialogTitle => 'Duplicate Book';

  @override
  String get remoteCatalogDuplicateDialogConfirmButton => 'Create Anyway';

  @override
  String get wifiTransferLeaveConfirmTitle => 'Files are still transferring';

  @override
  String get wifiTransferLeaveConfirmMessage =>
      'Leaving will interrupt the connection. Are you sure you want to leave?';

  @override
  String get wifiTransferLeaveConfirmButton => 'Leave Anyway';

  @override
  String get wifiTransferTitle => 'WiFi Book Transfer';

  @override
  String get wifiTransferInstructionText =>
      'On the same WiFi network, open the following URL in a browser:';

  @override
  String wifiTransferActiveCountText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Transferring ($count files)…',
      one: 'Transferring (1 file)…',
    );
    return '$_temp0';
  }

  @override
  String get wifiTransferUnavailableText =>
      'Please connect to WiFi or turn on your mobile hotspot';

  @override
  String get wifiTransferManualOverrideButton =>
      'I\'m sure I\'m using a mobile hotspot';

  @override
  String get wifiTransferNoInterfacesText =>
      'No available network interfaces found';

  @override
  String get downloadQueueTitle => 'Download Queue';

  @override
  String get downloadQueueCancelTooltip => 'Cancel';

  @override
  String get downloadQueueRetryTooltip => 'Retry';

  @override
  String get downloadQueueDismissTooltip => 'Remove from List';

  @override
  String get downloadQueueStatusPending => 'Pending';

  @override
  String get downloadQueueStatusDownloading => 'Downloading';

  @override
  String get downloadQueueStatusCheckingDuplicate => 'Checking';

  @override
  String get downloadQueueStatusDone => 'Done';

  @override
  String get downloadQueueStatusDuplicateSkipped => 'Duplicate Skipped';

  @override
  String get downloadQueueStatusFailed => 'Failed';

  @override
  String get downloadQueueStatusCancelled => 'Cancelled';

  @override
  String downloadQueueDuplicateConfirmMessage(String name) {
    return 'Detected that \"$name\" has the same content as an existing book on this device. Create a new copy anyway?';
  }

  @override
  String get sourcesHomeTitle => 'Sources';

  @override
  String get sourcesHomeLibraryTooltip => 'Library';

  @override
  String get sourcesHomeSettingsTooltip => 'Settings';

  @override
  String get sourcesHomeLocalSection => 'Local';

  @override
  String get sourcesHomePickFilesTitle => 'Choose Files (multiple selection)';

  @override
  String get sourcesHomePickFolderTitle => 'Choose Folder';

  @override
  String get sourcesHomeWifiTransferTile => 'WiFi Book Transfer';

  @override
  String get sourcesHomeConnectedServicesSection => 'Connected Services';

  @override
  String get sourcesHomeCloudNotLinkedSubtitle =>
      'Not linked yet. Please link your account in Settings.';

  @override
  String get sourcesHomeRemoteLibraryTitle => 'Remote Library (OPDS)';

  @override
  String get sourcesHomeRemoteLibraryNotConfiguredSubtitle =>
      'No remote library server configured yet';

  @override
  String get libraryImportFolderDialogTitle => 'Import Folder';

  @override
  String get libraryImportFolderAutoGroupLabel =>
      'Automatically create category by folder name';

  @override
  String get libraryImportFolderConfirmButton => 'Import';

  @override
  String libraryImportResultBothMessage(int importedCount, int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      importedCount,
      locale: localeName,
      other: 'Imported $importedCount books',
      one: 'Imported 1 book',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount already exist and were skipped',
      one: '1 already exists and was skipped',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String libraryImportResultImportedOnlyMessage(int importedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      importedCount,
      locale: localeName,
      other: 'Imported $importedCount books',
      one: 'Imported 1 book',
    );
    return '$_temp0';
  }

  @override
  String libraryImportResultSkippedOnlyMessage(int skippedCount) {
    String _temp0 = intl.Intl.pluralLogic(
      skippedCount,
      locale: localeName,
      other: '$skippedCount already exist and were skipped',
      one: '1 already exists and was skipped',
    );
    return '$_temp0';
  }

  @override
  String get layoutPresetBookPickerTitleMulti =>
      'Select Books (multiple selection)';

  @override
  String get layoutPresetBookPickerTitleSingle => 'Select Book';

  @override
  String get layoutPresetBookPickerSearchHint => 'Search by title or author';

  @override
  String get layoutPresetBookPickerEmptyBooks =>
      'No reflowable EPUB books available to select';

  @override
  String get layoutPresetBookPickerNoMatch => 'No matching books found';

  @override
  String get layoutPresetNameDialogTitle => 'Name the Preset';

  @override
  String get layoutPresetNameDialogEmptyError => 'Name cannot be empty';

  @override
  String get layoutPresetNameDialogSaveButton => 'Save';

  @override
  String markdownExportTitle(String bookTitle) {
    return '# Reading Notes: $bookTitle';
  }

  @override
  String markdownExportAuthorLabel(String author) {
    return '*   **Author**: $author';
  }

  @override
  String get markdownExportUnknownAuthor => 'Unknown Author';

  @override
  String markdownExportProgressLabel(int percent) {
    return '*   **Reading Progress**: $percent%';
  }

  @override
  String markdownExportTimeLabel(String time) {
    return '*   **Export Time**: $time';
  }

  @override
  String markdownExportBookmarksSection(int count) {
    return '## 🔖 Bookmarks ($count)';
  }

  @override
  String get markdownExportNoBookmarks => '*(No bookmarks yet)*';

  @override
  String markdownExportAnnotationsSection(int count) {
    return '## ✏️ Highlights & Notes ($count)';
  }

  @override
  String get markdownExportNoAnnotations => '*(No highlights or notes yet)*';

  @override
  String markdownExportAnnotationHeading(String label, String position) {
    return '### 📌 $label (Position: $position)';
  }

  @override
  String bookmarkDefaultNamePdfPage(int page) {
    return 'Page $page';
  }

  @override
  String bookmarkDefaultNamePercent(int percent) {
    return 'At $percent%';
  }

  @override
  String get bookmarkDefaultNameFallback => 'Bookmark';

  @override
  String get ttsNotificationChannelName => 'Reading aloud';

  @override
  String get ttsVoiceSystemDefault => 'System default voice';

  @override
  String get remoteCatalogUnnamedCategory => 'Untitled category';

  @override
  String get remoteCatalogUnknownBookTitle => 'Unknown title';

  @override
  String get wifiPageTitle => 'elinkBook WiFi Transfer';

  @override
  String get wifiPageUploadHeading => 'Upload books';

  @override
  String get wifiPageDropzoneText => 'Drag and drop files here, or';

  @override
  String get wifiPageChooseFile => 'choose files';

  @override
  String get wifiPageDownloadHeading => 'Download books';

  @override
  String get wifiPageSearchPlaceholder => 'Search titles…';

  @override
  String get wifiPageSelectPage => 'Select this page';

  @override
  String get wifiPageClearSelection => 'Clear selection';

  @override
  String wifiPageSelectedCount(String count) {
    return 'Selected: $count';
  }

  @override
  String get wifiPageLoading => 'Loading…';

  @override
  String get wifiPagePrevPage => 'Previous';

  @override
  String get wifiPageNextPage => 'Next';

  @override
  String wifiPagePageInfo(String page, String total) {
    return 'Page $page / $total';
  }

  @override
  String get wifiPageDownloadSelected => 'Download selected books';

  @override
  String get wifiPageNoBooks => 'No books available for download';

  @override
  String get wifiPageNoMatch => 'No matching books';

  @override
  String get wifiPageLoadFailed => 'Unable to load the book list';

  @override
  String wifiPageTotalBooks(String count) {
    return 'Total books: $count';
  }

  @override
  String wifiPageMatchStats(String matched, String total) {
    return 'Matches: $matched / $total';
  }

  @override
  String get wifiPageSelectAtLeastOne => 'Select at least one book';

  @override
  String get wifiPageDownloading => 'Downloading…';

  @override
  String wifiPageDownloadTriggered(String count) {
    return 'All downloads started (total: $count)';
  }

  @override
  String get wifiPageOutcomeImported => 'Imported';

  @override
  String get wifiPageOutcomeDuplicateSkipped => 'Already exists, skipped';

  @override
  String get wifiPageOutcomeUnsupportedFormat => 'Unsupported format';

  @override
  String get wifiPageOutcomeFailed => 'Import failed';

  @override
  String wifiPageUploadResultLine(String name, String outcome) {
    return '$name: $outcome';
  }

  @override
  String get wifiPageUnknownFileName => '(unknown file name)';

  @override
  String get wifiPageUploadPreparing => 'Preparing upload…';

  @override
  String get wifiPageUploading => 'Uploading…';

  @override
  String wifiPageUploadingPercent(String percent) {
    return 'Uploading… ($percent%)';
  }

  @override
  String get wifiPageUploadProcessing =>
      'Upload complete. The phone is processing and importing, please wait…';

  @override
  String get wifiPageUnknownSize => 'unknown';

  @override
  String wifiPageUploadFailedServer(String status) {
    return 'Upload failed: server error ($status)';
  }

  @override
  String get wifiPageUploadFailedParse =>
      'Upload failed: unable to parse the server response';

  @override
  String get wifiPageUploadFailedNetwork => 'Upload failed: network error';

  @override
  String get wifiPageUploadAborted => 'Upload aborted';

  @override
  String get wifiPageUploadTimeout => 'Upload timed out';
}
