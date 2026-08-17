import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';
import 'package:elinkbook/remote/remote_server_repository.dart';

/// 供 widget test 使用的記憶體內 [RemoteServerRepository] 假實作
/// （比照 `FakeLibraryRepository` 既有模式）。[blockedDeletions] 供測試
/// 預先設定「刪除這個站點 id 時該回傳哪些擋下的書籍」，空清單或未設定
/// 代表允許刪除。
class FakeRemoteServerRepository implements RemoteServerRepository {
  FakeRemoteServerRepository({
    List<RemoteServerProfile> initialServers = const [],
    this.blockedDeletions = const {},
  }) : _servers = List.of(initialServers);

  final List<RemoteServerProfile> _servers;
  final Map<String, List<Book>> blockedDeletions;
  final Map<String, String> _passwords = {};

  final List<String> deleteServerCalls = [];

  @override
  Future<List<RemoteServerProfile>> listServers() async => List.of(_servers);

  @override
  Future<RemoteServerProfile> addServer(RemoteServerProfile profile, {String? password}) async {
    _servers.add(profile);
    if (password != null) {
      _passwords[profile.id] = password;
    }
    return profile;
  }

  @override
  Future<void> updateServer(RemoteServerProfile profile, {String? password}) async {
    final index = _servers.indexWhere((s) => s.id == profile.id);
    if (index != -1) _servers[index] = profile;
    if (password != null) {
      _passwords[profile.id] = password;
    } else {
      _passwords.remove(profile.id);
    }
  }

  @override
  Future<void> deleteServer(String serverId) async {
    deleteServerCalls.add(serverId);
    final blocking = blockedDeletions[serverId];
    if (blocking != null && blocking.isNotEmpty) {
      throw RemoteServerDeletionBlockedException(blocking);
    }
    _servers.removeWhere((s) => s.id == serverId);
    _passwords.remove(serverId);
  }

  @override
  Future<String?> loadPassword(String serverId) async => _passwords[serverId];
}
