import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/search/foliate_content_indexer.dart';

Book _sampleBook({required String filePath}) {
  return Book(
    id: 'b1',
    title: 'Test Book',
    format: BookFileFormat.epub,
    filePath: filePath,
    source: BookSource.local,
    progress: 0.0,
    groupName: 'default',
    createTime: DateTime(2025, 1, 1),
    lastReadTime: DateTime(2025, 1, 1),
  );
}

void main() {
  group('buildIndexerUri', () {
    test('bookBaseUri 為 null 時，網址不含 bookBaseUrl 參數，其餘與現狀一致', () {
      final book = _sampleBook(filePath: '/storage/sample.epub');
      final uri = buildIndexerUri(book);

      expect(uri.scheme, 'https');
      expect(uri.host, 'appassets.androidplatform.net');
      expect(uri.path, '/assets/foliate/index.html');
      expect(uri.queryParameters['bookFileName'], 'current.epub');
      expect(uri.queryParameters['mode'], 'index');
      expect(uri.queryParameters.containsKey('bookBaseUrl'), isFalse);
    });

    test('bookBaseUri 非 null 時，網址包含 bookBaseUrl 參數且含權杖與結尾斜線', () {
      final book = _sampleBook(filePath: '/storage/sample.cbz');
      final baseUri = Uri.parse('http://127.0.0.1:49152/book/secure-token-123/');
      final uri = buildIndexerUri(book, bookBaseUri: baseUri);

      expect(uri.scheme, 'https');
      expect(uri.host, 'appassets.androidplatform.net');
      expect(uri.path, '/assets/foliate/index.html');
      expect(uri.queryParameters['bookFileName'], 'current.cbz');
      expect(uri.queryParameters['mode'], 'index');
      expect(uri.queryParameters['bookBaseUrl'], 'http://127.0.0.1:49152/book/secure-token-123/');
    });
  });
}
