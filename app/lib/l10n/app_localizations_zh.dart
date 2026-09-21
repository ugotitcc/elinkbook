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
}
