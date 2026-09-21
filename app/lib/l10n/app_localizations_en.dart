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
  String get settingsLanguageZhTW => 'Traditional Chinese';

  @override
  String get settingsLanguageZhCN => 'Simplified Chinese';

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
}
