import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../library/library_repository.dart';
import 'remote_server_profile.dart';
import 'remote_server_repository.dart';

/// [RemoteServerRepository] 的 SQLite＋`flutter_secure_storage` 實作。
/// 與 `SqliteLibraryRepository` 共用同一個 [Database] 連線（比照
/// `LayoutPresetRepository`／`BookReaderPrefsRepository` 既有模式，
/// `main.dart` 建構時注入）。**刻意不直接查詢 `books` 表**——
/// `LibraryRepository` 是該表的唯一存取入口（見
/// `library_repository.dart` 類別文件），[deleteServer] 的刪除防護透過
/// 注入的 [LibraryRepository] 查詢。
class SqliteRemoteServerRepository implements RemoteServerRepository {
  SqliteRemoteServerRepository({
    required Database database,
    required LibraryRepository libraryRepository,
    FlutterSecureStorage? secureStorage,
  })  : _db = database,
        _libraryRepository = libraryRepository,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final Database _db;
  final LibraryRepository _libraryRepository;
  final FlutterSecureStorage _secureStorage;

  static String _passwordKey(String serverId) => 'remote_server_password_$serverId';

  @override
  Future<List<RemoteServerProfile>> listServers() async {
    final rows = await _db.query('remote_servers', orderBy: 'created_at ASC');
    return rows.map(RemoteServerProfile.fromMap).toList();
  }

  @override
  Future<RemoteServerProfile> addServer(RemoteServerProfile profile, {String? password}) async {
    await _db.insert('remote_servers', profile.toMap());
    await _writePassword(profile.id, password);
    return profile;
  }

  @override
  Future<void> updateServer(RemoteServerProfile profile, {String? password}) async {
    await _db.update(
      'remote_servers',
      profile.toMap(),
      where: 'id = ?',
      whereArgs: [profile.id],
    );
    await _writePassword(profile.id, password);
  }

  Future<void> _writePassword(String serverId, String? password) async {
    if (password == null) {
      await _secureStorage.delete(key: _passwordKey(serverId));
    } else {
      await _secureStorage.write(key: _passwordKey(serverId), value: password);
    }
  }

  @override
  Future<String?> loadPassword(String serverId) async {
    // Keystore 損毀等已知環境因素讀取失敗時安全退回 null（視同匿名連線），
    // 比照 SyncAccountRepository 既有先例，不拋例外、不卡住畫面。
    try {
      return await _secureStorage.read(key: _passwordKey(serverId));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteServer(String serverId) async {
    final blocking =
        await _libraryRepository.listUndownloadedBooksForRemoteServer(serverId);
    if (blocking.isNotEmpty) {
      throw RemoteServerDeletionBlockedException(blocking);
    }
    await _db.delete('remote_servers', where: 'id = ?', whereArgs: [serverId]);
    await _secureStorage.delete(key: _passwordKey(serverId));
  }
}
