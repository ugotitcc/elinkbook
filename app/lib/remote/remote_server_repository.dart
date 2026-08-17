import '../library/models/book.dart';
import 'remote_server_profile.dart';

/// 遠端書庫站點的存取介面（epic-30-calibre-remote-library Issue 1，
/// spec.md「站點管理：RemoteServerRepository」）。密碼獨立於
/// `RemoteServerProfile` 之外管理（見 [addServer]/[updateServer] 文件），
/// 不落地明文於 SQLite。
abstract class RemoteServerRepository {
  Future<List<RemoteServerProfile>> listServers();

  /// [password] 為 `null` 代表匿名連線（不使用密碼）。
  Future<RemoteServerProfile> addServer(RemoteServerProfile profile, {String? password});

  /// [password] 語意與 [addServer] 對稱：傳 `null` 清空既有密碼（退回
  /// 匿名），傳非 `null` 字串覆蓋既有密碼。沒有「留空＝不變更」這種
  /// 第三種狀態（YAGNI）。
  Future<void> updateServer(RemoteServerProfile profile, {String? password});

  /// 若該站點仍有 [Book.isDownloaded] 為 `false`（僅雲端紀錄、無本機
  /// 檔案）的書籍，拋出 [RemoteServerDeletionBlockedException] 並保留
  /// 站點不刪除；成功刪除時，已下載完成的書籍不受影響（`remoteServerId`
  /// 由資料庫外鍵自動清為 `null`，見 epic-30 Issue 0）。
  Future<void> deleteServer(String serverId);

  Future<String?> loadPassword(String serverId);
}

/// [RemoteServerRepository.deleteServer] 偵測到該站點仍有僅雲端紀錄書籍
/// 時拋出，[blockingBooks] 供呼叫端（UI）顯示示警清單。
class RemoteServerDeletionBlockedException implements Exception {
  final List<Book> blockingBooks;
  const RemoteServerDeletionBlockedException(this.blockingBooks);

  @override
  String toString() =>
      'RemoteServerDeletionBlockedException: ${blockingBooks.length} 本書僅有雲端紀錄，無法刪除此站點';
}
