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
}
