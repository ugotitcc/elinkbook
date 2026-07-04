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
