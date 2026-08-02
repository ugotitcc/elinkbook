/// 使用者上傳的自訂字型（epic-14-system-settings FR-35），對應
/// `custom_fonts` 表的一列（見 docs/epics/epic-14-system-settings/spec.md
/// 「字型管理模組」）。字型檔案本身不落地複本（ADR 0021），[fontUri] 存
/// `content://` URI。
class CustomFont {
  /// SQLite 自動指派的 rowid，新增前（尚未寫入資料庫）為 null。
  final int? id;
  final String displayName;
  final String familyName;
  final String fontUri;

  const CustomFont({
    this.id,
    required this.displayName,
    required this.familyName,
    required this.fontUri,
  });

  /// 供 [CustomFontsRepository.insert] 使用；刻意不含 `id`——新增一律交由
  /// SQLite `AUTOINCREMENT` 指派。
  Map<String, Object?> toMap() {
    return {
      'display_name': displayName,
      'family_name': familyName,
      'font_uri': fontUri,
    };
  }

  factory CustomFont.fromMap(Map<String, Object?> map) {
    return CustomFont(
      id: map['id'] as int?,
      displayName: map['display_name'] as String,
      familyName: map['family_name'] as String,
      fontUri: map['font_uri'] as String,
    );
  }

  CustomFont copyWith({String? displayName}) {
    return CustomFont(
      id: id,
      displayName: displayName ?? this.displayName,
      familyName: familyName,
      fontUri: fontUri,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CustomFont &&
      other.id == id &&
      other.displayName == displayName &&
      other.familyName == familyName &&
      other.fontUri == fontUri;

  @override
  int get hashCode => Object.hash(id, displayName, familyName, fontUri);

  @override
  String toString() =>
      'CustomFont(id: $id, displayName: $displayName, familyName: $familyName, fontUri: $fontUri)';
}
