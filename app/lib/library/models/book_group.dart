import '../../l10n/app_localizations.dart';

/// 書籍分類群組（FR-33）。[uncategorized]（「未分類」）為系統保留群組，
/// 不可重新命名或刪除——書籍未歸類、或原群組被刪除時皆歸入此群組。
class BookGroup {
  static const String uncategorized = '未分類';

  final String name;

  const BookGroup(this.name);

  Map<String, Object?> toMap() => {'name': name};

  factory BookGroup.fromMap(Map<String, Object?> map) =>
      BookGroup(map['name'] as String);
}

/// 表現層顯示名稱轉換：系統保留分類（[BookGroup.uncategorized]）依目前介面
/// 語言轉譯；使用者自訂分類原樣顯示，不經過此轉譯（epic-45-interface-i18n
/// Issue 2）。獨立頂層函式而非只做成 [BookGroup] 擴充方法——多處畫面（例如
/// `cloud_browser_screen.dart` 的 `_selectedGroupName`）是以裸 `String`
/// 持有群組名稱，並非都經手 [BookGroup] 物件，需要能直接對字串呼叫。
String localizeGroupName(String name, AppLocalizations l10n) =>
    name == BookGroup.uncategorized ? l10n.groupUncategorized : name;

extension BookGroupL10n on BookGroup {
  /// 轉發至 [localizeGroupName]，供已持有 [BookGroup] 物件的呼叫端使用。
  String displayName(AppLocalizations l10n) => localizeGroupName(name, l10n);
}

/// elinkBook 支援語言是已知的封閉集合（正體中文／簡體中文／英文三種），
/// 保留名稱集合本身也是固定已知的——同時防禦所有支援語言的保留名稱（不限
/// 當前介面語言），英文不分大小寫。純函式、刻意公開（非底線開頭）且不需要
/// [AppLocalizations] 參數，供 `library_group_management_dialog.dart`
/// 等呼叫端在新增/重新命名分類前檢查，也供本身的純邏輯單元測試直接呼叫
/// （`plan-issue-2.md` 對 `spec.md` §5.2 的刻意偏離：原設計為
/// `library_group_management_dialog.dart` 內的私有函式 `_isReservedGroupName()`，
/// 因 Dart privacy 以檔案為界線、私有頂層函式無法被獨立測試檔呼叫，改為
/// 本檔案的公開頂層函式，`issues.md` 本身也以「或等效抽出的頂層純函式」
/// 預留了這個彈性）。
bool isReservedGroupName(String name) {
  const reserved = {'未分類', '未分类', 'uncategorized'};
  return reserved.contains(name.trim().toLowerCase());
}
