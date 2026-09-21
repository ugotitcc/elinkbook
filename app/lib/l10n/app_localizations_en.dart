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
}
