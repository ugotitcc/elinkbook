/// Calibre／OPDS 遠端書庫站點型別（epic-30-calibre-remote-library
/// Issue 1，spec.md「站點管理：RemoteServerRepository」）。v1 三種類型
/// 目前無行為差異，`type` 純粹是使用者填寫時的分類標記／UI 顯示用途，
/// 為後續 Calibre 專屬 REST API 加強 Issue 預留擴充位（spec.md
/// 「Further Notes」）。
enum RemoteServerType { opds, calibreServer, calibreWeb }

/// 對應 `remote_servers` 表一列（epic-30-calibre-remote-library Issue 0
/// 已建表）。密碼**不**存放於本類別——獨立存 `flutter_secure_storage`，
/// 由 `RemoteServerRepository` 另外管理（見 spec.md「站點管理」）。
class RemoteServerProfile {
  final String id;
  final String name;
  final String baseUrl;
  final RemoteServerType type;

  /// `null` 代表匿名連線（不需要帳密）。
  final String? username;

  /// 是否允許自簽憑證／憑證錯誤（僅作用於單次連線物件，見 Global
  /// Constraints）。
  final bool allowInsecure;

  final DateTime createdAt;

  /// `null` 代表尚未成功瀏覽過這個站點（Issue 1 範圍內恆為 `null`，
  /// Issue 2 建構 `RemoteCatalogScreen` 時才會在瀏覽成功後更新）。
  final DateTime? lastAccessedAt;

  const RemoteServerProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.type,
    this.username,
    required this.allowInsecure,
    required this.createdAt,
    this.lastAccessedAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'base_url': baseUrl,
      'type': type.name,
      'username': username,
      'allow_insecure': allowInsecure ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_accessed_at': lastAccessedAt?.millisecondsSinceEpoch,
    };
  }

  factory RemoteServerProfile.fromMap(Map<String, Object?> map) {
    return RemoteServerProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      baseUrl: map['base_url'] as String,
      type: RemoteServerType.values.byName(map['type'] as String),
      username: map['username'] as String?,
      allowInsecure: (map['allow_insecure'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      lastAccessedAt: map['last_accessed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['last_accessed_at'] as int),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteServerProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          baseUrl == other.baseUrl &&
          type == other.type &&
          username == other.username &&
          allowInsecure == other.allowInsecure &&
          createdAt == other.createdAt &&
          lastAccessedAt == other.lastAccessedAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        baseUrl,
        type,
        username,
        allowInsecure,
        createdAt,
        lastAccessedAt,
      );
}
