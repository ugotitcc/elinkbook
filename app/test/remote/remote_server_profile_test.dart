import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/remote/remote_server_profile.dart';

void main() {
  RemoteServerProfile _profile({String? username, DateTime? lastAccessedAt}) {
    return RemoteServerProfile(
      id: 'srv1',
      name: '家用 NAS',
      baseUrl: 'http://192.168.1.100:8080/opds',
      type: RemoteServerType.opds,
      username: username,
      allowInsecure: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      lastAccessedAt: lastAccessedAt,
    );
  }

  test('toMap()/fromMap() 往返保留全部欄位', () {
    final profile = _profile(
      username: 'admin',
      lastAccessedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    final restored = RemoteServerProfile.fromMap(profile.toMap());
    expect(restored, profile);
  });

  test('username／lastAccessedAt 皆為 null 時（匿名連線、尚未存取過）toMap()/fromMap() 往返正確', () {
    final profile = _profile();
    final restored = RemoteServerProfile.fromMap(profile.toMap());
    expect(restored.username, isNull);
    expect(restored.lastAccessedAt, isNull);
    expect(restored, profile);
  });

  test('三種 RemoteServerType 皆能正確往返', () {
    for (final type in RemoteServerType.values) {
      final profile = RemoteServerProfile(
        id: 'srv1',
        name: '測試',
        baseUrl: 'http://example.com/opds',
        type: type,
        allowInsecure: false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(RemoteServerProfile.fromMap(profile.toMap()).type, type);
    }
  });

  test('allowInsecure=true 時 toMap()/fromMap() 往返正確', () {
    final profile = RemoteServerProfile(
      id: 'srv1',
      name: '自簽憑證站點',
      baseUrl: 'https://192.168.1.100:8443/opds',
      type: RemoteServerType.calibreServer,
      allowInsecure: true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    expect(RemoteServerProfile.fromMap(profile.toMap()).allowInsecure, true);
  });
}
